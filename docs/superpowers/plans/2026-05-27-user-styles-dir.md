# User-Styles Dir Survives Updates Implementation Plan (v0.2.1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.2.1` so user-added themes at `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` are picked up alongside bundled themes AND survive any update path. User-wins on name collision lets users locally override bundled themes without forking.

**Architecture:** Refactor `Get-AvailableStyles` to union `$script:TStylesDataRoot\styles\` (user) with `$script:TStylesModuleRoot\styles\` (bundled), dedup by name with user-wins precedence. Add `Get-StyleDir -StyleName <name>` helper for callers that resolve a style by name (also user-wins). Update 3 call sites to use the helper. README replaces the "doesn't survive updates" disclaimer with the new unified path guidance.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-user-styles-dir-design.md`

---

## File Structure

Five files modified / created. Pure-additive runtime behavior (no breaking changes for users who don't drop folders into the new dir).

- **Modify:** `tstyles.ps1` — rewrite `Get-AvailableStyles`, add `Get-StyleDir`, update `Show-CurrentStyle` / `Apply-StyleDirect` / tab completer to use the new helper. ~40 lines touched.
- **Create:** `tests/Get-StyleDir.Tests.ps1` — 3 tests (user-wins collision, bundled fallback, null when missing).
- **Modify:** `README.md` — replace `## Adding your own style` section with the simpler unified guidance.
- **Modify:** `TerminalStyles.psd1` — `ModuleVersion 0.2.0` → `0.2.1`, update `ReleaseNotes`.
- **No change:** `apply.ps1`, `install.ps1`, `scripts/publish.ps1`, the other test files, `docs/RELEASING.md`.

**Task ordering** keeps CI green at every commit boundary:

1. **Task 1:** Add `Get-StyleDir` helper + its test file (pure addition; tests 46 → 49).
2. **Task 2:** Refactor `Get-AvailableStyles` to union both dirs + update the 3 call sites. Existing tests still pass.
3. **Task 3:** README "Adding your own style" section rewrite.
4. **Task 4:** Bump `ModuleVersion` to `0.2.1` + update `ReleaseNotes`.
5. **Task 5:** Push + publish 0.2.1 via `scripts/publish.ps1` + smoke-test from clean shell + tag `v0.2.1`.

---

## Task 1: Add `Get-StyleDir` helper + its test file

**Files:**
- Modify: `tstyles.ps1` (insert new function near `Get-AvailableStyles`, currently around line 287)
- Create: `tests/Get-StyleDir.Tests.ps1`

Pure addition. Helper isn't called from production yet — Task 2 wires it in. Tests verify it in isolation.

- [ ] **Step 1: Insert `Get-StyleDir` into `tstyles.ps1`**

Find the existing function `Get-AvailableStyles` in `tstyles.ps1` (currently around line 287). Insert the new function IMMEDIATELY ABOVE `Get-AvailableStyles`:

```powershell
function Get-StyleDir {
    # Resolves a style name to its on-disk directory, checking the user
    # dir first ($DataRoot\styles\<name>\) then the bundled dir
    # ($ModuleRoot\styles\<name>\). Returns $null if neither has a
    # scheme.json for that name. User-wins matches Get-AvailableStyles'
    # union-and-dedup precedence.
    param([Parameter(Mandatory)][string]$StyleName)

    $userDir = Join-Path $script:TStylesDataRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) { return $userDir }

    $bundledDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) { return $bundledDir }

    return $null
}
```

Use Edit with anchor `function Get-AvailableStyles {` (unique in file). Prepend the new function plus a blank line.

- [ ] **Step 2: Create `tests/Get-StyleDir.Tests.ps1`**

Create the new file at `C:\Users\felip\dotfiles\tests\Get-StyleDir.Tests.ps1` with this exact content:

```powershell
# Pester 5 tests for Get-StyleDir.
#
# The function resolves a style name to its on-disk directory with
# user-dir precedence (user copy wins on name collision with bundled).
# Module-private; tests run inside InModuleScope.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-StyleDir' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Two distinct subdirs under $TestDrive simulate the two roots.
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesDataRoot 'styles')   -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesModuleRoot 'styles') -Force | Out-Null
        }

        It "returns the user dir when the style exists only in $DataRoot\styles\" {
            $userStyle = Join-Path $script:TStylesDataRoot 'styles\my-theme'
            New-Item -ItemType Directory -Path $userStyle -Force | Out-Null
            '{"name":"my-theme"}' | Set-Content -LiteralPath (Join-Path $userStyle 'scheme.json') -Encoding UTF8 -NoNewline

            Get-StyleDir -StyleName 'my-theme' | Should -Be $userStyle
        }

        It "returns the bundled dir when the style exists only in $ModuleRoot\styles\" {
            $bundledStyle = Join-Path $script:TStylesModuleRoot 'styles\bundled-theme'
            New-Item -ItemType Directory -Path $bundledStyle -Force | Out-Null
            '{"name":"bundled-theme"}' | Set-Content -LiteralPath (Join-Path $bundledStyle 'scheme.json') -Encoding UTF8 -NoNewline

            Get-StyleDir -StyleName 'bundled-theme' | Should -Be $bundledStyle
        }

        It "returns the USER dir (user-wins) when the style exists in both" {
            $userStyle    = Join-Path $script:TStylesDataRoot   'styles\eva'
            $bundledStyle = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $userStyle    -Force | Out-Null
            New-Item -ItemType Directory -Path $bundledStyle -Force | Out-Null
            '{"name":"eva-user"}'    | Set-Content -LiteralPath (Join-Path $userStyle    'scheme.json') -Encoding UTF8 -NoNewline
            '{"name":"eva-bundled"}' | Set-Content -LiteralPath (Join-Path $bundledStyle 'scheme.json') -Encoding UTF8 -NoNewline

            # User-wins: the returned path is the user dir, not the bundled dir.
            Get-StyleDir -StyleName 'eva' | Should -Be $userStyle
        }

        It "returns `$null when neither dir has the style" {
            Get-StyleDir -StyleName 'no-such-theme' | Should -BeNullOrEmpty
        }
    }
}
```

(4 tests, not 3 — the "returns `$null`" case is included as the negative-path coverage. Total existing 46 + 4 new = 50.)

- [ ] **Step 3: Run the new test file**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-StyleDir.Tests.ps1 -Output Detailed"
```

