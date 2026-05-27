# Installer UX Polish — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe

## Problem

The `iwr -useb …/install.ps1 | iex` flow currently produces output
that's correct but undersells the product. Current end-to-end:

```
TerminalStyles installer
------------------------
Downloading from https://github.com/fcreme/TerminalStyles/archive/refs/heads/main.zip ...
Extracting ...
Preserved your existing style selection.
Preserved 16 cached background image(s).
Files installed at: C:\Users\felip\AppData\Local\TerminalStyles

[PowerShell 7]
  Loader registered in: C:\Users\…\Microsoft.PowerShell_profile.ps1

[Windows PowerShell 5.1]
  Loader registered in: C:\Users\…\Microsoft.PowerShell_profile.ps1

Done!
  Registered for: PowerShell 7, Windows PowerShell 5.1
  1. Open a new tab in one of those shells (or run: . $PROFILE)
  2. Run:  tstyles
     -> Arrow keys to preview each style live, Enter to keep, Esc to cancel.
```

Two specific issues:

1. **Visual.** TerminalStyles is a visual-flair tool. The installer
   reads like generic CLI output — flat headers, no branding, the
   "Files installed at" line is misleadingly green (it's a fact, not a
   success), the long ZIP URL clutters the screen, and the final
   "Done!" panel buries the action under a numbered list.

2. **Functional.** The "Open a new tab" step is pessimistic. After
   `iwr | iex` finishes, `$PROFILE` was modified but the *current*
   shell hasn't re-sourced it, so `tstyles` isn't defined. The
   installer can just dot-source `tstyles.ps1` itself at the end —
   since `| iex` runs the installer in the current scope, dot-sourcing
   exposes `tstyles` in the same scope. Net result: the user types
   `tstyles` immediately in the same tab. Zero-friction first-run.

## Goals

- Replace the flat title with a small branded banner (wordmark +
  tagline) that matches the project's visual identity without
  competing with the themes themselves.
- Replace flat per-step `Write-Host` lines with a consistent checked
  step list (`→ Downloaded ✓`).
- Replace per-shell `[Label]` brackets with cleaner section headers
  that don't visually fight the rest of the output.
- Replace the "Done!" numbered list with a single bordered panel
  showing the one command to run (`tstyles`) and the 16 theme names.
- Drop the "open a new tab" caveat for the engine that ran the
  installer — dot-source `tstyles.ps1` so the user runs `tstyles` in
  the same tab.
- Mention the *other* engine briefly so a user with both installed
  knows it's wired up for the next tab they open.
- All changes happen in `install.ps1` only. The picker, `tstyles.ps1`,
  `apply.ps1`, and `README.md` stay untouched (apart from the README's
  install-step description, which becomes more accurate).

## Non-goals

