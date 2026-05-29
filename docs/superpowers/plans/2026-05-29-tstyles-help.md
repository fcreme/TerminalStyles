# `tstyles help` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.4.0` adding in-CLI command discovery: `tstyles help` (overview) and `tstyles help <command>` (per-command detail), an unknown-arg → help fallback, a picker hint line, and `help` in tab completion.

**Architecture:** Data-driven, single source of truth. `Get-TerminalStyleHelpData` returns ordered command descriptors; `Show-TerminalStyleHelp` renders the overview or one command's detail from that data. A drift-guard test keeps the help topics in sync with the dispatch table. The unknown-arg path replaces the undocumented positional-profile fallback (superseded by `-Target`). All help output is ASCII (matching the existing UI strings in `tstyles.ps1`, which use `--` not em-dashes).

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-tstyles-help-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1`
  - Add `Get-TerminalStyleHelpData` and `Show-TerminalStyleHelp` before the `# === Public command ===` marker.
  - Add a `help` dispatch line in `Invoke-TerminalStyle` (reuses the existing `$SubArg` Position=1 param).
  - Replace the unknown-arg positional-profile fallback with an unknown → help block.
  - Add a hint line to the picker's `$drawMenu` header.
  - Add `'help'` to the tab-completer `$subcommands` array.
- **Create:** `tests/Get-TerminalStyleHelpData.Tests.ps1`, `tests/Show-TerminalStyleHelp.Tests.ps1`, `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1`.
- **Modify:** `README.md` (Subcommands row), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** data (Task 1), renderer (Task 2), dispatch + completer (Task 3), unknown-arg (Task 4), picker hint (Task 5), docs/version (Task 6), publish (Task 7).

---

## Task 1: `Get-TerminalStyleHelpData` (single source of truth)

**Files:**
- Modify: `tstyles.ps1` (add 1 function before `# === Public command ===`)
- Test: `tests/Get-TerminalStyleHelpData.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-TerminalStyleHelpData.Tests.ps1`:

```powershell
# Pester 5 tests for Get-TerminalStyleHelpData (the help data: single source
# of truth). Drift guard: every dispatched subcommand must have an entry.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-TerminalStyleHelpData' {
    InModuleScope TerminalStyles {
        It 'has a help entry for every dispatched subcommand' {
            # Canonical dispatched subcommands. 'ls' is an alias of 'list' and is
            # NOT a separate topic, so it is intentionally excluded.
            $dispatched = @('list','current','random','tune','register','update','uninstall','help')
            $topics = (Get-TerminalStyleHelpData).Name
            foreach ($cmd in $dispatched) { $topics | Should -Contain $cmd }
        }
        It 'gives every entry a Name, Usage, and Summary' {
            foreach ($e in (Get-TerminalStyleHelpData)) {
                $e.Name    | Should -Not -BeNullOrEmpty
                $e.Usage   | Should -Not -BeNullOrEmpty
                $e.Summary | Should -Not -BeNullOrEmpty
            }
        }
        It 'the tune entry carries KEYS and EXAMPLES' {
            $tune = (Get-TerminalStyleHelpData) | Where-Object Name -eq 'tune'
            $tune.Keys     | Should -Not -BeNullOrEmpty
            $tune.Examples | Should -Contain 'tstyles tune eva'
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-TerminalStyleHelpData.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-TerminalStyleHelpData` is not defined (CommandNotFoundException).

