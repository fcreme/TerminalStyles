# Pester 5 tests for the non-Windows-Terminal apply/reset path and the
# current-style record that backs it.
#
# These cover the branch taken on macOS/Linux terminals: no settings.json is
# read or written, colors go out as an OSC packet, and the applied style is
# recorded so a new tab can re-emit it at startup.
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

Describe 'current-style record' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
        }

        It 'round-trips the applied style name' {
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'AppleTerminal'
            (Get-CurrentStyleRecord).name | Should -Be 'eva'
        }

        It 'records which terminal it was applied on' {
            Set-CurrentStyleRecord -StyleName 'umbrella' -Kind 'ITerm2'
            (Get-CurrentStyleRecord).terminal | Should -Be 'ITerm2'
        }

        It 'returns $null when no record exists' {
            Clear-CurrentStyleRecord
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'returns $null rather than throwing on a corrupt record' {
            # Self-healing matters here: this runs at shell startup, and an
            # exception would break every new tab until the file was deleted
            # by hand.
            [System.IO.File]::WriteAllText((Get-CurrentStyleRecordPath), '{not json at all',
                [System.Text.UTF8Encoding]::new($false))
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'returns $null for a record with no name field' {
            [System.IO.File]::WriteAllText((Get-CurrentStyleRecordPath), '{"terminal":"ITerm2"}',
                [System.Text.UTF8Encoding]::new($false))
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'clears an existing record' {
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'AppleTerminal'
            Clear-CurrentStyleRecord
            Test-Path -LiteralPath (Get-CurrentStyleRecordPath) | Should -BeFalse
        }

        It 'clearing a missing record is not an error' {
            Clear-CurrentStyleRecord
            { Clear-CurrentStyleRecord } | Should -Not -Throw
        }

        It 'overwrites rather than appends on re-apply' {
            Set-CurrentStyleRecord -StyleName 'eva'      -Kind 'AppleTerminal'
            Set-CurrentStyleRecord -StyleName 'umbrella' -Kind 'AppleTerminal'
            (Get-CurrentStyleRecord).name | Should -Be 'umbrella'
        }
    }
}

Describe 'Invoke-TerminalStyleOscApply / Reset' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:emitted = @()
            # Returns $true: Write-HostOscPacket's contract is "did the bytes
            # reach a terminal?", and callers propagate that to decide whether
            # to tell the user the colors did not land. A mock returning nothing
            # would model a console that is never there.
            Mock Write-HostOscPacket { param($Packet) $script:emitted += $Packet; $true }
        }

        It 'emits a packet on a terminal that supports OSC' {
            $scheme = [pscustomobject]@{ name = 't'; background = '#000000'; foreground = '#ffffff' }
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeExactly 'painted'
            Should -Invoke Write-HostOscPacket -Times 1
        }

        It 'emits nothing on a terminal without OSC support' {
            # 'Unknown' does support OSC, so this needs a kind that genuinely
            # cannot take one. Capability is what gates it, not the kind name.
            Mock Get-TerminalCapability { @{ OscPalette = $false } }
            $scheme = [pscustomobject]@{ name = 't'; background = '#000000' }
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeExactly 'unsupported'
            Should -Invoke Write-HostOscPacket -Times 0
        }

        It 'says nocolors, not noterminal, for a scheme it cannot read' {
            # The collapse this status exists to undo. Both answers used to be
            # $false, and the caller's one branch on that value blamed the
            # terminal -- which had painted the previous style perfectly and was
            # never sent anything this time. The writer is mocked to SUCCEED, so
            # a $false here can only have come from the empty packet.
            $scheme = [pscustomobject]@{ name = 't'; background = 'black'; foreground = 'white' }
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeExactly 'nocolors'
            Should -Invoke Write-HostOscPacket -Times 0 `
                -Because 'there was nothing to write, so the writer is not what failed'
        }

        It 'says noterminal when there was a packet and nothing took it' {
            Mock Write-HostOscPacket { $false }
            $scheme = [pscustomobject]@{ name = 't'; background = '#0a0006' }
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeExactly 'noterminal'
            Should -Invoke Write-HostOscPacket -Times 1
        }

        It 'emits the reset packet' {
            Invoke-TerminalStyleOscReset -Kind 'AppleTerminal' | Should -BeTrue
            $script:emitted -join '' | Should -Be (Get-OscResetPacket)
        }
    }
}

Describe 'Apply-StyleNonWT' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:TStylesCurrent  = Join-Path $TestDrive 'current-style.ps1'

            # A minimal style on disk: scheme + a prompt to install.
            $script:styleDir = Join-Path $TestDrive 'styles/fake'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fake","background":"#101010","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'profile.ps1'),
                '# fake prompt', [System.Text.UTF8Encoding]::new($false))

            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Write-HostOscPacket { }
            Mock Write-Host { }
            # No bundled background: keeps the test off the network entirely.
            Mock Get-StyleBundledBackground { $null }
        }

        It 'records the applied style' {
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir
            (Get-CurrentStyleRecord).name | Should -Be 'fake'
        }

        It 'emits the color packet' {
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir
            Should -Invoke Write-HostOscPacket -Times 1 -Scope It
        }

        It "installs the style's prompt to current-style.ps1" {
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeTrue
        }

        It '-KeepPrompt leaves the user prompt in control' {
            # The style's visuals still apply; only the prompt install is skipped.
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
            (Get-CurrentStyleRecord).name | Should -Be 'fake'
        }

        It '-KeepPrompt removes a prompt left by a previous apply' {
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeTrue
            Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }

        It 'never reads or writes a Windows Terminal settings.json' {
            # The whole point of this branch: no settings file is involved.
            Mock Find-WTSettingsPath { throw 'Find-WTSettingsPath must not be called off Windows Terminal' }
            Mock Write-SettingsFile  { throw 'Write-SettingsFile must not be called off Windows Terminal' }
            { Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir } | Should -Not -Throw
        }

        It 'errors when the style has no scheme.json' {
            $empty = Join-Path $TestDrive 'styles/empty'
            New-Item -ItemType Directory -Force -Path $empty | Out-Null
            { Apply-StyleNonWT -StyleName 'empty' -StyleDir $empty -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe 'the zsh/bash half of an apply says when it could not stage' {
    # Set-ShellStyleState stages current-style.osc and current-prompt.sh -- the
    # two files that decide what every FUTURE zsh/bash tab looks like -- inside
    # one try whose catch was literally `} catch { }`, and it returned nothing.
    # Both call sites invoked it as a bare statement, because there was nothing
    # to check. So a write failure on the first of those files skipped the rest,
    # left the PREVIOUS style staged, and `tstyles <style>` printed its ordinary
    # green success block over the top of it.
    #
    # Best-effort is the right policy here and is documented as deliberate: a
    # PowerShell user with no shell integration must not see an apply fail over
    # these. Best effort still has to REPORT, and the asymmetry made that
    # obvious -- the half that repaints THIS tab reports its failure in three
    # careful yellow lines, and the half that decides every future tab said
    # nothing at all.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

            $script:styleDir = Join-Path $script:TStylesDataRoot 'styles/fake'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fake","background":"#101010","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'prompt.sh'),
                "# fake shell prompt`n", [System.Text.UTF8Encoding]::new($false))
            $script:scheme = [pscustomobject]@{
                name = 'fake'; background = '#101010'; foreground = '#f0f0f0'
            }

            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Write-HostOscPacket { $false }
            Mock Get-StyleBundledBackground { $null }

            # A directory that does not exist, so [System.IO.File]::WriteAllText
            # throws a DirectoryNotFoundException on the FIRST statement in the
            # try -- the same shape as an unwritable data root, with no chmod,
            # which keeps this portable to the Windows legs of CI.
            function script:Break-Staging {
                Mock Get-ShellOscPath { Join-Path $script:TStylesDataRoot 'no-such-dir/current-style.osc' }
            }
        }

        It 'returns ok when it staged everything' {
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme |
                Should -Be 'ok'
        }

        It 'returns failed rather than swallowing the write error' {
            script:Break-Staging
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme |
                Should -Be 'failed'
        }

        It 'the apply names the directory it could not write into' {
            script:Break-Staging
            $out = Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir 6>&1 | Out-String

            $out | Should -Match 'Could not stage'
            $out | Should -Match ([regex]::Escape($script:TStylesDataRoot)) `
                -Because 'the user cannot fix a directory the message never names'
            $out | Should -Match 'PREVIOUS style' `
                -Because 'that is what every new zsh/bash tab will come up in'
        }

        It 'stops claiming the style is saved for the next tab' {
            # The sentence the staging failure falsifies, word for word. It is
            # printed only when stdout is redirected, which is the case a
            # machine might act on -- and the case every CI leg runs under.
            if (-not [Console]::IsOutputRedirected) {
                Set-ItResult -Skipped -Because 'that sentence is only printed to a redirected host'
                return
            }
            script:Break-Staging
            $out = Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir 6>&1 | Out-String
            $out | Should -Not -Match 'The style is saved'
        }

        It 'says none of that on an ordinary apply' {
            # A warning printed when nothing is wrong is the same defect wearing
            # the other hat.
            $out = Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir 6>&1 | Out-String
            $out | Should -Not -Match 'Could not stage'
            [System.IO.File]::ReadAllText((Get-ShellOscPath), [System.Text.UTF8Encoding]::new($false)) |
                Should -Be (Get-SchemeOscPacket -Scheme $script:scheme) -Because 'the fixture must really stage'
        }

        It 'does not leak its status into the command output' {
            # The call sites have to CONSUME the new return value. A bare
            # `Set-ShellStyleState ...` statement would now emit 'ok' straight
            # into `tstyles`' own output.
            $out = Apply-StyleNonWT -StyleName 'fake' -StyleDir $script:styleDir 6>&1 |
                   Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] } |
                   Out-String
            $out.Trim() | Should -BeNullOrEmpty
        }
    }
}

