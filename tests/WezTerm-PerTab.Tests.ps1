# Pester 5 tests: WezTerm per-tab mode, the tag packet, the per-tab record and
# the per-tab module generator.
#
# Nothing here talks to a running WezTerm. The packet is pinned byte for byte, and
# the record is exercised against a data root under $TestDrive with this process's
# WEZTERM_UNIX_SOCKET / WEZTERM_PANE set per test and restored afterwards. The
# generated Lua is pinned as text, the way tests/WezTerm-Writer.Tests.ps1 pins the
# single-style module; it was loaded in a real WezTerm by hand (see the PR).
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

Describe 'Test-WezTermPerTab' {
    InModuleScope TerminalStyles {
        It 'is true only for WezTerm, off Windows, wired' {
            Mock Test-WezTermStyleWired { $true }
            Test-WezTermPerTab -Kind WezTerm -Platform MacOS | Should -BeTrue
            Test-WezTermPerTab -Kind WezTerm -Platform Windows | Should -BeFalse
            Test-WezTermPerTab -Kind ITerm2 -Platform MacOS | Should -BeFalse
        }
        It 'is false when the wiring line is absent' {
            Mock Test-WezTermStyleWired { $false }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux | Should -BeFalse
        }
        It 'forwards HomeDir to the wiring check only when bound' {
            Mock Test-WezTermStyleWired { $true }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux -HomeDir '/nowhere' | Should -BeTrue
            Should -Invoke Test-WezTermStyleWired -Times 1 -Exactly -ParameterFilter { $HomeDir -eq '/nowhere' }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux | Should -BeTrue
            Should -Invoke Test-WezTermStyleWired -Times 1 -Exactly -ParameterFilter { $null -eq $HomeDir }
        }
    }
}

Describe 'WezTerm tag constants' {
    InModuleScope TerminalStyles {
        It 'holds the user variable name and the two non-style markers' {
            $script:WezTermTagVar | Should -BeExactly 'TERMINALSTYLES_STYLE'
            $script:WezTermTagUnstyled | Should -BeExactly '/unstyled'
            $script:WezTermTagPreviewPrefix | Should -BeExactly '/preview/'
        }
    }
}

Describe 'Get-WezTermTagPacket' {
    InModuleScope TerminalStyles {
        It 'base64-encodes the UTF-8 value' {
            $p = Get-WezTermTagPacket -Value "o'brién" -InTmux $false
            $p | Should -BeExactly ("$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=" +
                [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("o'brién")) + "$([char]7)")
        }
        It 'wraps for tmux with every ESC doubled' {
            $p = Get-WezTermTagPacket -Value kitty -InTmux $true
            $p.StartsWith("$([char]27)Ptmux;$([char]27)$([char]27)]1337;") | Should -BeTrue
            $p.EndsWith("$([char]27)\") | Should -BeTrue
        }
        It 'encodes an empty value as an empty user var' {
            Get-WezTermTagPacket -Value '' -InTmux $false |
                Should -BeExactly "$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=$([char]7)"
        }
    }
}

Describe 'per-tab record' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:origRoot = $script:TStylesDataRoot
            $script:origSock = $env:WEZTERM_UNIX_SOCKET
            $script:origPane = $env:WEZTERM_PANE
            $script:TStylesDataRoot = $TestDrive
            $script:recFile = Join-Path $TestDrive 'wezterm-tabs.json'
            if (Test-Path -LiteralPath $script:recFile) { Remove-Item -LiteralPath $script:recFile -Force }
            $script:liveSock = Join-Path $TestDrive 'live.sock'
            Set-Content -LiteralPath $script:liveSock -Value 'x'
            $env:WEZTERM_UNIX_SOCKET = $script:liveSock
            $env:WEZTERM_PANE = '3'
        }
        AfterEach {
            $script:TStylesDataRoot = $script:origRoot
            $env:WEZTERM_UNIX_SOCKET = $script:origSock
            $env:WEZTERM_PANE = $script:origPane
        }

        It 'builds the key from socket and pane, and is null when either is empty' {
            Get-WezTermTabKey | Should -BeExactly "$($script:liveSock)|3"
            $env:WEZTERM_PANE = ''
            Get-WezTermTabKey | Should -BeNullOrEmpty
            $env:WEZTERM_PANE = '3'
            $env:WEZTERM_UNIX_SOCKET = ''
            Get-WezTermTabKey | Should -BeNullOrEmpty
        }
        It 'round-trips this tab and keeps unstyled distinct from missing' {
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
            Set-WezTermTabRecord -Value '' | Should -BeExactly 'ok'
            $r = Get-WezTermTabRecord
            $null -eq $r | Should -BeFalse
            $r | Should -BeExactly ''
            $env:WEZTERM_PANE = '4'
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
        }
        It 'returns nokey and writes nothing outside WezTerm' {
            $env:WEZTERM_UNIX_SOCKET = ''
            $env:WEZTERM_PANE = ''
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'nokey'
            [System.IO.File]::Exists($script:recFile) | Should -BeFalse
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
        }
        It 'drops entries whose socket no longer exists' {
            $dead = Join-Path $TestDrive 'dead.sock'
            $fixture = [ordered]@{ "$dead|1" = 'eva'; "$($script:liveSock)|9" = 'kitty' } | ConvertTo-Json
            [System.IO.File]::WriteAllText($script:recFile, $fixture, [System.Text.UTF8Encoding]::new($false))
            Set-WezTermTabRecord -Value 'x' | Should -BeExactly 'ok'
            $text = [System.IO.File]::ReadAllText($script:recFile)
            $text | Should -Not -BeLike '*dead.sock*'
            $env:WEZTERM_PANE = '9'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
            $env:WEZTERM_PANE = '3'
            Get-WezTermTabRecord | Should -BeExactly 'x'
        }
        It 'reads a corrupt file as no record' {
            [System.IO.File]::WriteAllText($script:recFile, 'not json')
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
        }
        It 'writes UTF-8 without a byte-order mark' {
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            $b = [System.IO.File]::ReadAllBytes($script:recFile)
            $b[0] | Should -Be ([byte][char]'{')
        }
    }
}

