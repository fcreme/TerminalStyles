# `-KeepPrompt` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.5.0` adding a `-KeepPrompt` flag that applies a style's full visuals (colors/cursor/font/opacity/background) without imposing the style's prompt/banner — so Oh My Posh / Starship users keep their own prompt.

**Architecture:** Thread a `[switch]$KeepPrompt` from `Invoke-TerminalStyle` into `Apply-StyleDirect`, where it inverts the prompt step to "clear `current-style.ps1`" instead of copying the style's `profile.ps1`. The visuals path (`Merge-StyleIntoSettings`) is untouched. `apply.ps1` already has this as `-NoProfile`; rename it to `-KeepPrompt` with `[Alias('NoProfile')]` for back-compat.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-keep-prompt-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1` — `Apply-StyleDirect` (param + prompt block); `Invoke-TerminalStyle` (param + the direct-apply dispatch call).
- **Modify:** `apply.ps1` — rename `-NoProfile` param to `-KeepPrompt` with `[Alias('NoProfile')]`; update its one usage.
- **Create:** `tests/Apply-StyleDirect-KeepPrompt.Tests.ps1` (behavior), `tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1` (dispatch + apply.ps1 alias).
- **Modify:** `README.md` (a "Keeping your own prompt" note), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** Apply-StyleDirect core + tests (Task 1), dispatch threading + tests (Task 2), apply.ps1 rename + test (Task 3), docs/version (Task 4), publish (Task 5).

---

## Task 1: `Apply-StyleDirect -KeepPrompt`

**Files:**
- Modify: `tstyles.ps1` (`Apply-StyleDirect` param ~`:618`, prompt block ~`:684`)
- Test: `tests/Apply-StyleDirect-KeepPrompt.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/Apply-StyleDirect-KeepPrompt.Tests.ps1`:

```powershell
# Pester 5 tests for Apply-StyleDirect -KeepPrompt: applies visuals but does
# not install the style's prompt (clears current-style.ps1 instead).
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

Describe 'Apply-StyleDirect -KeepPrompt' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # $script:TStylesCurrent is computed at module load from the REAL
            # data root, so override it explicitly to a TestDrive path.
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }

            $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
            [System.IO.File]::WriteAllText($script:fakeSettings,
                '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}',
                [System.Text.UTF8Encoding]::new($false))

            $script:styleDir = Join-Path $TestDrive 'styles\fakeStyle'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'profile.ps1'),
                '# fakeStyle prompt', [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Merge-StyleIntoSettings      { param($Settings) $Settings }
            Mock Write-SettingsFile           {}
        }

        # -Target 'defaults' makes $isPwshTarget true (so the prompt block runs)
        # without needing a pwsh-flavored profile entry.

        It 'with -KeepPrompt: does NOT copy the style profile to current-style.ps1' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'with -KeepPrompt: removes an existing current-style.ps1' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old prompt',
                [System.Text.UTF8Encoding]::new($false))
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'with -KeepPrompt: still applies the visuals (Merge + Write run)' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Should -Invoke Merge-StyleIntoSettings -Times 1
            Should -Invoke Write-SettingsFile -Times 1
        }
        It 'WITHOUT -KeepPrompt: copies the style profile to current-style.ps1 (regression)' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeTrue
            (Get-Content -LiteralPath $script:TStylesCurrent -Raw).Trim() | Should -Be '# fakeStyle prompt'
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Apply-StyleDirect-KeepPrompt.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Apply-StyleDirect` has no `-KeepPrompt` parameter (ParameterBindingException on the `-KeepPrompt` calls).

- [ ] **Step 3: Add the `-KeepPrompt` param**

In `tstyles.ps1`, find `Apply-StyleDirect`'s param block (~`:618`):

```powershell
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided = $false
    )
```

Replace with:

```powershell
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided = $false,
        # Apply the visuals but not the style's prompt/banner: clears
        # current-style.ps1 so the user's own prompt stays in control.
        [switch]$KeepPrompt
    )
```

- [ ] **Step 4: Invert the prompt block under `-KeepPrompt`**

Find (~`:684`):

```powershell
    if ($isPwshTarget) {
        if (Test-Path -LiteralPath $styleProfile) {
            Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
        } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
            Remove-Item -LiteralPath $script:TStylesCurrent -Force
        }
    }
```

Replace with:

