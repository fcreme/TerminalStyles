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

        It 'writes a number Lua can load for an image opacity that overflows' {
            # pwsh 7 parses '-1e400' as -Infinity, which wrote `opacity =
            # -Infinity`: unary minus on a nil global, so the whole module
            # failed to load. Not finite reads as not given.
            foreach ($v in '-1e400', '1e400', 'NaN') {
                $script:theme.backgroundImageOpacity = $v
                $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
                script:Get-LookTopLine $l 'image' | Should -BeLike '*, opacity = 1 },' -Because "'$v' is not a finite number"
            }
        }

        It 'clamps an image opacity to 0..1' {
            $script:theme.backgroundImageOpacity = 1.5
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            script:Get-LookTopLine $l 'image' | Should -BeLike '*, opacity = 1 },'
            $script:theme.backgroundImageOpacity = -0.25
            $l = Get-WezTermStyleLook -StyleName eva -Scheme $script:scheme -Theme $script:theme -BackgroundCandidates @('/c/background.gif')
            script:Get-LookTopLine $l 'image' | Should -BeLike '*, opacity = 0 },'
        }
    }
}

Describe 'Get-WezTermImageOpacity' {
    InModuleScope TerminalStyles {
        It 'passes a finite value in 0..1 through, number or string' {
            Get-WezTermImageOpacity 0.35 | Should -Be 0.35
            Get-WezTermImageOpacity '0.35' | Should -Be 0.35
            Get-WezTermImageOpacity 0 | Should -Be 0
            Get-WezTermImageOpacity 1 | Should -Be 1
        }
        It 'reads nothing, a non-number and a non-finite number as fully opaque' {
            foreach ($v in $null, '', '40%', 'NaN', '-1e400', '1e400', [double]::NegativeInfinity, [double]::NaN) {
                $r = Get-WezTermImageOpacity $v
                $r | Should -Be 1 -Because "'$v' is not a finite number"
                [double]::IsInfinity($r) -or [double]::IsNaN($r) | Should -BeFalse
            }
        }
        It 'clamps to 0..1' {
            Get-WezTermImageOpacity 1.5 | Should -Be 1
            Get-WezTermImageOpacity '-0.25' | Should -Be 0
        }
    }
}

