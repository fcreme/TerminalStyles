# WezTerm adds the files it `require`s to its config reload watch list, so
# rewriting the generated module restyles a RUNNING window. That makes it the one
# terminal off Windows where arrowing through the picker can preview the whole
# style -- background, font, padding, cursor shape, opacity -- and not just the
# palette the OSC retint carries.
#
# Two properties are load-bearing and neither is obvious from reading the picker:
# the preview runs on the input thread and must never reach the network, and Esc
# must put back exactly what was there INCLUDING nothing.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'the picker previews a style on WezTerm without touching the network' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Both halves of the sandbox: the data root for the cache the
            # resolver reads, and -HomeDir for the module path it writes.
            $script:TStylesDataRoot = $TestDrive
            $script:home = Join-Path $TestDrive ('h-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path (Join-Path $script:home '.config/wezterm') -Force | Out-Null
            $script:styleDir = Join-Path $TestDrive 'styles/probe'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
        }

        It 'answers from disk or answers nothing, but never fetches' {
            # The picker previews on every arrow key, and the fetching tier can
            # spend four serial attempts at -TimeoutSec 10 before it concludes
            # anything -- on the thread reading the keystrokes.
            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $script:styleDir -NoFetch | Should -BeNullOrEmpty
            $script:hits | Should -Be 0 -Because 'the preview path runs on the input thread'
        }

        It 'does not fetch through the inheritance hop either' {
            # A tuned style inherits its base's background, and that hop resolves
            # the base -- which would fetch on the thread we just protected.
            $kid = Join-Path $TestDrive 'styles/kid'
            New-Item -ItemType Directory -Path $kid -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'styles/base') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $kid 'tune.json'), '{"base":"base"}',
                [System.Text.UTF8Encoding]::new($false))

            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $kid -NoFetch | Should -BeNullOrEmpty
            $script:hits | Should -Be 0
        }

        It 'still fetches without the switch, or the switch proves nothing' {
            # The control. A -NoFetch test passes just as well against a function
            # that never fetched at all.
            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Out-Null
            $script:hits | Should -BeGreaterThan 0 -Because 'the default path is the one -NoFetch opts out of'
        }

        It 'writes a module a preview can restore from, and one it can remove' {
            $scheme = [pscustomobject]@{ background = '#101010'; foreground = '#f0f0f0' }
            $path = Get-WezTermModulePath -HomeDir $script:home

            # Case 1: nothing there before. Esc has to leave nothing there after,
            # or a first-ever picker run on a clean machine invents a file.
            [System.IO.File]::Exists($path) | Should -BeFalse
            Write-WezTermStyleModule -StyleName 'probe' -Scheme $scheme -Theme $null `
                -BackgroundImage $null -HomeDir $script:home | Should -Not -Be 'failed'
            [System.IO.File]::Exists($path) | Should -BeTrue
            Remove-Item -LiteralPath $path -Force
            [System.IO.File]::Exists($path) | Should -BeFalse

            # Case 2: something there before. Esc has to put those bytes back
            # exactly -- it is the user's active style, not ours to rewrite.
            $original = [System.Text.Encoding]::UTF8.GetBytes("-- the user's own`n")
            [System.IO.File]::WriteAllBytes($path, $original)
            Write-WezTermStyleModule -StyleName 'probe' -Scheme $scheme -Theme $null `
                -BackgroundImage $null -HomeDir $script:home | Out-Null
            ([System.IO.File]::ReadAllBytes($path) -join ',') | Should -Not -Be ($original -join ',') `
                -Because 'the preview has to actually change something, or there is nothing to restore'
            [System.IO.File]::WriteAllBytes($path, $original)
            ([System.IO.File]::ReadAllBytes($path) -join ',') | Should -Be ($original -join ',')
        }
    }
}