- [ ] **Step 3: Implement the function**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Get-TerminalStyleHelpData {
    # Single source of truth for `tstyles help`. Ordered command descriptors.
    # Name is the dispatch token AND the `help <Name>` topic key. The picker
    # and `tstyles <style>` are arg-less modes described in the overview
    # preamble (Show-TerminalStyleHelp), not topics here. A drift-guard test
    # asserts every dispatched subcommand has an entry.
    @(
        [pscustomobject]@{
            Name = 'list'; Usage = 'list'; Summary = "List all styles; '*' marks the active one"
            Detail = @("Prints every available style (bundled + your own), one per line,",
                       "with the active style marked by an asterisk.")
            Keys = @(); Examples = @('tstyles list')
        }
        [pscustomobject]@{
            Name = 'current'; Usage = 'current'; Summary = 'Print the active style name'
            Detail = @("Prints just the name of the currently applied style (or nothing",
                       "if none is detected).")
            Keys = @(); Examples = @('tstyles current')
        }
        [pscustomobject]@{
            Name = 'random'; Usage = 'random'; Summary = 'Apply a random style'
            Detail = @("Picks a random style and applies it immediately.")
            Keys = @(); Examples = @('tstyles random')
        }
        [pscustomobject]@{
            Name = 'tune'; Usage = 'tune [name]'; Summary = 'Live-tune a style; save as your own'
            Detail = @("Opens an arrow-key editor for the active style (or [name]). Adjusts",
                       "brightness, saturation, opacity, font face, and font size.",
                       "Saved styles land in your user dir and show up in 'tstyles list'.")
            Keys = @('Up/Down      select a knob',
                     'Left/Right   adjust it',
                     'R            reset colors',
                     'Enter        save (Overwrite / Save as)',
                     'Esc          revert')
            Examples = @('tstyles tune', 'tstyles tune eva')
        }
        [pscustomobject]@{
            Name = 'register'; Usage = 'register'; Summary = 'Add the loader to your $PROFILE'
            Detail = @("Adds the Import-Module loader to both PowerShell 7 and Windows",
                       "PowerShell 5.1 `$PROFILE files (with a confirm prompt) so tstyles",
                       "loads on every new tab.")
            Keys = @(); Examples = @('tstyles register')
        }
        [pscustomobject]@{
            Name = 'update'; Usage = 'update'; Summary = 'Update to the latest version'
            Detail = @("Updates TerminalStyles. PSGallery installs run Update-PSResource;",
                       "bootstrap installs re-run the installer.")
            Keys = @(); Examples = @('tstyles update')
        }
        [pscustomobject]@{
            Name = 'uninstall'; Usage = 'uninstall'; Summary = 'Remove the module (keeps your styles)'
            Detail = @("Removes the module and strips the `$PROFILE loader. Your saved",
                       "styles and state are preserved unless you pass -DeleteData.")
            Keys = @(); Examples = @('tstyles uninstall', 'tstyles uninstall -DeleteData')
        }
        [pscustomobject]@{
            Name = 'help'; Usage = 'help [command]'; Summary = 'Show all commands, or details for one'
            Detail = @("With no argument, lists every command. With a command name, shows",
                       "detailed help for that command.")
            Keys = @(); Examples = @('tstyles help', 'tstyles help tune')
        }
    )
}
```

Note: the backtick before `$PROFILE` (`` `$PROFILE ``) escapes the `$` so the literal text "$PROFILE" appears in the help output rather than expanding an (empty) variable.

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-TerminalStyleHelpData.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests, 0 failed.

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Get-TerminalStyleHelpData.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Get-TerminalStyleHelpData (help single source of truth)

Ordered command descriptors (Name/Usage/Summary/Detail/Keys/Examples) for
`tstyles help`. A drift-guard test asserts every dispatched subcommand has
an entry, so help can't silently fall out of sync with behavior.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `Show-TerminalStyleHelp` (the renderer)

**Files:**
- Modify: `tstyles.ps1` (add 1 function before `# === Public command ===`)
- Test: `tests/Show-TerminalStyleHelp.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Show-TerminalStyleHelp.Tests.ps1`:

```powershell
# Pester 5 tests for Show-TerminalStyleHelp (overview + per-command detail).
# Write-Host output is captured via the information stream (6>&1).
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Show-TerminalStyleHelp' {
    InModuleScope TerminalStyles {
        It 'overview lists every command name' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            foreach ($name in (Get-TerminalStyleHelpData).Name) {
                $out | Should -Match ([regex]::Escape($name))
            }
        }
        It 'overview shows USAGE and the docs link' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            $out | Should -Match 'USAGE'
            $out | Should -Match 'github\.com/fcreme/TerminalStyles'
        }
        It 'help <command> shows that command''s detail' {
            $out = Show-TerminalStyleHelp -Command 'tune' 6>&1 | Out-String
            $out | Should -Match 'brightness'
            $out | Should -Match 'Esc'
        }
        It 'command lookup is case-insensitive' {
            $out = Show-TerminalStyleHelp -Command 'TUNE' 6>&1 | Out-String
            $out | Should -Match 'brightness'
        }
        It 'unknown topic shows a not-found message and lists topics' {
            $out = Show-TerminalStyleHelp -Command 'frobnicate' 6>&1 | Out-String
            $out | Should -Match "No help topic 'frobnicate'"
            $out | Should -Match 'tune'
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Show-TerminalStyleHelp.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Show-TerminalStyleHelp` is not defined.

- [ ] **Step 3: Implement the function**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1` (after `Get-TerminalStyleHelpData`):

```powershell
function Show-TerminalStyleHelp {
    # Renders `tstyles help`. No -Command: the overview (USAGE + COMMANDS +
    # EXAMPLES + docs link). With -Command: that command's detail, or a
    # not-found message. Data comes from Get-TerminalStyleHelpData. All ASCII,
    # lightly colorized to match the picker/tuner.
    param([string]$Command)

    $data = Get-TerminalStyleHelpData

    if ($Command) {
        $entry = $data | Where-Object { $_.Name -eq $Command.ToLower() } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "No help topic '$Command'." -ForegroundColor Yellow
            Write-Host ("Topics: " + (($data.Name) -join ', ')) -ForegroundColor DarkGray
            return
        }
        Write-Host ""
        Write-Host ("tstyles " + $entry.Usage) -ForegroundColor Cyan -NoNewline
        Write-Host (" - " + $entry.Summary)
        if ($entry.Detail) {
            Write-Host ""
            foreach ($line in $entry.Detail) { Write-Host ("  " + $line) }
        }
        if ($entry.Keys) {
            Write-Host ""
            Write-Host "KEYS" -ForegroundColor DarkGray
            foreach ($k in $entry.Keys) { Write-Host ("  " + $k) }
        }
        if ($entry.Examples) {
            Write-Host ""
            Write-Host "EXAMPLES" -ForegroundColor DarkGray
            foreach ($e in $entry.Examples) { Write-Host ("  " + $e) }
        }
        Write-Host ""
        return
    }

    # Overview. Module version is best-effort (no disk I/O); omitted if absent.
    $ver = $ExecutionContext.SessionState.Module.Version
    $title = if ($ver) { "tstyles - themed styles for Windows Terminal (v$ver)" }
             else       { "tstyles - themed styles for Windows Terminal" }

    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor DarkGray
    Write-Host "  tstyles [command] [args]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor DarkGray
    Write-Host "  (no command)      Open the interactive picker"
    Write-Host "  <style>           Apply a style by name (umbrella, eva, ...)"
    foreach ($e in $data) {
        Write-Host ("  " + ('{0,-16}' -f $e.Usage) + "  " + $e.Summary)
    }
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor DarkGray
    Write-Host "  tstyles                 # pick interactively"
    Write-Host "  tstyles eva             # apply 'eva'"
    Write-Host "  tstyles tune eva        # tune + save your own"
    Write-Host ""
    Write-Host "More: https://github.com/fcreme/TerminalStyles" -ForegroundColor DarkGray
    Write-Host ""
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Show-TerminalStyleHelp.Tests.ps1 -Output Detailed"`
Expected: PASS — 5 tests, 0 failed.