Expected: 4 tests pass, 0 failed.

- [ ] **Step 4: Run the full suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 50, Failed: 0, ...`

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Get-StyleDir.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Get-StyleDir helper + tests (user-wins style resolution)

New module-private helper that resolves a style name to its on-disk
directory, checking $DataRoot\styles\<name>\ first (user dir,
persistent across updates) then $ModuleRoot\styles\<name>\ (bundled,
install-managed). User-wins on name collision so users can locally
override a bundled theme without forking.

Not wired into production code yet -- Task 2 of the user-styles plan
swaps Show-CurrentStyle / Apply-StyleDirect / tab completer to use
this helper instead of directly constructing the module-rooted path.

4 new Pester tests cover all four cases (user-only, bundled-only,
both/user-wins, neither/null).

Spec: docs/superpowers/specs/2026-05-27-user-styles-dir-design.md
EOF
)"
```

---

## Task 2: Refactor `Get-AvailableStyles` + update call sites

**Files:**
- Modify: `tstyles.ps1`

`Get-AvailableStyles` unions both dirs with user-wins dedup. Three call sites switch to the new `Get-StyleDir` helper for name-based lookups.

- [ ] **Step 1: Rewrite `Get-AvailableStyles`**

Find the existing function in `tstyles.ps1` (currently around lines 287-291):

```powershell
function Get-AvailableStyles {
    # Returns an array of DirectoryInfo for every styles/<name>/ that has a
    # scheme.json. Sorted alphabetically by name.
    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) { return @() }
    @(Get-ChildItem -LiteralPath $stylesDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'scheme.json')
    } | Sort-Object Name)
}
```

Replace with:

