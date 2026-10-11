# The VS Code settings WRITER: lib/vscodewriter.ps1, the half of the VS Code
# support that touches files. lib/vscode.ps1 is the pure text engine and is
# tested in VSCode-Settings.Tests.ps1; everything here is about what reaches
# disk, in what order, and what the user is told.
#
# Nothing here may resolve a real editor's settings.json. Every Describe either
# mocks Resolve-VSCodeTarget to a $TestDrive path or binds all three of its path
# seams, and sandboxes $script:TStylesDataRoot, which holds vscode-state.json.
# Confirm-Action is mocked, never answered.
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

Describe 'Resolve-VSCodeTarget' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            # All three path seams, so no platform can fall through to a real
            # profile: macOS reads HomeDir, Linux XDG, Windows APPDATA.
            $script:seams = @{
                HomeDir       = $script:h
                AppData       = (Join-Path $script:h 'AppData/Roaming')
                XdgConfigHome = (Join-Path $script:h '.config')
            }
            $script:cursor = '/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh'
        }

        It 'refuses to guess when it cannot name the editor' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -AskpassNode '' -GitAskpass '' @s
            $t.Status  | Should -Be 'unknownvariant'
            $t.Variant | Should -BeNullOrEmpty
            $t.Path    | Should -BeNullOrEmpty -Because 'with no path, nothing can be written to the wrong one'
        }

        It 'says nodir, and creates nothing, when the editor has no User folder' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -AskpassNode $script:cursor -GitAskpass '' @s
            $t.Status  | Should -Be 'nodir'
            $t.Variant | Should -Be 'Cursor'
            [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($t.Path)) |
                Should -BeFalse -Because 'asking where the file is must not create its folder'
        }

        It 'is ok with a User folder and no settings.json in it yet' {
            $s = $script:seams
            $expected = Get-VSCodeSettingsPath -Variant 'Cursor' @s
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($expected)) -Force | Out-Null

            $t = Resolve-VSCodeTarget -AskpassNode $script:cursor -GitAskpass '' @s
            $t.Status | Should -Be 'ok'
            $t.Path   | Should -Be $expected
            [System.IO.File]::Exists($t.Path) | Should -BeFalse -Because 'VS Code creates it lazily, and so may we'
        }

        It 'takes a variant it is given instead of detecting one' {
            $s = $script:seams
            $t = Resolve-VSCodeTarget -Variant 'VSCodium' -AskpassNode '' -GitAskpass '' @s
            $t.Variant | Should -Be 'VSCodium'
            $t.Path    | Should -Be (Get-VSCodeSettingsPath -Variant 'VSCodium' @s)
        }

        It 'keeps a bound -HomeDir away from the real APPDATA and XDG_CONFIG_HOME' {
            # The sandbox rule CLAUDE.md states for ZDOTDIR, one level further:
            # on Windows Get-VSCodeSettingsPath prefers APPDATA, so -HomeDir
            # alone would still resolve to the operator's roaming profile.
            $t = Resolve-VSCodeTarget -Variant 'Code' -HomeDir $script:h
            $t.Path.StartsWith($script:h) | Should -BeTrue -Because "$($t.Path) must be inside the sandbox"
        }

        It 'forwards an empty AppData when only -HomeDir is bound' {
            # The test above cannot see this on macOS or Linux: only the Windows
            # branch of Get-VSCodeSettingsPath reads APPDATA. So check what is
            # PASSED ON, which is the same on every platform.
            Mock Get-VSCodeSettingsPath { Join-Path $script:h 'x/settings.json' }
            Resolve-VSCodeTarget -Variant 'Code' -HomeDir $script:h | Out-Null
            Should -Invoke Get-VSCodeSettingsPath -Times 1 -Exactly -ParameterFilter { $AppData -ceq '' }
        }
    }
}

