# Pester 5 tests for Write-SettingsAtomic: writes settings.json via a
# same-directory temp file + atomic replace so a crash/kill mid-write can never
# leave a truncated settings.json, and never leaves the temp file behind.
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

Describe 'Write-SettingsAtomic' {
    InModuleScope TerminalStyles {
        It 'writes the exact content as UTF-8 without BOM' {
            $f = Join-Path $TestDrive 'settings.json'
            Write-SettingsAtomic -Path $f -Json '{"a":1}'
            [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false)) | Should -Be '{"a":1}'
            $bytes = [System.IO.File]::ReadAllBytes($f)
            # No UTF-8 BOM (EF BB BF) prefix.
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }

        It 'overwrites an existing file' {
            $f = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($f, '{"old":true}', [System.Text.UTF8Encoding]::new($false))
            Write-SettingsAtomic -Path $f -Json '{"new":true}'
            [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false)) | Should -Be '{"new":true}'
        }

        It 'leaves no temp file behind' {
            $f = Join-Path $TestDrive 'settings.json'
            Write-SettingsAtomic -Path $f -Json '{"a":1}'
            Test-Path -LiteralPath "$f.tstmp" | Should -BeFalse
        }
    }
}
