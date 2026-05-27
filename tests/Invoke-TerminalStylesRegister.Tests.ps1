# Pester 5 tests for Invoke-TerminalStylesRegister.
#
# Function adds `Import-Module TerminalStyles -DisableNameChecking` to
# both PowerShell engines' $PROFILE files (wrapped in BEGIN/END markers
# so uninstall can strip it). Tests use the function's -Targets
# parameter to inject a synthetic single-target list pointing at
# $TestDrive, bypassing the real engine discovery.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Invoke-TerminalStylesRegister' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive 'fake-profile.ps1'
            $script:loaderBegin = '# ===== TerminalStyles BEGIN ====='
            $script:loaderEnd   = '# ===== TerminalStyles END ====='
            $script:blockPattern = "(?ms)$([regex]::Escape($script:loaderBegin)).*?$([regex]::Escape($script:loaderEnd))\r?\n?"
            Mock Read-Host { '' }  # default Y on confirm prompt
        }

        It 'writes the loader block to a fresh $PROFILE' {
            # Pre-condition: fakeProfile doesn't exist
            Test-Path -LiteralPath $script:fakeProfile | Should -BeFalse

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $false
                HasLoader   = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target)

            Test-Path -LiteralPath $script:fakeProfile | Should -BeTrue
            $content = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $content | Should -Match $script:blockPattern
            $content | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
        }

        It 'is idempotent: re-running with existing loader skips' {
            # Pre-populate with a BEGIN/END block
            $existingContent = "# my existing profile`r`n`r`n$script:loaderBegin`r`nImport-Module TerminalStyles -DisableNameChecking`r`n$script:loaderEnd`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Targets @($target)

            # Content unchanged
            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Be $before
            # Exactly one BEGIN/END block (no duplicates)
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
        }

        It '-Force replaces an existing loader block' {
            # Pre-populate with a BEGIN/END block whose body is DIFFERENT (legacy format)
            $oldBody = "$script:loaderBegin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:loaderEnd"
            $existingContent = "# my existing profile`r`n`r`n$oldBody`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Force -Targets @($target)

            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            # Exactly one BEGIN/END block
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
            # The new body is the canonical PSGallery loader (NOT the legacy dot-source)
            $after | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
            $after | Should -Not -Match 'LOCALAPPDATA\\TerminalStyles\\tstyles\.ps1'
        }
    }
}