Describe 'the VS Code state store' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:koholint = Get-StyleDir -StyleName 'koholint'
        }

        It 'reads no file as empty, not as broken' {
            $s = Read-VSCodeState
            $s.Ok | Should -BeTrue
            $s.Entries.Count | Should -Be 0
        }

        It 'will not start over on top of a file it cannot read' {
            # It holds the only record of which keys went into a settings.json.
            # Replacing it would strand them.
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{not json', [System.Text.UTF8Encoding]::new($false))
            (Read-VSCodeState).Ok | Should -BeFalse
            { Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' } | Should -Throw
            [System.IO.File]::ReadAllText((Get-VSCodeStatePath)) | Should -BeExactly '{not json'
        }

        It 'treats a root that is not an object as unreadable too' {
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '[1,2]', [System.Text.UTF8Encoding]::new($false))
            (Read-VSCodeState).Ok | Should -BeFalse
        }

        It 'lets a failed state write through, so the caller knows the record did not land' {
            # NO KEY WITHOUT A RECORD (see the header of lib/vscodewriter.ps1): the
            # record is saved first and settings.json only after, which works only
            # if a state write that fails says so. Write-SettingsAtomic is what
            # fails here; everything above it has to let that through.
            # -ExpectedMessage shows it was this mock that fired, not some other
            # failure on the way.
            Mock Write-SettingsAtomic { throw 'read-only data root' }
            { Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' } |
                Should -Throw -ExpectedMessage '*read-only data root*'
        }

        It 'stops the caller when the state file really cannot be written' {
            # A real failure rather than a mock, and the message is part of the
            # assertion. A mocked throw is already script-terminating, and
            # Should -Throw is itself a try/catch, so neither can tell our rethrow
            # from the bare .NET exception Write-SettingsAtomic raises -- which,
            # under a caller with no try of its own, is printed and then stepped
            # over, record unsaved. Only our own words prove the conversion ran.
            # A directory cannot be written as a file, which is how this fails.
            New-Item -ItemType Directory -Path (Get-VSCodeStatePath) -Force | Out-Null
            { Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' } |
                Should -Throw -ExpectedMessage 'Could not write*'
        }

        It 'changes one editor and leaves the others as they were' {
            Set-VSCodeStateEntry -Variant 'Code'   -SettingsPath '/c/settings.json' -Consent 'yes'
            Set-VSCodeStateEntry -Variant 'Cursor' -SettingsPath '/u/settings.json' -Consent 'no'
            Set-VSCodeStateEntry -Variant 'Code'   -Consent 'no'

            $e = (Read-VSCodeState).Entries
            $e['Code'].consent        | Should -Be 'no'
            $e['Code'].settingsPath   | Should -Be '/c/settings.json'
            $e['Cursor'].consent      | Should -Be 'no'
            $e['Cursor'].settingsPath | Should -Be '/u/settings.json'
        }

        It 'round-trips a variant name with spaces in it' {
            Set-VSCodeStateEntry -Variant 'Code - Insiders' -Consent 'yes'
            (Read-VSCodeState).Entries['Code - Insiders'].consent | Should -Be 'yes'
        }

        It 'clears a record only when -Record is bound' {
            $a = Invoke-VSCodeStyleApply -Text '{}' -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' -Record $a.Record
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty -Because '-Record was not bound'
            Set-VSCodeStateEntry -Variant 'Code' -Record $null
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'leaves consent and settingsPath alone when only a record is set' {
            # Only what was BOUND changes. -Record $null is bound, so it clears
            # the record; consent and settingsPath were not, so a 'yes' must still
            # be a 'yes' -- losing it would ask the user a second time.
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'yes' -SettingsPath '/x'
            Set-VSCodeStateEntry -Variant 'Code' -Record $null
            $e = (Read-VSCodeState).Entries['Code']
            $e.consent      | Should -Be 'yes'
            $e.settingsPath | Should -Be '/x'
        }

        It 'brings a record back from the file that still undoes the apply byte for byte' {
            # The test the record never had: through JSON and back. Windows
            # PowerShell 5.1 is where this would break -- ConvertTo-Json stops
            # at depth 2 by default, and a one-element array can come back as
            # its bare element.
            $user = "{`n  // mine`n  `"terminal.integrated.cursorStyle`": `"block`",`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $user -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath '/x' -Record $a.Record

            $back = (Read-VSCodeState).Entries['Code'].record
            $back.Style | Should -Be 'koholint'
            (Invoke-VSCodeStyleReset -Text $a.Text -Record $back).Text | Should -BeExactly $user
        }

        It 'keeps a one-key path a path, not a string' {
            $a = Invoke-VSCodeStyleApply -Text '{}' -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Record $a.Record
            $font = @((Read-VSCodeState).Entries['Code'].record.Wrote |
                      Where-Object { $_.Path[0] -eq 'terminal.integrated.fontFamily' })
            $font.Count | Should -Be 1 -Because 'koholint sets a font face'
            ,$font[0].Path | Should -BeOfType [string[]]
            @($font[0].Path).Count | Should -Be 1
        }

        It 'keeps the parent it created, so the emptied block is still taken away' {
            $bare = "{`n  `"editor.fontSize`": 13`n}"
            $a = Invoke-VSCodeStyleApply -Text $bare -StyleDir $script:koholint -StyleName 'koholint'
            Set-VSCodeStateEntry -Variant 'Code' -Record $a.Record
            $back = (Read-VSCodeState).Entries['Code'].record
            @($back.CreatedParents).Count | Should -Be 1
            (Invoke-VSCodeStyleReset -Text $a.Text -Record $back).Text | Should -BeExactly $bare
        }

        It 'reads no file as an empty string, not as null' {
            # The function's own promise: the file's text, or '' when there is no
            # file yet. Test-VSCodeSettingsReadable calls blank text readable, so
            # a settings.json that does not exist reads as blank settings.
            Read-VSCodeSettingsText -Path (Join-Path $TestDrive 'nope.json') | Should -BeExactly ''
        }

        It 'stops the caller when settings.json really cannot be read' {
            # The same reasoning as the write above. Held open with no sharing, the
            # file exists but ReadAllText cannot read it: natively on Windows, and
            # on Unix through .NET's advisory lock. A bare .NET failure would leave
            # the caller holding $null, which Test-VSCodeSettingsReadable calls
            # blank -- an unreadable file passing for "no settings yet".
            $p = Join-Path $TestDrive 'held.json'
            [System.IO.File]::WriteAllText($p, '{}', [System.Text.UTF8Encoding]::new($false))
            $fs = [System.IO.File]::Open($p, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                { Read-VSCodeSettingsText -Path $p } | Should -Throw -ExpectedMessage 'Could not read*'
            } finally { $fs.Dispose() }
        }
    }
}

Describe 'Test-VSCodeSettingsReadable' {
    InModuleScope TerminalStyles {
        It 'reads <label> as <ok>' -ForEach @(
            @{ label = 'a blank file';       text = '';                        ok = $true  }
            @{ label = 'whitespace';         text = "  `n";                    ok = $true  }
            @{ label = 'an object';          text = '{ "a": 1 }';              ok = $true  }
            @{ label = 'a commented object'; text = "// mine`n{ `"a`": 1 }";   ok = $true  }
            @{ label = 'a truncated object'; text = '{ "a": 1 ';               ok = $false }
            @{ label = 'an array';           text = '[1, 2]';                  ok = $false }
        ) {
            Test-VSCodeSettingsReadable -Text $text | Should -Be $ok
        }
    }
}

Describe 'Get-VSCodeWriterState and the question it asks' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-Host { }
        }

        It 'is undecided before anyone has been asked' {
            (Get-VSCodeWriterState).Status | Should -Be 'undecided'
            Test-VSCodeWriterActive | Should -BeFalse
        }

        It 'passes through an editor it cannot name' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Get-VSCodeWriterState).Status | Should -Be 'unknownvariant'
        }

        It 'passes through a missing settings folder' {
            Mock Resolve-VSCodeTarget { @{ Status = 'nodir'; Variant = 'Code'; Path = $script:sPath } }
            (Get-VSCodeWriterState).Status | Should -Be 'nodir'
        }

        It 'is statecorrupt when the record file cannot be read' {
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{broken', [System.Text.UTF8Encoding]::new($false))
            (Get-VSCodeWriterState).Status | Should -Be 'statecorrupt'
        }

        It 'asks at a console, remembers yes, and does not ask again' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Request-VSCodeWriterConsent | Should -Be 'active'
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            Request-VSCodeWriterConsent | Should -Be 'active'
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It -Because 'once per editor'
            Test-VSCodeWriterActive | Should -BeTrue
        }

        It 'remembers no' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $false }
            Request-VSCodeWriterConsent | Should -Be 'declined'
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'no'
            Request-VSCodeWriterConsent | Should -Be 'declined'
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'does not ask, and stores nothing, when nobody is at the console' {
            # Confirm-Action would answer $false here too -- for "nobody could be
            # asked", which must not be stored as the user's no.
            Mock Test-InteractiveConsole { $false }
            Mock Confirm-Action { throw 'nobody is there to be asked' }
            Request-VSCodeWriterConsent | Should -Be 'undecided'
            [System.IO.File]::Exists((Get-VSCodeStatePath)) | Should -BeFalse
        }

        It 'names the file it would write, in the question' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $false }
            Request-VSCodeWriterConsent | Out-Null
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match "Code's settings\.json" }
        }

        It 'reports an answer it could not store, and stays undecided' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Mock Set-VSCodeStateEntry { throw 'read-only' }
            Request-VSCodeWriterConsent | Should -Be 'undecided'
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Could not save that answer' }
        }

        It 'does not ask an editor that has already answered' {
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { throw 'already answered' }
            Request-VSCodeWriterConsent | Should -Be 'declined'
        }
    }
}

Describe 'Publish-StyleVSCodeConfig' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            $script:eva      = Get-StyleDir -StyleName 'eva'

            # A style with a scheme and no theme.json: it writes colours only,
            # never a font or a cursor.
            $script:plain = Join-Path $script:TStylesDataRoot 'styles/plain'
            New-Item -ItemType Directory -Path $script:plain -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:plain 'scheme.json'),
                '{"name":"plain","background":"#101010","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))

            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
        }

        It 'returns nothing off VS Code' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'WezTerm' |
                Should -BeNullOrEmpty
        }

        It 'writes the style, keeps the comments, and saves the record' {
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            $text = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $text -Path @('workbench.colorCustomizations', 'terminal.background') |
                Should -Not -BeNullOrEmpty
            Test-JsoncCommentsIntact -Before $script:user -After $text | Should -BeTrue
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'
        }

        It 'takes a first-touch copy before the first write, and only then' {
            $r1 = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r1.Backup | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($r1.Backup) | Should -BeExactly $script:user
            $r2 = Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode'
            $r2.Backup | Should -BeNullOrEmpty -Because 'a later copy would capture a file that already carries a style'
        }

        It 'writes nothing while <consent>' -ForEach @(
            @{ consent = 'declined';  expected = 'declined' }
            @{ consent = 'undecided'; expected = 'undecided' }
        ) {
            if ($consent -eq 'declined') {
                Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            } else {
                Remove-Item -LiteralPath (Get-VSCodeStatePath) -Force
            }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be $expected
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'passes an editor it cannot name straight through, reading nothing' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            Mock Read-VSCodeSettingsText { throw 'must not read' }
            (Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode').Status |
                Should -Be 'unknownvariant'
        }

        It 'refuses a file that does not parse, and keeps no record' {
            [System.IO.File]::WriteAllText($script:sPath, '{ "a": 1 ', [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'does not parse'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly '{ "a": 1 '
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'refuses a file it cannot read, rather than treating it as empty' {
            # Held open with no sharing: ReadAllText fails on every platform
            # the suite runs on. Writing over it would replace the user's file.
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            } finally { $fs.Dispose() }
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'could not be read'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'says what is wrong when the colour block is not an object' {
            [System.IO.File]::WriteAllText($script:sPath, '{ "workbench.colorCustomizations": null }',
                [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'colorCustomizations'
        }

        It 'starts a missing settings.json from {}' {
            Remove-Item -LiteralPath $script:sPath -Force
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            Test-VSCodeSettingsReadable -Text ([System.IO.File]::ReadAllText($script:sPath)) | Should -BeTrue
            $r.Backup | Should -BeNullOrEmpty -Because 'there was no file to copy'
        }

        It 'puts the record back when the settings write fails' {
            # Pester 6 throws on a call no filter matches (Pester 5 called the
            # real command), so the state write needs a default mock to land on.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status     | Should -Be 'writefailed'
            $r.FailedPath | Should -Be $script:sPath
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty -Because 'no key landed, so no record may claim one'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'keeps the previous style''s record when switching fails' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $styled = [System.IO.File]::ReadAllText($script:sPath)
            # Default first, for the reason the test above gives.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            $r = Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode'
            $r.Status | Should -Be 'writefailed'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the file still holds koholint, so its record must still name it'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $styled
        }

        It 'says so when the record cannot be put back either' {
            $script:stateWrites = 0
            Mock Write-SettingsAtomic {
                $script:stateWrites++
                if ($script:stateWrites -gt 1) { throw 'disk full' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'writefailed'
            $r.Detail | Should -Match 'undo record could not be restored'
        }

        It 'does not touch settings.json when its record cannot be saved' {
            Mock Set-VSCodeStateEntry { throw 'read-only data root' }
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status     | Should -Be 'writefailed'
            $r.FailedPath | Should -Be (Get-VSCodeStatePath)
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'names a theme block that will hide the colours' {
            $scoped = "{`n  `"workbench.colorCustomizations`": {`n    `"[Monokai]`": { `"terminal.background`": `"#000000`" }`n  }`n}"
            [System.IO.File]::WriteAllText($script:sPath, $scoped, [System.Text.UTF8Encoding]::new($false))
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode'
            $r.Status | Should -Be 'written'
            @($r.Overrides).Count | Should -Be 1
            $r.Overrides[0].Scope | Should -Be '[Monokai]'
            $r.Overrides[0].Ids   | Should -Contain 'terminal.background'
        }

        It 'says which hand edits it left, and which the next style wrote over' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            # Two keys changed by hand while koholint is on: one the next style
            # also sets (the background), one it does not (the font).
            $t = [System.IO.File]::ReadAllText($script:sPath)
            $t = (Set-JsoncLiteral -Text $t -Path @('workbench.colorCustomizations', 'terminal.background') -Literal '"#000000"').Text
            $t = (Set-JsoncLiteral -Text $t -Path @('terminal.integrated.fontFamily') -Literal '"Mine Mono"').Text
            [System.IO.File]::WriteAllText($script:sPath, $t, [System.Text.UTF8Encoding]::new($false))

            $r = Publish-StyleVSCodeConfig -StyleName 'plain' -StyleDir $script:plain -Kind 'VSCode'
            $r.Status   | Should -Be 'written'
            $r.Replaced | Should -Contain 'workbench.colorCustomizations/terminal.background'
            $r.Kept     | Should -Contain 'terminal.integrated.fontFamily'
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) -Path @('terminal.integrated.fontFamily') |
                Should -Be '"Mine Mono"'
        }
    }
}

Describe 'Show-VSCodeWriteResult' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Write-Host { }
            $script:base = @{
                Variant = 'Code'; Path = '/x/Code/User/settings.json'; Kept = @(); Replaced = @()
                Overrides = @(); Backup = $null; FailedPath = '/x/Code/User/settings.json'
                Detail = 'it does not parse as a JSON object'
            }
        }

        It 'says <status> in its own words' -ForEach @(
            @{ status = 'written';        pattern = "Saved to Code's settings\.json" }
            @{ status = 'declined';       pattern = 'as you chose' }
            @{ status = 'undecided';      pattern = 'no answer on record' }
            @{ status = 'unknownvariant'; pattern = 'nothing was saved to its settings\.json' }
            @{ status = 'nodir';          pattern = 'no settings folder' }
            @{ status = 'wontparse';      pattern = 'does not parse' }
            @{ status = 'writefailed';    pattern = 'Could not write' }
            @{ status = 'statecorrupt';   pattern = 'Could not read' }
        ) {
            $r = $script:base.Clone(); $r.Status = $status
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match $pattern }
        }

        It 'never says Saved unless it was written' {
            foreach ($s in 'declined', 'undecided', 'unknownvariant', 'nodir', 'wontparse', 'writefailed', 'statecorrupt') {
                $r = $script:base.Clone(); $r.Status = $s
                Show-VSCodeWriteResult -Result $r
            }
            # -cmatch: -match is case-insensitive, and 'Not saved to' contains 'saved to'.
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -cmatch '\bSaved to' }
        }

        It 'names kept and replaced keys, and an overriding theme block' {
            $r = $script:base.Clone(); $r.Status = 'written'
            $r.Kept = @('terminal.integrated.fontFamily')
            $r.Replaced = @('workbench.colorCustomizations/terminal.background')
            $r.Overrides = @(@{ Scope = '[Monokai]'; Ids = @('terminal.background') })
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Left terminal\.integrated\.fontFamily' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Replaced workbench\.colorCustomizations/terminal\.background' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match '\[Monokai\]' }
        }

        It 'says what a failed rollback means' {
            $r = $script:base.Clone(); $r.Status = 'writefailed'; $r.Detail = 'its undo record could not be restored either'
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'reset may leave' }
        }

        It 'prints nothing for no result' {
            Show-VSCodeWriteResult -Result $null
            Should -Invoke Write-Host -Times 0 -Scope It
        }

        It 'never advises deleting the record file without saying what that costs' {
            $r = $script:base.Clone(); $r.Status = 'statecorrupt'
            Show-VSCodeWriteResult -Result $r
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Fix or delete' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'loses' }
        }
    }
}

