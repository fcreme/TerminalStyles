# Pester 5 tests: the commands that write Windows Terminal's settings.json write
# the hosting build's file, and when Find-WTSettingsPath refuses, they stop
# there and add nothing of their own.
#
# 'through the real lookup' drives Apply-StyleDirect end to end, with only the
# process walk (Find-WTHostExePath) mocked, against a LOCALAPPDATA that holds
# both Stable's and Preview's settings.json. Get-ProcessRecord is mocked to
# throw as a tripwire: a regression that walked the real process tree would
# fail here instead of reading a developer's. The fixture's profile has no
# commandline or source, so it is not a pwsh target and the live-reload line
# after the apply is never reached; nothing here mocks what that line asks.
#
# 'stop at a null and add nothing' mocks the finder to $null: the refusal is
# the finder's to word (tests/Find-WTSettingsPath.Tests.ps1), and five
# commands used to print their own "Could not locate Windows Terminal
# settings.json." beside it.
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

Describe 'the commands that write Windows Terminal settings, through Find-WTSettingsPath' {
    InModuleScope TerminalStyles {
        Context 'through the real lookup' {
            BeforeEach {
                $script:savedEnv = @{}
                foreach ($n in 'LOCALAPPDATA', 'WT_SETTINGS_PATH', 'WT_SETTINGS_DIR', 'TSTYLES_WT_SETTINGS') {
                    $script:savedEnv[$n] = [System.Environment]::GetEnvironmentVariable($n)
                }
                $script:savedModuleRoot = $script:TStylesModuleRoot
                $script:savedDataRoot   = $script:TStylesDataRoot
                $script:savedCurrent    = $script:TStylesCurrent

                # A folder per test: Pester clears TestDrive only when a block
                # ends, so one test's .bak would otherwise still be there.
                $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                $lad = Join-Path $script:root 'lad'
                $env:LOCALAPPDATA = $lad
                foreach ($n in 'WT_SETTINGS_PATH', 'WT_SETTINGS_DIR', 'TSTYLES_WT_SETTINGS') {
                    Remove-Item -LiteralPath "Env:\$n" -ErrorAction SilentlyContinue
                }

                $packages = Join-Path $lad 'Packages'
                $script:stable  = Join-Path (Join-Path (Join-Path $packages 'Microsoft.WindowsTerminal_8wekyb3d8bbwe') 'LocalState') 'settings.json'
                $script:preview = Join-Path (Join-Path (Join-Path $packages 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe') 'LocalState') 'settings.json'
                # The same profile in both, as in life: Preview seeds its file
                # from Stable's, and the GUIDs match in every build.
                $json = @'
{
    // the user's own note, which a write to the wrong build would eat
    "profiles": { "list": [ { "name": "PowerShell", "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}" } ] },
    "schemes": []
}
'@
                foreach ($p in @($script:stable, $script:preview)) {
                    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $p))
                    [System.IO.File]::WriteAllText($p, $json, [System.Text.UTF8Encoding]::new($false))
                }
                $script:stableBytes  = [System.IO.File]::ReadAllBytes($script:stable)
                $script:previewBytes = [System.IO.File]::ReadAllBytes($script:preview)

                $script:TStylesModuleRoot = $script:root
                $script:TStylesDataRoot   = $script:root
                $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'

                $styleDir = Join-Path (Join-Path $script:root 'styles') 'fakeStyle'
                [void][System.IO.Directory]::CreateDirectory($styleDir)
                [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'),
                    '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))
                [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'),
                    '{"colorScheme":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))

                $script:previewExe = Join-Path (Join-Path (Join-Path $script:root 'WindowsApps') 'Microsoft.WindowsTerminalPreview_1.23.2702.0_x64__8wekyb3d8bbwe') 'WindowsTerminal.exe'

                Mock Test-InteractiveConsole      { $false }
                Mock Get-TerminalKind             { 'WindowsTerminal' }
                Mock Show-UpdateNoticeIfAvailable {}
                Mock Write-Host                   {}
                Mock Write-Error                  {}
                Mock Merge-StyleIntoSettings      { param($Settings) $Settings }
                Mock Write-SettingsFile           {}
                Mock Get-ProcessRecord            { throw 'no test may read the real process tree' }
            }

            AfterEach {
                foreach ($n in @($script:savedEnv.Keys)) {
                    if ($null -eq $script:savedEnv[$n]) {
                        Remove-Item -LiteralPath "Env:\$n" -ErrorAction SilentlyContinue
                    } else {
                        Set-Item -LiteralPath "Env:\$n" -Value $script:savedEnv[$n]
                    }
                }
                $script:TStylesModuleRoot = $script:savedModuleRoot
                $script:TStylesDataRoot   = $script:savedDataRoot
                $script:TStylesCurrent    = $script:savedCurrent
            }

            It "applying a style in a Preview tab writes Preview's settings.json and backs it up there, leaving Stable's alone" {
                Mock Find-WTHostExePath { $script:previewExe }

                Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

                Should -Invoke Write-SettingsFile -Times 1 -Exactly -ParameterFilter { $Path -eq $script:preview }
                # The one line that told a user which file was edited.
                Should -Invoke Write-Host -ParameterFilter {
                    ([string]$Object) -ceq ('Backed up settings to: ' + $script:preview + '.bak')
                }
                [System.IO.File]::Exists($script:preview + '.bak') | Should -BeTrue
                [System.IO.File]::Exists($script:stable + '.bak') | Should -BeFalse `
                    -Because "Stable's one rolling backup is its user's undo, not this tab's"
                [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:stable)) |
                    Should -BeExactly ([System.Convert]::ToBase64String($script:stableBytes))
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'with the host unknown and two builds installed, apply refuses once, naming both, and writes neither' {
                Mock Find-WTHostExePath { $null }

                Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains($script:stable) -and ([string]$Message).Contains($script:preview)
                }
                Should -Invoke Write-SettingsFile -Times 0 -Exactly
                [System.IO.File]::Exists($script:stable + '.bak') | Should -BeFalse
                [System.IO.File]::Exists($script:preview + '.bak') | Should -BeFalse
                [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:stable)) |
                    Should -BeExactly ([System.Convert]::ToBase64String($script:stableBytes))
                [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:preview)) |
                    Should -BeExactly ([System.Convert]::ToBase64String($script:previewBytes))
                Should -Not -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains('Style applied') }
            }
        }

        Context 'stop at a null and add nothing' {
            BeforeEach {
                $script:savedModuleRoot = $script:TStylesModuleRoot
                $script:savedDataRoot   = $script:TStylesDataRoot
                $script:savedCurrent    = $script:TStylesCurrent
                $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                [void][System.IO.Directory]::CreateDirectory($script:root)
                $script:TStylesModuleRoot = $script:root
                $script:TStylesDataRoot   = $script:root
                $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'

                Mock Test-InteractiveConsole      { $false }
                Mock Get-TerminalKind             { 'WindowsTerminal' }
                Mock Show-UpdateNoticeIfAvailable {}
                Mock Find-WTSettingsPath          { $null }
                Mock Write-Error                  {}
            }

            AfterEach {
                $script:TStylesModuleRoot = $script:savedModuleRoot
                $script:TStylesDataRoot   = $script:savedDataRoot
                $script:TStylesCurrent    = $script:savedCurrent
            }

            It 'reset stops at a missing settings.json and adds no message of its own' {
                Mock ConvertFrom-JsoncText { throw 'must not parse a settings.json it was not given' }

                Reset-StyleDirect

                Should -Invoke Find-WTSettingsPath -Times 1 -Exactly
                Should -Invoke Write-Error -Times 0 -Exactly
                Should -Invoke ConvertFrom-JsoncText -Times 0 -Exactly
            }

            It 'the picker stops there too, before it takes the screen' {
                Mock Invoke-WelcomeFirstRun      {}
                Mock Invoke-WezTermOfferFirstRun {}
                Mock Invoke-FontFirstRunPrompt   {}
                Mock Get-AvailableStyles         { throw 'the picker must stop at the missing settings.json' }
                Mock Clear-Host                  { throw 'must not take the screen' }

                Invoke-TerminalStyle

                Should -Invoke Find-WTSettingsPath -Times 1 -Exactly
                Should -Invoke Write-Error -Times 0 -Exactly
                Should -Invoke Get-AvailableStyles -Times 0 -Exactly
            }
        }
    }
}
