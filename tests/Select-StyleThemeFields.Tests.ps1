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
            # colorScheme 'eva' so the rule under test is the path, not the
            # marker reset needs (tested below).
            $r = Select-StyleThemeFields -Theme ([pscustomobject]@{ colorScheme = 'eva'; backgroundImage = $Value })
            $r.Fields.Contains('backgroundImage') | Should -Be $Kept
            if (-not $Kept) { $r.Skipped[0].Reason | Should -Be 'not a file on this computer' }
        }

        # Reset recognises a profile it may clear by one thing: a colorScheme
        # naming a style this tool wrote (Test-TerminalStylesSchemeName). An
        # apply without one put keys on the profile that reset then refused to
        # touch, so every key is held back instead.
        It 'holds every key back when <Name>' -ForEach @(
            @{ Name = 'no colorScheme is set';                  Json = '{"tabTitle":"T","opacity":90}';              Held = @('tabTitle', 'opacity') }
            @{ Name = 'colorScheme names no installed style';   Json = '{"colorScheme":"My Scheme","tabTitle":"T"}'; Held = @('colorScheme', 'tabTitle') }
            @{ Name = 'colorScheme is spelled in another case'; Json = '{"ColorScheme":"eva","tabTitle":"T"}';       Held = @('tabTitle') }
        ) {
            $r = Select-StyleThemeFields -Theme ($Json | ConvertFrom-Json)
            $r.Fields.Count | Should -Be 0
            @($r.Skipped | Where-Object { $_.Reason -eq 'tstyles reset could not tell the profile was styled' } |
                ForEach-Object { $_.Name }) | Should -Be $Held
        }

        It "keeps the keys of the creator's live preview, whose scheme this tool also writes" {
            $r = Select-StyleThemeFields -Theme ([pscustomobject][ordered]@{ colorScheme = 'tstyles create'; tabTitle = 'T' })
            @($r.Fields.Keys) | Should -Be @('colorScheme', 'tabTitle')
            Test-TerminalStylesSchemeName -Name 'tstyles create' | Should -BeTrue -Because 'reset must clear what that preview left'
        }

        It 'refuses a backgroundImage that only becomes a network path once expanded' {
            $saved = $env:TS_TEST_NET
            try {
                $env:TS_TEST_NET = '\\server\share'
                $r = Select-StyleThemeFields -Theme ([pscustomobject]@{ colorScheme = 'eva'; backgroundImage = '%TS_TEST_NET%\a.png' })
                $r.Fields.Contains('backgroundImage') | Should -BeFalse
            } finally { $env:TS_TEST_NET = $saved }
        }
    }
}