Describe 'Reset-StyleVSCodeConfig' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'

            function script:Publish([string]$Name) {
                Publish-StyleVSCodeConfig -StyleName $Name -StyleDir (Get-StyleDir -StyleName $Name) -Kind 'VSCode' | Out-Null
            }
        }

        It 'puts the file back byte for byte, and clears the record' {
            script:Publish 'koholint'
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'still does, after a chain of styles' {
            script:Publish 'koholint'; script:Publish 'eva'; script:Publish 'sober'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'leaves a key you changed since, and names it' {
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $t -Path @('terminal.integrated.fontFamily') -Literal '"Mine Mono"').Text,
                [System.Text.UTF8Encoding]::new($false))
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Kept | Should -Contain 'terminal.integrated.fontFamily'
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) -Path @('terminal.integrated.fontFamily') |
                Should -Be '"Mine Mono"'
        }

        It 'says norecord, and touches nothing, when no style was saved' {
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:sPath)
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'norecord'
            [System.IO.File]::GetLastWriteTimeUtc($script:sPath) | Should -Be $stamp
        }

        It 'keeps the record when the file no longer parses' {
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath, $t.Substring(0, $t.Length - 3), [System.Text.UTF8Encoding]::new($false))
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'wontparse'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty -Because 'a later reset still needs it'
        }

        It 'keeps the record when the file cannot be read' {
            script:Publish 'koholint'
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                $r = Reset-StyleVSCodeConfig -Variant 'Code'
            } finally { $fs.Dispose() }
            $r.Status | Should -Be 'wontparse'
            $r.Detail | Should -Match 'could not be read'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty
        }

        It 'keeps the record when the write fails' {
            script:Publish 'koholint'
            # Pester 6 throws on a call no filter matches (Pester 5 called the
            # real command), so the state write needs a default mock to land on.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'writefailed'
            (Read-VSCodeState).Entries['Code'].record | Should -Not -BeNullOrEmpty
        }

        It 'works from any terminal, off the recorded path' {
            script:Publish 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'refuses to guess when it has to find the editor itself' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            (Reset-StyleVSCodeConfig).Status | Should -Be 'unknownvariant'
        }

        It 'does not bring back a settings.json deleted since' {
            script:Publish 'koholint'
            Remove-Item -LiteralPath $script:sPath -Force
            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::Exists($script:sPath) | Should -BeFalse
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        # Review Focus 1-3.
        It 'returns a CRLF file with its CRLF' {
            $crlf = "{`r`n  // mine`r`n  `"editor.fontSize`": 13`r`n}"
            [System.IO.File]::WriteAllText($script:sPath, $crlf, [System.Text.UTF8Encoding]::new($false))
            script:Publish 'koholint'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $crlf
        }

        It 'keeps a byte-order mark through apply and reset' {
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($true))
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath))
            script:Publish 'koholint'
            $mid = [System.IO.File]::ReadAllBytes($script:sPath)
            ($mid[0] -eq 0xEF -and $mid[1] -eq 0xBB -and $mid[2] -eq 0xBF) | Should -BeTrue -Because 'the apply keeps the BOM'
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath)) | Should -BeExactly $before
        }

        It 'still takes everything out after the file was re-indented' {
            # VS Code's settings UI and Settings Sync both rewrite the file.
            # What the reset compares is each value's text, not its position.
            script:Publish 'koholint'
            $t = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath, ($t -replace "`n  ", "`n    "), [System.Text.UTF8Encoding]::new($false))
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            @($r.Kept).Count | Should -Be 0 -Because 'no value changed, only the whitespace around it'
            $after = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $after -Path @('workbench.colorCustomizations') | Should -BeNullOrEmpty
            Get-JsoncValueLiteral -Text $after -Path @('terminal.integrated.fontFamily') | Should -BeNullOrEmpty
            Get-JsoncValueLiteral -Text $after -Path @('editor.fontSize') | Should -Be '13'
        }

        It 'says so when the record cannot be cleared' {
            script:Publish 'koholint'
            Mock Set-VSCodeStateEntry { throw 'Could not write state: read-only' }
            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Status | Should -Be 'reset' -Because 'the file itself was put back'
            $r.Detail | Should -Match 'record could not be cleared'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'round-trips a file that already has a colour block, through the state file' {
            # The shape most at risk on Windows PowerShell 5.1: the apply creates
            # no parent, so CreatedParents is EMPTY, and an empty list is what a
            # JSON round trip is least careful with. Coming back naming the
            # block would let a reset take the user's own colour block with it.
            $own = "{`n  `"workbench.colorCustomizations`": {`n    // mine`n    `"editor.background`": `"#202020`"`n  },`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $own, [System.Text.UTF8Encoding]::new($false))
            $a = Invoke-VSCodeStyleApply -Text $own -StyleDir $script:koholint -StyleName 'koholint'
            @($a.Record.CreatedParents).Count | Should -Be 0 -Because 'the colour block was already there'

            script:Publish 'koholint'
            $back = (Read-VSCodeState).Entries['Code'].record
            $back.Style | Should -Be 'koholint'
            @($back.CreatedParents).Count | Should -Be 0 -Because 'an empty list has to come back empty'

            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $own
        }

        It 'takes out a style deleted since, from its record alone' {
            # tstyles delete moves the style away; a reset afterwards has the
            # record and nothing else, which is all it needs.
            $mine = Join-Path $script:TStylesDataRoot 'styles/mine'
            New-Item -ItemType Directory -Path $mine -Force | Out-Null
            Copy-Item -Path (Join-Path $script:koholint '*') -Destination $mine -Recurse
            script:Publish 'mine'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'mine'
            Remove-Item -LiteralPath $mine -Recurse -Force
            Get-StyleDir -StyleName 'mine' | Should -BeNullOrEmpty -Because 'the style is gone'

            (Reset-StyleVSCodeConfig -Variant 'Code').Status | Should -Be 'reset'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }
    }
}

