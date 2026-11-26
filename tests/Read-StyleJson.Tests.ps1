# One reader for a style's scheme.json and theme.json, and one answer to "can
# this style be applied?". Every apply, preview, random pick, list row and
# tune entry asks it, so a broken file fails the same way everywhere: before
# anything is touched, with a message naming the style, the file and the fix.
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

Describe 'Read-StyleJson' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))) 'wavy'
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            function script:Set-StyleFile {
                param([string]$Name, [string]$Text)
                [System.IO.File]::WriteAllText((Join-Path $script:d $Name), $Text, [System.Text.UTF8Encoding]::new($false))
            }
        }

        It 'returns the object for a readable file' {
            script:Set-StyleFile 'theme.json' '{"name":"x"}'
            (Read-StyleJson -StyleDir $script:d -FileName 'theme.json').name | Should -Be 'x'
        }

        It 'returns $null for a file that is not there' {
            Read-StyleJson -StyleDir $script:d -FileName 'theme.json' | Should -BeNullOrEmpty
        }

        It 'refuses <Case>' -ForEach @(
            @{ Case = 'a JSON typo';  Text = '{"name": }' }
            @{ Case = 'an empty file'; Text = '' }
            @{ Case = 'JSON null';     Text = 'null' }
            @{ Case = 'an array';      Text = '[1]' }
            @{ Case = 'an array holding one object'; Text = '[{"name":"x"}]' }
            @{ Case = 'a string';      Text = '"x"' }
        ) {
            script:Set-StyleFile 'theme.json' $Text
            { Read-StyleJson -StyleDir $script:d -FileName 'theme.json' } |
                Should -Throw "*could not parse wavy's theme.json*tstyles delete wavy*"
        }

        It 'reads JSONC: comments and a trailing comma' {
            script:Set-StyleFile 'theme.json' "{`n  // a note`n  `"name`": `"x`",`n}"
            (Read-StyleJson -StyleDir $script:d -FileName 'theme.json').name | Should -Be 'x'
        }
    }
}

Describe 'Get-StyleUnreadableFile' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))) 'wavy'
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            function script:Set-StyleFile {
                param([string]$Name, [string]$Text)
                [System.IO.File]::WriteAllText((Join-Path $script:d $Name), $Text, [System.Text.UTF8Encoding]::new($false))
            }
        }

        It 'answers $null for a style whose files both read' {
            script:Set-StyleFile 'scheme.json' '{"name":"wavy"}'
            script:Set-StyleFile 'theme.json' '{"colorScheme":"wavy"}'
            Get-StyleUnreadableFile -StyleDir $script:d | Should -BeNullOrEmpty
        }

        It 'answers $null when theme.json is absent and scheme.json reads' {
            script:Set-StyleFile 'scheme.json' '{"name":"wavy"}'
            Get-StyleUnreadableFile -StyleDir $script:d | Should -BeNullOrEmpty
        }

        It 'names scheme.json first when both are broken' {
            script:Set-StyleFile 'scheme.json' '{'
            script:Set-StyleFile 'theme.json' '{'
            $r = Get-StyleUnreadableFile -StyleDir $script:d
            $r.File | Should -Be 'scheme.json'
            $r.Message | Should -BeLike "*wavy's scheme.json*"
        }

        It 'names theme.json when only it is broken' {
            script:Set-StyleFile 'scheme.json' '{"name":"wavy"}'
            script:Set-StyleFile 'theme.json' ''
            (Get-StyleUnreadableFile -StyleDir $script:d).File | Should -Be 'theme.json'
        }
    }
}
