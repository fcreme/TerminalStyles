# Pester 5 tests: tstyles font refuses a profile whose "font" holds something
# that is not an object, before it backs up or writes anything.
#
# Set-ProfileFont handled a missing or null font and nothing else. On a string
# -- "font": "Cascadia Code", a hand edit -- Add-Member put the face on a
# wrapper of the string rather than on the profile, so nothing landed, and the
# function still answered $true: settings.json was written back without its
# JSONC comments, the rolling .bak had already been taken, and the command
# printed "Applied '<font>' to '<profile>'".
#
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

Describe 'tstyles font on a profile whose font is not an object' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:saved = @{ D = $script:TStylesDataRoot }
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($sand)
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:p = Join-Path $sand 'settings.json'
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:write = {
                param([string]$FontJson)
                $text = @('{', '  // mine',
                    ('  "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "font": ' + $FontJson + ' } ] }'),
                    '}') -join "`n"
                [System.IO.File]::WriteAllText($script:p, $text, $script:enc)
                $text
            }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Find-WTSettingsPath { $script:p }
            Mock Get-CurrentWTProfileName { 'PowerShell' }
            Mock Test-FontInstalled { $true }
            Mock Get-FontCatalog { @([pscustomobject]@{ name = 'Probe Mono'; family = 'Probe Mono'; nerd = $false }) }
        }
        AfterEach { $script:TStylesDataRoot = $script:saved.D }

        It 'refuses <Label>, and writes and backs up nothing' -ForEach @(
            @{ Label = 'a string'; Json = '"Cascadia Code"' }
            @{ Label = 'a number'; Json = '12' }
            @{ Label = 'a boolean'; Json = 'true' }
            @{ Label = 'an array'; Json = '[ "Cascadia Code" ]' }
        ) {
            $before = & $script:write $Json

            $out = Invoke-TerminalStyleFont -Name 'Probe Mono' -Target 'PowerShell' 6>&1 | Out-String

            [System.IO.File]::ReadAllText($script:p, $script:enc) | Should -BeExactly $before
            @([System.IO.Directory]::GetFiles((Split-Path $script:p), 'settings.json.bak*')).Count | Should -Be 0
            $out | Should -Not -Match 'Applied'
            $out | Should -Match '"font"' -Because 'the refusal names the key that is wrong'
            $out | Should -Match 'PowerShell' -Because 'and the profile it is in'
        }

        It 'still applies over an object, and over null' -ForEach @(
            @{ Json = '{ "size": 11 }' }
            @{ Json = 'null' }
        ) {
            & $script:write $Json | Out-Null
            $out = Invoke-TerminalStyleFont -Name 'Probe Mono' -Target 'PowerShell' 6>&1 | Out-String
            $out | Should -Match "Applied 'Probe Mono'"
            @((ConvertFrom-JsoncText ([System.IO.File]::ReadAllText($script:p))).profiles.list)[0].font.face | Should -Be 'Probe Mono'
        }

        It 'Set-ProfileFont itself refuses a string font rather than answering $true' {
            $before = & $script:write '"Cascadia Code"'
            { Set-ProfileFont -SettingsPath $script:p -TargetName 'PowerShell' -Family 'Probe Mono' } | Should -Throw '*"font"*'
            [System.IO.File]::ReadAllText($script:p, $script:enc) | Should -BeExactly $before
        }
    }
}