```powershell
function Get-AvailableStyles {
    # Returns DirectoryInfo for every styles/<name>/ that has a scheme.json,
    # merged from two locations:
    #   1. $DataRoot\styles\<name>\ -- user dir, persistent across updates
    #   2. $ModuleRoot\styles\<name>\ -- bundled, install-managed
    # User-wins on name collision (matches Get-StyleDir's precedence).
    # Sorted alphabetically by name.
    $userStylesDir    = Join-Path $script:TStylesDataRoot   'styles'
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

    $userNames = @($user | ForEach-Object Name)
    @(@($user) + @($bundled | Where-Object { $_.Name -notin $userNames })) | Sort-Object Name
}
```

- [ ] **Step 2: Update `Show-CurrentStyle` to use `Get-StyleDir`**

Find the section in `Show-CurrentStyle` (currently around lines 400-410). The exact existing block:

```powershell
        if ([Console]::IsOutputRedirected) {
            Write-Output $current
        } else {
            $schemePath = Join-Path $script:TStylesModuleRoot "styles\$current\scheme.json"
            if (Test-Path -LiteralPath $schemePath) {
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                Write-Host ("{0,-16}  {1}" -f $current, (Get-SchemeSwatch -Scheme $scheme))
            } else {
                Write-Host $current
            }
        }
```

Replace with:

```powershell
        if ([Console]::IsOutputRedirected) {
            Write-Output $current
        } else {
            $styleDir = Get-StyleDir -StyleName $current
            $schemePath = if ($styleDir) { Join-Path $styleDir 'scheme.json' } else { $null }
            if ($schemePath -and (Test-Path -LiteralPath $schemePath)) {
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                Write-Host ("{0,-16}  {1}" -f $current, (Get-SchemeSwatch -Scheme $scheme))
            } else {
                Write-Host $current
            }
        }
```

- [ ] **Step 3: Update `Apply-StyleDirect` to use `Get-StyleDir`**

Find the early validation block in `Apply-StyleDirect` (currently around lines 468-472):

```powershell
    $styleDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"
    if (-not (Test-Path -LiteralPath (Join-Path $styleDir 'scheme.json'))) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }
```

Replace with:

```powershell
    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }
```

- [ ] **Step 4: Update the tab completer to use `Get-AvailableStyles`**

Find the `Register-ArgumentCompleter` block at the bottom of `tstyles.ps1` (currently around lines 1039-1052):

```powershell
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = @('list', 'current', 'random', 'update', 'uninstall')
    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    $styleNames = if (Test-Path -LiteralPath $stylesDir) {
        @(Get-ChildItem -LiteralPath $stylesDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name })
    } else { @() }
    $all = @($subcommands + $styleNames | Sort-Object)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
```

Replace with:

```powershell
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = @('list', 'current', 'random', 'update', 'uninstall')
    # Get-AvailableStyles already unions $DataRoot\styles\ + $ModuleRoot\styles\
    # with user-wins dedup -- single source of truth for what `tstyles <name>`
    # can target.
    $styleNames = @(Get-AvailableStyles | ForEach-Object Name)
    $all = @($subcommands + $styleNames | Sort-Object -Unique)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
```

(`Sort-Object -Unique` instead of `Sort-Object` — defense against the unlikely case where a subcommand and a style share a name like `list` or `current`.)

- [ ] **Step 5: Run the full Pester suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 50, Failed: 0, ...`

If any test fails: most likely a path issue in one of the call-site updates. Read the failing test's error message and trace which production line it ran through.

- [ ] **Step 6: Sanity-test the user-dir union manually**

In a scratch pwsh tab from the repo root:

```powershell
# Set up a fake user style in the data dir
$dataStyles = Join-Path $env:LOCALAPPDATA 'TerminalStyles\styles\sanity-test'
New-Item -ItemType Directory -Path $dataStyles -Force | Out-Null
@'
{
  "name": "sanity-test",
  "background": "#000000",
  "foreground": "#ffffff",
  "cursorColor": "#ff00ff",
  "black": "#000000", "red": "#cc0000", "green": "#4e9a06", "yellow": "#c4a000",
  "blue": "#3465a4", "purple": "#75507b", "cyan": "#06989a", "white": "#d3d7cf",
  "brightBlack": "#555753", "brightRed": "#ef2929", "brightGreen": "#8ae234",
  "brightYellow": "#fce94f", "brightBlue": "#729fcf", "brightPurple": "#ad7fa8",
  "brightCyan": "#34e2e2", "brightWhite": "#eeeeec"
}
'@ | Set-Content -LiteralPath (Join-Path $dataStyles 'scheme.json') -Encoding UTF8

