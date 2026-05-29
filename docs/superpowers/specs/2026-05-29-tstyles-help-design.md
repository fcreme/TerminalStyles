# `tstyles help` — In-CLI Command Discovery (Design)

**Date:** 2026-05-29
**Status:** Approved (brainstorming)
**Target version:** TerminalStyles 0.4.0

## Goal

Give users a way to discover and understand `tstyles` commands from inside
the terminal. Today the only in-CLI discovery is tab completion (which you
must already know to try); everything else lives in the GitHub README. Worse,
an arg that is neither a known subcommand nor a style name silently falls
through to opening the picker against a (usually bogus) Windows Terminal
profile — a typo like `tstyles helpp` produces confusing behavior and no error.

Add a first-class help system:

- `tstyles help` — a compact overview of every command.
- `tstyles help <command>` — per-command detail (usage, keys, examples).
- An unrecognized arg prints an "unknown" message + the overview instead of
  silently opening the picker.
- A one-line discovery hint in the interactive picker.

## Non-goals (YAGNI)

- No `-h` / `--help` / `-?` flags (explicitly declined; `help` subcommand only).
- No `Get-Help`/comment-based-help integration (doesn't model subcommands or
  match the `tstyles help <command>` UX).
- No paging, no man-page generation, no localization.
- The help text is a quick reference, not a mirror of the README — the README
  remains the home for deep/edge documentation. `help` links to it.

## User-facing behavior

### `tstyles help` (overview)

```
tstyles — themed styles for Windows Terminal (v0.4.0)

USAGE
  tstyles [command] [args]

COMMANDS
  (no command)     Open the interactive picker
  <style>          Apply a style by name (umbrella, eva, ...)
  list             List all styles; * marks the active one
  current          Print the active style name
  random           Apply a random style
  tune [name]      Live-tune a style; save as your own
  register         Add the loader to your $PROFILE
  update           Update to the latest version
  uninstall        Remove the module (keeps your styles)
  help [command]   Show this help

EXAMPLES
  tstyles                 # pick interactively
  tstyles eva             # apply 'eva'
  tstyles tune eva        # tune + save your own

More: https://github.com/fcreme/TerminalStyles
```

### `tstyles help <command>` (per-command detail)

Renders the matching command's full descriptor — usage line, summary, optional
detail paragraph, optional KEYS block (e.g. `tune`), and EXAMPLES. Example for
`tstyles help tune`:

```
tstyles tune [name] — live theme tuning

  Opens an arrow-key editor for the active style (or [name]). Adjusts
  brightness, saturation, opacity, font face, and font size.

KEYS
  Up/Down      select a knob
  Left/Right   adjust it
  R            reset colors
  Enter        save (Overwrite / Save as)
  Esc          revert

EXAMPLES
  tstyles tune
  tstyles tune eva

Saved styles live in your user dir and show up in `tstyles list` + the picker.
```

An unknown topic (`tstyles help frobnicate`) prints
`No help topic 'frobnicate'.` followed by the list of valid topics.

### Unknown argument

`tstyles <arg>` where `<arg>` is neither a known subcommand nor an available
style name now prints:

```
Unknown command or style: '<arg>'
Run 'tstyles help' for the list of commands. To target a Windows Terminal
profile, use: tstyles -Target '<profile name>'
```

…and returns. The picker is **not** opened. This **drops the legacy
positional-profile fallback** (`tstyles "My Profile"`), which was undocumented
and is fully superseded by the `-Target` parameter.

### Picker hint

The interactive picker's header gains one dim/gray footer line:

```
Tip: tstyles help  ·  all commands
```

## Architecture

Data-driven, single source of truth. Two module-private functions added to
`tstyles.ps1` before the `# === Public command ===` marker.

### `Get-TerminalStyleHelpData`

Returns an ordered array of command descriptors. One entry per real
subcommand. Each descriptor:

| Field      | Type       | Purpose                                                        |
|------------|------------|----------------------------------------------------------------|
| `Name`     | string     | Dispatch token, e.g. `tune`. Also the `help <Name>` topic key. |
| `Usage`    | string     | Display form, e.g. `tune [name]`.                              |
| `Summary`  | string     | One-line description (overview COMMANDS column).               |
| `Detail`   | string[]   | Optional. Paragraph lines for `help <command>`.               |
| `Keys`     | string[]   | Optional. `KEYS` rows (e.g. `tune`), pre-formatted `label  desc`. |
| `Examples` | string[]   | Optional. Example invocations.                                 |

Entries: `list`, `current`, `random`, `tune`, `register`, `update`,
`uninstall`, `help`. The two arg-less modes — the picker and `tstyles <style>`
— are described in the overview's USAGE/COMMANDS preamble (hard-coded in the
renderer), not as `help`-able topics, since they have no subcommand token.

This is the single source of truth: the dispatch table and the help data are
kept in sync by a test (see Testing).

### `Show-TerminalStyleHelp [-Command <name>]`

