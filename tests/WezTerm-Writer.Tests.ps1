# Pester 5 tests: the generated WezTerm Lua module.
#
# WHY THIS FILE IS SHAPED LIKE THIS. Nothing here can ask a running WezTerm
# whether the config it produced is valid -- WezTerm is not installed on the
# machines this suite runs on, and a wrong key does not degrade: WezTerm shows an
# error window and falls back to the DEFAULT config, costing the user their whole
# terminal appearance rather than just the style.
#
# So the assertions pin the exact keys and shapes the WezTerm documentation and
# its `config/src/background.rs` define, and Get-WezTermStyleLua is the single
# place that decides them. Where a rule was verified against wezterm's source
# rather than its docs, the test says so, because those are the ones a future
# reader will most want to re-check.
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

Describe 'Get-WezTermStyleLua' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:scheme = [pscustomobject]@{
                name = 'eva'; background = '#0a0006'; foreground = '#ffe8e8'
                cursorColor = '#ff3d5a'; selectionBackground = '#4a0a14'
                black = '#0a0006'; red = '#c41e3a'; green = '#7aae7a'; yellow = '#e8c547'
                blue = '#6ed5ff'; purple = '#e5419e'; cyan = '#b8c5e0'; white = '#ffe8e8'
                brightBlack = '#4a1a20'; brightRed = '#ff3d5a'; brightGreen = '#9ec99e'
                brightYellow = '#f4d87a'; brightBlue = '#a8c5e8'; brightPurple = '#ff85b8'
                brightCyan = '#d4ddf0'; brightWhite = '#ffffff'
            }
            $script:theme = [pscustomobject]@{
                font = [pscustomobject]@{ face = 'Cascadia Code'; size = 11; weight = 'semi-bold' }
                padding = '12'
                backgroundImageOpacity = 0.4
                backgroundImageStretchMode = 'uniformToFill'
            }
        }

        Context 'the palette' {
            It 'defines a named scheme and selects it' {
                # A NAMED scheme, not a bare `colors` block: the precedence
                # between color_scheme and colors flipped in 20220903, and a
                # named scheme behaves the same on both sides of that change.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme
                $lua | Should -Match "config\.color_schemes\['TerminalStyles eva'\]"
                $lua | Should -Match "config\.color_scheme = 'TerminalStyles eva'"
            }

            It 'emits ansi and brights as exactly eight entries each' {
                # WezTerm's type is Option<[RgbaColor; 8]>. Seven or sixteen is a
                # config error, not a truncation -- and a config error is the
                # user's whole appearance.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme
                foreach ($key in 'ansi', 'brights') {
                    $m = [regex]::Match($lua, "$key = \{\s*([^}]*)\}")
                    $m.Success | Should -BeTrue -Because "$key must be present"
                    @($m.Groups[1].Value -split ',' | Where-Object { $_.Trim() }).Count |
                        Should -Be 8 -Because "$key is a fixed 8-element array"
                }
            }

            It 'puts the ansi colours in WezTerm order, not scheme.json order' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme
                $m = [regex]::Match($lua, "ansi = \{\s*([^}]*)\}")
                ($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") } |
                    Where-Object { $_ }) | Should -Be @(
                        '#0a0006','#c41e3a','#7aae7a','#e8c547','#6ed5ff','#e5419e','#b8c5e0','#ffe8e8')
            }

            It 'sets cursor_border as well as cursor_bg' {
                # Only setting cursor_bg leaves the block cursor's outline wrong.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme
                $lua | Should -Match "cursor_bg = '#ff3d5a'"
                $lua | Should -Match "cursor_border = '#ff3d5a'"
            }

            It 'drops a colour WezTerm would reject rather than emitting it' {
                # SrgbaTuple::from_str requires 1 + digits*3 == length, so
                # #RRGGBBAA is REJECTED. Emitting one is a config error.
                $bad = $script:scheme.PSObject.Copy()
                $bad.cursorColor = '#ff3d5aff'
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $bad
                $lua | Should -Not -Match 'ff3d5aff'
                $lua | Should -Match "background = '#0a0006'" -Because 'the valid ones still land'
            }
        }

        Context 'the background layers -- the reason this writer exists' {
            It 'emits the GIF as a layer with an absolute path' {
                # File.path is a plain String handed to fs::read: no config-dir
                # expansion, no ~, no $HOME. A path it cannot read is dropped
                # with only a log line -- no background and no error.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme `
                    -Theme $script:theme -BackgroundImage '/abs/eva/background.gif'
                $lua | Should -Match "source = \{ File = \{ path = '/abs/eva/background\.gif' \} \}"
            }

            It 'puts a solid colour layer underneath the image' {
                # Once ANY background list exists WezTerm stops drawing the
                # pane's solid rect and clears the frame to transparent, so a
                # translucent or non-covering GIF would show the desktop.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme `
                    -Theme $script:theme -BackgroundImage '/abs/eva/background.gif'
                $colorAt = $lua.IndexOf("source = { Color = '#0a0006' }")
                $fileAt  = $lua.IndexOf('source = { File =')
                $colorAt | Should -BeGreaterThan -1 -Because 'the base layer must exist'
                $colorAt | Should -BeLessThan $fileAt -Because 'layer 1 is the deepest'
            }

            It 'carries backgroundImageOpacity onto the layer, invariantly formatted' {
                # On a comma-decimal culture "0.4" would be written "0,4", which
                # is a Lua syntax error -- and a syntax error here is the whole
                # config. The same class of bug as the trash-stamp calendar.
                $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
                    $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme `
                        -Theme $script:theme -BackgroundImage '/abs/b.gif'
                    $lua | Should -Match 'opacity = 0\.4'
                    $lua | Should -Not -Match 'opacity = 0,4'
                } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved }
            }

            It 'emits no background block for a style that ships none' {
                $lua = Get-WezTermStyleLua -StyleName 'sober' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Not -Match 'config\.background'
            }
        }

        Context 'theme.json' {
            It 'maps the Windows Terminal font weight to a WezTerm one' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Match "config\.font = wezterm\.font\('Cascadia Code', \{ weight = 'DemiBold' \} \)|weight = 'DemiBold'"
                $lua | Should -Not -Match "semi-bold" -Because 'that is not a WezTerm weight name'
            }

            It 'expands the padding shorthand to all four sides' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Match 'window_padding = \{ left = 12, right = 12, top = 12, bottom = 12 \}'
            }

            It 'does not claim opacity, which the capability table also refuses' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Not -Match 'window_background_opacity' `
                    -Because 'Get-TerminalCapability does not claim Opacity for WezTerm'
            }
        }

        Context 'the file is a loadable Lua chunk' {
            It 'opens with a require and returns the module table' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme
                $lua | Should -Match "local wezterm = require 'wezterm'"
                $lua | Should -Match 'function M\.apply_to_config\(config\)'
                $lua.TrimEnd() | Should -Match 'return M$'
            }

            It 'balances its braces and parentheses' {
                # Cheap, but it is the one structural property a wrong edit to
                # the generator breaks first, and the cost of shipping it broken
                # is the user's entire config.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme `
                    -Theme $script:theme -BackgroundImage '/abs/b.gif'
                ($lua.ToCharArray() | Where-Object { $_ -eq '{' }).Count |
                    Should -Be ($lua.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                ($lua.ToCharArray() | Where-Object { $_ -eq '(' }).Count |
                    Should -Be ($lua.ToCharArray() | Where-Object { $_ -eq ')' }).Count
            }

            It 'escapes a quote in a style name instead of ending the string' {
                # An unescaped quote is not a wrong colour, it is a syntax error.
                $lua = Get-WezTermStyleLua -StyleName "it's" -Scheme $script:scheme
                $lua | Should -Match "TerminalStyles it\\\\'s|TerminalStyles it\\'s"
                ($lua.ToCharArray() | Where-Object { $_ -eq '{' }).Count |
                    Should -Be ($lua.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            }
        }
    }
}