Describe 'Reset-StyleNonWT' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:TStylesCurrent  = Join-Path $TestDrive 'current-style.ps1'
            Mock Get-TerminalKind { 'AppleTerminal' }
            # $true, not `{ }`. A mock that returns nothing is $false to the
            # caller, so these four drove the FAILED-repaint path while being
            # named for the ordinary one -- and nothing here could tell, because
            # the function printed the same sentence either way. The Describe
            # below is the one that measures which sentence.
            Mock Write-HostOscPacket { $true }
            Mock Write-Host { }
        }

        It 'clears the style record' {
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'AppleTerminal'
            Reset-StyleNonWT
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'removes current-style.ps1 so the user prompt returns' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# x', [System.Text.UTF8Encoding]::new($false))
            Reset-StyleNonWT
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }

        It 'emits the OSC reset packet' {
            Reset-StyleNonWT
            Should -Invoke Write-HostOscPacket -Times 1 -Scope It
        }

        It 'is safe to run when no style was ever applied' {
            { Reset-StyleNonWT } | Should -Not -Throw
        }
    }
}

Describe 'Reset-StyleNonWT says which of the two things happened' {
    # "Reset <terminal> to its unstyled default." was printed whether the OSC
    # packet reached a terminal or reached nothing at all. Measured on main, with
    # the data root and $script:TStylesCurrent sandboxed: the two opposite
    # outcomes produced byte-identical output.
    #
    # Its apply sibling has said the narrow truth since 0.8.27 -- "Colors were
    # not applied to this session: its output is redirected, so there is no
    # terminal to repaint" -- and the reset half, on the same terminal in the
    # same session, still claimed the repaint.
    #
    # Not mocking Write-Host here, deliberately: the Describe above does, and
    # that is exactly why four tests could drive this branch without seeing it.
    # The information stream is captured instead.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:TStylesCurrent  = Join-Path $TestDrive 'current-style.ps1'
            Mock Get-TerminalKind { 'AppleTerminal' }
        }

        It 'does not claim a repaint that did not happen' {
            Mock Write-HostOscPacket { $false }
            $out = (Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String)

            Should -Invoke Write-HostOscPacket -Times 1 -Scope It `
                -Because 'a branch that was never reached would report green'
            $out | Should -Not -Match 'to its unstyled default'
            $out | Should -Match 'no terminal to repaint'
        }

        It 'still says what DID happen when the repaint failed' {
            # The record and the staged shell files really are gone, so a new
            # tab really does come up unstyled. Saying nothing at all would be
            # the opposite defect.
            Mock Write-HostOscPacket { $false }
            $out = (Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String)
            $out | Should -Match 'a new tab comes up unstyled'
            $out | Should -Match 'Open a new tab to restore your default prompt'
        }

        It 'blames the terminal only when the terminal is really what refused' {
            # Not redirected, and the packet still did not land. "its output is
            # redirected" would be false here, and it is the half a user acts on.
            Mock Write-HostOscPacket { $false }
            $out = (Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String)
            $out | Should -Not -Match 'to its unstyled default'
            $out | Should -Not -Match 'output is redirected'
            $out | Should -Match 'did not accept the color reset'
        }

        It 'does print the success line when the reset really painted' {
            # The complement, so a fix that simply always reports failure fails
            # here. Named in full: -match is substring-matching, and "unstyled"
            # alone appears in the failure wording too.
            Mock Write-HostOscPacket { $true }
            $out = (Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String)
            $out | Should -Match 'to its unstyled default'
            $out | Should -Not -Match 'no terminal to repaint'
            $out | Should -Not -Match 'did not accept'
        }

        It 'names the terminal it reset' {
            Mock Write-HostOscPacket { $true }
            $out = (Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String)
            $out | Should -Match ([regex]::Escape((Get-TerminalDisplayName -Kind 'AppleTerminal')))
        }
    }
}

Describe 'Write-HostOscPacket reports whether it painted' {
    InModuleScope TerminalStyles {
        It 'reports failure when output is redirected' {
            # The bug this guards: `tstyles <name>` printed "Style applied" and
            # recorded the style while painting nothing, because the emit
            # function returned void and the caller reported the terminal's
            # CAPABILITY instead of the actual outcome. Anything running tstyles
            # through a pipe or an agent shell saw a success message and an
            # unchanged window.
            if ([Console]::IsOutputRedirected) {
                Write-HostOscPacket -Packet "test" | Should -BeFalse
                Invoke-TerminalStyleOscApply -Scheme ([pscustomobject]@{ background = '#000000' }) `
                    -Kind 'AppleTerminal' | Should -BeExactly 'noterminal'
            } else {
                Set-ItResult -Skipped -Because 'this run has a real console attached'
            }
        }

        It 'reports failure for an empty packet' {
            Write-HostOscPacket -Packet '' | Should -BeFalse
        }

        It 'returns a real boolean' {
            Write-HostOscPacket -Packet '' | Should -BeOfType [bool]
        }
    }
}

