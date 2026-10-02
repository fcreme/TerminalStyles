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
            @{ status = 'declined';       pattern = 'tstyles vscode on' }
            @{ status = 'undecided';      pattern = 'no answer on record' }
            @{ status = 'unknownvariant'; pattern = "Couldn't tell which editor" }
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
    }
}