Describe 'Write-WezTermStyleModule' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
        }

        It 'writes into ~/.config/wezterm, which is on package.path' {
            # Fixed target on purpose: package.path carries that directory
            # whatever the config file's own location, so `require` resolves
            # even for a user whose config is ~/.wezterm.lua.
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme -HomeDir $script:h |
                Should -Be 'written'
            Test-Path -LiteralPath (Join-Path $script:h '.config/wezterm/terminalstyles.lua') |
                Should -BeTrue
        }

        It 'writes UTF-8 with no BOM' {
            # A BOM ahead of a Lua chunk is a parse error.
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme -HomeDir $script:h | Out-Null
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:h '.config/wezterm/terminalstyles.lua'))
            $bytes[0..2] | Should -Not -Be ([byte[]]@(0xEF,0xBB,0xBF))
        }

        It 'reports unchanged rather than rewriting an identical file' {
            # Rewriting would trip WezTerm's reload watch and repaint the window
            # for a style that did not change.
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme -HomeDir $script:h | Out-Null
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme -HomeDir $script:h |
                Should -Be 'unchanged'
        }

        It 'drops a background path that does not exist rather than emitting it' {
            # It would be dropped by WezTerm anyway, silently, into a log file.
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme `
                -BackgroundImage (Join-Path $script:h 'nope.gif') -HomeDir $script:h | Out-Null
            [System.IO.File]::ReadAllText((Join-Path $script:h '.config/wezterm/terminalstyles.lua')) |
                Should -Not -Match 'nope\.gif'
        }

        It 'returns a status, never a bare boolean' {
            Write-WezTermStyleModule -StyleName 'eva' -Scheme $script:scheme -HomeDir $script:h |
                Should -BeOfType [string]
        }
    }
}

Describe 'Test-WezTermStyleWired' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $script:h '.config/wezterm') -Force | Out-Null
        }

        It 'sees the line the tool tells the user to add' {
            [System.IO.File]::WriteAllText((Join-Path $script:h '.config/wezterm/wezterm.lua'),
                "local config = {}`n" + (Get-WezTermWiringLine) + "`nreturn config`n")
            Test-WezTermStyleWired -HomeDir $script:h | Should -BeTrue
        }

        It 'still sees it when the user reformatted it' {
            # Matching the require, not the literal line: a user who renamed the
            # local or moved it into their own function is still wired up.
            [System.IO.File]::WriteAllText((Join-Path $script:h '.config/wezterm/wezterm.lua'),
                "local mine = require('terminalstyles')`nmine.apply_to_config(config)`n")
            Test-WezTermStyleWired -HomeDir $script:h | Should -BeTrue
        }

        It 'is false for a config that never loads the module' {
            [System.IO.File]::WriteAllText((Join-Path $script:h '.config/wezterm/wezterm.lua'),
                "local config = {}`nreturn config`n")
            Test-WezTermStyleWired -HomeDir $script:h | Should -BeFalse
        }

        It 'is false when there is no config at all' {
            Test-WezTermStyleWired -HomeDir $script:h | Should -BeFalse
        }

        It 'never creates a file it was only asked about' {
            Test-WezTermStyleWired -HomeDir $script:h | Out-Null
            Test-Path -LiteralPath (Join-Path $script:h '.config/wezterm/wezterm.lua') | Should -BeFalse
        }
    }
}

