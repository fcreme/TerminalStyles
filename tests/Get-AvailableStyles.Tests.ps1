# Pester 5 tests for Get-AvailableStyles: the user+bundled style enumeration
# (user-wins dedup) shared by the picker, list, current, random, and dispatch.
# Guard test -- Get-AvailableStyles already exists; this locks its contract.
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

Describe 'Get-AvailableStyles' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            # Bundled: alpha, beta. User: beta (override), gamma (new).
            foreach ($n in 'alpha','beta') {
                $d = Join-Path $script:TStylesModuleRoot "styles\$n"
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), "{`"name`":`"$n`"}", [System.Text.UTF8Encoding]::new($false))
            }
            foreach ($n in 'beta','gamma') {
                $d = Join-Path $script:TStylesDataRoot "styles\$n"
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), "{`"name`":`"$n`"}", [System.Text.UTF8Encoding]::new($false))
            }
            # A user dir WITHOUT scheme.json must be ignored.
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesDataRoot 'styles\noscheme') -Force | Out-Null
        }

        It 'returns the union of bundled + user styles, sorted by name' {
            (Get-AvailableStyles).Name | Should -Be @('alpha','beta','gamma')
        }
        It 'user style wins on name collision (beta resolves to the user dir)' {
            $beta = Get-AvailableStyles | Where-Object Name -eq 'beta'
            ($beta | Measure-Object).Count | Should -Be 1
            $beta.FullName | Should -BeLike (Join-Path $script:TStylesDataRoot '*beta*')
        }
        It 'ignores directories without a scheme.json' {
            (Get-AvailableStyles).Name | Should -Not -Contain 'noscheme'
        }
        It 'returns objects with Name and FullName (what the picker consumes)' {
            $s = Get-AvailableStyles | Select-Object -First 1
            $s.Name     | Should -Not -BeNullOrEmpty
            $s.FullName | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $s.FullName | Should -BeTrue
        }
    }
}
