# Pester 5 tests: -NewWindow must stop importing a second copy of a profile.
#
# THE DEFECT. Open-AppleTerminalProfile was `& open $Path`. `open` on a
# .terminal file does not UPDATE a profile of the same name -- it imports a
# second one, and Terminal.app resolves the collision by appending a number. So
# every `tstyles <style> -NewWindow` added a permanent entry to the user's
# profile list. Found on a real machine with nine of them:
#
#   eva, eva 1, eva 2, eva 3, umbrella, umbrella 1, felitest, neon-rain, shorty
#
# Nothing deduplicated, nothing updated in place, and `tstyles uninstall` does
# not remove them either -- it promises not to touch Terminal.app's settings.
#
# Invoke-AppleTerminalScript is mocked in every test here. Without that the
# suite would drive the Terminal.app of whoever is running it: opening windows
# on their screen and deleting settings sets they own.
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

Describe 'Open-AppleTerminalProfile' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null

            $script:profilePath = Join-Path $script:TStylesDataRoot 'eva.terminal'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v1</plist>')

            $script:scripts = [System.Collections.ArrayList]::new()
            $script:opened  = [System.Collections.ArrayList]::new()
            $script:installedNames = @('Basic', 'Pro')

            Mock Invoke-AppleTerminalScript {
                [void]$script:scripts.Add($Script)
                if ($Script -match 'name of every settings set') {
                    return ($script:installedNames -join ', ')
                }
                return 'ok'
            }
            # The real `open`. Mocked as a function so no window is launched.
            function script:open { param($p) [void]$script:opened.Add("$p") }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'imports the file the first time, and records what it imported' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:opened | Should -Contain $script:profilePath
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeTrue `
                -Because 'the record is what makes the profile ours to replace later'
        }

        It 'opens the INSTALLED profile the second time, importing nothing' {
            # The whole defect: this call used to `open` the file again and
            # leave an 'eva 1' behind.
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:installedNames = @('Basic', 'Pro', 'eva')
            $script:opened.Clear()

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $script:opened.Count | Should -Be 0 -Because 'a second import is what created the duplicate'
            ($script:scripts -join "`n") | Should -Match 'current settings of t to settings set "eva"'
        }

        It 're-imports when the style changed, so a re-tuned style is not stale' {
            # The trade this fix must not make: reusing the installed profile
            # unconditionally would swap a duplicate for a window showing
            # colours the style no longer has.
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:installedNames = @('Basic', 'eva')
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2 RETUNED</plist>')
            $script:opened.Clear(); $script:scripts.Clear()

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            ($script:scripts -join "`n") | Should -Match 'delete settings set "eva"' `
                -Because 'deleting ours first keeps the re-import from being numbered'
            $script:opened | Should -Contain $script:profilePath
        }

        It 'never deletes a profile it did not import' {
            # No import record: this 'eva' is the user's own, named after a
            # style by coincidence. A numbered copy is the lesser harm.
            $script:installedNames = @('Basic', 'eva')
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            ($script:scripts -join "`n") | Should -Not -Match 'delete settings set' `
                -Because 'there is no proof that profile is ours'
            $script:opened | Should -Contain $script:profilePath
        }

        It 'falls back to open when Terminal.app cannot be asked' {
            # Nothing here may make the feature worse than the `& open` it replaced.
            Mock Invoke-AppleTerminalScript { $null }
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:opened | Should -Contain $script:profilePath
        }

        It 'falls back to open when Terminal.app refuses the window' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:installedNames = @('Basic', 'eva')
            $script:opened.Clear()
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'name of every settings set') { return ($script:installedNames -join ', ') }
                return $null   # the do-script arm fails
            }
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:opened | Should -Contain $script:profilePath `
                -Because 'a user asking for a window must still get one'
        }

        It 'still works when no name is given' {
            Open-AppleTerminalProfile -Path $script:profilePath
            $script:opened | Should -Contain $script:profilePath
        }
    }
}

Describe 'Get-AppleTerminalDuplicateProfile' {
    InModuleScope TerminalStyles {
        It 'finds the numbered copies of a known style' {
            @(Get-AppleTerminalDuplicateProfile `
                -InstalledName @('eva', 'eva 1', 'eva 2', 'Basic') `
                -StyleName @('eva')).Name | Should -Be @('eva 1', 'eva 2')
        }

        It 'never reports the unnumbered profile' {
            # It may be the user's own, and nothing can prove otherwise.
            @(Get-AppleTerminalDuplicateProfile -InstalledName @('eva') -StyleName @('eva')).Count |
                Should -Be 0
        }

        It 'ignores a numbered profile whose base is not a style' {
            @(Get-AppleTerminalDuplicateProfile `
                -InstalledName @('Pro 1', 'Ocean 2') -StyleName @('eva')).Count | Should -Be 0
        }

        It 'handles a style name containing a space' {
            @(Get-AppleTerminalDuplicateProfile `
                -InstalledName @('neon rain 1') -StyleName @('neon rain')).Name |
                Should -Be @('neon rain 1')
        }
    }
}

Describe 'tstyles profiles' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Get-TStylesPlatform { 'MacOS' }
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'eva' }) }
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'name of every settings set') { return 'Basic, eva, eva 1, eva 2' }
                return 'ok'
            }
        }

        It 'lists the duplicates without deleting anything' {
            Invoke-TerminalStyleProfiles
            $out = $script:written -join "`n"
            $out | Should -Match 'eva 1'
            $out | Should -Match 'tstyles profiles -Clean'
            Should -Not -Invoke Invoke-AppleTerminalScript -ParameterFilter {
                $Script -match 'delete settings set' }
        }

        It 'deletes nothing when consent is refused' {
            Mock Confirm-Action { $false }
            Invoke-TerminalStyleProfiles -Clean
            ($script:written -join "`n") | Should -Match 'Cancelled'
            Should -Not -Invoke Invoke-AppleTerminalScript -ParameterFilter {
                $Script -match 'delete settings set' }
        }

        It 'names every profile it will delete before asking' {
            # The rule the uninstall consent listing had to learn: a command may
            # not delete a thing it did not name.
            Mock Confirm-Action { $false }
            Invoke-TerminalStyleProfiles -Clean
            $out = $script:written -join "`n"
            $out | Should -Match 'eva 1'
            $out | Should -Match 'eva 2'
        }

        It 'deletes only the numbered copies once consent is given' {
            Mock Confirm-Action { $true }
            $script:calls = [System.Collections.ArrayList]::new()
            Mock Invoke-AppleTerminalScript {
                [void]$script:calls.Add($Script)
                if ($Script -match 'name of every settings set') {
                    # After the deletes, report them gone so the check passes.
                    if (($script:calls -join '') -match 'delete settings set') { return 'Basic, eva' }
                    return 'Basic, eva, eva 1, eva 2'
                }
                return 'ok'
            }
            Invoke-TerminalStyleProfiles -Clean
            $deletes = @($script:calls | Where-Object { $_ -match 'delete settings set' })
            $deletes.Count | Should -Be 2
            ($deletes -join "`n") | Should -Not -Match 'settings set "eva"$'
        }

        It 'says so plainly off macOS instead of pretending' {
            Mock Get-TStylesPlatform { 'Linux' }
            Invoke-TerminalStyleProfiles
            ($script:written -join "`n") | Should -Match 'macOS'
        }
    }
}

Describe 'the profiles command is reachable and documented' {
    InModuleScope TerminalStyles {
        It 'dispatches from Invoke-TerminalStyle' {
            (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() |
                Should -Match "Arg -eq 'profiles'"
        }
        It 'has a help topic' {
            $h = Get-TerminalStyleHelpData | Where-Object Name -eq 'profiles'
            $h | Should -Not -BeNullOrEmpty
            ($h.Detail -join ' ') | Should -Match 'Terminal\.app'
        }
        It 'is in the known-subcommand list, so it is not read as a style name' {
            # The VALUE, not the source text: the list is a script variable, and
            # asserting on where it is written would pass or fail on layout.
            $script:TStylesSubcommands | Should -Contain 'profiles'
        }
    }
}