Describe 'Get-WezTermStyleLook' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # The eva fixtures from tests/WezTerm-Writer.Tests.ps1: the shape
            # fifteen of the sixteen bundled styles have.
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
                colorScheme = 'eva'; tabTitle = 'EVA // NERV'; tabColor = '#ff3d5a'
                cursorShape = 'filledBox'; useAcrylic = $false; opacity = 100
                font = [pscustomobject]@{ face = 'Cascadia Code'; size = 11; weight = 'semi-bold' }
                padding = '12'
                backgroundImageOpacity = 0.4
                backgroundImageStretchMode = 'uniformToFill'
            }
            # The look's own fields, one per line: everything but the scheme
            # body and its arrays, which sit deeper.
            function script:Get-LookTopLine {
                param([string]$Look, [string]$Field)
                @($Look -split '\r?\n' | Where-Object { $_ -match "^    $Field = " })
            }
        }

        It 'carries no layout' {
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            $l | Should -Not -Match 'font'
            $l | Should -Not -Match 'padding'
        }

        It 'lists every candidate in order, quoted' {
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('C:\a\bg.gif','/b/bg.png')
            $l | Should -Match ([regex]::Escape("images = { 'C:\\a\\bg.gif', '/b/bg.png' }"))
        }

        It 'escapes the style name' {
            $l = Get-WezTermStyleLook -StyleName "o'brien" -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @()
            @($l -split '\r?\n')[0].Trim() | Should -BeExactly "['o\'brien'] = {"
        }

        It 'escapes a name holding a quote, a backslash and a non-ASCII letter' {
            $name = "o'br\i" + [char]0x00E9
            $l = Get-WezTermStyleLook -StyleName $name -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @()
            @($l -split '\r?\n')[0].Trim() | Should -BeExactly ("['o\'br\\i" + [char]0x00E9 + "'] = {")
        }

        It 'omits opacity and blur for an opaque style' {
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            @(script:Get-LookTopLine $l 'opacity').Count | Should -Be 0
            $l | Should -Not -Match 'blur'
        }

        It 'carries opacity, and blur only with acrylic' {
            # The companion of the test above, so that one cannot pass on a
            # pattern that never matches anything.
            $script:theme.opacity = 83
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @()
            script:Get-LookTopLine $l 'opacity' | Should -BeExactly '    opacity = 0.83,'
            $l | Should -Not -Match 'blur'
            $script:theme.useAcrylic = $true
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @()
            script:Get-LookTopLine $l 'blur' | Should -BeExactly '    blur = 20,'
        }

        It 'carries the cursor, the tab colours, the base colour and the image placement' {
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            script:Get-LookTopLine $l 'cursor' | Should -BeExactly "    cursor = 'SteadyBlock',"
            script:Get-LookTopLine $l 'tab_bg' | Should -BeExactly "    tab_bg = '#ff3d5a',"
            script:Get-LookTopLine $l 'tab_fg' | Should -BeExactly "    tab_fg = '$(Get-WezTermTabForeground '#ff3d5a')',"
            script:Get-LookTopLine $l 'base' | Should -BeExactly "    base = '#0a0006',"
            script:Get-LookTopLine $l 'image' |
                Should -BeExactly "    image = { width = 'Cover', height = 'Cover', h = 'Center', v = 'Middle', opacity = 0.4 },"
        }

        It 'builds the scheme by the single-style module''s rule' {
            # One rule, shared: the same keys, and ansi/brights whole or not at
            # all. brightCyan is broken so the brights half has to be dropped.
            $script:scheme.brightCyan = 'nope'
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @()
            $look = @($l -split '\r?\n')
            $from = [array]::IndexOf($look, '    scheme = {')
            $to = [array]::IndexOf($look, '    },')
            $from | Should -BeGreaterThan -1
            $to | Should -BeGreaterThan $from
            $mine = @($look[($from + 1)..($to - 1)] | ForEach-Object { $_.Trim() })

            $single = @((Get-WezTermStyleLua -StyleName eva -Scheme $script:scheme) -split '\r?\n')
            $sFrom = [array]::IndexOf($single, "  config.color_schemes['TerminalStyles eva'] = {")
            $sTo = [array]::IndexOf($single, '  }')
            $theirs = @($single[($sFrom + 1)..($sTo - 1)] | ForEach-Object { $_.Trim() })

            ($mine -join "`n") | Should -BeExactly ($theirs -join "`n")
            ($mine -join "`n") | Should -Match 'ansi = \{'
            ($mine -join "`n") | Should -Not -Match 'brights'
        }

        It 'omits what is absent rather than writing nil' {
            $bare = [pscustomobject]@{ background = 'not-a-colour'; foreground = '#ffffff' }
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $bare -Theme $null -BackgroundCandidates @()
            $l | Should -Not -Match '\bnil\b'
            foreach ($f in 'cursor', 'opacity', 'blur', 'tab_bg', 'tab_fg', 'base', 'images', 'image') {
                @(script:Get-LookTopLine $l $f).Count | Should -Be 0 -Because "$f has no value"
            }
            script:Get-LookTopLine $l 'scheme' | Should -BeExactly '    scheme = {'
        }

        It 'draws the image fully opaque when the style names no image opacity' {
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $null -BackgroundCandidates @('/c/background.gif')
            script:Get-LookTopLine $l 'image' |
                Should -BeExactly "    image = { width = 'Cover', height = 'Cover', h = 'Center', v = 'Middle', opacity = 1 },"
        }

        It 'reads an image opacity that is not a number as fully opaque, rather than throwing' {
            # Every installed style is built into one module, so a throw here
            # would cost every other style its look.
            $script:theme.backgroundImageOpacity = '40%'
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            script:Get-LookTopLine $l 'image' | Should -BeLike '*, opacity = 1 },'
        }
    }
}

