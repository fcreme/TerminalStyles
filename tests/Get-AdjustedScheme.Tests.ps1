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
