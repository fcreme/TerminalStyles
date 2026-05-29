# WT-Only Prompt/Banner Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.4.2` so a style's prompt/banner (`profile.ps1`) loads only when the current session is Windows Terminal, leaving non-WT hosts (VS Code, Visual Studio, conhost) plain instead of half-themed.

**Architecture:** Add one tiny testable predicate `Test-InWindowsTerminal` (`[bool]$env:WT_SESSION`) and gate the three places that dot-source the active style's `profile.ps1` (startup auto-load + the two apply-time reloads) on it. The dot-sources stay inline (so the profile's `function global:prompt` binding keeps working); only the guarding `if` gains the WT check. Module functions still import in every host.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-wt-only-profile-gating-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1`
  - Add `Test-InWindowsTerminal` before the `# === Public command ===` marker.
  - Gate the startup auto-load (`~:2066`), the `Apply-StyleDirect` reload (`~:698`), and the picker-confirm reload (`~:2021`) on it.
  - Reuse it for the picker's existing non-WT warning (`~:1697`) and sharpen the message.
- **Create:** `tests/Test-InWindowsTerminal.Tests.ps1`.
- **Modify:** `README.md` (Known limitations note), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** helper + test (Task 1), gating wiring (Task 2), docs/version (Task 3), publish (Task 4).

---

## Task 1: `Test-InWindowsTerminal` helper

**Files:**
- Modify: `tstyles.ps1` (add 1 function before `# === Public command ===`)
- Test: `tests/Test-InWindowsTerminal.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Test-InWindowsTerminal.Tests.ps1`:

```powershell
# Pester 5 tests for Test-InWindowsTerminal: detects the Windows Terminal host
# via $env:WT_SESSION (the gate for loading a style's prompt/banner).
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

Describe 'Test-InWindowsTerminal' {
    InModuleScope TerminalStyles {
        BeforeEach { $script:savedWT = $env:WT_SESSION }
        AfterEach  {
            if ($null -eq $script:savedWT) { Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue }
            else { $env:WT_SESSION = $script:savedWT }
        }

        It 'returns $true when WT_SESSION is set' {
            $env:WT_SESSION = 'abc-123-session'
            Test-InWindowsTerminal | Should -BeTrue
        }
        It 'returns $false when WT_SESSION is empty' {
            $env:WT_SESSION = ''
            Test-InWindowsTerminal | Should -BeFalse
        }
        It 'returns $false when WT_SESSION is not set' {
            Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
            Test-InWindowsTerminal | Should -BeFalse
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-InWindowsTerminal.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Test-InWindowsTerminal` is not defined (CommandNotFoundException).

- [ ] **Step 3: Implement the helper**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1` (use Read to locate the marker, then Edit to insert before it):

```powershell
function Test-InWindowsTerminal {
    # True when the current session is hosted by Windows Terminal (which sets
    # WT_SESSION). WT is the only host that renders a style's colors/background,
    # so the themed prompt/banner is loaded only here.
    return [bool]$env:WT_SESSION
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-InWindowsTerminal.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests, 0 failed.

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (108 total: 105 + 3 new).

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Test-InWindowsTerminal.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Test-InWindowsTerminal (WT_SESSION host predicate)

A tiny testable predicate for "is the current session Windows Terminal" --
the gate for loading a style's prompt/banner (WT is the only host that
renders the colors/background). Not wired yet; Task 2 gates the dot-sources.

Spec: docs/superpowers/specs/2026-05-29-wt-only-profile-gating-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Gate the three profile dot-source sites + reuse for the picker warning

**Files:**
- Modify: `tstyles.ps1` (4 edits: startup load, 2 apply-time loads, picker warning)

