# Pester 5 tests for Remove-JsonComment / ConvertFrom-WTJson -- the JSONC
# tolerance layer for reading Windows Terminal settings.json. WT's
# auto-generated settings.json ships with // comments, which Windows
# PowerShell 5.1's ConvertFrom-Json rejects outright (pwsh 7 tolerates them).
# These lock the comment-stripping: remove // and /* */ comments OUTSIDE
# string literals, while preserving comment-like sequences INSIDE strings
# (URLs, globs, paths) so values aren't corrupted.
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

Describe 'Remove-JsonComment' {
    InModuleScope TerminalStyles {
        It 'leaves comment-free JSON unchanged' {
            $json = '{"a":1,"b":[2,3]}'
            Remove-JsonComment -Text $json | Should -Be $json
        }
        It 'strips a // line comment but keeps the data' {
            $in = @'
{
  // pick a profile
  "a": 1
}
'@
            $out = Remove-JsonComment -Text $in
            $out | Should -Not -Match '//'
            ($out | ConvertFrom-Json).a | Should -Be 1
        }
        It 'strips a /* block comment */' {
            $in  = '{ /* header */ "a": 1 }'
            $out = Remove-JsonComment -Text $in
            $out | Should -Not -Match '/\*'
            ($out | ConvertFrom-Json).a | Should -Be 1
        }
        It 'preserves // inside a string value (URL)' {
            $in  = '{"url":"https://example.com/x"}'
            $out = Remove-JsonComment -Text $in
            ($out | ConvertFrom-Json).url | Should -Be 'https://example.com/x'
        }
        It 'preserves /* */ inside a string value' {
            $in  = '{"glob":"/* not a comment */"}'
            $out = Remove-JsonComment -Text $in
            ($out | ConvertFrom-Json).glob | Should -Be '/* not a comment */'
        }
        It 'respects escaped quotes when tracking string boundaries' {
            # The \"hi\" is an escaped quote pair INSIDE the value; the //x must
            # survive (still in-string) and only the trailing // tail is stripped.
            $in  = '{"a":"he said \"hi\" //x"} // tail'
            $out = Remove-JsonComment -Text $in
            ($out | ConvertFrom-Json).a | Should -Be 'he said "hi" //x'
        }
    }
}

Describe 'Remove-JsonTrailingComma' {
    # Windows Terminal (and humans hand-editing settings.json) leave trailing
    # commas before } and ]. pwsh 7's ConvertFrom-Json tolerates them; Windows
    # PowerShell 5.1's does NOT ("extra trailing ','"), so a WT install or a
    # manual edit would crash every mutating command on 5.1 -- the same failure
    # class as comments. Strip trailing commas OUTSIDE string literals only,
    # leaving commas inside string values (e.g. "a,b") untouched.
    InModuleScope TerminalStyles {
        It 'leaves comma-free JSON unchanged' {
            $json = '{"a":1,"b":[2,3]}'
            Remove-JsonTrailingComma -Text $json | Should -Be $json
        }
        It 'drops a trailing comma before a closing brace' {
            $out = Remove-JsonTrailingComma -Text '{"a":1,}'
            $out | Should -Be '{"a":1}'
            ($out | ConvertFrom-Json).a | Should -Be 1
        }
        It 'drops a trailing comma before a closing bracket' {
            Remove-JsonTrailingComma -Text '{"list":[1,2,]}' | Should -Be '{"list":[1,2]}'
        }
        It 'drops a trailing comma separated from the bracket by whitespace/newline' {
            $in  = "{`n  `"a`": 1,`n}"
            $out = Remove-JsonTrailingComma -Text $in
            ($out | ConvertFrom-Json).a | Should -Be 1
        }
        It 'drops nested trailing commas (array inside object, both trailing)' {
            Remove-JsonTrailingComma -Text '{"a":[1,],"b":2,}' | Should -Be '{"a":[1],"b":2}'
        }
        It 'preserves a comma inside a string value' {
            $in  = '{"a":"x,","b":2}'
            $out = Remove-JsonTrailingComma -Text $in
            ($out | ConvertFrom-Json).a | Should -Be 'x,'
            ($out | ConvertFrom-Json).b | Should -Be 2
        }
        It 'preserves a string value that ends in a comma right before a brace' {
            # The comma is INSIDE the value, not a trailing structural comma.
            (Remove-JsonTrailingComma -Text '{"a":"trailing,"}' | ConvertFrom-Json).a |
                Should -Be 'trailing,'
        }
        It 'respects escaped quotes when tracking string boundaries' {
            $in  = '{"a":"he said \"hi,\"","b":2,}'
            $out = Remove-JsonTrailingComma -Text $in
            ($out | ConvertFrom-Json).a | Should -Be 'he said "hi,"'
            ($out | ConvertFrom-Json).b | Should -Be 2
        }
    }
}

Describe 'ConvertFrom-WTJson' {
    InModuleScope TerminalStyles {
        It 'parses Windows-Terminal-style JSON that contains // comments' {
            $json = @'
{
    // To view the default settings, hold "alt" while clicking Settings
    "profiles": { "list": [ { "name": "PowerShell" } ] }
}
'@
            $obj = ConvertFrom-WTJson -Json $json
            $obj.profiles.list[0].name | Should -Be 'PowerShell'
        }
        It 'parses comment-free JSON like ConvertFrom-Json' {
            $json = '{"x":42,"y":"z"}'
            (ConvertFrom-WTJson -Json $json).x | Should -Be 42
            (ConvertFrom-WTJson -Json $json).y | Should -Be 'z'
        }
        It 'throws an actionable error mentioning settings.json on invalid input' {
            { ConvertFrom-WTJson -Json '{ not json' } | Should -Throw '*settings.json*'
        }
        It 'parses JSON with a trailing comma (which WinPS 5.1 rejects natively)' {
            (ConvertFrom-WTJson -Json '{"a":1,}').a | Should -Be 1
        }
        It 'parses WT-style JSON with BOTH comments and trailing commas' {
            $json = @'
{
    // header comment
    "profiles": {
        "list": [
            { "name": "PowerShell" },
            { "name": "cmd" },
        ],
    },
}
'@
            $obj = ConvertFrom-WTJson -Json $json
            $obj.profiles.list.Count | Should -Be 2
            $obj.profiles.list[1].name | Should -Be 'cmd'
        }
        It 'does not strip a comma inside a string value' {
            $obj = ConvertFrom-WTJson -Json '{"note":"a,b","n":2}'
            $obj.note | Should -Be 'a,b'
            $obj.n    | Should -Be 2
        }
    }
}
