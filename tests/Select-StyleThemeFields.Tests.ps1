# Which theme.json fields a style may put on a Windows Terminal profile (audit
# #44): exactly the keys tstyles reset takes back off one
# ($script:TStylesThemeFields), matched case-sensitively as Windows Terminal
# matches them, and a backgroundImage only as the placeholder or a file on this
# computer. Everything else is skipped, and the apply names it once.
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

Describe 'Select-StyleThemeFields' {
    InModuleScope TerminalStyles {
        It 'keeps every key reset takes back, with its value' {
            $theme = [pscustomobject][ordered]@{
                colorScheme = 'eva'; tabTitle = 'EVA'; tabColor = '#ff3d5a'; cursorShape = 'filledBox'
                useAcrylic = $false; opacity = 90; 'experimental.retroTerminalEffect' = $false
                font = [pscustomobject]@{ face = 'Cascadia Code'; size = 11 }; padding = '12'
                backgroundImage = '{{BACKGROUND_IMAGE}}'; backgroundImageOpacity = 0.4
                backgroundImageStretchMode = 'uniformToFill'; backgroundImageAlignment = 'center'
            }
            $r = Select-StyleThemeFields -Theme $theme
            @($r.Fields.Keys) | Should -Be @($theme.PSObject.Properties.Name)
            $r.Fields['opacity'] | Should -Be 90
            $r.Fields['font'].face | Should -Be 'Cascadia Code'
            @($r.Skipped) | Should -BeNullOrEmpty
        }

        It 'skips <Key>, which reset could not take back' -ForEach @(
            @{ Key = 'commandline' }, @{ Key = 'elevate' }, @{ Key = 'startingDirectory' }, @{ Key = 'icon' }
            # Another case of a key reset knows: Windows Terminal's keys are
            # case-sensitive, so this one would be junk on the profile at best.
            @{ Key = 'TabTitle' }
        ) {
            $theme = [pscustomobject]@{ colorScheme = 'eva' }
            $theme | Add-Member -NotePropertyName $Key -NotePropertyValue 'x'
            $r = Select-StyleThemeFields -Theme $theme
            @($r.Fields.Keys) | Should -Be @('colorScheme')
            $r.Skipped[0].Name   | Should -BeExactly $Key
            $r.Skipped[0].Reason | Should -Be 'tstyles reset could not take it back'
        }

        It 'decides backgroundImage <Value>: <Kept>' -ForEach @(
            @{ Value = '{{BACKGROUND_IMAGE}}';         Kept = $true }
            @{ Value = 'C:\pics\a.png';                Kept = $true }
            @{ Value = '/Users/me/pics/a.png';         Kept = $true }
            @{ Value = 'ms-appdata:///local/a.png';    Kept = $true }
            @{ Value = 'file:///C:/a.png';             Kept = $true }
            @{ Value = '\\server\share\a.png';         Kept = $false }
            @{ Value = '//server/a.png';               Kept = $false }
            @{ Value = 'https://x/a.png';              Kept = $false }
            @{ Value = 'file://server/a.png';          Kept = $false }
        ) {
            $r = Select-StyleThemeFields -Theme ([pscustomobject]@{ backgroundImage = $Value })
            $r.Fields.Contains('backgroundImage') | Should -Be $Kept
            if (-not $Kept) { $r.Skipped[0].Reason | Should -Be 'not a file on this computer' }
        }

        It 'refuses a backgroundImage that only becomes a network path once expanded' {
            $saved = $env:TS_TEST_NET
            try {
                $env:TS_TEST_NET = '\\server\share'
                $r = Select-StyleThemeFields -Theme ([pscustomobject]@{ backgroundImage = '%TS_TEST_NET%\a.png' })
                $r.Fields.Contains('backgroundImage') | Should -BeFalse
            } finally { $env:TS_TEST_NET = $saved }
        }
    }
}

