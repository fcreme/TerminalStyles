# Pester 5 tests for Invoke-TerminalStyleTune guard paths (pre-loop).
# The interactive key loop itself is verified manually (like the picker).
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

Describe 'Invoke-TerminalStyleTune guards' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # The tuner writes opacity and font into settings.json, so it is
            # Windows-Terminal-only and returns early elsewhere with an
            # explanation. These tests are about the guards PAST that point, so
            # pin the terminal -- otherwise they assert nothing on macOS/Linux.
            Mock Get-TerminalKind { 'WindowsTerminal' }
        }

        It 'errors when no style name is given and no active style exists' {
            Mock Get-CurrentStyleName { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'No active style' }
        }
        It 'errors when the named style cannot be resolved' {
            Mock Get-StyleDir { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune -StyleName 'nope'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match "not found" }
        }
        It 'errors when settings.json cannot be located' {
            Mock Get-StyleDir { $TestDrive }
            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath { $null }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            # Provide a scheme.json so the base load would succeed past resolution.
            [System.IO.File]::WriteAllText((Join-Path $TestDrive 'scheme.json'), '{"name":"x"}', [System.Text.UTF8Encoding]::new($false))
            Invoke-TerminalStyleTune -StyleName 'x'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'settings.json' }
        }
    }
}

Describe 'Invoke-TerminalStyleTune outside Windows Terminal' {
    InModuleScope TerminalStyles {
        It 'never looks for a settings.json it cannot have' {
            # It used to fail here with "Could not locate Windows Terminal
            # settings.json" -- an error about a file the user was never going
            # to have. Then it refused outright, which was more conservative
            # than the facts warranted: the color knobs preview fine over OSC.
            # What must stay true is that no settings.json is touched.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Find-WTSettingsPath { throw 'must not look for a settings.json off Windows Terminal' }
            Mock Write-SettingsAtomic { throw 'must not write a settings.json off Windows Terminal' }
            Mock Write-Host {}
            Mock Start-Sleep {}
            # Fails on the console read rather than on settings.json -- there is
            # no keyboard in a test run. Any settings.json access would throw
            # from the mocks above instead, which is what is under test.
            try { Invoke-TerminalStyleTune -StyleName 'eva' } catch { }
            Should -Invoke Find-WTSettingsPath -Times 0
            Should -Invoke Write-SettingsAtomic -Times 0
        }

        # The two below were live assertions until the tuner grew its
        # IsInputRedirected guard. They could only ever reach the notice by
        # riding the very crash that guard now prevents: under Pester stdin is
        # always redirected, so every run drove the tuner into
        # [Console]::KeyAvailable and swallowed the exception in `catch { }`.
        # The branch needs a real console, so they are source assertions now --
        # the same trade Picker-NonWT.Tests.ps1 documents for the picker.

        # Asserted on the AST, not on the source text: the function CARRIES a
        # comment quoting the wrong wording ("promising 'a new window shows
        # them' sent the user to ..."), so a plain -Not -Match over
        # ScriptBlock.ToString() fails on the comment that documents the fix.
        # Only what Write-Host is actually handed counts.
        BeforeAll {
            function script:Get-TunerWriteHostText {
                $ast = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast
                $cmds = @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Write-Host' }, $true))
                $out = foreach ($c in $cmds) {
                    $c.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                        ForEach-Object { $_.Value }
                }
                return @($out)
            }
        }

        It 'warns that opacity and font will not preview' {
            # Setting expectations matters more here than usual: two of the five
            # knobs move on screen and three do not, and a user who does not know
            # that will read the stillness as the tuner being broken.
            (script:Get-TunerWriteHostText) -match 'cannot show them' | Should -Not -BeNullOrEmpty
        }

        It 'does not promise a new window will show opacity or font' {
            # It used to say "only a new window shows them", which is not true off
            # Windows Terminal: the .terminal profile carries colors and a
            # background image and nothing else, and no escape sequence carries a
            # font or an opacity. The advice sent the user to open a window and
            # compare an unchanged font against the screenshot.
            (script:Get-TunerWriteHostText) -match 'new window shows them' | Should -BeNullOrEmpty
        }
    }
}

