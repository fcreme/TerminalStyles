# Pester 5 tests: settings.json.bak may only be written once the operation is
# known to be possible, and settings.json may only be rewritten when something
# actually changed.
#
# THE RULE. Taking the rolling backup is itself destructive: there is ONE .bak,
# so writing it consumes the user's undo of their last real apply. A command
# that turns out to do nothing must not spend it.
#
# 0.8.17 established this for Apply-StyleDirect's -Target. The same rule was
# broken three more ways:
#   * Reset-StyleDirect copied settings.json over the .bak and only THEN
#     resolved the profile, so `tstyles reset -Target <typo>` printed
#     "nothing to reset" over the wreckage of the undo.
#   * Invoke-TerminalStyleFont did the same for `tstyles font <name> -Target <typo>`.
#   * Merge-StyleIntoSettings returns the settings UNTOUCHED for a style with no
#     theme.json -- a shape README documents as legal -- and every caller wrote
#     them anyway, re-serializing the parsed object and dropping every JSONC
#     comment the user wrote, while reporting success in green.
# And a reset on a never-styled profile rewrote settings.json (losing the
# comments) while printing "already plain".
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

Describe 'the rolling backup is not spent on a command that does nothing' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            $script:sPath = Join-Path $TestDrive 'settings.json'
            $script:live = @'
{
    // the user's own note, which no command may eat
    "profiles": { "list": [ { "name": "PowerShell", "guid": "{x}" } ] },
    "schemes": []
}
'@
            [System.IO.File]::WriteAllText($script:sPath, $script:live, [System.Text.UTF8Encoding]::new($false))

            # A GOOD backup from an earlier, real apply. This is the thing that
            # must survive a command that turns out to be a no-op.
            $script:goodBak = '{"THE-USERS-UNDO":"from their last real apply"}'
            [System.IO.File]::WriteAllText("$script:sPath.bak", $script:goodBak, [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath { $script:sPath }
            Mock Get-TerminalKind    { 'WindowsTerminal' }
            Mock Write-Host          {}
            Mock Write-Error         {}
        }

        It 'reset with a bad -Target keeps the previous backup' {
            Reset-StyleDirect -Target 'NoSuchProfile'
            [System.IO.File]::ReadAllText("$script:sPath.bak") | Should -Be $script:goodBak `
                -Because 'a typo must not cost the user the undo of their last real apply'
        }

        It 'reset with a bad -Target leaves settings.json byte-identical' {
            Reset-StyleDirect -Target 'NoSuchProfile'
            [System.IO.File]::ReadAllText($script:sPath) | Should -Be $script:live
        }

        It 'reset on a never-styled profile does not rewrite settings.json' {
            # It printed "'PowerShell' had no TerminalStyles fields -- already
            # plain." and then rewrote the file anyway, which strips the JSONC
            # comments. The most likely way a curious user tries this command
            # was also the one that cost them their comments.
            Reset-StyleDirect -Target 'PowerShell'
            [System.IO.File]::ReadAllText($script:sPath) | Should -Be $script:live `
                -Because 'a reset that strips nothing must write nothing'
            [System.IO.File]::ReadAllText($script:sPath) | Should -Match "the user's own note"
        }

        It 'applying a style with no theme.json writes nothing and keeps the backup' {
            # scheme.json only: legal per README, and nothing for settings.json.
            $styleDir = Join-Path $TestDrive 'styles/schemeonly'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'),
                '{"name":"schemeonly"}', [System.Text.UTF8Encoding]::new($false))

            Apply-StyleDirect -StyleName 'schemeonly' -Target 'PowerShell'

            [System.IO.File]::ReadAllText($script:sPath) | Should -Be $script:live `
                -Because 'the merge had nothing to merge, so the write must not happen'
            [System.IO.File]::ReadAllText("$script:sPath.bak") | Should -Be $script:goodBak `
                -Because 'and the backup must not be spent on it either'
        }

        It 'font with a bad -Target keeps the previous backup' {
            Mock Get-FontCatalog       { @([pscustomobject]@{ name='jb'; family='JetBrains Mono'; license='OFL'; url='x'; sha256='y' }) }
            Mock Test-FontInstalled    { $true }
            Mock Get-TerminalCapability { [pscustomobject]@{ Font = $true } }

            Invoke-TerminalStyleFont -Name 'jb' -Target 'NoSuchProfile'

            [System.IO.File]::ReadAllText("$script:sPath.bak") | Should -Be $script:goodBak
            [System.IO.File]::ReadAllText($script:sPath)       | Should -Be $script:live
        }
    }
}

