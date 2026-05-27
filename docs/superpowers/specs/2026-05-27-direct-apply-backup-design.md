# Direct-Apply Backup Safety — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe

## Problem

`Apply-StyleDirect` (`tstyles.ps1:456-507`) — the function behind
`tstyles <name>` and `tstyles random` — overwrites
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_…\LocalState\settings.json`
with no backup of any kind. If the merge logic in
`Merge-StyleIntoSettings` ever produces a valid-JSON-but-WT-rejected
output (e.g. due to an upstream Windows Terminal schema change, a
malformed bundled `theme.json`, or a bug in our bg-state machine), the
user silently loses their `settings.json`. They first notice when WT
fails to load profiles correctly on its next launch; they have no easy
recovery path.

By contrast:

- **The picker** (`Invoke-TerminalStyle`, `tstyles.ps1:617+`) is byte-safe:
  it snapshots `$originalJson` in memory and writes it back on Esc, so
  any preview is reversible.
- **`apply.ps1`** writes a timestamped `settings.json.bak-<timestamp>`
  before any modification (`apply.ps1:205-207`).

`Apply-StyleDirect` is the only entry point with neither safety net,
which is also the one the user invokes most frequently (every
`tstyles <name>` from the shell).

## Goals

- A direct apply (`tstyles <name>` or `tstyles random`) is recoverable:
  the previous `settings.json` is preserved as `settings.json.bak`
  alongside it in the same directory.
- The backup file is a rolling single file — overwritten on each direct
  apply — so the LocalState directory doesn't fill up over time
  regardless of how often the user switches themes.
- Backup failure (read-only volume, AV interference, disk full) warns
  but does not block the user's primary action.
- The user can restore with a single `Copy-Item` (documented in the
  README), no new subcommand required.

## Non-goals

- A `tstyles restore` subcommand. One-line `Copy-Item` is sufficient
  and discoverable from the README note. Defer until the lack of it
  causes real friction.
- Multi-generation backups (`.bak.1`, `.bak.2`, …). YAGNI — the rolling
  single file covers the common case (one mistaken apply, undo it).
- Migrating `apply.ps1` from timestamped to rolling. Its timestamped
  audit trail serves a different use case (non-interactive scripted
  installs where keeping history matters).
- Adding backup safety to the picker. Already covered by in-memory
  revert on Esc.
- Post-merge JSON re-parse validation. Considered during brainstorming;
  rejected as defense-in-depth that doesn't address the actual failure
  mode (valid JSON but WT-rejected — re-parse passes such output).
- Pester test coverage. Defer with the throttle test (also deferred).
- Backup compression / size cap. `settings.json` is a few KB; not
  worth the code.

## Architecture

One `Copy-Item -LiteralPath … -Destination … -Force` inserted into
`Apply-StyleDirect` between the settings.json read and the merge.
Wrapped in `try/catch` to downgrade backup failures from "kills the
command" to "warns and proceeds." One paragraph in the README
documenting the restore path. No new files, no new subcommand, no
schema or signature changes.

## File-by-file changes

### `tstyles.ps1` — `Apply-StyleDirect` (lines 456-507)

Insert a backup block immediately after the existing read of
`$originalJson` (currently line 482) and before the call to
`Merge-StyleIntoSettings` (currently line 491). Pseudocode:

```
function Apply-StyleDirect:
    # ... existing validation: style exists, settingsPath found ...

    originalJson = [System.IO.File]::ReadAllText(settingsPath, UTF8-no-BOM)
    settings     = originalJson | ConvertFrom-Json

    if (-not $Target) { ... existing auto-detect ... }
    if (-not $Target) { Write-Error ...; return }

    # NEW: rolling backup. Copy the on-disk file rather than write
    # originalJson back -- preserves exact bytes including any encoding
    # quirks WT itself wrote, and is one filesystem call.
    bakPath = settingsPath + '.bak'
    try:
        Copy-Item -LiteralPath settingsPath -Destination bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor DarkGray
    catch:
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow

    # ... existing merge + write + profile install + live reload ...
```

Implementation notes:

- **`Copy-Item` over `WriteAllText($originalJson)`.** `Copy-Item`
  preserves the exact on-disk bytes including any encoding quirks WT
  itself wrote (which could differ from what `[System.IO.File]::ReadAllText`
  decodes and re-encodes). One filesystem op, no round-trip.
- **`-Force`** is required so the second-and-subsequent applies overwrite
  the prior `.bak` rather than throw on existence.
- **`-ErrorAction Stop`** inside the try so non-terminating errors
  (e.g. permission denied) actually enter the catch block. Without
  `Stop`, `Copy-Item` failure could log via `$Error` but not enter the
  catch, leaving the user with a silently-missing backup and a green
  "applied" message.
- **DarkGray foreground** for the success message matches the project's
  convention for incidental info (see `apply.ps1:207`, `tstyles.ps1:413`).
  Yellow for warnings matches `tstyles.ps1:657` and elsewhere.
- **`$_` in the warning** is kept for debuggability. The user only sees
  this line if something is actually wrong; the exception text is the
  thing they'd report.

### `README.md`

Append one paragraph after the existing "Scriptable / non-interactive"
section (currently around line 287-299). The "Known limitations" or
"Backups" subsection feels heavier than needed — a single paragraph
inline is the lightest touch. Approximate wording:

```markdown
### Recovering from a bad apply

