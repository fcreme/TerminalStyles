# Editing JSONC as text, so a user's comments and formatting survive a style.
#
# WHERE THESE CASES COME FROM. Four independent designs were written for this
# and reviewed against each other. Every one of them was broken, and all four
# breakages were in the same place: what text a member OWNS when it is removed.
# The specific inputs that broke them are the specific inputs below, marked
# with the design they killed. A design review that produces counterexamples is
# only worth having if the counterexamples become tests.
#
# The load-bearing assertion in this file is not any single case. It is
# Test-JsoncCommentsIntact: no edit may lose a comment, ever. Everything else
# is about producing a sensible result; that one is about not destroying
# somebody's writing.
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

Describe 'Get-JsoncToken' {
    InModuleScope TerminalStyles {

        It 'covers the text with no gaps: <Label>' -ForEach @(
            @{ Label = 'plain object';      Text = '{ "a": 1 }' }
            @{ Label = 'line comment';      Text = "{`n  // hi`n  `"a`": 1`n}" }
            @{ Label = 'block comment';     Text = '{ /* hi */ "a": 1 }' }
            @{ Label = 'escaped quote';     Text = '{ "a": "say \" here" }' }
            @{ Label = 'brace in a string'; Text = '{ "a": "not } a brace" }' }
            @{ Label = 'slashes in a string'; Text = '{ "a": "http://x.test/y" }' }
            @{ Label = 'trailing backslash'; Text = '{ "a": "C:\\path\\" }' }
            @{ Label = 'unterminated string'; Text = '{ "a": "oops' }
            @{ Label = 'unterminated block'; Text = '{ /* oops' }
            @{ Label = 'crlf';              Text = "{`r`n  `"a`": 1`r`n}" }
            @{ Label = 'empty';             Text = '' }
        ) {
            # If this ever fails, every splice in the file is unsafe: offsets
            # would no longer address the text they came from.
            $tokens = Get-JsoncToken -Text $Text
            $rebuilt = -join @($tokens | ForEach-Object { $Text.Substring($_.Start, $_.Length) })
            $rebuilt | Should -Be $Text
        }

        It 'does not see structure inside a string' {
            # A value containing braces, a comma and a // must not be read as
            # structure. This is the whole reason for the escape state machine.
            $t = Get-JsoncToken -Text '{ "a": "{ , // }" }'
            @($t | Where-Object { $_.Kind -eq 'BraceOpen' }).Count | Should -Be 1
            @($t | Where-Object { $_.Kind -eq 'LineComment' }).Count | Should -Be 0
            @($t | Where-Object { $_.Kind -eq 'Comma' }).Count | Should -Be 0
        }
    }
}

Describe 'Set-JsoncValue' {
    InModuleScope TerminalStyles {

        It 'updates a value and changes nothing else' {
            $before = "{`n  // keep me`n  `"a`": 1,`n  `"b`": 2`n}"
            $r = Set-JsoncValue -Text $before -Path @('a') -Value 9
            $r.Status | Should -Be 'updated'
            $r.Text | Should -Be "{`n  // keep me`n  `"a`": 9,`n  `"b`": 2`n}"
        }

        It 'inserts a missing key using the indentation already in the file' {
            $before = "{`n    `"a`": 1`n}"
            $r = Set-JsoncValue -Text $before -Path @('b') -Value 'x'
            $r.Status | Should -Be 'inserted'
            $r.Text | Should -Be "{`n    `"a`": 1,`n    `"b`": `"x`"`n}"
        }

        It 'writes the separating comma at the value, not at the end of the line' {
            # DESIGN 4's defect. Anchoring the comma at end-of-line puts it
            # INSIDE the trailing comment, which deletes the separator: the
            # file still looks fine and the next member is orphaned.
            $before = "{`n  `"a`": 1 // why`n}"
            $r = Set-JsoncValue -Text $before -Path @('b') -Value 2
            $r.Text | Should -Be "{`n  `"a`": 1, // why`n  `"b`": 2`n}"
            $r.Text | Should -Not -Match '// why,'
        }

        It 'keeps a one-line object on one line' {
            # DESIGN 4's other defect: whole-line handling mangles compact
            # files. Expanding this would rewrite lines nobody asked us to.
            $r = Set-JsoncValue -Text '{ "a": 1, "b": 2 }' -Path @('c') -Value 3
            $r.Text | Should -Be '{ "a": 1, "b": 2, "c": 3 }'
        }

        It 'does not destroy a comment inside an otherwise empty object' {
            # DESIGN 3's defect: treating a container with only a comment in it
            # as "empty" and replacing its interior wholesale.
            $before = "{`n  `"workbench.colorCustomizations`": {`n    // TODO: pick a palette`n  }`n}"
            $r = Set-JsoncValue -Text $before -Path @('workbench.colorCustomizations', 'terminal.background') -Value '#182098'
            $r.Status | Should -Be 'inserted'
            $r.Text | Should -Match 'TODO: pick a palette'
            Test-JsoncCommentsIntact -Before $before -After $r.Text | Should -BeTrue
        }

        It 'treats a dotted key as one key, never as a path' {
            # VS Code settings keys contain dots. Splitting on '.' would look
            # for an object called "terminal" that does not exist.
            $r = Set-JsoncValue -Text '{}' -Path @('terminal.integrated.fontSize') -Value 14
            $r.Text | Should -Match ([regex]::Escape('"terminal.integrated.fontSize": 14'))
        }

        It 'refuses rather than guessing when the parent is not an object' {
            $r = Set-JsoncValue -Text '{ "a": 5 }' -Path @('a', 'b') -Value 1
            $r.Changed | Should -BeFalse
            $r.Status  | Should -Be 'parentnotobject'
        }

        It 'refuses a document whose root is not an object' {
            $r = Set-JsoncValue -Text '[1, 2]' -Path @('a') -Value 1
            $r.Changed | Should -BeFalse
            $r.Status  | Should -Be 'rootnotobject'
        }

        It 'reports no change when the value is already what we would write' {
            $r = Set-JsoncValue -Text '{ "a": 1 }' -Path @('a') -Value 1
            $r.Changed | Should -BeFalse
            $r.Status  | Should -Be 'same'
        }

        It 'keeps CRLF when the file uses CRLF' {
            $before = "{`r`n  `"a`": 1`r`n}"
            $r = Set-JsoncValue -Text $before -Path @('b') -Value 2
            $r.Text | Should -Be "{`r`n  `"a`": 1,`r`n  `"b`": 2`r`n}"
            $r.Text | Should -Not -Match "[^`r]`n"
        }
    }
}