Describe 'the picker wires that preview in' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        }

        It 'previews on the branch that used to do nothing but retint' {
            # Structural because the picker body needs a console and a keypress
            # loop no test can drive -- the same reason Get-PickerViewport and
            # Get-PickerFramePlan were carved out as pure functions.
            $script:picker | Should -Match '& \$previewWezTerm \$i' `
                -Because 'the non-settings-file branch is where a WezTerm preview happens'
        }

        It 'restores on Esc, next to the settings.json restore it mirrors' {
            $script:picker | Should -Match '& \$restoreWezTerm' `
                -Because 'a rejected preview must not outlive the picker'
        }

        It 'asks for the background without fetching' {
            $script:picker | Should -Match 'Get-StyleBundledBackground -StyleDir \$sd -NoFetch' `
                -Because 'the preview runs on the input thread'
        }

        It 'restores through the preview session, which writes nothing when nothing was previewed' {
            # Restoring over a file the picker never touched is not free: it
            # bumps the mtime, and WezTerm is watching. The session restores
            # nothing when it wrote nothing (tests/FilePreviewSession.Tests.ps1).
            $script:picker | Should -Match 'Restore-FilePreview -Session \$wezSession'
            $script:picker | Should -Match '-Session \$wezSession'
        }
    }
}

Describe 'previewing a style does not move the layout' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # Three real bundled styles that genuinely differ: sober is normal
            # weight with padding 16, eva is semi-bold with 12, gitbash is
            # normal with 10. Every style declares Cascadia Code at size 11, so
            # weight and padding are the whole of what a reader sees as "this
            # theme's text is a different size".
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $script:load = {
                param($n)
                @{ Scheme = [System.IO.File]::ReadAllText((Join-Path $repoRoot "styles/$n/scheme.json"),
                       [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                   Theme  = [System.IO.File]::ReadAllText((Join-Path $repoRoot "styles/$n/theme.json"),
                       [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json }
            }
            $script:sober = & $script:load 'sober'
            $script:eva   = & $script:load 'eva'
            $script:git   = & $script:load 'gitbash'
            $script:layoutOf = {
                param($lua)
                @{ Font    = (($lua -split "`n") | Where-Object { $_ -match 'config\.font =' })        -join ''
                   Size    = (($lua -split "`n") | Where-Object { $_ -match 'config\.font_size' })     -join ''
                   Padding = (($lua -split "`n") | Where-Object { $_ -match 'config\.window_padding' })-join '' }
            }
        }

        It 'keeps font, size and padding identical across every previewed style' {
            # WezTerm reflows the terminal for a font_size or window_padding
            # change, so previewing them makes the text jump on every arrow key.
            # Pinned to whatever is applied, the frame holds still and only the
            # colours move.
            $pinned = $script:sober.Theme
            $seen = @()
            foreach ($st in @($script:sober, $script:eva, $script:git)) {
                $lua = Get-WezTermStyleLua -StyleName 'probe' -Scheme $st.Scheme -Theme $st.Theme `
                           -BackgroundImage $null -LayoutTheme $pinned
                $seen += ,(& $script:layoutOf $lua)
            }
            @($seen).Count | Should -Be 3 -Because 'a loop that never ran would pass silently'
            foreach ($k in 'Font', 'Size', 'Padding') {
                @($seen | ForEach-Object { $_[$k] } | Sort-Object -Unique).Count |
                    Should -Be 1 -Because "$k must not change while arrowing through the list"
            }
        }

        It 'still swaps the colours it is previewing' {
            # The counterpart, or "nothing moves" would be satisfied by a
            # preview that did nothing at all.
            $names = @()
            foreach ($st in @($script:sober, $script:eva, $script:git)) {
                $lua = Get-WezTermStyleLua -StyleName $st.Theme.colorScheme -Scheme $st.Scheme `
                           -Theme $st.Theme -BackgroundImage $null -LayoutTheme $script:sober.Theme
                $names += (($lua -split "`n") | Where-Object { $_ -match 'config\.color_scheme' }) -join ''
            }
            @($names | Sort-Object -Unique).Count | Should -Be 3 `
                -Because 'the palette is the thing a preview is for'
        }

        It 'gives the confirmed style its own layout back' {
            # Unbound means "this style's own", which is the normal apply. The
            # pin is a preview concern and must not leak into it.
            $a = & $script:layoutOf (Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:eva.Scheme `
                     -Theme $script:eva.Theme -BackgroundImage $null)
            $b = & $script:layoutOf (Get-WezTermStyleLua -StyleName 'sober' -Scheme $script:sober.Scheme `
                     -Theme $script:sober.Theme -BackgroundImage $null)
            $a.Padding | Should -Not -Be $b.Padding -Because 'eva pads 12 and sober pads 16'
            $a.Font    | Should -Not -Be $b.Font    -Because 'eva is semi-bold and sober is normal'
        }

        It 'omits layout entirely when nothing is applied to pin to' {
            # A first run, or an active style since deleted. $null is a real
            # answer here -- the user's own wezterm.lua settings hold, which are
            # as stable as anything else we could have picked.
            $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:eva.Scheme -Theme $script:eva.Theme `
                       -BackgroundImage $null -LayoutTheme $null
            $lua | Should -Not -Match 'config\.font'
            $lua | Should -Not -Match 'config\.window_padding'
            $lua | Should -Match 'config\.color_scheme' -Because 'the style is still previewed'
        }

        It 'the picker pins it, and binds $null rather than leaving it unbound' {
            # Unbound would mean "this style's own layout", which is the bug
            # this fixes. Structural because the picker body needs a console.
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match '-LayoutTheme \$wezLayoutTheme' `
                -Because 'the preview has to pass the pin'
            $src | Should -Match '\$wezLayoutTheme = \$null' `
                -Because 'no applied style must reach the writer as an explicit $null'
        }
    }
}