Describe 'Show-VSCodeResetResult' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host { } }

        It 'says <status> in its own words' -ForEach @(
            @{ status = 'reset';          pattern = "Took the style back out of Code's settings\.json" }
            @{ status = 'unknownvariant'; pattern = "Couldn't tell which editor" }
            @{ status = 'statecorrupt';   pattern = 'Could not read' }
            @{ status = 'wontparse';      pattern = 'Could not edit .* safely: it could not be read' }
            @{ status = 'writefailed';    pattern = 'Could not write' }
        ) {
            Show-VSCodeResetResult -Result @{ Status = $status; Variant = 'Code'; Path = '/x/settings.json'
                                              Kept = @(); Restored = @(); Removed = @('x'); Detail = 'it could not be read' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match $pattern }
        }

        It 'does not say it took the style out when the reset found none of it (<label>)' -ForEach @(
            # Missing members as well as empty ones: @() around a missing member
            # is one $null, whose Count of 1 would claim a key was taken out.
            @{ label = 'empty lists';     result = @{ Status = 'reset'; Variant = 'Code'; Path = '/x'; Kept = @(); Restored = @(); Removed = @() } }
            @{ label = 'missing members'; result = @{ Status = 'reset'; Variant = 'Code'; Path = '/x' } }
        ) {
            Show-VSCodeResetResult -Result $result
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Took the style back out' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match "Found none of the style left in Code's settings\.json to take out" }
        }

        It 'stays quiet when there was nothing of ours to take out' {
            Show-VSCodeResetResult -Result @{ Status = 'norecord'; Variant = 'Code'; Path = $null
                                              Kept = @(); Restored = @(); Removed = @() }
            Should -Invoke Write-Host -Times 0 -Scope It
        }

        It 'names a key it left' {
            Show-VSCodeResetResult -Result @{ Status = 'reset'; Variant = 'Code'; Path = '/x'
                                              Kept = @('terminal.integrated.fontFamily'); Restored = @(); Removed = @() }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Left terminal\.integrated\.fontFamily' }
        }

        It 'says what an uncleared record means' {
            Show-VSCodeResetResult -Result @{ Status = 'reset'; Variant = 'Code'; Path = '/x'; Kept = @(); Restored = @(); Removed = @(); Detail = 'its record could not be cleared' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'wrongly call some of your settings hand edits' }
        }

        It 'never advises deleting the record file without saying what that costs' {
            Show-VSCodeResetResult -Result @{ Status = 'statecorrupt'; Variant = 'Code'; Path = '/x'; Kept = @(); Restored = @(); Removed = @(); Detail = $null }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Fix or delete' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'no record to take it out by' }
        }
    }
}

Describe 'what VS Code claims, and the notice that reads it' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Get-StyleBundledBackground { $null }
            $script:theme = [pscustomobject]@{
                font = [pscustomobject]@{ face = 'Cascadia Code'; size = 11 }; cursorShape = 'bar'
            }
        }

        It 'names font and cursor shape while the writer is off' {
            Mock Test-VSCodeWriterActive { $false }
            $f = Get-UnsupportedStyleField -Theme $script:theme -StyleDir $TestDrive -Kind 'VSCode'
            $f | Should -Contain 'font'
            $f | Should -Contain 'cursor shape'
        }

        It 'names neither once it is on' {
            Mock Test-VSCodeWriterActive { $true }
            $f = @(Get-UnsupportedStyleField -Theme $script:theme -StyleDir $TestDrive -Kind 'VSCode')
            $f | Should -Not -Contain 'font'
            $f | Should -Not -Contain 'cursor shape'
        }

        It 'still names a cursor shape VS Code has no answer for' {
            Mock Test-VSCodeWriterActive { $true }
            $odd = [pscustomobject]@{ cursorShape = 'doubleUnderscore' }
            Get-UnsupportedStyleField -Theme $odd -StyleDir $TestDrive -Kind 'VSCode' | Should -Contain 'cursor shape'
        }

        It 'never claims what settings.json cannot carry, even when on' {
            Mock Test-VSCodeWriterActive { $true }
            $caps = Get-TerminalCapability -Kind 'VSCode'
            $caps.Persist     | Should -BeTrue
            $caps.Font        | Should -BeTrue
            $caps.CursorShape | Should -BeTrue
            foreach ($n in 'Opacity', 'BackgroundImage', 'Padding', 'TabColor', 'TabTitle') {
                $caps[$n] | Should -BeFalse -Because "VS Code has no setting that delivers $n"
            }
        }
    }
}

Describe 'tstyles font in a VS Code terminal' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:cat = @([pscustomobject]@{
                name = 'JetBrains Mono'; family = 'JetBrains Mono'; license = 'OFL-1.1'
                url = 'https://example.invalid/x.zip'; sha256 = 'deadbeef' })
            Mock Get-FontCatalog     { $script:cat }
            Mock Test-FontInstalled  { $true }
            Mock Find-WTSettingsPath { $null }
            Mock Get-TerminalKind    { 'VSCode' }
        }

        It 'says the style owns the font once the writer is on, and gives no WezTerm advice' {
            Mock Test-VSCodeWriterActive { $true }
            Get-FontOwner -Kind 'VSCode' | Should -Be 'style'
            $out = Invoke-TerminalStyleFont -Name 'JetBrains Mono' 6>&1 | Out-String
            $out | Should -Match 'tstyles tune'
            $out | Should -Not -Match 'config\.font' -Because 'that route exists on WezTerm only'
        }

        It 'leaves the font to VS Code while the writer is off' {
            Mock Test-VSCodeWriterActive { $false }
            Get-FontOwner -Kind 'VSCode' | Should -Be 'terminal'
        }
    }
}

