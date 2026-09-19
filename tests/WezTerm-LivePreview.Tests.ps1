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

        It 'gates the restore on having written, like the settings.json half' {
            # Restoring over a file the picker never touched is not free: it
            # bumps the mtime, and WezTerm is watching.
            $script:picker | Should -Match '\$pickerState\.WezWritten' `
                -Because 'a picker that wrote nothing must restore nothing'
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
