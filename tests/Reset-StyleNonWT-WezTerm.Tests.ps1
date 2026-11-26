# Pester 5 tests: `tstyles reset` in WezTerm takes the style out of the
# generated module, and says the terminal is unstyled only once it is.
#
# THE BUG. In WezTerm a style lives in the generated terminalstyles.lua, which
# every window loads through the require line the README asks for. Reset never
# touched it. It sent the OSC reset, which hands the colours back to WezTerm's
# configured palette -- and with the module loaded, the configured palette is
# the style's own color_scheme. So nothing on screen changed, every new window
# still came up in the whole style, and reset printed "Reset WezTerm to its
# unstyled default." (or "a new tab comes up unstyled") while clearing the
# record, so `tstyles current` then reported no style at all.
#
# SANDBOXING. The module path is NOT under the data root: it is resolved from
# the live $HOME and $XDG_CONFIG_HOME. So overriding $script:TStylesDataRoot
# alone does not contain it, and on a developer machine running this suite from
# WezTerm an unmocked reset would rewrite the developer's real module. Every
# test here mocks Get-WezTermModulePath into its own TestDrive folder, and
# Write-HostOscPacket so no reset packet reaches the terminal running the suite.
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

Describe 'tstyles reset in WezTerm takes the style out of the generated module' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedModule  = $script:TStylesModuleRoot
            $script:savedCurrent = $script:TStylesCurrent

            # A fresh folder per test: Pester clears TestDrive only when a block
            # ends, so a module one test left would be the next test's fixture.
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'
            $script:wezPath = Join-Path $script:root 'terminalstyles.lua'

            Mock Get-TerminalKind { 'WezTerm' }
            Mock Get-WezTermModulePath { $script:wezPath }
            Mock Write-HostOscPacket { $true }
            Mock Show-UpdateNoticeIfAvailable {}
            # The single-style world these tests describe. Unmocked, the answer
            # would be the live $HOME's wiring line.
            Mock Test-WezTermPerTab { $false }

            # What `tstyles eva` leaves in WezTerm: the module, and the record.
            Write-WezTermStyleModule -StyleName 'eva' `
                -Scheme ([pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }) |
                Should -Be 'written'
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'WezTerm'
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesCurrent    = $script:savedCurrent
        }

        It 'tstyles reset, as dispatched, leaves no style in the module' {
            [System.IO.File]::ReadAllText($script:wezPath) |
                Should -Match ([regex]::Escape("config.color_scheme = 'TerminalStyles eva'")) `
                -Because 'the fixture has to be a real styled module, or the reset proves nothing'

            Invoke-TerminalStyle -Arg 'reset' 6>&1 | Out-Null

            [System.IO.File]::Exists($script:wezPath) | Should -BeTrue -Because 'rewritten, not deleted'
            $after = [System.IO.File]::ReadAllText($script:wezPath, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Not -Match ([regex]::Escape("config.color_scheme = 'TerminalStyles eva'")) `
                -Because 'every WezTerm window loads this file, so the style it selects is still the one on screen'
            $after | Should -BeExactly (Get-WezTermUnstyledLua)
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'says unstyled, and names the module, once the module applies nothing' {
            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            $out | Should -Match 'to its unstyled default'
            $out | Should -Match ([regex]::Escape($script:wezPath))
            $out | Should -Match ([regex]::Escape("Took the style back out of WezTerm's module"))
        }

        It 'does not say unstyled when the module could not be rewritten' {
            # A folder stands in for a module that cannot be rewritten. The
            # repaint itself landed: the success line used to depend on that
            # alone, over a module still styling this window and every new one.
            Remove-Item -LiteralPath $script:wezPath
            New-Item -ItemType Directory -Path $script:wezPath | Out-Null

            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500

            $out | Should -Not -Match 'to its unstyled default'
            $out | Should -Not -Match 'comes up unstyled'
            $out | Should -Not -Match 'Took the style back out' -Because 'nothing was taken out'
            $out | Should -Match ([regex]::Escape($script:wezPath))
            $out | Should -Match 'delete it by hand'
            $out | Should -Match 'keeps applying the last style'
            $out | Should -Match 'Open a new tab to restore your default prompt' `
                -Because 'the prompt file is removed on every path, so that line is still true'
        }

        It 'does not promise an unstyled new tab when the module could not be rewritten' {
            Remove-Item -LiteralPath $script:wezPath
            New-Item -ItemType Directory -Path $script:wezPath | Out-Null
            Mock Write-HostOscPacket { $false }

            $out = Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String -Width 500

            $out | Should -Not -Match 'a new tab comes up unstyled'
            $out | Should -Not -Match 'Took the style back out' -Because 'nothing was taken out'
            $out | Should -Match ([regex]::Escape($script:wezPath))
            $out | Should -Match 'keeps applying the last style'
        }

        It 'says a new tab comes up unstyled, and nothing about this session''s colors, once the rewrite landed' {
            # The complement of the two above: a fix that always reports failure
            # fails here. Redirected, the packet reached nothing -- but the
            # rewrite makes WezTerm reload this tab too, so "this session's
            # colors were not reset" is no longer something it can know.
            Mock Write-HostOscPacket { $false }

            $out = Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String -Width 500

            $out | Should -Match 'a new tab comes up unstyled'
            $out | Should -Match 'did not reach this session'
            $out | Should -Not -Match ([regex]::Escape("This session's colors were not reset"))
            [System.IO.File]::ReadAllText($script:wezPath, [System.Text.UTF8Encoding]::new($false)) |
                Should -BeExactly (Get-WezTermUnstyledLua)
        }

        It 'does not say this session kept its colors once WezTerm reloads without the style' {
            Mock Write-HostOscPacket { $false }

            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500

            $out | Should -Match 'did not accept the color reset'
            $out | Should -Match 'a new tab comes up unstyled'
            $out | Should -Not -Match 'so this session keeps the'
            [System.IO.File]::ReadAllText($script:wezPath, [System.Text.UTF8Encoding]::new($false)) |
                Should -BeExactly (Get-WezTermUnstyledLua)
        }

        It 'a reset in another terminal leaves the WezTerm module alone' {
            # The scope rule the VS Code half already follows, pinned the same
            # way (tests/VSCode-Writer.Tests.ps1, 'a reset in another terminal
            # leaves VS Code alone'): by the bytes. Fails a fix that clears the
            # module from every terminal kind. No Should -Invoke on
            # Get-WezTermModulePath: Pester files the BeforeEach's own call in
            # this test's history, so -Times 0 -Scope It could never pass.
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:wezPath))
            Mock Get-TerminalKind { 'AppleTerminal' }

            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500

            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:wezPath)) | Should -Be $before
            $out | Should -Not -Match ([regex]::Escape("WezTerm's module"))
        }

        It 'never creates a module where there was none' {
            # A WezTerm that never had a style applied. Fails a fix that writes
            # the unstyled module unconditionally, or that announces a clear
            # when there was nothing to clear.
            Remove-Item -LiteralPath $script:wezPath

            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500

            [System.IO.File]::Exists($script:wezPath) | Should -BeFalse
            [System.IO.Directory]::Exists($script:wezPath) | Should -BeFalse
            $out | Should -Not -Match ([regex]::Escape("WezTerm's module"))
            $out | Should -Match 'to its unstyled default' -Because 'with no module, the OSC reset is the whole reset'
        }
    }
}