- Auto-launch the picker after install (the "Polish + first-run
  preview" option from brainstorming). Rejected: surprise interactive
  takeover for users scripting installs, and the `tstyles` command is
  already one keystroke away.
- Auto-apply a default theme on first install. Same reasoning — opt-in
  is the safer default.
- Banner ASCII art (figlet-style block letters). Looks dated, takes
  too much vertical space, and competes with the theme banners (eva,
  umbrella, lain, etc.) which are the actual show. A clean wordmark
  with rules above/below is the right register.
- Emoji icons. Box-drawing chars (✓, →, ┌─┐) are font-safe in Cascadia
  Mono / Consolas / DejaVu. Emoji rendering across PowerShell hosts is
  inconsistent (Windows Terminal handles them, conhost doesn't).
- Spinner / progress bar during download. The current `$ProgressPreference
  = 'SilentlyContinue'` is deliberate (kills the IWR progress UI that
  added 25s+ on WinPS 5.1). Adding a custom spinner means re-rendering
  per-tick across two engines and a polyglot codepath; defer.
- Apply the same polish to `apply.ps1`'s output. Different use case
  (scriptable, non-interactive); separate spec if we want to.
- Changes to the execution-policy prompt (`Read-Host`-driven). Out of
  scope; that's a separate UX axis.
- Internationalization. Strings stay English.

## Architecture

Two layers of change in `install.ps1`:

1. **Output polish** — a handful of new `Write-Host` helpers
   (banner, step, panel) that the existing flow calls instead of bare
   `Write-Host`. No new dependencies; pure string composition with
   ANSI escapes.

2. **Same-tab handoff** — one new line near the end of the installer
   that dot-sources the freshly-installed `tstyles.ps1` into the
   current scope. Guarded by a quick `Test-Path` so a missing file
   (extremely unlikely at this point) doesn't crash the install.

## File-by-file changes

### `install.ps1` — output polish

Add three small helper functions near the top (after the `$loaderBody`
heredoc, before the existing `Write-Host "TerminalStyles installer"`):

```powershell
function Write-InstallBanner {
    # Cyan rule + wordmark + tagline + cyan rule. Wordmark is the
    # literal string "tstyles" in bold white; tagline in dim gray.
    $rule = '─' * 52
    Write-Host ''
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host '   tstyles' -ForegroundColor White -NoNewline
    Write-Host '  ·  Windows Terminal themes for pwsh' -ForegroundColor DarkGray
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host ''
}

function Write-InstallStep {
    param([Parameter(Mandatory)][string]$Message, [switch]$Check)
    $arrow = '→'
    $tick  = if ($Check) { ' ✓' } else { '' }
    Write-Host "  $arrow $Message$tick" -ForegroundColor White
}

function Write-InstallPanel {
    # Bordered "Ready" panel at the end. Shows the one command + a
    # comma-wrapped list of installed theme names.
    param([Parameter(Mandatory)][string[]]$ThemeNames, [string[]]$RegisteredEngines)
    $themeCount = $ThemeNames.Count
    $width = 56
    $top    = '┌─ Ready ' + ('─' * ($width - 9)) + '┐'
    $bottom = '└' + ('─' * $width) + '┘'

    Write-Host ''
    Write-Host "  $top" -ForegroundColor Green
    Write-Host '  │' -ForegroundColor Green -NoNewline
    Write-Host ('  ' + "$themeCount themes installed.").PadRight($width - 2) -NoNewline
    Write-Host '│' -ForegroundColor Green
    Write-Host '  │' -ForegroundColor Green -NoNewline
    Write-Host (''.PadRight($width)) -NoNewline
    Write-Host '│' -ForegroundColor Green
    Write-Host '  │' -ForegroundColor Green -NoNewline
    Write-Host '      ' -NoNewline
    Write-Host 'tstyles' -ForegroundColor Cyan -NoNewline
    Write-Host (''.PadRight($width - 13)) -NoNewline
    Write-Host '│' -ForegroundColor Green
    Write-Host '  │' -ForegroundColor Green -NoNewline
    Write-Host (''.PadRight($width)) -NoNewline
    Write-Host '│' -ForegroundColor Green

    # Theme names wrapped to fit inside the panel
    $line = '  '
    foreach ($name in $ThemeNames) {
        $candidate = if ($line -eq '  ') { "$line$name" } else { "$line · $name" }
        if ($candidate.Length -gt $width - 2) {
            Write-Host '  │' -ForegroundColor Green -NoNewline
            Write-Host $line.PadRight($width) -ForegroundColor DarkGray -NoNewline
            Write-Host '│' -ForegroundColor Green
            $line = "  $name"
        } else {
            $line = $candidate
        }
    }
    if ($line.Trim().Length -gt 0) {
        Write-Host '  │' -ForegroundColor Green -NoNewline
        Write-Host $line.PadRight($width) -ForegroundColor DarkGray -NoNewline
        Write-Host '│' -ForegroundColor Green
    }

    Write-Host "  $bottom" -ForegroundColor Green
    Write-Host ''

    # Note about the other engine if both were registered
    if ($RegisteredEngines.Count -gt 1) {
        $current = $PSVersionTable.PSEdition  # 'Core' for pwsh 7, 'Desktop' for WinPS 5.1
        $otherLabel = if ($current -eq 'Core') { 'Windows PowerShell 5.1' } else { 'PowerShell 7' }
        Write-Host "  Also wired up for $otherLabel — available in any new tab there." -ForegroundColor DarkGray
        Write-Host ''
    }
}
```

Replace the existing top-of-script banner block (currently lines 38-40):

```powershell
Write-Host ""
Write-Host "TerminalStyles installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
```

with:

```powershell
Write-InstallBanner
```

Replace per-step `Write-Host` calls with `Write-InstallStep`:

| Current line | Replacement |
|---|---|
| `Write-Host "Downloading from $zipUrl ..."` | `Write-InstallStep "Downloading"` (then `-Check` after success) |
| `Write-Host "Extracting ..."` | `Write-InstallStep "Extracting"` (then `-Check`) |
| `Write-Host "Preserved your existing style selection."` | `Write-InstallStep "Preserved your active style" -Check` |
| `Write-Host ("Preserved {0} cached background image(s)." -f ...)` | `Write-InstallStep "Preserved $count cached background(s)" -Check` |
| `Write-Host "Files installed at: $installDir" -ForegroundColor Green` | **Remove.** The bordered panel at the end already implies success; the install path is in the loader-registered line. |
| `Write-Host "[$($s.Label)]" -ForegroundColor Cyan` | **Remove the bracket header.** The `Loader registered in:` line below is self-describing once it's the only output. |
| `Write-Host "  Loader registered in: $ProfilePath" -ForegroundColor Green` | `Write-InstallStep "Registered loader: $Label" -Check` (drops the path — only relevant for debugging, and `Find-WTSettingsPath`-style failures already print a separate diagnostic). |
| Final `Write-Host "Done!"` + numbered list | `Write-InstallPanel -ThemeNames $themeNames -RegisteredEngines $registered` |

The `→ Downloading` / `→ Downloading ✓` pattern needs a small flow
change: print the in-progress line, run the action, then re-render the
line with the check. Pseudocode:

```powershell
Write-InstallStep "Downloading"
Invoke-WebRequest …
Write-InstallStep "Downloading" -Check       # overwrites with checked variant
```

Actually simpler: just print the un-checked line BEFORE the action and
the checked line AFTER (two lines total). Cosmetically acceptable and
easier to reason about than ANSI cursor-up tricks.

### `install.ps1` — same-tab handoff

Add at the very end of `install.ps1`, after the `Write-InstallPanel`
call and the final `Write-Host`:

```powershell
# --- Same-tab handoff ---
# Dot-source the freshly-installed tstyles.ps1 into the current scope
# so the user can type `tstyles` immediately without opening a new tab.
# `iwr | iex` runs this whole installer in the caller's scope, so a
# dot-source from here exposes Invoke-TerminalStyle to that scope too.
$installedLib = Join-Path $installDir 'tstyles.ps1'
if (Test-Path -LiteralPath $installedLib) {
    . $installedLib *> $null
}
```

The `*> $null` suppresses any startup output `tstyles.ps1` would print
(currently none — but defensive against future additions like a
load-time banner).

### `install.ps1` — gather theme names for the panel

Immediately before the `Write-InstallPanel` call, add:

```powershell
$themeNames = @(
    Get-ChildItem -LiteralPath (Join-Path $installDir 'styles') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
        Sort-Object Name |
        ForEach-Object Name
)
```

Then:

```powershell
Write-InstallPanel -ThemeNames $themeNames -RegisteredEngines $registered
```

### `README.md`

Two paragraphs touched:

1. The post-install instructions (currently around line 55 — "Then open
   a new pwsh or powershell tab (or run `. $PROFILE` to reload).") →
   change to mention the installer drops `tstyles` into the current
   tab. Approximate replacement: "After install you can run `tstyles`
   right away in the same tab. Other tabs (and the other PowerShell
   engine if both are installed) pick it up next time they start."
2. Nothing else.

### Not touched

- `apply.ps1` (different use case)
- `tstyles.ps1` (only sourced from install.ps1, no code change)
- The picker (`Invoke-TerminalStyle`)
- Tests (no test for installer output today; not adding one — `install.ps1`
  is hard to test hermetically because it shells out)

## Output mockup (after changes)

```
  ────────────────────────────────────────────────────
   tstyles  ·  Windows Terminal themes for pwsh
  ────────────────────────────────────────────────────

  → Downloading
  → Downloading ✓
  → Extracting
  → Extracting ✓
  → Preserved your active style ✓
  → Preserved 16 cached background(s) ✓
  → Registered loader: PowerShell 7 ✓
  → Registered loader: Windows PowerShell 5.1 ✓

  ┌─ Ready ───────────────────────────────────────────────┐
  │  16 themes installed.                                 │
  │                                                       │
  │      tstyles                                          │
  │                                                       │
  │  umbrella · eva · ex-machina · forest · garden-rain   │
  │  · gitbash · golden-forest · halo · kitty · lain ·    │
  │  marquee · neon-rain · rain · snowday · sober ·       │
  │  tombraider                                           │
  └───────────────────────────────────────────────────────┘

  Also wired up for Windows PowerShell 5.1 — available in any new tab there.

```

The user can immediately type `tstyles` in the same tab.

## Data flow

1. User runs `iwr -useb …/install.ps1 | iex` in pwsh (either edition).
2. Banner renders (cyan rule + wordmark + cyan rule).
3. Each install phase prints `→ Doing X` before, `→ Doing X ✓` after.
4. Loader registration prints `→ Registered loader: <engine> ✓` per
   detected engine.
5. Theme names are enumerated from `$installDir/styles/`.
6. "Ready" panel renders with theme list and the one command (`tstyles`).
7. If both engines were registered, the dim "Also wired up for <other>"
   note prints once.
8. `tstyles.ps1` is dot-sourced into the current scope.
9. User types `tstyles` — picker launches immediately.

## Error handling

| Failure | Behavior |
|---|---|
| Banner / panel write fails (vanishingly unlikely — just `Write-Host`) | Falls through; the rest of the install still runs. |
| Dot-source at the end fails (e.g. `tstyles.ps1` somehow missing) | `Test-Path` guard means we silently skip. User falls back to the "open a new tab" path. Loud error is wrong here — the install proper succeeded. |
| `Get-ChildItem` on `$installDir/styles/` returns nothing | `$themeNames` is empty; panel renders with "0 themes installed." This means something is very wrong upstream; the panel surfaces it. |
| Box-drawing characters render as `?` on a host that doesn't support them | UI is uglier but functional. We're explicit that this targets Windows Terminal (whose default fonts handle them). |
| User runs the installer from a non-pwsh host (e.g. cmd.exe via `pwsh -Command "iwr | iex"`) | The dot-source happens in the spawned `pwsh` process, not in cmd.exe. The current tab is cmd.exe, so the user has to open pwsh to use `tstyles` anyway. Same as today — no regression. |
| `$PSVersionTable.PSEdition` is not Core/Desktop (some bleeding-edge build) | The "Also wired up for <other>" line falls back to "the other engine." Cosmetic only. |

## Testing

Manual (no automated installer test in this repo):

- **Fresh install (pwsh 7):**
  - Delete `%LOCALAPPDATA%\TerminalStyles\` and unregister both
    `$PROFILE` loaders. Open a new pwsh 7 tab.
  - Run the one-liner. Verify: banner renders cleanly, step lines
    print in `→ X` / `→ X ✓` order, panel renders inside borders
    with all 16 themes wrapped readably.
  - Without opening a new tab, type `tstyles`. Picker launches.
- **Fresh install (WinPS 5.1):** same, from a `powershell.exe` tab.
  Confirm box-drawing chars render (Consolas / Cascadia Mono handle
  them; default Windows Terminal font is fine).
- **Reinstall over existing:** run the one-liner again. Verify the
  "Preserved your active style" and "Preserved N cached backgrounds"
  steps fire with ✓, the panel still renders correctly.
- **Single-engine machine:** mock by `Rename-Item powershell.exe`
  temporarily (or use a machine without WinPS 5.1). Confirm panel
  omits the "Also wired up for…" line.
- **Path with spaces:** `$installDir` is fixed at
  `%LOCALAPPDATA%\TerminalStyles\` so spaces aren't expected, but
  cross-check by skimming the step lines for path corruption.
- **Same-tab `tstyles` works:** after the new install, immediately
  `Get-Command tstyles` should print `Function Invoke-TerminalStyle`.
  Confirm.

No Pester for the installer. Adding installer tests is a bigger
question (hermeticity, network mocking) — defer.

## Known limitations

- **Same-tab handoff only works for the engine that ran the installer.**
  If you ran the one-liner in pwsh 7, opening a Windows PowerShell 5.1
  tab still requires the new-tab handshake (which the panel mentions
  with the dim "Also wired up for…" line). This is intrinsic to how
  `$PROFILE` works — there's no cross-process loader injection.
- **Box-drawing chars depend on the font.** Cascadia Mono (the default
  Windows Terminal font) renders them perfectly. A user who picked a
  font without box-drawing glyphs (rare on Windows) sees fallback
  glyphs. Not worth a fallback path.
- **Panel width is hardcoded at 56 columns.** Narrow terminals
  (< 60 cols) will wrap the borders. Acceptable — installer is
  one-shot, and 56 cols fits even on a 70-col laptop default.
- **No undo for the dot-source.** If the user's current tab was
  set up with a non-tstyles prompt, dot-sourcing `tstyles.ps1`
  (which auto-loads `current-style.ps1` if it exists) might overwrite
  the prompt. Acceptable: the user just installed a tool that
  manages prompts; they expect this. The pre-existing
  `tstyles.ps1:18-21` auto-load logic is the same behavior every
  new shell tab gets.
- **The two-line `→ X` / `→ X ✓` cadence is verbose** compared to
  cursor-up rewrite. Worth revisiting if it ever feels noisy in
  practice. Out of scope here.
