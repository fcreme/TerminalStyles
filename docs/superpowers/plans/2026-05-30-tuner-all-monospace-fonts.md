# Tuner All-Monospace-Fonts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.6.1` so `tstyles tune`'s font picker cycles every installed monospace font (curated favorites first), not just a fixed 10-font allowlist.

**Architecture:** Add a `Test-MonospaceFont` helper (glyph-width measurement via System.Drawing — equal advance width for a narrow vs wide glyph ⇒ monospace). Widen `Get-MonospaceFontList` to a three-tier list: current-first → installed favorites → all other installed monospace fonts (alphabetical), Consolas fallback. Favorites bypass measurement (always trusted). A new `-MonospaceNames` test seam (mirroring `-Installed`) keeps the ordering logic hermetically testable.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. System.Drawing (already used for font enumeration). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-30-tuner-all-monospace-fonts-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1`
  - Add `Test-MonospaceFont` (immediately before `Get-MonospaceFontList`, ~line 1056).
  - Widen `Get-MonospaceFontList` (add `-MonospaceNames` seam + measurement path + tier ordering).
- **Create:** `tests/Test-MonospaceFont.Tests.ps1`.
- **Modify:** `tests/Get-MonospaceFontList.Tests.ps1` (make existing tests hermetic via `-MonospaceNames @()`, add the new-tier tests).
- **Modify:** `README.md` (one line in "Tuning a theme"), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** helper first (Task 1, so the widened consumer's real path works), consumer + tests (Task 2), docs/version (Task 3), publish (Task 4).

---

## Task 1: `Test-MonospaceFont` helper

**Files:**
- Modify: `tstyles.ps1` (add function before `Get-MonospaceFontList`)
- Test: `tests/Test-MonospaceFont.Tests.ps1`

- [ ] **Step 1: Write the tests**

Create `tests/Test-MonospaceFont.Tests.ps1`:

```powershell
# Pester 5 tests for Test-MonospaceFont. Glyph-width measurement depends on the
# real font subsystem, so the positive/negative cases skip when the reference
# font isn't installed; the non-existent-font case is hermetic (try/catch path).
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