Describe 'Get-WezTermBackgroundCandidates' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:origRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:stylesDir = Join-Path $script:TStylesDataRoot 'styles'
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            function script:New-FixtureStyle {
                param([string]$Name, [string]$Base)
                $d = Join-Path $script:stylesDir $Name
                [void][System.IO.Directory]::CreateDirectory($d)
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'),
                    (@{ name = $Name; background = '#000000' } | ConvertTo-Json), $utf8)
                if ($Base) {
                    [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'),
                        (@{ base = $Base } | ConvertTo-Json), $utf8)
                }
                $d
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:origRoot }

        It 'returns the cache paths for every extension when nothing is cached' {
            $d = script:New-FixtureStyle -Name 'alpha'
            $r = @(Get-WezTermBackgroundCandidates -StyleDir $d)
            $r.Count | Should -Be @(Get-BackgroundImageExtensions).Count
            $r[0] | Should -BeLike '*background.gif'
            $cache = Get-StyleCacheDir -StyleName 'alpha'
            ($r -join '|') | Should -BeExactly ((@(Get-BackgroundImageExtensions) |
                ForEach-Object { Join-Path $cache "background.$_" }) -join '|')
            @($r | Where-Object { [System.IO.File]::Exists($_) }).Count | Should -Be 0
        }

        It 'lists every cache path even when one of them is there' {
            # The Lua picks the first that exists when it builds a look, so a
            # download that lands later is found without a rewrite.
            $d = script:New-FixtureStyle -Name 'alpha'
            $cache = Get-StyleCacheDir -StyleName 'alpha'
            [void][System.IO.Directory]::CreateDirectory($cache)
            [System.IO.File]::WriteAllText((Join-Path $cache 'background.png'), 'x')
            @(Get-WezTermBackgroundCandidates -StyleDir $d).Count | Should -Be @(Get-BackgroundImageExtensions).Count
        }

        It 'returns only the bundled file when the style ships one' {
            $d = script:New-FixtureStyle -Name 'alpha'
            $own = Join-Path $d 'background.png'
            [System.IO.File]::WriteAllText($own, 'x')
            $r = @(Get-WezTermBackgroundCandidates -StyleDir $d)
            $r.Count | Should -Be 1
            $r[0] | Should -BeExactly $own
        }

        It 'inherits a tuned style''s base: its file, else its cache' {
            $parent = script:New-FixtureStyle -Name 'parent'
            $child = script:New-FixtureStyle -Name 'child' -Base 'parent'
            $r = @(Get-WezTermBackgroundCandidates -StyleDir $child)
            $r[0] | Should -BeExactly (Join-Path (Get-StyleCacheDir -StyleName 'parent') 'background.gif')

            $file = Join-Path $parent 'background.jpg'
            [System.IO.File]::WriteAllText($file, 'x')
            $r = @(Get-WezTermBackgroundCandidates -StyleDir $child)
            $r.Count | Should -Be 1
            $r[0] | Should -BeExactly $file
        }
    }
}

