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
    }
}