Describe 'Test-LocalImagePath' {
    # Every spelling below reaches another machine: Win32 reads two leading
    # separators of either kind as a share, .NET's [Uri] reads each file: form
    # here as UNC, \??\UNC\ is the NT path to the same share, and whitespace
    # or an invisible character in front only hides the share from a check
    # that looks at the first two characters. A network path in a theme.json
    # makes Windows authenticate to that host every time the tab draws.
    InModuleScope TerminalStyles {
        It 'refuses <Name>' -ForEach @(
            @{ Name = 'a URL behind a leading space';        Value = ' https://evil/a.png' }
            @{ Name = 'a URL behind a leading tab';          Value = "`thttps://evil/a.png" }
            @{ Name = 'a share behind a leading space';      Value = ' \\server\share\a.png' }
            @{ Name = 'a share spelled \/';                  Value = '\/server/share/a.png' }
            @{ Name = 'a share spelled /\';                  Value = '/\server\share\a.png' }
            @{ Name = 'an NT path to a share';               Value = '\??\UNC\server\share\a.png' }
            @{ Name = 'file: with four slashes';             Value = 'file:////server/share/a.png' }
            @{ Name = 'file: with five slashes';             Value = 'file://///server/share/a.png' }
            @{ Name = 'file: with a share after the slashes'; Value = 'file:///\\server\share\a.png' }
            @{ Name = 'file: with escaped backslashes';      Value = 'file:///%5C%5Cserver/share/a.png' }
            @{ Name = 'ms-appdata: with a host';             Value = 'ms-appdata://server/a.png' }
            @{ Name = 'a local path with a trailing space';  Value = 'C:\pics\a.png ' }
            @{ Name = 'a share behind a zero-width space';   Value = ([string][char]0x200B + '\\server\share\a.png') }
            @{ Name = 'a path holding a control character';  Value = ('C:\pics\a' + [char]7 + '.png') }
        ) {
            Test-LocalImagePath -Value $Value | Should -BeFalse
        }

        It 'keeps <Value>' -ForEach @(
            @{ Value = 'C:\pics\a.png' }
            @{ Value = 'C:/pics/a.png' }
            @{ Value = 'D:\My Pictures\a b.png' }
            @{ Value = '/Users/me/pics/a.png' }
            @{ Value = 'pics\a.png' }
            @{ Value = 'ms-appdata:///local/a.png' }
            @{ Value = 'ms-appx:///Assets/a.png' }
            @{ Value = 'file:///C:/a.png' }
        ) {
            Test-LocalImagePath -Value $Value | Should -BeTrue
        }
    }
}

Describe 'Write-StyleSettingsNote' {
    # What an apply says about settings.json, for every payload. The three
    # applies that write the file printed it themselves, and the picker's copy
    # printed "'mine' ships no , so nothing was written" for a theme.json with
    # nothing to write: it formatted Missing, which only a missing file sets.
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:payload = {
                param([bool]$Ok, $Missing, [bool]$None, [object[]]$Skipped)
                [pscustomobject]@{ Ok = $Ok; Missing = $Missing; Unreadable = $null
                                   NothingApplicable = $None; Skipped = @($Skipped) }
            }
            $script:skip = {
                param([string]$Name, [string]$Reason) [pscustomobject]@{ Name = $Name; Reason = $Reason }
            }
            $script:say = {
                param($Payload)
                @(Write-StyleSettingsNote -StyleName 'mine' -Payload $Payload 6>&1 | ForEach-Object { "$_" })
            }
            $script:resetReason  = 'tstyles reset could not take it back'
            $script:localReason  = 'not a file on this computer'
            $script:markerReason = 'tstyles reset could not tell the profile was styled'
        }

        It 'says a style with no theme.json wrote nothing' {
            & $script:say (& $script:payload $false 'theme.json' $false @()) | Should -Be @(
                "  'mine' ships no theme.json, so nothing was written to settings.json.")
        }

        It 'says an empty theme.json wrote nothing' {
            & $script:say (& $script:payload $false $null $true @()) | Should -Be @(
                "  'mine' ships a theme.json that sets nothing, so nothing was written to settings.json.")
        }

        It 'names the keys reset could not take back, after a write' {
            $s = @((& $script:skip 'commandline' $script:resetReason), (& $script:skip 'elevate' $script:resetReason))
            & $script:say (& $script:payload $true $null $false $s) | Should -Be @(
                '  Not applied from theme.json: commandline, elevate. A style sets only what tstyles reset can take back off a profile.')
        }

        It "gives a skipped background its own reason, not reset's" {
            $s = @(& $script:skip 'backgroundImage' $script:localReason)
            & $script:say (& $script:payload $true $null $false $s) | Should -Be @(
                '  Not applied from theme.json: backgroundImage, which is not a file on this computer.')
        }

        It 'says nothing was written when nothing was' {
            $s = @(& $script:skip 'commandline' $script:resetReason)
            & $script:say (& $script:payload $false $null $true $s) | Should -Be @(
                '  Not applied from theme.json: commandline. A style sets only what tstyles reset can take back off a profile.'
                '  Nothing was written to settings.json.')
        }

        It 'says how to give reset the colorScheme it needs' {
            $s = @((& $script:skip 'tabTitle' $script:markerReason), (& $script:skip 'opacity' $script:markerReason))
            & $script:say (& $script:payload $false $null $true $s) | Should -Be @(
                "  Not applied from theme.json: tabTitle, opacity. Its colorScheme must name an installed style, which is how tstyles reset knows a profile is styled: set it, and the name in scheme.json, to 'mine'."
                '  Nothing was written to settings.json.')
        }

        It 'shows a key name holding an escape sequence instead of sending it' {
            $evil = 'x' + [char]27 + ']0;PWNED' + [char]7
            $out = (& $script:say (& $script:payload $true $null $false @(& $script:skip $evil $script:resetReason))) -join "`n"
            $out.IndexOf([char]27) | Should -Be -1
            $out.IndexOf([char]7)  | Should -Be -1
            $out | Should -Match ([regex]::Escape('x\x1b]0;PWNED\x07'))
        }

        It 'is silent when everything was written' {
            & $script:say (& $script:payload $true $null $false @()) | Should -BeNullOrEmpty
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

        It 'reset leaves the profile as it was when theme.json <Name>' -ForEach @(
            @{ Name = 'sets no colorScheme';                Json = '{"tabTitle":"EVA","opacity":90,"cursorShape":"bar"}' }
            @{ Name = 'names a scheme that is not a style'; Json = '{"colorScheme":"My Scheme","tabTitle":"EVA","opacity":90}' }
            @{ Name = 'spells colorScheme in another case'; Json = '{"ColorScheme":"eva","tabTitle":"EVA","opacity":90}' }
        ) {
            script:Set-Theme $Json
            $before = (script:Get-Entry) | ConvertTo-Json -Depth 10 -Compress

            Apply-StyleDirect -StyleName 'eva' -Target 'PowerShell' 6>&1 | Out-Null
            Reset-StyleDirect -Target 'PowerShell' 6>&1 | Out-Null

            ((script:Get-Entry) | ConvertTo-Json -Depth 10 -Compress) | Should -Be $before
        }
    }
}
