# Pester 5 tests: scripts/capture-screenshots.ps1 puts the original style back.
#
# The script promises "When done, the original theme is restored
# automatically" and never did (#133). It saved the style with
# `(tstyles current) -join ''`, but at a real console -- the only place this
# script can run, since it captures the focused Windows Terminal window --
# `tstyles current` writes the name with Write-Host and returns nothing. So
# $originalTheme was always empty and the restore was skipped, leaving the
# maintainer on the last style captured. The restore also sat after the loop,
# so a failed capture or Ctrl+C skipped it even when the name was known.
#
# The script's main flow needs Windows Terminal, so these tests dot-source it
# with $TStylesCaptureNoRun set and drive its two functions.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $TStylesCaptureNoRun = $true
    . (Join-Path (Join-Path $repoRoot 'scripts') 'capture-screenshots.ps1')
}

Describe 'capture-screenshots.ps1 restores the original style' {
    BeforeEach {
        # Records each style the script asks for and applies nothing. It is
        # passed in as -Apply, never defined as a function named `tstyles`:
        # the module exports `tstyles` as an alias, an alias beats a function
        # of the same name, and a first draft of this file applied real styles
        # to the machine running it that way.
        $script:applied = [System.Collections.ArrayList]::new()
        $script:record = { param($Name) [void]$script:applied.Add($Name) }
        # Tripwire, in case anything still reaches the real command. In the
        # caller's scope on purpose: measured in a sandbox, a mock with
        # -ModuleName TerminalStyles does not catch `tstyles` called from out here.
        Mock Invoke-TerminalStyle { throw 'a real style apply was reached from a test' }
    }

    Context 'Get-CaptureOriginalStyle' {
        It 'returns the active style name, not what tstyles current printed' {
            # At a console `tstyles current` returns nothing (it Write-Hosts),
            # which is the whole bug. The name has to come from the module.
            Mock Get-CurrentStyleName -ModuleName TerminalStyles { 'eva' }
            Get-CaptureOriginalStyle | Should -Be 'eva'
        }

        It 'returns nothing when no style is active' {
            Mock Get-CurrentStyleName -ModuleName TerminalStyles { $null }
            Get-CaptureOriginalStyle | Should -BeNullOrEmpty
        }
    }

    Context 'Invoke-CaptureWithRestore' {
        It 'reapplies the original style after the captures' {
            Invoke-CaptureWithRestore -OriginalStyle 'eva' -Apply $script:record -Capture { & $script:record 'forest'; & $script:record 'lain' }
            @($script:applied) | Should -Be @('forest', 'lain', 'eva')
        }

        It 'reapplies it even when a capture throws' {
            { Invoke-CaptureWithRestore -OriginalStyle 'eva' -Apply $script:record -Capture { & $script:record 'forest'; throw 'capture failed' } } |
                Should -Throw 'capture failed' -Because 'the failure is still reported'
            @($script:applied)[-1] | Should -Be 'eva' -Because 'the restore runs in finally'
        }

        It 'applies nothing extra when no style was active' {
            Invoke-CaptureWithRestore -OriginalStyle $null -Apply $script:record -Capture { & $script:record 'forest' }
            @($script:applied) | Should -Be @('forest')
        }
    }
}