# Force-reload the module from the dev repo
Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking

# Confirm the user style shows up in list
tstyles list | Select-String 'sanity-test'

# Cleanup
Remove-Item $dataStyles -Recurse -Force
```

Expected: `tstyles list` output includes a `sanity-test` row alongside the 16 bundled themes.

If it doesn't appear: confirm `$script:TStylesDataRoot` actually points at `%LOCALAPPDATA%\TerminalStyles`. From the same shell: `Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; (Get-Module TerminalStyles).Invoke({ $script:TStylesDataRoot })` should print the LOCALAPPDATA path.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Union $DataRoot\styles\ into Get-AvailableStyles (user-wins)

Get-AvailableStyles now reads from BOTH $DataRoot\styles\ (user dir,
persistent across updates) and $ModuleRoot\styles\ (bundled). User-wins
on name collision -- users can locally override a bundled theme by
dropping a same-name folder in the user dir.

Three call sites switched from hardcoded $ModuleRoot path to the new
Get-StyleDir helper (also user-wins):
- Show-CurrentStyle's swatch lookup
- Apply-StyleDirect's $styleDir resolution
- Tab completer (now uses Get-AvailableStyles directly -- single
  source of truth)

User-added themes at %LOCALAPPDATA%\TerminalStyles\styles\<name>\ now
show up in `tstyles list`, can be applied via `tstyles <name>`, and
survive any update (bootstrap re-install or Update-PSResource).

All 50 Pester tests pass.

Spec: docs/superpowers/specs/2026-05-27-user-styles-dir-design.md
EOF
)"
```

---

## Task 3: README — rewrite the "Adding your own style" section

**Files:**
- Modify: `README.md`

Replace the per-install-path guidance + "doesn't survive updates" disclaimer with simpler unified guidance.

- [ ] **Step 1: Find and replace the section**

Find the existing section in `README.md` (currently around lines 400-432). The exact span starts at `## Adding your own style` and ends just before `For contributing back:`.

```markdown
## Adding your own style

Once installed, you can drop a new style folder into your
TerminalStyles install dir with:

```
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── background.gif     # default background image (optional, .png/.jpg also accepted)
└── README.md          # description (optional)
```

The install dir depends on which install path you used:

- **Bootstrap (`iwr | iex`):** `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`.
- **PSGallery (`Install-PSResource`):** the module's per-version dir,
  e.g. `~\Documents\PowerShell\Modules\TerminalStyles\0.2.0\styles\<name>\`.

`tstyles` will pick it up automatically on next module load — no
registration needed.

**Custom styles don't survive `tstyles update` on either path** — the
installer re-extracts (bootstrap) or installs into a fresh per-version
dir (PSGallery), so user-added folders inside `styles/` aren't carried
over. Your active style (`current-style.ps1`) and any lazy-fetched
backgrounds at `%LOCALAPPDATA%\TerminalStyles\` *are* preserved.

For a custom style you want long-term, the cleanest path is to
contribute it upstream — see "For contributing back" below. If you
want to keep working ones locally between updates, save the folder
somewhere outside `styles/` and re-drop it in after each update.

For contributing back:
```

Replace **that entire block** (everything from `## Adding your own style` up to BUT NOT INCLUDING `For contributing back:`) with:

```markdown
## Adding your own style

Drop a folder into `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`
with:

```
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── background.gif     # default background image (optional, .png/.jpg also accepted)
└── README.md          # description (optional)
```

`tstyles` picks it up automatically on next module load — no
registration needed. The dir is the same regardless of install path
(bootstrap or PSGallery), and folders here **survive updates**: both
`tstyles update` (bootstrap re-install) and `Update-PSResource`
leave `%LOCALAPPDATA%\TerminalStyles\` untouched.

If you drop in a folder with the same name as a bundled theme (e.g.
`eva/`), your version wins — useful for tweaking a bundled theme's
prompt or palette without forking the repo.

For contributing back:
```