- [ ] **Step 5: Eyeball the rendered output (sanity)**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; & (Get-Module TerminalStyles) { Show-TerminalStyleHelp }"`
Expected: the overview prints with USAGE / COMMANDS / EXAMPLES sections, every command listed, no errors. (Then optionally `Show-TerminalStyleHelp -Command tune`.)

- [ ] **Step 6: Run the full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Show-TerminalStyleHelp.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Show-TerminalStyleHelp (overview + per-command detail)

Renders the overview (USAGE/COMMANDS/EXAMPLES/docs link) or one command's
detail (usage/summary/detail/keys/examples) from Get-TerminalStyleHelpData;
unknown topics get a graceful not-found + topic list. Case-insensitive.
ASCII output, lightly colorized to match the picker. Not dispatched yet --
Task 3 wires it.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire `help` into dispatch + tab completer

**Files:**
- Modify: `tstyles.ps1` (dispatch line + completer array)
- Test: `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1`:

```powershell
# Pester 5 tests: `tstyles help [command]` routes to Show-TerminalStyleHelp,
# and the tab completer offers 'help'.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'tstyles help dispatch' {
    InModuleScope TerminalStyles {
        It 'routes bare `help` to Show-TerminalStyleHelp with no command' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'help'
            Should -Invoke Show-TerminalStyleHelp -Times 1 -ParameterFilter { -not $Command }
        }
        It 'routes `help <command>` with the command name' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'help' -SubArg 'tune'
            Should -Invoke Show-TerminalStyleHelp -Times 1 -ParameterFilter { $Command -eq 'tune' }
        }
    }
}

Describe 'tstyles help tab completion' {
    It "offers 'help' as a subcommand" {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $matches = (TabExpansion2 -inputScript 'tstyles hel' -cursorColumn 11).CompletionMatches.CompletionText
        $matches | Should -Contain 'help'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-HelpDispatch.Tests.ps1 -Output Detailed"`
Expected: FAIL — `help` is not dispatched (falls through) and/or the completer doesn't offer `help`.

- [ ] **Step 3: Add the dispatch line**

In `tstyles.ps1`, find this dispatch line inside `Invoke-TerminalStyle`:

```powershell
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
```

Insert the `help` line immediately after it:

```powershell
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
    if ($Arg -eq 'help')                 { Show-TerminalStyleHelp -Command $SubArg; return }
```

- [ ] **Step 4: Add `'help'` to the completer**

Find:

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'tune', 'update', 'uninstall')
```

Replace with:

```powershell
    $subcommands = @('help', 'list', 'current', 'random', 'register', 'tune', 'update', 'uninstall')
