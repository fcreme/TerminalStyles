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

Describe 'Get-VSCodeColorOverride' {
    InModuleScope TerminalStyles {

        # A style can be written correctly, saved, and still not show up: a
        # theme-scoped block inside workbench.colorCustomizations wins over its
        # plain siblings when that theme is active. VS Code has issues filed on
        # the confusion (microsoft/vscode#61566; #303246 names
        # terminal.background). Reporting success over that is the capability
        # rule's false promise with the writer working.

        It 'finds a theme-scoped block that sets a colour we write' {
            $t = @'
{
  "workbench.colorCustomizations": {
    "[Default Dark+]": { "terminal.background": "#000000" },
    "terminal.background": "#182098"
  }
}
'@
            $hits = Get-VSCodeColorOverride -Text $t -Ids @('terminal.background', 'terminal.foreground')
            $hits.Count | Should -Be 1
            $hits[0].Scope | Should -Be '[Default Dark+]'
            $hits[0].Ids   | Should -Contain 'terminal.background'
        }

        It 'ignores a scoped block that touches nothing of ours' {
            $t = '{ "workbench.colorCustomizations": { "[Monokai]": { "sideBar.background": "#347890" } } }'
            (Get-VSCodeColorOverride -Text $t -Ids @('terminal.background')).Count | Should -Be 0
        }

        It 'ignores plain colour ids, which we overwrite on purpose' {
            $t = '{ "workbench.colorCustomizations": { "terminal.background": "#000000" } }'
            (Get-VSCodeColorOverride -Text $t -Ids @('terminal.background')).Count | Should -Be 0
        }

        It 'finds every colliding scope, not just the first' {
            $t = @'
{
  "workbench.colorCustomizations": {
    "[Abyss]": { "terminal.background": "#000000" },
    "[Monokai*]": { "terminal.foreground": "#ffffff" }
  }
}
'@
            $hits = Get-VSCodeColorOverride -Text $t -Ids @('terminal.background', 'terminal.foreground')
            $hits.Count | Should -Be 2
            @($hits | ForEach-Object { $_.Scope }) | Should -Contain '[Monokai*]'
        }

        It 'does not read the ROOT object when a scoped key holds no object' {
            # Legal JSON, nonsense settings: a "[Theme]" key whose value is a
            # string. Its ValueOpen is -1, and without the object guard the
            # member scan starts at token 0 -- the root -- and reports root
            # keys as though they sat inside the scoped block. A mutation
            # removing that guard survived until this fixture existed, because
            # the earlier ones had nothing at the root to collide with.
            $t = @'
{
  "terminal.background": "#deadbe",
  "workbench.colorCustomizations": { "[Monokai]": "#ffffff" }
}
'@
            (Get-VSCodeColorOverride -Text $t -Ids @('terminal.background')).Count | Should -Be 0
        }

        It 'says nothing when there is no colour block at all' {
            (Get-VSCodeColorOverride -Text '{ "editor.fontSize": 13 }' -Ids @('terminal.background')).Count |
                Should -Be 0
        }

        It 'reports what a real style would actually collide with' {
            # The ids are the plan's, not a hand-written list, so this cannot
            # drift away from what the apply writes.
            $plan = Get-VSCodeStylePlan -StyleDir (Get-StyleDir -StyleName 'koholint')
            $ids = @($plan | Where-Object { $_.Path.Count -eq 2 } | ForEach-Object { $_.Path[1] })
            $t = '{ "workbench.colorCustomizations": { "[Default Dark+]": { "terminal.ansiRed": "#ff0000" } } }'
            $hits = Get-VSCodeColorOverride -Text $t -Ids $ids
            $hits.Count | Should -Be 1
            $hits[0].Ids | Should -Contain 'terminal.ansiRed'
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

        It 'takes the previous style off before putting the next one on' {
            # MEASURED, not theorised. eva writes fontWeight 600 and koholint
            # writes "normal". Apply eva, apply koholint, reset koholint, and
            # the file was left holding 600 -- eva's value, on a machine whose
            # owner never set a font weight, with no command able to remove it.
            # koholint's record had captured eva's leftover as "what was there
            # before", so the reset faithfully restored the wrong thing.
            $user = "{`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $user -StyleDir (Get-StyleDir -StyleName 'eva') -StyleName 'eva'
            $b = Invoke-VSCodeStyleApply -Text $a.Text -StyleDir $script:Dir -StyleName 'koholint' -PreviousRecord $a.Record
            $c = Invoke-VSCodeStyleReset -Text $b.Text -Record $b.Record
            (Get-JsoncValueLiteral -Text $c.Text -Path @('terminal.integrated.fontWeight')) | Should -BeNullOrEmpty
            $c.Text | Should -Be $user
        }

        It 'survives a chain of styles and still comes back' {
            # Changing your mind means another style far more often than it
            # means a reset, so the chain is the normal path, not the edge.
            $user = "{`n  `"editor.fontSize`": 13`n}"
            $r = Invoke-VSCodeStyleApply -Text $user -StyleDir (Get-StyleDir -StyleName 'eva') -StyleName 'eva'
            foreach ($name in @('koholint', 'umbrella', 'lain')) {
                $r = Invoke-VSCodeStyleApply -Text $r.Text -StyleDir (Get-StyleDir -StyleName $name) `
                        -StyleName $name -PreviousRecord $r.Record
            }
            (Invoke-VSCodeStyleReset -Text $r.Text -Record $r.Record).Text | Should -Be $user
        }

        It 'keeps comments across a style switch' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir (Get-StyleDir -StyleName 'eva') -StyleName 'eva'
            $b = Invoke-VSCodeStyleApply -Text $a.Text -StyleDir $script:Dir -StyleName 'koholint' -PreviousRecord $a.Record
            Test-JsoncCommentsIntact -Before $script:User -After $b.Text | Should -BeTrue
        }

        It 'reports what the outgoing style could not take back' {
            # A value the user changed while style A was on is theirs. The
            # switch must not silently drop it, and must not silently keep it
            # either -- it says which.
            $user = "{`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $user -StyleDir (Get-StyleDir -StyleName 'eva') -StyleName 'eva'
            $edited = (Set-JsoncLiteral -Text $a.Text -Path @('terminal.integrated.fontFamily') -Literal '"Fira Code"').Text
            $b = Invoke-VSCodeStyleApply -Text $edited -StyleDir $script:Dir -StyleName 'koholint' -PreviousRecord $a.Record
            $b.Kept | Should -Contain 'terminal.integrated.fontFamily'
        }

        It 'behaves as before when there is no previous style' {
            $a = Invoke-VSCodeStyleApply -Text $script:User -StyleDir $script:Dir -StyleName 'koholint' -PreviousRecord $null
            $b = Invoke-VSCodeStyleReset -Text $a.Text -Record $a.Record
            $b.Text | Should -Be $script:User
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
