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
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeTrue
            Should -Invoke Write-HostOscPacket -Times 1
        }

        It 'emits nothing on a terminal without OSC support' {
            # 'Unknown' does support OSC, so this needs a kind that genuinely
            # cannot take one. Capability is what gates it, not the kind name.
            Mock Get-TerminalCapability { @{ OscPalette = $false } }
            $scheme = [pscustomobject]@{ name = 't'; background = '#000000' }
            Invoke-TerminalStyleOscApply -Scheme $scheme -Kind 'AppleTerminal' | Should -BeFalse
            Should -Invoke Write-HostOscPacket -Times 0
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
            Mock Write-HostOscPacket { }
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
                    -Kind 'AppleTerminal' | Should -BeFalse
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
