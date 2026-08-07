#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-FontInstalled' {
    InModuleScope TerminalStyles {
        It 'matches case-insensitively against the installed list' {
            Test-FontInstalled -Family 'jetbrains mono' -Installed @('Consolas','JetBrains Mono') | Should -BeTrue
        }
        It 'returns false when absent' {
            Test-FontInstalled -Family 'Fira Code' -Installed @('Consolas') | Should -BeFalse
        }
    }
}

Describe 'Get-UserFontInstallPlan' {
    InModuleScope TerminalStyles {
        It 'computes dest path and TrueType registry value name for a .ttf' {
            $plan = Get-UserFontInstallPlan -FontFiles @('C:\tmp\JetBrainsMono-Regular.ttf') -FontsDir 'D:\Fonts'
            @($plan).Count       | Should -Be 1
            $plan[0].Dest        | Should -Be 'D:\Fonts\JetBrainsMono-Regular.ttf'
            $plan[0].ValueName   | Should -Be 'JetBrainsMono-Regular (TrueType)'
            $plan[0].ValueData   | Should -Be 'D:\Fonts\JetBrainsMono-Regular.ttf'
        }
        It 'uses OpenType for a .otf' {
            $plan = Get-UserFontInstallPlan -FontFiles @('C:\tmp\SourceCodePro-Regular.otf') -FontsDir 'D:\Fonts'
            $plan[0].ValueName | Should -Be 'SourceCodePro-Regular (OpenType)'
        }
    }
}