Describe 'tstyles <name> and tstyles reset in a VS Code terminal' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'

            Mock Get-TerminalKind { 'VSCode' }
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-HostOscPacket { $true }
            Mock Get-StyleBundledBackground { $null }
            Mock Write-Host { }
            # Nobody at the console, and nothing answered: a test that needs
            # another answer overrides these. Without them a run from a real
            # terminal could reach the real prompt.
            Mock Test-InteractiveConsole { $false }
            Mock Confirm-Action { throw 'mocked, never answered' }
        }

        It 'asks nobody about a style that has no scheme.json' {
            # The apply stops on the missing scheme, so a question asked first
            # would be answered for nothing -- and a yes stored for good.
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            $broken = Join-Path $script:TStylesDataRoot 'styles/noscheme'
            New-Item -ItemType Directory -Path $broken -Force | Out-Null
            # -ErrorAction, not 2>&1: CI's pwsh and powershell steps run with
            # $ErrorActionPreference = 'Stop', which makes the Write-Error throw.
            Apply-StyleNonWT -StyleName 'noscheme' -StyleDir $broken -KeepPrompt -ErrorVariable err -ErrorAction SilentlyContinue
            "$err" | Should -Match 'has no scheme\.json'
            Should -Invoke Confirm-Action -Times 0 -Scope It
            [System.IO.File]::Exists((Get-VSCodeStatePath)) | Should -BeFalse -Because 'no answer was asked for, so none was stored'
        }

        It 'asks once, and asks before the notice is built' {
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) `
                -Path @('workbench.colorCustomizations', 'terminal.background') | Should -Not -BeNullOrEmpty
            # Had the question come after the notice, the notice would have
            # named the font this very apply then wrote.
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match "can't show:.*\bfont\b" }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'says Saved, once' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Should -Invoke Write-Host -Times 1 -Exactly -Scope It -ParameterFilter { "$Object" -match "Saved to Code's settings\.json" }
        }

        It 'writes nothing, and says why, when nobody is there to ask' {
            Mock Test-InteractiveConsole { $false }
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'no answer on record' }
        }

        It 'tstyles reset takes it back out, byte for byte' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            Reset-StyleNonWT -OutputRedirected $false
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match "Took the style back out of Code's settings\.json" }
        }

        It 'a reset in another terminal leaves VS Code alone' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Apply-StyleNonWT -StyleName 'koholint' -StyleDir $script:koholint -KeepPrompt
            $styled = [System.IO.File]::ReadAllText($script:sPath)
            Mock Get-TerminalKind { 'AppleTerminal' }
            Reset-StyleNonWT -OutputRedirected $false
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $styled
        }

        It 'the reset help no longer says there is no settings file off Windows Terminal' {
            $reset = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'reset' })
            ($reset.Detail -join ' ') | Should -Match 'VS Code'
        }
    }
}

Describe 'the picker''s VS Code preview session' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            $script:eva      = Get-StyleDir -StyleName 'eva'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
            Mock Write-Host { }
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
        }

        It 'is $null while the writer is off, so the picker stays colors-only' {
            Set-VSCodeStateEntry -Variant 'Code' -Consent 'no'
            New-VSCodePreviewSession | Should -BeNullOrEmpty
        }

        It 'gives no session for a file it cannot read, so nothing is previewed over it' {
            $fs = [System.IO.File]::Open($script:sPath, 'Open', 'ReadWrite', 'None')
            try {
                New-VSCodePreviewSession | Should -BeNullOrEmpty
            } finally { $fs.Dispose() }
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'gives no session for a file that does not parse, and leaves it as it was' {
            # The root object never closes, so a preview would splice against
            # offsets that mean nothing. Enter still reaches the publisher,
            # which says why it wrote nothing.
            [System.IO.File]::WriteAllText($script:sPath, '{ "broken": ', [System.Text.UTF8Encoding]::new($false))
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath))
            New-VSCodePreviewSession | Should -BeNullOrEmpty
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath)) | Should -BeExactly $before
        }

        It 'asks first when nobody has been asked' {
            Remove-Item -LiteralPath (Get-VSCodeStatePath) -Force
            Mock Test-InteractiveConsole { $true }
            Mock Confirm-Action { $true }
            New-VSCodePreviewSession | Should -Not -BeNullOrEmpty
            Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It
        }

        It 'previews from the original every time, never from the last preview' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
        }

        It 'records each preview before it writes it, so the record names what the file holds' {
            # Order, not just outcome: the record has to be on file at the moment
            # the preview lands, or a picker killed between the two leaves a
            # style no record names. Pester 6 throws on a call no filter
            # matches, so the state write needs a default mock to land on.
            $script:atWrite = 'never written'
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:atWrite = (Read-VSCodeState).Entries['Code'].record.Style
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:sPath }
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'
            $script:atWrite | Should -Be 'koholint' -Because 'the record lands before the file it describes'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the record names what the file holds'
        }

        It 'a picker that dies mid-preview leaves nothing reset cannot take out (<label>)' -ForEach @(
            @{ label = 'no style on'; start = $null }
            @{ label = 'koholint on'; start = 'koholint' }
        ) {
            if ($start) {
                Publish-StyleVSCodeConfig -StyleName $start -StyleDir (Get-StyleDir -StyleName $start) -Kind 'VSCode' | Out-Null
            }
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            # The terminal closes here. Closing the tab, Kill Terminal and
            # quitting VS Code all end pwsh on SIGHUP, so neither Esc nor the
            # picker's finally runs: the session is simply abandoned.
            $s = $null

            $r = Reset-StyleVSCodeConfig -Variant 'Code'
            $r.Status | Should -Be 'reset' -Because 'norecord would leave the preview in the file with nothing to take it out by'
            @($r.Kept).Count | Should -Be 0 -Because 'nothing in the file was changed by hand'
            Show-VSCodeResetResult -Result $r
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match '\bLeft\b' }
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'a preview whose file write fails puts the record back' {
            $s = New-VSCodePreviewSession
            # The record at the moment the write fails shows it had moved, so the
            # empty record afterwards is a rollback and not a record never saved.
            $script:atWrite = 'never written'
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:atWrite = (Read-VSCodeState).Entries['Code'].record.Style
                throw 'locked'
            } -ParameterFilter { $Path -eq $script:sPath }
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'failed'
            $script:atWrite | Should -Be 'koholint' -Because 'the record goes first'
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty -Because 'the file never got the preview'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'writes no preview whose record cannot be saved' {
            $s = New-VSCodePreviewSession
            Mock Set-VSCodeStateEntry { throw 'read-only data root' }
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'failed'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user -Because 'a preview no record names is what a closed terminal would strand'
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none' -Because 'nothing was written, so Esc has nothing to take out'
        }

        It 'Esc puts the starting record back (<label>)' -ForEach @(
            @{ label = 'no style on'; start = $null }
            @{ label = 'koholint on'; start = 'koholint' }
        ) {
            if ($start) {
                Publish-StyleVSCodeConfig -StyleName $start -StyleDir (Get-StyleDir -StyleName $start) -Kind 'VSCode' | Out-Null
            }
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'eva' -Because 'the preview is what the file holds'

            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            $back = (Read-VSCodeState).Entries['Code'].record
            if ($start) {
                $back.Style | Should -Be $start -Because 'the file holds the starting style again'
            } else {
                $back | Should -BeNullOrEmpty -Because 'no style was on when the picker opened'
            }
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'Esc with no style on puts the file back before it clears the record' {
            # A terminal closed between the two writes must leave a record that
            # names what the file holds. Cleared first, it would strand the
            # preview with no record at all.
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            $script:atWrite = 'never written'
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:atWrite = (Read-VSCodeState).Entries['Code'].record.Style
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:sPath }
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            $script:atWrite | Should -Be 'eva' -Because 'the record is cleared only once the original is back'
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'Esc removes a settings.json the picker created before it clears the record' {
            Remove-Item -LiteralPath $script:sPath -Force
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            $script:atRemove = 'never removed'
            Mock Remove-Item { }
            Mock Remove-Item {
                $script:atRemove = (Read-VSCodeState).Entries['Code'].record.Style
                [System.IO.File]::Delete($LiteralPath[0])
            } -ParameterFilter { $LiteralPath -eq $script:sPath }
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            $script:atRemove | Should -Be 'eva' -Because 'the record is cleared only once the file is gone'
            [System.IO.File]::Exists($script:sPath) | Should -BeFalse
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'Esc with no style on says so when the file is back but the record could not be cleared' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            Mock Write-VSCodeState { throw 'state locked' }
            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'restored' -Because 'the file is back exactly as it was'
            $r.Detail | Should -Be 'its record could not be cleared'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'a second Esc after a record that could not be cleared finds nothing to do' {
            # The record left names keys the file no longer holds -- the harmless
            # kind -- so a second call has nothing to put right, and nothing it
            # may say never reached the file.
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            Mock Write-VSCodeState { throw 'state locked' }
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none'
        }

        It 'Esc puts the record right after a preview whose write and rollback both failed' {
            $s = New-VSCodePreviewSession
            $script:statePath = Get-VSCodeStatePath
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            Mock Write-SettingsAtomic {
                # The preview's record lands; putting it back after the failed
                # settings write does not.
                $script:stateWrites++
                if ($script:stateWrites -eq 2) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'failed'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'eva' -Because 'the record went first and could not be put back'

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'none' -Because 'nothing of the picker''s reached settings.json'
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty -Because 'the record names what the file holds again'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'Esc says so when it cannot put that record right either' {
            $s = New-VSCodePreviewSession
            $script:statePath = Get-VSCodeStatePath
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            Mock Write-SettingsAtomic {
                $script:stateWrites++
                if ($script:stateWrites -ge 2) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'failed'

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'recordstale'
            $r.Reason | Should -Match 'state locked'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'eva'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user -Because 'settings.json never got the preview'
        }

        It 'Esc after an outside edit, with no style on, puts the file back before it clears the record' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'written'
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('editor.fontSize') -Literal '15').Text,
                [System.Text.UTF8Encoding]::new($false))
            $script:atWrite = 'never written'
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:atWrite = (Read-VSCodeState).Entries['Code'].record.Style
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:sPath }
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'merged'
            $script:atWrite | Should -Be 'eva' -Because 'with no style to put back, the record is cleared only once the preview is out'
            (Read-VSCodeState).Entries['Code'].record | Should -BeNullOrEmpty
        }

        It 'a failed Esc after a preview that failed twice leaves a record reset can use' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'
            $script:statePath = Get-VSCodeStatePath
            $script:locked = $true
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                if ($script:locked) { throw 'locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:sPath }
            Mock Write-SettingsAtomic {
                # The eva preview's record lands, its rollback does not; later
                # state writes work.
                $script:stateWrites++
                if ($script:stateWrites -eq 2) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'failed'

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeNullOrEmpty -Because 'the message promises the reset'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the file still holds the koholint preview'
            # The lock goes away, and the user runs the reset the message offered.
            $script:locked = $false
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'a failed Esc after a commit that failed twice leaves a record reset can use' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'
            $script:statePath = Get-VSCodeStatePath
            $script:locked = $true
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                if ($script:locked) { throw 'locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:sPath }
            Mock Write-SettingsAtomic {
                # The commit's record lands, its rollback does not; later state
                # writes work.
                $script:stateWrites++
                if ($script:stateWrites -eq 2) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            (Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s).Status | Should -Be 'writefailed'

            # The picker follows a commit that did not land with Esc's restore.
            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeNullOrEmpty -Because 'the message promises the reset'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the file still holds the koholint preview'
            $script:locked = $false
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'a commit that fails after such a preview rolls back to the record the file matches' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $s = New-VSCodePreviewSession
            $script:statePath = Get-VSCodeStatePath
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }
            Mock Write-SettingsAtomic {
                $script:stateWrites++
                if ($script:stateWrites -eq 2) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'failed'

            # Enter on eva, and the commit's own settings write fails too.
            (Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s).Status | Should -Be 'writefailed'
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'koholint is what the file still holds'
        }

        It 'Esc puts the exact bytes back, BOM included' {
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($true))
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath))
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:sPath)) | Should -BeExactly $before
        }

        It 'Esc removes a settings.json the picker created' {
            Remove-Item -LiteralPath $script:sPath -Force
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            [System.IO.File]::Exists($script:sPath) | Should -BeTrue
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            [System.IO.File]::Exists($script:sPath) | Should -BeFalse
        }

        # Review Focus 5.
        It 'Esc with nothing previewed writes nothing' {
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:sPath)
            $s = New-VSCodePreviewSession
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none'
            [System.IO.File]::GetLastWriteTimeUtc($script:sPath) | Should -Be $stamp
        }

        It 'a second Esc finds nothing to do' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'restored'
            (Restore-VSCodePreview -Session $s).Status | Should -Be 'none'
        }

        It 'Esc after an edit keeps the edit and puts the starting style back' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $start = [System.IO.File]::ReadAllText($script:sPath)
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null

            # Somebody edits settings.json in VS Code while the picker is open.
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('editor.fontSize') -Literal '15').Text,
                [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'merged'
            $text = [System.IO.File]::ReadAllText($script:sPath)
            Get-JsoncValueLiteral -Text $text -Path @('editor.fontSize') | Should -Be '15' -Because 'the edit is theirs'
            # eva writes fontWeight 600 and koholint "normal": which one is in
            # the file says which style came back.
            Get-JsoncValueLiteral -Text $text -Path @('terminal.integrated.fontWeight') |
                Should -Be (Get-JsoncValueLiteral -Text $start -Path @('terminal.integrated.fontWeight'))
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'

            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Set-JsoncLiteral -Text $script:user -Path @('editor.fontSize') -Literal '15').Text
        }

        It 'Esc names a key the starting style sets again as replaced, not left' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null

            # The edit is to a key both styles write (eva 600, koholint "normal").
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('terminal.integrated.fontWeight') -Literal '"bold"').Text,
                [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'merged'
            @($r.Replaced) | Should -Contain 'terminal.integrated.fontWeight'
            @($r.Kept) | Should -Not -Contain 'terminal.integrated.fontWeight'
        }

        It 'Esc over an edit to a key the starting style sets again, and tstyles reset then puts the edit back' {
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null

            # The edit is to a key both styles write (eva 600, koholint "normal").
            $now = [System.IO.File]::ReadAllText($script:sPath)
            [System.IO.File]::WriteAllText($script:sPath,
                (Set-JsoncLiteral -Text $now -Path @('terminal.integrated.fontWeight') -Literal '"bold"').Text,
                [System.Text.UTF8Encoding]::new($false))

            (Restore-VSCodePreview -Session $s).Status | Should -Be 'merged'

            # Esc wrote the starting style's value over that key, and the message
            # says tstyles reset puts the edit back. It can only if the record Esc
            # saved remembers the edit as the value that was there before.
            $reset = Reset-StyleVSCodeConfig -Variant 'Code'
            $reset.Status | Should -Be 'reset' -Because 'norecord would mean Esc left nothing for the reset to work from'
            Get-JsoncValueLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) -Path @('terminal.integrated.fontWeight') |
                Should -BeExactly '"bold"' -Because 'the edit is theirs, and tstyles reset is what puts it back'
        }

        It 'Esc will not undo into a file that no longer parses, and keeps the preview''s record' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null

            # Saved half-way through an edit: the root object never closes.
            $broken = ([System.IO.File]::ReadAllText($script:sPath)).TrimEnd().TrimEnd('}')
            [System.IO.File]::WriteAllText($script:sPath, $broken, [System.Text.UTF8Encoding]::new($false))

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match 'no longer parses'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $broken
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint' -Because 'the preview is what the file still holds'
        }

        It 'Esc that cannot write keeps the preview''s record, so reset can take it out' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            # Pester 6 throws on a call no filter matches, so the default mock
            # lets the state file's own write through.
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match 'locked'
            $r.Detail | Should -BeNullOrEmpty
            (Read-VSCodeState).Entries['Code'].record.Style | Should -Be 'koholint'
        }

        It 'Esc says so when the preview''s record cannot be put back either' {
            # With a style on before the picker, Esc moves the record before the
            # file, so this double fault exists. With none, the file goes first
            # and a failed write leaves the preview's record where it was.
            Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' | Out-Null
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            # A counting mock, so the double fault is still reached: the starting
            # record lands, the settings write fails, and putting the preview's
            # record back fails too.
            $script:stateWrites = 0
            Mock Write-SettingsAtomic {
                $script:stateWrites++
                if ($script:stateWrites -gt 1) { throw 'disk full' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:sPath }

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -Be 'its undo record could not be saved either'
            $script:stateWrites | Should -Be 2 -Because 'the starting record landed, and putting the preview''s back is what failed'
        }

        It 'Esc that cannot even move the record still leaves one reset can use' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            # Nothing can be written at all: not the starting record, not the file.
            Mock Write-SettingsAtomic { throw 'locked' }

            $r = Restore-VSCodePreview -Session $s
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeNullOrEmpty -Because 'the preview''s own record is still the one on file, so the message may promise the reset'
            $left = (Read-VSCodeState).Entries['Code'].record
            $left.Style | Should -Be 'koholint'
            (Invoke-VSCodeStyleReset -Text ([System.IO.File]::ReadAllText($script:sPath)) -Record $left).Text |
                Should -BeExactly $script:user -Because 'that record is one a reset takes the preview out by'
        }

        It 'stops previewing into a file somebody else changed, and Esc keeps the edit' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Should -Be 'written'

            # Somebody edits settings.json in VS Code while the picker is open.
            $edited = (Set-JsoncLiteral -Text ([System.IO.File]::ReadAllText($script:sPath)) `
                           -Path @('editor.fontSize') -Literal '15').Text
            [System.IO.File]::WriteAllText($script:sPath, $edited, [System.Text.UTF8Encoding]::new($false))

            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Should -Be 'changed'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $edited

            (Restore-VSCodePreview -Session $s).Status | Should -Be 'merged'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Set-JsoncLiteral -Text $script:user -Path @('editor.fontSize') -Literal '15').Text
        }

        It 'Enter commits what is on disk, with a record that undoes it to the original' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            Invoke-VSCodePreview -Session $s -StyleName 'eva' -StyleDir $script:eva | Out-Null
            $r = Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s
            $r.Status | Should -Be 'written'
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
            Reset-StyleVSCodeConfig -Variant 'Code' | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        # Review Focus 5.
        It 'Enter with nothing previewed is a plain apply' {
            $s = New-VSCodePreviewSession
            Publish-StyleVSCodeConfig -StyleName 'eva' -StyleDir $script:eva -Kind 'VSCode' -Session $s | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) |
                Should -BeExactly (Invoke-VSCodeStyleApply -Text $script:user -StyleDir $script:eva -StyleName 'eva').Text
        }

        It 'reports the first-touch copy it took during the preview' {
            $s = New-VSCodePreviewSession
            Invoke-VSCodePreview -Session $s -StyleName 'koholint' -StyleDir $script:koholint | Out-Null
            $r = Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' -Session $s
            $r.Backup | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($r.Backup) | Should -BeExactly $script:user
        }
    }
}