Describe 'Remove-JsoncValue' {
    InModuleScope TerminalStyles {

        It 'removes a member and the line it sat on' {
            $before = "{`n  `"a`": 1,`n  `"b`": 2`n}"
            $r = Remove-JsoncValue -Text $before -Path @('a')
            $r.Status | Should -Be 'removed'
            $r.Text | Should -Be "{`n  `"b`": 2`n}"
        }

        It 'removes the last member without leaving a dangling comma' {
            $before = "{`n  `"a`": 1,`n  `"b`": 2`n}"
            $r = Remove-JsoncValue -Text $before -Path @('b')
            $r.Text | Should -Be "{`n  `"a`": 1`n}"
        }

        It 'removes the only member' {
            $r = Remove-JsoncValue -Text "{`n  `"a`": 1`n}" -Path @('a')
            $r.Text | Should -Be "{`n}"
        }

        It 'keeps a section header comment above the key it removes' {
            # DESIGN 1's defect, and the commonest real layout there is. The
            # comment heads a GROUP; the key under it is merely the first
            # member of that group, and owning it deletes hand-written prose.
            $before = "{`n  // --- terminal ---`n  `"a`": 1,`n  `"b`": 2`n}"
            $r = Remove-JsoncValue -Text $before -Path @('a')
            $r.Text | Should -Match ([regex]::Escape('// --- terminal ---'))
            Test-JsoncCommentsIntact -Before $before -After $r.Text | Should -BeTrue
        }

        It 'does not eat a trailing comment belonging to a member that survives' {
            # DESIGN 1's other defect: the comment is on the SURVIVING member's
            # line, and a rule that reaches forward from the removed member
            # takes it.
            $before = "{`n  `"a`": 1,`n  `"b`": 2 // keep`n}"
            $r = Remove-JsoncValue -Text $before -Path @('a')
            $r.Text | Should -Match ([regex]::Escape('// keep'))
            Test-JsoncCommentsIntact -Before $before -After $r.Text | Should -BeTrue
        }

        It 'leaves a comment on the removed line orphaned rather than deleting it' {
            # The deliberate cost of the ownership rule, asserted so it is a
            # decision and not an accident. The line is not blank, so it stays.
            $before = "{`n  `"a`": 1, // mine`n  `"b`": 2`n}"
            $r = Remove-JsoncValue -Text $before -Path @('a')
            Test-JsoncCommentsIntact -Before $before -After $r.Text | Should -BeTrue
            $r.Text | Should -Match ([regex]::Escape('// mine'))
        }

        It 'removes from a one-line object without mangling it' {
            $r = Remove-JsoncValue -Text '{ "a": 1, "b": 2 }' -Path @('a')
            $r.Text | Should -Be '{ "b": 2 }'
        }

        It 'reports absent rather than changing anything' {
            $r = Remove-JsoncValue -Text '{ "a": 1 }' -Path @('zz')
            $r.Changed | Should -BeFalse
            $r.Status  | Should -Be 'absent'
        }

        It 'removes a nested key and leaves its siblings alone' {
            $before = "{`n  `"w`": {`n    `"x`": 1,`n    `"y`": 2`n  }`n}"
            $r = Remove-JsoncValue -Text $before -Path @('w', 'x')
            $r.Text | Should -Be "{`n  `"w`": {`n    `"y`": 2`n  }`n}"
        }
    }
}

Describe 'the invariant the ownership rule exists to keep' {
    InModuleScope TerminalStyles {

        BeforeAll {
            # One file carrying every shape that broke a design, plus the
            # shapes real settings.json files have.
            $script:Hard = @'
{
  // --- editor ---
  "editor.fontSize": 13,   // I like it small

  /* a block comment
     over two lines */
  "files.autoSave": "onFocusChange",
  "workbench.colorCustomizations": {
    // my own overrides
    "editor.background": "#1b1b1b", // keep
    "terminal.background": "#000000"
  },
  "terminal.integrated.scrollback": 20000
}
'@
        }

        It 'loses no comment when setting <Desc>' -ForEach @(
            @{ Desc = 'an existing top-level key'; Path = @('editor.fontSize'); Value = 99 }
            @{ Desc = 'a new top-level key';       Path = @('terminal.integrated.fontFamily'); Value = 'Fira Code' }
            @{ Desc = 'an existing nested key';    Path = @('workbench.colorCustomizations', 'terminal.background'); Value = '#182098' }
            @{ Desc = 'a new nested key';          Path = @('workbench.colorCustomizations', 'terminal.ansiRed'); Value = '#d05840' }
        ) {
            $r = Set-JsoncValue -Text $script:Hard -Path $Path -Value $Value
            $r.Changed | Should -BeTrue
            Test-JsoncCommentsIntact -Before $script:Hard -After $r.Text | Should -BeTrue
        }

        It 'loses no comment when removing <Desc>' -ForEach @(
            @{ Desc = 'a key with a trailing comment'; Path = @('editor.fontSize') }
            @{ Desc = 'a key under a block comment';   Path = @('files.autoSave') }
            @{ Desc = 'a nested key with a comment';   Path = @('workbench.colorCustomizations', 'editor.background') }
            @{ Desc = 'the last nested key';           Path = @('workbench.colorCustomizations', 'terminal.background') }
            @{ Desc = 'the last top-level key';        Path = @('terminal.integrated.scrollback') }
        ) {
            $r = Remove-JsoncValue -Text $script:Hard -Path $Path
            $r.Changed | Should -BeTrue
            Test-JsoncCommentsIntact -Before $script:Hard -After $r.Text | Should -BeTrue
        }

        It 'still parses as JSON after every one of those edits' {
            # Preserving comments is worthless if the result is not valid. Each
            # edit is applied to the hard fixture and the result is put through
            # the repo's own JSONC reader.
            $paths = @(
                @('editor.fontSize'),
                @('files.autoSave'),
                @('terminal.integrated.scrollback'),
                @('workbench.colorCustomizations', 'editor.background'),
                @('workbench.colorCustomizations', 'terminal.background')
            )
            foreach ($p in $paths) {
                $r = Remove-JsoncValue -Text $script:Hard -Path $p
                $parsed = ConvertFrom-WTJson -Json $r.Text
                $parsed | Should -Not -BeNullOrEmpty -Because "removing $($p -join '/') must leave valid JSON"
            }
            foreach ($p in $paths) {
                $r = Set-JsoncValue -Text $script:Hard -Path $p -Value 'zz'
                $parsed = ConvertFrom-WTJson -Json $r.Text
                $parsed | Should -Not -BeNullOrEmpty
            }
        }

        It 'changes exactly the one key it was asked to, and no other' {
            # The other half of "preserved": everything else must still hold
            # the value it held.
            $before = ConvertFrom-WTJson -Json $script:Hard
            $r = Set-JsoncValue -Text $script:Hard -Path @('editor.fontSize') -Value 99
            $after = ConvertFrom-WTJson -Json $r.Text
            $after.'editor.fontSize' | Should -Be 99
            $after.'files.autoSave'  | Should -Be $before.'files.autoSave'
            $after.'terminal.integrated.scrollback' | Should -Be $before.'terminal.integrated.scrollback'
            $after.'workbench.colorCustomizations'.'editor.background' |
                Should -Be $before.'workbench.colorCustomizations'.'editor.background'
        }
    }
}

Describe 'the two ways a PowerShell array lies about its size' {
    InModuleScope TerminalStyles {

        # Both of these cost real bugs while this file was being written, and
        # both report a plausible number rather than failing.

        It 'reports no members for an empty object' {
            # Get-JsoncObjectMember returns ,$arr so a ONE-member object does
            # not unroll into a bare hashtable. The cost is that a
            # comma-wrapped return put back inside @() is an array of one
            # whatever it holds -- so @(Get-JsoncObjectMember ...) on '{}' is
            # 1, and an emptied object looks occupied. Assign, do not wrap.
            $t = '{}'
            $members = Get-JsoncObjectMember -Text $t -Tokens (Get-JsoncToken -Text $t) -OpenIndex 0
            $members.Count | Should -Be 0
        }

        It 'reports one member for a one-member object, not its key count' {
            # The other direction: unrolled to a bare hashtable, .Count is the
            # number of KEYS in the record, so $m[$m.Count - 1] indexes past
            # the end and yields $null on the commonest shape there is.
            $t = '{ "a": 1 }'
            $members = Get-JsoncObjectMember -Text $t -Tokens (Get-JsoncToken -Text $t) -OpenIndex 0
            $members.Count | Should -Be 1
            $members[$members.Count - 1].Name | Should -Be 'a'
        }
    }
}

Describe 'Set-JsoncLiteral' {
    InModuleScope TerminalStyles {

        It 'changes a value that differs only in case' {
            # PowerShell's -eq is case-insensitive, so a no-op check written
            # with it reports 'same' and silently declines the edit.
            $r = Set-JsoncLiteral -Text '{ "a": "#f8f8f8" }' -Path @('a') -Literal '"#F8F8F8"'
            $r.Changed | Should -BeTrue
            $r.Text | Should -Be '{ "a": "#F8F8F8" }'
        }

        It 'still reports same for a byte-identical value' {
            $r = Set-JsoncLiteral -Text '{ "a": "#f8f8f8" }' -Path @('a') -Literal '"#f8f8f8"'
            $r.Changed | Should -BeFalse
            $r.Status  | Should -Be 'same'
        }
    }
}

Describe 'Test-JsoncCommentsIntact' {
    InModuleScope TerminalStyles {

        # Every comment assertion in this file runs through this function, so
        # if it could only ever answer $true they would all pass while
        # measuring nothing. These are the cases that prove it answers $false.

        It 'notices a comment that was deleted' {
            Test-JsoncCommentsIntact -Before '{ // gone
"a": 1 }' -After '{ "a": 1 }' | Should -BeFalse
        }

        It 'notices one of two identical comments going missing' {
            # A multiset, not a set: losing the second "// x" is still a loss.
            $before = '{ // x
"a": 1, // x
"b": 2 }'
            $after  = '{ // x
"a": 1,
"b": 2 }'
            Test-JsoncCommentsIntact -Before $before -After $after | Should -BeFalse
        }

        It 'notices a comment whose text was altered' {
            Test-JsoncCommentsIntact -Before '{ // mine
"a": 1 }' -After '{ // MINE
"a": 1 }' | Should -BeFalse
        }

        It 'allows a comment to be added' {
            Test-JsoncCommentsIntact -Before '{ "a": 1 }' -After '{ // new
"a": 1 }' | Should -BeTrue
        }

        It 'is true when nothing changed' {
            $t = '{ // x
"a": 1 }'
            Test-JsoncCommentsIntact -Before $t -After $t | Should -BeTrue
        }
    }
}

Describe 'Invoke-JsoncSplice' {
    InModuleScope TerminalStyles {

        It 'refuses overlapping edits rather than producing something plausible' {
            # A planning bug has to be loud. The alternative is a settings.json
            # that is subtly wrong and saved.
            { Invoke-JsoncSplice -Text 'abcdef' -Edits @(
                @{ Start = 1; Length = 3; Text = 'X' },
                @{ Start = 2; Length = 2; Text = 'Y' }
            ) } | Should -Throw
        }

        It 'applies disjoint edits against original offsets' {
            $out = Invoke-JsoncSplice -Text 'abcdef' -Edits @(
                @{ Start = 4; Length = 1; Text = 'E' },
                @{ Start = 1; Length = 1; Text = 'B' }
            )
            $out | Should -Be 'aBcdEf'
        }

        It 'refuses an edit that runs past the end' {
            { Invoke-JsoncSplice -Text 'abc' -Edits @(@{ Start = 2; Length = 9; Text = '' }) } |
                Should -Throw
        }
    }
}
