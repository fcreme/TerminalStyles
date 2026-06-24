#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Set-ProfileFont' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:settings = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($script:settings,
                '{"profiles":{"list":[{"name":"PowerShell","guid":"{g}"}]}}', $script:enc)
        }

        It 'sets font.face on the named target profile' {
            $ok = Set-ProfileFont -SettingsPath $script:settings -TargetName 'PowerShell' -Family 'JetBrains Mono'
            $ok | Should -BeTrue
            $s = [System.IO.File]::ReadAllText($script:settings, $script:enc) | ConvertFrom-Json
            ($s.profiles.list | Where-Object name -eq 'PowerShell').font.face | Should -Be 'JetBrains Mono'
        }

        It 'returns false and leaves the file untouched for a missing target' {
            $before = [System.IO.File]::ReadAllText($script:settings, $script:enc)
            $ok = Set-ProfileFont -SettingsPath $script:settings -TargetName 'Nope' -Family 'JetBrains Mono'
            $ok | Should -BeFalse
            [System.IO.File]::ReadAllText($script:settings, $script:enc) | Should -Be $before
        }

        It 'sets font.face on the defaults target, creating it if absent' {
            $ok = Set-ProfileFont -SettingsPath $script:settings -TargetName 'defaults' -Family 'Hack'
            $ok | Should -BeTrue
            $s = [System.IO.File]::ReadAllText($script:settings, $script:enc) | ConvertFrom-Json
            $s.profiles.defaults.font.face | Should -Be 'Hack'
        }

        It 'preserves existing font sub-properties when setting face' {
            [System.IO.File]::WriteAllText($script:settings,
                '{"profiles":{"list":[{"name":"PowerShell","guid":"{g}","font":{"size":14}}]}}', $script:enc)
            $ok = Set-ProfileFont -SettingsPath $script:settings -TargetName 'PowerShell' -Family 'Hack'
            $ok | Should -BeTrue
            $entry = (([System.IO.File]::ReadAllText($script:settings, $script:enc) | ConvertFrom-Json).profiles.list |
                      Where-Object name -eq 'PowerShell')
            $entry.font.face | Should -Be 'Hack'
            $entry.font.size | Should -Be 14
        }
    }
}