Describe 'Apply-StyleNonWT names the right culprit for colors that did not land' {
    # The half of the tri-state nobody pinned: what the apply SAYS. The packet
    # length was the only signal that a scheme had rendered to nothing, and it
    # was thrown away, so "there was no terminal" and "the style carried no
    # colour this tool can read" arrived as the same $false and the one branch
    # on it blamed the terminal. Measured on a real pty: `tstyles namedcolors`
    # printed "Style applied" and then "this terminal did not accept live color
    # changes" on a terminal that repainted perfectly for `tstyles sober` in the
    # same session seconds later.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

            $script:sDir = Join-Path $script:TStylesDataRoot 'styles/claim'
            New-Item -ItemType Directory -Force -Path $script:sDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:sDir 'prompt.sh'),
                "# claim shell prompt`n", $script:enc)

            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Get-StyleBundledBackground { $null }
            # A terminal that takes everything it is handed, so nothing below
            # can be explained by the writer. Whatever the apply then says about
            # colours has to come from the STYLE.
            Mock Write-HostOscPacket { $true }

            function script:Set-Scheme([string]$Json) {
                [System.IO.File]::WriteAllText((Join-Path $script:sDir 'scheme.json'), $Json, $script:enc)
            }
            # -OutputRedirected is bound explicitly, and defaults to $false --
            # the REAL-CONSOLE arm, which is the one that carried the wrong
            # sentence and the one no CI leg can otherwise reach, since every
            # leg runs with stdout redirected.
            function script:Get-ApplyOutput {
                param([bool]$Redirected = $false)
                Apply-StyleNonWT -StyleName 'claim' -StyleDir $script:sDir `
                    -OutputRedirected $Redirected 6>&1 | Out-String
            }
        }

        It 'blames the style, not the terminal, when nothing was readable' {
            # X11 colour words -- which the terminal itself would have honoured,
            # and which ConvertTo-NormalHex refuses. The packet is empty, so
            # nothing was ever sent and the terminal cannot have refused it.
            script:Set-Scheme '{"name":"claim","background":"black","foreground":"white"}'
            $out = script:Get-ApplyOutput

            $out | Should -Not -Match 'did not accept' `
                -Because 'the terminal was never sent anything to refuse'
            $out | Should -Match 'no colors this tool can read'
            $out | Should -Match '#rrggbb' -Because 'the user has to be told what a readable value looks like'
        }

        It 'still reports the real no-terminal case' {
            # The other side of the same fork: a packet that existed and did not
            # land. Revert the status and case one starts printing this too,
            # which is the collapse.
            Mock Write-HostOscPacket { $false }
            script:Set-Scheme '{"name":"claim","background":"#0a0006"}'
            $out = script:Get-ApplyOutput

            $out | Should -Match 'did not accept live color changes'
            $out | Should -Not -Match 'no colors this tool can read'
        }

        It 'names the slots it skipped when only some of the scheme was readable' {
            # Quieter and worse: the packet is non-empty, so it paints, reports
            # unqualified success, and the slots it left out keep the PREVIOUS
            # style's colours -- OSC only sets what it emits.
            script:Set-Scheme '{"name":"claim","background":"#0a0006","foreground":"white","red":"#c41e3a"}'
            $out = script:Get-ApplyOutput

            $out | Should -Match 'skipped'
            $out | Should -Match '1 color value in this style is not readable'
            $out | Should -Match 'foreground' -Because 'a slot that kept the old colour must be named'
            $out | Should -Not -Match 'background' -Because 'that one was applied'
        }

        It 'counts the skipped slots rather than saying value(s)' {
            script:Set-Scheme '{"name":"claim","background":"#0a0006","foreground":"white","red":"crimson"}'
            $out = script:Get-ApplyOutput

            $out | Should -Match '2 color values in this style are not readable'
            $out | Should -Match 'foreground, red'
        }

        It 'says none of that for a style it could read in full' {
            script:Set-Scheme '{"name":"claim","background":"#0a0006","foreground":"#ffe8e8"}'
            $out = script:Get-ApplyOutput

            $out | Should -Not -Match 'skipped'
            $out | Should -Not -Match 'no colors this tool can read'
            $out | Should -Not -Match 'did not accept'
        }

        It 'does not claim a prompt was applied when the style ships none' {
            # The second false clause in the same sentence. current-style.ps1 is
            # written only for a style carrying profile.ps1; this one does not,
            # so "only the prompt was applied" named the one thing that had also
            # not happened.
            Mock Write-HostOscPacket { $false }
            script:Set-Scheme '{"name":"claim","background":"#0a0006"}'
            $out = script:Get-ApplyOutput

            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse -Because 'the fixture must really ship no prompt'
            $out | Should -Match 'did not accept live color changes' -Because 'the arm under test must be the one that ran'
            $out | Should -Not -Match 'only the prompt was applied'
            $out | Should -Match 'nothing from this style reached this session'
        }

        It 'still says the prompt was applied when it really was' {
            Mock Write-HostOscPacket { $false }
            script:Set-Scheme '{"name":"claim","background":"#0a0006"}'
            [System.IO.File]::WriteAllText((Join-Path $script:sDir 'profile.ps1'), "# claim prompt`n", $script:enc)
            $out = script:Get-ApplyOutput

            $out | Should -Match 'only the prompt was applied'
        }
    }
}

