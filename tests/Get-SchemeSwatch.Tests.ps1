# Pester 5 tests for Get-SchemeSwatch.
#
# Guards against the two swatch bugs caught manually this session:
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
# Requires: Pester 5+  (Install-Module Pester -Force -SkipPublisherCheck)

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
    # Dot-source tstyles.ps1 to bring Get-SchemeSwatch into scope. Suppress
    # its load-time output (alias registration, current-style.ps1 banner if
    # any) so the test runner stays clean.
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null

    function Get-ThemeSwatchRGBs {
        param([Parameter(Mandatory)][string]$ThemeName, [Parameter(Mandatory)][string]$RepoRoot)
        $schemePath = Join-Path $RepoRoot "styles\$ThemeName\scheme.json"
        $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatch = Get-SchemeSwatch -Scheme $scheme
        return [regex]::Matches($swatch, '\[48;2;(\d+;\d+;\d+)m') | ForEach-Object { $_.Groups[1].Value }
    }
}

Describe 'Get-SchemeSwatch' {
    Context 'For theme <_>' -ForEach $themeNames {
        BeforeAll {
            $rgbs = Get-ThemeSwatchRGBs -ThemeName $_ -RepoRoot (Split-Path $PSScriptRoot -Parent)
        }

        It 'produces exactly 5 colored cells' {
            $rgbs.Count | Should -Be 5
        }

        It 'has 5 unique cell colors (no collisions)' {
            ($rgbs | Select-Object -Unique).Count | Should -Be 5
        }
    }

    Context 'Across all themes' {
        It 'every pair of themes produces a byte-distinct swatch' {
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $signatures = @{}
            foreach ($name in $themeNames) {
                $signatures[$name] = (Get-ThemeSwatchRGBs -ThemeName $name -RepoRoot $repoRoot) -join '|'
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
