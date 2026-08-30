# Pester 5 tests: with two Windows Terminal profiles sharing a name, the style
# must land on the one the user is actually sitting in.
#
# THE BUG. Windows Terminal allows two profiles with the same `name` and
# different `guid`s -- a hand-copied profile, or a fragment/dynamic profile
# colliding with a manually defined one. Get-CurrentWTProfileName finds the
# session's entry by $env:WT_PROFILE_ID and then returns only its NAME,
# throwing the GUID away; every resolution downstream was
# `Where-Object name -eq $TargetName | Select-Object -First 1`.
#
# So `tstyles <style>` run in the SECOND of two same-named profiles wrote the
# style onto the FIRST: the user's own window was unchanged, an unrelated
# profile was silently restyled, and "Style applied" printed in green. -Target
# could not rescue it, because the two are indistinguishable by name. `tstyles
# reset` then stripped the same wrong profile, destroying fields the user had
# set there by hand.
#
# The GUID only breaks a TIE. A -Target naming a different profile than the
# session's must still win -- otherwise the flag would become unusable.
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

Describe 'Resolve-WTProfileTarget breaks a name tie with the session GUID' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Two profiles, same name, different GUIDs. Legal in Windows Terminal.
            $script:dup = @'
{
  "profiles": { "list": [
    { "name": "PowerShell", "guid": "{aaaaaaaa-0000-0000-0000-000000000001}", "commandline": "first.exe" },
    { "name": "PowerShell", "guid": "{bbbbbbbb-0000-0000-0000-000000000002}", "commandline": "second.exe" },
    { "name": "Ubuntu",     "guid": "{cccccccc-0000-0000-0000-000000000003}" }
  ] }
}
'@ | ConvertFrom-Json
        }

        It 'picks the profile the session is running in, not the first match' {
            $r = Resolve-WTProfileTarget -Settings $script:dup -TargetName 'PowerShell' `
                    -PreferGuid '{bbbbbbbb-0000-0000-0000-000000000002}'
            $r.Ok | Should -BeTrue
            $r.Entry.guid | Should -Be '{bbbbbbbb-0000-0000-0000-000000000002}' `
                -Because 'the style belongs in the window the user is looking at'
            $r.Ambiguous | Should -BeTrue
        }

        It 'still reports the tie when no GUID is available' {
            # Nothing to disambiguate with: first match, but the caller can see
            # that the answer was a guess.
            $r = Resolve-WTProfileTarget -Settings $script:dup -TargetName 'PowerShell' -PreferGuid ''
            $r.Ok        | Should -BeTrue
            $r.Ambiguous | Should -BeTrue
            $r.Entry.guid | Should -Be '{aaaaaaaa-0000-0000-0000-000000000001}'
        }

        It 'does NOT let the session GUID override a different -Target' {
            # The user asked for Ubuntu while sitting in PowerShell. The GUID is
            # a tie-break among same-named profiles, never a veto.
            $r = Resolve-WTProfileTarget -Settings $script:dup -TargetName 'Ubuntu' `
                    -PreferGuid '{bbbbbbbb-0000-0000-0000-000000000002}'
            $r.Entry.name | Should -Be 'Ubuntu'
            $r.Ambiguous  | Should -BeFalse
        }

        It 'is unambiguous for an ordinary unique name' {
            $r = Resolve-WTProfileTarget -Settings $script:dup -TargetName 'Ubuntu' -PreferGuid ''
            $r.Ok        | Should -BeTrue
            $r.Ambiguous | Should -BeFalse
        }

        It 'still refuses a name that is not there at all' {
            $r = Resolve-WTProfileTarget -Settings $script:dup -TargetName 'Nope' -PreferGuid ''
            $r.Ok    | Should -BeFalse
            $r.Available | Should -Contain 'Ubuntu'
        }
    }
}

Describe 'an ambiguous profile name is reported, not resolved in silence' {
    InModuleScope TerminalStyles {
        It 'tells the user when more than one profile carries the target name' {
            # Ambiguous existed as a computed-but-unread field until this. The
            # tie-break is almost always right, and "almost always" is worth a
            # line: from the outside the user cannot tell the two profiles
            # apart, so a silent choice between them is not something they can
            # check.
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            $styleDir = Join-Path $TestDrive 'styles/amb'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"amb"}')
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'), '{"colorScheme":"amb"}')

            $sp = Join-Path $TestDrive 'amb-settings.json'
            [System.IO.File]::WriteAllText($sp, @'
{ "profiles": { "list": [
    { "name": "PowerShell", "guid": "{aaaaaaaa-0000-0000-0000-000000000001}" },
    { "name": "PowerShell", "guid": "{bbbbbbbb-0000-0000-0000-000000000002}" }
] }, "schemes": [] }
'@)
            Mock Find-WTSettingsPath { $sp }
            Mock Get-TerminalKind    { 'WindowsTerminal' }
            Mock Write-Host          {}

            Apply-StyleDirect -StyleName 'amb' -Target 'PowerShell'

            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -match "more than one profile is named"
            } -Because 'a tie the user cannot see must not be broken silently'
        }

        It 'says nothing for an ordinary unique name' {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style2.ps1'

            $styleDir = Join-Path $TestDrive 'styles/amb2'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"amb2"}')
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'), '{"colorScheme":"amb2"}')

            $sp = Join-Path $TestDrive 'uniq-settings.json'
            [System.IO.File]::WriteAllText($sp, '{ "profiles": { "list": [ { "name": "PowerShell", "guid": "{a}" } ] }, "schemes": [] }')
            Mock Find-WTSettingsPath { $sp }
            Mock Get-TerminalKind    { 'WindowsTerminal' }
            Mock Write-Host          {}

            Apply-StyleDirect -StyleName 'amb2' -Target 'PowerShell'

            Should -Not -Invoke Write-Host -ParameterFilter {
                "$Object" -match "more than one profile is named"
            }
        }
    }
}

Describe 'the merge writes to the profile the session is in' {
    InModuleScope TerminalStyles {
        It 'applies the colorScheme to the session profile, not the first namesake' {
            # End to end through the real merge -- this is the assertion that
            # would have caught the original defect, since Merge-StyleIntoSettings
            # did its own first-match lookup independently of every caller.
            $settings = @'
{
  "profiles": { "list": [
    { "name": "PowerShell", "guid": "{aaaaaaaa-0000-0000-0000-000000000001}" },
    { "name": "PowerShell", "guid": "{bbbbbbbb-0000-0000-0000-000000000002}" }
  ] },
  "schemes": []
}
'@ | ConvertFrom-Json

            $styleDir = Join-Path $TestDrive 'styles/dup'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"dupscheme"}')
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'theme.json'), '{"colorScheme":"dupscheme"}')

            $prev = $env:WT_PROFILE_ID
            try {
                $env:WT_PROFILE_ID = '{bbbbbbbb-0000-0000-0000-000000000002}'
                $out = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
                        -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            } finally { $env:WT_PROFILE_ID = $prev }

            $first  = $out.profiles.list | Where-Object { $_.guid -eq '{aaaaaaaa-0000-0000-0000-000000000001}' }
            $second = $out.profiles.list | Where-Object { $_.guid -eq '{bbbbbbbb-0000-0000-0000-000000000002}' }

            $second.colorScheme | Should -Be 'dupscheme' `
                -Because 'the session profile is the one that should change'
            $first.PSObject.Properties.Match('colorScheme').Count | Should -Be 0 `
                -Because 'an unrelated profile must not be restyled behind the user'
        }
    }
}
