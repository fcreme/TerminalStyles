# Pester 5 tests for Get-TerminalCapability / Test-TerminalCapability
# (module-private).
#
# The point of these is to pin the *shape* of the capability record and the
# few invariants that callers rely on, not to re-assert every flag: a flag
# table that only restates itself in a test is noise. The invariants that do
# matter are the ones a future terminal block could quietly violate.
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

Describe 'Get-TerminalCapability' {
    InModuleScope TerminalStyles {

        $script:AllKinds = @('WindowsTerminal','AppleTerminal','ITerm2','Ghostty',
                             'WezTerm','Kitty','Alacritty','VSCode','Unknown')

        It 'returns a record covering exactly the declared capability names for <_>' -ForEach $script:AllKinds {
            $caps = Get-TerminalCapability -Kind $_
            # Sorted comparison: the record must be neither missing a declared
            # capability nor carrying an undeclared one, or Test-TerminalCapability's
            # guard becomes meaningless.
            ($caps.Keys | Sort-Object) -join ',' |
                Should -Be (($script:TStylesCapabilityNames | Sort-Object) -join ',')
        }

        It 'returns only boolean values for <_>' -ForEach $script:AllKinds {
            $caps = Get-TerminalCapability -Kind $_
            foreach ($v in $caps.Values) { $v | Should -BeOfType [bool] }
        }

        It 'grants Windows Terminal every capability' {
            # WT is the reference implementation -- theme.json was defined against
            # it, so anything it cannot do is a field no style should contain.
            $caps = Get-TerminalCapability -Kind 'WindowsTerminal'
            foreach ($n in $script:TStylesCapabilityNames) {
                $caps[$n] | Should -BeTrue -Because "Windows Terminal should support $n"
            }
        }

        It 'assumes OSC colors but nothing else for an unknown terminal' {
            # Getting OscPalette wrong on an unknown terminal costs one ignored
            # escape sequence; getting Persist wrong would mean writing a config
            # file for a terminal that will never read it.
            $caps = Get-TerminalCapability -Kind 'Unknown'
            $caps.OscPalette | Should -BeTrue
            foreach ($n in ($script:TStylesCapabilityNames | Where-Object { $_ -ne 'OscPalette' })) {
                $caps[$n] | Should -BeFalse -Because "an unknown terminal must not be assumed to support $n"
            }
        }

        It 'claims Terminal.app can show a background image' {
            # Terminal.app DOES support one, via the BackgroundImageBookmark key
            # in a .terminal profile. This was wrong in 0.8.0/0.8.1, which told
            # users the feature did not exist.
            (Get-TerminalCapability -Kind 'AppleTerminal').BackgroundImage | Should -BeTrue
        }

        It 'claims OSC palette support for Terminal.app' {
            # Verified by round-trip probe against Terminal.app 470: OSC 11 set to
            # #ff00ff read back exactly, and OSC 111/104 restored the defaults.
            (Get-TerminalCapability -Kind 'AppleTerminal').OscPalette | Should -BeTrue
        }

        It 'never claims a stored visual on a terminal it cannot persist to' {
            # The invariant that actually holds, and the one that catches the
            # bug this replaced. Font, opacity, cursor shape, a background
            # image and a tab color cannot be delivered by an escape sequence
            # -- each has to be written into a config the terminal reads. So
            # any of them being true REQUIRES Persist.
            #
            # The previous version of this test asserted the converse, that
            # Persist implies Font, and it was the assumption rather than the
            # code that was wrong: off Windows Terminal, Persist means the
            # .terminal profile writer, which carries colors and an image and
            # no font at all. Asserting it that way round is what kept five
            # terminals marked as font-capable with nothing behind it.
            $stored = @('Font', 'Opacity', 'CursorShape', 'BackgroundImage', 'TabColor')
            foreach ($k in $script:AllKinds) {
                $caps = Get-TerminalCapability -Kind $k
                foreach ($n in $stored) {
                    if ($caps[$n]) {
                        $caps.Persist | Should -BeTrue -Because "$k claims $n, which can only arrive through a config write"
                    }
                }
            }
        }

        It 'claims a capability only where a writer exists' {
            # Windows Terminal has Merge-StyleIntoSettings; Terminal.app has
            # New-AppleTerminalProfile. No other terminal has anything that
            # writes a config, so no other terminal may claim a stored visual
            # -- however capable the emulator itself is. iTerm2 would honour a
            # Dynamic Profile and WezTerm animates background GIFs; neither is
            # written today, and claiming them made styles fail silently.
            $writers = @('WindowsTerminal', 'AppleTerminal')
            $stored  = @('Font', 'Opacity', 'CursorShape', 'BackgroundImage', 'TabColor')
            foreach ($k in ($script:AllKinds | Where-Object { $_ -notin $writers })) {
                $caps = Get-TerminalCapability -Kind $k
                $caps.Persist | Should -BeFalse -Because "nothing writes a config for $k"
                foreach ($n in $stored) {
                    $caps[$n] | Should -BeFalse -Because "$k has no config writer, so it cannot deliver $n"
                }
            }
        }

        It 'does not claim a font or opacity for Terminal.app' {
            # The .terminal profile carries colors and a background image only
            # (Get-AppleTerminalProfileData). Terminal.app would honour a font
            # in a profile -- this is a gap in the writer, not in the terminal
            # -- so when the profile learns to carry one, flip this with it.
            $caps = Get-TerminalCapability -Kind 'AppleTerminal'
            $caps.Font        | Should -BeFalse
            $caps.Opacity     | Should -BeFalse
            $caps.CursorShape | Should -BeFalse
        }

        It 'still lets every OSC terminal preview colors' {
            # The counterweight to the two tests above: trimming the
            # over-claims must not cost the live retint, which is the one thing
            # that does work everywhere and the whole of the picker preview.
            foreach ($k in $script:AllKinds) {
                (Get-TerminalCapability -Kind $k).OscPalette |
                    Should -BeTrue -Because "$k should still get the OSC preview"
            }
        }

        It 'defaults -Kind to the live terminal' {
            $direct = Get-TerminalCapability -Kind (Get-TerminalKind)
            $implied = Get-TerminalCapability
            ($implied.Keys | Sort-Object) -join ',' | Should -Be (($direct.Keys | Sort-Object) -join ',')
            foreach ($n in $script:TStylesCapabilityNames) {
                $implied[$n] | Should -Be $direct[$n]
            }
        }
    }
}

