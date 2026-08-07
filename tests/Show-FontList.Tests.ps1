#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Show-FontList' {
    InModuleScope TerminalStyles {
        It 'marks installed fonts with [+] and installable with [ ]' {
            $cat = @(
                [pscustomobject]@{ name='JetBrains Mono'; family='JetBrains Mono'; license='OFL-1.1' },
                [pscustomobject]@{ name='Fira Code';     family='Fira Code';     license='OFL-1.1' }
            )
            $out = Show-FontList -Catalog $cat -Installed @('JetBrains Mono') 6>&1 | Out-String
            $out | Should -Match '\[\+\]\s+JetBrains Mono'
            $out | Should -Match '\[ \]\s+Fira Code'
        }
    }
}