Describe 'Test-MonospaceFont' {
    InModuleScope TerminalStyles {
        It 'detects a known monospace font (Consolas) as monospace' {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $installed = @()
            try { $installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name } catch {}
            if ('Consolas' -notin $installed) { Set-ItResult -Skipped -Because 'Consolas not installed'; return }
            Test-MonospaceFont -FamilyName 'Consolas' | Should -BeTrue
        }
        It 'detects a known proportional font (Arial) as not monospace' {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $installed = @()
            try { $installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name } catch {}
            if ('Arial' -notin $installed) { Set-ItResult -Skipped -Because 'Arial not installed'; return }
            Test-MonospaceFont -FamilyName 'Arial' | Should -BeFalse
        }
        It 'returns $false for a non-existent font family without throwing' {
            Test-MonospaceFont -FamilyName 'No Such Font ZZZ 123' | Should -BeFalse
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-MonospaceFont.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Test-MonospaceFont` is not defined (CommandNotFoundException).

- [ ] **Step 3: Implement `Test-MonospaceFont`**

In `tstyles.ps1`, insert the following IMMEDIATELY BEFORE the `function Get-MonospaceFontList {` line (~line 1056; use Read to locate it):

```powershell
function Test-MonospaceFont {
    # True when $FamilyName renders as monospace (fixed advance width), detected
    # by measuring a narrow vs wide glyph. Pass a reusable $Graphics for speed
    # when measuring many fonts; omit it and one is created/disposed per call.
    # Any error (font not constructible, measurement fails) -> $false. Curated
    # favorites bypass this check entirely, so they're always offered.
    param(
        [Parameter(Mandatory)][string]$FamilyName,
        $Graphics
    )
    $ownGraphics = $false
    $bmp = $null
    try {
        if (-not $Graphics) {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $bmp = [System.Drawing.Bitmap]::new(1, 1)
            $Graphics = [System.Drawing.Graphics]::FromImage($bmp)
            $ownGraphics = $true
        }
        $font = [System.Drawing.Font]::new($FamilyName, 12.0)
        try {
            # GenericTypographic avoids layout padding, so the widths reflect the
            # glyph advance. Equal narrow/wide advance (within tolerance) = mono.
            $fmt = [System.Drawing.StringFormat]::GenericTypographic
            $wi = $Graphics.MeasureString('i', $font, [int]::MaxValue, $fmt).Width
            $ww = $Graphics.MeasureString('W', $font, [int]::MaxValue, $fmt).Width
            return [Math]::Abs($wi - $ww) -lt 0.5
        } finally {
            $font.Dispose()
        }
    } catch {
        return $false
    } finally {
        if ($ownGraphics) {
            if ($Graphics) { $Graphics.Dispose() }
            if ($bmp)      { $bmp.Dispose() }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-MonospaceFont.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests pass (the Consolas/Arial cases may report Skipped on a machine lacking those fonts; the non-existent-font case always passes). 0 failed.

- [ ] **Step 5: Full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (~131 total: 128 + 3 new; up to 2 may be Skipped depending on installed fonts).

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Test-MonospaceFont.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Test-MonospaceFont (glyph-width monospace detection)

Detects whether a font family is monospace by measuring a narrow ('i') vs
wide ('W') glyph advance via System.Drawing -- equal width (within tolerance)
means fixed-pitch. Any measurement error returns $false. Self-creates a
Graphics when none is passed (so it's independently testable); callers
measuring many fonts pass a reused one. Foundation for offering all installed
monospace fonts in the tuner.

Spec: docs/superpowers/specs/2026-05-30-tuner-all-monospace-fonts-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Widen `Get-MonospaceFontList`

**Files:**
- Modify: `tstyles.ps1` (`Get-MonospaceFontList`, ~line 1056 after Task 1's insert)
- Test: `tests/Get-MonospaceFontList.Tests.ps1`

- [ ] **Step 1: Update the existing tests for hermeticity + add the new-tier tests**

Replace the ENTIRE `Describe 'Get-MonospaceFontList' { ... }` block in `tests/Get-MonospaceFontList.Tests.ps1` with this (keeps the 4 existing cases — now passing `-MonospaceNames @()` so they stay favorites-only and font-subsystem-free — and adds 3 new-tier cases):

```powershell
Describe 'Get-MonospaceFontList' {
    InModuleScope TerminalStyles {
        It 'returns the allowlist intersected with installed fonts' {
            $installed = @('Consolas','JetBrains Mono','Arial','Times New Roman')
            $list = Get-MonospaceFontList -Current 'Consolas' -Installed $installed -MonospaceNames @()
            $list | Should -Contain 'Consolas'
            $list | Should -Contain 'JetBrains Mono'
            $list | Should -Not -Contain 'Arial'
        }
        It 'puts the current font first and de-duplicates' {
            $installed = @('Consolas','JetBrains Mono')
            $list = Get-MonospaceFontList -Current 'JetBrains Mono' -Installed $installed -MonospaceNames @()
            $list[0] | Should -Be 'JetBrains Mono'
            ($list | Where-Object { $_ -eq 'JetBrains Mono' }).Count | Should -Be 1
        }
        It 'includes a current font that is not on the allowlist' {
            $list = Get-MonospaceFontList -Current 'My Custom Mono' -Installed @('Consolas') -MonospaceNames @()
            $list[0] | Should -Be 'My Custom Mono'
            $list    | Should -Contain 'Consolas'
        }
        It 'falls back to Consolas when nothing intersects' {
            $list = Get-MonospaceFontList -Current '' -Installed @('Arial') -MonospaceNames @()
            $list | Should -Be @('Consolas')
        }
        It 'includes installed monospace fonts beyond the favorites' {
            $list = Get-MonospaceFontList -Current 'Consolas' `
                -Installed @('Consolas','MonoLisa','Arial') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list | Should -Contain 'MonoLisa'
            $list | Should -Not -Contain 'Arial'
        }
        It 'floats favorites above other monospace fonts, others alphabetical' {
            $list = Get-MonospaceFontList -Current '' `
                -Installed @('Consolas','Aardvark Mono','MonoLisa') `
                -MonospaceNames @('Aardvark Mono','MonoLisa','Consolas')
            $idxFav = [array]::IndexOf($list, 'Consolas')       # a favorite
            $idxA   = [array]::IndexOf($list, 'Aardvark Mono')  # non-favorite
            $idxM   = [array]::IndexOf($list, 'MonoLisa')       # non-favorite
            $idxFav | Should -BeLessThan $idxA
            $idxA   | Should -BeLessThan $idxM   # non-favorites alphabetical
        }
        It 'keeps the current font first even when it is a non-favorite monospace' {
            $list = Get-MonospaceFontList -Current 'MonoLisa' `
                -Installed @('Consolas','MonoLisa') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list[0] | Should -Be 'MonoLisa'
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify the NEW ones FAIL (and existing still pass)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-MonospaceFontList.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-MonospaceFontList` has no `-MonospaceNames` parameter yet, so every call errors (ParameterBindingException). (This confirms the seam doesn't exist; after Step 3 all 7 pass.)

- [ ] **Step 3: Widen `Get-MonospaceFontList`**

In `tstyles.ps1`, replace the ENTIRE current `Get-MonospaceFontList` function body with:

```powershell
function Get-MonospaceFontList {
    # Ordered, de-duplicated list of monospace font families to cycle in the
    # tuner: current font first, then installed curated favorites (always
    # trusted), then every OTHER installed monospace font (alphabetical),
    # Consolas fallback. -Installed and -MonospaceNames are test seams; real
    # callers omit them and we enumerate (System.Drawing) + measure
    # (Test-MonospaceFont). Curated favorites never get measured.
    param(
        [string]$Current,
        [string[]]$Installed,
        [string[]]$MonospaceNames
    )
    if (-not $Installed) {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            $Installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
        } catch {
            $Installed = @()
        }
    }

    $allow = @('Cascadia Mono','Cascadia Code','Consolas','JetBrains Mono',
               'Fira Code','Hack','Source Code Pro','DejaVu Sans Mono',
               'Lucida Console','Courier New')
    $favorites = @($allow | Where-Object { $_ -in $Installed })

    # $null means "not provided" -> measure. An explicit empty array (tests, or
    # a host without System.Drawing) means "no monospace beyond favorites".
    if ($null -eq $MonospaceNames) {
        $MonospaceNames = @()
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            $bmp = [System.Drawing.Bitmap]::new(1, 1)
            $g   = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $MonospaceNames = @($Installed | Where-Object { Test-MonospaceFont -FamilyName $_ -Graphics $g })
            } finally {
                $g.Dispose(); $bmp.Dispose()
            }
        } catch {
            $MonospaceNames = @()
        }
    }

    $others = @($MonospaceNames | Where-Object { $_ -notin $favorites } | Sort-Object)
    $list = @($favorites) + @($others)
    if (-not $list) { $list = @('Consolas') }
    if ($Current) {
        $list = @($Current) + @($list | Where-Object { $_ -ne $Current })
    }
    return @($list | Select-Object -Unique)
}
```

- [ ] **Step 4: Run the tests to verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-MonospaceFontList.Tests.ps1 -Output Detailed"`
Expected: PASS — 7 tests, 0 failed.

- [ ] **Step 5: Full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (~134 total: 131 + 3 new Get-MonospaceFontList cases).

- [ ] **Step 6: Live smoke check (real measurement path)**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; & (Get-Module TerminalStyles) { (Get-MonospaceFontList -Current 'Consolas').Count }"`
Expected: a number >= the count of installed favorites (typically several to a few dozen depending on installed fonts) — confirms the real enumerate+measure path runs without error and returns a non-trivial list. (Exact number is machine-dependent; the point is it doesn't throw and returns more than just the favorites if non-favorite monospace fonts are installed.)

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Get-MonospaceFontList.Tests.ps1
git commit -m "$(cat <<'EOF'
Offer all installed monospace fonts in the tuner

Get-MonospaceFontList now returns a three-tier list: current font first,
installed curated favorites (always trusted), then every other installed
monospace font (alphabetical, detected via Test-MonospaceFont), Consolas
fallback. A new -MonospaceNames test seam mirrors -Installed so the ordering
logic stays hermetic. Users now see their own coding fonts (Maple Mono,
MonoLisa, ...) in `tstyles tune` automatically.

Spec: docs/superpowers/specs/2026-05-30-tuner-all-monospace-fonts-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: README + version bump to 0.6.1

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Add a note to the "Tuning a theme" subsection**

In `README.md`, find this sentence in the "### Tuning a theme" subsection:

```
Opens a live editor with arrow-key sliders for **brightness**,
**saturation**, **opacity**, **font face**, and **font size**. Up/Down
selects a knob, Left/Right adjusts it, **R** resets colors, **Enter** saves,
**Esc** reverts. Colors retint instantly; opacity/font follow a beat
later (one Windows Terminal reload).
```

Insert the following sentence immediately AFTER that paragraph (as a new line within the same subsection, before the next paragraph):

```
The **font face** knob cycles every monospace font installed on your machine
(curated favorites first), so your own coding fonts show up automatically.
```

(If the exact paragraph wording differs slightly, Read the "Tuning a theme" subsection and add the sentence after the paragraph that describes the knobs.)

- [ ] **Step 2: Bump the version**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.6.0'
```

Replace with:

```powershell
    ModuleVersion     = '0.6.1'
```

- [ ] **Step 3: Update ReleaseNotes**

In `TerminalStyles.psd1`, Read the current `ReleaseNotes = '...'` line (begins `v0.6.0: ...`). Replace that entire single-quoted value with:

```powershell
            ReleaseNotes = 'v0.6.1: the `tstyles tune` font picker now cycles every installed monospace font (curated favorites first), instead of a fixed allowlist -- your own coding fonts (Maple Mono, MonoLisa, ...) show up automatically. Purely additive.'
```

(Preserve the `ReleaseNotes = '...'` structure. This value has no apostrophes needing `''` escaping; backticks are literal inside a single-quoted PS string.)

- [ ] **Step 4: Verify manifest + README**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.6.1`; exported functions `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

Run: `pwsh -NoProfile -Command "(Select-String -Path .\README.md -Pattern 'monospace font').Count"`
Expected: `1` or higher.

- [ ] **Step 5: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (~134 total).

- [ ] **Step 6: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document tuner all-monospace-fonts + bump to 0.6.1

README "Tuning a theme": note the font knob now cycles all installed
monospace fonts (favorites first). Manifest: ModuleVersion 0.6.0 -> 0.6.1
and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-30-tuner-all-monospace-fonts-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Push + publish 0.6.1 + tag

**Files:** None local. PSGallery + git remote. **User-handled** — publish needs the maintainer's API key at `publish.ps1`'s hidden prompt. Tag + push are agent-doable.

- [ ] **Step 1:** Merge the feature branch to main + push (finishing-a-development-branch).
- [ ] **Step 2:** Dry-run: `pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf` → `Staged TerminalStyles 0.6.1 ...`; eyeball staged files.
- [ ] **Step 3:** Publish (maintainer, hidden key): `pwsh -NoProfile -File .\scripts\publish.ps1` → `Published TerminalStyles 0.6.1 to PSGallery.`
- [ ] **Step 4:** Verify: `Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 Name, Version | Format-Table` → 0.6.1 newest.
- [ ] **Step 5:** Tag: `git tag v0.6.1; git push origin v0.6.1`.
- [ ] **Step 6:** Smoke-test in Windows Terminal: `tstyles tune` → the font-face knob cycles installed monospace fonts beyond the old 10 (if you have any installed).

---

## Self-Review Notes

**Spec coverage:**

- `Test-MonospaceFont` glyph-width detection (favorites bypass) → Task 1.
- Widened `Get-MonospaceFontList`: current-first → favorites → other monospace (alpha) → Consolas fallback → Task 2.
- `-MonospaceNames` test seam (mirrors `-Installed`) → Task 2.
- System.Drawing-unavailable degradation (empty MonospaceNames → favorites-only) → Task 2 (the `catch { $MonospaceNames = @() }` + the `$null`-vs-empty distinction).
- Existing guarantees preserved (current-first, favorites, dedup, Consolas fallback) → Task 2 (4 existing tests retained, now hermetic).
- README note + version 0.6.1 + ReleaseNotes → Task 3. Publish/tag → Task 4.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output (machine-dependent counts are flagged as such). The only `<...>` is user-facing prose.

**Type/signature consistency:**

- `Test-MonospaceFont -FamilyName <string> [-Graphics <obj>]` — defined Task 1; called by `Get-MonospaceFontList` (Task 2) with `-FamilyName`/`-Graphics`; tests call with `-FamilyName` only (self-creating Graphics path).
- `Get-MonospaceFontList -Current -Installed -MonospaceNames` — widened Task 2; the `$null -eq $MonospaceNames` check (NOT `-not`, so explicit `@()` is respected) is the seam contract the tests rely on.
- Test counts: Task 1 → ~131 (128 + 3, up to 2 skippable); Task 2 → ~134 (+3). Consistent.

**Judgment calls flagged:**

- `Test-MonospaceFont` self-creates a `Graphics` when none is passed (refinement over the spec's caller-must-pass version) so it's independently unit-testable; the batch caller in `Get-MonospaceFontList` still passes a reused `Graphics` for speed.
- Seam detection uses `$null -eq $MonospaceNames` (not `-not`), because an explicit `-MonospaceNames @()` (tests, or a no-monospace host) must be respected as "favorites-only", NOT trigger measurement. This differs from the `-Installed` seam's `-not` check (where empty == enumerate is acceptable). Flagged because it's a deliberate asymmetry.
- The Consolas/Arial smoke tests skip (not fail) when those fonts aren't installed, so CI stays green on minimal hosts; the hermetic non-existent-font case always runs.