This task wires the gate into interactive/startup load paths. Per the spec, these inline dot-sources stay inline (the profile's `function global:prompt` binding must keep its scope) and are verified by module-load + review + manual check — the same model used for the picker/tuner key loops. No new automated test; Task 1's helper test covers the decision logic.

- [ ] **Step 1: Gate the startup auto-load**

In `tstyles.ps1`, find this block (near the end of the file, ~line 2066):

```powershell
# === Auto-load the currently selected style's profile.ps1 ===
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}
```

Replace it with:

```powershell
# === Auto-load the currently selected style's profile.ps1 (Windows Terminal only) ===
# Skipped outside WT: other hosts (VS Code, Visual Studio, conhost) don't render
# the style's colors/background, so loading the prompt/banner there would be a
# half-themed look. Module functions are already imported regardless.
if ((Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
    . $script:TStylesCurrent
}
```

- [ ] **Step 2: Gate both apply-time reloads (one replace-all)**

Both `Apply-StyleDirect` and the picker-confirm path reload the profile with the exact same line. Replace **all** occurrences. Find (appears twice — `~:698` and `~:2021`):

```powershell
    if ($isPwshTarget -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
```

Replace all with:

```powershell
    if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
```

(With the Edit tool, set `replace_all: true`. Verify afterward there are exactly two such lines, both now containing `(Test-InWindowsTerminal)`.)

- [ ] **Step 3: Reuse the helper for the picker's non-WT warning + sharpen the message**

Find (`~:1697`):

```powershell
    if (-not $env:WT_SESSION) {
        Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
    }
```

Replace with:

```powershell
    if (-not (Test-InWindowsTerminal)) {
        Write-Host "Note: color scheme + background only render in Windows Terminal; this host shows a plain prompt." -ForegroundColor Yellow
    }
```

- [ ] **Step 4: Verify the module parses + loads**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; if (Get-Command Test-InWindowsTerminal -EA SilentlyContinue) { 'ok: module loaded' } else { 'MISSING' }"`
Expected: `ok: module loaded` (no parse errors; a style banner from a sourced profile may print — harmless).

- [ ] **Step 5: Confirm all three sites are gated**

Run: `pwsh -NoProfile -Command "(Select-String -Path .\tstyles.ps1 -Pattern 'Test-InWindowsTerminal').Count"`
Expected: `5` — the function definition (1), the startup gate (1), the two apply-time gates (2), and the picker warning (1).

- [ ] **Step 6: Run the full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (108 total — unchanged from Task 1).

- [ ] **Step 7: Manual verification (record the result)**

The gate governs interactive/startup behavior that the suite can't drive. Confirm by reasoning + a non-WT check:
- Run: `pwsh -NoProfile -Command "$env:WT_SESSION=''; Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; & (Get-Module TerminalStyles) { (Test-InWindowsTerminal) }"`
  Expected: prints `False` (so the startup gate's first clause is false → the active profile is NOT dot-sourced).
- Inside a real Windows Terminal tab (your environment), opening a new tab still shows the active style's prompt/banner (WT path unchanged). Inside VS Code's terminal, the prompt is now plain.

- [ ] **Step 8: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Load a style's prompt/banner only in Windows Terminal

A style's colors/background apply via WT settings.json, which VS Code,
Visual Studio, and conhost ignore -- but the profile.ps1 prompt/banner
dot-sourced from $PROFILE loaded in every host, a half-themed look. Gate
the three dot-source sites (startup auto-load + both apply-time reloads) on
Test-InWindowsTerminal so the prompt/banner loads only in WT; other hosts
stay plain. Module functions still import everywhere. The picker's non-WT
warning reuses the helper and now names what's affected.

Spec: docs/superpowers/specs/2026-05-29-wt-only-profile-gating-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: README + version bump to 0.4.2

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Update the "Known limitations" note**

In `README.md`, find the Windows-Terminal-only limitation bullet:

```
- **Live preview is Windows-Terminal-only.** Other hosts (VS Code, conhost)
  don't read `settings.json`, so the menu won't show theme changes there —
  `tstyles` warns when this is the case.
```

Replace it with:

```
- **Windows-Terminal-only styling.** A style's colors, cursor, font, and
  background apply through Windows Terminal's `settings.json`, which other hosts
  (VS Code, Visual Studio, conhost) don't read. To avoid a half-themed look
  there, the style's prompt/banner (`profile.ps1`) is loaded **only** in Windows
  Terminal — non-WT hosts stay plain by design. The module's commands still work
  everywhere; the picker also warns when run outside Windows Terminal.
```

(If the exact wording of the current bullet differs slightly, Read the "Known limitations" section and replace the live-preview/WT-only bullet with the text above.)

- [ ] **Step 2: Bump the version**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.4.1'
```

Replace with:

```powershell
    ModuleVersion     = '0.4.2'
```

- [ ] **Step 3: Update ReleaseNotes**

In `TerminalStyles.psd1`, Read the current `ReleaseNotes = '...'` line (it begins `v0.4.1: bugfix ...`). Replace that entire single-quoted value with:

```powershell
            ReleaseNotes = 'v0.4.2: the themed prompt/banner now loads only in Windows Terminal. A style''s colors and background apply via WT settings.json, which VS Code / Visual Studio / conhost ignore -- so loading the prompt there produced a half-themed look. Those hosts now stay plain by design; the `tstyles` commands still work everywhere.'
```

(Preserve the `ReleaseNotes = '...'` structure and PowerShell's doubled-single-quote `''` escaping — note `style''s`.)

- [ ] **Step 4: Verify the manifest parses + version**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.4.2`; exported functions still `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

- [ ] **Step 5: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (108 total).

- [ ] **Step 6: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document WT-only prompt/banner + bump to 0.4.2

README Known limitations: the prompt/banner now loads only in Windows
Terminal (non-WT hosts stay plain by design). Manifest: ModuleVersion
0.4.1 -> 0.4.2 and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-29-wt-only-profile-gating-design.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Push + publish 0.4.2 + tag

**Files:** None modified locally. PSGallery + git remote state. **User-handled** — the PSGallery publish needs the maintainer's API key at `publish.ps1`'s hidden prompt (cannot be driven non-interactively). Tag + push are git operations the agent can do.

- [ ] **Step 1: Merge the feature branch to main + push** (per finishing-a-development-branch).

- [ ] **Step 2: Dry-run the publish (no key)**

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf
```

Expected: `Staged TerminalStyles 0.4.2 ...` + a `What if:` line. Eyeball the staged file list (allowlist only).

- [ ] **Step 3: Publish 0.4.2** (maintainer runs; hidden key prompt)

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1
```

Expected: `Published TerminalStyles 0.4.2 to PSGallery.`

- [ ] **Step 4: Verify + tag**

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 Name, Version | Format-Table"
```
Then:
```bash
git tag v0.4.2
git push origin v0.4.2
```

- [ ] **Step 5: Smoke-test**

Inside a Windows Terminal tab: open a new tab → active style's prompt/banner still loads. Inside VS Code's terminal: `Import-Module TerminalStyles -Force -DisableNameChecking` → prompt stays plain; `tstyles help` still works.

---

## Self-Review Notes

**Spec coverage:**

- `Test-InWindowsTerminal` helper -> Task 1 (def + unit test).
- Gate startup auto-load -> Task 2 Step 1.
- Gate both apply-time reloads -> Task 2 Step 2 (replace-all).
- Reuse helper for picker warning + sharpen message -> Task 2 Step 3.
- Module functions still import everywhere -> unchanged (only the dot-source `if`s gained a condition; gating is verified in Task 2 Step 5).
- README Known-limitations update -> Task 3 Step 1.
- Version 0.4.2 + ReleaseNotes -> Task 3 Steps 2-3.
- Helper unit-tested; inline dot-sources review/manual-verified -> Task 1 + Task 2 Steps 4-7 (matches the spec's testing section, incl. the optional non-WT import check).
- Publish/tag -> Task 4.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output. The only `<...>` is user-facing prose.

**Type/signature consistency:**

- `Test-InWindowsTerminal` (no params, returns `[bool]`) — defined Task 1; called in all four sites in Task 2 and in the Task 1 tests; same name everywhere.
- The two apply-time `if` lines are byte-identical, so the Task 2 Step 2 replace-all changes both to the same gated form (verified by the count check in Step 5: 5 total mentions of `Test-InWindowsTerminal`).

**Judgment calls flagged:**

- Gating uses `$env:WT_SESSION` as the sole signal (spec decision); the dot-sources stay inline to preserve the `function global:prompt` scope (confirmed by the existing comment at `tstyles.ps1:~2019`).
- The startup/apply gates are interactive/startup paths verified by review + the non-WT import check (Task 2 Step 7), consistent with how the picker/tuner are handled; the testable decision is isolated in the unit-tested helper.