- [ ] **Step 2: Verify the changes**

```powershell
pwsh -NoProfile -Command "Select-String -Path .\README.md -Pattern 'survive updates','your version wins','no registration needed'"
```

Expected: at least 3 matches (one per key new phrase).

```powershell
pwsh -NoProfile -Command "Select-String -Path .\README.md -Pattern 'Custom styles don.t survive','re-drop it in after each update'"
```

Expected: **no matches** (the old disclaimers are gone).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
README: simplify "Adding your own style" (now survives updates)

Replaces the per-install-path guidance + "doesn't survive updates"
disclaimer with a single unified path: drop a folder into
%LOCALAPPDATA%\TerminalStyles\styles\<name>\ and it survives any
update (matches v0.2.1's Get-AvailableStyles union behavior).

Also documents the user-wins-on-name-collision precedence as a
"tweak a bundled theme locally" use case.

Spec: docs/superpowers/specs/2026-05-27-user-styles-dir-design.md
EOF
)"
```

---

## Task 4: Bump `ModuleVersion` to `0.2.1` + update `ReleaseNotes`

**Files:**
- Modify: `TerminalStyles.psd1`

- [ ] **Step 1: Bump the version**

Find this line in `TerminalStyles.psd1`:

```powershell
    ModuleVersion     = '0.2.0'
```

Replace with:

```powershell
    ModuleVersion     = '0.2.1'
```

- [ ] **Step 2: Update `ReleaseNotes`**

Find this line:

```powershell
            ReleaseNotes = 'v0.2.0: state files relocated to %LOCALAPPDATA%\TerminalStyles\ (survives version upgrades). tstyles update / uninstall now delegate to Update-PSResource / Uninstall-PSResource for PSGallery-installed copies. README leads with Install-PSResource; iwr|iex bootstrap is now a documented fallback. Transparent migration of cached background images on first import.'
```

Replace with:

```powershell
            ReleaseNotes = 'v0.2.1: user-added themes at %LOCALAPPDATA%\TerminalStyles\styles\<name>\ are now picked up alongside bundled themes AND survive any update path (bootstrap re-install, Update-PSResource). User-wins on name collision lets you locally override a bundled theme without forking. Purely additive -- zero behavior change if you don''t use the new user-styles dir.'
```

(Note: double the single-quote in `don''t` for PowerShell string escaping.)

- [ ] **Step 3: Verify the manifest parses**

```powershell
pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"
```

Expected: `Version : 0.2.1` with the same exports as 0.2.0.

- [ ] **Step 4: Re-run the test suite as a final pre-publish check**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 50, Failed: 0, ...`

- [ ] **Step 5: Commit**

```bash
git add TerminalStyles.psd1
git commit -m "Bump version to 0.2.1 + update ReleaseNotes"
```

---

## Task 5: Push + publish 0.2.1 + smoke-test + tag

**Files:** None modified locally. PSGallery + git remote state changes.

Controller-handled (needs the API key for publish).

- [ ] **Step 1: Push all sub-project D commits to `origin/main`**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Four commits ahead:

1. `Bump version to 0.2.1 + update ReleaseNotes` (Task 4)
2. `README: simplify "Adding your own style" (now survives updates)` (Task 3)
3. `Union $DataRoot\styles\ into Get-AvailableStyles (user-wins)` (Task 2)
4. `Add Get-StyleDir helper + tests (user-wins style resolution)` (Task 1)

```bash
git push origin main
```

- [ ] **Step 2: Publish 0.2.1 via the existing script**

```powershell
pwsh -NoProfile -File ./scripts/publish.ps1 -ApiKey '<the-api-key>'
```

Expected output:

```
Staged TerminalStyles 0.2.1 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

Published TerminalStyles 0.2.1 to PSGallery.
Verify at: https://www.powershellgallery.com/packages/TerminalStyles/0.2.1
```

