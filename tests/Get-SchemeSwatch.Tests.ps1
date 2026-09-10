# Pester 5 tests for Get-SchemeSwatch (module-private).
#
# Module-restructure migration: dot-source replaced with Import-Module,
# Get-SchemeSwatch calls wrapped in InModuleScope so the test can see
# the module-private function.
#
# Guards against the two swatch bugs caught manually before the test
# was written:
#   1. "All themes look like rainbows": prior picks (brightRed / yellow /
#      brightGreen / brightCyan / brightPurple) sat in semantically fixed
#      hue slots, so every theme rendered the same red->yellow->green->
#      cyan->purple sequence regardless of palette. The cross-theme
#      assertion below catches the degenerate form of that -- two themes
#      whose swatch rows are byte-identical. It does NOT catch the shape
#      the bug actually had: those five slots hold different hex per
#      theme, so the rows look alike while their bytes differ, and the
#      assertion stays green (measured: restore the old candidate list in
#      Get-SchemeSwatch and only the malformed-colors test goes red).
#      What rules that shape out today is the candidate ORDER in
#      Get-SchemeSwatch, which leads with background / foreground /
#      cursorColor -- unguarded here.
#   2. Collapsed cells: themes with cursorColor == foreground (sober,
#      gitbash) or cursorColor == brightRed (eva) used to render only 4
#      unique colors instead of 5. Now caught by the per-theme unique-
#      colors assertion.
#
# Run: Invoke-Pester (Join-Path $PSScriptRoot 'tests')
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $themeNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'styles') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name } | Sort-Object
    )
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    # Enumerated AGAIN here, deliberately. Pester runs BeforeDiscovery in the
    # discovery scope, so the $themeNames above is $null by the time an It body
    # executes -- `-ForEach` on the per-theme Contexts reads the discovery copy
    # and is fine, a loop inside an It body is not. The cross-theme assertion
    # below compared zero pairs, and reported green, for its whole life without
    # this line: @($null) has Count 1, not 0, so its outer loop ran one iteration
    # and its inner `for ($j = 1; $j -lt 1; ...)` never entered. Same trap, same
    # cure, as tests/Lib-Loading.Tests.ps1 and tests/Bootstrap-ModuleSync.Tests.ps1.
    $script:themeNames = @(
        Get-ChildItem -Path (Join-Path $script:repoRoot 'styles') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name } | Sort-Object
    )
}

Describe 'Get-SchemeSwatch' {
    Context 'For theme <_>' -ForEach $themeNames {
        BeforeAll {
            $themeName = $_
            $repoRoot  = Split-Path $PSScriptRoot -Parent
            $rgbs = InModuleScope TerminalStyles -Parameters @{ ThemeName = $themeName; RepoRoot = $repoRoot } {
                param($ThemeName, $RepoRoot)
                $schemePath = Join-Path $RepoRoot "styles\$ThemeName\scheme.json"
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                $swatch = Get-SchemeSwatch -Scheme $scheme
                [regex]::Matches($swatch, '\[48;2;(\d+;\d+;\d+)m') | ForEach-Object { $_.Groups[1].Value }
            }
        }

        It 'produces exactly 5 colored cells' {
            $rgbs.Count | Should -Be 5
        }

        It 'has 5 unique cell colors (no collisions)' {
            ($rgbs | Select-Object -Unique).Count | Should -Be 5
        }
    }


    Context 'Malformed colors' {
        It 'skips invalid hex values instead of throwing' {
            InModuleScope TerminalStyles {
                $scheme = [pscustomobject]@{
                    background          = '#101010'
                    foreground          = 'not-a-color'
                    cursorColor         = '#202020'
                    brightRed           = '#zzzzzz'
                    brightCyan          = '#303030'
                    selectionBackground = '#12345'
                    brightPurple        = '#404040'
                    brightYellow        = '#505050'
                }

                { $script:swatch = Get-SchemeSwatch -Scheme $scheme } | Should -Not -Throw
                ([regex]::Matches($script:swatch, '\[48;2;(\d+;\d+;\d+)m')).Count | Should -Be 5
            }
        }
    }

    Context 'Across all themes' {
        It 'every pair of themes produces a byte-distinct swatch' {
            $repoRoot = $script:repoRoot
            $names = @($script:themeNames)
            # Coverage before comparison. This is the suite's only cross-theme
            # check of the picker's output, and an empty comparison passes
            # silently, so the loop has to prove it ran before its verdict counts.
            $names.Count | Should -BeGreaterThan 5 `
                -Because 'the bundled themes have to reach the run phase for the comparison below to mean anything'
            $signatures = InModuleScope TerminalStyles -Parameters @{ ThemeNames = $names; RepoRoot = $repoRoot } {
                param($ThemeNames, $RepoRoot)
                $sigs = @{}
                foreach ($name in $ThemeNames) {
                    $schemePath = Join-Path $RepoRoot "styles\$name\scheme.json"
                    $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                    $swatch = Get-SchemeSwatch -Scheme $scheme
                    $rgbs = [regex]::Matches($swatch, '\[48;2;(\d+;\d+;\d+)m') | ForEach-Object { $_.Groups[1].Value }
                    $sigs[$name] = $rgbs -join '|'
                }
                $sigs
            }
            $signatures.Count | Should -Be $names.Count `
                -Because 'a swatch has to be computed for every theme, not for none of them'
            $pairs = 0
            $collisions = @()
            for ($i = 0; $i -lt $names.Count; $i++) {
                for ($j = $i + 1; $j -lt $names.Count; $j++) {
                    $pairs++
                    if ($signatures[$names[$i]] -eq $signatures[$names[$j]]) {
                        $collisions += "$($names[$i]) == $($names[$j])"
                    }
                }
            }
            $pairs | Should -Be ($names.Count * ($names.Count - 1) / 2) `
                -Because 'every pair, which is what this test is named after, has to be compared'
            $collisions | Should -BeNullOrEmpty
        }
    }
}