Describe 'Get-WezTermTabModuleLua' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            $script:theme = [pscustomobject]@{ cursorShape = 'bar'; tabColor = '#ff3d5a' }
            $script:styles = @(
                @{ Name = 'eva'; Scheme = $script:scheme; Theme = $script:theme; BackgroundCandidates = @('/c/eva/background.gif') },
                @{ Name = 'kitty'; Scheme = $script:scheme; Theme = $null; BackgroundCandidates = @('/c/kitty/background.gif') }
            )
            function script:Get-Generation {
                param([string]$Module)
                [regex]::Match($Module, "local GENERATION = '([^']*)'").Groups[1].Value
            }
            function script:ConvertFrom-LuaShortString {
                # Lua's short-string rule by hand: `\\` is one backslash, `\'`
                # a quote. No Lua runtime exists on the CI machines.
                param([string]$Literal)
                $body = $Literal.Substring(1, $Literal.Length - 2)
                $out = [System.Text.StringBuilder]::new()
                for ($i = 0; $i -lt $body.Length; $i++) {
                    if ($body[$i] -ne '\') { [void]$out.Append($body[$i]); continue }
                    $i++
                    [void]$out.Append($body[$i])
                }
                $out.ToString()
            }
        }

        It 'names the default, or nil' {
            Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty | Should -Match ([regex]::Escape("local DEFAULT = 'kitty'"))
            Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle $null | Should -Match ([regex]::Escape('local DEFAULT = nil'))
        }

        It 'interpolates the reserved tag values from the PowerShell constants' {
            $m = Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null
            $m | Should -Match ([regex]::Escape("'$($script:WezTermTagVar)', '$($script:WezTermTagUnstyled)', '$($script:WezTermTagPreviewPrefix)'"))
        }

        It 'carries every style''s look' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            foreach ($s in $script:styles) {
                $look = Get-WezTermStyleLook -StyleName $s.Name -Scheme $s.Scheme -Theme $s.Theme -BackgroundCandidates $s.BackgroundCandidates
                $m.Contains($look) | Should -BeTrue -Because "$($s.Name)'s look belongs in LOOKS"
            }
        }

        It 'has a stable generation for the same input and a new one when the default changes' {
            $a = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $b = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $c = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle eva
            $d = Get-WezTermTabModuleLua -Styles @($script:styles[0]) -DefaultStyle kitty
            $g = script:Get-Generation $a
            $g | Should -Match '^[0-9a-f]{16}$'
            $b | Should -BeExactly $a
            script:Get-Generation $c | Should -Not -Be $g
            script:Get-Generation $d | Should -Not -Be $g
        }

        It 'stamps the first 16 hex digits of the SHA-256 of its own text with the stamp blank' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $g = script:Get-Generation $m
            $blank = $m.Replace("local GENERATION = '$g'", "local GENERATION = ''")
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hex = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($blank)) | ForEach-Object { $_.ToString('x2') })
            $g | Should -BeExactly $hex.Substring(0, 16)
        }

        It 'keeps the wiring entry point' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $m | Should -Match 'function M\.apply_to_config\(config\)'
            $m.TrimEnd() | Should -Match 'return M$'
            $m | Should -Match "local wezterm = require 'wezterm'"
        }

        It 'never touches the status bar' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $m | Should -Not -Match 'set_right_status|set_left_status|return false'
        }

        It 'syncs from tab switches, tag changes and reloads' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $m | Should -Match ([regex]::Escape("wezterm.on('update-status',"))
            $m | Should -Match ([regex]::Escape("wezterm.on('user-var-changed',"))
            $m | Should -Match ([regex]::Escape("wezterm.on('window-config-reloaded',"))
        }

        It 'fills unset keys with the values measured in WezTerm' {
            # Measured 2026-11-23 against wezterm 20260917-114457-b09b56c2:
            # effective_config() of a config that sets none of these keys.
            $m = Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null
            $m | Should -Match ([regex]::Escape("color_schemes['TerminalStyles ' .. UNSTYLED] = wezterm.color.get_default_colors()"))
            foreach ($line in @(
                "  color_scheme = 'TerminalStyles ' .. UNSTYLED,",
                '  background = {},',
                '  window_background_opacity = 1.0,',
                '  macos_window_background_blur = 0,',
                "  default_cursor_style = 'SteadyBlock',")) {
                @($m -split '\r?\n') -ccontains $line | Should -BeTrue -Because "BUILTIN carries $line"
            }
        }

        # The four below pin generated statements, because no Lua runs on the
        # CI machines. Each one's behaviour was checked in a sandbox WezTerm
        # (task 3 report, fix round 1); each fails on the module before it.

        It 'pins a new pane to what its tab shows, not to the default of the moment' {
            # A split of an untagged tab, made after the default changed,
            # used to be pinned to the new default, so the tab's two panes
            # showed two styles and every focus change between them was a
            # set_config_overrides.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $lines -ccontains "if their_pin == nil then their_pin = wezterm.GLOBAL['ts_pin_' .. other:pane_id()] end" | Should -BeTrue
            $lines -ccontains 'pin = their_pin or DEFAULT or UNSTYLED' | Should -BeTrue
            # ...and the pin follows a tagged pane, so it outlives that pane.
            $lines -ccontains 'if wezterm.GLOBAL[key] ~= theirs then wezterm.GLOBAL[key] = theirs end' | Should -BeTrue
        }

        It 'stamps a sync with the user''s own values, taken before the default is applied' {
            # Without it an edit to wezterm.lua never reached a window that
            # holds an override: the stamp still matched after the reload.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $lines -ccontains "local stamp = want .. '@' .. GENERATION .. '@' .. USERPRINT" | Should -BeTrue
            $capture = [array]::IndexOf($lines, 'for _, k in ipairs(KEYS) do USER[k] = copy(config[k]) end')
            $print = [array]::IndexOf($lines, 'USERPRINT = fingerprint(USER)')
            $base = [array]::IndexOf($lines, 'for k, v in pairs(look_of(DEFAULT or UNSTYLED)) do config[k] = v end')
            $capture | Should -BeGreaterThan -1
            $print | Should -BeGreaterThan $capture
            $base | Should -BeGreaterThan $print
        }

        It 'keeps the window''s other overrides, and reads them only once a sync is needed' {
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $m | Should -Not -Match 'set_config_overrides\(\{\}\)'
            $m | Should -Not -Match 'set_config_overrides\(look_of'
            $lines = @($m -split '\r?\n' | ForEach-Object { $_.Trim() })
            $compare = [array]::IndexOf($lines, 'if wezterm.GLOBAL[key] == stamp then return end')
            $read = [array]::IndexOf($lines, 'local overrides = window:get_config_overrides() or {}')
            $strip = [array]::IndexOf($lines, 'for _, k in ipairs(KEYS) do overrides[k] = nil end')
            $set = [array]::IndexOf($lines, 'window:set_config_overrides(overrides)')
            $compare | Should -BeGreaterThan -1
            $read | Should -BeGreaterThan $compare
            $strip | Should -BeGreaterThan $read
            $set | Should -BeGreaterThan $strip
        }

        It 'gives the base colour layer the window opacity the look carries' {
            # With a layer list WezTerm takes the layer's alpha and ignores
            # window_background_opacity, so a style that sets no opacity
            # silently dropped the user's own.
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $m | Should -Match ([regex]::Escape('opacity = look.opacity or t.window_background_opacity }'))
        }

        It 'marks itself as the per-tab module on the line after the header' {
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n')
            $lines[0] | Should -BeLike '-- Generated by TerminalStyles *'
            $lines[2] | Should -BeExactly "--   $(Get-WezTermWiringLine)"
            $lines[3] | Should -BeExactly '-- TerminalStyles per-tab module'
        }

        It 'round-trips a style name holding a quote, a backslash and a non-ASCII letter' {
            $name = "o'br\i" + [char]0x00E9
            $m = Get-WezTermTabModuleLua -Styles @(@{ Name = $name; Scheme = $script:scheme; Theme = $null; BackgroundCandidates = @() }) -DefaultStyle $name
            $keyLine = @($m -split '\r?\n' | Where-Object { $_ -match "^  \['" })
            $keyLine.Count | Should -Be 1
            script:ConvertFrom-LuaShortString ([regex]::Match($keyLine[0], "^  \[('.*')\] = \{$").Groups[1].Value) | Should -BeExactly $name
            $defLine = @($m -split '\r?\n' | Where-Object { $_ -match '^local DEFAULT = ' })
            script:ConvertFrom-LuaShortString ([regex]::Match($defLine[0], "^local DEFAULT = ('.*')$").Groups[1].Value) | Should -BeExactly $name
            ($m.ToCharArray() | Where-Object { $_ -eq '{' }).Count |
                Should -Be ($m.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            ($m.ToCharArray() | Where-Object { $_ -eq '(' }).Count |
                Should -Be ($m.ToCharArray() | Where-Object { $_ -eq ')' }).Count
        }
    }
}

