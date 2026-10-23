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
# THE SECOND DEFECT. That fix keeps an import record, so that only a profile
# TerminalStyles imported is ever reused or deleted -- and then wrote it after
# every `open`, including where the import cannot land on the style's name:
# beside a same-named profile it had no record of, and after a delete of its
# own out-of-date copy that did not go through. Terminal.app files those
# imports as 'eva 1', but the record said 'eva', so the next run opened a
# window on the user's own 'eva', and the first run after the style changed
# deleted it. Remove-AppleTerminalSettingsSet had the matching hole: a
# follow-up query that got no answer read as an empty profile list, so a
# delete nobody saw counted as done. The Describe for this runs against a
# stand-in Terminal.app that keeps state: it names an import after its file,
# numbers an exact-name collision ('eva 1', 'eva 2'), and records which
# profile's content each window shows. One caveat: the stand-in numbers EVERY
# collision, identical content included, whereas Terminal.app's import code
# (read from its binary, never driven live) reuses an identical same-named
# profile. No assertion depends on that difference, but the copy counts it
# produces are not a measurement of Terminal.app.
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

            # Keeps the notes Open-AppleTerminalProfile prints off the runner's console.
            Mock Write-Host {}
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

Describe 'Open-AppleTerminalProfile against a Terminal.app that keeps state' {
    # A Describe of its own, so these tests do not depend on how Pester orders
    # a nested BeforeEach's mocks against the stateless ones above.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null

            $script:profilePath = Join-Path $script:TStylesDataRoot 'eva.terminal'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v1</plist>')

            # Terminal.app's profiles, in its own order, and what each one holds.
            $script:sets = [System.Collections.ArrayList]::new()
            [void]$script:sets.Add([pscustomobject]@{ Name = 'Basic'; Content = 'builtin' })
            [void]$script:sets.Add([pscustomobject]@{ Name = 'Pro';   Content = 'builtin' })
            # The content each window opened on, in order.
            $script:windows = [System.Collections.ArrayList]::new()
            $script:opened  = [System.Collections.ArrayList]::new()
            $script:scripts = [System.Collections.ArrayList]::new()
            $script:written = [System.Collections.ArrayList]::new()
            $script:refuseDelete = $false

            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Invoke-AppleTerminalScript {
                [void]$script:scripts.Add($Script)
                if ($Script -ceq 'tell application "Terminal" to get name of every settings set') {
                    return (@($script:sets | ForEach-Object { $_.Name }) -join ', ')
                }
                $m = [regex]::Match($Script,
                    '^tell application "Terminal" to delete settings set "(?<n>(?:[^"\\]|\\.)*)"$')
                if ($m.Success) {
                    if ($script:refuseDelete) { return $null }
                    $n      = $m.Groups['n'].Value -replace '\\(.)', '$1'
                    $before = $script:sets.Count
                    # By position, so no engine's idea of object equality decides
                    # which profile goes.
                    for ($i = $script:sets.Count - 1; $i -ge 0; $i--) {
                        if ($script:sets[$i].Name -ceq $n) { $script:sets.RemoveAt($i) }
                    }
                    if ($script:sets.Count -eq $before) { return $null }
                    return ''
                }
                $m = [regex]::Match($Script,
                    'set current settings of t to settings set "(?<n>(?:[^"\\]|\\.)*)"')
                if ($m.Success) {
                    $n   = $m.Groups['n'].Value -replace '\\(.)', '$1'
                    $hit = @($script:sets | Where-Object { $_.Name -ceq $n })
                    if ($hit.Count -eq 0) { return $null }
                    [void]$script:windows.Add($hit[0].Content)
                    return 'ok'
                }
                # Loudly, so a change to the production AppleScript fails here
                # instead of making the assertions below vacuous.
                throw "The Terminal.app stand-in does not know this AppleScript: $Script"
            }
            # `open` on a .terminal file: imported under the file's name, numbered
            # on an exact-name collision, and a window opened on the import.
            function script:open {
                param($p)
                $content = [System.IO.File]::ReadAllText($p)
                $base = [System.IO.Path]::GetFileNameWithoutExtension($p)
                $name = $base
                $i = 0
                while (@($script:sets | Where-Object { $_.Name -ceq $name }).Count -gt 0) {
                    $i++
                    $name = '{0} {1}' -f $base, $i
                }
                [void]$script:sets.Add([pscustomobject]@{ Name = $name; Content = $content })
                [void]$script:windows.Add($content)
                [void]$script:opened.Add("$p")
            }
            # On macOS /usr/bin/open would drive the real Terminal.app, and a
            # Linux image may have an `open` binary of its own.
            if ((Get-Command open).CommandType -ne 'Function') {
                throw '`open` does not resolve to the stand-in; refusing to run.'
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'does not record a profile it did not import' {
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            # It got past both fallbacks to the import, which also run `open`.
            $script:scripts | Should -Contain 'tell application "Terminal" to get name of every settings set'
            @($script:sets | Where-Object { $_.Name -ceq 'eva 1' } | ForEach-Object { $_.Content }) |
                Should -Be @('<plist>v1</plist>') -Because 'the import lands beside the profile it found'
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeFalse `
                -Because "the import is 'eva 1'; a record saying 'eva' would claim the user's own profile"
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match 'cannot prove it imported'
        }

        It 'never opens a window on a profile it did not import, on a later run' {
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $script:windows.Count | Should -Be 2 -Because 'each call must still deliver a window'
            $script:windows | Should -Not -Contain 'USER'
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) |
                Should -Be @('USER')
        }

        It 'never deletes a profile it did not import, even after the style changes' {
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            # By content, not by name: a delete followed by a re-import leaves a
            # profile called 'eva' too.
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) |
                Should -Be @('USER') -Because 'there is no proof that profile is ours'
            @($script:scripts | Where-Object { $_ -cmatch 'delete settings set "eva"' }).Count | Should -Be 0
            $script:windows.Count | Should -Be 3
        }

        It 'a delete that does not go through keeps the old hash, so the old profile is never reused' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $v1 = Get-AppleTerminalProfileHash -Path $script:profilePath
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:refuseDelete = $true
            $script:windows.Clear()

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            (Get-AppleTerminalImportRecord)['eva'] | Should -Be $v1 `
                -Because "the import landed as 'eva 1', so 'eva' still holds the old style"
            $script:windows.Count | Should -Be 2
            $script:windows | Should -Not -Contain '<plist>v1</plist>'
        }

        It 'replaces its own out-of-date copy, records the new hash, and reuses it' {
            # The control for the two above: where the delete is confirmed, the
            # re-import lands on the name and is recorded, so the next run
            # reuses it instead of deleting and importing again.
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            (Get-AppleTerminalImportRecord)['eva'] | Should -Be (Get-AppleTerminalProfileHash -Path $script:profilePath)
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) |
                Should -Be @('<plist>v2</plist>')
            @($script:sets | Where-Object { $_.Name -ceq 'eva 1' }).Count | Should -Be 0
            $openedBefore = $script:opened.Count

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $script:opened.Count | Should -Be $openedBefore -Because 'an up-to-date import is reused, not imported again'
            $script:windows[$script:windows.Count - 1] | Should -Be '<plist>v2</plist>'
        }

        It 'does not trust an import record written before 0.9.3' {
            # 0.8.24-0.9.2 wrote this file after every `open`, so an entry in it
            # may be a claim on a profile TerminalStyles never imported.
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })
            $v1 = Get-AppleTerminalProfileHash -Path $script:profilePath
            [System.IO.File]::WriteAllText((Join-Path $script:TStylesDataRoot '.appleterminal-imported.json'),
                ('{"eva":"' + $v1 + '"}'), [System.Text.UTF8Encoding]::new($false))

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $script:windows | Should -Not -Contain 'USER'
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) |
                Should -Be @('USER')
            $script:windows.Count | Should -Be 2
        }

        It 'says why when a profile it cannot prove it imported already has the name' {
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            # Collapsed, because the sentence spans Write-Host lines.
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match "named 'eva' that TerminalStyles cannot prove it imported"
            $said | Should -Match 'Rename or delete that'
            $said | Should -Match 'profiles -Clean'
        }

        It 'adds no note when the name is free' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Not -Match 'cannot prove it imported'
            $script:opened.Count | Should -Be 1
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeTrue
        }

        It 'says so when its own out-of-date copy is not confirmed deleted' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:refuseDelete = $true

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match "did not confirm that it deleted TerminalStyles' out-of-date 'eva' profile"
        }

        It 'never records a name Terminal.app cannot list intact: "<Style>"' -ForEach @(
            @{ Style = 'Tokyo, Night' }
            @{ Style = 'eva ' }
        ) {
            # Terminal.app joins the names with ', ' and the lister splits and
            # trims them, so neither name is ever seen -- a profile of the user's
            # own by that name looks free.
            $path = Join-Path $script:TStylesDataRoot ('{0}.terminal' -f $Style)
            [System.IO.File]::WriteAllText($path, '<plist>v1</plist>')
            [void]$script:sets.Add([pscustomobject]@{ Name = $Style; Content = 'USER' })

            Open-AppleTerminalProfile -Path $path -Name $Style

            $script:scripts | Should -Contain 'tell application "Terminal" to get name of every settings set'
            @($script:sets | Where-Object { $_.Name -ceq ('{0} 1' -f $Style) }).Count | Should -Be 1 `
                -Because 'the import lands numbered, beside the profile the lister could not show'
            (Get-AppleTerminalImportRecord).ContainsKey($Style) | Should -BeFalse
        }

        It 'does not record a name the import cannot land on' {
            # Terminal.app names an import after its file, so eva.terminal lands
            # on 'eva' whatever -Name says.
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'umbrella'

            @($script:sets | Where-Object { $_.Name -ceq 'eva' }).Count | Should -Be 1
            (Get-AppleTerminalImportRecord).ContainsKey('umbrella') | Should -BeFalse
        }
    }
}

Describe 'Remove-AppleTerminalSettingsSet' {
    InModuleScope TerminalStyles {
        It 'does not call a profile gone when Terminal.app does not answer afterwards' {
            # Neither the delete nor the follow-up query gets an answer. An empty
            # list is what the lister returns then, so it proves nothing.
            Mock Invoke-AppleTerminalScript { $null }

            Remove-AppleTerminalSettingsSet -Name 'eva 1' | Should -BeFalse

            Should -Invoke Invoke-AppleTerminalScript -Times 2 -Exactly
        }

        It 'calls it gone when Terminal.app answers without it' {
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'name of every settings set') { return 'Basic, Pro' }
                return ''
            }
            Remove-AppleTerminalSettingsSet -Name 'eva 1' | Should -BeTrue
        }

        It 'does not call it gone while Terminal.app still lists it' {
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'name of every settings set') { return 'Basic, eva 1' }
                return ''
            }
            Remove-AppleTerminalSettingsSet -Name 'eva 1' | Should -BeFalse
        }

        It 'never confirms a name the lister cannot return intact' {
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'name of every settings set') { return 'Basic, Pro' }
                return ''
            }

            Remove-AppleTerminalSettingsSet -Name 'Tokyo, Night' | Should -BeFalse

            Should -Invoke Invoke-AppleTerminalScript -ParameterFilter {
                $Script -match 'delete settings set' } -Times 1 -Exactly
        }
    }
}

Describe 'Get-AppleTerminalSettingsSetName and the names it can list' {
    # What couples the two: change the lister without the helper, or the
    # helper without the lister, and a case below flips.
    InModuleScope TerminalStyles {
        It 'calls "<N>" listable exactly when the lister returns it intact' -ForEach @(
            @{ N = 'eva' }
            @{ N = 'neon rain' }
            @{ N = 'Tokyo, Night' }
            @{ N = 'eva ' }
            @{ N = ' eva' }
        ) {
            $script:answerName = $N
            Mock Invoke-AppleTerminalScript { 'Basic, ' + $script:answerName }

            $listed = @(Get-AppleTerminalSettingsSetName)

            $listed | Should -Contain 'Basic' -Because 'the lister answered'
            (Test-AppleTerminalSettingsSetNameListable -Name $N) | Should -Be ($listed -ccontains $N)
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

        It 'does not date every numbered profile to before the fix' {
            # A current -NewWindow still adds one beside a profile it cannot
            # prove it imported, and a user's own 'eva 2' is a copy of nothing.
            Invoke-TerminalStyleProfiles
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match 'eva 1'
            $said | Should -Match 'Numbered profiles named after a style'
            $said | Should -Not -Match 'before this was fixed'
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

        It 'does not report a removal Terminal.app did not confirm' {
            # Set here, so a value left in module scope cannot satisfy the check.
            $script:sentDelete = $false
            Mock Confirm-Action { $true }
            Mock Invoke-AppleTerminalScript {
                if ($Script -ceq 'tell application "Terminal" to get name of every settings set') {
                    # Answers until a delete is sent, then goes quiet.
                    if ($script:sentDelete) { return $null }
                    return 'Basic, eva, eva 1'
                }
                if ($Script -match 'delete settings set') {
                    $script:sentDelete = $true
                    return $null
                }
                throw "unexpected AppleScript: $Script"
            }

            Invoke-TerminalStyleProfiles -Clean

            $script:sentDelete | Should -BeTrue -Because 'the delete was attempted, or this measures nothing'
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Not -CMatch 'Removed eva 1'
            $said | Should -Match 'could not confirm eva 1 was removed'
            $said | Should -Match 'Terminal\.app confirmed 0 of 1 removed'
            $said | Should -Match 'Run tstyles profiles to see which are still listed'
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
        It 'says when a run can still add a numbered copy' {
            # "Before this was fixed" alone reads as the whole story, and a run
            # beside a profile it cannot prove it imported still adds one.
            $h = Get-TerminalStyleHelpData | Where-Object Name -eq 'profiles'
            (($h.Detail -join ' ') -replace '\s+', ' ') | Should -Match 'cannot prove it imported'
        }
        It 'is in the known-subcommand list, so it is not read as a style name' {
            # The VALUE, not the source text: the list is a script variable, and
            # asserting on where it is written would pass or fail on layout.
            $script:TStylesSubcommands | Should -Contain 'profiles'
        }
    }
}