`tstyles <name>` and `tstyles random` write a rolling backup of
`settings.json` to `settings.json.bak` in the same directory before
each change. To restore the last-known-good settings:

\`\`\`powershell
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Copy-Item "$wt.bak" $wt -Force
\`\`\`

The picker (`tstyles` with no arg) doesn't write a backup — pressing
Esc reverts in-memory to the exact prior bytes. `apply.ps1` keeps a
timestamped `settings.json.bak-<timestamp>` per run (full audit trail).
```

(Backticks shown unescaped here for spec readability; the actual README
uses real code fences.)

### `apply.ps1`

No change. Its timestamped backup serves a different use case and
predates this work.

### Picker (`Invoke-TerminalStyle`)

No change. In-memory revert on Esc already covers it.

### Tests

No change. Defer Pester coverage to a future cohort with the
`Test-UpdateAvailable` test (which is also deferred per the
2026-05-27 throttle spec).

## Data flow

1. User runs `tstyles umbrella` (or `tstyles random`).
2. `Apply-StyleDirect` resolves the style, validates settings.json
   path, reads settings.json into `$originalJson`, and parses it.
3. Target profile auto-detect runs as today.
4. **NEW:** `Copy-Item settings.json settings.json.bak -Force` runs.
   - Success → gray "Backed up settings to: <path>" line prints.
   - Failure → yellow warning prints, function continues.
5. Existing merge + write + profile install + live reload runs as
   today.
6. If user later realizes the apply was bad, they restore via the
   one-line `Copy-Item` from the README.

## Error handling

| Failure | Behavior |
|---|---|
| `Copy-Item` succeeds, subsequent merge throws | Existing exception propagation. `.bak` is the prior good state, user can restore. Strictly better than today (today the merge throwing leaves `settings.json` untouched but a partial in-memory state, which is fine — the bug case is when merge produces *valid-but-wrong* output). |
| `Copy-Item` fails (read-only, AV, disk full) | Yellow warning with `$_`, proceed without backup. The user is now in the same state as today (no backup), but they were warned and can choose to abort. |
| Backup file already exists | Overwritten via `-Force`. Intentional — rolling semantics. |
| `Apply-StyleDirect` called when `settings.json` doesn't exist | Existing `Write-Error "Could not locate Windows Terminal settings.json."` fires before the backup block. No new error path. |
| User runs two `tstyles <name>` invocations in parallel from different shells | Last writer wins for both `settings.json` and `.bak`. Possible to lose a backup if writes interleave just so. Not worth a lock — `tstyles` is interactive and parallel invocations are vanishingly rare. |
| The `.bak` itself is what's broken (rare: AV corrupted it) | Restore fails silently or produces an invalid file. User has same recovery options as today (WT settings UI, manual edit). No regression. |

## Testing

Manual:

- **Basic backup creation.** Note `LastWriteTime` and a hash of
  `settings.json`. Run `tstyles umbrella`. Verify
  `settings.json.bak` exists in the same directory with the *prior*
  contents (compare hash). Verify gray "Backed up settings to:" line
  printed.
- **Rolling overwrite.** Run `tstyles eva`. Verify `.bak` now contains
  the post-umbrella state (not the original pre-umbrella state).
- **`tstyles random`.** Run several times. Verify only one `.bak`
  file exists, always reflecting the prior state.
- **Picker not affected.** Run `tstyles` (no arg), pick a theme, hit
  Enter. Confirm no `.bak` was created or modified by the picker.
- **Read-only fallback.** `attrib +R settings.json.bak` (if it
  exists), run `tstyles golden-forest`. Confirm yellow warning printed
  with the exception text, `settings.json` still got the new theme,
  and the function returned cleanly. `attrib -R settings.json.bak` to
  reset.
- **Restore round-trip.** Backup hash, apply two themes, restore via
  the README's one-liner, confirm `settings.json` hash matches the
  prior state.

No automated tests this round.

## Known limitations

- **Single-generation only.** If the user applies bad style A, then
  applies bad style B (without restoring between), the original good
  state is lost — `.bak` now reflects A, not the original. This is
  the deliberate trade-off for the rolling-single design. Mitigation:
  if you suspect a problem after the first apply, restore *before*
  applying anything else.
- **Parallel-invocation race.** Two shells running `tstyles <name>`
  simultaneously can produce a `.bak` that reflects neither's
  intended source state. Vanishingly rare in practice.
- **No automatic detection of "bad" state.** We back up on *every*
  direct apply, including ones the user intended. If they want a
  "restore from N applies ago" feature, this design doesn't give it
  to them. Out of scope.
- **Restore is manual.** No `tstyles restore` subcommand; the user
  must run the README's `Copy-Item` line. Acceptable for the
  estimated frequency (once a year per user, if ever).