Describe 'Write-WezTermTabModule' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:origRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:marker = Join-Path $script:TStylesDataRoot 'wezterm-pertab'
            $fixtures = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            $script:alpha = Join-Path $fixtures 'alpha'
            $script:beta = Join-Path $fixtures 'beta'
            foreach ($d in $script:alpha, $script:beta) { [void][System.IO.Directory]::CreateDirectory($d) }
            [System.IO.File]::WriteAllText((Join-Path $script:alpha 'scheme.json'),
                (@{ name = 'alpha'; background = '#101010'; foreground = '#eeeeee' } | ConvertTo-Json), $utf8)
            [System.IO.File]::WriteAllText((Join-Path $script:beta 'scheme.json'),
                (@{ name = 'beta'; background = '#202020'; foreground = '#dddddd' } | ConvertTo-Json), $utf8)
            [System.IO.File]::WriteAllText((Join-Path $script:beta 'theme.json'),
                (@{ cursorShape = 'bar' } | ConvertTo-Json), $utf8)
            Mock Get-AvailableStyles { @(Get-Item -LiteralPath $script:alpha, $script:beta) }
        }
        AfterEach { $script:TStylesDataRoot = $script:origRoot }

        It 'writes, then reports unchanged, and leaves the per-tab marker' {
            Write-WezTermTabModule -DefaultStyle alpha -HomeDir $script:h | Should -BeExactly 'written'
            $path = Get-WezTermModulePath -HomeDir $script:h
            $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
            $text | Should -Match ([regex]::Escape("local DEFAULT = 'alpha'"))
            $text | Should -Match ([regex]::Escape("['alpha'] = {"))
            $text | Should -Match ([regex]::Escape("['beta'] = {"))
            $text | Should -Match ([regex]::Escape("cursor = 'SteadyBar'"))   # beta's theme.json was read
            $alphaCache = Join-Path (Get-StyleCacheDir -StyleName 'alpha') 'background.gif'
            $text | Should -Match ([regex]::Escape("images = { $(ConvertTo-WezTermLuaString $alphaCache),"))
            [System.IO.File]::Exists($script:marker) | Should -BeTrue
            [System.IO.File]::ReadAllBytes($script:marker).Length | Should -Be 0

            [System.IO.File]::Delete($script:marker)
            Write-WezTermTabModule -DefaultStyle alpha -HomeDir $script:h | Should -BeExactly 'unchanged'
            [System.IO.File]::Exists($script:marker) | Should -BeTrue
            Should -Invoke Get-AvailableStyles -Times 2 -Exactly
        }

        It 'writes no default when given none' {
            Write-WezTermTabModule -DefaultStyle $null -HomeDir $script:h | Should -BeExactly 'written'
            [System.IO.File]::ReadAllText((Get-WezTermModulePath -HomeDir $script:h)) |
                Should -Match ([regex]::Escape('local DEFAULT = nil'))
        }

        It 'skips a style whose scheme.json is unreadable' {
            [System.IO.File]::WriteAllText((Join-Path $script:beta 'scheme.json'), '{ not json')
            Write-WezTermTabModule -DefaultStyle alpha -HomeDir $script:h | Should -BeExactly 'written'
            $text = [System.IO.File]::ReadAllText((Get-WezTermModulePath -HomeDir $script:h))
            $text | Should -Match ([regex]::Escape("['alpha'] = {"))
            $text | Should -Not -Match ([regex]::Escape("['beta']"))
        }

        It 'skips a style whose scheme.json is missing' {
            [System.IO.File]::Delete((Join-Path $script:beta 'scheme.json'))
            Write-WezTermTabModule -DefaultStyle alpha -HomeDir $script:h | Should -BeExactly 'written'
            $text = [System.IO.File]::ReadAllText((Get-WezTermModulePath -HomeDir $script:h))
            $text | Should -Match ([regex]::Escape("['alpha'] = {"))
            $text | Should -Not -Match ([regex]::Escape("['beta']"))
        }

        It 'says failed, and leaves no marker, when the module cannot be written' {
            # A folder at the module path: reading and writing it both throw,
            # on every leg, with no chmod (see Write-WezTermStyleModule's test).
            New-Item -ItemType Directory -Path (Get-WezTermModulePath -HomeDir $script:h) -Force | Out-Null
            Write-WezTermTabModule -DefaultStyle alpha -HomeDir $script:h | Should -BeExactly 'failed'
            [System.IO.File]::Exists($script:marker) | Should -BeFalse
        }
    }
}

Describe 'Test-WezTermTabModule' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:dir)
            $script:path = Join-Path $script:dir 'terminalstyles.lua'
            $script:scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
        }

        It 'is true for a per-tab module' {
            [System.IO.File]::WriteAllText($script:path,
                (Get-WezTermTabModuleLua -Styles @(@{ Name = 'eva'; Scheme = $script:scheme; Theme = $null; BackgroundCandidates = @() }) -DefaultStyle eva))
            Test-WezTermTabModule -Path $script:path | Should -BeTrue
        }

        It 'is false for the single-style module and the module a reset leaves' {
            [System.IO.File]::WriteAllText($script:path, (Get-WezTermStyleLua -StyleName 'eva' -Scheme $script:scheme))
            Test-WezTermTabModule -Path $script:path | Should -BeFalse
            [System.IO.File]::WriteAllText($script:path, (Get-WezTermUnstyledLua))
            Test-WezTermTabModule -Path $script:path | Should -BeFalse
        }

        It 'is false when there is no file, or it cannot be read' {
            Test-WezTermTabModule -Path $script:path | Should -BeFalse
            [void][System.IO.Directory]::CreateDirectory($script:path)
            Test-WezTermTabModule -Path $script:path | Should -BeFalse
        }
    }
}
