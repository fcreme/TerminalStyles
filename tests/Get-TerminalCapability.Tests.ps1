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

        It 'marks every terminal it can persist to as also able to set a font' {
            # A persistable config that cannot carry a font would silently drop
            # the style's font choice on apply.
            foreach ($k in $script:AllKinds) {
                $caps = Get-TerminalCapability -Kind $k
                if ($caps.Persist) {
                    $caps.Font | Should -BeTrue -Because "$k persists config, so it should carry a font"
                }
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