Describe 'Show-VSCodeRestoreResult' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host { } }

        It 'says the edit survived when it merged' {
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Your edit is still there' }
        }

        It 'names a key the starting style set again, and does not call that edit still there' {
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x'; Kept = @(); Replaced = @('terminal.integrated.fontWeight'); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Replaced terminal\.integrated\.fontWeight' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Your edit is still there' }
        }

        It 'says the edit survived, and names no key, when the result carries no Kept or Replaced' {
            # A missing member, not an empty one: @() around a missing member is
            # one $null, which would print a line naming nothing.
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Your edit is still there' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'Replaced|Left' }
        }

        It 'says how to get out when it failed' {
            Show-VSCodeRestoreResult -Result @{ Status = 'failed'; Path = '/x'; Kept = @(); Replaced = @(); Reason = 'locked'; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'tstyles reset takes it out' }
        }

        It 'does not promise a reset that has no record to work from' {
            Show-VSCodeRestoreResult -Result @{ Status = 'failed'; Path = '/x'; Kept = @(); Replaced = @(); Reason = 'locked'; Detail = 'its undo record could not be saved either' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'tstyles reset cannot take it out' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'tstyles reset takes it out' }
        }

        It 'says when it merged but the record could not be cleared' {
            Show-VSCodeRestoreResult -Result @{ Status = 'merged'; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = 'its record could not be cleared' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'But its record could not be cleared' }
        }

        It 'says when the file is back but its record could not be cleared' {
            Show-VSCodeRestoreResult -Result @{ Status = 'restored'; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = 'its record could not be cleared' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'back as it was, but its record could not be cleared' }
        }

        It 'says when the record names a preview that never reached the file' {
            Show-VSCodeRestoreResult -Result @{ Status = 'recordstale'; Path = '/x'; Kept = @(); Replaced = @(); Reason = 'Could not write /s/vscode-state.json: state locked'; Detail = $null }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'never reached it' }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { "$Object" -match 'preview is still in it' } -Because 'nothing of the picker''s is in settings.json'
        }

        It 'stays quiet for <status>' -ForEach @(@{ status = 'none' }, @{ status = 'restored' }) {
            Show-VSCodeRestoreResult -Result @{ Status = $status; Path = '/x'; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
            Should -Invoke Write-Host -Times 0 -Scope It
        }
    }
}

