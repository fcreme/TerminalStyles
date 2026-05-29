# Pester 5 tests for Get-SchemeOscPacket (OSC color-retint string builder,
# extracted verbatim from the picker). Locks the byte format so the picker
# refactor stays behavior-preserving.
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

Describe 'Get-SchemeOscPacket' {
    InModuleScope TerminalStyles {
        It 'emits the documented OSC sequences for fg/bg/cursor/selection + palette' {
            $E = [char]27; $BEL = [char]7
            $scheme = [pscustomobject]@{
                foreground = '#ffffff'; background = '#000000'
                cursorColor = '#ff0000'; selectionBackground = '#202020'
                black = '#111111'; red = '#aa0000'
            }
            $expected = "$E]10;#ffffff$BEL" + "$E]11;#000000$BEL" +
                        "$E]12;#ff0000$BEL" + "$E]17;#202020$BEL" +
                        "$E]4;0;#111111$BEL" + "$E]4;1;#aa0000$BEL"
            Get-SchemeOscPacket -Scheme $scheme | Should -Be $expected
        }
        It 'omits slots that are absent' {
            $E = [char]27; $BEL = [char]7
            $scheme = [pscustomobject]@{ background = '#000000' }
            Get-SchemeOscPacket -Scheme $scheme | Should -Be "$E]11;#000000$BEL"
        }
    }
}