Describe 'the tuner guards on a non-console session' {
    InModuleScope TerminalStyles {
        It 'explains itself instead of throwing .NET console internals' {
            # Regression: the tuner printed its notice, slept 900ms, wrote the
            # first preview, repainted the terminal with the OSC packet, cleared
            # the screen and drew the whole five-knob menu -- and only THEN died
            # on [Console]::KeyAvailable with "Cannot see if a key has been
            # pressed ... Try Console.In.Peek", exiting 0 so the shell shim
            # reported success. Anything running tstyles with stdin detached --
            # a pipe, a redirect, a CI step, an agent shell -- hit it, and lost
            # its scrollback to the Clear-Host on the way. The picker was fixed
            # for this in 0.8.0; the tuner kept the bug.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Start-Sleep { throw 'the tuner must not sleep before bailing out' }
            # Clear-Host must NOT run: the guard returns before the tuner takes
            # over the screen, so the user's scrollback survives.
            Mock Clear-Host { throw 'the tuner must not clear the screen before bailing out' }
            Mock Get-AdjustedScheme { throw 'the tuner must not build a preview without a console' }
            Mock Write-SettingsAtomic { throw 'the tuner must not write settings.json without a console' }

            if ([Console]::IsInputRedirected) {
                { Invoke-TerminalStyleTune -StyleName 'eva' } | Should -Not -Throw
                Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'needs an interactive terminal' }
            } else {
                Set-ItResult -Skipped -Because 'this test run has a real console attached'
            }
        }

        It 'guards before it touches the screen, not after' {
            # Ordering is the whole fix: the crash itself was survivable, the
            # repainted terminal and the wiped scrollback were not. Pinned on
            # the AST -- the guard's own comment names Clear-Host, so comparing
            # source-text offsets finds the comment and passes/fails on prose.
            $ast = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast

            $guard = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and
                $n.Clauses[0].Item1.Extent.Text -match 'IsInputRedirected' }, $true))
            $guard.Count | Should -Be 1 -Because 'the tuner must have exactly one redirected-input guard'
            $guardAt = $guard[0].Extent.StartOffset

            foreach ($name in 'Clear-Host', 'Start-Sleep') {
                $calls = @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq $name }, $true))
                $calls.Count | Should -BeGreaterThan 0 -Because "$name should still be reachable after the guard"
                foreach ($c in $calls) {
                    $c.Extent.StartOffset | Should -BeGreaterThan $guardAt -Because "the guard must run before $name"
                }
            }

            # ...and before anything repaints the live terminal over OSC.
            $writes = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Expression.Extent.Text -match 'Console\]::Out' }, $true))
            $writes.Count | Should -BeGreaterThan 0
            foreach ($w in $writes) {
                $w.Extent.StartOffset | Should -BeGreaterThan $guardAt -Because 'the guard must run before the terminal is repainted'
            }
        }
    }
}

