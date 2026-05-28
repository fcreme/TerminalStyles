# Live Theme Tuning (`tstyles tune`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.3.0` adding an interactive `tstyles tune [name]` subcommand that adjusts a style's brightness, saturation, opacity, font face, and font size in real time, then saves the result to the user-styles dir (Save / Save As).

**Architecture:** Five new module-private functions in `tstyles.ps1`. Pure color math (`Get-AdjustedScheme`) recomputes the scheme via HSL; an extracted `Get-SchemeOscPacket` retints the terminal instantly for color changes; opacity/font changes ride a debounced `settings.json` write through the existing `Merge-StyleIntoSettings` (fed via a throwaway "scratch" style dir, reusing the proven merge + background path). Saved styles are materialized full styles (`scheme.json`/`theme.json`/`profile.ps1`/`tune.json`) in the user dir, inheriting the base style's background. Reopening re-derives from the pristine base + remembered deltas.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. `System.Drawing` for font enumeration. No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1`
  - New internal functions (all inserted before the `# === Public command ===` marker unless noted): `Convert-HueToRgb`, `Convert-HexAdjust`, `Get-AdjustedScheme`, `Get-SchemeOscPacket`, `Get-MonospaceFontList`, `New-TunedThemeObject`, `Save-TunedStyle`, `Get-TunedBaseBackground`, `Invoke-TerminalStyleTune`.
  - Refactor the picker's inline OSC builder to call `Get-SchemeOscPacket`.
  - Extend `Get-StyleBundledBackground` + `Test-StyleResolved` with base-inheritance fallback.
  - Add a `Position=1` `$SubArg` param + a `tune` dispatch line to `Invoke-TerminalStyle`.
  - Add `'tune'` to the tab completer subcommands.
- **Create:** `tests/Get-AdjustedScheme.Tests.ps1`, `tests/Get-SchemeOscPacket.Tests.ps1`, `tests/Get-MonospaceFontList.Tests.ps1`, `tests/Save-TunedStyle.Tests.ps1`, `tests/Get-StyleBundledBackground-Inherit.Tests.ps1`, `tests/Invoke-TerminalStyleTune.Tests.ps1`, `tests/Invoke-TerminalStyle-TuneDispatch.Tests.ps1`.
- **Modify:** `README.md` (Subcommands row + "Tuning a theme" subsection), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** pure helpers first (Tasks 1–5), then the interactive loop (Task 6, defined but not dispatched), then dispatch wiring (Task 7), then docs/version (Task 8), then publish (Task 9).

---

## Task 1: Color math — `Get-AdjustedScheme` + HSL helpers

**Files:**
- Modify: `tstyles.ps1` (add 3 functions before `# === Public command ===`)
- Test: `tests/Get-AdjustedScheme.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-AdjustedScheme.Tests.ps1`:

```powershell
# Pester 5 tests for Get-AdjustedScheme (pure HSL brightness/saturation math).
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

Describe 'Get-AdjustedScheme' {
    InModuleScope TerminalStyles {
        It 'is identity for a mid-gray when both deltas are 0' {
            $s = [pscustomobject]@{ name = 't'; background = '#808080' }
            (Get-AdjustedScheme -Scheme $s -Brightness 0 -Saturation 0).background | Should -Be '#808080'
        }
        It 'brightness +100 pushes mid-gray to white' {
            $s = [pscustomobject]@{ name = 't'; background = '#808080'; red = '#808080' }
            $o = Get-AdjustedScheme -Scheme $s -Brightness 100 -Saturation 0
            $o.background | Should -Be '#ffffff'
            $o.red        | Should -Be '#ffffff'
        }
        It 'brightness -100 pushes mid-gray to black' {
            $s = [pscustomobject]@{ name = 't'; background = '#808080' }
            (Get-AdjustedScheme -Scheme $s -Brightness -100 -Saturation 0).background | Should -Be '#000000'
        }
        It 'saturation -100 turns pure red into mid-gray' {
            $s = [pscustomobject]@{ name = 't'; red = '#ff0000' }
            (Get-AdjustedScheme -Scheme $s -Brightness 0 -Saturation -100).red | Should -Be '#808080'
        }
        It 'preserves the name and any non-color properties' {
            $s = [pscustomobject]@{ name = 'eva'; tabTitle = 'X'; background = '#808080' }
            $o = Get-AdjustedScheme -Scheme $s -Brightness 50 -Saturation 0
            $o.name     | Should -Be 'eva'
            $o.tabTitle | Should -Be 'X'
        }
        It 'passes malformed hex through unchanged' {
            $s = [pscustomobject]@{ name = 't'; background = 'nothex' }
            (Get-AdjustedScheme -Scheme $s -Brightness 100 -Saturation 0).background | Should -Be 'nothex'
        }
        It 'does not mutate the input object' {
            $s = [pscustomobject]@{ name = 't'; background = '#808080' }
            $null = Get-AdjustedScheme -Scheme $s -Brightness 100 -Saturation 0
            $s.background | Should -Be '#808080'
        }
        It 'always emits 6-digit hex within range' {
            $s = [pscustomobject]@{ name = 't'; green = '#3a7a3a' }
            (Get-AdjustedScheme -Scheme $s -Brightness 80 -Saturation 80).green | Should -Match '^#[0-9a-f]{6}$'
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-AdjustedScheme.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-AdjustedScheme` is not defined (CommandNotFoundException).

- [ ] **Step 3: Implement the three functions**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Convert-HueToRgb {
    # HSL hue helper. Internal to Convert-HexAdjust.
    param([double]$P, [double]$Q, [double]$T)
    if ($T -lt 0) { $T += 1.0 }
    if ($T -gt 1) { $T -= 1.0 }
    if ($T -lt (1.0/6.0)) { return $P + ($Q - $P) * 6.0 * $T }
    if ($T -lt (1.0/2.0)) { return $Q }
    if ($T -lt (2.0/3.0)) { return $P + ($Q - $P) * ((2.0/3.0) - $T) * 6.0 }
    return $P
}

