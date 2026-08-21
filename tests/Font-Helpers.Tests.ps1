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
        # Paths are built with Join-Path / [IO.Path]::Combine rather than written
        # as Windows literals. Both the function (Split-Path -Leaf) and the
        # expectation resolve against the CURRENT platform's separator, so a
        # hardcoded 'D:\Fonts\x.ttf' would be a single unsplit filename on
        # macOS/Linux and the assertion would be testing nothing.
        BeforeAll {
            $script:SrcDir   = Join-Path (Join-Path $TestDrive 'src') 'tmp'
            $script:FontsDir = Join-Path $TestDrive 'Fonts'
        }

        It 'computes dest path and TrueType registry value name for a .ttf' {
            $src  = Join-Path $script:SrcDir 'JetBrainsMono-Regular.ttf'
            $plan = Get-UserFontInstallPlan -FontFiles @($src) -FontsDir $script:FontsDir
            $expected = [System.IO.Path]::Combine($script:FontsDir, 'JetBrainsMono-Regular.ttf')
            @($plan).Count       | Should -Be 1
            $plan[0].Dest        | Should -Be $expected
            $plan[0].ValueName   | Should -Be 'JetBrainsMono-Regular (TrueType)'
            $plan[0].ValueData   | Should -Be $expected
        }
        It 'uses OpenType for a .otf' {
            $src  = Join-Path $script:SrcDir 'SourceCodePro-Regular.otf'
            $plan = Get-UserFontInstallPlan -FontFiles @($src) -FontsDir $script:FontsDir
            $plan[0].ValueName | Should -Be 'SourceCodePro-Regular (OpenType)'
        }
    }
}
