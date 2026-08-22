# Pester 5 tests for the picker's post-confirm live-reload gate.
#
# The bug this pins: the gate also required Test-InWindowsTerminal, so off
# Windows Terminal the picker copied a style's profile.ps1 into place and then
# refused to dot-source it. `tstyles eva` painted a banner and a themed prompt;
# choosing eva in the picker painted neither, on the same terminal, until the
# user opened a new tab.
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

Describe 'Test-ShouldLiveReloadPrompt' {
    InModuleScope TerminalStyles {
        It 'reloads when a prompt was installed for a PowerShell target' {
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $true |
                Should -BeTrue
        }

        It 'does not reload when the style ships no prompt' {
            # current-style.ps1 absent: nothing to dot-source, and sourcing a
            # stale file would reinstate the PREVIOUS style's prompt.
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $false |
                Should -BeFalse
        }

        It 'does not reload when the target is not a PowerShell profile' {
            # Windows Terminal only: styling a cmd/WSL profile must not rebind
            # the prompt of the pwsh session running the picker.
            Test-ShouldLiveReloadPrompt -IsPwshTarget $false -ProfilePresent $true |
                Should -BeFalse
        }

        It 'does not consult the host terminal' {
            # The regression guard. Whatever this session is running in, the
            # answer depends only on the two arguments -- a picker confirm off
            # Windows Terminal must reload exactly as one inside it does.
            $inWT = Test-InWindowsTerminal
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $true |
                Should -BeTrue -Because "the gate must not vary with the host (in WT: $inWT)"
        }
    }
}