```powershell
    if ($isPwshTarget) {
        if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
            Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
        } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
            Remove-Item -LiteralPath $script:TStylesCurrent -Force
        }
    }
```

(With `-KeepPrompt`, the first branch is false, so it always takes the "remove `current-style.ps1` if present" branch. The later live dot-source at ~`:698` is unchanged — its `Test-Path $script:TStylesCurrent` guard is now false, so it skips.)

- [ ] **Step 5: Run the tests to verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Apply-StyleDirect-KeepPrompt.Tests.ps1 -Output Detailed"`
Expected: PASS — 4 tests, 0 failed.

- [ ] **Step 6: Full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (112 total: 108 + 4 new).

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Apply-StyleDirect-KeepPrompt.Tests.ps1
git commit -m "$(cat <<'EOF'
Add -KeepPrompt to Apply-StyleDirect (apply visuals, keep your prompt)

With -KeepPrompt, Apply-StyleDirect applies the style's visuals via
Merge-StyleIntoSettings but does not install the style's prompt: it clears
current-style.ps1 instead of copying the style's profile.ps1, so the user's
own prompt (Oh My Posh / Starship) stays in control. Not wired to the CLI
yet -- Task 2 threads it through Invoke-TerminalStyle.

Spec: docs/superpowers/specs/2026-05-29-keep-prompt-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Thread `-KeepPrompt` through `Invoke-TerminalStyle`

**Files:**
- Modify: `tstyles.ps1` (`Invoke-TerminalStyle` param + the direct-apply dispatch call ~`:1655`)
- Test: `tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1`:

```powershell
# Pester 5 tests: `tstyles <name> -KeepPrompt` threads the switch to
# Apply-StyleDirect.
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

Describe 'tstyles <name> -KeepPrompt dispatch' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Apply-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'eva'; FullName = 'X' }) }
        }
        It 'threads -KeepPrompt to Apply-StyleDirect when set' {
            Invoke-TerminalStyle -Arg 'eva' -KeepPrompt
            Should -Invoke Apply-StyleDirect -Times 1 -ParameterFilter { $StyleName -eq 'eva' -and $KeepPrompt }
        }
        It 'does not set -KeepPrompt when the flag is absent' {
            Invoke-TerminalStyle -Arg 'eva'
            Should -Invoke Apply-StyleDirect -Times 1 -ParameterFilter { $StyleName -eq 'eva' -and -not $KeepPrompt }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-KeepPrompt.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Invoke-TerminalStyle` has no `-KeepPrompt` parameter.

- [ ] **Step 3: Add the param to `Invoke-TerminalStyle`**

In `tstyles.ps1`, find the end of `Invoke-TerminalStyle`'s param block (use Read to confirm — the last param is `[switch]$Force`):

```powershell
        [switch]$Force
    )
```

Replace with:

```powershell
        [switch]$Force,
        # Apply a style's visuals but keep your own prompt (skip the style's
        # prompt/banner). Threaded to Apply-StyleDirect for `tstyles <name>`.
        [switch]$KeepPrompt
    )
```

- [ ] **Step 4: Thread it into the direct-apply dispatch call**

Find (~`:1655`):

```powershell
            Apply-StyleDirect -StyleName $Arg -Target $Target `
                -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
```

Replace with:

```powershell
            Apply-StyleDirect -StyleName $Arg -Target $Target `
                -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
                -KeepPrompt:$KeepPrompt
```

- [ ] **Step 5: Run the tests + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-KeepPrompt.Tests.ps1 -Output Detailed"` → PASS, 2 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"` → `Failed: 0` (114 total).

- [ ] **Step 6: Manual sanity (optional)**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; (Get-Command Invoke-TerminalStyle).Parameters.ContainsKey('KeepPrompt')"`
Expected: `True`.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1
git commit -m "$(cat <<'EOF'
Wire `tstyles <name> -KeepPrompt` through to Apply-StyleDirect

Adds a [switch]$KeepPrompt to Invoke-TerminalStyle and threads it into the
direct-apply dispatch. After this, `tstyles eva -KeepPrompt` applies eva's
look but leaves your prompt alone.

Spec: docs/superpowers/specs/2026-05-29-keep-prompt-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rename `apply.ps1`'s `-NoProfile` to `-KeepPrompt` (alias for back-compat)