Describe 'Test-TerminalCapability' {
    InModuleScope TerminalStyles {

        It 'agrees with the underlying capability record' {
            Test-TerminalCapability -Capability 'BackgroundImage' -Kind 'WindowsTerminal' | Should -BeTrue
            # VS Code's integrated terminal genuinely cannot show one; Terminal.app
            # can, through a profile, so it is no longer the negative case here.
            Test-TerminalCapability -Capability 'BackgroundImage' -Kind 'VSCode'          | Should -BeFalse
        }

        It 'throws on an unknown capability name instead of returning false' {
            # A typo'd capability silently reading as "unsupported" would disable
            # a feature with no error anywhere -- the worst kind of bug to chase.
            { Test-TerminalCapability -Capability 'Bacgkround' -Kind 'WindowsTerminal' } |
                Should -Throw -ExpectedMessage '*Unknown terminal capability*'
        }

        It 'returns an actual boolean, not a truthy value' {
            Test-TerminalCapability -Capability 'Persist' -Kind 'Unknown' | Should -BeOfType [bool]
        }
    }
}

Describe 'Get-TerminalDisplayName' {
    InModuleScope TerminalStyles {
        It 'gives a human-readable name for <_>' -ForEach @('WindowsTerminal','AppleTerminal','ITerm2','Unknown') {
            Get-TerminalDisplayName -Kind $_ | Should -Not -BeNullOrEmpty
        }
        It 'does not leak the internal kind token for Windows Terminal' {
            Get-TerminalDisplayName -Kind 'WindowsTerminal' | Should -Be 'Windows Terminal'
        }
        It 'falls back to a neutral phrase for an unrecognized kind' {
            Get-TerminalDisplayName -Kind 'NoSuchTerm' | Should -Be 'this terminal'
        }
    }
}