function Convert-HexAdjust {
    # hex -> RGB -> HSL -> adjust (L additive, S multiplicative) -> RGB -> hex.
    # Brightness/Saturation in -100..+100. Preserves a leading '#'. Lowercase out.
    param(
        [Parameter(Mandatory)][string]$Hex,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $hadHash = $Hex.StartsWith('#')
    $h = $Hex.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($h.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($h.Substring(4,2),16) / 255.0

    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $d = $max - $min
    if ($d -eq 0) {
        $hh = 0.0; $s = 0.0
    } else {
        $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        if     ($max -eq $r) { $hh = (($g - $b) / $d) % 6 }
        elseif ($max -eq $g) { $hh = (($b - $r) / $d) + 2 }
        else                 { $hh = (($r - $g) / $d) + 4 }
        $hh = $hh * 60.0
        if ($hh -lt 0) { $hh += 360.0 }
    }

    $l = [Math]::Max(0.0, [Math]::Min(1.0, $l + ($Brightness / 100.0) * 0.5))
    $s = [Math]::Max(0.0, [Math]::Min(1.0, $s * (1.0 + ($Saturation / 100.0))))

    if ($s -eq 0) {
        $r2 = $l; $g2 = $l; $b2 = $l
    } else {
        $q = if ($l -lt 0.5) { $l * (1.0 + $s) } else { $l + $s - $l * $s }
        $p = 2.0 * $l - $q
        $hk = $hh / 360.0
        $r2 = Convert-HueToRgb -P $p -Q $q -T ($hk + 1.0/3.0)
        $g2 = Convert-HueToRgb -P $p -Q $q -T $hk
        $b2 = Convert-HueToRgb -P $p -Q $q -T ($hk - 1.0/3.0)
    }

    $ri = [int][Math]::Round($r2 * 255.0)
    $gi = [int][Math]::Round($g2 * 255.0)
    $bi = [int][Math]::Round($b2 * 255.0)
    $out = '{0:x2}{1:x2}{2:x2}' -f $ri, $gi, $bi
    if ($hadHash) { return "#$out" } else { return $out }
}

function Get-AdjustedScheme {
    # Returns a NEW scheme object (does not mutate $Scheme) with every hex
    # color slot adjusted by the brightness/saturation deltas in HSL space.
    # Non-color props (name, etc.) pass through. Missing slots skipped;
    # malformed hex passed through unchanged.
    param(
        [Parameter(Mandatory)]$Scheme,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $slots = @('background','foreground','cursorColor','selectionBackground',
               'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite')
    $out = [pscustomobject]@{}
    foreach ($prop in $Scheme.PSObject.Properties) {
        $name = $prop.Name
        $val  = $prop.Value
        if (($name -in $slots) -and ($val -is [string]) -and ($val -match '^#?[0-9a-fA-F]{6}$')) {
            $val = Convert-HexAdjust -Hex $val -Brightness $Brightness -Saturation $Saturation
        }
        $out | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
    return $out
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-AdjustedScheme.Tests.ps1 -Output Detailed"`
Expected: PASS — 8 tests, 0 failed.

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Get-AdjustedScheme.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Get-AdjustedScheme + HSL helpers (pure color math)

Convert-HexAdjust does hex -> HSL -> adjust (L additive for brightness,
S multiplicative for saturation, both clamped) -> hex. Get-AdjustedScheme
maps it over a scheme's color slots, returning a new object; name and
non-color props pass through, malformed hex is left alone, input is not
mutated. Foundation for `tstyles tune`.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 2: Extract `Get-SchemeOscPacket` from the picker

**Files:**
- Modify: `tstyles.ps1` (add function + refactor the picker's inline OSC builder)
- Test: `tests/Get-SchemeOscPacket.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-SchemeOscPacket.Tests.ps1`:

```powershell
# Pester 5 tests for Get-SchemeOscPacket (OSC color-retint string builder,
# extracted verbatim from the picker). Locks the byte format so the picker
# refactor stays behavior-preserving.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-SchemeOscPacket' {
    InModuleScope TerminalStyles {
        It 'emits the documented OSC sequences for fg/bg/cursor/selection + palette' {
            $E = [char]27; $BEL = [char]7
            $scheme = [pscustomobject]@{
                foreground = '#ffffff'; background = '#000000'
                cursorColor = '#ff0000'; selectionBackground = '#202020'
                black = '#111111'; red = '#aa0000'
            }
            $expected = "$E]10;#ffffff$BEL" + "$E]11;#000000$BEL" +
                        "$E]12;#ff0000$BEL" + "$E]17;#202020$BEL" +
                        "$E]4;0;#111111$BEL" + "$E]4;1;#aa0000$BEL"
            Get-SchemeOscPacket -Scheme $scheme | Should -Be $expected
        }
        It 'omits slots that are absent' {
            $E = [char]27; $BEL = [char]7
            $scheme = [pscustomobject]@{ background = '#000000' }
            Get-SchemeOscPacket -Scheme $scheme | Should -Be "$E]11;#000000$BEL"
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-SchemeOscPacket.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-SchemeOscPacket` not defined.

- [ ] **Step 3: Add the function**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Get-SchemeOscPacket {
    # Returns a single string of OSC escape sequences that, when written to
    # stdout, instantly retints the terminal's fg/bg/cursor/selection + the
    # 16-color palette to $Scheme -- no settings.json write, no WT reload.
    # Extracted from the picker so the tuner reuses the exact same format.
    param([Parameter(Mandatory)]$Scheme)
    $BEL = [char]7
    $E   = [char]27
    $palette = 'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite'
    $sb = [System.Text.StringBuilder]::new()
    if ($Scheme.foreground)          { [void]$sb.Append("$E]10;$($Scheme.foreground)$BEL") }
    if ($Scheme.background)          { [void]$sb.Append("$E]11;$($Scheme.background)$BEL") }
    if ($Scheme.cursorColor)         { [void]$sb.Append("$E]12;$($Scheme.cursorColor)$BEL") }
    if ($Scheme.selectionBackground) { [void]$sb.Append("$E]17;$($Scheme.selectionBackground)$BEL") }
    for ($p = 0; $p -lt $palette.Count; $p++) {
        $color = $Scheme.($palette[$p])
        if ($color) { [void]$sb.Append("$E]4;${p};${color}$BEL") }
    }
    return $sb.ToString()
}
```

- [ ] **Step 4: Refactor the picker to call it**

In `tstyles.ps1`, find this inline block inside `Invoke-TerminalStyle` (it builds `$oscPackets`):

```powershell
        $oscPackets = @{}
        $BEL  = [char]7
        $oscEsc = [char]27
        $palette = 'black','red','green','yellow','blue','purple','cyan','white',
                   'brightBlack','brightRed','brightGreen','brightYellow',
                   'brightBlue','brightPurple','brightCyan','brightWhite'
        for ($i = 0; $i -lt $styles.Count; $i++) {
            $s = $schemes[$i]
            $sb = [System.Text.StringBuilder]::new()
            if ($s.foreground)          { [void]$sb.Append("${oscEsc}]10;$($s.foreground)$BEL") }
            if ($s.background)          { [void]$sb.Append("${oscEsc}]11;$($s.background)$BEL") }
            if ($s.cursorColor)         { [void]$sb.Append("${oscEsc}]12;$($s.cursorColor)$BEL") }
            if ($s.selectionBackground) { [void]$sb.Append("${oscEsc}]17;$($s.selectionBackground)$BEL") }
            for ($p = 0; $p -lt $palette.Count; $p++) {
                $color = $s.($palette[$p])
                if ($color) {
                    [void]$sb.Append("${oscEsc}]4;${p};${color}$BEL")
                }
            }
            $oscPackets[$i] = $sb.ToString()
        }
```

Replace the entire block with:

```powershell
        $oscPackets = @{}
        for ($i = 0; $i -lt $styles.Count; $i++) {
            $oscPackets[$i] = Get-SchemeOscPacket -Scheme $schemes[$i]
        }
```

- [ ] **Step 5: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-SchemeOscPacket.Tests.ps1 -Output Detailed"`
Expected: PASS — 2 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 6: Sanity-check the picker still loads**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; Get-Command Get-SchemeOscPacket -ErrorAction SilentlyContinue | Out-Null; 'ok: module loaded'"`
Expected: prints `ok: module loaded` (no parse errors).

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Get-SchemeOscPacket.Tests.ps1
git commit -m "$(cat <<'EOF'
Extract Get-SchemeOscPacket from the picker (shared by the tuner)

The picker built OSC color-retint packets inline. Extract that logic
verbatim into Get-SchemeOscPacket and have the picker call it, so the
upcoming `tstyles tune` reuses one copy. A parity test pins the byte
format. Behavior-preserving.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 3: `Get-MonospaceFontList`

**Files:**
- Modify: `tstyles.ps1` (add function)
- Test: `tests/Get-MonospaceFontList.Tests.ps1`

The `-Installed` parameter is a test-injection seam (mirrors the `-Targets` pattern in `Invoke-TerminalStylesRegister`): real callers omit it and the function enumerates installed fonts; tests pass a synthetic list.

- [ ] **Step 1: Write the failing test**

Create `tests/Get-MonospaceFontList.Tests.ps1`:

```powershell
# Pester 5 tests for Get-MonospaceFontList. Uses the -Installed injection
# param to bypass real System.Drawing font enumeration.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-MonospaceFontList' {
    InModuleScope TerminalStyles {
        It 'returns the allowlist intersected with installed fonts' {
            $installed = @('Consolas','JetBrains Mono','Arial','Times New Roman')
            $list = Get-MonospaceFontList -Current 'Consolas' -Installed $installed
            $list | Should -Contain 'Consolas'
            $list | Should -Contain 'JetBrains Mono'
            $list | Should -Not -Contain 'Arial'
        }
        It 'puts the current font first and de-duplicates' {
            $installed = @('Consolas','JetBrains Mono')
            $list = Get-MonospaceFontList -Current 'JetBrains Mono' -Installed $installed
            $list[0] | Should -Be 'JetBrains Mono'
            ($list | Where-Object { $_ -eq 'JetBrains Mono' }).Count | Should -Be 1
        }
        It 'includes a current font that is not on the allowlist' {
            $list = Get-MonospaceFontList -Current 'My Custom Mono' -Installed @('Consolas')
            $list[0] | Should -Be 'My Custom Mono'
            $list    | Should -Contain 'Consolas'
        }
        It 'falls back to Consolas when nothing intersects' {
            $list = Get-MonospaceFontList -Current '' -Installed @('Arial')
            $list | Should -Be @('Consolas')
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-MonospaceFontList.Tests.ps1 -Output Detailed"`
Expected: FAIL — function not defined.

- [ ] **Step 3: Add the function**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Get-MonospaceFontList {
    # Ordered, de-duplicated list of monospace font families to cycle in the
    # tuner: a curated allowlist intersected with installed fonts, with
    # $Current guaranteed present and first. -Installed is a test seam; real
    # callers omit it and we enumerate via System.Drawing.
    param(
        [string]$Current,
        [string[]]$Installed
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
    $list = @($allow | Where-Object { $_ -in $Installed })
    if (-not $list) { $list = @('Consolas') }
    if ($Current) {
        $list = @($Current) + @($list | Where-Object { $_ -ne $Current })
    }
    return @($list | Select-Object -Unique)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-MonospaceFontList.Tests.ps1 -Output Detailed"`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Get-MonospaceFontList.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Get-MonospaceFontList (curated allowlist intersect installed)

Returns the fonts the tuner cycles: a curated terminal-font allowlist
intersected with installed families (via System.Drawing), current font
first, Consolas fallback. -Installed param is a test injection seam,
matching the -Targets pattern in Invoke-TerminalStylesRegister.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 4: `New-TunedThemeObject` + `Save-TunedStyle`

**Files:**
- Modify: `tstyles.ps1` (add 2 functions)
- Test: `tests/Save-TunedStyle.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Save-TunedStyle.Tests.ps1`:

```powershell
# Pester 5 tests for Save-TunedStyle: materializes a tuned style into the
# user-styles dir (scheme.json/theme.json/profile.ps1/tune.json).
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Save-TunedStyle' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            # Build a fake base style dir with theme.json + profile.ps1.
            $script:baseDir = Join-Path $TestDrive 'base\eva'
            New-Item -ItemType Directory -Path $script:baseDir -Force | Out-Null
            $baseTheme = '{"colorScheme":"eva","opacity":100,"font":{"face":"Cascadia Code","size":11,"weight":"semi-bold"},"backgroundImage":"{{BACKGROUND_IMAGE}}"}'
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'theme.json'), $baseTheme, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'profile.ps1'), '# eva profile', [System.Text.UTF8Encoding]::new($false))
            $script:adjusted = [pscustomobject]@{ name = 'eva'; background = '#000000'; red = '#aa0000' }
        }

        It 'writes the four files with the save name as scheme name and colorScheme' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-night' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness -15 -Saturation 10 -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 12

            $dir = Join-Path $TestDrive 'styles\eva-night'
            Test-Path (Join-Path $dir 'scheme.json')  | Should -BeTrue
            Test-Path (Join-Path $dir 'theme.json')   | Should -BeTrue
            Test-Path (Join-Path $dir 'profile.ps1')  | Should -BeTrue
            Test-Path (Join-Path $dir 'tune.json')    | Should -BeTrue

            $scheme = Get-Content (Join-Path $dir 'scheme.json') -Raw | ConvertFrom-Json
            $scheme.name | Should -Be 'eva-night'

            $theme = Get-Content (Join-Path $dir 'theme.json') -Raw | ConvertFrom-Json
            $theme.colorScheme | Should -Be 'eva-night'
            $theme.opacity     | Should -Be 85
            $theme.font.face   | Should -Be 'JetBrains Mono'
            $theme.font.size   | Should -Be 12
            $theme.font.weight | Should -Be 'semi-bold'   # preserved from base
            $theme.backgroundImage | Should -Be '{{BACKGROUND_IMAGE}}'  # placeholder kept
        }

        It 'round-trips the deltas in tune.json with the base name' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-night' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness -15 -Saturation 10 -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 12
            $tune = Get-Content (Join-Path $TestDrive 'styles\eva-night\tune.json') -Raw | ConvertFrom-Json
            $tune.schemaVersion | Should -Be 1
            $tune.base          | Should -Be 'eva'
            $tune.brightness    | Should -Be -15
            $tune.saturation    | Should -Be 10
            $tune.opacity       | Should -Be 85
            $tune.fontFace      | Should -Be 'JetBrains Mono'
            $tune.fontSize      | Should -Be 12
        }

        It 'overwrite (same name) writes into the base name folder' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness 5 -Saturation 0 -Opacity 100 -FontFace 'Consolas' -FontSize 11
            Test-Path (Join-Path $TestDrive 'styles\eva\scheme.json') | Should -BeTrue
            (Get-Content (Join-Path $TestDrive 'styles\eva\scheme.json') -Raw | ConvertFrom-Json).name | Should -Be 'eva'
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Save-TunedStyle.Tests.ps1 -Output Detailed"`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Add the functions**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function New-TunedThemeObject {
    # Builds the theme.json object for a tuned style: base theme.json (or {})
    # with colorScheme/opacity/font overridden. Preserves font.weight and the
    # backgroundImage placeholder. Shared by Save-TunedStyle and the live
    # preview so the saved result matches what was previewed.
    param(
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$ColorScheme,
        [int]$Opacity,
        [string]$FontFace,
        [int]$FontSize
    )
    $themeSrc = Join-Path $BaseStyleDir 'theme.json'
    $theme = if (Test-Path -LiteralPath $themeSrc) {
        [System.IO.File]::ReadAllText($themeSrc, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } else { [pscustomobject]@{} }

    $theme | Add-Member -NotePropertyName colorScheme -NotePropertyValue $ColorScheme -Force
    $theme | Add-Member -NotePropertyName opacity     -NotePropertyValue $Opacity     -Force

    $font = if ($theme.PSObject.Properties.Match('font').Count) { $theme.font } else { [pscustomobject]@{} }
    $font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
    $font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize -Force
    $theme | Add-Member -NotePropertyName font -NotePropertyValue $font -Force
    return $theme
}

function Save-TunedStyle {
    # Materializes a tuned style into $DataRoot\styles\$SaveName\:
    #   scheme.json (adjusted colors, name = $SaveName)
    #   theme.json  (base theme + colorScheme/opacity/font overrides)
    #   profile.ps1 (copied from base if present)
    #   tune.json   (deltas + base name, for re-tuning)
    param(
        [Parameter(Mandatory)]$AdjustedScheme,
        [Parameter(Mandatory)][string]$SaveName,
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$BaseName,
        [int]$Brightness, [int]$Saturation, [int]$Opacity,
        [string]$FontFace, [int]$FontSize
    )
    $destDir = Join-Path $script:TStylesDataRoot "styles\$SaveName"
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $AdjustedScheme | Add-Member -NotePropertyName name -NotePropertyValue $SaveName -Force
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'scheme.json'),
        ($AdjustedScheme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $theme = New-TunedThemeObject -BaseStyleDir $BaseStyleDir -ColorScheme $SaveName `
        -Opacity $Opacity -FontFace $FontFace -FontSize $FontSize
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'theme.json'),
        ($theme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $profileSrc = Join-Path $BaseStyleDir 'profile.ps1'
    if (Test-Path -LiteralPath $profileSrc) {
        Copy-Item -LiteralPath $profileSrc -Destination (Join-Path $destDir 'profile.ps1') -Force
    }

    $tune = [pscustomobject]@{
        schemaVersion = 1
        base          = $BaseName
        brightness    = $Brightness
        saturation    = $Saturation
        opacity       = $Opacity
        fontFace      = $FontFace
        fontSize      = $FontSize
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'tune.json'),
        ($tune | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false))

    return $destDir
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Save-TunedStyle.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Save-TunedStyle.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Save-TunedStyle + New-TunedThemeObject

Save-TunedStyle materializes a tuned style into the user-styles dir:
scheme.json (adjusted, name = save name), theme.json (base + colorScheme/
opacity/font overrides via the shared New-TunedThemeObject; font.weight
and the {{BACKGROUND_IMAGE}} placeholder preserved), profile.ps1 copied
from base, and tune.json recording deltas + base for re-tuning.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 5: Background inheritance for tuned styles

**Files:**
- Modify: `tstyles.ps1` (`Get-TunedBaseBackground` + edits to `Get-StyleBundledBackground` and `Test-StyleResolved`)
- Test: `tests/Get-StyleBundledBackground-Inherit.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-StyleBundledBackground-Inherit.Tests.ps1`:

```powershell
# Pester 5 tests for tuned-style background inheritance: a style whose
# tune.json names a base with no background of its own resolves the base's.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-StyleBundledBackground inheritance' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            # Bundled base 'eva' with a scheme.json (so Get-StyleDir resolves it)
            # and a background.gif.
            $evaDir = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $evaDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $evaDir 'scheme.json'), '{"name":"eva"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $evaDir 'background.gif'), 'GIFDATA', [System.Text.UTF8Encoding]::new($false))
            # Tuned 'eva-night' in the user dir: scheme + tune.json (base=eva), no bg.
            $script:nightDir = Join-Path $script:TStylesDataRoot 'styles\eva-night'
            New-Item -ItemType Directory -Path $script:nightDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'scheme.json'), '{"name":"eva-night"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'tune.json'), '{"base":"eva"}', [System.Text.UTF8Encoding]::new($false))
        }

        It 'resolves the base background for a tuned style with none of its own' {
            $bg = Get-StyleBundledBackground -StyleDir $script:nightDir
            $bg | Should -Match 'styles[\\/]eva[\\/]background\.gif$'
        }

        It 'reports a tuned style as resolved when its base is resolved' {
            Test-StyleResolved -StyleDir $script:nightDir | Should -BeTrue
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-StyleBundledBackground-Inherit.Tests.ps1 -Output Detailed"`
Expected: FAIL — `eva-night` has no background and the inheritance fallback doesn't exist yet (the function attempts a lazy-fetch of `eva-night` and returns `$null`).

- [ ] **Step 3: Add `Get-TunedBaseBackground`**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Get-TunedBaseBackground {
    # If $StyleDir is a tuned style (tune.json with a 'base'), resolve and
    # return the base style's background. $null if not tuned / base missing /
    # base has no background. One hop only (guards self-reference).
    param([Parameter(Mandatory)][string]$StyleDir)
    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (-not (Test-Path -LiteralPath $tuneFile)) { return $null }
    try {
        $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return $null }
    if (-not $tune.base) { return $null }
    $baseDir = Get-StyleDir -StyleName $tune.base
    if (-not $baseDir -or ($baseDir -eq $StyleDir)) { return $null }
    return Get-StyleBundledBackground -StyleDir $baseDir
}
```

- [ ] **Step 4: Wire inheritance into `Get-StyleBundledBackground`**

In `Get-StyleBundledBackground`, find the negative-cache check that precedes the lazy-fetch:

```powershell
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch into cache
```

Replace it with (insert the inheritance check before the negative-cache return):

```powershell
    # 2b. Inheritance: a tuned style inherits its base's background. For a
    # non-tuned style this returns $null instantly (no tune.json), so the
    # normal path is unaffected.
    $inherited = Get-TunedBaseBackground -StyleDir $StyleDir
    if ($inherited) { return $inherited }

    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch into cache
```

- [ ] **Step 5: Wire inheritance into `Test-StyleResolved`**

In `Test-StyleResolved`, find the final fallthrough:

```powershell
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }
    return $false
}
```

Replace with:

```powershell
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }

    # Tuned styles inherit resolution from their base.
    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (Test-Path -LiteralPath $tuneFile) {
        try {
            $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($tune.base) {
                $baseDir = Get-StyleDir -StyleName $tune.base
                if ($baseDir -and ($baseDir -ne $StyleDir)) {
                    return (Test-StyleResolved -StyleDir $baseDir)
                }
            }
        } catch { }
    }
    return $false
}
```

- [ ] **Step 6: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-StyleBundledBackground-Inherit.Tests.ps1 -Output Detailed"`
Expected: PASS — 2 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Get-StyleBundledBackground-Inherit.Tests.ps1
git commit -m "$(cat <<'EOF'
Tuned styles inherit their base style's background

Get-TunedBaseBackground reads a style's tune.json and, when it names a
base, resolves the base's background. Wired into Get-StyleBundledBackground
(before lazy-fetch, so a tuned style shows its base's GIF instead of
404-ing on its own name) and Test-StyleResolved (so the picker doesn't
show "...fetching" forever for tuned styles). No-op for non-tuned styles.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 6: `Invoke-TerminalStyleTune` (the interactive loop)

**Files:**
- Modify: `tstyles.ps1` (add the function — NOT dispatched yet)
- Test: `tests/Invoke-TerminalStyleTune.Tests.ps1` (guard paths only; the key loop is manual, like the picker)

The function performs ALL validation/error returns before any `[Console]` interaction, so the guard tests never enter the key loop.

- [ ] **Step 1: Write the failing test**

Create `tests/Invoke-TerminalStyleTune.Tests.ps1`:

```powershell
# Pester 5 tests for Invoke-TerminalStyleTune guard paths (pre-loop).
# The interactive key loop itself is verified manually (like the picker).
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Invoke-TerminalStyleTune guards' {
    InModuleScope TerminalStyles {
        It 'errors when no style name is given and no active style exists' {
            Mock Get-CurrentStyleName { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'No active style' }
        }
        It 'errors when the named style cannot be resolved' {
            Mock Get-StyleDir { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune -StyleName 'nope'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match "not found" }
        }
        It 'errors when settings.json cannot be located' {
            Mock Get-StyleDir { $TestDrive }
            Mock Find-WTSettingsPath { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            # Provide a scheme.json so the base load would succeed past resolution.
            [System.IO.File]::WriteAllText((Join-Path $TestDrive 'scheme.json'), '{"name":"x"}', [System.Text.UTF8Encoding]::new($false))
            Invoke-TerminalStyleTune -StyleName 'x'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'settings.json' }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyleTune.Tests.ps1 -Output Detailed"`
Expected: FAIL — function not defined.

- [ ] **Step 3: Add the function**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Invoke-TerminalStyleTune {
    # `tstyles tune [name]` -- interactive live tuning of a style's brightness,
    # saturation, opacity, font face, and font size. Colors retint instantly
    # via OSC; opacity/font ride a debounced settings.json write (through a
    # scratch style dir reusing Merge-StyleIntoSettings). Esc reverts byte-
    # exact; Enter prompts Save / Save As into the user-styles dir.
    [CmdletBinding()]
    param([string]$StyleName)

    Show-UpdateNoticeIfAvailable

    # --- Resolve the style (all guards run BEFORE any console interaction) ---
    if (-not $StyleName) {
        $StyleName = Get-CurrentStyleName
        if (-not $StyleName) {
            Write-Error "No active style detected. Try: tstyles tune <name>"
            return
        }
    }
    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    # --- Establish working base scheme + seed knob values ---
    # If this style is itself a tuned style (has tune.json), the working base
    # is its recorded base's PRISTINE scheme, and knobs seed from the deltas
    # (so re-deriving never double-applies onto the baked file). Otherwise the
    # working base is this style's own scheme with neutral knobs.
    $brightness = 0; $saturation = 0
    $opacity = 100; $fontFace = $null; $fontSize = 12
    $baseName = $StyleName
    $baseDir  = $styleDir

    $tuneFile = Join-Path $styleDir 'tune.json'
    if (Test-Path -LiteralPath $tuneFile) {
        try {
            $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($tune.base) {
                $resolvedBaseDir = Get-StyleDir -StyleName $tune.base
                if ($resolvedBaseDir) {
                    $baseName = $tune.base
                    $baseDir  = $resolvedBaseDir
                    $brightness = [int]$tune.brightness
                    $saturation = [int]$tune.saturation
                    $opacity    = [int]$tune.opacity
                    $fontFace   = [string]$tune.fontFace
                    $fontSize   = [int]$tune.fontSize
                }
            }
        } catch { }
    }

    $baseScheme = [System.IO.File]::ReadAllText((Join-Path $baseDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    # Seed font/opacity from the base theme.json when not already set from tune.json.
    $baseThemePath = Join-Path $baseDir 'theme.json'
    $baseTheme = if (Test-Path -LiteralPath $baseThemePath) {
        [System.IO.File]::ReadAllText($baseThemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } else { $null }
    if (-not (Test-Path -LiteralPath $tuneFile)) {
        if ($baseTheme) {
            if ($baseTheme.PSObject.Properties.Match('opacity').Count) { $opacity = [int]$baseTheme.opacity }
            if ($baseTheme.PSObject.Properties.Match('font').Count) {
                if ($baseTheme.font.PSObject.Properties.Match('face').Count) { $fontFace = [string]$baseTheme.font.face }
                if ($baseTheme.font.PSObject.Properties.Match('size').Count) { $fontSize = [int]$baseTheme.font.size }
            }
        }
    }

    $fontList = Get-MonospaceFontList -Current $fontFace
    if (-not $fontFace) { $fontFace = $fontList[0] }
    $fontIdx = [Math]::Max(0, [array]::IndexOf($fontList, $fontFace))

    # --- Target WT profile ---
    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $originalSettings = $originalJson | ConvertFrom-Json
    $target = Get-CurrentWTProfileName -Settings $originalSettings
    if (-not $target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to preview against."
        return
    }
    if (-not $env:WT_SESSION) {
        Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
    }

    # --- Scratch dir for the debounced settings.json preview (reuses Merge) ---
    $scratchDir = Join-Path $script:TStylesDataRoot ".tune-preview\$baseName"
    if (-not (Test-Path -LiteralPath $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }

    # Knob model: index 0..4 = brightness, saturation, opacity, font face, size.
    $knobs = @('Brightness','Saturation','Opacity','Font face','Font size')
    $sel = 0
    $confirmed = $false
    $pendingApply = $true   # apply once up front so the preview reflects seeds

    $hint  = "$([char]27)[38;2;160;160;160m"
    $reset = "$([char]27)[0m"

    # Recompute the adjusted scheme + cache its OSC packet.
    $adjusted   = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
    $oscPacket  = Get-SchemeOscPacket -Scheme $adjusted

    $writePreview = {
        # Write scratch scheme/theme then merge into settings.json (brings
        # opacity/font/background live). Colors are already shown via OSC.
        $adj = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        $adj | Add-Member -NotePropertyName name -NotePropertyValue $baseScheme.name -Force
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'scheme.json'),
            ($adj | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        $theme = New-TunedThemeObject -BaseStyleDir $baseDir -ColorScheme $baseScheme.name `
            -Opacity $opacity -FontFace $fontFace -FontSize $fontSize
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'theme.json'),
            ($theme | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        # tune.json so background inheritance resolves the base GIF in preview.
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'tune.json'),
            ('{"base":"' + $baseName + '"}'), [System.Text.UTF8Encoding]::new($false))

        $preview = $originalJson | ConvertFrom-Json
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $scratchDir `
            -TargetName $target -BackgroundImage '' -BackgroundImageProvided $false
        [System.IO.File]::WriteAllText($settingsPath, ($preview | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))
    }

    $bar = {
        param([int]$Value, [int]$Min, [int]$Max)
        $width = 10
        $pos = [int][Math]::Round(($Value - $Min) / [double]($Max - $Min) * ($width - 1))
        $pos = [Math]::Max(0, [Math]::Min($width - 1, $pos))
        $cells = (1..$width | ForEach-Object { if (($_ - 1) -eq $pos) { 'o' } else { '-' } }) -join ''
        return "[$cells]"
    }

    $drawMenu = {
        Clear-Host
        Write-Host ""
        Write-Host "  Tuning " -NoNewline
        Write-Host "'$StyleName'" -ForegroundColor Cyan -NoNewline
        Write-Host "                      base: $baseName" -ForegroundColor DarkGray
        Write-Host "$hint  Up/Down select   Left/Right adjust   R reset   Enter save   Esc cancel$reset"
        Write-Host ""
        $rows = @(
            @{ Label = 'Brightness'; Display = (& $bar $brightness -100 100); Value = ('{0:+#;-#;0}' -f $brightness) },
            @{ Label = 'Saturation'; Display = (& $bar $saturation -100 100); Value = ('{0:+#;-#;0}' -f $saturation) },
            @{ Label = 'Opacity';    Display = (& $bar $opacity 0 100);       Value = "$opacity%" },
            @{ Label = 'Font face';  Display = "< $fontFace >";                Value = '' },
            @{ Label = 'Font size';  Display = (& $bar $fontSize 6 36);        Value = "$fontSize" }
        )
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $color  = if ($i -eq $sel) { 'Yellow' } else { 'Gray' }
            $prefix = if ($i -eq $sel) { '   > ' } else { '     ' }
            Write-Host ($prefix + ('{0,-12} ' -f $rows[$i].Label) + ('{0,-14} ' -f $rows[$i].Display) + $rows[$i].Value) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  Preview  " -NoNewline
        Write-Host (Get-SchemeSwatch -Scheme $adjusted)
        Write-Host ""
    }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle
    $needsRedraw = $true
    try {
        & $writePreview   # initial preview from seeds
        [Console]::Out.Write($oscPacket)

        while (-not $confirmed) {
            if ($needsRedraw) { & $drawMenu; $needsRedraw = $false }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $isColor = ($sel -eq 0 -or $sel -eq 1)
                switch ($key.Key) {
                    'UpArrow'   { if ($sel -gt 0) { $sel-- }; $needsRedraw = $true; continue }
                    'DownArrow' { if ($sel -lt 4) { $sel++ }; $needsRedraw = $true; continue }
                    'LeftArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Max(-100, $brightness - 5) }
                            1 { $saturation = [Math]::Max(-100, $saturation - 5) }
                            2 { $opacity    = [Math]::Max(0,    $opacity - 5) }
                            3 { $fontIdx = ($fontIdx - 1 + $fontList.Count) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Max(6, $fontSize - 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'RightArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Min(100, $brightness + 5) }
                            1 { $saturation = [Math]::Min(100, $saturation + 5) }
                            2 { $opacity    = [Math]::Min(100, $opacity + 5) }
                            3 { $fontIdx = ($fontIdx + 1) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Min(36, $fontSize + 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'R' {
                        $brightness = 0; $saturation = 0
                        $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness 0 -Saturation 0
                        $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                        [Console]::Out.Write($oscPacket)
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'Enter'  { if ($pendingApply) { & $writePreview; $pendingApply = $false }; $confirmed = $true; continue }
                    'Escape' {
                        [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
                        Clear-Host
                        Write-Host "Reverted." -ForegroundColor Yellow
                        return
                    }
                }
                continue
            }

            if ($pendingApply) { $pendingApply = $false; & $writePreview; continue }
            Start-Sleep -Milliseconds 50
        }

        # --- Confirmed: Save / Save As prompt ---
        Clear-Host
        Write-Host ""
        Write-Host "  Save tuned '$StyleName'?" -ForegroundColor Cyan
        Write-Host "    [1] Overwrite '$StyleName'   (shadows the bundled style)"
        Write-Host "    [2] Save as a new name"
        Write-Host ""
        $choice = (Read-Host "  Choose [1/2]").Trim()
        $saveName = $null
        if ($choice -eq '1') {
            $saveName = $StyleName
        } else {
            while (-not $saveName) {
                $candidate = (Read-Host "  New style name").Trim()
                if (-not $candidate) { Write-Host "  Cancelled." -ForegroundColor Gray; break }
                if ($candidate -notmatch '^[A-Za-z0-9._-]+$') {
                    Write-Host "  Use letters, digits, dot, underscore, or hyphen only." -ForegroundColor Yellow
                    continue
                }
                $bundledDir = Join-Path $script:TStylesModuleRoot "styles\$candidate"
                if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) {
                    $warn = (Read-Host "  That shadows bundled '$candidate'. Continue? [y/N]").Trim()
                    if ($warn -notmatch '^(?i)y') { continue }
                }
                $saveName = $candidate
            }
        }

        if (-not $saveName) {
            # Treat an aborted save like a cancel: revert and exit.
            [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Reverted (nothing saved)." -ForegroundColor Yellow
            return
        }

        # Bake + persist, then apply the saved style from a clean settings.json
        # so no preview-scheme pollution lingers.
        $finalScheme = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        Save-TunedStyle -AdjustedScheme $finalScheme -SaveName $saveName `
            -BaseStyleDir $baseDir -BaseName $baseName `
            -Brightness $brightness -Saturation $saturation -Opacity $opacity `
            -FontFace $fontFace -FontSize $fontSize | Out-Null

        [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
        Apply-StyleDirect -StyleName $saveName -Target $target
    } finally {
        [Console]::CursorVisible = $true
        if (-not $confirmed) { $Host.UI.RawUI.WindowTitle = $originalTitle }
        if (Test-Path -LiteralPath $scratchDir) {
            Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] **Step 4: Run the guard tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyleTune.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests (guard paths return before the key loop).

- [ ] **Step 5: Run the full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyleTune.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Invoke-TerminalStyleTune (interactive live tuning loop)

The `tstyles tune` engine: arrow-key sliders for brightness, saturation,
opacity, font face, and font size. Color knobs retint instantly via OSC;
opacity/font ride a debounced settings.json write fed by a scratch style
dir (reusing Merge-StyleIntoSettings + background inheritance). Esc reverts
byte-exact; Enter prompts Save / Save As; reopening a tuned style re-derives
from the pristine base + tune.json deltas. Not dispatched from the CLI yet
-- Task 7 wires it. Guard paths (no style / not found / no settings.json)
are unit-tested; the key loop is manual, like the picker.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 7: Wire `tune` into dispatch + tab completer

**Files:**
- Modify: `tstyles.ps1` (param block + dispatch line + completer)
- Test: `tests/Invoke-TerminalStyle-TuneDispatch.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Invoke-TerminalStyle-TuneDispatch.Tests.ps1`:

```powershell
# Pester 5 tests: `tstyles tune <name>` routes to Invoke-TerminalStyleTune
# with the right style name, and the tab completer offers 'tune'.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'tstyles tune dispatch' {
    InModuleScope TerminalStyles {
        It 'routes `tune <name>` to Invoke-TerminalStyleTune with the style name' {
            Mock Invoke-TerminalStyleTune {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'tune' -SubArg 'eva'
            Should -Invoke Invoke-TerminalStyleTune -Times 1 -ParameterFilter { $StyleName -eq 'eva' }
        }
        It 'routes bare `tune` with no name' {
            Mock Invoke-TerminalStyleTune {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'tune'
            Should -Invoke Invoke-TerminalStyleTune -Times 1
        }
    }
}

Describe 'tstyles tune tab completion' {
    It "offers 'tune' as a subcommand" {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $matches = (TabExpansion2 -inputScript 'tstyles tun' -cursorColumn 11).CompletionMatches.CompletionText
        $matches | Should -Contain 'tune'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-TuneDispatch.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Invoke-TerminalStyle` has no `-SubArg` param (and/or `tune` not dispatched / not completed).

- [ ] **Step 3: Add the `$SubArg` param**

In `Invoke-TerminalStyle`, find the `$Arg` parameter declaration:

```powershell
        [Parameter(Position=0)]
        [string]$Arg,
        # Explicit Windows Terminal profile to apply to (defaults to the
        # current tab's profile via $env:WT_PROFILE_ID).
        [string]$Target,
```

Replace with:

```powershell
        [Parameter(Position=0)]
        [string]$Arg,
        # Second positional: a style name for `tstyles tune <name>`. Backward-
        # compatible -- existing single-positional usage binds to $Arg only.
        [Parameter(Position=1)]
        [string]$SubArg,
        # Explicit Windows Terminal profile to apply to (defaults to the
        # current tab's profile via $env:WT_PROFILE_ID).
        [string]$Target,
```

- [ ] **Step 4: Add the dispatch line**

Find the subcommand dispatch block:

```powershell
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
```

Insert the `tune` line between them:

```powershell
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
```

- [ ] **Step 5: Add `'tune'` to the tab completer**

Find:

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'update', 'uninstall')
```

Replace with:

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'tune', 'update', 'uninstall')
```

- [ ] **Step 6: Run the test + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-TuneDispatch.Tests.ps1 -Output Detailed"`
Expected: PASS — 3 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyle-TuneDispatch.Tests.ps1
git commit -m "$(cat <<'EOF'
Wire `tstyles tune` into dispatch + tab completer

Adds a Position=1 $SubArg param (backward-compatible) so `tstyles tune eva`
parses, one dispatch line routing to Invoke-TerminalStyleTune, and 'tune'
in the completer's subcommand list. After this commit `tstyles tune` works
end-to-end.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 8: README + version bump to 0.3.0

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Add the `tstyles tune` row to the Subcommands listing**

In `README.md`, find:

```powershell
tstyles random                    # Pick a random style and apply it
tstyles register                  # Auto-add `Import-Module TerminalStyles ...` to both $PROFILE files
```

Replace with:

```powershell
tstyles random                    # Pick a random style and apply it
tstyles tune [name]               # Live-tune brightness/saturation/opacity/font; save as a style
tstyles register                  # Auto-add `Import-Module TerminalStyles ...` to both $PROFILE files
```

- [ ] **Step 2: Add a "Tuning a theme" subsection**

In `README.md`, find the end of the `### Subcommands` block (the line about tab completion):

```
Tab completion works on the subcommand and style names:
`tstyles u<TAB>` cycles `umbrella`, `uninstall`, `update`.
```

Immediately after it, insert:

```markdown

### Tuning a theme

```powershell
tstyles tune            # tune the active style
tstyles tune eva        # tune a specific style
```

Opens a live editor with arrow-key sliders for **brightness**,
**saturation**, **opacity**, **font face**, and **font size**. Up/Down
selects a knob, Left/Right adjusts it, **R** resets, **Enter** saves,
**Esc** reverts. Colors retint instantly; opacity/font follow a beat
later (one Windows Terminal reload).

On save you choose **Overwrite** (shadows the theme you tuned) or **Save
as** a new name. The result lands in your user-styles dir as a full style
— so it shows up in `tstyles list`, the picker, and tab-completion, and
survives updates. It inherits the base theme's background, and a small
`tune.json` remembers your adjustments so `tstyles tune <name>` resumes
where you left off.
```

- [ ] **Step 3: Bump the version + ReleaseNotes**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.2.2'
```

Replace with:

```powershell
    ModuleVersion     = '0.3.0'
```

Then find:

```powershell
            ReleaseNotes = 'v0.2.2: new `tstyles register` subcommand auto-writes the Import-Module loader to both PowerShell engines'' $PROFILE files (with a confirm prompt). Closes the manual-edit gap for PSGallery installs. Idempotent; -Force replaces. Purely additive -- existing behavior unchanged.'
```

Replace with:

```powershell
            ReleaseNotes = 'v0.3.0: new `tstyles tune [name]` subcommand -- live, arrow-key tuning of a style''s brightness, saturation, opacity, font face, and font size. Colors retint instantly; Enter saves the result to your user-styles dir (Overwrite or Save As) as a full style that inherits the base background and remembers its adjustments. Purely additive -- existing behavior unchanged.'
```

- [ ] **Step 4: Verify the manifest parses + version**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.3.0`; exported functions still `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

- [ ] **Step 5: Verify README mentions**

Run: `pwsh -NoProfile -Command "(Select-String -Path .\README.md -Pattern 'tstyles tune').Count"`
Expected: `3` (Subcommands row + two in the new subsection's code block) or higher — at least 3.

- [ ] **Step 6: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document `tstyles tune` + bump to 0.3.0

README: Subcommands row + a "Tuning a theme" subsection. Manifest:
ModuleVersion 0.2.2 -> 0.3.0 and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-28-live-theme-tuning-design.md
EOF
)"
```

---

## Task 9: Push + publish 0.3.0 + smoke-test + tag

**Files:** None modified locally. PSGallery + git remote state changes. Controller-handled (needs the API key for publish).

- [ ] **Step 1: Confirm clean tree + push**

```bash
git status
git log --oneline origin/main..HEAD
git push origin main
```

Expected: working tree clean; 8 commits ahead (Tasks 1–8); push succeeds.

- [ ] **Step 2: Publish 0.3.0**

```powershell
pwsh -NoProfile -File ./scripts/publish.ps1 -ApiKey '<the-api-key>'
```

Expected:

```
Staged TerminalStyles 0.3.0 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

Published TerminalStyles 0.3.0 to PSGallery.
Verify at: https://www.powershellgallery.com/packages/TerminalStyles/0.3.0
```

- [ ] **Step 3: Verify on PSGallery**

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 | Format-Table Name, Version"
```

Expected: `0.3.0` newest, with `0.2.2`, `0.2.1`, `0.2.0` still present.

- [ ] **Step 4: Smoke-test from a clean shell**

```powershell
pwsh -NoProfile -Command "Update-PSResource -Name TerminalStyles -TrustRepository; Import-Module TerminalStyles -Force -DisableNameChecking; (Get-Module TerminalStyles).Version; TabExpansion2 -inputScript 'tstyles tun' -cursorColumn 11 | ForEach-Object CompletionMatches | ForEach-Object CompletionText"
```

Expected: `0.3.0`; completion includes `tune`.

Then interactively (inside Windows Terminal): `tstyles tune eva` → adjust each knob (confirm colors retint instantly, opacity/font after a beat), Save As `eva-night`, verify it appears in `tstyles list`, shows eva's background, and `tstyles tune eva-night` resumes the sliders.

- [ ] **Step 5: Tag v0.3.0**

```bash
git tag v0.3.0
git push --tags
```

Expected: `* [new tag]  v0.3.0 -> v0.3.0`.

---

## Self-Review Notes

**Spec coverage:**

- `tstyles tune` / `tstyles tune <name>` → Task 6 (function) + Task 7 (dispatch).
- Five knobs (brightness/saturation/opacity/font face/size) → Task 6 (knob model + Left/Right handlers).
- Two-channel preview (OSC colors + debounced settings.json for opacity/font) → Task 6 (`writePreview` scratch-merge + OSC on color knobs) using Task 2's `Get-SchemeOscPacket`.
- HSL brightness/saturation math → Task 1.
- Esc byte-exact revert + R reset → Task 6 (Escape branch restores `$originalJson`; `R` zeroes color deltas).
- Save / Save As into user dir → Task 6 (prompt) + Task 4 (`Save-TunedStyle`).
- `tune.json` remembers deltas; reopen re-derives from pristine base + deltas → Task 6 (seed block) + Task 4 (tune.json write).
- Materialized style appears in list/picker/completion → Task 4 writes a full style to the user dir (existing `Get-AvailableStyles` machinery picks it up); Task 7 adds completer entry for the subcommand.
- Background inheritance → Task 5.
- Scheme `name` uniqueness / `colorScheme` rewrite → Task 4 (`Save-TunedStyle` sets scheme `name` and `New-TunedThemeObject` sets `colorScheme` to the save name).
- Extract shared OSC helper → Task 2.
- Error handling (no style / not found / no settings.json / not in WT / save failure) → Task 6 guards + Task 6 tests (first three). "Not in WT" warns; save-failure surfaces via `Apply-StyleDirect`/`Save-TunedStyle` errors (non-fatal to the session look since preview already applied).
- Version bump + README → Task 8. Publish/tag → Task 9.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output. The only `<...>` is `<the-api-key>` in Task 9 Step 2 (a real secret the controller supplies) and `<name>` in user-facing prose.

**Type/signature consistency:**

- `Get-AdjustedScheme -Scheme -Brightness -Saturation` — same signature in Task 1 def, Task 6 calls, and the parity with `Convert-HexAdjust`.
- `Get-SchemeOscPacket -Scheme` — Task 2 def + Task 6 calls + Task 2 picker refactor.
- `Get-MonospaceFontList -Current -Installed` — Task 3 def + Task 6 call (`-Current` only).
- `Save-TunedStyle -AdjustedScheme -SaveName -BaseStyleDir -BaseName -Brightness -Saturation -Opacity -FontFace -FontSize` — Task 4 def + Task 6 call (identical param set).
- `New-TunedThemeObject -BaseStyleDir -ColorScheme -Opacity -FontFace -FontSize` — Task 4 def + used by `Save-TunedStyle` and Task 6 `writePreview`.
- `Get-TunedBaseBackground -StyleDir` — Task 5 def + call inside `Get-StyleBundledBackground`.
- `Invoke-TerminalStyleTune -StyleName` — Task 6 def + Task 7 dispatch + Task 6/7 tests.

**Scope:** Single cohesive feature (one subcommand + its helpers). Fits one plan; tasks are independently committable and keep CI green.

**Judgment calls flagged:**

- The live opacity/font preview uses a throwaway scratch style dir under `$DataRoot\.tune-preview\` to reuse `Merge-StyleIntoSettings` (incl. background inheritance) rather than duplicating merge logic. Cleaned up in `finally`.
- The Opacity knob maps to Windows Terminal's window `opacity` field (0–100). `backgroundImageOpacity` is left at the base theme's value. (Spec said "and/or"; window opacity is the clearest single effect for v1.)
- API key is inlined at publish time (Task 9 Step 2), matching the established release procedure in prior plans.