Describe 'tstyles reset in per-tab WezTerm resets this tab and the default, nothing else' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedModule  = $script:TStylesModuleRoot
            $script:savedCurrent = $script:TStylesCurrent
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'
            $script:wezPath = Join-Path $script:root 'terminalstyles.lua'

            Mock Get-TerminalKind { 'WezTerm' }
            Mock Get-WezTermModulePath { $script:wezPath }
            Mock Write-HostOscPacket { $true }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Test-WezTermPerTab { $true }
            Mock Invoke-WezTermTabTag { 'painted' }
            Mock Write-WezTermTabModule { 'written' }
            Mock Clear-WezTermStyleModule { 'cleared' }
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'WezTerm'
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesCurrent    = $script:savedCurrent
        }

        It 'per-tab: tags this tab unstyled, clears the default, and leaves other tabs alone' {
            Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-Null
            Should -Invoke Invoke-WezTermTabTag -Times 1 -Exactly -ParameterFilter {
                $Value -eq '/unstyled' -and $WithReset }
            Should -Invoke Write-WezTermTabModule -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($DefaultStyle) }
            Should -Invoke Clear-WezTermStyleModule -Times 0
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }

        It 'per-tab: says it reset this tab' {
            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            $out | Should -Match ([regex]::Escape('Reset this WezTerm tab to your own look.'))
            $out | Should -Match ([regex]::Escape('New tabs open unstyled; other open tabs keep their styles.'))
            $out | Should -Not -Match 'to its unstyled default'
            $out | Should -Match 'Open a new tab to restore your default prompt'
        }

        It 'per-tab: is not refused because the default is already empty' {
            # The reset a styled-nowhere module needs: another tab may still
            # carry a style. Test-WezTermModuleStyled would call this module
            # styled whatever it holds; the point is that nothing asks it.
            Mock Write-WezTermTabModule { 'unchanged' }
            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            Should -Invoke Invoke-WezTermTabTag -Times 1 -Exactly
            $out | Should -Match ([regex]::Escape('Reset this WezTerm tab to your own look.'))
        }

        It 'per-tab: does not claim the tab was reset when the tag reached no terminal' {
            Mock Invoke-WezTermTabTag { 'noterminal' }
            $out = Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'Reset this WezTerm tab'
            $out | Should -Match 'This tab was not reset'
            $out | Should -Match ([regex]::Escape('New tabs open unstyled'))
        }

        It 'per-tab: a failed module write says this tab was reset, and that only the new-tab default failed' {
            # The tag went out before the module write, so this tab WAS reset;
            # what failed is the default new tabs open in, which lives in the
            # module. Saying neither left the user to guess which half held.
            Mock Write-WezTermTabModule { 'failed' }
            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            $out | Should -Match ([regex]::Escape('Reset this WezTerm tab to your own look'))
            $out | Should -Match 'clear the style new tabs open in from WezTerm''s module'
            $out | Should -Match ([regex]::Escape($script:wezPath))
            $out | Should -Not -Match 'New tabs open unstyled'
            $out | Should -Match 'last style you applied'
        }

        It 'per-tab: a failed module write with a tag that reached no terminal claims no reset at all' {
            Mock Write-WezTermTabModule { 'failed' }
            Mock Invoke-WezTermTabTag { 'noterminal' }
            $out = Reset-StyleNonWT -OutputRedirected:$true 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'Reset this WezTerm tab'
            $out | Should -Match 'This tab was not reset'
            $out | Should -Match 'clear the style new tabs open in from WezTerm''s module'
            $out | Should -Match ([regex]::Escape($script:wezPath))
            $out | Should -Not -Match 'New tabs open unstyled'
        }
    }
}