Describe 'both apply paths reach both publishers' {
    # The duplication guard. Publish-StyleWezTermConfig is a sibling of
    # Publish-StyleBackgroundProfile rather than a branch inside it, so the two
    # apply paths each call two publishers -- and the picker forgetting one of
    # them is a defect this project has already shipped once, recorded in the
    # comment above the picker's call site.
    InModuleScope TerminalStyles {
        It 'Apply-StyleNonWT calls both' {
            $src = (Get-Command Apply-StyleNonWT).ScriptBlock.ToString()
            $src | Should -Match 'Publish-StyleBackgroundProfile'
            $src | Should -Match 'Publish-StyleWezTermConfig'
        }

        It 'the picker calls both' {
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match 'Publish-StyleBackgroundProfile'
            $src | Should -Match 'Publish-StyleWezTermConfig'
        }

        It 'the WezTerm publisher declines every other terminal' {
            Publish-StyleWezTermConfig -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'the WezTerm capability table matches what the writer emits' {
    InModuleScope TerminalStyles {
        It 'claims exactly what Get-WezTermStyleLua writes' {
            $caps = Get-TerminalCapability -Kind 'WezTerm'
            $caps.OscPalette      | Should -BeTrue
            $caps.BackgroundImage | Should -BeTrue -Because 'the animated GIF is the point'
            $caps.Font            | Should -BeTrue
            $caps.Padding         | Should -BeTrue
            $caps.Persist         | Should -BeTrue
        }

        It 'claims nothing the writer does not deliver' {
            # The rule the capability table exists for: a claimed capability that
            # no code delivers makes a style report success, paint nothing, and
            # suppress the notice that would have explained why.
            $caps = Get-TerminalCapability -Kind 'WezTerm'
            $caps.Opacity     | Should -BeFalse
            $caps.CursorShape | Should -BeFalse
            $caps.TabTitle    | Should -BeFalse
            $caps.TabColor    | Should -BeFalse
        }
    }
}
