# Pester 5 tests: the commands that act on Get-TerminalKind take the
# escape-sequence path when their only Windows Terminal marker was inherited.
#
# Windows Terminal puts WT_SESSION and WT_PROFILE_ID into every process a tab
# starts, and copies both into WSL through WSLENV. Get-TerminalKind answered
# WindowsTerminal for WT_SESSION on every platform, ahead of every other
# terminal's marker, so:
#
#   * pwsh inside WSL under Windows Terminal -- a Linux install, with WT's
#     settings.json out of its reach -- stopped `tstyles <name>`, reset, the
#     picker and the tuner on "Could not locate Windows Terminal
#     settings.json.", though WT renders the escape sequences every other
#     terminal is styled with;
#   * a VS Code that `code .` started from a WT tab inherits both variables in
#     every terminal it opens, and there every styling command looked up --
#     and on Windows found and rewrote -- Windows Terminal's settings.json, for
#     the profile the inherited WT_PROFILE_ID names.
#
# Get-TerminalKind.Tests.ps1 pins the detection itself through -EnvTable. These
# drive the four doors that act on it -- Apply-StyleDirect, Reset-StyleDirect,
# the picker and the tuner -- through the live environment, because that is
# what those doors read: WT_SESSION, WT_PROFILE_ID and TERM_PROGRAM are set for
# each test and put back after it, and the platform comes from a mocked
# Get-TStylesPlatform. TERM is never touched: .NET loads terminfo from it
# lazily on Unix.
#
# Nothing real is in reach on the old path or on the new one. Both roots and
# current-style.ps1 point into a fresh folder under $TestDrive, the two
# escape-sequence hand-offs and Find-WTSettingsPath are mocked, and
# Test-InteractiveConsole answers that nobody is there. The picker and the
# tuner get past their kind check only to reach their own [Console] guards,
# which cannot be mocked, and past those both take over the terminal -- so
# those two tests run only where input or output is redirected, as on every CI
# leg, and report skipped from a real terminal. That is decided inside the It:
# a -Skip: condition is evaluated at discovery.
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

