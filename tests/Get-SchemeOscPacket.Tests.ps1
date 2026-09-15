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

Describe 'Get-SchemeUnreadableSlots' {
    # The builder drops a slot it cannot read with no record, and the length of
    # the string it returns was the only evidence anything went missing. This
    # answers the question the packet throws away, so the apply can name the
    # slots that kept the previous style's colours instead of reporting plain
    # success over a window showing two styles at once.
    InModuleScope TerminalStyles {
        It 'names a slot the packet builder could not read' {
            $scheme = [pscustomobject]@{
                name = 'x'; background = '#0a0006'; foreground = 'white'; red = '#c41e3a'
            }
            $dropped = @(Get-SchemeUnreadableSlots -Scheme $scheme)
            $dropped | Should -Be @('foreground')
        }

        It 'names every unreadable slot, in the order the scheme carries them' {
            $scheme = [pscustomobject]@{
                background = 'black'; foreground = 'white'; red = 'rgb(196,30,58)'
            }
            $dropped = @(Get-SchemeUnreadableSlots -Scheme $scheme)
            $dropped | Should -Be @('background', 'foreground', 'red')
        }

        It 'says nothing about a scheme it can read in full' {
            $scheme = [pscustomobject]@{
                name = 'x'; background = '#0a0006'; foreground = '#fff'
                cursorColor = '#c41e3aff'; brightWhite = '#f0f0f0'
            }
            @(Get-SchemeUnreadableSlots -Scheme $scheme).Count | Should -Be 0 `
                -Because '#rgb and #rrggbbaa are readable, and a notice about nothing is the same defect'
        }

        It 'ignores keys that are not colour slots at all' {
            # `name` is not a colour, and a third-party style may carry anything
            # else. Reporting those would make the notice noise and train the
            # user to ignore it.
            $scheme = [pscustomobject]@{
                name = 'my-style'; author = 'someone'; opacity = 85; background = '#0a0006'
            }
            @(Get-SchemeUnreadableSlots -Scheme $scheme).Count | Should -Be 0
        }

        It 'asks the builder rather than carrying its own list of slots' {
            # The two are spellings of "what counts as a colour slot", and a
            # copy here would go quiet about exactly the slot just added to the
            # builder. Proven by adding one: with Get-SchemeOscPacket mocked to
            # render a slot it does not really know, the answer follows it.
            Mock Get-SchemeOscPacket {
                param($Scheme)
                if ((ConvertTo-NormalHex -Hex $Scheme.underlineColor)) { 'sequence' } else { '' }
            }
            $scheme = [pscustomobject]@{ underlineColor = 'chartreuse' }
            @(Get-SchemeUnreadableSlots -Scheme $scheme) | Should -Be @('underlineColor')
        }
    }
}
