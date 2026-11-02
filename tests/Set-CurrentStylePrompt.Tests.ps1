# Pester 5 tests for Set-CurrentStylePrompt: the one place that decides what
# current-style.ps1 holds after an apply.
#
# The rule was written out inline four times -- the picker, Apply-StyleDirect,
# Apply-StyleNonWT and apply.ps1 -- and apply.ps1's copy drifted: -KeepPrompt,
# or a style with no profile.ps1, skipped the whole step, so the previous
# style's prompt stayed and loaded in every new tab. The contract is that the
# file ends up the style's prompt, or ABSENT -- never stale.
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

Describe 'Set-CurrentStylePrompt' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedCurrent   = $script:TStylesCurrent
            $script:TStylesCurrent = Join-Path $TestDrive 'current-style.ps1'

            $script:withPrompt = Join-Path $TestDrive 'withprompt'
            $script:noPrompt   = Join-Path $TestDrive 'noprompt'
            [void][System.IO.Directory]::CreateDirectory($script:withPrompt)
            [void][System.IO.Directory]::CreateDirectory($script:noPrompt)
            # A UTF-8 BOM and a byte that is not valid UTF-8: the copy is a byte
            # copy, which 5.1 needs for non-ASCII prompt glyphs and which
            # Get-CurrentStyleName's byte-compare depends on. A text read and
            # write would change both.
            $script:promptBytes = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes("# prompt`n") + @(0xF3, 0x0A))
            [System.IO.File]::WriteAllBytes((Join-Path $script:withPrompt 'profile.ps1'), $script:promptBytes)
            [System.IO.File]::WriteAllText((Join-Path $script:noPrompt 'scheme.json'), '{"name":"noprompt"}')

            $script:seedOld = {
                [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old')
                [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeTrue -Because 'the fixture must plant the stale file'
            }
        }
        AfterEach {
            [System.IO.File]::Delete($script:TStylesCurrent)
            $script:TStylesCurrent = $script:savedCurrent
        }

        It 'installs the style''s prompt byte for byte' {
            & $script:seedOld
            Set-CurrentStylePrompt -StyleDir $script:withPrompt | Should -BeExactly 'installed'
            ([System.IO.File]::ReadAllBytes($script:TStylesCurrent) -join ',') | Should -BeExactly ($script:promptBytes -join ',')
        }

        It 'removes the previous prompt under -KeepPrompt' {
            & $script:seedOld
            Set-CurrentStylePrompt -StyleDir $script:withPrompt -KeepPrompt | Should -BeExactly 'removed'
            [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeFalse
        }

        It 'removes the previous prompt for a style that ships no profile.ps1' {
            & $script:seedOld
            Set-CurrentStylePrompt -StyleDir $script:noPrompt | Should -BeExactly 'removed'
            [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeFalse
        }

        It 'says none when there is nothing to install and nothing to remove' {
            Set-CurrentStylePrompt -StyleDir $script:noPrompt | Should -BeExactly 'none'
            [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeFalse
        }

        It 'installs nothing under -KeepPrompt' {
            Set-CurrentStylePrompt -StyleDir $script:withPrompt -KeepPrompt | Should -BeExactly 'none'
            [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeFalse
        }
    }
}
