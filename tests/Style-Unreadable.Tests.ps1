# A style whose scheme.json or theme.json will not parse fails before anything
# is touched (audit #20): no settings.json.bak spent, no record written, no
# "Style applied", and one message naming the style, the file and the fix
# (Read-StyleJson's). random never lands on one, `tstyles list` marks one, and
# `tstyles tune` refuses one before it takes the screen.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'a style whose JSON will not parse' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            # Both roots, and the current-style path computed from the data root
            # at module load: Get-StyleDir, Get-AvailableStyles and every record
            # derive from them, and nothing here may reach the real install.
            $script:TStylesModuleRoot = Join-Path $TestDrive ('mod-'  + [guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent    = Join-Path $script:TStylesDataRoot 'current-style.ps1'

            function script:New-TestStyle {
                param([string]$Name, [string]$Scheme, [string]$Theme)
                $d = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $Name
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                if ($null -ne $Scheme) { [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), $Scheme, $script:enc) }
                if ($null -ne $Theme)  { [System.IO.File]::WriteAllText((Join-Path $d 'theme.json'), $Theme, $script:enc) }
                [System.IO.File]::WriteAllText((Join-Path $d 'prompt.sh'), "# $Name`n", $script:enc)
                $d
            }
            $script:goodScheme = '{"name":"good","background":"#101010","foreground":"#f0f0f0"}'
            $script:errors = [System.Collections.ArrayList]::new()
            Mock Write-Error { [void]$script:errors.Add("$Message") }
            Mock Show-UpdateNoticeIfAvailable {}
        }

        Context 'applying it in Windows Terminal' {
            BeforeEach {
                $script:fakeSettings = Join-Path $script:TStylesDataRoot 'fake-settings.json'
                [System.IO.File]::WriteAllText($script:fakeSettings,
                    '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}', $script:enc)
                Mock Find-WTSettingsPath           { $script:fakeSettings }
                Mock Get-TerminalKind              { 'WindowsTerminal' }
                Mock Get-CurrentWTProfileName      { 'PowerShell' }
                Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            }

            It 'refuses a broken theme.json without spending the backup' {
                [void](script:New-TestStyle -Name 'broken' -Scheme '{"name":"broken"}' -Theme '{"colorScheme": }')
                $before = [System.IO.File]::ReadAllBytes($script:fakeSettings)

                Apply-StyleDirect -StyleName 'broken' -Target 'PowerShell' 6>&1 | Out-Null

                [System.IO.File]::ReadAllBytes($script:fakeSettings) | Should -Be $before
                Test-Path -LiteralPath "$script:fakeSettings.bak" | Should -BeFalse `
                    -Because 'the rolling .bak is the undo of the LAST apply, and this one wrote nothing'
                Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'current-style.json') | Should -BeFalse
                ($script:errors -join "`n") | Should -BeLike "*could not parse broken's theme.json*"
            }
        }

        Context 'applying it outside Windows Terminal' {
            BeforeEach {
                Mock Get-TerminalKind { 'AppleTerminal' }
                Mock Get-StyleBundledBackground { $null }
                Mock Write-HostOscPacket { $true }
            }

            It 'refuses a broken scheme.json before recording it' {
                $d = script:New-TestStyle -Name 'broken' -Scheme '{"name": ' -Theme $null
                # The old code parsed with no guard. Under pwsh's default
                # preference the parse error ended only its statement, and the
                # apply went on to record the style and say it applied; under
                # Stop (zsh/bash, and this test run) it escaped as a raw .NET
                # error naming a line of this module. The gate answers before
                # either can happen, so this asserts what nothing may do.
                $out = Apply-StyleNonWT -StyleName 'broken' -StyleDir $d -OutputRedirected $true 6>&1 | Out-String

                Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'current-style.json') | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'current-style.osc')  | Should -BeFalse
                $out | Should -Not -Match 'Style applied'
                ($script:errors -join "`n") | Should -BeLike "*could not parse broken's scheme.json*"
            }
        }

        It 'random never picks an unreadable style' {
            [void](script:New-TestStyle -Name 'good'   -Scheme $script:goodScheme -Theme '{"colorScheme":"good"}')
            [void](script:New-TestStyle -Name 'broken' -Scheme $script:goodScheme -Theme '')
            Mock Get-CurrentStyleName { $null }
            Mock Write-Host {}
            $script:picked = [System.Collections.ArrayList]::new()
            Mock Apply-StyleDirect { [void]$script:picked.Add($StyleName) }

            1..20 | ForEach-Object { Invoke-RandomStyle }

            @($script:picked).Count | Should -Be 20
            @($script:picked | Sort-Object -Unique) | Should -Be @('good')
        }

        It 'list marks an unreadable theme.json' {
            [void](script:New-TestStyle -Name 'good'   -Scheme $script:goodScheme -Theme '{"colorScheme":"good"}')
            [void](script:New-TestStyle -Name 'broken' -Scheme $script:goodScheme -Theme '[1]')
            Mock Get-CurrentStyleName { $null }

            $rows = @((Show-StyleList 6>&1 | Out-String -Width 500) -split '\r?\n')

            @($rows | Where-Object { $_ -match '\bbroken\b' }) -join "`n" | Should -Match '\(unreadable theme\.json\)'
            @($rows | Where-Object { $_ -match '\bgood\b' })   -join "`n" | Should -Not -Match 'unreadable'
        }

        It 'tune refuses an unreadable style before it takes the screen' {
            [void](script:New-TestStyle -Name 'broken' -Scheme $script:goodScheme -Theme '{')
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Clear-Host { throw 'the tuner must not take the screen for a style it cannot read' }

            { Invoke-TerminalStyleTune -StyleName 'broken' } | Should -Not -Throw

            ($script:errors -join "`n") | Should -BeLike "*could not parse broken's theme.json*"
        }
    }
}