Describe 'the per-tab module''s default line' {
    InModuleScope TerminalStyles {
        It 'is the one form the generator writes and the reader reads' {
            $none = Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null
            $some = Get-WezTermTabModuleLua -Styles @() -DefaultStyle "o'brien"
            @($none -split '\r?\n') -ccontains (Get-WezTermTabDefaultLine -DefaultStyle $null) | Should -BeTrue
            @($some -split '\r?\n') -ccontains (Get-WezTermTabDefaultLine -DefaultStyle "o'brien") | Should -BeTrue
            Test-WezTermTabModuleDefault -Text $none | Should -BeFalse
            Test-WezTermTabModuleDefault -Text $some | Should -BeTrue
        }
        It 'reads CR LF and LF alike' {
            $none = (Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null) -replace '\r?\n', "`r`n"
            Test-WezTermTabModuleDefault -Text $none | Should -BeFalse
            $none = (Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null) -replace '\r?\n', "`n"
            Test-WezTermTabModuleDefault -Text $none | Should -BeFalse
        }
        It 'is not fooled by a style named nil' {
            # `local DEFAULT = 'nil'` names a style; only the bare nil is none.
            Test-WezTermTabModuleDefault -Text (Get-WezTermTabModuleLua -Styles @() -DefaultStyle 'nil') | Should -BeTrue
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
            $m | Should -Match ([regex]::Escape("local schemes = { [BUILTIN.color_scheme] = wezterm.color.get_default_colors() }"))
            foreach ($line in @(
                "  color_scheme = PREFIX .. UNSTYLED,",
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
            # The scheme the user's own color_scheme names is part of it: an
            # unstyled window carries a copy of that scheme (see the test of
            # self-contained looks below), so an edit to it must reach them.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $lines -ccontains "local stamp = want .. '@' .. GENERATION .. '@' .. USERPRINT" | Should -BeTrue
            $capture = [array]::IndexOf($lines, 'for _, k in ipairs(KEYS) do user[k] = copy(config[k]) end')
            $scheme = [array]::IndexOf($lines, 'user_scheme = copy(config.color_schemes[user.color_scheme])')
            $print = [array]::IndexOf($lines, 'USERPRINT = fingerprint({ user, user_scheme })')
            $base = [array]::IndexOf($lines, 'local base = look_of(DEFAULT or UNSTYLED)')
            $capture | Should -BeGreaterThan -1
            $scheme | Should -BeGreaterThan $capture
            $print | Should -BeGreaterThan $scheme
            $base | Should -BeGreaterThan $print
        }

        # R21. Each of the four below was checked in a sandbox WezTerm (the
        # final-fix-wave report); the text pins what was measured.

        It 'gives every window a complete look, the default''s included' {
            # A window showing the default used to hold none of a look's keys,
            # so a rewrite that moved the default painted the NEW default in it
            # until its sync put the old look back.
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $lines = @($m -split '\r?\n' | ForEach-Object { $_.Trim() })
            $m | Should -Not -Match 'want ~= \(DEFAULT or UNSTYLED\)'
            $strip = [array]::IndexOf($lines, 'for _, k in ipairs(KEYS) do overrides[k] = nil end')
            $look = [array]::IndexOf($lines, 'local look, scheme = look_of(want)')
            $merge = [array]::IndexOf($lines, 'for k, v in pairs(look) do overrides[k] = v end')
            $set = [array]::IndexOf($lines, 'window:set_config_overrides(overrides)')
            $strip | Should -BeGreaterThan -1
            $look | Should -BeGreaterThan $strip
            $merge | Should -Be ($look + 1) -Because 'the merge is unconditional'
            $set | Should -BeGreaterThan $merge
        }

        It 'makes each look carry the scheme it names, keeping the window''s other schemes' {
            # Measured: an override's color_schemes REPLACES the base config's
            # whole table, so a name only the base registers is "not found"
            # there -- and the scheme a window names has to travel with it, or
            # the window loses its palette when this file is deleted.
            $m = Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty
            $lines = @($m -split '\r?\n' | ForEach-Object { $_.Trim() })
            $lines -ccontains "local PREFIX = 'TerminalStyles '" | Should -BeTrue
            $keep = [array]::IndexOf($lines, 'if type(k) ~= ''string'' or k:sub(1, #PREFIX) ~= PREFIX then schemes[k] = v end')
            $own = [array]::IndexOf($lines, 'if scheme then schemes[look.color_scheme] = scheme end')
            $put = [array]::IndexOf($lines, 'overrides.color_schemes = schemes')
            $set = [array]::IndexOf($lines, 'window:set_config_overrides(overrides)')
            $keep | Should -BeGreaterThan -1
            $own | Should -BeGreaterThan $keep
            $put | Should -BeGreaterThan $own
            $set | Should -BeGreaterThan $put
        }

        It 'gives an unstyled look the scheme it draws: WezTerm''s default, or the user''s own registered one' {
            # A builtin name the user picked needs nothing carried: measured,
            # it still resolves under an override's color_schemes.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $start = [array]::IndexOf($lines, 'local function look_of(name)')
            $fromUser = [array]::IndexOf($lines, 'local scheme = USER_SCHEME')
            $none = [array]::IndexOf($lines, 'if USER.color_scheme == nil then scheme = wezterm.color.get_default_colors() end')
            $styled = [array]::IndexOf($lines, 'scheme = look.scheme')
            $start | Should -BeGreaterThan -1
            $fromUser | Should -BeGreaterThan $start
            $none | Should -Be ($fromUser + 1)
            $styled | Should -BeGreaterThan $none
            $lines -ccontains 'return t, scheme' | Should -BeTrue
        }

        It 'lets the style''s palette win over the user''s colors in a styled look' {
            # Measured: colors lays over color_scheme key by key, so a user's
            # colors.background drew over every style's background. Every key
            # the style's scheme sets is dropped from the user's copy; the
            # rest (tab bar parts, say) stays.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $copy = [array]::IndexOf($lines, 't.colors = t.colors or {}')
            $named = [array]::IndexOf($lines, 't.color_scheme = PREFIX .. name')
            $drop = [array]::IndexOf($lines, 'for k in pairs(look.scheme) do t.colors[k] = nil end')
            $tab = [array]::IndexOf($lines, 'if look.tab_bg then')
            $copy | Should -BeGreaterThan -1
            $named | Should -BeGreaterThan $copy
            $drop | Should -BeGreaterThan $named
            $tab | Should -BeGreaterThan $drop
        }

        It 'works everything out before it writes to config, inside a pcall that logs once' {
            # M6. The wiring line's pcall guards only the require; an error in
            # apply_to_config is a config error, which costs the user their
            # whole wezterm.lua.
            $lines = @((Get-WezTermTabModuleLua -Styles $script:styles -DefaultStyle kitty) -split '\r?\n' | ForEach-Object { $_.Trim() })
            $fn = [array]::IndexOf($lines, 'function M.apply_to_config(config)')
            $fn | Should -BeGreaterThan -1
            $lines[$fn + 1] | Should -BeExactly 'local ok, err = pcall(function()'
            $base = [array]::IndexOf($lines, 'local base = look_of(DEFAULT or UNSTYLED)')
            $firstWrite = -1
            for ($i = $fn + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -cmatch '^config(\.|\[)') { $firstWrite = $i; break }
            }
            $firstWrite | Should -BeGreaterThan $base -Because 'nothing is written to config until every value is worked out'
            $logged = @($lines | Where-Object { $_ -clike 'if not ok then wezterm.log_error(*' })
            $logged.Count | Should -Be 1
            [array]::IndexOf($lines, 'return config') | Should -BeGreaterThan ([array]::IndexOf($lines, $logged[0]))
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

Describe 'a style name typed in another case, per tab' {
    # Get-AvailableStyles matches a name case-insensitively and, on a
    # case-insensitive file system, Get-StyleDir resolves 'EVA' to the folder
    # 'eva'. But the module's LOOKS keys are folder names and Lua compares
    # strings exactly, so a DEFAULT or a tag of 'EVA' named no look: the tab
    # fell to its pin, new tabs opened unstyled, and the apply printed success.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:origRoot = $script:TStylesDataRoot
            $script:origCurrent = $script:TStylesCurrent
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'
            $script:evaDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'eva'
            [void][System.IO.Directory]::CreateDirectory($script:evaDir)
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                (@{ name = 'eva'; background = '#0a0006'; foreground = '#ffe8e8' } | ConvertTo-Json),
                [System.Text.UTF8Encoding]::new($false))
            $script:modPath = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))) 'terminalstyles.lua'
            # The module path is mocked, never derived: unmocked it is the
            # operator's own ~/.config/wezterm/terminalstyles.lua.
            Mock Get-WezTermModulePath { $script:modPath }
            Mock Get-AvailableStyles { @(Get-Item -LiteralPath $script:evaDir) }
            $script:tagged = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WezTermTabTag { $script:tagged.Add($Value); 'painted' }
            Mock Write-Host { }
        }
        AfterEach {
            $script:TStylesDataRoot = $script:origRoot
            $script:TStylesCurrent = $script:origCurrent
        }

        It 'tstyles EVA writes the default eva and tags this tab eva' {
            Mock Get-TerminalKind { 'WezTerm' }
            Mock Test-WezTermPerTab { $true }
            Mock Test-WezTermStyleWired { $true }
            Mock Write-HostOscPacket { $true }
            Mock Show-UpdateNoticeIfAvailable { }
            Mock Publish-StyleVSCodeConfig { $null }
            Mock Get-StyleBundledBackground { $null }

            Invoke-TerminalStyle -Arg 'EVA'

            $text = [System.IO.File]::ReadAllText($script:modPath, [System.Text.UTF8Encoding]::new($false))
            @($text -split '\r?\n') -ccontains "local DEFAULT = 'eva'" | Should -BeTrue -Because 'LOOKS is keyed by the folder name'
            @($script:tagged) | Should -HaveCount 1
            $script:tagged[0] | Should -BeExactly 'eva'
            (Get-CurrentStyleRecord).name | Should -BeExactly 'eva'
        }

        It 'the dispatcher hands the apply the listed name' {
            Mock Apply-StyleDirect { }
            Invoke-TerminalStyle -Arg 'EVA'
            Should -Invoke Apply-StyleDirect -Times 1 -Exactly -ParameterFilter { $StyleName -ceq 'eva' }
        }

        It 'Publish-StyleWezTermConfig puts the listed name in the module and the tag, from any door' {
            # The tuner's save and delete's re-apply reach the publisher with a
            # name as the user typed it, not through the dispatcher.
            Mock Test-WezTermPerTab { $true }
            Mock Test-WezTermStyleWired { $true }
            Mock Get-StyleBundledBackground { $null }
            $scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }

            Publish-StyleWezTermConfig -StyleName 'EVA' -StyleDir $script:evaDir -Scheme $scheme -Kind 'WezTerm' | Out-Null

            $text = [System.IO.File]::ReadAllText($script:modPath, [System.Text.UTF8Encoding]::new($false))
            @($text -split '\r?\n') -ccontains "local DEFAULT = 'eva'" | Should -BeTrue
            $script:tagged[0] | Should -BeExactly 'eva'
        }

        It 'Write-WezTermTabModule writes a default in another case as the listed name' {
            # The picker's open writes the recorded name, and delete writes the
            # name it was asked to delete: both through here.
            Write-WezTermTabModule -DefaultStyle 'EVA' | Should -Be 'written'
            $text = [System.IO.File]::ReadAllText($script:modPath, [System.Text.UTF8Encoding]::new($false))
            @($text -split '\r?\n') -ccontains "local DEFAULT = 'eva'" | Should -BeTrue
        }

        It 'Write-WezTermTabModule keeps a default no style is listed under' {
            Write-WezTermTabModule -DefaultStyle 'gone' | Should -Be 'written'
            $text = [System.IO.File]::ReadAllText($script:modPath, [System.Text.UTF8Encoding]::new($false))
            @($text -split '\r?\n') -ccontains "local DEFAULT = 'gone'" | Should -BeTrue
        }
    }
}