- **No `-Command`:** render the overview — title line (with module version
  from the manifest/`$script` version constant if available, else omitted),
  `USAGE`, `COMMANDS` (Usage + Summary per descriptor, column-aligned),
  `EXAMPLES`, and the docs link. Light color to match the picker/tuner
  aesthetic: cyan title, gray section headers and hints, default body text.
- **`-Command <name>`:** look up the descriptor (case-insensitive). If found,
  render Usage + Summary + Detail + KEYS + Examples. If not found, print
  `No help topic '<name>'.` and the list of valid topics.

Rendering uses `Write-Host` (human-facing output, consistent with
`Show-StyleList` / `Show-CurrentStyle`).

### Dispatch wiring (`Invoke-TerminalStyle`)

1. Add a dispatch line (reusing the existing `$SubArg` Position=1 param that
   `tune` introduced — no new parameter):
   ```powershell
   if ($Arg -eq 'help') { Show-TerminalStyleHelp -Command $SubArg; return }
   ```
   Placed in the subcommand block (near `tune`).
2. Replace the unknown-arg fallback. Current code (after the style-name match
   fails):
   ```powershell
       # Backward compat: treat $Arg as a WT profile name for the picker.
       if (-not $Target) { $Target = $Arg }
   ```
   New behavior:
   ```powershell
       Write-Host "Unknown command or style: '$Arg'" -ForegroundColor Yellow
       Show-TerminalStyleHelp
       Write-Host "To target a Windows Terminal profile, use: tstyles -Target '<name>'" -ForegroundColor DarkGray
       return
   ```
   (Exact wording per the User-facing section; the point is: message + overview
   + `-Target` pointer, then `return` — no picker.)
3. Add `'help'` to the tab-completer `$subcommands` array.

### Picker hint

Add one `Write-Host` line to the picker's header block (where it currently
prints `Up/Down to preview, Enter to keep, Esc to cancel`), in the existing
dim color, reading `Tip: tstyles help  ·  all commands`.

## Error handling

- `tstyles help <unknown-topic>` → graceful not-found message + valid topics
  (never throws).
- Unknown top-level arg → message + overview (never throws, never opens a
  bogus picker).
- The renderer reads no files and has no failure modes beyond console output;
  the version line degrades gracefully (omitted) if a version value isn't
  readily available without disk I/O.

## Testing (Pester)

New file `tests/Show-TerminalStyleHelp.Tests.ps1` plus additions to the
dispatch test:

1. **Drift guard (key test):** every subcommand dispatched in
   `Invoke-TerminalStyle` has a matching `Get-TerminalStyleHelpData` entry. The
   set of help `Name`s must be a superset of the canonical dispatched subcommand
   tokens (`list`, `current`, `random`, `tune`, `register`, `update`,
   `uninstall`, `help`). The `ls` token is an alias of `list` and is **not** a
   separate help topic, so the test compares against the canonical set (it does
   not require an `ls` entry). Prevents help drifting from behavior.
2. Overview output (captured) contains every command name.
3. `Show-TerminalStyleHelp -Command tune` output contains tune-specific text
   (e.g. `brightness`, `Esc`).
4. `Show-TerminalStyleHelp -Command bogus` output contains the not-found
   message and lists valid topics.
5. Dispatch: `Invoke-TerminalStyle -Arg 'help'` invokes `Show-TerminalStyleHelp`
   (no `-Command`); `-Arg 'help' -SubArg 'tune'` invokes it with `Command =
   'tune'` (via mock).
6. Unknown arg: `Invoke-TerminalStyle -Arg 'definitely-not-real'` invokes
   `Show-TerminalStyleHelp` and does **not** enter the picker (mock
   `Show-TerminalStyleHelp` + assert the picker path / `Find-WTSettingsPath`
   is not reached).
7. Tab completion offers `help` (via `TabExpansion2`, mirroring the existing
   `tune` completer test).

All tests run headless (no WT, no interactive loop).

## Documentation & version

- `README.md`: add a `tstyles help [command]` row to the Subcommands listing.
- `TerminalStyles.psd1`: `ModuleVersion` 0.3.0 → 0.4.0; update `ReleaseNotes`.
- SemVer rationale: a new subcommand is a feature → minor bump, consistent with
  `docs/RELEASING.md` ("minor for new themes/features") and the `tune` release
  (0.2.2 → 0.3.0).

## Decisions / judgment calls

- **Drop the positional-profile fallback** rather than make the unknown-arg
  path profile-aware. It's undocumented and superseded by `-Target`; the
  simpler rule keeps dispatch predictable and avoids loading `settings.json`
  just to disambiguate a typo. (Mitigation: the unknown-arg message points at
  `-Target`.)
- **Help text is curated, not generated** from the dispatch table — the
  summaries/detail need human phrasing — but a test keeps the *set* of topics
  in sync with what's dispatched.
- **Version line** in the overview is best-effort: include it only if the
  version is available without extra disk I/O at call time; otherwise omit.