**Files:**
- Modify: `apply.ps1` (param `:16-22`, usage `:236`)
- Test: append a Describe to `tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1`

- [ ] **Step 1: Add the failing test (param introspection)**

Append this `Describe` block to `tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1` (after the existing `Describe`, at end of file):

```powershell

Describe 'apply.ps1 -KeepPrompt parameter' {
    It 'exposes -KeepPrompt with -NoProfile as a back-compat alias' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $cmd = Get-Command (Join-Path $repoRoot 'apply.ps1')
        $cmd.Parameters.ContainsKey('KeepPrompt') | Should -BeTrue
        $cmd.Parameters['KeepPrompt'].Aliases | Should -Contain 'NoProfile'
        $cmd.Parameters.ContainsKey('NoProfile') | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run it to verify it FAILS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-KeepPrompt.Tests.ps1 -Output Detailed"`
Expected: FAIL — `apply.ps1` has `NoProfile` (no `KeepPrompt` param / no alias yet).

- [ ] **Step 3: Rename the param**

In `apply.ps1`, find the param block (`:16-22`):

```powershell
param(
    [string]$Style,
    [string]$Target,
    [string]$BackgroundImage,
    [string]$SettingsPath,
    [switch]$NoProfile
)
```

Replace with:

```powershell
param(
    [string]$Style,
    [string]$Target,
    [string]$BackgroundImage,
    [string]$SettingsPath,
    # Apply visuals but not the style's prompt/banner. -NoProfile is the
    # original name, kept as an alias for back-compat.
    [Alias('NoProfile')]
    [switch]$KeepPrompt
)
```

- [ ] **Step 4: Update the one usage**

In `apply.ps1`, find (`:236`):

```powershell
if ($hasProfile -and -not $NoProfile) {
```

Replace with:

```powershell
if ($hasProfile -and -not $KeepPrompt) {
```

(Confirm there are no other `$NoProfile` references: `pwsh -NoProfile -Command "(Select-String -Path .\apply.ps1 -Pattern '\\\$NoProfile').Count"` should be `0` after this edit.)

- [ ] **Step 5: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-KeepPrompt.Tests.ps1 -Output Detailed"` → PASS, 3 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"` → `Failed: 0` (115 total).

- [ ] **Step 6: Confirm apply.ps1 still parses**

Run: `pwsh -NoProfile -Command "$null = Get-Command .\apply.ps1; 'ok: apply.ps1 parses'"`
Expected: `ok: apply.ps1 parses`.

- [ ] **Step 7: Commit**

```bash
git add apply.ps1 tests/Invoke-TerminalStyle-KeepPrompt.Tests.ps1
git commit -m "$(cat <<'EOF'
Rename apply.ps1 -NoProfile to -KeepPrompt (keep -NoProfile alias)

Standardizes the flag name with `tstyles <name> -KeepPrompt`. -NoProfile is
retained as a parameter alias so existing callers/dotfiles keep working.
Behavior unchanged (skip installing the style's prompt).

Spec: docs/superpowers/specs/2026-05-29-keep-prompt-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: README + version bump to 0.5.0

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Add a "Keeping your own prompt" subsection to `README.md`**

Find the `## Styles` heading (the section after the "Tuning a theme" subsection). Insert the following BEFORE the `## Styles` line. NOTE: write the inner ```powershell fence literally into the README (the outer ```markdown here just delimits this instruction):

```markdown
### Keeping your own prompt (Oh My Posh / Starship)

Applying a style normally also sets that style's prompt and banner. If you run
a prompt engine like **Oh My Posh** or **Starship**, add `-KeepPrompt` to get
the style's colors, cursor, font, and background **without** touching your
prompt:

```powershell
tstyles eva -KeepPrompt        # eva's look; your prompt stays
```

The scriptable `apply.ps1` accepts the same flag (`apply.ps1 -KeepPrompt`,
with `-NoProfile` kept as an alias). Note: a `-KeepPrompt` apply isn't reported
by `tstyles current` / the `*` in `tstyles list`, because active-style detection
is prompt-based.

```

(The final blank line keeps a gap before `## Styles`.)

- [ ] **Step 2: Bump the version**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.4.2'
```

Replace with:

```powershell
    ModuleVersion     = '0.5.0'