Describe 'Get-ListedStyleName' {
    InModuleScope TerminalStyles {
        It 'answers with the listed spelling, an exact match first, and $null for none' {
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'EVA' }, [pscustomobject]@{ Name = 'eva' }, [pscustomobject]@{ Name = 'kitty' }) }
            Get-ListedStyleName -Name 'eva' | Should -BeExactly 'eva'
            Get-ListedStyleName -Name 'EVA' | Should -BeExactly 'EVA'
            Get-ListedStyleName -Name 'KITTY' | Should -BeExactly 'kitty'
            Get-ListedStyleName -Name 'nope' | Should -BeNullOrEmpty
            Get-ListedStyleName -Name '' | Should -BeNullOrEmpty
        }
        It 'reads a list it is given instead of listing again' {
            Mock Get-AvailableStyles { throw 'must not list' }
            Get-ListedStyleName -Name 'ALPHA' -Listed @('beta', 'alpha') | Should -BeExactly 'alpha'
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

Describe 'Invoke-StartupPaletteReplay' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($dir)
            [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'),
                (@{ name = 'alpha'; background = '#101010'; foreground = '#eeeeee' } | ConvertTo-Json),
                [System.Text.UTF8Encoding]::new($false))
            $script:styleDir = $dir
            Mock Get-CurrentStyleRecord { [pscustomobject]@{ name = 'alpha' } }
            Mock Get-StyleDir { $script:styleDir }
            Mock Invoke-TerminalStyleOscApply { $true }
        }
        It 'startup does not repaint in per-tab mode' {
            Mock Get-TerminalKind { 'WezTerm' }
            Mock Test-WezTermPerTab { $true }
            Invoke-StartupPaletteReplay
            Should -Invoke Invoke-TerminalStyleOscApply -Times 0 -Exactly
        }
        It 'startup still repaints in WezTerm outside per-tab mode' {
            Mock Get-TerminalKind { 'WezTerm' }
            Mock Test-WezTermPerTab { $false }
            Invoke-StartupPaletteReplay
            Should -Invoke Invoke-TerminalStyleOscApply -Times 1 -Exactly
        }
        It 'startup does not repaint in Windows Terminal' {
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Test-WezTermPerTab { $false }
            Invoke-StartupPaletteReplay
            Should -Invoke Invoke-TerminalStyleOscApply -Times 0 -Exactly
        }
    }
}

