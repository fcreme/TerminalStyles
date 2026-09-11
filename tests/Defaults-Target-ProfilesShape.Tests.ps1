# Pester 5 tests: 'defaults' is addressable only when settings.json can actually
# carry a profiles.defaults block.
#
# THE BUG. Resolve-WTProfileTarget answered Ok=$true for -Target defaults
# UNCONDITIONALLY, on the reasoning that an apply creates the block lazily. That
# lazy creation is `$Settings.profiles | Add-Member`, which needs a profiles
# OBJECT to add to. Four settings.json shapes have no such object -- no
# `profiles` key at all, `"profiles": null`, a zero-byte or truncated file (so
# the parsed settings are $null), and the legacy flat form `"profiles": [ ... ]`
# -- and on all four the resolver said yes:
#
#   * Apply-StyleDirect's -Target guard asks exactly that question, so it
#     passed, and Save-SettingsBackup spent the rolling .bak -- the user's undo
#     of their last real apply.
#   * Merge-StyleIntoSettings then threw "You cannot call a method on a
#     null-valued expression". A method call on null aborts the STATEMENT, not
#     the command, and $ErrorActionPreference is 'Continue' in an interactive
#     shell -- so the assignment never happened, $settings still held the
#     parsed-but-unmerged object, and the very next line wrote THAT out:
#     ConvertFrom-WTJson had already stripped the comments, so every // note in
#     the user's settings.json was deleted, "Style applied" printed in green,
#     and `tstyles current` named a style no profile had received. Run it a
#     second time and the .bak -- the one copy that still held the comments --
#     was overwritten with the stripped file. Unrecoverable from there.
#   * On the array form there was no throw at all: Add-Member UNROLLS an array,
#     so every profile in the list gained a `defaults` NoteProperty and the
#     whole theme was written INSIDE the first profile, where Windows Terminal
#     ignores it. Silent, and reported as success.
#
# This is the same failure the -Target guard was added for in 0.8.17, re-entered
# through the one target the resolver declared always addressable.
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

