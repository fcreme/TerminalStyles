# Pester 5 tests for Reset-StyleDirect: strips the TerminalStyles field set
# from a profile, removes the orphan scheme, clears current-style.ps1.
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

Describe 'Reset-StyleDirect' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesCurrent = Join-Path $TestDrive 'current-style.ps1'
            $script:fakeSettings   = Join-Path $TestDrive 'fake-settings.json'

            $settingsObj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' }, [pscustomobject]@{ name = 'other' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'
                        colorScheme = 'eva'; opacity = 80; cursorShape = 'vintage'
                        font = [pscustomobject]@{ face = 'Cascadia Code' }
                        backgroundImage = 'C:\bg.gif'; tabTitle = 'EVA'
                        historySize = 9001
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($settingsObj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName     { 'PowerShell' }
            Mock Write-SettingsFile           { param($Path, $Settings) $script:written = $Settings }
        }

        It 'strips every TerminalStyles field from the target profile' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            foreach ($f in @('colorScheme','opacity','cursorShape','font','backgroundImage','tabTitle')) {
                $p.PSObject.Properties.Match($f).Count | Should -Be 0
            }
        }
        It 'leaves foreign (non-TerminalStyles) profile fields intact' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $p.historySize | Should -Be 9001
            $p.name        | Should -Be 'PowerShell'
        }
        It 'removes the orphan scheme from schemes[]' {
            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'other').Count | Should -Be 1
        }
        It 'keeps a scheme still referenced by another profile' {
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $obj.profiles.list += [pscustomobject]@{ name = 'Other'; guid = '{y}'; colorScheme = 'eva' }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 1
        }
        It 'clears an existing current-style.ps1' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old prompt', [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'writes the rolling settings.json.bak with the prior contents' {
            $prior = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            $bak = "$script:fakeSettings.bak"
            Test-Path $bak | Should -BeTrue
            [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $prior
        }
        It 'does not touch schemes[] when the profile has no colorScheme' {
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $p = $obj.profiles.list | Where-Object name -eq 'PowerShell'
            $p.PSObject.Properties.Remove('colorScheme')   # profile with no colorScheme
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'
            # Both schemes remain (nothing to orphan-remove).
            @($script:written.schemes).Count | Should -Be 2
        }
        It 'resets the defaults profile when -Target defaults' {
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' })
                profiles = [pscustomobject]@{
                    defaults = [pscustomobject]@{ colorScheme = 'eva'; opacity = 80 }
                    list     = @([pscustomobject]@{ name = 'PowerShell'; guid = '{x}' })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'defaults'
            $script:written.profiles.defaults.PSObject.Properties.Match('colorScheme').Count | Should -Be 0
            $script:written.profiles.defaults.PSObject.Properties.Match('opacity').Count     | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 0
        }
        It 'errors gracefully when the target profile is not found' {
            Mock Write-Host {}
            { Reset-StyleDirect -Target 'NoSuchProfile' } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'nothing to reset' }
            Should -Not -Invoke Write-SettingsFile
        }
    }
}
