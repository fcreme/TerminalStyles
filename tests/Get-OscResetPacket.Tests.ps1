# Pester 5 tests for Get-OscResetPacket: the OSC sequence that resets the
# terminal's dynamic colors (palette + fg/bg/cursor/selection) back to the
# profile defaults. Emitted on Esc/cancel in the picker and tuner so a cancelled
# live preview doesn't leave the terminal retinted (the OSC color overrides
# would otherwise persist after settings.json is reverted).
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

Describe 'Get-OscResetPacket' {
    InModuleScope TerminalStyles {
        It 'emits palette reset (OSC 104) + fg/bg/cursor/selection resets (OSC 110/111/112/117)' {
            $E = [char]27; $BEL = [char]7
            $expected = "$E]104$BEL" + "$E]110$BEL" + "$E]111$BEL" + "$E]112$BEL" + "$E]117$BEL"
            Get-OscResetPacket | Should -Be $expected
        }
    }
}