Describe 'tstyles reset in per-tab WezTerm, through the real writer' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedModule  = $script:TStylesModuleRoot
            $script:savedCurrent = $script:TStylesCurrent
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'
            $script:wezPath = Join-Path $script:root 'terminalstyles.lua'
            Mock Get-TerminalKind { 'WezTerm' }
            Mock Get-WezTermModulePath { $script:wezPath }
            Mock Write-HostOscPacket { $true }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Test-WezTermPerTab { $true }
            Mock Invoke-WezTermTabTag { 'painted' }
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesCurrent    = $script:savedCurrent
        }

        It 'rewrites a styled per-tab module to one with no default, and resets again on the empty one' {
            Write-WezTermTabModule -DefaultStyle 'eva' | Should -Be 'written'
            $read = { [System.IO.File]::ReadAllText($script:wezPath, [System.Text.UTF8Encoding]::new($false)) }
            (& $read) | Should -Match "local DEFAULT = 'eva'" -Because 'the fixture has a default to clear'

            $out = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            (& $read) | Should -Match 'local DEFAULT = nil'
            Test-WezTermTabModule -Path $script:wezPath | Should -BeTrue
            $out | Should -Match ([regex]::Escape('Reset this WezTerm tab to your own look.'))

            # That module is one Test-WezTermModuleStyled calls styled with no
            # default in it. A second reset must still run, and say so.
            $out2 = Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-String -Width 500
            $out2 | Should -Match ([regex]::Escape('Reset this WezTerm tab to your own look.'))
            Should -Invoke Invoke-WezTermTabTag -Times 2 -Exactly -ParameterFilter { $Value -eq '/unstyled' -and $WithReset }
        }
    }
}

