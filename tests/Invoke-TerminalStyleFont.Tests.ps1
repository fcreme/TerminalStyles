# Pester 5 tests for Invoke-TerminalStyleFont -- `tstyles font` (list) and
# `tstyles font <name>` (install if needed, then apply).
#
# Every helper under this function was already covered; the orchestrator was
# not, which is how it kept a Windows-only tail long after Install-Font learned
# macOS and Linux. Off Windows Terminal it installed the font successfully and
# then printed "Could not locate Windows Terminal settings.json." in red,
# reporting failure for a job that had just succeeded.
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

Describe 'Invoke-TerminalStyleFont' {
    InModuleScope TerminalStyles {

        BeforeEach {
            Mock Write-Host {}
            Mock Show-FontList {}
            # A font that is already present, so the install half is a no-op and
            # each test isolates the apply half.
            Mock Test-FontInstalled { $true }
        }

        It 'lists the catalog when given no name' {
            Invoke-TerminalStyleFont
            Should -Invoke Show-FontList -Times 1 -Exactly
        }

        It 'rejects an unknown font without touching the terminal' {
            Mock Find-WTSettingsPath { throw 'must not look for settings.json for an unknown font' }
            Invoke-TerminalStyleFont -Name 'Definitely Not A Font'
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'Unknown font' }
        }

        Context 'on a terminal that cannot take a font from us' {

            BeforeEach {
                Mock Get-TerminalKind { 'AppleTerminal' }
                # Find-WTSettingsPath must not even be consulted: off Windows
                # Terminal there is no settings.json to find, and asking builds
                # candidate paths from a null $env:LOCALAPPDATA.
                Mock Find-WTSettingsPath { throw 'must not look for Windows Terminal settings.json off WT' }
                Mock Set-ProfileFont { throw 'must not try to write a profile off WT' }
            }

            It 'does not report a Windows Terminal failure' {
                Invoke-TerminalStyleFont -Name 'JetBrains Mono'
                Should -Not -Invoke Write-Host -ParameterFilter {
                    "$Object" -match 'Could not locate Windows Terminal'
                }
            }

            It 'says the font is installed and where to pick it up' {
                Invoke-TerminalStyleFont -Name 'JetBrains Mono'
                Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'is installed' }
                Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'cannot apply it for you' }
            }

            It 'still installs a font that is missing' {
                Mock Test-FontInstalled { $false }
                Mock Resolve-FontPackage { @('/tmp/fake.ttf') }
                Mock Install-Font { 1 }
                Invoke-TerminalStyleFont -Name 'JetBrains Mono'
                Should -Invoke Install-Font -Times 1 -Exactly
            }
        }

        Context 'on Windows Terminal' {

            BeforeEach {
                Mock Get-TerminalKind { 'WindowsTerminal' }
            }

            It 'still goes down the settings.json path' {
                # The gate is the Font capability, which only Windows Terminal
                # has -- so trimming the over-claims must not have cost WT its
                # apply.
                Mock Find-WTSettingsPath { $null }
                Invoke-TerminalStyleFont -Name 'JetBrains Mono'
                Should -Invoke Find-WTSettingsPath -Times 1 -Exactly
                Should -Invoke Write-Host -ParameterFilter {
                    "$Object" -match 'Could not locate Windows Terminal'
                }
            }
        }
    }
}
