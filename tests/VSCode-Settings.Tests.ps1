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

Describe 'Merge-StyleIntoVSCodeSettings' {
    InModuleScope TerminalStyles {

        BeforeAll {
            # A settings.json shaped like one somebody actually has: their own
            # colour overrides, and settings that have nothing to do with us.
            $script:UserJson = @'
{
  "editor.fontSize": 13,
  "files.autoSave": "onFocusChange",
  "workbench.colorCustomizations": {
    "editor.background": "#1b1b1b",
    "statusBar.background": "#332211"
  },
  "terminal.integrated.scrollback": 20000
}
'@
            function New-UserSettings { $script:UserJson | ConvertFrom-Json }
        }

        It 'writes the style colours' {
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) `
                    -StyleDir (Get-StyleDir -StyleName 'koholint')
            $scheme = Get-Content (Join-Path (Get-StyleDir -StyleName 'koholint') 'scheme.json') -Raw | ConvertFrom-Json
            $s.'workbench.colorCustomizations'.'terminal.background' | Should -Be $scheme.background
            $s.'workbench.colorCustomizations'.'terminal.ansiMagenta' | Should -Be $scheme.purple
        }

        It 'leaves colour customisations that are not ours exactly where they were' {
            # The whole file is one object. A merge that replaced
            # workbench.colorCustomizations wholesale would silently delete
            # every editor colour the user had set.
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) `
                    -StyleDir (Get-StyleDir -StyleName 'koholint')
            $s.'workbench.colorCustomizations'.'editor.background' | Should -Be '#1b1b1b'
            $s.'workbench.colorCustomizations'.'statusBar.background' | Should -Be '#332211'
        }

        It 'leaves settings outside our own alone' {
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) `
                    -StyleDir (Get-StyleDir -StyleName 'koholint')
            $s.'editor.fontSize' | Should -Be 13
            $s.'files.autoSave' | Should -Be 'onFocusChange'
            $s.'terminal.integrated.scrollback' | Should -Be 20000
        }

        It 'creates the colour block when the file has none' {
            $s = Merge-StyleIntoVSCodeSettings -Settings ('{ "editor.fontSize": 13 }' | ConvertFrom-Json) `
                    -StyleDir (Get-StyleDir -StyleName 'koholint')
            $s.'workbench.colorCustomizations'.'terminal.foreground' | Should -Not -BeNullOrEmpty
        }

        It 'says nothing about a font the style does not specify' {
            # "this style has no opinion" and "this style wants the default"
            # are different, and writing a default would be the second claim.
            $dir = Join-Path $TestDrive 'nofont'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            '{ "background": "#101010", "foreground": "#eeeeee" }' |
                Set-Content (Join-Path $dir 'scheme.json') -Encoding utf8
            '{ "colorScheme": "nofont" }' | Set-Content (Join-Path $dir 'theme.json') -Encoding utf8

            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) -StyleDir $dir
            $s.PSObject.Properties['terminal.integrated.fontFamily'] | Should -BeNullOrEmpty
            $s.PSObject.Properties['terminal.integrated.cursorStyle'] | Should -BeNullOrEmpty
        }

        It 'never mentions a background image, because VS Code has none' {
            # The capability rule, as a test. koholint HAS a backgroundImage in
            # its theme.json; if any key here carried it, the style would look
            # applied while the picture was silently dropped.
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) `
                    -StyleDir (Get-StyleDir -StyleName 'koholint')
            ($s | ConvertTo-Json -Depth 100) | Should -Not -Match 'backgroundImage'
        }
    }
}

Describe 'Remove-StyleFromVSCodeSettings' {
    InModuleScope TerminalStyles {

        BeforeAll {
            $script:UserJson = @'
{
  "editor.fontSize": 13,
  "workbench.colorCustomizations": {
    "editor.background": "#1b1b1b"
  },
  "terminal.integrated.scrollback": 20000
}
'@
            function New-UserSettings { $script:UserJson | ConvertFrom-Json }
        }

        It 'puts the file back exactly as it was' {
            # The property that makes this safe to ship: apply then reset is
            # the identity. Compared as serialised JSON so key order, nesting
            # and types all have to match, not just the values we thought to
            # look at.
            $dir = Get-StyleDir -StyleName 'koholint'
            $before = (New-UserSettings) | ConvertTo-Json -Depth 100
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) -StyleDir $dir
            $s = Remove-StyleFromVSCodeSettings -Settings $s -StyleDir $dir
            ($s | ConvertTo-Json -Depth 100) | Should -Be $before
        }

        It 'keeps a colour the user changed by hand after applying' {
            # Reset removes what an apply put there. A value that is no longer
            # ours is the user's, and taking it out would be deleting their
            # edit to fix our own.
            $dir = Get-StyleDir -StyleName 'koholint'
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) -StyleDir $dir
            $s.'workbench.colorCustomizations'.'terminal.ansiRed' = '#ff0000'
            $s = Remove-StyleFromVSCodeSettings -Settings $s -StyleDir $dir
            $s.'workbench.colorCustomizations'.'terminal.ansiRed' | Should -Be '#ff0000'
        }

        It 'does not leave an empty colour block behind' {
            # An orphan {} in a config we were asked to clean out is the same
            # defect as an orphan colour scheme in settings.json.
            $dir = Get-StyleDir -StyleName 'koholint'
            $s = Merge-StyleIntoVSCodeSettings -Settings ('{ "editor.fontSize": 13 }' | ConvertFrom-Json) -StyleDir $dir
            $s = Remove-StyleFromVSCodeSettings -Settings $s -StyleDir $dir
            $s.PSObject.Properties['workbench.colorCustomizations'] | Should -BeNullOrEmpty
        }

        It 'keeps the colour block when the user has their own colours in it' {
            $dir = Get-StyleDir -StyleName 'koholint'
            $s = Merge-StyleIntoVSCodeSettings -Settings (New-UserSettings) -StyleDir $dir
            $s = Remove-StyleFromVSCodeSettings -Settings $s -StyleDir $dir
            $s.'workbench.colorCustomizations'.'editor.background' | Should -Be '#1b1b1b'
        }

        It 'removes what it wrote from a file it has never seen before' {
            $dir = Get-StyleDir -StyleName 'koholint'
            $s = Remove-StyleFromVSCodeSettings -Settings (New-UserSettings) -StyleDir $dir
            $s.'editor.fontSize' | Should -Be 13
            $s.'workbench.colorCustomizations'.'editor.background' | Should -Be '#1b1b1b'
        }
    }
}
