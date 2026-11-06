# Legibility guard: every chromatic ANSI color in a bundled scheme.json must
# stay readable against that scheme's own background. Colored text below ~3:1
# reads as muddy syntax highlighting in the prompt. WCAG 1.4.11 puts the floor
# for non-body / accent color at 3:1, which is the right bar for terminal token
# colors (they are short identifiers, not paragraphs).
#
# Scope note: black / white (and their bright variants) are deliberately NOT
# checked -- they are the achromatic ends that blend into the background by
# design (e.g. gitbash is a light theme where white text is never used).
#
# Documented exceptions live in $allow below.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

# The floors themselves live in Get-SchemeCatalogueContrastProblems
# (lib/submit.ps1), which `tstyles submit` holds a submitted style to: one
# rule, so the submission check and this guard cannot disagree.
Describe 'Bundled scheme color contrast' {
    BeforeDiscovery {
        $repoRoot  = Split-Path $PSScriptRoot -Parent

        # (theme/key) pairs intentionally allowed below the 3:1 floor.
        #   umbrella/red -- the theme's signature "blood red" (#b41e1e), used for
        #   the banner, prompt scaffolding and cursor. It sits at 2.99:1, within
        #   rounding of the floor; lifting it would shift the whole theme's
        #   identity for an imperceptible contrast gain.
        $allow = @{ 'umbrella' = @('red') }

        $cases = foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory) {
            $schemePath = Join-Path $dir.FullName 'scheme.json'
            if (-not (Test-Path -LiteralPath $schemePath)) { continue }
            $exempt = @()
            if ($allow.ContainsKey($dir.Name)) { $exempt = $allow[$dir.Name] }
            @{ Theme = $dir.Name; SchemePath = $schemePath; Exempt = $exempt }
        }
    }

    It '<Theme>: every chromatic slot is above 3:1 on its background' -ForEach $cases {
        $scheme = Get-Content -LiteralPath $SchemePath -Raw | ConvertFrom-Json
        $misses = @(InModuleScope TerminalStyles -Parameters @{ S = $scheme; E = $Exempt } {
            param($S, $E)
            Get-SchemeCatalogueContrastProblems -Scheme $S -Exempt $E | Where-Object Against -eq 'background'
        })
        ($misses | ForEach-Object { '{0} {1} {2:0.00}:1' -f $_.Slot, $_.Color, $_.Ratio }) -join '; ' |
            Should -BeNullOrEmpty -Because "$Theme's accent colours must stay readable on its background"
    }

    It 'reports a slot below the floor, and skips it when exempt' {
        InModuleScope TerminalStyles {
            $s = [pscustomobject]@{ background = '#000000'; red = '#202020'; green = '#00ff00' }
            @(Get-SchemeCatalogueContrastProblems -Scheme $s).Slot | Should -Be @('red')
            @(Get-SchemeCatalogueContrastProblems -Scheme $s -Exempt 'red').Count | Should -Be 0
        }
    }
}

Describe 'Selection highlight' {
    # A separate floor from the one above, and a stricter one. The chromatic
    # check asks whether accent tokens stay legible on the BACKGROUND; nothing
    # asked what happens on top of selectionBackground, which is the fill behind
    # ordinary body text the moment anyone drags a mouse. That gap shipped
    # kitty with selectionBackground set to a byte-identical copy of its
    # cursorColor (#ffb3c6, a near-white pink): 15 of its 17 slots fell below
    # 3:1 on it, foreground at 1.34:1 and brightRed at 1.00:1 -- selecting a line
    # produced a blank pink bar.
    #
    # 4.5:1 is the WCAG AA body-text floor, which is the right bar here: unlike
    # a syntax token, selected text is whatever the user is reading. The worst
    # legitimate theme (golden-forest) sits at 5.33:1.
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $selCases = foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory) {
            $schemePath = Join-Path $dir.FullName 'scheme.json'
            if (-not (Test-Path -LiteralPath $schemePath)) { continue }
            $scheme = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
            if (-not $scheme.selectionBackground) { continue }
            @{ Theme = $dir.Name; Dir = $dir.FullName
               Selection = [string]$scheme.selectionBackground
               Foreground = [string]$scheme.foreground
               Cursor = [string]$scheme.cursorColor }
        }
    }

    It '<Theme> foreground (<Foreground>) is >4.5:1 on its selection (<Selection>)' -ForEach $selCases {
        $s = [pscustomobject]@{ foreground = $Foreground; selectionBackground = $Selection }
        $misses = @(InModuleScope TerminalStyles -Parameters @{ S = $s } {
            param($S)
            Get-SchemeCatalogueContrastProblems -Scheme $S | Where-Object Against -eq 'selectionBackground'
        })
        $misses.Count | Should -Be 0 -Because "selected text in $Theme is body text, not an accent token"
    }

    It '<Theme> paints the same selection colour in PSReadLine as in the terminal' -ForEach $selCases {
        # profile.ps1 sets PSReadLine's Selection highlight with an SGR
        # 48;2;R;G;B. In every theme but the broken one that value equalled
        # scheme.json's selectionBackground exactly -- which is how kitty''s
        # pasted-over slot was identifiable at all, and what made #584868
        # recoverable as the value it meant.
        #
        # Two highlights that disagree is a visible defect in its own right: the
        # input line and the scrollback above it fill with different colours
        # during one drag.
        $profilePath = Join-Path $Dir 'profile.ps1'
        if (-not (Test-Path -LiteralPath $profilePath)) {
            Set-ItResult -Skipped -Because "$Theme ships no profile.ps1"
            return
        }
        $src = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
        $m = [regex]::Match($src, '48;2;(\d{1,3});(\d{1,3});(\d{1,3})')
        if (-not $m.Success) {
            Set-ItResult -Skipped -Because "$Theme sets no PSReadLine selection background"
            return
        }
        $fromProfile = '#{0:x2}{1:x2}{2:x2}' -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value
        $fromProfile | Should -Be $Selection.ToLowerInvariant() `
            -Because "$Theme must highlight a selection the same colour everywhere it can"
    }
}
