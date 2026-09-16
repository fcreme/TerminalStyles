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
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $true -AutoLoadSuppressed $false |
                Should -BeTrue
        }

        It 'does not reload when the style ships no prompt' {
            # current-style.ps1 absent: nothing to dot-source, and sourcing a
            # stale file would reinstate the PREVIOUS style's prompt.
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $false -AutoLoadSuppressed $false |
                Should -BeFalse
        }

        It 'does not reload when the target is not a PowerShell profile' {
            # Windows Terminal only: styling a cmd/WSL profile must not rebind
            # the prompt of the pwsh session running the picker.
            Test-ShouldLiveReloadPrompt -IsPwshTarget $false -ProfilePresent $true -AutoLoadSuppressed $false |
                Should -BeFalse
        }

        It 'does not reload into the one-shot pwsh the zsh/bash shim runs' {
            # The generated tstyles-cli.ps1 sets $global:TStylesNoAutoLoad
            # (terminals.ps1) because from zsh or bash `tstyles` runs in a
            # one-shot pwsh that exits immediately: dot-sourcing the style's
            # profile.ps1 there reloads nothing and prints the style's whole
            # ASCII banner, and the shell wrapper then re-sources the staged
            # prompt.sh and prints it a SECOND time.
            #
            # Apply-StyleNonWT honoured that flag; the picker's confirm asked
            # THIS gate, which had no way to know the shim was running. Measured
            # from a real interactive bash on a pty: picker + Enter printed two
            # NERV banners, `tstyles eva` printed one.
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $true -AutoLoadSuppressed $true |
                Should -BeFalse
        }

        It 'does not consult the host terminal' {
            # The regression guard. Whatever this session is running in, the
            # answer depends only on the arguments -- a picker confirm off
            # Windows Terminal must reload exactly as one inside it does.
            $inWT = Test-InWindowsTerminal
            Test-ShouldLiveReloadPrompt -IsPwshTarget $true -ProfilePresent $true -AutoLoadSuppressed $false |
                Should -BeTrue -Because "the gate must not vary with the host (in WT: $inWT)"
        }

        It 'both apply doors decide it here, and neither keeps its own copy' {
            # The rule that made this a defect in the first place: two
            # implementations of one question, agreeing until one of them was
            # fixed. Apply-StyleNonWT tested $global:TStylesNoAutoLoad inline
            # and the picker asked this gate, so fixing the flag in one place
            # left the other door printing two banners for several releases.
            foreach ($name in 'Invoke-TerminalStyle', 'Apply-StyleNonWT') {
                $ast = (Get-Command $name).ScriptBlock.Ast
                $calls = @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Test-ShouldLiveReloadPrompt' }, $true))
                @($calls).Count | Should -BeGreaterThan 0 `
                    -Because "$name must ask the shared gate rather than re-deciding"
                foreach ($c in $calls) {
                    $c.Extent.Text | Should -Match '-AutoLoadSuppressed' `
                        -Because "$name must pass the shim's own signal, or the gate cannot see it"
                }
            }
        }
    }
}