Describe 'Apply-StyleNonWT resolves the background at most once' {
    # Get-StyleBundledBackground can make up to four serial 10-second HTTP
    # attempts against the gifs branch before giving up. It used to be called
    # twice per apply -- once as the LEFT operand of an -and whose right side
    # would have short-circuited it away, and once again below -- so an apply
    # for a style with no cached image could sit on the network for up to 80
    # seconds, all of it AFTER "Style applied" had already printed.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:TStylesCurrent  = Join-Path $TestDrive 'current-style.ps1'

            $script:styleDir = Join-Path $TestDrive 'styles/bgfake'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"bgfake","background":"#101010","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))
            # A theme.json is required to reach the "can't show" block at all.
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'theme.json'),
                '{"colorScheme":"bgfake","backgroundImage":"{{BACKGROUND_IMAGE}}"}',
                [System.Text.UTF8Encoding]::new($false))

            Mock Write-HostOscPacket { }
            Mock Write-Host { }
            Mock New-AppleTerminalProfile { $null }
            Mock Get-StyleBundledBackground { Join-Path $TestDrive 'bg.gif' }
        }

        It 'calls it once on a terminal that can show an image' {
            # AppleTerminal: the capability is true, so the "can't show" check
            # short-circuits before the call and only the profile builder asks.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Apply-StyleNonWT -StyleName 'bgfake' -StyleDir $script:styleDir
            Should -Invoke Get-StyleBundledBackground -Times 1 -Exactly -Scope It
        }

        It 'calls it once on a terminal that cannot' {
            # Ghostty: the capability is false, so the "can't show" check has to
            # ask -- and the profile builder must then not ask again.
            Mock Get-TerminalKind { 'Ghostty' }
            Apply-StyleNonWT -StyleName 'bgfake' -StyleDir $script:styleDir
            Should -Invoke Get-StyleBundledBackground -Times 1 -Exactly -Scope It
        }

        It 'still reports an image it cannot show' {
            Mock Get-TerminalKind { 'Ghostty' }
            Apply-StyleNonWT -StyleName 'bgfake' -StyleDir $script:styleDir
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match "can't show" }
        }

        It 'never asks when the style ships no theme.json' {
            # No theme.json means no background field to resolve and nothing to
            # report as unsupported, on a terminal that could not show it anyway.
            Mock Get-TerminalKind { 'Ghostty' }
            Remove-Item -LiteralPath (Join-Path $script:styleDir 'theme.json') -Force
            Apply-StyleNonWT -StyleName 'bgfake' -StyleDir $script:styleDir
            Should -Invoke Get-StyleBundledBackground -Times 0 -Exactly -Scope It
        }
    }
}

