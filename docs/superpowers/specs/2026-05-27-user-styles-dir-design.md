# User-Styles Dir Survives Updates — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Target version:** `0.2.1` (patch — additive, no behavior change for existing users)
**Builds on:** [Sub-project C: PSGallery migration UX](2026-05-27-psgallery-migration-design.md)

## Problem

The README's "Adding your own style" section (post-0.2.0) admits:

> **Custom styles don't survive `tstyles update` on either path** — the
> installer re-extracts (bootstrap) or installs into a fresh per-version
> dir (PSGallery), so user-added folders inside `styles/` aren't carried
> over.

This is a real gap. The `$ModuleRoot\styles\` directory is install-managed:

- **Bootstrap** rewrites `%LOCALAPPDATA%\TerminalStyles\` on every `iwr | iex` re-extract.
- **PSGallery** lands each version in a sibling dir (`~\Documents\PowerShell\Modules\TerminalStyles\<version>\`), so 0.2.0 → 0.2.1 leaves the 0.2.0 dir orphaned along with any user-added `styles\<custom>\` folders inside it.

The fix is to give users a separate directory at `$DataRoot\styles\<name>\` that the module reads from in addition to its bundled themes. `$DataRoot` is `%LOCALAPPDATA%\TerminalStyles\` regardless of install path (per sub-project C), so a user folder there survives any update mechanism.

## Goals

- Users can drop `<style-name>\` folders into `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` and `tstyles list`, the picker, and `tstyles <name>` pick them up alongside bundled themes.
- User-added styles survive both `tstyles update` paths (bootstrap re-install, `Update-PSResource`).
- When a user dir and a bundled dir have the same style name (e.g., both have `eva/`), **the user dir wins**. Use case: locally tweak a bundled theme's prompt/scheme without forking the repo.
- No breaking changes to consumers of `Invoke-TerminalStyle`, the `tstyles` alias, or any tested function signature.
- Existing 46 Pester tests continue to pass; add 1-3 new tests locking in the union + precedence behavior.
- README's "Adding your own style" section updated: the install dir is now ONE path (`%LOCALAPPDATA%\TerminalStyles\styles\<name>\`) regardless of install kind, and folders there survive updates.

## Non-goals

- **No UI distinction in the picker** between bundled and user styles. Could add a tag/swatch later; YAGNI for v0.2.1.
- **No `tstyles import-style <path>` subcommand** for copying a folder into the user dir. The manual `Copy-Item` is fine; auto-import is a future polish.
- **No "ghost" handling** of a user folder whose `scheme.json` is malformed. Existing behavior is "filter by Test-Path scheme.json" — same logic applies, malformed user style is silently skipped just like a malformed bundled one would be.
- **No migration of files from the old install location** for users who somehow already have custom styles in `$ModuleRoot\styles\<custom>\`. They've either lost them in the most recent update, or are still on a pre-update install. After upgrading to 0.2.1, the user can move folders to `$DataRoot\styles\` manually.
- **No automatic registration of a user style for "contribute back"** workflow. The README already documents the manual fork-and-PR path.
- **No version bump beyond 0.2.1.** This is a patch — purely additive, no behavior change for users who don't drop folders into the new dir.

## Architecture

Two refactors plus minimal call-site updates.

### Refactor 1 — `Get-AvailableStyles` unions both dirs (user-wins dedup)

Currently:

```powershell
function Get-AvailableStyles {
    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) { return @() }
    @(Get-ChildItem -LiteralPath $stylesDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'scheme.json')
    } | Sort-Object Name)
}
```

New:

```powershell
function Get-AvailableStyles {
    # Reads styles from two locations and merges them (user-wins dedup
    # by name). $DataRoot\styles\ is the user dir -- survives any
    # update path. $ModuleRoot\styles\ is bundled with the module.
    $userStylesDir    = Join-Path $script:TStylesDataRoot 'styles'
    $bundledStylesDir = Join-Path $script:TStylesModuleRoot 'styles'

    $user = if (Test-Path -LiteralPath $userStylesDir) {
        @(Get-ChildItem -LiteralPath $userStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $bundled = if (Test-Path -LiteralPath $bundledStylesDir) {
        @(Get-ChildItem -LiteralPath $bundledStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    # User-dir styles override bundled by name
    $userNames = $user.Name
    @($user) + @($bundled | Where-Object { $_.Name -notin $userNames }) | Sort-Object Name
}
```

### Refactor 2 — new `Get-StyleDir -StyleName <name>` helper

Currently several callers construct style paths directly:

```powershell
$styleDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"
```

This misses any user-dir style of the same name. New helper applies the same user-wins precedence:

```powershell
function Get-StyleDir {
    # Resolves a style name to its on-disk directory, checking the user
    # dir first ($DataRoot\styles\<name>\) then the bundled dir
    # ($ModuleRoot\styles\<name>\). Returns $null if neither has a
    # scheme.json for that name.
    param([Parameter(Mandatory)][string]$StyleName)

    $userDir = Join-Path $script:TStylesDataRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) { return $userDir }

    $bundledDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) { return $bundledDir }

    return $null
}
```

Module-private (not exported); inserted near `Get-AvailableStyles` for proximity.

### Call-site updates

Three direct path-construction sites get swapped for `Get-StyleDir`:

| Function | Current | New |
|---|---|---|
| `Show-CurrentStyle` (~line 404) | `$schemePath = Join-Path $script:TStylesModuleRoot "styles\$current\scheme.json"` | `$styleDir = Get-StyleDir -StyleName $current; $schemePath = Join-Path $styleDir 'scheme.json'` |
| `Apply-StyleDirect` (~line 468) | `$styleDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"; if (-not (Test-Path -LiteralPath (Join-Path $styleDir 'scheme.json'))) { Write-Error ... }` | `$styleDir = Get-StyleDir -StyleName $StyleName; if (-not $styleDir) { Write-Error ... }` |
| Picker setup (~line 630) — already uses `Get-AvailableStyles` (which now returns merged) | unchanged | unchanged |
| Tab completer (~line 1042) | `$stylesDir = Join-Path $script:TStylesRoot 'styles'; ... Get-ChildItem $stylesDir ...` | call `Get-AvailableStyles` and enumerate `.Name` directly |

(Tab completer refactor: replace the inline directory walk with `(Get-AvailableStyles).Name` — same end result, one source of truth.)

### What about `Get-CurrentStyleName`?

This function (line ~293) byte-compares `current-style.ps1` against each bundled style's `profile.ps1`. It already calls `Get-AvailableStyles` to iterate. After the refactor, `Get-AvailableStyles` returns user + bundled. A user style whose `profile.ps1` matches the active `current-style.ps1` would be reported by `Get-CurrentStyleName` — which is correct (the user IS using that user-customized theme).

### What about `Get-StyleBundledBackground`?

Takes `$StyleDir` as a parameter. The caller now resolves to either user or bundled dir. For a user-dir style, the function looks for a `background.<ext>` in the user folder first (good), then the per-style cache dir under `$DataRoot\cache\<name>\` (works the same), then lazy-fetches. The lazy-fetch URL pattern `gifs/<styleName>` won't match user-named styles (no such file on the gifs branch), but the negative-cache marker handles that gracefully — first attempt fails for every extension, marker gets written, subsequent runs skip the network entirely. Edge case but not broken.

## File-by-file changes

### `tstyles.ps1`

- **Get-AvailableStyles** rewritten as above.
- **Get-StyleDir** added (new function).
- **Show-CurrentStyle** updated to use `Get-StyleDir`.
- **Apply-StyleDirect** updated to use `Get-StyleDir`.
- **Tab completer** simplified to use `(Get-AvailableStyles).Name`.

Estimated diff: ~40 lines changed.

### `TerminalStyles.psd1`

- `ModuleVersion` `0.2.0` → `0.2.1`.
- `ReleaseNotes` updated: "User-added themes at `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` now survive any update path (bootstrap re-install, Update-PSResource). Same path regardless of install kind."

### `README.md` — `## Adding your own style` section

Replace the current text (which describes per-install-path locations + disclaims that custom styles don't survive updates) with simpler unified guidance:

```markdown
## Adding your own style

Drop a folder into `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` with:

\`\`\`
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── background.gif     # default background image (optional)
└── README.md          # description (optional)
\`\`\`

`tstyles` picks it up automatically on next module load — no
registration needed. The dir is the same regardless of install path
(bootstrap or PSGallery), and folders here **survive updates**: both
`tstyles update` (bootstrap re-install) and `Update-PSResource`
leave `%LOCALAPPDATA%\TerminalStyles\` untouched.

If you drop in a folder with the same name as a bundled theme (e.g.
`eva/`), your version wins — useful for tweaking a bundled theme's
prompt or palette without forking the repo.
```

(The existing "For contributing back" subsection stays as-is — that's about upstreaming via PR, separate concern.)

### Pester tests

One new test file: `tests/Get-StyleDir.Tests.ps1` with 3 tests:

1. **User dir wins on name collision.** Create user `<TestDrive>\styles\eva\scheme.json` and bundled `<TestDrive>\bundled\styles\eva\scheme.json` (use two different TestDrives or two subdirs to simulate). `Get-StyleDir -StyleName eva` returns the user dir.
2. **Falls back to bundled when user dir doesn't have the style.** Only bundled exists. Returns bundled.
3. **Returns `$null` when neither has the style.** Returns `$null`.

Optional: extend `tests/Get-SchemeSwatch.Tests.ps1` with a test that adds a user style and asserts `Get-AvailableStyles` includes it. Recommend including; small.

Existing tests should pass without modification (they set `$script:TStylesModuleRoot = $script:TStylesDataRoot = $TestDrive` so both dirs collapse to the same place — the union returns just one copy via dedup).

Total Pester after: 46 existing + 3-4 new = 49-50.

### `apply.ps1`

**No change.** Standalone script with its own (independent) `Get-AvailableStyles` implementation. Out of scope; could be updated in a future spec if dual-source support there matters.

### `install.ps1`

**No change.** The bootstrap installer's "preserve user customizations" logic only handles `current-style.ps1` and cached backgrounds (per the install.ps1 preservation block at line 180+). With user styles now living in a separate dir outside the install path, the installer naturally leaves them alone — same as it leaves `%LOCALAPPDATA%\TerminalStyles\cache\` alone today.

### `scripts/publish.ps1`

**No change.** Existing allowlist publishes bundled styles only (correct — `$DataRoot\styles\` is user data, never shipped).

## Data flow

### New user dropping a custom theme

1. User creates `%LOCALAPPDATA%\TerminalStyles\styles\my-theme\scheme.json` (and any other files).
2. Opens a new shell tab — module imports, `Get-AvailableStyles` enumerates user dir + bundled dir, finds `my-theme` in user dir.
3. `tstyles list` shows it alongside the 16 bundled themes.
4. `tstyles my-theme` applies it via `Apply-StyleDirect → Get-StyleDir` resolving to user dir.

### Updating with a custom theme already in place

1. User runs `tstyles update` (or `Update-PSResource -Name TerminalStyles`).
2. New module version installed; `$ModuleRoot` is new, `$DataRoot` unchanged.
3. `%LOCALAPPDATA%\TerminalStyles\styles\my-theme\` is untouched.
4. After update, `tstyles list` still shows `my-theme` plus updated bundled themes.

### Overriding a bundled theme

1. User copies `~\Documents\PowerShell\Modules\TerminalStyles\0.2.1\styles\eva\` to `%LOCALAPPDATA%\TerminalStyles\styles\eva\`.
2. Edits the user copy's `profile.ps1` or `scheme.json`.
3. Reloads module — `Get-AvailableStyles` returns the user `eva` (wins on name collision), bundled `eva` is hidden.
4. `tstyles eva` applies the user-customized version.
5. After update to `0.2.2`, bundled `eva` may have changed, but user copy still takes precedence. User can reconcile manually if desired.

## Error handling

| Failure | Behavior |
|---|---|
| `$DataRoot\styles\` doesn't exist | `Get-AvailableStyles` treats as empty user-side; returns just bundled. Standard `Test-Path` short-circuit. |
| `$DataRoot\styles\my-theme\` exists but has no `scheme.json` | `Where-Object Test-Path scheme.json` filters it out (existing behavior for bundled, applied to user dir too). Silently skipped, no error. |
| User dir style has identical name to bundled, user dir's `scheme.json` is malformed | `Apply-StyleDirect → Get-StyleDir` returns the user dir. Subsequent `ConvertFrom-Json` throws. Error is surfaced to the user (existing exception-propagation behavior). User can fix their JSON or delete the user folder to fall back to bundled. |
| User's `profile.ps1` references undefined commands | Same as today: dot-source error printed at theme apply time; previous theme's prompt remains. Not a 0.2.1-specific concern. |
| `Get-StyleDir` called with `$null` or empty `$StyleName` | `Mandatory` parameter catches null; empty string falls through (both Test-Path checks fail, returns `$null`). Caller checks for `$null` return. |
| Concurrent module imports during user-style add | No locking; user style appears in next session's `Get-AvailableStyles`. Race window is microseconds; no real-world impact. |

## Testing

Manual:

- **Drop a custom theme, verify it appears.** Create `%LOCALAPPDATA%\TerminalStyles\styles\test-theme\scheme.json` with a minimal valid scheme (`{"name":"test","background":"#000000","foreground":"#FFFFFF",...}`). Open a new shell. Run `tstyles list`. Confirm `test-theme` appears with a swatch.
- **Apply it.** `tstyles test-theme`. Confirm WT settings.json gets the new scheme.
- **Override-wins.** Copy `~\Documents\PowerShell\Modules\TerminalStyles\0.2.1\styles\eva\` to `%LOCALAPPDATA%\TerminalStyles\styles\eva\`. Edit the user copy's `scheme.json` (change `name` or `background`). Reload module. `tstyles eva`. WT picks up the user-customized scheme.
- **Survival across update.** With `test-theme` in place, run `tstyles update`. After upgrade, `tstyles list` still includes `test-theme`.

Automated:

- New `tests/Get-StyleDir.Tests.ps1` (3 tests): user-wins-on-collision, bundled fallback, null when missing.
- Optional extension to `tests/Get-SchemeSwatch.Tests.ps1` or a new `tests/Get-AvailableStyles.Tests.ps1`: assert that adding a user style increases the count by 1 (or by 0 if it dedupes a bundled).

CI runs the full suite as today; both new and old tests must pass.

## Known limitations

- **No UI hint for user vs. bundled** in `tstyles list` or the picker. A small tag (`(user)` next to the name) would help users see at a glance which styles are local overrides. Defer.
- **No version-aware drift detection.** If a user overrides `eva` and bundled `eva` ships a breaking change in 0.3.0, the user's override silently masks the update. Out of scope to detect; consistent with how every package manager handles user overrides.
- **Lazy-fetch of user-style backgrounds.** If a user creates `my-theme/` without bundling a `background.<ext>`, `Get-StyleBundledBackground` will try to fetch from `https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/my-theme.<ext>` and fail (no such file). Negative-cache marker handles this gracefully — first attempt fails, marker is written to `$DataRoot\cache\my-theme\.no-background`, subsequent calls skip the network. Cosmetic 4x HTTP timeout on first use only.
- **No `tstyles import` / `tstyles export` subcommands** for moving user styles between machines. YAGNI; users can copy the folder manually.
- **Custom user style with the same name as a future bundled style is hidden.** Acceptable per user-wins-on-collision design choice.