Describe 'the tuner only skips its revert when the style really went on' {
    # $applied gates the finally block's safety net (restore settings.json, OSC
    # reset, restore the title). It used to be set unconditionally right after
    # Apply-StyleDirect -- but every one of that function's give-up paths is a
    # NON-terminating Write-Error followed by return, so a failed apply sailed
    # past, skipped the reset, and left the tuner's preview colors painted over
    # an already-restored settings.json.
    InModuleScope TerminalStyles {

        It 'treats a deliberate Write-Error bail-out as "not applied"' {
            function script:Fake-Apply {
                [CmdletBinding()] param([Parameter(Mandatory)][string]$StyleName)
                Write-Error "Style '$StyleName' not found."
                return
            }
            $e = $null
            script:Fake-Apply -StyleName 'nope' -ErrorVariable e -ErrorAction SilentlyContinue
            $applied = -not @($e | Where-Object { $_.CategoryInfo.Activity -eq 'Write-Error' }).Count
            $applied | Should -BeFalse
        }

        It 'treats incidental cmdlet noise as "applied"' {
            # The Copy-Item/Remove-Item that install current-style.ps1 run AFTER
            # the style is on. Counting their noise as failure would revert a
            # good apply -- the opposite bug, and a worse one.
            function script:Fake-ApplyNoisy {
                [CmdletBinding()] param([Parameter(Mandatory)][string]$StyleName, [string]$Missing, [string]$Dest)
                Copy-Item -LiteralPath $Missing -Destination $Dest -Force
                'applied'
            }
            $missing = Join-Path $TestDrive 'definitely-not-here.txt'
            $dest    = Join-Path $TestDrive 'dest.txt'
            $e = $null
            script:Fake-ApplyNoisy -StyleName 'eva' -Missing $missing -Dest $dest `
                -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            $e | Should -Not -BeNullOrEmpty   # there WAS an error...
            $applied = -not @($e | Where-Object { $_.CategoryInfo.Activity -eq 'Write-Error' }).Count
            $applied | Should -BeTrue         # ...but the style still went on
        }

        It 'gates $applied on the filtered count, not on any error at all' {
            # Pins the shape in the source: a bare `-not $applyErr` would flip
            # the incidental case above and silently revert good applies.
            $fn = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $fn | Should -Match "CategoryInfo\.Activity\s+-eq\s+'Write-Error'"
            # (?m) so $ anchors per line, not just at end-of-string -- without it
            # this assertion would pass no matter what the body contained.
            $fn | Should -Not -Match '(?m)^\s*\$applied\s*=\s*\$true\s*$'
        }
    }
}

Describe 'the tuner warns about the collision that actually loses work' {
    InModuleScope TerminalStyles {

        It 'checks the USER styles dir, which is where a save would land' {
            # Save-TunedStyle writes to $DataRoot/styles/<name>. A user style of
            # that name is REPLACED. The prompt only ever checked the module's
            # bundled dir -- so it warned about the harmless collision (a bundled
            # style is merely shadowed and comes back) and stayed silent about
            # the destructive one.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match "userDir = Join-Path \(Join-Path \`$script:TStylesDataRoot 'styles'\)"
            $src | Should -Match 'will be REPLACED'
        }

        It 'still mentions shadowing for a bundled name' {
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match 'shadows bundled'
        }

        It 'asks before replacing, rather than after' {
            # Both branches gate on a y/N answer and `continue` back to the name
            # prompt, so declining re-asks instead of saving anyway.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $block = [regex]::Match($src, '(?s)\$userDir = .*?\n            \}').Value
            $block | Should -Match "warn -notmatch '\^\(\?i\)y'"
            ([regex]::Matches($block, 'continue')).Count | Should -BeGreaterOrEqual 2
        }
    }
}

Describe 'cancelling the tuner puts the terminal back' {
    InModuleScope TerminalStyles {

        It 'restores the base style off Windows Terminal, not the terminal default' {
            # Same bug the picker had. Get-OscResetPacket hands colour control to
            # the TERMINAL's own defaults -- correct on Windows Terminal, where
            # settings.json has just been restored and WT repaints from it, and
            # wrong everywhere else, where the style being tuned was itself only
            # escape sequences. Esc dropped the user to a stock palette instead
            # of the style they opened the tuner on.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match '\$restoreBaseLook = \{'
            # ...and it restores the style the user OPENED, not the working base.
            # Those differ for a tuned style: tuning 'eva-night' resolves its
            # base 'eva' as the working base, so restoring $baseScheme repainted
            # the terminal as eva and called it "Reverted." -- leaving the user
            # on a style they had never chosen.
            $block = [regex]::Match($src, '(?s)\$restoreBaseLook = \{.*?\n    \}').Value
            $block | Should -Match 'Get-SchemeOscPacket -Scheme \$openedScheme'
            $block | Should -Not -Match 'Get-SchemeOscPacket -Scheme \$baseScheme'
        }

        It 'routes every exit path through the same restore' {
            # Three of them: Esc in the key loop, an aborted save, and the
            # finally-block safety net. They drifted apart once already.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            ([regex]::Matches($src, '& \$restoreBaseLook')).Count | Should -BeGreaterOrEqual 3
        }

        It 'still hands control back to Windows Terminal there' {
            # On WT the reset is right: the file is restored and WT repaints.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $block = [regex]::Match($src, '(?s)\$restoreBaseLook = \{.*?\n    \}').Value
            $block | Should -Match 'Get-OscResetPacket'
            $block | Should -Match 'Write-SettingsAtomic'
        }

        It 'guards the finally against restoring before it exists' {
            # An exception thrown before $baseScheme is read would otherwise turn
            # a real error into a null-invocation error on the way out.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match 'if \(\$restoreBaseLook\) \{ & \$restoreBaseLook \}'
        }
    }
}
