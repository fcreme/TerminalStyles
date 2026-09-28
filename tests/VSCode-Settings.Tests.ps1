# The VS Code settings writer, which is a prototype and is tested as if it
# were not -- because the thing it edits is a file the user owns and has
# probably hand-maintained for years.
#
# The load-bearing tests here are the ones about what it does NOT touch. A
# merge that gets the colours right and eats somebody's editor.background, or
# a reset that removes a value the user changed by hand afterwards, is worse
# than no feature. Both directions are driven off one plan on purpose, so the
# round trip is a property this can actually assert rather than two lists that
# have to be kept in step.
#
# Nothing here writes a file, and no test reads a real VS Code install.
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

Describe 'Get-VSCodeSettingsPath' {
    InModuleScope TerminalStyles {

        # Exact strings, not patterns. The answer depends on -Platform and on
        # nothing about the machine asking, so there is one right answer per
        # case and it is the same on all four CI legs. The first version of
        # these used regexes with a literal '/' and passed here while failing
        # on both Windows legs, because the path was being built with the
        # HOST's separator -- so the pattern was hiding the bug it should have
        # caught.
        It 'puts settings under Application Support on macOS' {
            Get-VSCodeSettingsPath -Platform 'MacOS' -HomeDir '/Users/x' |
                Should -Be '/Users/x/Library/Application Support/Code/User/settings.json'
        }

        It 'uses roaming APPDATA on Windows, not the local one' {
            # settings.json is the file that follows a roaming profile. Putting
            # it under LOCALAPPDATA would work on one machine and lose the
            # style on every other one the user signs in to.
            Get-VSCodeSettingsPath -Platform 'Windows' -AppData 'C:\Users\x\AppData\Roaming' |
                Should -Be 'C:\Users\x\AppData\Roaming\Code\User\settings.json'
        }

        It 'falls back to a roaming path when APPDATA is not set' {
            Get-VSCodeSettingsPath -Platform 'Windows' -AppData '' -HomeDir 'C:\Users\x' |
                Should -Be 'C:\Users\x\AppData\Roaming\Code\User\settings.json'
        }

        It 'uses XDG config on Linux' {
            Get-VSCodeSettingsPath -Platform 'Linux' -HomeDir '/home/x' |
                Should -Be '/home/x/.config/Code/User/settings.json'
        }

        It 'lets a bound -HomeDir beat the machine''s own XDG_CONFIG_HOME' {
            # The ubuntu runner sets XDG_CONFIG_HOME, so this case passed on
            # three legs and failed on the fourth: the caller said where home
            # was and the ambient variable answered instead. Same rule the rest
            # of the repo applies to $env:ZDOTDIR.
            $saved = $env:XDG_CONFIG_HOME
            try {
                $env:XDG_CONFIG_HOME = '/somewhere/else'
                Get-VSCodeSettingsPath -Platform 'Linux' -HomeDir '/home/x' |
                    Should -Be '/home/x/.config/Code/User/settings.json'
            } finally { $env:XDG_CONFIG_HOME = $saved }
        }

        It 'still honours an XDG path the caller asked for by name' {
            # Binding both is a caller who means it.
            Get-VSCodeSettingsPath -Platform 'Linux' -HomeDir '/home/x' -XdgConfigHome '/home/x/cfg' |
                Should -Be '/home/x/cfg/Code/User/settings.json'
        }

        It 'gives the same answer whatever machine is asking' {
            # The property CI found missing. A Windows path is backslashed and
            # a macOS path is not, on every host -- otherwise a function whose
            # platform is a PARAMETER quietly answers about the host instead.
            $win = Get-VSCodeSettingsPath -Platform 'Windows' -AppData 'C:\Users\x\AppData\Roaming'
            $mac = Get-VSCodeSettingsPath -Platform 'MacOS' -HomeDir '/Users/x'
            $win | Should -Not -Match '/'
            $mac | Should -Not -Match ([regex]::Escape('\'))
        }

        It 'does not double a separator the caller already left on' {
            Get-VSCodeSettingsPath -Platform 'MacOS' -HomeDir '/Users/x/' |
                Should -Be '/Users/x/Library/Application Support/Code/User/settings.json'
        }

        It 'gives <Variant> its own path, because they install side by side' -ForEach @(
            @{ Variant = 'Code - Insiders' }
            @{ Variant = 'VSCodium' }
            @{ Variant = 'Cursor' }
            @{ Variant = 'Windsurf' }
        ) {
            $stable = Get-VSCodeSettingsPath -Platform 'macOS' -HomeDir '/Users/x'
            $other  = Get-VSCodeSettingsPath -Platform 'macOS' -HomeDir '/Users/x' -Variant $Variant
            $other | Should -Not -Be $stable
            $other | Should -Match ([regex]::Escape($Variant))
        }
    }
}

Describe 'Get-VSCodeVariant' {
    InModuleScope TerminalStyles {

        # Cursor, Windsurf and VSCodium all set TERM_PROGRAM=vscode, so
        # Get-TerminalKind's 'VSCode' names the FAMILY. Guessing stable VS Code
        # from that writes a Cursor user's style into an editor they may not
        # have installed, while the terminal in front of them does not change
        # and the command says it worked.

        It 'reads <Variant> out of a macOS application path' -ForEach @(
            @{ Variant = 'Cursor'
               Path = '/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass-main.js' }
            @{ Variant = 'Windsurf'
               Path = '/Applications/Windsurf.app/Contents/Resources/app/extensions/git/dist/askpass-main.js' }
            @{ Variant = 'VSCodium'
               Path = '/Applications/VSCodium.app/Contents/Resources/app/extensions/git/dist/askpass-main.js' }
            @{ Variant = 'Code'
               Path = '/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/git/dist/askpass-main.js' }
            @{ Variant = 'Code - Insiders'
               Path = '/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/git/dist/askpass-main.js' }
        ) {
            Get-VSCodeVariant -AskpassNode $Path | Should -Be $Variant
        }

        It 'reads a Windows install path' {
            Get-VSCodeVariant -AskpassNode 'C:\Users\x\AppData\Local\Programs\cursor\resources\app\out\node.exe' |
                Should -Be 'Cursor'
        }

        It 'reads a Linux install path' {
            Get-VSCodeVariant -AskpassNode '/usr/share/code/resources/app/extensions/git/dist/askpass-main.js' |
                Should -Be 'Code'
        }

        It 'falls back to GIT_ASKPASS when the VS Code variable is not set' {
            Get-VSCodeVariant -AskpassNode '' `
                -GitAskpass '/Applications/Windsurf.app/Contents/Resources/app/extensions/git/dist/askpass.sh' |
                Should -Be 'Windsurf'
        }

        It 'is not fooled by a username that happens to be an editor' {
            # Substring matching reads this as Cursor. Segment matching sees
            # both 'cursor' (the home directory) and 'Visual Studio Code', which
            # is two answers, which is no answer.
            Get-VSCodeVariant -AskpassNode '/Users/cursor/Applications/Visual Studio Code.app/Contents/x.js' |
                Should -BeNullOrEmpty
        }

        It 'says nothing rather than guessing when there is no evidence' {
            Get-VSCodeVariant -AskpassNode '' -GitAskpass '' | Should -BeNullOrEmpty
            Get-VSCodeVariant -AskpassNode '/usr/bin/env' -GitAskpass '' | Should -BeNullOrEmpty
        }

        It 'never answers a name Get-VSCodeSettingsPath would reject' {
            # The two halves of one rule: a variant this returns has to be a
            # variant the path builder accepts, or a correct detection still
            # throws at the call site.
            $paths = @(
                '/Applications/Cursor.app/x', '/Applications/Windsurf.app/x',
                '/Applications/VSCodium.app/x', '/Applications/Visual Studio Code.app/x',
                '/Applications/Visual Studio Code - Insiders.app/x'
            )
            foreach ($p in $paths) {
                $v = Get-VSCodeVariant -AskpassNode $p
                $v | Should -Not -BeNullOrEmpty
                { Get-VSCodeSettingsPath -Platform 'MacOS' -HomeDir '/Users/x' -Variant $v } | Should -Not -Throw
            }
        }
    }
}

Describe 'Get-VSCodeTerminalColor' {
    InModuleScope TerminalStyles {

        BeforeAll {
            $script:Scheme = Get-Content (Join-Path (Get-StyleDir -StyleName 'koholint') 'scheme.json') `
                -Raw | ConvertFrom-Json
        }

        It 'names every ID VS Code actually reads, and invents none' {
            # This list is the spec. VS Code silently ignores a colour ID it
            # does not know, so a typo here would paint nothing and report
            # success -- there is no error to notice.
            $expected = @(
                'terminal.background', 'terminal.foreground', 'terminalCursor.foreground',
                'terminal.selectionBackground',
                'terminal.ansiBlack', 'terminal.ansiRed', 'terminal.ansiGreen', 'terminal.ansiYellow',
                'terminal.ansiBlue', 'terminal.ansiMagenta', 'terminal.ansiCyan', 'terminal.ansiWhite',
                'terminal.ansiBrightBlack', 'terminal.ansiBrightRed', 'terminal.ansiBrightGreen',
                'terminal.ansiBrightYellow', 'terminal.ansiBrightBlue', 'terminal.ansiBrightMagenta',
                'terminal.ansiBrightCyan', 'terminal.ansiBrightWhite'
            )
            $got = Get-VSCodeTerminalColor -Scheme $script:Scheme
            @($got.Keys) | Should -Be $expected
        }

        It 'calls slot 5 magenta, which is what VS Code calls it' {
            # scheme.json speaks Windows Terminal ("purple"). Writing
            # terminal.ansiPurple would be ignored without complaint.
            $got = Get-VSCodeTerminalColor -Scheme $script:Scheme
            $got['terminal.ansiMagenta'] | Should -Be $script:Scheme.purple
            $got['terminal.ansiBrightMagenta'] | Should -Be $script:Scheme.brightPurple
        }

        It 'omits a colour the scheme does not carry rather than writing an empty one' {
            # VS Code reports "" as an invalid colour value; it does not treat
            # it as absent.
            $partial = [pscustomobject]@{ background = '#101010'; foreground = '#e0e0e0' }
            $got = Get-VSCodeTerminalColor -Scheme $partial
            $got.Keys | Should -Not -Contain 'terminal.ansiRed'
            @($got.Values) | Should -Not -Contain ''
            $got.Count | Should -Be 2
        }
    }
}

Describe 'the vocabulary VS Code does not share with Windows Terminal' {
    InModuleScope TerminalStyles {

        It 'maps cursor <Shape> to <Expected>' -ForEach @(
            @{ Shape = 'filledBox';  Expected = 'block' }
            @{ Shape = 'emptyBox';   Expected = 'block' }
            @{ Shape = 'bar';        Expected = 'line' }
            @{ Shape = 'underscore'; Expected = 'underline' }
            @{ Shape = 'vintage';    Expected = 'underline' }
        ) {
            Get-VSCodeCursorStyle -CursorShape $Shape | Should -Be $Expected
        }

        It 'says nothing about a cursor shape it does not know' {
            # Writing a shape VS Code rejects invalidates the setting; leaving
            # it alone leaves the user's own, which is at least theirs.
            Get-VSCodeCursorStyle -CursorShape 'hourglass' | Should -BeNullOrEmpty
        }

        It 'turns <Weight> into <Expected>, which VS Code will accept' -ForEach @(
            @{ Weight = 'normal';    Expected = 'normal' }
            @{ Weight = 'bold';      Expected = 'bold' }
            @{ Weight = 'semi-bold'; Expected = 600 }
            @{ Weight = 'light';     Expected = 300 }
        ) {
            Get-VSCodeFontWeight -Weight $Weight | Should -Be $Expected
        }

        It 'says nothing about a weight it does not know' {
            Get-VSCodeFontWeight -Weight 'ultra-heavy' | Should -BeNullOrEmpty
        }
    }
}

Describe 'ConvertTo-VSCodePixelSize' {
    InModuleScope TerminalStyles {

        # Windows Terminal documents font.size as POINTS; VS Code documents
        # terminal.integrated.fontSize as PIXELS. Copying the number across
        # wrote a terminal about a quarter smaller than the style asked for --
        # on all 18 bundled styles, so the normal outcome, not an edge case.

        It 'converts <Pt>pt to <Px>px' -ForEach @(
            @{ Pt = 11; Px = 15 }    # the bundled styles' size: 14.67, not 11
            @{ Pt = 12; Px = 16 }
            @{ Pt = 9;  Px = 12 }
            @{ Pt = 6;  Px = 8 }
        ) {
            ConvertTo-VSCodePixelSize -PointSize $Pt | Should -Be $Px
        }

        It 'rounds a half away from zero, not to even' {
            # [Math]::Round defaults to banker's rounding, so 14.5 would become
            # 14 and every half-point size would lose a pixel.
            ConvertTo-VSCodePixelSize -PointSize 10.875 | Should -Be 15
        }

        It 'is not the identity, which is what it replaced' {
            ConvertTo-VSCodePixelSize -PointSize 11 | Should -Not -Be 11
        }
    }
}

Describe 'Get-VSCodeStylePlan' {
    InModuleScope TerminalStyles {

        BeforeAll { $script:Dir = Get-StyleDir -StyleName 'koholint' }

        It 'converts the font size rather than copying it' {
            $theme = Get-Content (Join-Path $script:Dir 'theme.json') -Raw | ConvertFrom-Json
            # Assign, THEN pipe. Get-VSCodeStylePlan returns ,$arr so a
            # one-entry plan does not unroll -- and piping that return value
            # straight into Where-Object hands it the whole array as a single
            # item, which matches nothing and reports zero.
            $plan = Get-VSCodeStylePlan -StyleDir $script:Dir
            $entry = @($plan | Where-Object { $_.Path[0] -eq 'terminal.integrated.fontSize' })
            $entry.Count | Should -Be 1
            $entry[0].Value | Should -Be (ConvertTo-VSCodePixelSize -PointSize ([double]$theme.font.size))
            $entry[0].Value | Should -Not -Be $theme.font.size
        }

        It 'nests the colours and leaves the terminal settings at the top' {
            $plan = Get-VSCodeStylePlan -StyleDir $script:Dir
            @($plan | Where-Object { $_.Path[0] -eq 'workbench.colorCustomizations' }).Count |
                Should -BeGreaterThan 15
            @($plan | Where-Object { $_.Path.Count -eq 1 -and $_.Path[0] -notlike 'terminal.integrated.*' }).Count |
                Should -Be 0
        }

        It 'never mentions a background image, because VS Code has none' {
            ((Get-VSCodeStylePlan -StyleDir $script:Dir) | ConvertTo-Json -Depth 10) |
                Should -Not -Match 'backgroundImage'
        }
    }
}

Describe 'applying and resetting a style in settings.json text' {
    InModuleScope TerminalStyles {

        BeforeAll {
            $script:Dir = Get-StyleDir -StyleName 'koholint'

            # A file shaped like one somebody actually has: comments, their own
            # colour overrides, unrelated settings -- AND a terminal setting
            # they chose themselves whose value happens to be what koholint
            # writes. That last line is the one the old round-trip fixture left
            # out, which is why it could never catch the bug below.
            $script:User = @'
{
  // --- my terminal ---
  "terminal.integrated.cursorStyle": "block", // I hate the bar
  "editor.fontSize": 13,
  "workbench.colorCustomizations": {
    "editor.background": "#1b1b1b"
  }
}
'@
        }

        It 'keeps every comment in the file' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $a.Changed | Should -BeTrue
            Test-JsoncCommentsIntact -Before $script:User -After $a.Text | Should -BeTrue
        }

        It 'leaves settings and colours that are not ours alone' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            (Get-JsoncValueLiteral -Text $a.Text -Path @('editor.fontSize')) | Should -Be '13'
            (Get-JsoncValueLiteral -Text $a.Text -Path @('workbench.colorCustomizations', 'editor.background')) |
                Should -Be '"#1b1b1b"'
        }

        It 'puts the file back exactly as it was' {
            # Byte-identity, on a fixture that DOES contain one of the plan's
            # keys. The previous version of this test used a fixture with none
            # of them in it, so it could never reach the case below.
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            $b.Text | Should -Be $script:User
        }

        It 'restores a setting the user already had, rather than deleting it' {
            # THE BUG THIS EXISTS FOR. koholint's filledBox maps to "block",
            # and this user set "block" themselves years ago. Value-matching
            # says "this key holds our value, so it is ours" and deletes their
            # setting. Provenance says we overwrote a value that was already
            # there, so undoing means putting it back.
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            (Get-JsoncValueLiteral -Text $b.Text -Path @('terminal.integrated.cursorStyle')) |
                Should -Be '"block"'
            $b.Text | Should -Match ([regex]::Escape('// I hate the bar'))
        }

        It 'removes a key that was not there before' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            (Get-JsoncValueLiteral -Text $b.Text -Path @('terminal.integrated.fontFamily')) |
                Should -BeNullOrEmpty
            $b.Removed | Should -Contain 'terminal.integrated.fontFamily'
        }

        It 'keeps, and reports, a value the user changed after we wrote it' {
            # "I left it because it looks like yours" must not collapse into
            # "there was nothing to do".
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $edited = (Set-JsoncLiteral -Text $a.Text -Path @('terminal.integrated.fontFamily') -Literal '"Fira Code"').Text
            $b = Invoke-VSCodeStyleReset -Text $edited -Record $a.Record
            (Get-JsoncValueLiteral -Text $b.Text -Path @('terminal.integrated.fontFamily')) | Should -Be '"Fira Code"'
            $b.Kept | Should -Contain 'terminal.integrated.fontFamily'
        }

        It 'compares what it wrote ordinally, so a re-cased value is the user''s' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            # A colour with letters in it: koholint's background is #182098,
            # all digits, so re-casing it changes nothing and the case would
            # never be exercised.
            $path = @('workbench.colorCustomizations', 'terminal.foreground')
            $lit = Get-JsoncValueLiteral -Text $a.Text -Path $path
            $lit | Should -Match '[a-f]' -Because 'the case has to be able to differ'
            $edited = (Set-JsoncLiteral -Text $a.Text -Path $path -Literal $lit.ToUpperInvariant()).Text
            $b = Invoke-VSCodeStyleReset -Text $edited -Record $a.Record
            $b.Kept | Should -Contain 'workbench.colorCustomizations/terminal.foreground'
        }

        It 'creates the colour block when the file has none, and takes it away again' {
            $bare = "{`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $bare -StyleDir $script:Dir -StyleName 'koholint'
            (Get-JsoncValueLiteral -Text $a.Text -Path @('workbench.colorCustomizations', 'terminal.background')) |
                Should -Not -BeNullOrEmpty
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            $b.Text | Should -Be $bare
        }

        It 'does not need the style any more once it has applied it' {
            # `tstyles delete koholint` then reset used to strand twenty colour
            # keys with no command able to name them. The record names them.
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint'
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            $b.Status | Should -Be 'reset'
            $b.Text   | Should -Be $script:User
        }

        It 'refuses a file whose root is not an object' {
            $a = Invoke-VSCodeStyleApply -Text '[1,2]' -StyleDir $script:Dir -StyleName 'koholint'
            $a.Changed | Should -BeFalse
            $a.Status  | Should -Be 'rootnotobject'
        }

        It 'says so rather than guessing when it has no record' {
            $b = Invoke-VSCodeStyleReset -Text $script:User -Record $null
            $b.Status | Should -Be 'norecord'
            $b.Text   | Should -Be $script:User
        }
    }
}
