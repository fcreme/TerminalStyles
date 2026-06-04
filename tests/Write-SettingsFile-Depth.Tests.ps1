# Pester 5 tests for Write-SettingsFile's serialization depth. Real
# settings.json is shallow, but ConvertTo-Json -Depth 32 silently STRINGIFIES
# (corrupts) any subtree deeper than the limit -- silently on Windows
# PowerShell 5.1. This locks a generous depth so a deeply-nested user
# settings.json round-trips intact instead of being truncated on write.
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

Describe 'Write-SettingsFile serialization depth' {
    InModuleScope TerminalStyles {
        It 'round-trips a settings object nested ~40 levels deep without truncation' {
            $obj = [pscustomobject]@{ v = 'leaf' }
            for ($i = 0; $i -lt 40; $i++) { $obj = [pscustomobject]@{ child = $obj } }

            $f = Join-Path $TestDrive 'settings.json'
            Write-SettingsFile -Path $f -Settings $obj

            $parsed = [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $node = $parsed
            for ($i = 0; $i -lt 40; $i++) { $node = $node.child }
            # If serialization truncated, the deep node would be a stringified
            # "@{child=...}" blob and this leaf would be unreachable ($null).
            $node.v | Should -Be 'leaf'
        }
    }
}