Describe 'per tab, the picker previews a style in its own tab only' {
    # Per tab, the module already carries every installed style's look, so the
    # picker stops rewriting it: an arrow key tags this pane with the preview
    # tag, which the generated Lua honours only on the pane that carries it, and
    # Esc puts this tab's own tag back. Built by pure functions, because the
    # picker body that sends them needs a console no test can give it.
    InModuleScope TerminalStyles {
        It 'previews by tag, not by rewriting the module' {
            Get-WezTermPickerPreviewPacket -StyleName 'rain' |
                Should -BeExactly (Get-WezTermTagPacket -Value '/preview/rain')
        }

        It 'Esc puts back this tab''s own tag and hands colours to the window scheme' {
            # The reset first: the preview's OSC retint painted this pane, and
            # the window scheme -- this tab's style, through its tag -- has to
            # show through again.
            $script:tabRecord = 'kitty'
            Mock Get-WezTermTabRecord { $script:tabRecord }
            $p = Get-WezTermPickerRevertPacket
            $p.StartsWith((Get-OscResetPacket)) | Should -BeTrue
            $p.EndsWith((Get-WezTermTagPacket -Value 'kitty')) | Should -BeTrue
            $p | Should -BeExactly ((Get-OscResetPacket) + (Get-WezTermTagPacket -Value 'kitty'))

            # A tab with no record was never tagged, so the preview tag is
            # cleared rather than replaced: the tab shows what it showed before.
            $script:tabRecord = $null
            Get-WezTermPickerRevertPacket |
                Should -BeExactly ((Get-OscResetPacket) + (Get-WezTermTagPacket -Value ''))
            Should -Invoke Get-WezTermTabRecord -Times 2 -Exactly
        }

        It 'an unstyled tab gets the unstyled tag back, not an empty one' {
            # '' in the record is a tab reset to unstyled. An empty tag would
            # clear the variable, and an untagged pane shows its pin -- the
            # new-tab default it was first seen with, not unstyled.
            Mock Get-WezTermTabRecord { '' }
            Get-WezTermPickerRevertPacket |
                Should -BeExactly ((Get-OscResetPacket) + (Get-WezTermTagPacket -Value $script:WezTermTagUnstyled))
        }

        It 'the revert packet is the reset in per-tab mode' {
            # A regression pin on the arm the picker's, the tuner's and show's
            # Esc now select per tab: the window scheme already follows this
            # tab's tag, and colours set on a pane by OSC outrank it, so a
            # re-emitted palette would hold the pane instead of its tag.
            $s = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8'; cursorColor = '#ff3d5a' }
            Get-RevertOscPacket -UseSettingsFile:$true -HadStartingStyle:$true -StartingScheme $s |
                Should -BeExactly (Get-OscResetPacket)
        }
    }
}

Describe 'per tab, a picker confirm whose module write fails says so and puts the tab back' {
    # Publish-StyleWezTermConfig prints why it failed and returns nothing, and
    # the picker clears the screen after it: the notice was wiped, "Style
    # applied" printed over it, and the pane kept the PREVIEW tag while its
    # record kept the style it had. Get-WezTermPickerCommit reads the publish's
    # captured output (6>&1) so the picker body only prints and sends what it
    # answers. Driven here through the real publisher, sandboxed as above.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData = $script:TStylesDataRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:h = Join-Path $script:root 'home'
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:TStylesDataRoot = Join-Path $script:root 'data'
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            Mock Get-StyleBundledBackground { $null }
            Mock Write-HostOscPacket { $true }
            Mock Test-WezTermPerTab { $true }
            Mock Test-WezTermStyleWired { $true }
            Mock Invoke-WezTermTabTag { 'painted' }
            Mock Get-WezTermTabRecord { 'eva' }
            $script:publish = {
                @(Publish-StyleWezTermConfig -StyleName 'forest' -StyleDir '/tmp/forest' -Scheme $script:scheme `
                    -Kind 'WezTerm' -HomeDir $script:h 6>&1)
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedData }

        It 'a written module is applied: the success line, nothing to send, nothing to add' {
            Mock Write-WezTermTabModule { 'written' }
            $c = Get-WezTermPickerCommit -Output (& $script:publish)
            $c.Applied | Should -BeTrue
            $c.Label | Should -BeExactly '  Style applied: '
            $c.NameColor | Should -Be 'Green'
            $c.Packet | Should -BeNullOrEmpty
            @($c.Notes).Count | Should -Be 0
            Should -Invoke Invoke-WezTermTabTag -Times 1 -Exactly -Because 'the publish tagged this tab itself'
        }

        It 'a failed write is not applied: its notice is kept for below the clear, and this tab goes back' {
            Mock Write-WezTermTabModule { 'failed' }
            $c = Get-WezTermPickerCommit -Output (& $script:publish)
            $c.Applied | Should -BeFalse
            $c.Label | Should -BeExactly '  Not applied in WezTerm: '
            $c.NameColor | Should -Be 'Yellow'
            # The preview tag goes, and this tab's own tag comes back, with the
            # palette handed to the window scheme that tag selects.
            $c.Packet | Should -BeExactly ((Get-OscResetPacket) + (Get-WezTermTagPacket -Value 'eva'))
            $text = @($c.Notes | ForEach-Object { "$($_.MessageData)" }) -join "`n"
            $text | Should -Match ([regex]::Escape('Could not write ' + (Get-WezTermModulePath -HomeDir $script:h)))
            $text | Should -Match ([regex]::Escape('This tab keeps the colors it has now'))
            Should -Invoke Invoke-WezTermTabTag -Times 0 -Exactly -Because 'a failed write tags nothing'
        }
    }
}