# The notice reaches the SCREEN, not just the helper's return value.
#
# On 0.8.28, driving this same function over the bundled `forest` on
# Terminal.app, the full transcript was:
#
#   Style applied: forest
#   Terminal:      Terminal.app
#   Terminal.app can't show: tab color.
#
# with caps Font=False Opacity=False CursorShape=False Padding=False and the
# theme asking for font=Cascadia Code 11pt, cursorShape=filledBox, padding=12.
# One of five named, and the one named was the one the user was least likely to
# be looking for.
Describe 'Apply-StyleNonWT names every field this terminal cannot show' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

            $script:sDir = Join-Path $script:TStylesDataRoot 'styles/forestish'
            New-Item -ItemType Directory -Force -Path $script:sDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:sDir 'scheme.json'),
                '{"name":"forestish","background":"#0d1a12","foreground":"#e8f0e8"}', $script:enc)
            # The bundled `forest` field set, which fifteen of the sixteen
            # shipped styles share.
            [System.IO.File]::WriteAllText((Join-Path $script:sDir 'theme.json'), (@'
{
    "colorScheme": "forestish",
    "tabTitle": "FOREST",
    "tabColor": "#d49680",
    "cursorShape": "filledBox",
    "useAcrylic": false,
    "opacity": 100,
    "font": { "face": "Cascadia Code", "size": 11 },
    "padding": "12",
    "backgroundImage": "{{BACKGROUND_IMAGE}}"
}
'@), $script:enc)

            Mock Write-HostOscPacket { $true }
            Mock Get-StyleBundledBackground { $null }
            # Publish-StyleWezTermConfig is NOT given a -HomeDir by the apply, so
            # on Kind=WezTerm the real ~/.config/wezterm/terminalstyles.lua is
            # what it would write. Mocked for that reason, not for speed.
            Mock Publish-StyleWezTermConfig { $null }
            Mock Publish-StyleBackgroundProfile { $null }

            function script:Get-ApplyOutput {
                param([string]$Kind)
                Mock Get-TerminalKind { $Kind }.GetNewClosure()
                Apply-StyleNonWT -StyleName 'forestish' -StyleDir $script:sDir `
                    -OutputRedirected $false 6>&1 | Out-String
            }
        }

        It 'names the font, cursor shape and padding Terminal.app drops' {
            $out = script:Get-ApplyOutput -Kind 'AppleTerminal'

            $out | Should -Match "can't show:"
            $out | Should -Match 'font'
            $out | Should -Match 'cursor shape'
            $out | Should -Match 'padding'
            $out | Should -Match 'tab color'
        }

        It 'does not name the tab title, which the style''s prompt sets everywhere' {
            # -match is case-insensitive and matches substrings, so this is asked
            # of the notice line alone rather than of a transcript that also
            # carries the style's own tabTitle text.
            $line = @(script:Get-ApplyOutput -Kind 'AppleTerminal' -split "`n" |
                      Where-Object { $_ -match "can't show" })
            @($line).Count | Should -Be 1
            $line[0] | Should -Not -Match 'tab title'
        }

        It 'names only what WezTerm really cannot do' {
            # The record drives it: font and padding are written by
            # Get-WezTermStyleLua, so they must not appear.
            $line = @(script:Get-ApplyOutput -Kind 'WezTerm' -split "`n" |
                      Where-Object { $_ -match "can't show" })
            @($line).Count | Should -Be 1
            $line[0] | Should -Match 'cursor shape'
            $line[0] | Should -Match 'tab color'
            $line[0] | Should -Not -Match 'font'
            $line[0] | Should -Not -Match 'padding'
        }

        It 'says nothing at all for a style that declares nothing' {
            [System.IO.File]::WriteAllText((Join-Path $script:sDir 'theme.json'),
                '{"colorScheme":"forestish"}', $script:enc)
            script:Get-ApplyOutput -Kind 'AppleTerminal' | Should -Not -Match "can't show"
        }
    }
}