- [ ] **Step 3: Verify on PSGallery**

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 3 | Format-Table Name, Version"
```

Expected: `0.2.1` appears as the latest. `0.2.0` and `0.1.0` still present.

- [ ] **Step 4: Smoke-test from a clean shell — Update-PSResource brings in 0.2.1**

```powershell
pwsh -NoProfile -Command "Update-PSResource -Name TerminalStyles -TrustRepository; Import-Module TerminalStyles -Force -DisableNameChecking; Get-Module TerminalStyles | Format-List Name, Version, Path"
```

Expected: `Version : 0.2.1`, path under `~\Documents\PowerShell\Modules\TerminalStyles\0.2.1\`.

- [ ] **Step 5: Smoke-test the user-styles dir works**

In the same clean shell:

```powershell
pwsh -NoProfile -Command @'
# Create a minimal user style
$userStyles = Join-Path $env:LOCALAPPDATA 'TerminalStyles\styles\smoke-test'
New-Item -ItemType Directory -Path $userStyles -Force | Out-Null
'{"name":"smoke-test","background":"#101010","foreground":"#eeeeee","cursorColor":"#00ff00","black":"#000","red":"#f00","green":"#0f0","yellow":"#ff0","blue":"#00f","purple":"#f0f","cyan":"#0ff","white":"#fff","brightBlack":"#444","brightRed":"#f44","brightGreen":"#4f4","brightYellow":"#ff4","brightBlue":"#44f","brightPurple":"#f4f","brightCyan":"#4ff","brightWhite":"#fff"}' | Set-Content -LiteralPath (Join-Path $userStyles 'scheme.json') -Encoding UTF8 -NoNewline

Import-Module TerminalStyles -Force -DisableNameChecking
tstyles list | Select-String 'smoke-test'

# Cleanup
Remove-Item $userStyles -Recurse -Force
'@
```

Expected: `tstyles list` output contains a line with `smoke-test`. Confirms the union works end-to-end against the published v0.2.1.

If it doesn't appear: the published module's `Get-AvailableStyles` probably wasn't refactored correctly. Check `Get-Module TerminalStyles | Select-Object -ExpandProperty Version` to confirm you're on 0.2.1, then re-read the function in the installed `.psm1`/`.ps1`.

- [ ] **Step 6: Tag v0.2.1**

```bash
git tag v0.2.1
git push --tags
```

Expected: `* [new tag]         v0.2.1 -> v0.2.1`.

---

## Self-Review Notes

Spec coverage:

- `Get-AvailableStyles` union → Task 2 Step 1.
- `Get-StyleDir` helper → Task 1 Step 1.
- `Show-CurrentStyle` updated → Task 2 Step 2.
- `Apply-StyleDirect` updated → Task 2 Step 3.
- Tab completer updated → Task 2 Step 4.
- README rewrite → Task 3.
- Version bump + ReleaseNotes → Task 4.
- Publish + verify → Task 5.
- Pester tests for `Get-StyleDir` → Task 1 Step 2 (4 tests, slightly exceeds spec's "3" count — added the null/missing case for completeness).

Spec items deliberately not in plan:
- No UI distinction in picker for user vs. bundled (spec non-goal).
- No `tstyles import-style` subcommand (spec non-goal).
- No automated migration of files from old install location (spec non-goal — minimal-user-impact, deferred).

Type / signature consistency:

- `Get-StyleDir -StyleName <name>` — same signature in helper, callers, and tests.
- `$script:TStylesDataRoot` / `$script:TStylesModuleRoot` — same exact spellings throughout.
- Return shape: `[System.IO.DirectoryInfo]` from `Get-AvailableStyles` (consistent with prior); `[string]` path from `Get-StyleDir` (matches the spec's intent that callers `Join-Path` for sub-files).

No placeholders. All code blocks complete. All commands have expected output.

One judgment call worth flagging:

- **Task 2 Step 4's tab completer change** swaps `Sort-Object` for `Sort-Object -Unique`. This is a hedge against the (extremely unlikely) case where a user creates a style named `list` / `current` / `random` / `update` / `uninstall` — those would collide with the subcommand list. `-Unique` quietly dedups. No correctness change for the normal case.
