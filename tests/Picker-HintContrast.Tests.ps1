# The picker's hints and the style description were a fixed grey, #a0a0a0 --
# chosen once against a dark background, then asked to sit on whatever
# background the previewed style paints. The picker previews by repainting the
# terminal, so the mismatch is not theoretical: the text goes faint the moment
# you arrow onto gitbash, the one light theme.
#
# Measured before the fix, against the 4.5 WCAG body-text threshold:
#   gitbash 2.61 (fails), rain 5.07, snowday 5.97, garden-rain 6.34,
#   kitty 6.80, neon-rain 6.82, forest 6.90 (all marginal)
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
    $script:SchemeCases = @(
        Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') -Directory |
        ForEach-Object { @{ Name = $_.Name; Path = (Join-Path $_.FullName 'scheme.json') } }
    )
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Get-ContrastRatio' {
    InModuleScope TerminalStyles {

        It 'agrees with the WCAG endpoints' {
            # Black on white is the maximum the formula can produce, and a colour
            # against itself the minimum. If these are wrong nothing below means
            # anything.
            [Math]::Round((Get-ContrastRatio -A '#000000' -B '#ffffff'), 2) | Should -Be 21
            Get-ContrastRatio -A '#3a7bd5' -B '#3a7bd5' | Should -Be 1
        }

        It 'is symmetric' {
            $a = Get-ContrastRatio -A '#101010' -B '#e0e0e0'
            $b = Get-ContrastRatio -A '#e0e0e0' -B '#101010'
            $a | Should -Be $b
        }

        It 'answers null rather than guessing on something that is not a colour' {
            Get-ContrastRatio -A 'rebeccapurple' -B '#000000' | Should -BeNullOrEmpty
            Get-ContrastRatio -A '#000000' -B 'not-a-colour'  | Should -BeNullOrEmpty
        }
    }
}

Describe 'the hint colour is readable on the style it belongs to' {

    It '<Name> clears the WCAG body-text threshold' -ForEach $script:SchemeCases {
        $r = InModuleScope TerminalStyles {
            param($p)
            $s = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $h = Get-SchemeHintColor -Scheme $s
            [pscustomobject]@{ Hint = $h; Ratio = (Get-ContrastRatio -A $h -B $s.background) }
        } -Parameters @{ p = $Path }

        $r.Hint  | Should -Not -BeNullOrEmpty
        $r.Ratio | Should -BeGreaterOrEqual 4.5 -Because (
            "$Name's hint text sits on $Name's background while it is previewed")
    }

    It '<Name> gets a hint dimmer than its own foreground' -ForEach $script:SchemeCases {
        # It is SECONDARY text and has to read as such -- a hint at full
        # foreground competes with the style names it sits under. The blend
        # stops at the last step that still clears the threshold, so this is
        # the property that keeps it from simply returning the foreground.
        $r = InModuleScope TerminalStyles {
            param($p)
            $s = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            [pscustomobject]@{
                Hint = (Get-ContrastRatio -A (Get-SchemeHintColor -Scheme $s) -B $s.background)
                Fg   = (Get-ContrastRatio -A $s.foreground -B $s.background)
            }
        } -Parameters @{ p = $Path }

        $r.Hint | Should -BeLessThan $r.Fg -Because "$Name's hint must sit behind its body text"
    }
}

Describe 'Get-SchemeHintColor degrades rather than throwing' {
    InModuleScope TerminalStyles {

        It 'answers null when the scheme colours cannot be read' {
            # Those styles still LIST -- the picker falls back to its fixed grey,
            # which is no worse than what every style got before.
            $s = [pscustomobject]@{ foreground = 'periwinkle'; background = '#000000' }
            Get-SchemeHintColor -Scheme $s | Should -BeNullOrEmpty
            { Get-SchemeHintColor -Scheme ([pscustomobject]@{}) } | Should -Not -Throw
        }

        It 'returns the foreground when no blend can clear the threshold' {
            # A scheme whose own foreground is marginal cannot be improved by
            # dimming it. Returning the foreground is the most readable thing
            # available, and better than returning nothing.
            $s = [pscustomobject]@{ foreground = '#777777'; background = '#6f6f6f' }
            $h = Get-SchemeHintColor -Scheme $s
            $h | Should -Be '#777777'
        }
    }
}

Describe 'the picker uses it, and falls back when it cannot' {
    InModuleScope TerminalStyles {
        BeforeAll { $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() }

        It 'recomputes the hint colour per redraw' {
            # Structural: the picker body needs a console no test can drive. The
            # colour maths it calls IS driven, above.
            $script:picker | Should -Match 'Get-SchemeHintColor -Scheme \$schemes\[\$idx\]'
        }

        It 'keeps the old grey for a style whose scheme will not parse' {
            $script:picker | Should -Match '\$hintColor = \$script:PickerHintFallback'
        }
    }
}