Describe 'the picker wires the VS Code session in' {
    InModuleScope TerminalStyles {
        BeforeAll { $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() }

        It 'previews beside WezTerm, on the branch with no settings.json of its own' {
            $script:picker | Should -Match '& \$previewWezTerm \$i\s+& \$previewVSCode \$i'
        }

        It 'reverts through the one revert block Esc and the finally share' {
            $script:picker | Should -Match '(?s)\$restoreOriginalLook = \{\s*& \$restoreOriginalSettings\s*& \$restoreWezTerm\s*& \$restoreVSCode'
        }

        It 'opens the session below the console guard, so nobody is asked into a pipe' {
            $guard = $script:picker.IndexOf('The style picker needs an interactive terminal')
            $open  = $script:picker.IndexOf('$vscodeSession = New-VSCodePreviewSession')
            $guard | Should -BeGreaterThan 0
            $open  | Should -BeGreaterThan $guard
        }

        It 'commits with the session, and shows the result below the Clear-Host' {
            $publish = $script:picker.IndexOf('Publish-StyleVSCodeConfig')
            $publish | Should -BeGreaterThan 0
            $script:picker | Should -Match '-Session \$vscodeSession'
            $clear = $script:picker.IndexOf('Clear-Host', $publish)
            $show  = $script:picker.IndexOf('Show-VSCodeWriteResult -Result $vscodeResult')
            $clear | Should -BeGreaterThan $publish
            $show  | Should -BeGreaterThan $clear
        }

        It 'says what Esc did after it says Reverted' {
            $script:picker | Should -Match '(?s)Write-Host "Reverted\." -ForegroundColor Yellow\s*Show-VSCodeRestoreResult'
        }

        It 'takes the preview back out when an error after Enter skips the commit' {
            $publish = $script:picker.IndexOf('$vscodeResult = Publish-StyleVSCodeConfig')
            $done    = $script:picker.IndexOf('$pickerState.VSCodeDone = $true')
            $publish | Should -BeGreaterThan 0
            $done | Should -BeGreaterThan $publish -Because 'the session is settled only once the commit has run'
            $script:picker | Should -Match '(?s)if \(\$confirmed -and \$vscodeSession -and -not \$pickerState\.VSCodeDone\) \{\s*\$pickerState\.VSCodeRestore = Restore-VSCodePreview -Session \$vscodeSession'
        }

        # The six above pin WHERE the wiring sits. These four pin lines whose loss
        # changes what is left on disk, each found by deleting that line in a copy
        # of the picker and watching the six stay green. Text pins, like the six:
        # what the session does is pinned in the preview-session tests above.
        It 'puts the file back when the commit did not land' {
            $script:picker | Should -Match '(?s)if \(\$vscodeSession -and \$vscodeResult -and \$vscodeResult\.Status -ne ''written''\) \{[^}]*Restore-VSCodePreview -Session \$vscodeSession' `
                -Because 'a failed commit leaves the uncommitted preview in the file, and its record on file; only this Restore puts both back as the picker found them'
        }

        It 'commits through the session, so the preview is undone by its own record' {
            $script:picker | Should -Match '(?s)\$vscodeResult = Publish-StyleVSCodeConfig[^{]*?-Session \$vscodeSession' `
                -Because 'without the session the publisher undoes the style that was on when the picker opened, not the preview on disk, and a later reset leaves the preview in the file'
        }

        It 'says what putting the file back did, below the commit result' {
            $script:picker | Should -Match '(?s)Show-VSCodeWriteResult -Result \$vscodeResult\s*Show-VSCodeRestoreResult -Result \$pickerState\.VSCodeRestore' `
                -Because 'when the commit failed after a preview, what putting the file back did is told right after the commit result, below the Clear-Host'
        }

        It 'says what Ctrl+C put back' {
            $script:picker | Should -Match '(?s)try \{ & \$restoreOriginalLook \} catch \{ \}\s*Show-VSCodeRestoreResult' `
                -Because 'Ctrl+C and errors leave through the finally, which would otherwise say nothing about a merged or failed restore'
        }
    }
}

Describe 'every door that calls the WezTerm publisher calls the VS Code one too' {
    # The duplication guard tests/WezTerm-Writer.Tests.ps1 keeps for its own
    # publishers, carried to the fourth writer. Not a list of doors: any
    # function that calls Publish-StyleWezTermConfig is one, so a door added
    # later is held to this without editing it. Read off the AST, so a comment
    # that names a publisher is not a call to it.
    BeforeAll {
        $repo = Split-Path $PSScriptRoot -Parent
        $files = @((Join-Path $repo 'tstyles.ps1'), (Join-Path $repo 'terminals.ps1')) +
                 @(Get-ChildItem -Path (Join-Path $repo 'lib') -Filter '*.ps1' | ForEach-Object { $_.FullName })
        $script:doors = @{}
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
            $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $fns) {
                $calls = @($fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                           ForEach-Object { $_.GetCommandName() })
                if ($calls -contains 'Publish-StyleWezTermConfig') { $script:doors[$fn.Name] = $calls }
            }
        }
    }

    It 'finds the two doors it knows of, so the check below has something to check' {
        $script:doors.Keys | Should -Contain 'Apply-StyleNonWT'
        $script:doors.Keys | Should -Contain 'Invoke-TerminalStyle' -Because 'the picker is the other door'
    }

    It 'has every one of them call Publish-StyleVSCodeConfig' {
        foreach ($name in @($script:doors.Keys)) {
            $script:doors[$name] | Should -Contain 'Publish-StyleVSCodeConfig' -Because "$name publishes to WezTerm, so it has to publish to VS Code too"
        }
    }
}

Describe 'tstyles vscode' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:sPath = Join-Path $script:TStylesDataRoot 'Code/User/settings.json'
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($script:sPath)) -Force | Out-Null
            $script:user = "{`n  // mine`n  `"editor.fontSize`": 13`n}"
            [System.IO.File]::WriteAllText($script:sPath, $script:user, [System.Text.UTF8Encoding]::new($false))
            $script:koholint = Get-StyleDir -StyleName 'koholint'
            Mock Resolve-VSCodeTarget { @{ Status = 'ok'; Variant = 'Code'; Path = $script:sPath } }
        }

        It 'is dispatched, with its action' {
            Mock Invoke-TerminalStyleVSCode { }
            Invoke-TerminalStyle -Arg 'vscode' -SubArg 'off'
            Should -Invoke Invoke-TerminalStyleVSCode -Times 1 -Exactly -Scope It -ParameterFilter { $Action -eq 'off' }
        }

        It 'is a reserved word, so no style can shadow it' {
            $script:TStylesSubcommands | Should -Contain 'vscode'
        }

        It 'has a help topic' {
            (Get-TerminalStyleHelpData).Name | Should -Contain 'vscode'
        }

        It 'on records a yes and writes nothing' {
            $out = Invoke-TerminalStyleVSCode -Action 'on' 6>&1 | Out-String
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            $out | Should -Match 'Nothing was written now'
        }

        It 'off does not warn about a record its own write has cleared' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            # The real reset takes the style out but cannot clear its record --
            # the first state write fails -- and off's own save, the next one,
            # lands.
            $script:statePath = Get-VSCodeStatePath
            $script:stateWrites = 0
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:stateWrites++
                if ($script:stateWrites -eq 1) { throw 'state locked' }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:statePath }
            $out = Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-String -Width 500
            $out | Should -Match 'Took the style back out'
            $out | Should -Not -Match 'wrongly call' -Because 'the no was saved with the record cleared, so that warning would be false'
            $e = (Read-VSCodeState).Entries['Code']
            $e.consent | Should -Be 'no'
            $e.record | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
        }

        It 'off keeps that warning when its own write fails too' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $script:statePath = Get-VSCodeStatePath
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'state locked' } -ParameterFilter { $Path -eq $script:statePath }
            $out = Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-String -Width 500
            $out | Should -Match 'wrongly call' -Because 'the record was not cleared after all'
        }

        It 'off takes the saved style out, then records a no' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            $e = (Read-VSCodeState).Entries['Code']
            $e.consent | Should -Be 'no'
            $e.record  | Should -BeNullOrEmpty
        }

        It 'off leaves saving on when the style could not be taken out first' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            [System.IO.File]::WriteAllText($script:sPath, '{ "broken": ', [System.Text.UTF8Encoding]::new($false))
            $out = Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-String
            (Read-VSCodeState).Entries['Code'].consent | Should -Be 'yes'
            $out | Should -Match 'Saving was not changed; the style has to come out of settings\.json first'
        }

        It 'off clears a record the reset could not, when it records the no' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            # The reset's own clearing write fails once; the no written after it lands.
            $script:stateWrites = 0
            Mock Write-SettingsAtomic {
                if ($Path -ne $script:sPath) {
                    $script:stateWrites++
                    if ($script:stateWrites -eq 1) { throw 'busy' }
                }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            }
            Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-Null
            [System.IO.File]::ReadAllText($script:sPath) | Should -BeExactly $script:user
            $e = (Read-VSCodeState).Entries['Code']
            $e.consent | Should -Be 'no'
            $e.record  | Should -BeNullOrEmpty -Because 'the style is out of the file, so no record may still name it'
        }

        It 'off says saving is still on only when it was, if the no cannot be saved (<label>)' -ForEach @(
            @{ label = 'saving on';   consent = 'yes'; still = $true }
            @{ label = 'never asked'; consent = $null; still = $false }
        ) {
            if ($consent) { Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent $consent }
            Mock Write-SettingsAtomic { throw 'read-only data root' }
            # -Width: Windows PowerShell 5.1 wraps at the host width, and the
            # state path in this line is long enough to split the sentence.
            $out = Invoke-TerminalStyleVSCode -Action 'off' 6>&1 | Out-String -Width 500
            $out | Should -Match 'Could not save that to'
            if ($still) {
                $out | Should -Match 'so saving is still on'
            } else {
                $out | Should -Not -Match 'still on' -Because 'saving was never on'
            }
        }

        It 'says when this editor has no settings folder yet, and names the folder' {
            $script:missing = Join-Path $script:TStylesDataRoot 'Nope/User/settings.json'
            Mock Resolve-VSCodeTarget { @{ Status = 'nodir'; Variant = 'Code'; Path = $script:missing } }
            $out = Invoke-TerminalStyleVSCode 6>&1 | Out-String -Width 500
            $out | Should -Match 'settings folder does not exist'
            # On a line of its own: the settings.json path below it contains the
            # folder too, and would match on its own.
            $out | Should -Match ('(?m)' + [regex]::Escape([System.IO.Path]::GetDirectoryName($script:missing)) + '\s*$')
        }

        It 'refuses on and off where it cannot tell which editor this is' {
            Mock Resolve-VSCodeTarget { @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
            $out = Invoke-TerminalStyleVSCode -Action 'on' 6>&1 | Out-String
            $out | Should -Match "Can't tell which editor"
            [System.IO.File]::Exists((Get-VSCodeStatePath)) | Should -BeFalse
        }

        It 'shows what is recorded' {
            Set-VSCodeStateEntry -Variant 'Code' -SettingsPath $script:sPath -Consent 'yes'
            Publish-StyleVSCodeConfig -StyleName 'koholint' -StyleDir $script:koholint -Kind 'VSCode' | Out-Null
            $out = Invoke-TerminalStyleVSCode 6>&1 | Out-String -Width 500
            $out | Should -Match 'saving: on'
            $out | Should -Match 'style saved: koholint'
            $out | Should -Match ([regex]::Escape($script:sPath))
        }

        It 'answers an action it does not know with how to use it' {
            (Invoke-TerminalStyleVSCode -Action 'sideways' 6>&1 | Out-String) | Should -Match 'tstyles vscode \[on\|off\]'
        }
    }
}

