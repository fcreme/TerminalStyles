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
# The option names and enum values this file pins were probed against a real
# wezterm 20240203-110809-5046fc22 on a developer machine, with validation on:
#
#   cat > /tmp/p.lua <<'EOF'
#   local wezterm = require 'wezterm'
#   local config = wezterm.config_builder()
#   config.<option> = <value>
#   return config
#   EOF
#   wezterm --config-file /tmp/p.lua ls-fonts 2>&1 >/dev/null
#
# config_builder() rejects an unknown field AND an invalid enum value, so empty
# output is the measurement. (A bare `local config = {}` does NOT validate, and
# a probe written that way proves nothing.) All sixteen bundled styles were
# rendered through this writer and loaded that way. None of it can run in CI,
# where there is no wezterm, which is why the values are pinned here instead.
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
            # The bundled `eva` theme.json field for field -- the shape fifteen
            # of the sixteen shipped styles have, so a test that changes one
            # field is asking about one field rather than about a fixture no
            # style resembles.
            $script:theme = [pscustomobject]@{
                colorScheme                        = 'eva'
                tabTitle                           = 'EVA // NERV'
                tabColor                           = '#ff3d5a'
                cursorShape                        = 'filledBox'
                useAcrylic                         = $false
                opacity                            = 100
                'experimental.retroTerminalEffect' = $false
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

        }

        Context 'theme.json cursorShape -> default_cursor_style' {
            It 'maps <Shape> to <Style>' -ForEach @(
                @{ Shape = 'bar';              Style = 'SteadyBar' }
                @{ Shape = 'filledBox';        Style = 'SteadyBlock' }
                @{ Shape = 'emptyBox';         Style = 'SteadyBlock' }
                @{ Shape = 'underscore';       Style = 'SteadyUnderline' }
                @{ Shape = 'doubleUnderscore'; Style = 'SteadyUnderline' }
                @{ Shape = 'vintage';          Style = 'SteadyUnderline' }
            ) {
                # All six of Windows Terminal's shapes, not the three the
                # bundled styles use: a user style may declare any of them.
                # emptyBox and doubleUnderscore have no WezTerm counterpart at
                # all -- there is no hollow cursor and no double rule -- so they
                # take the nearest shape, which is a decision this test pins
                # rather than an equivalence it claims.
                $t = $script:theme.PSObject.Copy()
                $t.cursorShape = $Shape
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Match "config\.default_cursor_style = '$Style'"
            }

            It 'emits nothing at all for a shape it does not recognise' {
                # An unknown value is not a plain cursor. Measured on wezterm
                # 20240203-110809-5046fc22:
                #   error converting Lua table to Config (... Error processing
                #   Config::default_cursor_style: `EmptyBox` is not a valid
                #   DefaultCursorStyle variant ...)
                # and a config error drops WezTerm to its DEFAULT config: the
                # user's whole terminal appearance, for one word in a theme.json
                # this project has never seen.
                $t = $script:theme.PSObject.Copy()
                $t.cursorShape = 'lozenge'
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Not -Match 'default_cursor_style'
            }

            It 'never emits a name outside the six this wezterm accepts' {
                # Probed one by one: all six below load with no output, and
                # 'EmptyBox' -- the plausible-looking name that is NOT a variant
                # -- is rejected, so the enum really is discriminated rather
                # than passed through.
                $accepted = @('SteadyBlock', 'BlinkingBlock', 'SteadyUnderline',
                              'BlinkingUnderline', 'SteadyBar', 'BlinkingBar')
                $domain = @('bar', 'vintage', 'filledBox', 'emptyBox', 'underscore',
                            'doubleUnderscore', '', $null, 'EmptyBox ', 'nonsense')
                $emitted = @($domain | ForEach-Object { Get-WezTermCursorStyle $_ } |
                             Where-Object { $_ })
                # Projected with ForEach-Object, not $x.Prop: member access on
                # an empty array yields one $null and would make this pass on a
                # mapper that returned nothing at all.
                $emitted.Count | Should -Be 6 -Because 'the six Windows Terminal shapes must all map'
                foreach ($v in $emitted) { $accepted | Should -Contain $v }
            }
        }

        Context 'theme.json opacity and useAcrylic -> window transparency' {
            It 'converts Windows Terminal''s 0-100 to WezTerm''s 0.0-1.0' {
                $t = $script:theme.PSObject.Copy()
                $t.opacity = 80
                $lua = Get-WezTermStyleLua -StyleName 'kitty' -Scheme $script:scheme -Theme $t
                $lua | Should -Match 'config\.window_background_opacity = 0\.8'
            }

            It 'writes that fraction invariantly on a comma-decimal culture' {
                # "0,8" is a Lua syntax error, and a syntax error here is the
                # user's whole config -- the same trap as the background layer's
                # opacity above.
                $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
                    $t = $script:theme.PSObject.Copy()
                    $t.opacity = 80
                    $lua = Get-WezTermStyleLua -StyleName 'kitty' -Scheme $script:scheme -Theme $t
                    $lua | Should -Match 'window_background_opacity = 0\.8'
                    $lua | Should -Not -Match 'window_background_opacity = 0,8'
                } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved }
            }

            It 'says nothing for opacity 100, which is already the default' {
                # Fifteen of the sixteen bundled styles. 1.0 IS
                # window_background_opacity's default, so emitting it would
                # state a default into a file merged with the user's own config.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Not -Match 'window_background_opacity'
            }

            It 'says nothing for an opacity that is not a number' {
                $t = $script:theme.PSObject.Copy()
                $t.opacity = 'mostly'
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Not -Match 'window_background_opacity'
            }

            It 'carries the same fraction onto the base colour layer' {
                # THE HALF THAT ACTUALLY PAINTS. wezterm's render path, read at
                # 20240203-110809-5046fc22:
                #   paint.rs      -- with a `background` list it calls
                #                    render_backgrounds() and SKIPS the branch
                #                    that does .mul_alpha(window_background_opacity)
                #   background.rs -- render_background() uses
                #                    bg_color.mul_alpha(layer.def.opacity)
                # so for every bundled style (they all ship a GIF) the layer's
                # own opacity is the alpha that reaches the screen. Without this
                # line `kitty` would paint a fully opaque colour layer over a
                # correctly transparent window and the user would see nothing.
                $t = $script:theme.PSObject.Copy()
                $t.opacity = 80
                $lua = Get-WezTermStyleLua -StyleName 'kitty' -Scheme $script:scheme `
                    -Theme $t -BackgroundImage '/abs/kitty/background.gif'

                $lines = $lua -split "`n"
                $colorAt = -1; $fileAt = -1
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($colorAt -lt 0 -and $lines[$i] -match 'source = \{ Color =') { $colorAt = $i }
                    if ($fileAt  -lt 0 -and $lines[$i] -match 'source = \{ File =')  { $fileAt  = $i }
                }
                $colorAt | Should -BeGreaterThan -1 -Because 'the base colour layer must exist'
                $fileAt  | Should -BeGreaterThan $colorAt -Because 'the image layer follows it'
                @($lines[$colorAt..$fileAt] | Where-Object { $_.Trim() -eq 'opacity = 0.8,' }).Count |
                    Should -Be 1 -Because 'the style''s opacity belongs on the layer that is drawn'
            }

            It 'leaves the base colour layer alone for an opaque style' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme `
                    -Theme $script:theme -BackgroundImage '/abs/eva/background.gif'
                $lines = $lua -split "`n"
                $colorAt = -1; $fileAt = -1
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($colorAt -lt 0 -and $lines[$i] -match 'source = \{ Color =') { $colorAt = $i }
                    if ($fileAt  -lt 0 -and $lines[$i] -match 'source = \{ File =')  { $fileAt  = $i }
                }
                $fileAt | Should -BeGreaterThan $colorAt
                @($lines[$colorAt..$fileAt] | Where-Object { $_ -match 'opacity' }).Count |
                    Should -Be 0 -Because 'opacity 100 asks for nothing anywhere'
            }

            It 'guards the macOS blur behind the platform, not the file' {
                # useAcrylic is the blur. macos_window_background_blur is
                # macOS-only, and this file is written on Linux too, where
                # config_builder REJECTS a field it does not know -- costing the
                # user the whole config for a setting that could never have done
                # anything there. So the assignment must sit INSIDE the
                # target_triple test, not merely somewhere in the file.
                $t = $script:theme.PSObject.Copy()
                $t.opacity    = 80
                $t.useAcrylic = $true
                $lua = Get-WezTermStyleLua -StyleName 'kitty' -Scheme $script:scheme -Theme $t

                $lua | Should -Match 'config\.macos_window_background_blur = 20'
                [regex]::IsMatch($lua,
                    "if wezterm\.target_triple:find\('darwin'\) then\s*\r?\n\s*config\.macos_window_background_blur = 20\s*\r?\n\s*end") |
                    Should -BeTrue -Because 'an unguarded macos_* field is a config error on Linux'
            }

            It 'emits no blur for a style that does not ask for acrylic' {
                $t = $script:theme.PSObject.Copy()
                $t.opacity = 80
                $lua = Get-WezTermStyleLua -StyleName 'sober' -Scheme $script:scheme -Theme $t
                $lua | Should -Not -Match 'macos_window_background_blur'
            }

            It 'emits no blur where the window stays opaque' {
                # Acrylic on an opaque window blurs nothing: wezterm's macOS
                # window is setOpaque_(YES) whenever window_background_opacity
                # is >= 1.0 (window/src/os/macos/window.rs,
                # update_window_shadow), which is exactly what opacity 100 gives
                # -- and what Windows Terminal shows for the same theme.json.
                $t = $script:theme.PSObject.Copy()
                $t.useAcrylic = $true
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Not -Match 'macos_window_background_blur'
            }
        }

        Context 'theme.json tabColor -> the tab bar' {
            It 'paints the active tab with the style''s accent' {
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Match "config\.colors\.tab_bar\.active_tab\.bg_color = '#ff3d5a'"
            }

            It 'MERGES into config.colors rather than replacing it' {
                # The trap. config.colors is the table the user is most likely
                # to have written themselves, and it is also where a
                # color_scheme's per-key overrides live -- so `config.colors = {`
                # would delete settings this module never asked about, in a file
                # the user cannot see being generated.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Match 'config\.colors = config\.colors or \{\}'
                $lua | Should -Match 'config\.colors\.tab_bar = config\.colors\.tab_bar or \{\}'
                $lua | Should -Match 'config\.colors\.tab_bar\.active_tab = config\.colors\.tab_bar\.active_tab or \{\}'
                $lua | Should -Not -Match 'config\.colors = \{' `
                    -Because 'a wholesale assignment is what destroys the user''s own colors'
            }

            It 'leaves the inactive tabs to WezTerm' {
                # This config is global, not per-profile, so colouring inactive
                # tabs too would paint the whole bar the accent colour and erase
                # the active/inactive distinction. Windows Terminal's tabColor
                # tints the tab of the profile in front.
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $script:theme
                $lua | Should -Not -Match 'inactive_tab'
            }

            It 'picks tab text that can be read on <Accent>' -ForEach @(
                @{ Accent = '#ffb3c6'; Text = '#000000' }   # kitty's light pink
                @{ Accent = '#ff3d5a'; Text = '#000000' }   # eva's red: still light enough
                @{ Accent = '#2a2535'; Text = '#ffffff' }   # a dark accent
            ) {
                # Windows Terminal picks the tab's text colour from the accent's
                # luminance; WezTerm keeps its default light grey unless told,
                # which is unreadable on the light accents some styles ship.
                $t = $script:theme.PSObject.Copy()
                $t.tabColor = $Accent
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Match "config\.colors\.tab_bar\.active_tab\.fg_color = '$Text'"
            }

            It 'says nothing about the tab bar for a colour WezTerm would reject' {
                # #RRGGBBAA is not three channels; SrgbaTuple::from_str rejects
                # it, and a rejected colour is a config error.
                $t = $script:theme.PSObject.Copy()
                $t.tabColor = '#ff3d5aff'
                $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -Theme $t
                $lua | Should -Not -Match 'tab_bar'
            }

            It 'says nothing about the tab bar for a style that declares no tabColor' {
                $bare = [pscustomobject]@{ padding = '12' }
                $lua = Get-WezTermStyleLua -StyleName 'plain' -Scheme $script:scheme -Theme $bare
                $lua | Should -Not -Match 'tab_bar'
            }
        }

        Context 'backgroundImageStretchMode -> BackgroundSize' {
            It 'only ever emits a size this wezterm parses' {
                # BackgroundSize is Contain, Cover, or a dimension. `none` used
                # to map to 'Auto', which is not a variant, and the style that
                # declares `none` is the bundled `kitty` -- so applying it wrote
                # a module that took the user's whole WezTerm config down:
                #   error converting Lua table to Config (... Error processing
                #   background.width (types: Config, BackgroundLayer) expected
                #   either 'Contain', 'Cover', a number, or a string of the form
                #   '123px' ... but got String)
                $grammar = '^(Contain|Cover|\d+(\.\d+)?(px|%|pt|cell)?)$'
                foreach ($mode in 'uniform', 'uniformToFill', 'fill', 'none', '', 'wibble') {
                    Get-WezTermBackgroundSize $mode | Should -Match $grammar `
                        -Because "'$mode' must map to a BackgroundSize wezterm accepts"
                }
            }

            It 'is asking about every bundled style, not an empty list' {
                # The -ForEach below is expanded at DISCOVERY; if it ever
                # expanded to nothing the case would vanish and this file would
                # still report green, which is the failure mode this project
                # keeps finding in its own suite.
                $dirs = @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') -Directory)
                $themed = @($dirs | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'theme.json') })
                $themed.Count | Should -BeGreaterThan 0
                $themed.Count | Should -Be $dirs.Count -Because 'every bundled style ships a theme.json'
            }

            It 'keeps every bundled style inside that grammar' -ForEach @(
                @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') -Directory |
                    ForEach-Object {
                        $p = Join-Path $_.FullName 'theme.json'
                        if (Test-Path -LiteralPath $p) {
                            @{ Style = $_.Name
                               Mode  = [string]((Get-Content -LiteralPath $p -Raw | ConvertFrom-Json).backgroundImageStretchMode) }
                        }
                    })
            ) {
                # Driven off the shipped theme.json files rather than a list
                # here, so a style added with a new stretch mode is measured
                # instead of assumed. <Style> asks for <Mode>.
                Get-WezTermBackgroundSize $Mode |
                    Should -Match '^(Contain|Cover|\d+(\.\d+)?(px|%|pt|cell)?)$' `
                    -Because "$Style ships backgroundImageStretchMode '$Mode'"
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

            # THE BACKSLASH HALF, which the quote case above hid for as long as
            # it existed. `$Value -replace '\\', '\\\\'` is wrong by a factor of
            # two: a doubled backslash in the PATTERN means one backslash, but
            # in .NET's REPLACEMENT string only `$` is special, so four
            # backslashes stayed four. Lua decodes `\\\\` as two, so the path
            # WezTerm opened was not the path that was passed in --
            # `C:\Users\me\bg.gif` arrived as `C:\\Users\\me\\bg.gif`. It never
            # produced a syntax error, which is why nothing noticed.
            #
            # Round-tripped rather than regexed: the property that matters is
            # that the value survives, and a decoder makes the test say so in
            # the same terms WezTerm does. No Lua runtime exists on the CI
            # machines, so the decoder is the short-string rule by hand --
            # `\\` is one backslash, `\'` is a quote.
            BeforeAll {
                function script:ConvertFrom-LuaShortString {
                    param([Parameter(Mandatory)][string]$Literal)
                    $Literal.StartsWith("'") -and $Literal.EndsWith("'") | Should -BeTrue `
                        -Because 'the escaper must return a closed single-quoted literal'
                    $body = $Literal.Substring(1, $Literal.Length - 2)
                    $out = [System.Text.StringBuilder]::new()
                    for ($i = 0; $i -lt $body.Length; $i++) {
                        if ($body[$i] -ne '\') { [void]$out.Append($body[$i]); continue }
                        $i++
                        switch ($body[$i]) {
                            'r'     { [void]$out.Append("`r") }
                            'n'     { [void]$out.Append("`n") }
                            default { [void]$out.Append($body[$i]) }   # \\ -> \ , \' -> '
                        }
                    }
                    $out.ToString()
                }
            }

            It 'round-trips a Windows path through the Lua literal' {
                $path = 'C:\Users\me\bg.gif'
                $lit  = ConvertTo-WezTermLuaString -Value $path
                $lit | Should -Be "'C:\\Users\\me\\bg.gif'" -Because 'exactly two backslashes per input one'
                script:ConvertFrom-LuaShortString -Literal $lit | Should -Be $path
            }

            It 'round-trips a value carrying both a backslash and a quote' {
                # Pins the pass ORDER too: the backslash rule has to run first,
                # or the backslash it adds for the quote gets doubled.
                $raw = 'a' + [char]92 + [char]39 + 'b'          # a\'b
                $lit = ConvertTo-WezTermLuaString -Value $raw
                script:ConvertFrom-LuaShortString -Literal $lit | Should -Be $raw
            }

            It 'hands the generated module the path it was given' {
                # The escaper and its only real caller, checked together: the
                # background path is the one value that carries backslashes in
                # practice (style names cannot -- Test-StyleNameIsSingleSegment
                # rejects them -- and colours are hex-validated).
                $path = 'C:\Users\me\AppData\Local\TerminalStyles\cache\eva\background.gif'
                $lua  = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme -BackgroundImage $path
                $line = @($lua -split "`n" | Where-Object { $_ -match 'File = \{ path = ' })
                @($line).Count | Should -Be 1 -Because 'the image layer must be emitted for this to mean anything'
                $lit = ([regex]::Match($line[0], "path = ('.*')")).Groups[1].Value
                script:ConvertFrom-LuaShortString -Literal $lit | Should -Be $path
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
        BeforeAll {
            $script:capScheme = [pscustomobject]@{
                background = '#0a0006'; foreground = '#ffe8e8'; cursorColor = '#ff3d5a'
            }
            # A style that asks for EVERY field the notice can name, so both
            # directions below are actually exercised.
            $script:capTheme = [pscustomobject]@{
                tabTitle    = 'EVA // NERV'
                tabColor    = '#ff3d5a'
                cursorShape = 'filledBox'
                useAcrylic  = $true
                opacity     = 80
                font        = [pscustomobject]@{ face = 'Cascadia Code'; size = 11 }
                padding     = '12'
            }
        }

        It 'claims exactly what Get-WezTermStyleLua writes' {
            $caps = Get-TerminalCapability -Kind 'WezTerm'
            $caps.OscPalette      | Should -BeTrue
            $caps.BackgroundImage | Should -BeTrue -Because 'the animated GIF is the point'
            $caps.Font            | Should -BeTrue
            $caps.Padding         | Should -BeTrue
            $caps.Persist         | Should -BeTrue
            $caps.Opacity         | Should -BeTrue -Because 'window_background_opacity plus the layer alpha'
            $caps.CursorShape     | Should -BeTrue -Because 'default_cursor_style'
            $caps.TabColor        | Should -BeTrue -Because 'colors.tab_bar.active_tab'
        }

        It 'claims <Flag> only if the generated module really carries it' -ForEach @(
            @{ Flag = 'Font';            Option = 'config\.font = ' }
            @{ Flag = 'Padding';         Option = 'config\.window_padding' }
            @{ Flag = 'Opacity';         Option = 'config\.window_background_opacity' }
            @{ Flag = 'CursorShape';     Option = 'config\.default_cursor_style' }
            @{ Flag = 'TabColor';        Option = 'config\.colors\.tab_bar\.active_tab' }
            @{ Flag = 'BackgroundImage'; Option = 'config\.background' }
            @{ Flag = 'TabTitle';        Option = 'tab_title|set_title' }
        ) {
            # Both directions, against the writer's OUTPUT rather than its
            # source text. A flag turned on with no line behind it makes a style
            # report success, paint nothing, and suppress the notice that would
            # have explained why; a flag left off next to a line that DOES run
            # makes the apply print "WezTerm can't show: X" about something it
            # has just done. TabTitle is the second case's control: nothing
            # writes one, and the title still changes because the style's own
            # prompt sets it.
            $lua = Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:capScheme `
                -Theme $script:capTheme -BackgroundImage '/abs/eva/background.gif'
            if ((Get-TerminalCapability -Kind 'WezTerm')[$Flag]) {
                $lua | Should -Match $Option -Because "WezTerm claims $Flag"
            } else {
                $lua | Should -Not -Match $Option -Because "WezTerm does not claim $Flag"
            }
        }
    }
}

Describe 'the background is drawn once, never tiled' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:scheme = [pscustomobject]@{ background = '#101010'; foreground = '#f0f0f0' }
        }

        It 'says NoRepeat on both axes for every stretch mode' {
            # WezTerm TILES a background layer by default. Contain deliberately
            # leaves space -- it fits the image inside the pane without cropping
            # -- so a wide window has bare strips at the sides, and WezTerm fills
            # them with copies. Reported on `tombraider` (uniform -> Contain) as
            # the image duplicating once the terminal got wide enough.
            #
            # Asserted over the whole stretch-mode domain, not just the one that
            # was reported: Cover crops to fill and so hides the symptom today,
            # but nothing stops a style from being re-authored to `uniform`.
            foreach ($mode in 'none', 'fill', 'uniform', 'uniformToFill', $null) {
                $theme = [pscustomobject]@{
                    backgroundImage            = '{{BACKGROUND_IMAGE}}'
                    backgroundImageStretchMode = $mode
                }
                $lua = Get-WezTermStyleLua -StyleName 'probe' -Scheme $script:scheme `
                           -Theme $theme -BackgroundImage '/tmp/bg.gif'
                $lua | Should -Match "repeat_x = 'NoRepeat'" -Because "stretch mode '$mode' must draw one image"
                $lua | Should -Match "repeat_y = 'NoRepeat'" -Because "stretch mode '$mode' must draw one image"
            }
        }

        It 'matches Windows Terminal, which has no tiling mode at all' {
            # The styles are authored against Windows Terminal, and none of its
            # four backgroundImageStretchMode values tile: `none` draws one copy
            # at natural size, `fill` stretches one, `uniform` and `uniformToFill`
            # scale one. Repeating is this writer inventing a look no style asked
            # for, which is why it is unconditional rather than a mapped value.
            # Each maps to a size that draws ONE image -- Contain fits it,
            # Cover crops it, 100% stretches it. None of the three repeats, and
            # WezTerm has no size that implies repeating either: tiling is a
            # separate axis, which is exactly why it had to be turned off
            # explicitly rather than falling out of the size mapping.
            $expected = @{
                'none'          = 'Contain'   # draw at natural size: nearest without cropping or distorting
                'fill'          = '100%'      # stretch to the pane
                'uniform'       = 'Contain'   # scale to fit
                'uniformToFill' = 'Cover'     # scale to fill, cropping
            }
            foreach ($mode in $expected.Keys) {
                Get-WezTermBackgroundSize -Mode $mode | Should -Be $expected[$mode] `
                    -Because "'$mode' draws exactly one image, scaled this way"
            }
        }

        It 'every bundled style that ships a background says it' {
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $checked = 0
            foreach ($d in Get-ChildItem (Join-Path $repoRoot 'styles') -Directory) {
                $tp = Join-Path $d.FullName 'theme.json'
                if (-not (Test-Path -LiteralPath $tp)) { continue }
                $theme = [System.IO.File]::ReadAllText($tp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($theme.PSObject.Properties.Match('backgroundImage').Count -eq 0) { continue }
                $lua = Get-WezTermStyleLua -StyleName $d.Name -Scheme $script:scheme `
                           -Theme $theme -BackgroundImage '/tmp/bg.gif'
                $lua | Should -Match "repeat_x = 'NoRepeat'" -Because "$($d.Name) ships a background"
                $checked++
            }
            $checked | Should -BeGreaterThan 10 -Because 'a loop that never ran would pass silently'
        }
    }
}
