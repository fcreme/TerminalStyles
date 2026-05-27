# Pester 5 tests for Get-StyleDir.
#
# The function resolves a style name to its on-disk directory with
# user-dir precedence (user copy wins on name collision with bundled).
# Module-private; tests run inside InModuleScope.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-StyleDir' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Two distinct subdirs under $TestDrive simulate the two roots.
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesDataRoot 'styles')   -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesModuleRoot 'styles') -Force | Out-Null
        }

        It "returns the user dir when the style exists only in `$DataRoot\styles\" {
            $userStyle = Join-Path $script:TStylesDataRoot 'styles\my-theme'
            New-Item -ItemType Directory -Path $userStyle -Force | Out-Null
            '{"name":"my-theme"}' | Set-Content -LiteralPath (Join-Path $userStyle 'scheme.json') -Encoding UTF8 -NoNewline

            Get-StyleDir -StyleName 'my-theme' | Should -Be $userStyle
        }

        It "returns the bundled dir when the style exists only in `$ModuleRoot\styles\" {
            $bundledStyle = Join-Path $script:TStylesModuleRoot 'styles\bundled-theme'
            New-Item -ItemType Directory -Path $bundledStyle -Force | Out-Null
            '{"name":"bundled-theme"}' | Set-Content -LiteralPath (Join-Path $bundledStyle 'scheme.json') -Encoding UTF8 -NoNewline

            Get-StyleDir -StyleName 'bundled-theme' | Should -Be $bundledStyle
        }

        It "returns the USER dir (user-wins) when the style exists in both" {
            $userStyle    = Join-Path $script:TStylesDataRoot   'styles\eva'
            $bundledStyle = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $userStyle    -Force | Out-Null
            New-Item -ItemType Directory -Path $bundledStyle -Force | Out-Null
            '{"name":"eva-user"}'    | Set-Content -LiteralPath (Join-Path $userStyle    'scheme.json') -Encoding UTF8 -NoNewline
            '{"name":"eva-bundled"}' | Set-Content -LiteralPath (Join-Path $bundledStyle 'scheme.json') -Encoding UTF8 -NoNewline

            # User-wins: the returned path is the user dir, not the bundled dir.
            Get-StyleDir -StyleName 'eva' | Should -Be $userStyle
        }

        It "returns `$null when neither dir has the style" {
            Get-StyleDir -StyleName 'no-such-theme' | Should -BeNullOrEmpty
        }
    }
}