Describe 'Save-SettingsBackup makes the rule structural' {
    InModuleScope TerminalStyles {
        It 'refuses to run before the target is known valid' {
            # -ResolvedTarget is Mandatory ON PURPOSE. A caller cannot take the
            # backup before resolving, because it has nothing to pass until it
            # has -- which is what turns a convention into an invariant. A name
            # lint would have let a sixth caller re-introduce the whole class.
            $p = Join-Path $TestDrive 's.json'
            [System.IO.File]::WriteAllText($p, '{}')
            $settings = '{"profiles":{"list":[{"name":"PowerShell"}]}}' | ConvertFrom-Json
            $bad = Resolve-WTProfileTarget -Settings $settings -TargetName 'Nope'

            { Save-SettingsBackup -Path $p -ResolvedTarget $bad } | Should -Throw
            Test-Path -LiteralPath "$p.bak" | Should -BeFalse
        }

        It 'writes the backup once the target resolves' {
            $p = Join-Path $TestDrive 's2.json'
            [System.IO.File]::WriteAllText($p, '{"hello":true}')
            $settings = '{"profiles":{"list":[{"name":"PowerShell"}]}}' | ConvertFrom-Json
            $ok = Resolve-WTProfileTarget -Settings $settings -TargetName 'PowerShell'

            Save-SettingsBackup -Path $p -ResolvedTarget $ok -Quiet
            [System.IO.File]::ReadAllText("$p.bak") | Should -Be '{"hello":true}'
        }
    }
}

Describe 'every caller resolves before it backs up' {
    # The source-order lint. The structural guard above stops a caller taking a
    # backup with no resolved target; this stops one that resolves AFTER. Both
    # are needed: the picker's console guard was present and ineffective for
    # exactly this reason -- it sat below the prompt it was meant to protect.
    It 'Save-SettingsBackup never appears above Resolve-WTProfileTarget in a function' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $files = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
            Where-Object { $_.FullName -notmatch '[\\/](tests|out)[\\/]' }

        $checked = 0
        $offenders = @()
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $fns = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
            foreach ($fn in $fns) {
                # Its own definition mentions its own name; it is the writer,
                # not a caller.
                if ($fn.Name -eq 'Save-SettingsBackup') { continue }
                $body = $fn.Extent.Text
                $bak = $body.IndexOf('Save-SettingsBackup')
                if ($bak -lt 0) { continue }
                $checked++
                $res = $body.IndexOf('Resolve-WTProfileTarget')
                if ($res -lt 0 -or $res -gt $bak) {
                    $offenders += "$($f.Name)::$($fn.Name)"
                }
            }
        }

        $checked | Should -BeGreaterThan 2 -Because 'the lint must actually be inspecting callers'
        $offenders -join ', ' | Should -BeNullOrEmpty -Because @'
the rolling backup consumes the user's undo, so it must be taken only after the
target has been resolved and found valid.
'@
    }
}

Describe 'the test suite itself still parses' {
    # A parse error in a test file does not fail the run -- Pester drops that
    # file's tests and reports GREEN with a smaller total. That happened while
    # writing these tests: a bad edit silently removed 4 assertions and the
    # suite still said 0 failures. A shrinking suite is invisible; this makes
    # it loud.
    #
    # One assertion over every file rather than one per file: 85 always-passing
    # cases would inflate the suite count without adding a single signal, and
    # this file's other lints already work this way.
    It 'every test file parses, or its tests vanish silently' {
        $testDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'
        $files = @(Get-ChildItem -LiteralPath $testDir -Filter '*.Tests.ps1' -File)
        $files.Count | Should -BeGreaterThan 50 -Because 'the scan must actually be scanning the suite'

        $broken = @()
        foreach ($f in $files) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors) | Out-Null
            if (@($errors).Count) { $broken += "$($f.Name): $($errors[0].Message)" }
        }
        $broken -join "`n" | Should -BeNullOrEmpty
    }
}