Describe 'the reset help says what it does to WezTerm, and what a tab can keep' {
    InModuleScope TerminalStyles {
        It 'names WezTerm, the module, and the colors a tab can keep' {
            # Rendered through the screen path: a Detail line that never reaches
            # the screen is not help.
            $h = Show-TerminalStyleHelp -Command reset 6>&1 | Out-String -Width 500
            $h | Should -Match 'WezTerm'
            $h | Should -Match ([regex]::Escape('terminalstyles.lua'))
            # The per-tab caveat. WezTerm keeps colours an escape sequence set as
            # that tab's own, and an apply sends its packet before it writes the
            # module, so the tab a style was applied in can keep its colours
            # after a reset run elsewhere. "Every WezTerm window drops the
            # style" would be the overclaim this pins against.
            $h | Should -Match 'keep its colors'
        }
    }
}

Describe 'tstyles reset in per-tab WezTerm, through the real tab record' {
    # The record's word for unstyled is '' (Get-WezTermTabRecord); the tag's is
    # /unstyled. Recorded as the tag, a reset tab read to Get-CurrentStyleName
    # as no entry at all, which then answered with the last style applied
    # ANYWHERE: reset here, apply in another tab, and this tab reported that
    # style, and its picker opened on it. The bundled styles stay where they
    # are, so that a name the global record holds really resolves.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedCurrent = $script:TStylesCurrent
            $script:savedSock    = $env:WEZTERM_UNIX_SOCKET
            $script:savedPane    = $env:WEZTERM_PANE
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
            $script:TStylesDataRoot = $script:root
            $script:TStylesCurrent  = Join-Path $script:root 'current-style.ps1'
            $script:wezPath = Join-Path $script:root 'terminalstyles.lua'
            $env:WEZTERM_UNIX_SOCKET = Join-Path $script:root 'gui-sock'
            [System.IO.File]::WriteAllText($env:WEZTERM_UNIX_SOCKET, '')
            $env:WEZTERM_PANE = '0'
            Mock Get-TerminalKind { 'WezTerm' }
            Mock Get-WezTermModulePath { $script:wezPath }
            Mock Write-HostOscPacket { $true }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Test-WezTermPerTab { $true }
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedData
            $script:TStylesCurrent  = $script:savedCurrent
            $env:WEZTERM_UNIX_SOCKET = $script:savedSock
            $env:WEZTERM_PANE        = $script:savedPane
        }

        It 'a reset tab stays unstyled after another tab applies a style' {
            Set-WezTermTabRecord -Value 'eva' | Should -Be 'ok'
            Set-CurrentStyleRecord -StyleName 'eva' -Kind 'WezTerm'
            Get-CurrentStyleName | Should -Be 'eva' -Because 'the fixture: this tab wears eva'

            Reset-StyleNonWT -OutputRedirected:$false 6>&1 | Out-Null

            # Another tab applies kitty, which the global record now names.
            Set-CurrentStyleRecord -StyleName 'kitty' -Kind 'WezTerm'
            Get-CurrentStyleName | Should -BeNullOrEmpty -Because 'this tab was reset, whatever another tab applied since'
            Get-WezTermTabRecord | Should -BeExactly '' -Because 'reset records this tab as unstyled'
        }
    }
}