Describe "Resolve-WTProfileTarget refuses 'defaults' when there is nothing to create it on" {
    InModuleScope TerminalStyles {
        # $null models the zero-byte / whitespace-only / truncated file: on
        # pwsh 7 ConvertFrom-WTJson returns $null for it, which is what every
        # reader downstream then holds.
        It "refuses -Target defaults for <case>" -ForEach @(
            @{ case = 'a settings.json with no profiles key'; json = '{"schemes":[]}' }
            @{ case = 'a null profiles key';                  json = '{"profiles":null}' }
            @{ case = 'an empty object';                      json = '{}' }
            @{ case = 'the legacy flat-array form';           json = '{"profiles":[{"guid":"{a}","name":"PowerShell"}]}' }
            @{ case = 'an unparseable/empty settings.json';   json = $null }
        ) {
            $settings = if ($json) { $json | ConvertFrom-Json } else { $null }
            $r = Resolve-WTProfileTarget -Settings $settings -TargetName 'defaults'

            $r.Ok | Should -BeFalse -Because @'
Ok is what Apply-StyleDirect's guard asks before it spends the rolling backup
and hands the settings to a merge that cannot write this shape.
'@
            $r.Available | Should -Not -Contain 'defaults' `
                -Because 'offering the one answer guaranteed to be refused is not an error message'
        }

        It "still calls 'defaults' addressable on an ordinary settings.json" {
            # The positive control. Without it the guard above could be
            # satisfied by a resolver that always says no -- and 'defaults' is a
            # documented, ordinary target (apply.ps1's own header shows it).
            $s = '{"profiles":{"list":[{"guid":"{a}","name":"PowerShell"}]}}' | ConvertFrom-Json
            $r = Resolve-WTProfileTarget -Settings $s -TargetName 'defaults'
            $r.Ok         | Should -BeTrue
            $r.IsDefaults | Should -BeTrue
            $r.Entry      | Should -BeNullOrEmpty -Because 'the block is created lazily; Ok without Entry is the point'
            $r.Available  | Should -Contain 'defaults'
        }

        It "still calls 'defaults' addressable when the block already exists" {
            $s = '{"profiles":{"defaults":{"opacity":50},"list":[]}}' | ConvertFrom-Json
            $r = Resolve-WTProfileTarget -Settings $s -TargetName 'defaults'
            $r.Ok            | Should -BeTrue
            $r.Entry.opacity | Should -Be 50
        }

        It 'names the real profiles of the legacy flat-array form instead of only "defaults"' {
            # The other half of the same mis-read: Available was built from
            # $Settings.profiles.list, which is $null for the array form, so a
            # user with that file was told their only choice was the one target
            # that would corrupt it.
            $s = '{"profiles":[{"guid":"{a}","name":"PowerShell"},{"guid":"{b}","name":"Ubuntu"}]}' | ConvertFrom-Json
            $r = Resolve-WTProfileTarget -Settings $s -TargetName 'PowerShell'
            $r.Ok         | Should -BeTrue
            $r.Entry.guid | Should -Be '{a}'
            $r.Available  | Should -Contain 'Ubuntu'
        }

        It 'reports no addressable target at all when profiles is missing' {
            $r = Resolve-WTProfileTarget -Settings ('{"schemes":[]}' | ConvertFrom-Json) -TargetName 'PowerShell'
            @($r.Available).Count | Should -Be 0
            # ...and the message must not trail off into an empty list.
            Get-WTTargetNotFoundMessage -ResolvedTarget $r -TargetName 'PowerShell' |
                Should -Match "has no profile to apply to"
        }
    }
}

Describe 'Merge-StyleIntoSettings makes the same judgement as the resolver' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Sandboxed data root AND a mocked background resolver: the merge
            # resolves a style's background itself, and its third tier
            # lazy-FETCHES over the network into the cache.
            $script:savedDataRoot   = $script:TStylesDataRoot
            $script:TStylesDataRoot = $TestDrive
            Mock Get-StyleBundledBackground { $null }

            $script:shapeStyle = Join-Path $TestDrive 'styles/shape'
            New-Item -ItemType Directory -Path $script:shapeStyle -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:shapeStyle 'scheme.json'),
                '{"name":"shapescheme"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:shapeStyle 'theme.json'),
                '{"colorScheme":"shapescheme","opacity":90}', [System.Text.UTF8Encoding]::new($false))
        }
        AfterEach { $script:TStylesDataRoot = $script:savedDataRoot }

        # The load-bearing agreement: whatever the resolver decides, the merge
        # must not damage a file it cannot write. Both halves are asserted, so
        # neither can quietly become vacuous -- the resolver's answer is checked
        # AND the merge is actually run. On the unfixed code the merge throws
        # here for the null shapes and silently grafts for the array one.
        It 'writes nothing for a defaults target on <case>' -ForEach @(
            @{ case = 'a settings.json with no profiles key'; json = '{"schemes":[]}' }
            @{ case = 'a null profiles key';                  json = '{"profiles":null}' }
            @{ case = 'the legacy flat-array form';           json = '{"profiles":[{"guid":"{a}","name":"PowerShell"}]}' }
        ) {
            $s = $json | ConvertFrom-Json
            (Resolve-WTProfileTarget -Settings $s -TargetName 'defaults').Ok | Should -BeFalse

            # Not wrapped in Should -Not -Throw: an exception here fails the It
            # with the real message, which is the diagnosis.
            $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:shapeStyle `
                -TargetName 'defaults' -BackgroundImage '' -BackgroundImageProvided $false

            @($out.schemes | Where-Object { $_.name -eq 'shapescheme' }).Count | Should -Be 0 `
                -Because 'a scheme no profile can reference is one Reset can never clean up'
            # `$null -ne $_` first: piping a scalar $null sends ONE item down
            # the pipeline, so the member access alone would throw here for the
            # shapes whose `profiles` is missing entirely.
            @($out.profiles | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Match('defaults').Count }).Count |
                Should -Be 0 -Because @'
Add-Member unrolls an array: the flat-array form grafted a defaults block onto
every profile in the list and wrote the whole theme where WT ignores it.
'@
        }

        It 'still creates and styles profiles.defaults on an ordinary settings.json' {
            $s = '{"profiles":{"list":[{"guid":"{a}","name":"PowerShell"}]}}' | ConvertFrom-Json
            $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:shapeStyle `
                -TargetName 'defaults' -BackgroundImage '' -BackgroundImageProvided $false
            $out.profiles.defaults.colorScheme | Should -Be 'shapescheme'
            $out.profiles.defaults.opacity     | Should -Be 90
        }
    }
}

