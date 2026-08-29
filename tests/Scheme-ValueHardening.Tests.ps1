# Pester 5 tests for what counts as a colour, and what may reach an escape
# sequence.
#
# Two defects, one root cause -- three different notions of "a hex colour" in
# one file:
#
#   * Get-SchemeOscPacket interpolated a scheme slot into an OSC sequence with
#     NO validation. A scheme value carrying a BEL closed the sequence early and
#     made the remainder a second, attacker-chosen escape sequence -- and this
#     packet is persisted to current-style.osc and replayed by every new
#     zsh/bash shell, so it re-executed on every shell start.
#   * Get-AdjustedScheme accepted only `^#?[0-9a-fA-F]{6}$`, so a shorthand
#     `#013` froze while its neighbours moved with the knob -- and `#RGB` is
#     valid XParseColor, so the terminal genuinely applied the frozen value.
#     Get-SchemeSwatch used a THIRD, stricter pattern and dropped the slot from
#     the preview row entirely, hiding it from the only feedback the tuner shows.
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

Describe 'ConvertTo-NormalHex' {
    InModuleScope TerminalStyles {
        It 'canonicalises <in> to <out>' -ForEach @(
            @{ in = '#013';       out = '#001133' }
            @{ in = '013';        out = '#001133' }
            @{ in = '#0A1B2C';    out = '#0a1b2c' }
            @{ in = '0a1b2c';     out = '#0a1b2c' }
            @{ in = '#ffffffff';  out = '#ffffff' }
            @{ in = '  #013  ';   out = '#001133' }
        ) {
            ConvertTo-NormalHex -Hex $in | Should -Be $out
        }

        It 'returns $null for <label>' -ForEach @(
            @{ label = 'a colour word';    in = 'red' }
            @{ label = 'bad hex';          in = '#zzzzzz' }
            @{ label = 'wrong length';     in = '#12345' }
            @{ label = 'empty';            in = '' }
            @{ label = 'null';             in = $null }
            @{ label = 'an embedded BEL';  in = ("#000000" + [char]7 + "x") }
        ) {
            ConvertTo-NormalHex -Hex $in | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-SchemeOscPacket never emits anything but hex' {
    InModuleScope TerminalStyles {
        It 'drops a value carrying an embedded escape sequence' {
            # The packet is written to the terminal AND persisted to
            # current-style.osc, which every new zsh/bash shell replays -- so an
            # injected sequence re-executes on every shell start, indefinitely.
            $BEL = [char]7; $E = [char]27
            $hostile = "#000000$BEL$E]52;c;cHduZWQ=$BEL"
            $packet = Get-SchemeOscPacket -Scheme ([pscustomobject]@{
                name = 'x'; background = $hostile; foreground = '#ffffff'
            })

            $packet | Should -Not -Match ([regex]::Escape('52;c;'))
            # exactly one BEL for the foreground it did emit, and none smuggled in
            ([regex]::Matches($packet, [regex]::Escape($BEL))).Count | Should -Be 1
            $packet | Should -Match ([regex]::Escape("$E]10;#ffffff$BEL"))
        }

        It 'still emits every well-formed slot, normalised' {
            $packet = Get-SchemeOscPacket -Scheme ([pscustomobject]@{
                name = 'x'; background = '#013'; foreground = '#FFFFFF'; black = 'a1b2c3'
            })
            $E = [char]27; $BEL = [char]7
            $packet | Should -Match ([regex]::Escape("$E]11;#001133$BEL"))
            $packet | Should -Match ([regex]::Escape("$E]10;#ffffff$BEL"))
            $packet | Should -Match ([regex]::Escape("$E]4;0;#a1b2c3$BEL"))
        }

        It 'emits nothing at all for a scheme of pure garbage' {
            $packet = Get-SchemeOscPacket -Scheme ([pscustomobject]@{
                name = 'x'; background = 'red'; foreground = '#zz11gg'
            })
            $packet | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-AdjustedScheme moves every colour it can read' {
    InModuleScope TerminalStyles {
        It 'adjusts shorthand hex instead of freezing it' {
            # #RGB is valid XParseColor, so the terminal DID apply the frozen
            # value -- the background genuinely refused to move with the knob
            # while everything around it brightened.
            $out = Get-AdjustedScheme -Scheme ([pscustomobject]@{
                name = 'mine'; background = '#013'; foreground = '#cccccc'
            }) -Brightness 60

            $out.background | Should -Not -Be '#013'
            $out.background | Should -Match '^#[0-9a-f]{6}$'
            $out.foreground | Should -Not -Be '#cccccc'
        }

        It 'adjusts 8-digit hex, dropping the alpha nothing here can carry' {
            $out = Get-AdjustedScheme -Scheme ([pscustomobject]@{
                name = 'mine'; background = '#102030ff'
            }) -Brightness 40
            $out.background | Should -Match '^#[0-9a-f]{6}$'
            $out.background | Should -Not -Be '#102030ff'
        }

        It 'still passes real garbage through untouched' {
            $out = Get-AdjustedScheme -Scheme ([pscustomobject]@{
                name = 'mine'; background = 'nothex'; red = '#12345'
            }) -Brightness 40
            $out.background | Should -Be 'nothex'
            $out.red        | Should -Be '#12345'
        }

        It 'is still identity at neutral' {
            $out = Get-AdjustedScheme -Scheme ([pscustomobject]@{
                name = 'mine'; background = '#0a1b2c'
            }) -Brightness 0 -Saturation 0
            $out.background | Should -Be '#0a1b2c'
        }

        It 'preserves whether the author wrote a leading #' {
            $out = Get-AdjustedScheme -Scheme ([pscustomobject]@{
                name = 'mine'; background = '0a1b2c'; foreground = '#0a1b2c'
            }) -Brightness 10
            $out.background | Should -Not -Match '^#'
            $out.foreground | Should -Match '^#'
        }
    }
}

Describe 'the swatch shows the slots the adjuster moves' {
    InModuleScope TerminalStyles {
        It 'renders a shorthand slot rather than silently substituting another' {
            # It used to drop #013 and quietly promote a later candidate, so the
            # tuner's only in-menu colour feedback never showed the frozen slot.
            $swatch = Get-SchemeSwatch -Scheme ([pscustomobject]@{
                name = 'mine'; background = '#013'; foreground = '#ffffff'
            })
            $swatch | Should -Match '48;2;0;17;51m'
        }

        It 'still skips a value that is not a colour at all' {
            $swatch = Get-SchemeSwatch -Scheme ([pscustomobject]@{
                name = 'mine'; background = 'not-a-color'; foreground = '#ffffff'
            })
            $swatch | Should -Match '48;2;255;255;255m'
            $swatch | Should -Not -Match 'not-a-color'
        }
    }
}
