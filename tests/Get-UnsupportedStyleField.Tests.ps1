# Pester 5 tests: the "<terminal> can't show: ..." notice, and the capability
# record it is finally read from.
#
# THE DEFECT. Get-TerminalCapability is built as a promise, and terminals.ps1
# twice states the consequence of a $false flag in its own words:
#
#   "until the profile carries them, saying so here would suppress the
#    'can't show' notice and leave the user comparing an unchanged font
#    against the screenshot"                (AppleTerminal Font/Opacity/CursorShape)
#
#   "Claiming it would suppress the 'can't show' notice and leave the user
#    comparing an unchanged window against a screenshot, which is the exact
#    failure the capability table exists to prevent"        (WezTerm Opacity)
#
# The notice did not read the capability record. It was two hardcoded questions
# -- BackgroundImage and tabColor -- so no $false flag for Font, Opacity,
# CursorShape or Padding could ever produce a word on screen, and a grep found
# those four (plus TabTitle) had ZERO readers outside terminals.ps1. The
# rationale was circular: the flags stayed off to trigger a notice that never
# mentioned them.
#
# Measured on 0.8.28, driving the shipped Apply-StyleNonWT over the bundled
# `forest` on every non-WT kind:
#
#   AppleTerminal   style asks for, table says NO: font, opacity, cursorShape,
#                                                  tabColor, padding
#                   apply actually says          : Terminal.app can't show: tab color.
#   Ghostty         7 unsupported                : apply names 2
#   WezTerm         opacity, cursorShape, tabColor, tabTitle
#                                                : apply names 1
#
# and the delivery side agrees it is not a false alarm: New-AppleTerminalProfile
# run for real produces 23 plist keys -- name, type, ProfileCurrentVersion and 20
# colour keys -- carrying no Font, no CursorType and no BackgroundAlphaColor.
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

Describe 'Get-UnsupportedStyleField' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # The bundled `forest` theme.json, field for field. Fifteen of the
            # sixteen shipped styles are this shape.
            $script:theme = [pscustomobject]@{
                colorScheme                       = 'forest'
                tabTitle                          = 'FOREST'
                tabColor                          = '#d49680'
                cursorShape                       = 'filledBox'
                useAcrylic                        = $false
                opacity                           = 100
                'experimental.retroTerminalEffect' = $false
                font                              = [pscustomobject]@{ face = 'Cascadia Code'; size = 11 }
                padding                           = '12'
                backgroundImage                   = '{{BACKGROUND_IMAGE}}'
                backgroundImageOpacity            = 0.45
            }
            $script:styleDir = Join-Path $TestDrive 'styles/forest'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null

            # The background question is asked of the RESOLVED image, and
            # resolving it for real can make four serial 10-second HTTP attempts.
            # Mocked to "there is one" so the capability is the only variable.
            Mock Get-StyleBundledBackground { Join-Path $script:styleDir 'background.gif' }

            function script:Fields {
                param([string]$Kind, $Theme = $script:theme)
                return @(Get-UnsupportedStyleField -Theme $Theme -StyleDir $script:styleDir -Kind $Kind)
            }
        }

        It 'names the font, cursor shape and padding Terminal.app drops' {
            # The three genuinely visible drops on the primary macOS flow, all
            # three $false in the table, none of them ever printed.
            $f = script:Fields -Kind 'AppleTerminal'
            $f | Should -Contain 'font'
            $f | Should -Contain 'cursor shape'
            $f | Should -Contain 'padding'
            $f | Should -Contain 'tab color'
        }

        It 'does not name the background image on Terminal.app, which can show one' {
            # Through a profile and a new window, which is what Persist plus
            # BackgroundImage means here. Saying it cannot would be this same
            # defect pointed the other way.
            script:Fields -Kind 'AppleTerminal' | Should -Not -Contain 'background image'
        }

        It 'names it on a terminal that really cannot' {
            script:Fields -Kind 'Ghostty' | Should -Contain 'background image'
        }

        It 'asks the resolver, not the theme key, about the background' {
            # Every bundled theme.json carries the literal "{{BACKGROUND_IMAGE}}"
            # placeholder whether or not an image exists to substitute into it,
            # so reading the key would report an image for all sixteen styles on
            # every terminal.
            Mock Get-StyleBundledBackground { $null }
            script:Fields -Kind 'Ghostty' | Should -Not -Contain 'background image'
        }

        It 'follows the capability record rather than a list of its own' {
            # WezTerm is the proof that the record drives this: same style, same
            # question, and font and padding drop off the list purely because
            # Get-WezTermStyleLua writes config.font and window_padding.
            $f = script:Fields -Kind 'WezTerm'
            $f | Should -Not -Contain 'font'
            $f | Should -Not -Contain 'padding'
            $f | Should -Not -Contain 'background image'
            $f | Should -Contain 'cursor shape'
            $f | Should -Contain 'tab color'
        }

        It 'has nothing to say about Windows Terminal' {
            # The reference implementation: theme.json was defined against it.
            script:Fields -Kind 'WindowsTerminal' | Should -BeNullOrEmpty
        }

        It 'never names the tab title on <_>' -ForEach @('AppleTerminal','ITerm2','Ghostty','WezTerm','Kitty','VSCode','Unknown') {
            # The style's profile.ps1 sets $Host.UI.RawUI.WindowTitle and the
            # staged prompt.sh emits OSC 0, both on every terminal -- so the
            # title DOES change here, and "can't show: tab title" would be false
            # everywhere the flag is $false. The one field deliberately left out
            # of the map, and the reason TabTitle is not a notice trigger.
            @(Get-UnsupportedStyleField -Theme $script:theme -StyleDir $script:styleDir -Kind $_) |
                Should -Not -Contain 'tab title'
        }

        It 'stays quiet about an opacity of 100, which asks for nothing' {
            # useAcrylic false + opacity 100 is an ordinary opaque window --
            # exactly what a terminal with no transparency support already gives.
            # Fifteen of the sixteen bundled styles are this, so naming it would
            # be noise on nearly every apply and would teach the user to skip the
            # line carrying the real drops.
            script:Fields -Kind 'AppleTerminal' | Should -Not -Contain 'opacity'
        }

        It 'names opacity when the style really asks for transparency' {
            # `kitty` is the one bundled style that does: opacity 80, acrylic on.
            $t = $script:theme.PSObject.Copy()
            $t.opacity    = 80
            $t.useAcrylic = $true
            script:Fields -Kind 'AppleTerminal' -Theme $t | Should -Contain 'opacity'
        }

        It 'names opacity for acrylic alone' {
            $t = $script:theme.PSObject.Copy()
            $t.useAcrylic = $true
            script:Fields -Kind 'AppleTerminal' -Theme $t | Should -Contain 'opacity'
        }

        It 'reads an opacity written as a string the same way' {
            # theme.json values arrive from ConvertFrom-Json, and a culture whose
            # decimal separator is a comma must not turn 80 into 100.
            $t = $script:theme.PSObject.Copy()
            $t.opacity = '80'
            script:Fields -Kind 'AppleTerminal' -Theme $t | Should -Contain 'opacity'
        }

        It 'says nothing at all for a style that declares nothing' {
            $bare = [pscustomobject]@{ colorScheme = 'plain' }
            Mock Get-StyleBundledBackground { $null }
            script:Fields -Kind 'Ghostty' -Theme $bare | Should -BeNullOrEmpty
        }

        It 'returns an empty list, not a resolution, for a style with no theme.json' {
            # $null theme means nothing was declared, so there is no claim to
            # fall short of -- and asking anyway would pay for a background
            # resolution the style never asked for.
            @(Get-UnsupportedStyleField -Theme $null -StyleDir $script:styleDir -Kind 'Ghostty') |
                Should -BeNullOrEmpty
            Should -Not -Invoke Get-StyleBundledBackground
        }

        It 'orders the list the same way every time' {
            # A notice whose wording shuffles between runs reads as two different
            # notices.
            (script:Fields -Kind 'Ghostty') -join ',' |
                Should -Be 'background image,font,cursor shape,padding,tab color'
        }

        It 'resolves the background at most once' {
            # Get-StyleBundledBackground can make four serial 10-second HTTP
            # attempts. It is asked only where the answer can matter, and only
            # once there.
            script:Fields -Kind 'Ghostty' | Out-Null
            Should -Invoke Get-StyleBundledBackground -Times 1 -Exactly -Scope It
        }

        It 'never asks at all where the terminal can show one' {
            script:Fields -Kind 'AppleTerminal' | Out-Null
            Should -Not -Invoke Get-StyleBundledBackground
        }
    }
}