Describe 'an apply to a settings.json that has no profiles object costs the user nothing' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            $script:shapeStyle = Join-Path $TestDrive 'styles/shape'
            New-Item -ItemType Directory -Path $script:shapeStyle -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:shapeStyle 'scheme.json'),
                '{"name":"shapescheme"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:shapeStyle 'theme.json'),
                '{"colorScheme":"shapescheme","opacity":90}', [System.Text.UTF8Encoding]::new($false))

            # TestDrive is shared across the Its in this file, and the positive
            # control below legitimately writes a style record. Clear it, or the
            # "no style was recorded" assertions pass or fail on test ORDER.
            Remove-Item -LiteralPath (Get-CurrentStyleRecordPath) -Force -ErrorAction SilentlyContinue

            $script:sPath = Join-Path $TestDrive 'settings.json'
            # A GOOD backup from an earlier, real apply: the thing a command
            # that cannot do its job must not spend.
            $script:goodBak = '{"THE-USERS-UNDO":"from their last real apply"}'
            [System.IO.File]::WriteAllText("$script:sPath.bak", $script:goodBak,
                [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath          { $script:sPath }
            Mock Get-TerminalKind             { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-StyleBundledBackground   { $null }
            Mock Write-Host                   {}
            Mock Write-Error                  {}
        }

        It 'leaves both files alone and claims nothing: <case>' -ForEach @(
            @{ case = 'no profiles key'
               live = @'
{
    // I keep my notes in here
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "schemes": []
}
'@ }
            @{ case = 'a null profiles key'
               live = @'
{
    // I keep my notes in here
    "profiles": null
}
'@ }
            @{ case = 'the legacy flat-array form'
               live = @'
{
    // I keep my notes in here
    "profiles": [ { "guid": "{a}", "name": "PowerShell" } ]
}
'@ }
        ) {
            [System.IO.File]::WriteAllText($script:sPath, $live, [System.Text.UTF8Encoding]::new($false))

            Apply-StyleDirect -StyleName 'shape' -Target 'defaults'

            [System.IO.File]::ReadAllText($script:sPath, [System.Text.UTF8Encoding]::new($false)) |
                Should -Be $live -Because @'
Write-SettingsFile re-serializes the PARSED object and ConvertFrom-WTJson has
already dropped every comment, so any write at all deletes the user's own notes.
'@
            [System.IO.File]::ReadAllText("$script:sPath.bak", [System.Text.UTF8Encoding]::new($false)) |
                Should -Be $script:goodBak -Because 'there is one .bak, and it is the undo of the last real apply'
            Should -Not -Invoke Write-Host -ParameterFilter { "$Object" -match 'Style applied' }
            Get-CurrentStyleRecord | Should -BeNullOrEmpty `
                -Because 'tstyles current must not name a style no profile received'
        }

        It 'leaves both files alone for a zero-byte settings.json' {
            # Separate from the table because the two engines fail it at
            # different points and both are correct: pwsh 7's ConvertFrom-Json
            # returns $null for an empty string and the target guard refuses it,
            # while Windows PowerShell 5.1 rejects the empty string outright and
            # ConvertFrom-WTJson's parse error stops the command earlier. What
            # has to be true on both is that nothing was written -- and it was
            # not: this shape reached the same crash and then overwrote
            # settings.json.bak with the empty file while printing "Backed up
            # settings to: ...".
            [System.IO.File]::WriteAllText($script:sPath, '', [System.Text.UTF8Encoding]::new($false))

            try { Apply-StyleDirect -StyleName 'shape' -Target 'defaults' } catch { }

            [System.IO.File]::ReadAllText($script:sPath, [System.Text.UTF8Encoding]::new($false)) | Should -Be ''
            [System.IO.File]::ReadAllText("$script:sPath.bak", [System.Text.UTF8Encoding]::new($false)) |
                Should -Be $script:goodBak
            Should -Not -Invoke Write-Host -ParameterFilter { "$Object" -match 'Style applied' }
        }

        It 'still applies to profiles.defaults on an ordinary settings.json' {
            # The positive control for the whole Describe: the fix must cost the
            # documented `-Target defaults` apply nothing.
            $live = '{ "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell" } ] }, "schemes": [] }'
            [System.IO.File]::WriteAllText($script:sPath, $live, [System.Text.UTF8Encoding]::new($false))

            Apply-StyleDirect -StyleName 'shape' -Target 'defaults'

            $after = [System.IO.File]::ReadAllText($script:sPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $after.profiles.defaults.colorScheme | Should -Be 'shapescheme'
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'Style applied' }
            [System.IO.File]::ReadAllText("$script:sPath.bak", [System.Text.UTF8Encoding]::new($false)) |
                Should -Be $live -Because 'a real apply is exactly when the rolling backup SHOULD be spent'
        }

        It 'does not write settings.json when the merge fails part-way' {
            # The amplifier, independent of which target got us there. PowerShell
            # aborts the failing STATEMENT and carries on, so `$settings =
            # Merge-...` left $settings holding the parsed-but-unmerged object
            # and Write-SettingsFile serialized it -- comments gone, "Style
            # applied" in green. Any future throw inside the merge would do the
            # same thing again, so the write is guarded rather than the one
            # throw being fixed.
            $live = @'
{
    // I keep my notes in here
    "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell" } ] }
}
'@
            [System.IO.File]::WriteAllText($script:sPath, $live, [System.Text.UTF8Encoding]::new($false))
            Mock Merge-StyleIntoSettings { throw 'the merge could not finish' }

            Apply-StyleDirect -StyleName 'shape' -Target 'PowerShell'

            [System.IO.File]::ReadAllText($script:sPath, [System.Text.UTF8Encoding]::new($false)) | Should -Be $live
            Should -Not -Invoke Write-Host -ParameterFilter { "$Object" -match 'Style applied' }
            Get-CurrentStyleRecord | Should -BeNullOrEmpty
        }
    }
}
