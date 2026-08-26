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
#      cyan->purple sequence regardless of palette. Now caught by the
#      cross-theme distinguishability assertion.
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
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
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
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $signatures = InModuleScope TerminalStyles -Parameters @{ ThemeNames = $themeNames; RepoRoot = $repoRoot } {
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
            $names = @($themeNames)
            $collisions = @()
            for ($i = 0; $i -lt $names.Count; $i++) {
                for ($j = $i + 1; $j -lt $names.Count; $j++) {
                    if ($signatures[$names[$i]] -eq $signatures[$names[$j]]) {
                        $collisions += "$($names[$i]) == $($names[$j])"
                    }
                }
            }
            $collisions | Should -BeNullOrEmpty
        }
    }
}