Describe 'Get-ThemeSkippedNote' {
    InModuleScope TerminalStyles {
        It 'names each skipped key, with the reason only where it is not the usual one' {
            $skipped = @(
                [pscustomobject]@{ Name = 'commandline';     Reason = 'tstyles reset could not take it back' }
                [pscustomobject]@{ Name = 'backgroundImage'; Reason = 'not a file on this computer' }
            )
            Get-ThemeSkippedNote -Skipped $skipped | Should -BeExactly `
                '  Not applied from theme.json: commandline, backgroundImage (not a file on this computer). A style sets only what tstyles reset can take back off a profile.'
        }

        It 'says nothing was written when nothing was' {
            $skipped = @([pscustomobject]@{ Name = 'commandline'; Reason = 'tstyles reset could not take it back' })
            Get-ThemeSkippedNote -Skipped $skipped -NothingWritten | Should -BeExactly `
                '  Not applied from theme.json: commandline. A style sets only what tstyles reset can take back off a profile, so nothing was written to settings.json.'
        }

        It 'is silent when nothing was skipped' {
            Get-ThemeSkippedNote -Skipped @() | Should -BeNullOrEmpty
        }
    }
}

Describe 'applying and resetting a style with keys reset cannot take back' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesModuleRoot = Join-Path $TestDrive ('mod-'  + [guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:TStylesCurrent    = Join-Path $script:TStylesDataRoot 'current-style.ps1'

            $script:styleDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') 'eva'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"eva","background":"#000000","foreground":"#ffffff"}', $script:enc)
            function script:Set-Theme([string]$Json) {
                [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'theme.json'), $Json, $script:enc)
            }

            $script:fakeSettings = Join-Path $script:TStylesDataRoot 'fake-settings.json'
            [System.IO.File]::WriteAllText($script:fakeSettings,
                '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}","commandline":"pwsh.exe"}]}}', $script:enc)

            Mock Find-WTSettingsPath           { $script:fakeSettings }
            Mock Get-TerminalKind              { 'WindowsTerminal' }
            Mock Get-CurrentWTProfileName      { 'PowerShell' }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Show-UpdateNoticeIfAvailable  {}
            Mock Get-StyleBundledBackground    { $null }

            function script:Get-Entry {
                $s = [System.IO.File]::ReadAllText($script:fakeSettings, $script:enc) | ConvertFrom-Json
                $s.profiles.list | Where-Object name -eq 'PowerShell'
            }
        }

        It 'names the keys it skipped, once' {
            script:Set-Theme '{"colorScheme":"eva","tabTitle":"EVA","commandline":"evil.exe","elevate":true}'
            $out = Apply-StyleDirect -StyleName 'eva' -Target 'PowerShell' 6>&1 | Out-String -Width 500
            ([regex]::Matches($out, 'Not applied from theme\.json: commandline, elevate\.')).Count | Should -Be 1
            (script:Get-Entry).commandline | Should -Be 'pwsh.exe'
        }

        It 'says nothing about skipped keys when there were none' {
            script:Set-Theme '{"colorScheme":"eva","tabTitle":"EVA"}'
            $out = Apply-StyleDirect -StyleName 'eva' -Target 'PowerShell' 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'Not applied from theme\.json'
        }

        It 'writes nothing to settings.json when theme.json has nothing applicable' {
            script:Set-Theme '{"commandline":"evil.exe"}'
            $before = [System.IO.File]::ReadAllBytes($script:fakeSettings)
            $out = Apply-StyleDirect -StyleName 'eva' -Target 'PowerShell' 6>&1 | Out-String -Width 500
            [System.IO.File]::ReadAllBytes($script:fakeSettings) | Should -Be $before
            $out | Should -Match 'Not applied from theme\.json: commandline\.'
            $out | Should -Match 'nothing was written to settings\.json'
        }

        It 'reset leaves the profile exactly as it was before the apply' {
            script:Set-Theme ('{"colorScheme":"eva","tabTitle":"EVA","opacity":90,"cursorShape":"bar",' +
                              '"commandline":"evil.exe","elevate":true}')
            $before = (script:Get-Entry) | ConvertTo-Json -Depth 10 -Compress

            Apply-StyleDirect -StyleName 'eva' -Target 'PowerShell' 6>&1 | Out-Null
            (script:Get-Entry).tabTitle | Should -Be 'EVA' -Because 'the premise: the apply wrote something'
            Reset-StyleDirect -Target 'PowerShell' 6>&1 | Out-Null

            ((script:Get-Entry) | ConvertTo-Json -Depth 10 -Compress) | Should -Be $before
        }
    }
}
