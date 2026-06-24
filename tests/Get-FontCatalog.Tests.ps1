# Pester 5 tests for Get-FontCatalog. Uses a fixture manifest under $TestDrive.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-FontCatalog' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
        }
        BeforeEach {
            $script:manifest = Join-Path $TestDrive 'fonts.json'
        }

        It 'parses a valid manifest into entries' {
            [System.IO.File]::WriteAllText($script:manifest,
                '{"fonts":[{"name":"JetBrains Mono","family":"JetBrains Mono","license":"OFL-1.1","url":"https://x/jb.zip","sha256":"abc","files":["ttf/JetBrainsMono-Regular.ttf"]}]}',
                $script:enc)
            $cat = Get-FontCatalog -Path $script:manifest
            @($cat).Count | Should -Be 1
            $cat[0].name    | Should -Be 'JetBrains Mono'
            $cat[0].family  | Should -Be 'JetBrains Mono'
            $cat[0].url     | Should -Be 'https://x/jb.zip'
            $cat[0].files[0]| Should -Be 'ttf/JetBrainsMono-Regular.ttf'
        }

        It 'throws when the manifest file is missing' {
            { Get-FontCatalog -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw
        }

        It 'skips entries missing a required field' {
            [System.IO.File]::WriteAllText($script:manifest,
                '{"fonts":[{"name":"Good","family":"Good","url":"https://x/g.zip","sha256":"h","files":[]},{"name":"NoUrl","family":"NoUrl","sha256":"h"}]}',
                $script:enc)
            $cat = Get-FontCatalog -Path $script:manifest
            @($cat).Count | Should -Be 1
            $cat[0].name  | Should -Be 'Good'
        }
    }
}