```

- [ ] **Step 3: Update ReleaseNotes**

In `TerminalStyles.psd1`, Read the current `ReleaseNotes = '...'` line (begins `v0.4.2: ...`). Replace that entire single-quoted value with:

```powershell
            ReleaseNotes = 'v0.5.0: new `-KeepPrompt` flag (`tstyles <name> -KeepPrompt`, and `apply.ps1 -KeepPrompt`) applies a style''s colors, cursor, font, opacity, and background but leaves your prompt alone -- for Oh My Posh / Starship users. apply.ps1''s prior `-NoProfile` is kept as an alias. Purely additive.'
```

(Preserve the `ReleaseNotes = '...'` structure and PowerShell's doubled-single-quote `''` escaping — note `style''s` and `apply.ps1''s`.)

- [ ] **Step 4: Verify manifest + README**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.5.0`; exported functions `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

Run: `pwsh -NoProfile -Command "(Select-String -Path .\README.md -Pattern 'KeepPrompt').Count"`
Expected: `3` or higher.

- [ ] **Step 5: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (115 total).

- [ ] **Step 6: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document -KeepPrompt + bump to 0.5.0

README: "Keeping your own prompt" subsection for Oh My Posh / Starship users.
Manifest: ModuleVersion 0.4.2 -> 0.5.0 and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-29-keep-prompt-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Push + publish 0.5.0 + tag

**Files:** None local. PSGallery + git remote. **User-handled** — publish needs the maintainer's API key at `publish.ps1`'s hidden prompt. Tag + push are agent-doable.

- [ ] **Step 1:** Merge the feature branch to main + push (finishing-a-development-branch).
- [ ] **Step 2:** Dry-run: `pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf` → `Staged TerminalStyles 0.5.0 ...`; eyeball staged files.
- [ ] **Step 3:** Publish (maintainer, hidden key): `pwsh -NoProfile -File .\scripts\publish.ps1` → `Published TerminalStyles 0.5.0 to PSGallery.`
- [ ] **Step 4:** Verify: `Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 Name, Version | Format-Table` → 0.5.0 newest.
- [ ] **Step 5:** Tag: `git tag v0.5.0; git push origin v0.5.0`.
- [ ] **Step 6:** Smoke-test in Windows Terminal: `tstyles eva -KeepPrompt` keeps your prompt; `tstyles eva` (no flag) applies eva's prompt as before.

---

## Self-Review Notes

**Spec coverage:**

- `-KeepPrompt` on `tstyles <name>` → Task 1 (Apply-StyleDirect core) + Task 2 (dispatch threading).
- Clears `current-style.ps1` (deterministic no-prompt) → Task 1 (inverted block) + tests (remove existing / no copy).
- Visuals untouched → Task 1 test ("Merge + Write run"); `Merge-StyleIntoSettings` not modified.
- `apply.ps1` rename to `-KeepPrompt` + `[Alias('NoProfile')]` back-compat → Task 3.
- Not picker/random → out of scope; no dispatch added for those.
- Documented detection limitation → Task 4 README note.
- README + version 0.5.0 + ReleaseNotes → Task 4. Publish/tag → Task 5.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output. The only `<...>` is user-facing prose (`<name>`).

**Type/signature consistency:**

- `[switch]$KeepPrompt` — added to `Apply-StyleDirect` (Task 1), `Invoke-TerminalStyle` (Task 2), and `apply.ps1` (Task 3, with `[Alias('NoProfile')]`). Same name throughout.
- Dispatch passes `-KeepPrompt:$KeepPrompt` (Task 2) → matches the `Apply-StyleDirect` switch (Task 1).
- Test counts: Task 1 → 112; Task 2 → 114; Task 3 → 115 (4 + 2 + 1 new across the run).

**Judgment calls flagged:**

- Test uses `-Target 'defaults'` to force `$isPwshTarget = $true` (so the prompt block executes) without crafting a pwsh-flavored profile entry; and explicitly overrides `$script:TStylesCurrent` to a `$TestDrive` path (it's computed at module load, not from the overridden `$DataRoot`).
- `apply.ps1` keeps its shipped skip-only behavior (no `current-style.ps1` removal); only `tstyles <name>` clears it — the intentional asymmetry from the spec.
- `Merge-StyleIntoSettings` / `Write-SettingsFile` are mocked in the Task 1 tests (visuals path is exercised elsewhere); the test asserts they're still *invoked* under `-KeepPrompt`.
