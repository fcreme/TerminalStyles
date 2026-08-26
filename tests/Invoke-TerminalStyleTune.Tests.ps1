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

        It 'warns that opacity and font will not preview' {
            # Setting expectations matters more here than usual: two of the five
            # knobs move on screen and three do not, and a user who does not know
            # that will read the stillness as the tuner being broken.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Start-Sleep {}
            try { Invoke-TerminalStyleTune -StyleName 'eva' } catch { }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'cannot show them' }
        }

        It 'does not promise a new window will show opacity or font' {
            # It used to say "only a new window shows them", which is not true off
            # Windows Terminal: the .terminal profile carries colors and a
            # background image and nothing else, and no escape sequence carries a
            # font or an opacity. The advice sent the user to open a window and
            # compare an unchanged font against the screenshot.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Start-Sleep {}
            try { Invoke-TerminalStyleTune -StyleName 'eva' } catch { }
            Should -Not -Invoke Write-Host -ParameterFilter { "$Object" -match 'new window shows them' }
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