Describe 'Get-CurrentStyleName in per-tab mode' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # No current-style.ps1, so the byte-compare finds nothing and the answer
            # is decided by the per-tab record or the global one alone.
            $script:origCurrent = $script:TStylesCurrent
            $script:TStylesCurrent = Join-Path $TestDrive 'no-current-style.ps1'
            Mock Get-CurrentStyleRecord { [pscustomobject]@{ name = 'kitty' } }
            Mock Get-StyleDir { "$TestDrive/$StyleName" }
            Mock Test-WezTermPerTab { $true }
            Mock Get-WezTermTabRecord { 'neon-rain' }
        }
        AfterEach { $script:TStylesCurrent = $script:origCurrent }

        It "names this tab's style over the last applied one" {
            Get-CurrentStyleName | Should -BeExactly 'neon-rain'
        }
        It 'is $null for a tab reset to unstyled' {
            Mock Get-WezTermTabRecord { '' }
            Get-CurrentStyleName | Should -BeNullOrEmpty
        }
        It 'falls back to the last applied style when this tab has no record' {
            Mock Get-WezTermTabRecord { $null }
            Get-CurrentStyleName | Should -BeExactly 'kitty'
        }
        It "falls back when this tab's style was deleted" {
            Mock Get-WezTermTabRecord { 'gone' }
            Mock Get-StyleDir { if ($StyleName -eq 'gone') { $null } else { "$TestDrive/$StyleName" } }
            Get-CurrentStyleName | Should -BeExactly 'kitty'
        }
        It 'ignores the record off per-tab mode' {
            Mock Test-WezTermPerTab { $false }
            Get-CurrentStyleName | Should -BeExactly 'kitty'
            Should -Invoke Get-WezTermTabRecord -Times 0 -Exactly
        }
    }
}