Describe 'a Windows Terminal marker inherited from a parent process' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # The live environment these tests change, saved before anything
            # touches it.
            $script:inheritSavedEnv = @{}
            foreach ($name in @('WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM')) {
                $script:inheritSavedEnv[$name] = [System.Environment]::GetEnvironmentVariable($name)
            }

            # Both roots and current-style.ps1, which is fixed at module load.
            # A fresh folder per test: Pester clears TestDrive only when a block
            # ends.
            $script:inheritSavedModuleRoot = $script:TStylesModuleRoot
            $script:inheritSavedDataRoot   = $script:TStylesDataRoot
            $script:inheritSavedCurrent    = $script:TStylesCurrent
            $script:inheritRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:inheritRoot -Force | Out-Null
            $script:TStylesModuleRoot = $script:inheritRoot
            $script:TStylesDataRoot   = $script:inheritRoot
            $script:TStylesCurrent    = Join-Path $script:inheritRoot 'current-style.ps1'

            $styleDir = Join-Path (Join-Path $script:inheritRoot 'styles') 'fake'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'),
                '{"name":"fake","background":"#000000","foreground":"#ffffff"}',
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'),
                '{"colorScheme":"fake"}', [System.Text.UTF8Encoding]::new($false))

            Mock Show-UpdateNoticeIfAvailable {}
            Mock Apply-StyleNonWT {}
            Mock Reset-StyleNonWT {}
            Mock Find-WTSettingsPath { $null }
            Mock Test-InteractiveConsole { $false }
            # Recorded rather than raised, so the old path is measured by what
            # it wrote instead of by the caller's ErrorActionPreference.
            Mock Write-Error {}
        }

        AfterEach {
            foreach ($name in @('WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM')) {
                $saved = $script:inheritSavedEnv[$name]
                if ($null -eq $saved) {
                    Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
                } else {
                    Set-Item -LiteralPath "Env:\$name" -Value $saved
                }
            }
            $script:TStylesModuleRoot = $script:inheritSavedModuleRoot
            $script:TStylesDataRoot   = $script:inheritSavedDataRoot
            $script:TStylesCurrent    = $script:inheritSavedCurrent
        }

        It 'a WSL session under Windows Terminal applies through the escape-sequence path' {
            # What a pwsh in a WSL tab sees: WT's two variables through WSLENV,
            # no TERM_PROGRAM, on Linux. Off a Windows platform nothing can make
            # the kind WindowsTerminal, so this holds in any terminal the suite
            # is run from.
            $env:WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
            $env:WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            Remove-Item -LiteralPath 'Env:\TERM_PROGRAM' -ErrorAction SilentlyContinue
            Mock Get-TStylesPlatform { 'Linux' }

            Apply-StyleDirect -StyleName 'fake'

            Should -Invoke Apply-StyleNonWT -Times 1 -Exactly
            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            Should -Invoke Write-Error -Times 0 -Exactly
        }

        It 'a VS Code terminal opened from a Windows Terminal tab applies through the escape-sequence path' {
            # `code .` typed in a WT tab, on Windows: VS Code's terminals carry
            # WT_SESSION and WT_PROFILE_ID beside its own TERM_PROGRAM. On the
            # old path, the lookup mocked here is the one that finds WT's real
            # settings.json and leads to its rewrite. With TERM_PROGRAM set the
            # Windows Terminal check never answers, so this holds in any
            # terminal too (a live kitty or Alacritty TERM makes it that kind,
            # which hands off the same way).
            $env:WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
            $env:WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            $env:TERM_PROGRAM  = 'vscode'
            Mock Get-TStylesPlatform { 'Windows' }

            Apply-StyleDirect -StyleName 'fake'

            Should -Invoke Apply-StyleNonWT -Times 1 -Exactly
            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            Should -Invoke Write-Error -Times 0 -Exactly
        }

        It 'reset in a WSL session under Windows Terminal takes the escape-sequence path' {
            $env:WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
            $env:WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            Remove-Item -LiteralPath 'Env:\TERM_PROGRAM' -ErrorAction SilentlyContinue
            Mock Get-TStylesPlatform { 'Linux' }

            Reset-StyleDirect

            Should -Invoke Reset-StyleNonWT -Times 1 -Exactly
            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            Should -Invoke Write-Error -Times 0 -Exactly
        }

        It 'the picker in a WSL session under Windows Terminal reaches its console guard without looking for settings.json' {
            # The picker's own guard condition. Past it the picker clears the
            # screen and reads keys, and nothing here can stop that.
            if (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
                Set-ItResult -Skipped -Because 'a real console is attached; past its guard the picker takes over this terminal'
                return
            }

            Mock Invoke-WelcomeFirstRun {}
            Mock Invoke-WezTermOfferFirstRun {}
            Mock Invoke-FontFirstRunPrompt {}
            Mock Write-Host {}
            Mock Read-Host { throw 'the picker must not ask anything' }
            Mock Clear-Host { throw 'the picker must not take the screen' }
            Mock Invoke-PickerLoop { throw 'the picker loop must not start' }
            Mock Test-UpdateAvailable { throw 'the picker must not get past its console guard' }

            $env:WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
            $env:WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            Remove-Item -LiteralPath 'Env:\TERM_PROGRAM' -ErrorAction SilentlyContinue
            Mock Get-TStylesPlatform { 'Linux' }

            Invoke-TerminalStyle

            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -eq '  The style picker needs an interactive terminal.'
            } -Times 1 -Exactly
            Should -Invoke Write-Error -Times 0 -Exactly
        }

        It 'the tuner in a WSL session under Windows Terminal reaches its console guard without looking for settings.json' {
            # The picker's skip condition, for one rule throughout the suite.
            # The tuner checks input first and output second, each with its own
            # message, so the line expected depends on which one is redirected.
            if (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
                Set-ItResult -Skipped -Because 'a real console is attached; past its guards the tuner takes over this terminal'
                return
            }
            $guardLine = if ([Console]::IsInputRedirected) {
                '  The tuner needs an interactive terminal.'
            } else {
                '  The tuner needs a terminal to repaint.'
            }

            Mock Write-Host {}
            Mock Read-Host { throw 'the tuner must not ask anything' }
            Mock Clear-Host { throw 'the tuner must not take the screen' }
            Mock Test-UpdateAvailable { throw 'the tuner must not get past its console guard' }

            $env:WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
            $env:WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            Remove-Item -LiteralPath 'Env:\TERM_PROGRAM' -ErrorAction SilentlyContinue
            Mock Get-TStylesPlatform { 'Linux' }

            Invoke-TerminalStyleTune -StyleName 'fake'

            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            Should -Invoke Write-Host -ParameterFilter { "$Object" -eq $guardLine } -Times 1 -Exactly
            Should -Invoke Write-Error -Times 0 -Exactly
        }
    }
}