Describe 'tstyles uninstall and VS Code''s settings.json' {
    # Driven through the real command, past consent, with every path it can
    # reach inside TestDrive -- the setup Uninstall-ReversesShellInit uses:
    # -HomeDir for the rc half, a mocked data root, the Bootstrap branch so
    # Uninstall-PSResource is never reached, and no $PROFILE target.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Get-PowerShellProfileTarget { @() }

            # Two editors with a saved style, as an uninstall run from a plain
            # terminal finds them.
            $script:user = "{`n  `"editor.fontSize`": 13`n}"
            $script:files = @{}
            foreach ($v in 'Code', 'Cursor') {
                $p = Join-Path $script:h "$v/User/settings.json"
                New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($p)) -Force | Out-Null
                $a = Invoke-VSCodeStyleApply -Text $script:user -StyleDir (Get-StyleDir -StyleName 'koholint') -StyleName 'koholint'
                [System.IO.File]::WriteAllText($p, $a.Text, [System.Text.UTF8Encoding]::new($false))
                Set-VSCodeStateEntry -Variant $v -SettingsPath $p -Consent 'yes' -Record $a.Record
                $script:files[$v] = $p
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedData }

        It 'names every settings.json it will change, and changes none when refused' {
            Mock Confirm-Action { $false }
            $before = @{}
            foreach ($v in $script:files.Keys) { $before[$v] = [System.IO.File]::ReadAllText($script:files[$v]) }
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            foreach ($v in $script:files.Keys) {
                $out | Should -Match ([regex]::Escape($script:files[$v])) -Because 'the prompt must name the file it is about to edit'
                [System.IO.File]::ReadAllText($script:files[$v]) | Should -BeExactly $before[$v]
            }
            $out | Should -Match 'Cancelled'
        }

        It 'takes the style out of every editor once confirmed' {
            Mock Confirm-Action { $true }
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String -Width 500
            foreach ($v in $script:files.Keys) {
                [System.IO.File]::ReadAllText($script:files[$v]) | Should -BeExactly $script:user
                $out | Should -Match ("Took the style back out of {0}'s settings\.json" -f $v)
            }
            $out | Should -Match "Windows Terminal's settings\.json was NOT modified" `
                -Because 'the sign-off must not deny the edit it just made'
        }

        It 'says it will leave VS Code alone when the record cannot be read' {
            Mock Confirm-Action { $false }
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{broken', [System.Text.UTF8Encoding]::new($false))
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Match "Leave VS Code's settings alone"
            $out | Should -Match ([regex]::Escape((Get-VSCodeStatePath)))
        }

        It 'names, in the sign-off, a settings.json it could not take the style out of' {
            Mock Confirm-Action { $true }
            $fs = [System.IO.File]::Open($script:files['Code'], 'Open', 'ReadWrite', 'None')
            try {
                $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String -Width 500
            } finally { $fs.Dispose() }
            $out | Should -Match 'EXCEPT the style saved in'
            $out | Should -Match ([regex]::Escape($script:files['Code']))
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$' -Because 'a style is still in a file the user owns'
            $out | Should -Not -Match 'reset again' -Because 'the module is gone by then, so no reset can run'
            $out | Should -Not -Match 'record of what to take out is kept'
            [System.IO.File]::ReadAllText($script:files['Cursor']) | Should -BeExactly $script:user -Because 'the other editor still comes clean'
            # The advice names what to take out, and what the copy costs.
            $out | Should -Match 'terminal\.integrated\.fontFamily'
            $out | Should -Match 'restoring it also undoes your edits since'
        }

        It 'says what it would do to VS Code''s settings.json only when a style is saved there (<label>)' -ForEach @(
            @{ label = 'styles saved'; saved = $true }
            @{ label = 'none saved';   saved = $false }
        ) {
            # The consequence is what a run that cannot ask prints instead of
            # asking, so it is held to the same standard as the listing.
            if (-not $saved) { Remove-Item -LiteralPath (Get-VSCodeStatePath) -Force }
            Mock Confirm-Action { $false }
            Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-Null
            if ($saved) {
                Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Consequence -match "takes the saved style out of VS Code's settings\.json" }
            } else {
                Should -Invoke Confirm-Action -Times 1 -Exactly -Scope It -ParameterFilter { $Consequence -notmatch 'VS Code' }
            }
        }

        It 'the uninstall help says so too' {
            $u = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'uninstall' })
            ($u.Detail -join ' ') | Should -Match 'VS Code'
        }

        It 'lists the VS Code records among what -DeleteData deletes' {
            Mock Confirm-Action { $false }
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() -DeleteData 6>&1 | Out-String -Width 500
            $out | Should -Match 'VS Code consent answers and undo records'
        }

        It 'does not sign off uninstalled when it could not read what was saved' {
            Mock Confirm-Action { $true }
            [System.IO.File]::WriteAllText((Get-VSCodeStatePath), '{broken', [System.Text.UTF8Encoding]::new($false))
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
            $out | Should -Match 'EXCEPT any style saved to a VS Code-family settings\.json'
            $out | Should -Match ([regex]::Escape((Get-VSCodeStatePath)))
        }
    }
}

Describe 'Get-VSCodeUninstallTarget' {
    InModuleScope TerminalStyles {
        It 'names only editors with a saved style, sorted by editor' {
            # [ordered], and inserted out of order: a plain hashtable enumerates
            # in an order .NET Core randomizes per process, so with one the sort
            # being removed would go unnoticed in about half of all runs.
            # Windsurf said yes and has nothing saved: without it, consent and
            # record agree on every entry, and a filter on either would pass.
            $state = @{ Ok = $true; Path = '/x'; Entries = [ordered]@{
                'Cursor'   = @{ consent = 'yes'; settingsPath = '/c/settings.json'; record = @{ Style = 'eva' } }
                'Code'     = @{ consent = 'yes'; settingsPath = '/a/settings.json'; record = @{ Style = 'koholint' } }
                'VSCodium' = @{ consent = 'no';  settingsPath = '/v/settings.json'; record = $null }
                'Windsurf' = @{ consent = 'yes'; settingsPath = '/w/settings.json'; record = $null }
            } }
            $t = @(Get-VSCodeUninstallTarget -State $state)
            (@($t | ForEach-Object { $_.Variant }) -join ',') | Should -Be 'Code,Cursor'
            $t[0].Path | Should -Be '/a/settings.json'
        }

        It 'names nothing when the state could not be read' {
            # With an entry in it: Read-VSCodeState hands back no entries when it
            # fails, which would make this pass with or without the guard.
            $state = @{ Ok = $false; Path = '/x'; Entries = @{
                'Code' = @{ consent = 'yes'; settingsPath = '/a/settings.json'; record = @{ Style = 'koholint' } }
            } }
            @(Get-VSCodeUninstallTarget -State $state).Count | Should -Be 0
        }
    }
}

Describe 'Show-VSCodeResetResult during uninstall' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            Mock Write-Host { }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedData }

        It 'still says what failed, and never tells the user to reset again, on <status>' -ForEach @(@{ status = 'wontparse' }, @{ status = 'writefailed' }, @{ status = 'statecorrupt' }) {
            Show-VSCodeResetResult -Result @{ Status = $status; Variant = 'Code'; Path = '/x/settings.json'; Kept = @(); Restored = @(); Removed = @(); Detail = 'it does not parse as a JSON object' } -Uninstalling
            Should -Invoke Write-Host -Times 0 -Exactly -Scope It -ParameterFilter { "$Object" -match 'reset again|record of what to take out is kept' }
            Should -Invoke Write-Host -Scope It -ParameterFilter { "$Object" -match 'Could not' }
        }
    }
}