```

- [ ] **Step 5: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-HelpDispatch.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1
git commit -m "$(cat <<'EOF'
Wire `tstyles help` into dispatch + tab completer

Routes `help` / `help <command>` to Show-TerminalStyleHelp (reusing the
$SubArg Position=1 param) and adds 'help' to the completer's subcommands.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Unknown arg -> help (drop the positional-profile fallback)

**Files:**
- Modify: `tstyles.ps1` (replace the unknown-arg fallback in `Invoke-TerminalStyle`)
- Test: `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1` (add a Describe block)

- [ ] **Step 1: Add the failing test**

Append this `Describe` block to `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1` (after the existing `Describe 'tstyles help tab completion'` block):

```powershell
Describe 'tstyles unknown-arg fallback' {
    InModuleScope TerminalStyles {
        It 'shows help and does NOT open the picker for an unknown arg' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-AvailableStyles { @() }   # nothing matches the arg
            Mock Find-WTSettingsPath { throw 'picker path must not be reached' }
            { Invoke-TerminalStyle -Arg 'definitely-not-a-real-thing' } | Should -Not -Throw
            Should -Invoke Show-TerminalStyleHelp -Times 1
            Should -Not -Invoke Find-WTSettingsPath
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-HelpDispatch.Tests.ps1 -Output Detailed"`
Expected: FAIL — the unknown arg currently falls through to the picker (the mocked `Find-WTSettingsPath` throws), so the test errors / `Show-TerminalStyleHelp` is not invoked.

- [ ] **Step 3: Replace the fallback**

In `tstyles.ps1`, find this block inside `Invoke-TerminalStyle` (the style-match + legacy fallback):

```powershell
        # Backward compat: $Arg wasn't a subcommand or a style name, so treat
        # it as a Windows Terminal profile name for the picker (old behavior).
        if (-not $Target) { $Target = $Arg }
```

Replace it with:

```powershell
        # Not a subcommand and not a style name: show help instead of silently
        # opening the picker against a (likely bogus) profile name. To target a
        # specific Windows Terminal profile, use the -Target parameter.
        Write-Host "Unknown command or style: '$Arg'" -ForegroundColor Yellow
        Show-TerminalStyleHelp
        Write-Host "To target a Windows Terminal profile, use: tstyles -Target '<name>'" -ForegroundColor DarkGray
        return
```

- [ ] **Step 4: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-HelpDispatch.Tests.ps1 -Output Detailed"`
Expected: PASS — 4 tests (3 prior + the new unknown-arg test).

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 5: Manual sanity (optional)**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; tstyles zzznotreal"`
Expected: prints `Unknown command or style: 'zzznotreal'` + the overview + the `-Target` hint; does NOT hang or open a picker.

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1
git commit -m "$(cat <<'EOF'
Unknown arg shows help instead of a silent bogus picker

Replaces the undocumented positional-profile fallback (superseded by
-Target) with: print "Unknown command or style" + the overview + a -Target
hint, then return. No more silent picker against a typo'd profile name.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Picker hint line

**Files:**
- Modify: `tstyles.ps1` (one `Write-Host` in the picker's `$drawMenu`)

This is in the interactive picker (manual-verified, like the picker/tuner key loops). No new automated test; a module-load/parse check guards against syntax errors.

- [ ] **Step 1: Add the hint line**

In `tstyles.ps1`, find the picker header inside `$drawMenu`:

```powershell
            Write-Host "$hintColor  Up/Down to preview, Enter to keep, Esc to cancel$resetColor"
            Write-Host ""
```

Replace with (insert the hint line between them):

```powershell
            Write-Host "$hintColor  Up/Down to preview, Enter to keep, Esc to cancel$resetColor"
            Write-Host "$hintColor  Tip: run 'tstyles help' for all commands$resetColor"
            Write-Host ""
```

- [ ] **Step 2: Verify the module still parses + loads**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; 'ok: module loaded'"`
Expected: prints `ok: module loaded` (no parse errors).

- [ ] **Step 3: Run the full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Add a `tstyles help` hint to the picker header

One dim line under the picker instructions pointing users at the new help
command for passive discovery.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: README + version bump to 0.4.0

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Add the `help` row to the Subcommands listing**

In `README.md`, find:

```
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
```

Replace with (add the help row after it):

```
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
tstyles help [command]            # Show all commands, or details for one
```

- [ ] **Step 2: Bump the version**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.3.0'
```

Replace with:

```powershell
    ModuleVersion     = '0.4.0'
```

- [ ] **Step 3: Update ReleaseNotes**

In `TerminalStyles.psd1`, Read the current `ReleaseNotes = '...'` line (it currently begins `v0.3.0: new \`tstyles tune ...`). Replace that entire single-quoted value with:

```powershell
            ReleaseNotes = 'v0.4.0: new `tstyles help [command]` subcommand -- an in-CLI overview of every command plus per-command detail (tstyles help tune). Unknown commands now print help instead of silently opening the picker, and the picker shows a help hint. Purely additive -- existing behavior unchanged.'
```

(Preserve the `ReleaseNotes = '...'` structure and PowerShell's doubled-single-quote `''` escaping for any apostrophes.)

- [ ] **Step 4: Verify the manifest parses + version**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.4.0`; exported functions still `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

- [ ] **Step 5: Verify README mentions help**

Run: `pwsh -NoProfile -Command "(Select-String -Path .\README.md -Pattern 'tstyles help').Count"`
Expected: `1` or higher.

- [ ] **Step 6: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document `tstyles help` + bump to 0.4.0

README: Subcommands row for `help`. Manifest: ModuleVersion 0.3.0 -> 0.4.0
and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-29-tstyles-help-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Push + publish 0.4.0 + tag

**Files:** None modified locally. PSGallery + git remote state. **User-handled** — the PSGallery publish needs the maintainer's API key entered at `publish.ps1`'s hidden prompt (cannot be driven non-interactively). Tagging and the remote branch are git pushes the agent can do.

- [ ] **Step 1: Confirm clean tree + push the branch/PR per the finishing-a-development-branch flow**

```bash
git status            # clean
git log --oneline origin/main..HEAD   # Tasks 1-6
```

- [ ] **Step 2: Dry-run the publish (no key)**

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf
```

Expected: `Staged TerminalStyles 0.4.0 ...` + a `What if:` line for the upload. Eyeball the staged file list (allowlist only).

- [ ] **Step 3: Publish 0.4.0** (maintainer runs this; hidden key prompt)

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1
```

Expected: `Published TerminalStyles 0.4.0 to PSGallery.`

- [ ] **Step 4: Verify on PSGallery**

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 Name, Version | Format-Table"
```

Expected: `0.4.0` newest, with `0.3.0`, `0.2.2`, `0.2.1` present.

- [ ] **Step 5: Tag v0.4.0**

```bash
git tag v0.4.0
git push origin v0.4.0
```

- [ ] **Step 6: Smoke-test** (inside a Windows Terminal tab)

```powershell
Update-PSResource -Name TerminalStyles -TrustRepository
Import-Module TerminalStyles -Force -DisableNameChecking
tstyles help
tstyles help tune
tstyles zzznotreal     # should show unknown + help, not a picker
```

---

## Self-Review Notes

**Spec coverage:**

- `tstyles help` overview -> Task 2 (renderer) + Task 1 (data) + Task 3 (dispatch).
- `tstyles help <command>` detail -> Task 2 (`-Command` path) + Task 3 (dispatch passes `$SubArg`).
- Unknown arg -> help, drop positional-profile fallback -> Task 4.
- Picker hint line -> Task 5.
- `help` in tab completion -> Task 3.
- Data-driven single source of truth + drift guard -> Task 1 (data + drift-guard test).
- Not-found topic handling -> Task 2 (test + impl).
- README row + version 0.4.0 + ReleaseNotes -> Task 6.
- Publish/tag -> Task 7.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output. The only `<...>` are user-facing prose (`<command>`, `<name>`, `<style>`) and the `<filename>` in handoff text.

**Type/signature consistency:**

- `Get-TerminalStyleHelpData` returns objects with `Name/Usage/Summary/Detail/Keys/Examples` — same fields read by `Show-TerminalStyleHelp` (Task 2) and the drift-guard/shape tests (Task 1).
- `Show-TerminalStyleHelp -Command <string>` — defined Task 2; called with `$SubArg` in dispatch (Task 3) and bare in the unknown-arg path (Task 4); tests reference the same signature.
- Dispatch reuses the existing `$SubArg` (Position=1) param — no new parameter introduced.

**ASCII note:** All help/hint output uses ASCII (`-`, `'`) to match the existing UI strings in `tstyles.ps1` and avoid PS 5.1 / non-ASCII-locale encoding issues. The spec mockups used `—`/`·` for looks; the implementation deliberately uses ASCII.

**Judgment calls flagged:**

- Overview version line is best-effort via `$ExecutionContext.SessionState.Module.Version` (runtime, no disk I/O); omitted if null. Tests don't assert the version value.
- `ls` (alias of `list`) is intentionally not a help topic; the drift guard compares against the canonical set only.
- The picker hint and the picker itself remain manually verified (consistent with how the existing picker/tuner key loops are tested).
