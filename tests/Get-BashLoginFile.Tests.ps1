# Pester 5 tests for Get-BashLoginFile: bash's own order for a login shell.
#
# bash reads the first of ~/.bash_profile, ~/.bash_login and ~/.profile that
# exists, and stops. shell-init reduced that to "does ~/.profile exist", so a
# home whose login setup lives in ~/.bash_login got a ~/.bash_profile that
# shadowed it.
#
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

Describe 'Get-BashLoginFile' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:h)
            $script:plant = {
                param([string[]]$Files)
                foreach ($f in $Files) {
                    [System.IO.File]::WriteAllText((Join-Path $script:h $f), "# $f`n", [System.Text.UTF8Encoding]::new($false))
                }
            }
        }

        It 'picks <expected> from a home holding <label>' -ForEach @(
            @{ label = 'all three';               files = @('.bash_profile', '.bash_login', '.profile'); expected = '.bash_profile' }
            @{ label = '.bash_login + .profile';  files = @('.bash_login', '.profile');                  expected = '.bash_login' }
            @{ label = '.profile only';           files = @('.profile');                                 expected = '.profile' }
        ) {
            & $script:plant $files
            Get-BashLoginFile -HomeDir $script:h | Should -Be (Join-Path $script:h $expected)
        }

        It 'returns nothing for a home with none of them' {
            & $script:plant @('.bashrc')
            [System.IO.File]::Exists((Join-Path $script:h '.bashrc')) | Should -BeTrue -Because 'the fixture is a real home'
            Get-BashLoginFile -HomeDir $script:h | Should -BeNullOrEmpty
        }
    }
}
