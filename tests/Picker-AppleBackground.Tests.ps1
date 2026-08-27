# Pester 5 tests: the picker must deliver a style's background image on
# Terminal.app, the same as `tstyles <name>` does.
#
# The bug: on Terminal.app, `tstyles` + arrow + Enter applied colors and prompt,
# printed "Style applied: eva", and stopped. No profile written under
# <data-root>/profiles/, no mention that the style ships a background, no hint
# about how to see it. `tstyles eva` on the same terminal wrote the profile and
# said "This style ships a background image ... tstyles eva -NewWindow".
#
# -NewWindow made it worse: it is declared on Invoke-TerminalStyle's param block
# and was read only by the two apply paths, so `tstyles -NewWindow` was accepted
# without error and did nothing at all. CHANGELOG records the identical defect
# already fixed for `tstyles random`; the picker was the last place it survived.
#
# The picker branch's own comment claimed it staged state "exactly as
# Apply-StyleNonWT does" while omitting half of it, which is why the shape
# assertion at the bottom is against Apply-StyleNonWT rather than a literal.
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

Describe 'Publish-StyleBackgroundProfile' {
    # Tested directly rather than through the picker: the picker's non-WT branch
    # needs a real console and blocks on input, which is exactly why this half of
    # it went uncovered long enough to diverge from Apply-StyleNonWT.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Get-StyleBundledBackground { '/tmp/does-not-matter.gif' }
            Mock New-AppleTerminalProfile { '/tmp/generated.terminal' }
            Mock Start-Process {}
        }

        It 'writes the profile on Terminal.app' {
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            Should -Invoke New-AppleTerminalProfile -Times 1 -Exactly
        }

        It 'tells the user how to see it when -NewWindow was not given' {
            # The whole point of writing it either way: the image cannot reach
            # the window the user is already in.
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            $out = $script:written -join "`n"
            $out | Should -Match 'ships a background image'
            $out | Should -Match 'tstyles eva -NewWindow'
        }

        It 'names the style the user actually picked in the hint' {
            Publish-StyleBackgroundProfile -StyleName 'tombraider' -StyleDir '/tmp/tr' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            ($script:written -join "`n") | Should -Match 'tstyles tombraider -NewWindow'
        }

        It 'opens the window instead of hinting when -NewWindow was given' {
            # Open-AppleTerminalProfile exists as a seam precisely so this test
            # does not shell out to `open` on the runner.
            Mock Open-AppleTerminalProfile {}
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' -NewWindow | Out-Null
            $out = $script:written -join "`n"
            $out | Should -Match 'Opening a new window'
            $out | Should -Not -Match 'ships a background image'
            Should -Invoke Open-AppleTerminalProfile -ParameterFilter {
                $Path -eq '/tmp/generated.terminal'
            } -Times 1 -Exactly
        }

        It 'reports a failure to open rather than throwing out of the apply' {
            Mock Open-AppleTerminalProfile { throw 'no such file' }
            { Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' -NewWindow } |
                Should -Not -Throw
            ($script:written -join "`n") | Should -Match 'Could not open the profile'
        }

        It 'does nothing on a terminal that cannot carry a background at all' {
            # VSCode reports BackgroundImage = $false. Writing a Terminal.app
            # profile there would be meaningless, and the fetch behind it is up
            # to four serial 10-second HTTP attempts.
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'VSCode' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
            Should -Not -Invoke Get-StyleBundledBackground
            @($script:written).Count | Should -Be 0
        }

        It 'does nothing on Windows Terminal, which carries its own background' {
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'WindowsTerminal' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
        }

        It 'stays quiet for a style that ships no background' {
            Mock Get-StyleBundledBackground { $null }
            Publish-StyleBackgroundProfile -StyleName 'sober' -StyleDir '/tmp/sober' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
            @($script:written).Count | Should -Be 0
        }

        It 'says nothing when the profile could not be written' {
            # A hint pointing at a profile that does not exist is worse than
            # silence.
            Mock New-AppleTerminalProfile { $null }
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            @($script:written).Count | Should -Be 0
        }
    }
}

Describe 'both apply paths deliver the background' {
    InModuleScope TerminalStyles {

        It 'Apply-StyleNonWT goes through the shared helper' {
            (Get-Command Apply-StyleNonWT).ScriptBlock.ToString() |
                Should -Match 'Publish-StyleBackgroundProfile' `
                -Because 'it is the reference path; the picker mirrors it'
        }

        It 'the picker''s non-WT commit does the same, and honours -NewWindow' {
            # Asked of the AST so the assertion is about a real call with a real
            # argument, not about a string appearing somewhere in the function.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $calls = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Publish-StyleBackgroundProfile' }, $true))
            @($calls).Count | Should -Be 1 `
                -Because 'the picker must write the profile exactly as tstyles <name> does'
            $calls[0].Extent.Text | Should -Match '-NewWindow:\$NewWindow' `
                -Because '`tstyles -NewWindow` was accepted in silence and did nothing'
        }

        It '-NewWindow reaches every path that declares it' {
            # The flag is on Invoke-TerminalStyle's param block, so every branch
            # that applies a style owes the user an answer for it. random was
            # fixed once, direct-apply was always right, the picker was not.
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match 'Invoke-RandomStyle[\s\S]{0,300}?-NewWindow:\$NewWindow'
            $src | Should -Match 'Apply-StyleDirect[\s\S]{0,300}?-NewWindow:\$NewWindow'
            $src | Should -Match 'Publish-StyleBackgroundProfile[\s\S]{0,300}?-NewWindow:\$NewWindow'
        }
    }
}
