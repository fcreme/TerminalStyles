# Pester 5 tests: when Windows Terminal's settings.json cannot be written, the
# commands that write it stop there -- they do not record the style, install its
# prompt, clear the record, or print a success line over a file they never
# wrote.
#
# The write is made to fail for real, not mocked: a directory sits at both temp
# names Write-SettingsAtomic could use (the per-process one and the one every
# writer shared before), which every leg refuses with no chmod and no ACL. A
# mocked throw would be script-terminating already and would pass on a tree
# where the real failure was stepped over. Each case has a control It on the
# same fixture without the directories, so the absences are not vacuous.
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

Describe 'a settings.json write that fails stops the command' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedModuleRoot = $script:TStylesModuleRoot
            $script:savedDataRoot   = $script:TStylesDataRoot
            $script:savedCurrent    = $script:TStylesCurrent

            # A folder per test: Pester clears TestDrive only when a block ends.
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:root)
            $script:TStylesModuleRoot = $script:root
            $script:TStylesDataRoot   = $script:root
            $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'

            $enc = [System.Text.UTF8Encoding]::new($false)
            $styleDir = Join-Path (Join-Path $script:root 'styles') 'fakeStyle'
            [void][System.IO.Directory]::CreateDirectory($styleDir)
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"fakeStyle"}', $enc)
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'), '{"colorScheme":"fakeStyle"}', $enc)
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'profile.ps1'), "# fixture`n", $enc)

            $script:settings = Join-Path $script:root 'settings.json'
            $script:block = {
                foreach ($t in @(('{0}.{1}.tstmp' -f $script:settings, $PID), "$($script:settings).tstmp")) {
                    [void][System.IO.Directory]::CreateDirectory($t)
                }
            }
            $script:bytes = { [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:settings)) }

            Mock Test-InteractiveConsole      { $false }
            Mock Confirm-Action               { $false }
            Mock Get-TerminalKind             { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Find-WTSettingsPath          { $script:settings }
            Mock Merge-StyleIntoSettings      { param($Settings) $Settings }
            Mock Write-Host                   {}
        }

        AfterEach {
            $script:TStylesModuleRoot = $script:savedModuleRoot
            $script:TStylesDataRoot   = $script:savedDataRoot
            $script:TStylesCurrent    = $script:savedCurrent
        }

        Context 'tstyles <style>' {
            BeforeEach {
                # A pwsh profile, so the prompt-install branch is live.
                [System.IO.File]::WriteAllText($script:settings,
                    '{"profiles":{"list":[{"name":"PowerShell","source":"Windows.Terminal.PowershellCore"}]},"schemes":[]}',
                    [System.Text.UTF8Encoding]::new($false))
            }

            It 'applies, records and says so when the write lands (control)' {
                Apply-StyleDirect -StyleName fakeStyle -Target PowerShell
                Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains('Style applied') }
                [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeTrue
            }

            It 'stops before it records the style or says it applied, naming the file' {
                & $script:block
                $before = & $script:bytes
                $err = $null
                try { Apply-StyleDirect -StyleName fakeStyle -Target PowerShell } catch { $err = $_ }

                $err | Should -Not -BeNullOrEmpty
                ([string]$err.Exception.Message).Contains("Could not write $($script:settings)") | Should -BeTrue -Because $err.Exception.Message
                Should -Not -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains('Style applied') }
                [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeFalse
                [System.IO.File]::Exists((Get-CurrentStyleRecordPath)) | Should -BeFalse
                (& $script:bytes) | Should -BeExactly $before
            }
        }

        Context 'tstyles reset' {
            BeforeEach {
                [System.IO.File]::WriteAllText($script:settings,
                    '{"profiles":{"list":[{"name":"PowerShell","source":"Windows.Terminal.PowershellCore","colorScheme":"fakeStyle","opacity":80}]},"schemes":[{"name":"fakeStyle"}]}',
                    [System.Text.UTF8Encoding]::new($false))
                Set-CurrentStyleRecord -StyleName fakeStyle -Kind WindowsTerminal
                [System.IO.File]::WriteAllText($script:TStylesCurrent, "# fixture`n", [System.Text.UTF8Encoding]::new($false))
            }

            It 'resets and says so when the write lands (control)' {
                Reset-StyleDirect -Target PowerShell
                Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("Reset 'PowerShell'") }
            }

            It 'stops before it clears the record or calls the profile plain, naming the file' {
                & $script:block
                $before = & $script:bytes
                $err = $null
                try { Reset-StyleDirect -Target PowerShell } catch { $err = $_ }

                $err | Should -Not -BeNullOrEmpty
                ([string]$err.Exception.Message).Contains("Could not write $($script:settings)") | Should -BeTrue -Because $err.Exception.Message
                Should -Not -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("Reset 'PowerShell'") }
                [System.IO.File]::Exists((Get-CurrentStyleRecordPath)) | Should -BeTrue
                [System.IO.File]::Exists($script:TStylesCurrent) | Should -BeTrue
                (& $script:bytes) | Should -BeExactly $before
            }
        }

        Context 'tstyles font' {
            BeforeEach {
                [System.IO.File]::WriteAllText($script:settings,
                    '{"profiles":{"list":[{"name":"PowerShell","source":"Windows.Terminal.PowershellCore"}]},"schemes":[]}',
                    [System.Text.UTF8Encoding]::new($false))
                Mock Test-FontInstalled { $true }
                Mock Get-FontCatalog { @([pscustomobject]@{ name = 'fixture'; family = 'Fixture Mono' }) }
            }

            It 'applies and says so when the write lands (control)' {
                Invoke-TerminalStyleFont -Name fixture -Target PowerShell
                Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("Applied 'Fixture Mono' to 'PowerShell'") }
            }

            It 'is not reported as applied, and names the file' {
                & $script:block
                $before = & $script:bytes
                $err = $null
                try { Invoke-TerminalStyleFont -Name fixture -Target PowerShell } catch { $err = $_ }

                $err | Should -Not -BeNullOrEmpty
                ([string]$err.Exception.Message).Contains("Could not write $($script:settings)") | Should -BeTrue -Because $err.Exception.Message
                Should -Not -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("Applied '") }
                (& $script:bytes) | Should -BeExactly $before
            }
        }
    }
}