Describe 'Show-UnsupportedStyleField' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:said = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:said.Add("$Object") }
        }

        It 'names the terminal and every field, in one line' {
            Show-UnsupportedStyleField -Kind 'AppleTerminal' -Field @('font', 'cursor shape')
            ($script:said -join "`n") | Should -Match "Terminal\.app can't show: font, cursor shape\."
        }

        It 'prints nothing for an empty list' {
            Show-UnsupportedStyleField -Kind 'AppleTerminal' -Field @()
            @($script:said).Count | Should -Be 0
        }
    }
}

# Both doors, one notice. The apply door printed it and the picker's confirm path
# printed nothing at all, so `tstyles` + Enter on Terminal.app said not one word
# about any dropped field -- the same door that forgot to stage the shell files
# and to write the background profile for several releases.
Describe 'both apply doors name what the terminal cannot show' {
    InModuleScope TerminalStyles {

        It 'Apply-StyleNonWT goes through the shared notice' {
            (Get-Command Apply-StyleNonWT).ScriptBlock.ToString() |
                Should -Match 'Show-UnsupportedStyleField' `
                -Because 'it is the reference path; the picker mirrors it'
        }

        It 'the picker''s confirm path calls it too' {
            # Asked of the AST so this is about a real call, not a string that
            # happens to appear in a comment.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $calls = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Show-UnsupportedStyleField' }, $true))
            @($calls).Count | Should -Be 1 `
                -Because 'the picker must say what tstyles <name> says'
        }

        It 'and prints it BELOW the Clear-Host, where it can be read' {
            # The trap this file exists inside: the picker's confirm block runs
            # several screens above a Clear-Host, so a notice emitted where the
            # list is computed would pass every test and show the user nothing.
            # "Style applied" is printed immediately after that Clear-Host, so
            # being after it in the source is the proof.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $show = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Show-UnsupportedStyleField' }, $true))
            $applied = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $n.Value -eq '  Style applied: ' }, $true))

            @($applied).Count | Should -Be 1 -Because 'the anchor must be unambiguous'
            @($show).Count    | Should -Be 1
            $show[0].Extent.StartOffset | Should -BeGreaterThan $applied[0].Extent.StartOffset
        }
    }
}
