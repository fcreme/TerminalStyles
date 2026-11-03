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
# produces are not a measurement of Terminal.app. Its delete rules are
# Terminal 2.15's, read from its binary (-[TTProfileManager setProfiles:]) and
# never driven live: a deleted default profile is replaced by the first in the
# list, a deleted startup profile by the default, and every tab on a deleted
# profile switches to the default.
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
                if ($Script -match 'settingsSets\.name') {
                    return (ConvertTo-Json -Compress -InputObject @(@($script:installedNames) | ForEach-Object { '=' + $_ }))
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
                if ($Script -match 'settingsSets\.name') { return (ConvertTo-Json -Compress -InputObject @(@($script:installedNames) | ForEach-Object { '=' + $_ })) }
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
            # The roles a profile can hold, and the open tabs (by profile name).
            $script:defaultSet = 'Basic'
            $script:startupSet = 'Basic'
            $script:tabs = [System.Collections.ArrayList]::new()
            $script:refuseUse = $false
            $script:refuseWindow = $false

            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Invoke-AppleTerminalScript {
                [void]$script:scripts.Add($Script)
                if ($Script -match 'settingsSets\.name') {
                    return (ConvertTo-Json -Compress -InputObject @(@($script:sets | ForEach-Object { $_.Name }) | ForEach-Object { '=' + $_ }))
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
                    # Terminal 2.15's rules for the roles the deleted profile held.
                    if ($script:defaultSet -ceq $n) { $script:defaultSet = $script:sets[0].Name }
                    if ($script:startupSet -ceq $n) { $script:startupSet = $script:defaultSet }
                    for ($i = 0; $i -lt $script:tabs.Count; $i++) {
                        if ($script:tabs[$i] -ceq $n) { $script:tabs[$i] = $script:defaultSet }
                    }
                    return ''
                }
                $m = [regex]::Match($Script,
                    'set p to id of settings set "(?<n>(?:[^"\\]|\\.)*)"')
                if ($m.Success -and $Script.Contains('id of default settings') -and $Script.Contains('id of startup settings')) {
                    if ($script:refuseUse) { return $null }
                    $n = $m.Groups['n'].Value -replace '\\(.)', '$1'
                    if (@($script:sets | Where-Object { $_.Name -ceq $n }).Count -eq 0) { return $null }
                    $t = @($script:tabs | Where-Object { $_ -ceq $n }).Count
                    return ('use:{0},{1},{2}' -f ($script:defaultSet -ceq $n).ToString().ToLowerInvariant(),
                            ($script:startupSet -ceq $n).ToString().ToLowerInvariant(), $t)
                }
                $m = [regex]::Match($Script,
                    'set current settings of t to settings set "(?<n>(?:[^"\\]|\\.)*)"')
                if ($m.Success) {
                    if ($script:refuseWindow) { return $null }
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
            @($script:scripts | Where-Object { $_ -match 'settingsSets\.name' }).Count | Should -BeGreaterThan 0
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

        It 'forgets its import once Terminal.app no longer lists it, so a later profile of that name is not claimed' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeTrue -Because 'control: the import is recorded'
            # The user deletes it in Terminal's Settings, and some later command
            # lists the profiles before they make one of their own.
            for ($i = $script:sets.Count - 1; $i -ge 0; $i--) { if ($script:sets[$i].Name -ceq 'eva') { $script:sets.RemoveAt($i) } }
            $other = Join-Path $script:TStylesDataRoot 'forest.terminal'
            [System.IO.File]::WriteAllText($other, '<plist>forest</plist>')
            Open-AppleTerminalProfile -Path $other -Name 'forest'
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeFalse
            (Get-AppleTerminalImportRecord).ContainsKey('forest') | Should -BeTrue

            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva'; Content = 'USER' })
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:windows.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('USER')
            @($script:scripts | Where-Object { $_ -cmatch 'delete settings set "eva"' }).Count | Should -Be 0
            $script:windows | Should -Not -Contain 'USER'
        }

        It 'keeps its import record when Terminal.app gives no list' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            Sync-AppleTerminalRecord -Installed @()
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeTrue
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

        It 'leaves its out-of-date profile alone while Terminal.app uses it as <Use>' -ForEach @(
            @{ Use = 'the default profile' }
            @{ Use = 'the startup profile' }
        ) {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $v1 = Get-AppleTerminalProfileHash -Path $script:profilePath
            if ($Use -eq 'the default profile') { $script:defaultSet = 'eva' } else { $script:startupSet = 'eva' }
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:windows.Clear()

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            if ($Use -eq 'the default profile') { $script:defaultSet | Should -BeExactly 'eva' } else { $script:startupSet | Should -BeExactly 'eva' }
            @($script:scripts | Where-Object { $_ -cmatch 'delete settings set "eva"' }).Count | Should -Be 0
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v1</plist>')
            @($script:windows) | Should -Be @('<plist>v1</plist>') -Because 'one window, on the profile as it is'
            @($script:sets | Where-Object { $_.Name -cmatch '^eva \d+$' }).Count | Should -Be 0
            (Get-AppleTerminalImportRecord)['eva'] | Should -Be $v1 -Because 'the next run asks again'
            @($script:scripts | Where-Object { $_ -match 'settingsSets\.name' }).Count | Should -BeGreaterThan 0
        }

        It 'says what it is used as, and what to change for it to be replaced' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:defaultSet = 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:written.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match "using its 'eva' profile as your default profile"
            $said | Should -Match 'left as it is'
            $said | Should -Match 'Settings > Profiles'
            $said | Should -Not -Match 'startup profile' -Because 'the startup profile is not eva here'

            # Doing what it says lets the next run replace it.
            $script:defaultSet = 'Basic'
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v2</plist>')
        }

        It 'leaves it alone when Terminal.app does not say what is using it' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $script:refuseUse = $true
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:windows.Clear()
            $script:written.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            @($script:scripts | Where-Object { $_ -cmatch 'delete settings set "eva"' }).Count | Should -Be 0
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v1</plist>')
            @($script:windows) | Should -Be @('<plist>v1</plist>')
            (($script:written -join ' ') -replace '\s+', ' ') | Should -Match 'did not say whether its'
        }

        It 'does not claim a window on a kept profile that Terminal.app would not open' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            $v1 = Get-AppleTerminalProfileHash -Path $script:profilePath
            $script:defaultSet = 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:windows.Clear()
            $script:written.Clear()
            $openedBefore = $script:opened.Count
            $script:refuseWindow = $true

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            $script:opened.Count | Should -Be ($openedBefore + 1)
            @($script:sets | Where-Object { $_.Name -ceq 'eva 1' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v2</plist>')
            (Get-AppleTerminalImportRecord)['eva'] | Should -Be $v1
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Not -Match 'opens on it'
            $said | Should -Match 'numbered copy'
        }

        It 'replaces it when only open tabs use it, and says those tabs switched' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [void]$script:tabs.Add('eva'); [void]$script:tabs.Add('eva')
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:written.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v2</plist>')
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match 'was older than the style, so it was deleted'
            $said | Should -Match "2 open tabs on it switched to Terminal.app's default profile"
        }

        It 'still replaces a profile nothing is using, and says what that costs' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:written.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v2</plist>')
            (Get-AppleTerminalImportRecord)['eva'] | Should -Be (Get-AppleTerminalProfileHash -Path $script:profilePath)
            $said = ($script:written -join ' ') -replace '\s+', ' '
            $said | Should -Match 'was older than the style, so it was deleted'
            $said | Should -Match 'did not carry over'
            $said | Should -Not -Match 'switched'
        }

        It 'deletes neither its out-of-date profile nor a case-variant beside it' {
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            [void]$script:sets.Insert(0, [pscustomobject]@{ Name = 'Eva'; Content = 'USER' })
            [System.IO.File]::WriteAllText($script:profilePath, '<plist>v2</plist>')
            $script:written.Clear()
            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'
            @($script:scripts | Where-Object { $_ -match 'delete settings set' }).Count | Should -Be 0
            @($script:sets | Where-Object { $_.Name -ceq 'Eva' } | ForEach-Object { $_.Content }) | Should -Be @('USER')
            @($script:sets | Where-Object { $_.Name -ceq 'eva' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v1</plist>')
            (($script:written -join ' ') -replace '\s+', ' ') | Should -Match "has 'Eva' beside"
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

        It "a style named '<Style>' is recorded and reused like any other" -ForEach @(
            @{ Style = 'Tokyo, Night' }
            @{ Style = 'eva ' }
        ) {
            # AppleScript joined the names with ', ', and the old lister split
            # and trimmed them, so neither name was ever seen. JXA returns them
            # exactly.
            $path = Join-Path $script:TStylesDataRoot ('{0}.terminal' -f $Style)
            [System.IO.File]::WriteAllText($path, '<plist>v1</plist>')

            Open-AppleTerminalProfile -Path $path -Name $Style
            Open-AppleTerminalProfile -Path $path -Name $Style

            $script:opened.Count | Should -Be 1
            @($script:sets | Where-Object { $_.Name -ceq $Style }).Count | Should -Be 1
            @($script:sets | Where-Object { $_.Name -ceq ('{0} 1' -f $Style) }).Count | Should -Be 0
            @((Get-AppleTerminalImportRecord).Keys) -ccontains $Style | Should -BeTrue
        }

        It '-NewWindow records the copy Terminal.app files beside a profile it cannot claim' {
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva';   Content = 'USER' })
            [void]$script:sets.Add([pscustomobject]@{ Name = 'eva 1'; Content = 'USER-DUP' })
            Mock Start-Sleep { }

            Open-AppleTerminalProfile -Path $script:profilePath -Name 'eva'

            @($script:sets | Where-Object { $_.Name -ceq 'eva 2' } | ForEach-Object { $_.Content }) | Should -Be @('<plist>v1</plist>')
            (@((Get-AppleTerminalImportRecord -Copies).Keys) -join ',') | Should -BeExactly 'eva 2'
            (Get-AppleTerminalImportRecord).ContainsKey('eva') | Should -BeFalse
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
                if ($Script -match 'settingsSets\.name') { return '["=Basic","=Pro"]' }
                return ''
            }
            Remove-AppleTerminalSettingsSet -Name 'eva 1' | Should -BeTrue
        }

        It 'does not call it gone while Terminal.app still lists it' {
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'settingsSets\.name') { return '["=Basic","=eva 1"]' }
                return ''
            }
            Remove-AppleTerminalSettingsSet -Name 'eva 1' | Should -BeFalse
        }

        It 'confirms a comma-named profile gone once Terminal.app lists without it' {
            Mock Invoke-AppleTerminalScript {
                if ($Script -match 'settingsSets\.name') { return '["=Basic","=Work, eva 1"]' }
                return ''
            }

            Remove-AppleTerminalSettingsSet -Name 'Tokyo, Night' | Should -BeTrue

            Should -Invoke Invoke-AppleTerminalScript -ParameterFilter {
                $Script -match 'delete settings set' } -Times 1 -Exactly
        }
    }
}

Describe 'Get-AppleTerminalSettingsSetName' {
    InModuleScope TerminalStyles {
        It 'returns names exactly, commas, edge spaces and date-like names included' {
            Mock Invoke-AppleTerminalScript { '["=Basic","=Work, eva 2","=eva 3 ","= Pro","=2026-10-24T10:00:00Z"]' }
            (@(Get-AppleTerminalSettingsSetName) | ForEach-Object { "[$_]" }) -join '' |
                Should -BeExactly '[Basic][Work, eva 2][eva 3 ][ Pro][2026-10-24T10:00:00Z]'
            Should -Invoke Invoke-AppleTerminalScript -ParameterFilter { $Language -eq 'JavaScript' }
        }

        It 'outputs nothing without an answer, or with one it cannot read: <Label>' -ForEach @(
            @{ Label = 'no answer'; Answer = $null }
            @{ Label = 'not JSON';  Answer = 'Basic, Pro' }
            @{ Label = 'unprefixed'; Answer = '["Basic"]' }
        ) {
            $script:answer = $Answer
            Mock Invoke-AppleTerminalScript { $script:answer }
            @(Get-AppleTerminalSettingsSetName).Count | Should -Be 0 -Because '@() counts a returned $null as one name'
        }
    }
}

Describe 'Register-AppleTerminalImportCopy' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            Mock Start-Sleep { }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'records nothing it cannot attribute: <Label>' -ForEach @(
            @{ Label = 'two new profiles';     After = @('Basic', 'eva', 'eva 1', 'eva 2') }
            @{ Label = 'another shape';        After = @('Basic', 'eva', 'Eva 1') }
            @{ Label = 'nothing new';          After = @('Basic', 'eva') }
        ) {
            $script:after = $After
            Mock Get-AppleTerminalSettingsSetName { $script:after }
            Register-AppleTerminalImportCopy -Name 'eva' -Hash 'h' -Before @('Basic', 'eva')
            [System.IO.File]::Exists((Get-AppleTerminalImportRecordPath -Copies)) | Should -BeFalse
            Should -Invoke Get-AppleTerminalSettingsSetName -Times 1
        }

        It 'records the one new copy, compared against the list as it was before the open' {
            Mock Get-AppleTerminalSettingsSetName { @('Basic', 'eva', 'eva 1') }
            Register-AppleTerminalImportCopy -Name 'eva' -Hash 'h' -Before @('Basic', 'eva')
            (@((Get-AppleTerminalImportRecord -Copies).Keys) -join ',') | Should -BeExactly 'eva 1'
        }
    }
}

Describe 'Get-AppleTerminalSettingsSetUse' {
    InModuleScope TerminalStyles {
        It 'reads what Terminal.app answers' {
            $script:answer = 'use:true,false,2'
            Mock Invoke-AppleTerminalScript { $script:answer }
            $u = Get-AppleTerminalSettingsSetUse -Name 'eva'
            $u.Answered | Should -BeTrue; $u.Default | Should -BeTrue; $u.Startup | Should -BeFalse; $u.Tabs | Should -Be 2
            $script:answer = 'use:false,false,0'
            $u = Get-AppleTerminalSettingsSetUse -Name 'eva'
            $u.Answered | Should -BeTrue; $u.Default | Should -BeFalse; $u.Startup | Should -BeFalse; $u.Tabs | Should -Be 0
        }

        It 'counts an answer it cannot read as unanswered: <Label>' -ForEach @(
            @{ Label = 'no answer'; Answer = $null }
            @{ Label = 'empty';     Answer = '' }
            @{ Label = 'ok';        Answer = 'ok' }
            @{ Label = 'truncated'; Answer = 'use:true,false' }
        ) {
            $script:answer = $Answer
            Mock Invoke-AppleTerminalScript { $script:answer }
            (Get-AppleTerminalSettingsSetUse -Name 'eva').Answered | Should -BeFalse
        }

        It 'asks about the profile by the name it is given, quoted for AppleScript' {
            Mock Invoke-AppleTerminalScript { 'use:false,false,0' }
            Get-AppleTerminalSettingsSetUse -Name 'say "hi"' | Out-Null
            Should -Invoke Invoke-AppleTerminalScript -Times 1 -Exactly -ParameterFilter {
                $Script.Contains('id of settings set ' + (ConvertTo-AppleScriptString 'say "hi"')) }
        }
    }
}

Describe 'ConvertTo-AppleScriptString' {
    InModuleScope TerminalStyles {
        It 'doubles a backslash once' {
            # A -replace replacement string is literal except for `$`, so
            # '\\\\' wrote four backslashes for one and the literal named a
            # profile with two.
            ConvertTo-AppleScriptString 'a\b' | Should -BeExactly '"a\\b"'
        }
        It 'escapes a quote, and a backslash before it' {
            ConvertTo-AppleScriptString 'say "hi"' | Should -BeExactly '"say \"hi\""'
            ConvertTo-AppleScriptString 'a\"b' | Should -BeExactly '"a\\\"b"'
        }
        It 'leaves a plain name alone, and an empty one empty' {
            ConvertTo-AppleScriptString 'eva 2' | Should -BeExactly '"eva 2"'
            ConvertTo-AppleScriptString '' | Should -BeExactly '""'
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

        It 'matches the style name exactly' {
            # Terminal.app numbers only an exact-name collision.
            (@(Get-AppleTerminalDuplicateProfile -InstalledName @('Forest 1', 'forest 1') -StyleName @('forest')) |
                ForEach-Object { $_.Name }) -join '|' | Should -BeExactly 'forest 1'
        }

        It 'handles a style name containing a space' {
            @(Get-AppleTerminalDuplicateProfile `
                -InstalledName @('neon rain 1') -StyleName @('neon rain')).Name |
                Should -Be @('neon rain 1')
        }
    }
}

Describe 'tstyles profiles' {
    # -Clean deletes only numbered copies TerminalStyles recorded making:
    # Terminal.app's own Duplicate Profile names a copy of 'eva' 'eva 1' too,
    # so a name proves nothing. Against a stand-in that keeps state.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:written = [System.Collections.ArrayList]::new()
            $script:scripts = [System.Collections.ArrayList]::new()
            $script:sets = [System.Collections.ArrayList]::new()
            foreach ($n in 'Basic', 'eva', 'eva 1', 'eva 2') { [void]$script:sets.Add($n) }
            $script:defaultSet = 'Basic'
            $script:startupSet = 'Basic'
            $script:refuseDelete = $false
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Get-TStylesPlatform { 'MacOS' }
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'eva' }) }
            Mock Invoke-AppleTerminalScript {
                [void]$script:scripts.Add($Script)
                if ($Script -match 'settingsSets\.name') {
                    return (ConvertTo-Json -Compress -InputObject @(@($script:sets) | ForEach-Object { '=' + $_ }))
                }
                $m = [regex]::Match($Script, 'delete settings set "(?<n>(?:[^"\\]|\\.)*)"')
                if ($m.Success) {
                    if ($script:refuseDelete) { return $null }
                    $n = $m.Groups['n'].Value -replace '\\(.)', '$1'
                    for ($i = $script:sets.Count - 1; $i -ge 0; $i--) { if ($script:sets[$i] -ceq $n) { $script:sets.RemoveAt($i) } }
                    return ''
                }
                $m = [regex]::Match($Script, 'set p to id of settings set "(?<n>(?:[^"\\]|\\.)*)"')
                if ($m.Success) {
                    $n = $m.Groups['n'].Value -replace '\\(.)', '$1'
                    return ('use:{0},{1},0' -f ($script:defaultSet -ceq $n).ToString().ToLowerInvariant(),
                            ($script:startupSet -ceq $n).ToString().ToLowerInvariant())
                }
                throw "unexpected AppleScript: $Script"
            }
            # 'eva 2' is a copy TerminalStyles recorded making; 'eva 1' is the
            # user's own Duplicate Profile copy.
            Set-AppleTerminalImportRecord -Copies -Name 'eva 2' -Hash 'h'
            $script:said = { ($script:written -join ' ') -replace '\s+', ' ' }
            $script:deletesOf = { param($n) @($script:scripts | Where-Object { $_ -ceq ('tell application "Terminal" to delete settings set "' + $n + '"') }).Count }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'lists recorded copies and numbered profiles with no record apart, and deletes nothing' {
            Invoke-TerminalStyleProfiles
            $t = & $script:said
            $t | Should -CMatch 'Numbered copies TerminalStyles recorded making: eva 2 '
            $t | Should -CMatch 'no record of making: eva 1 '
            $t | Should -CMatch 'TerminalStyles never deletes these'
            $t | Should -Match 'tstyles profiles -Clean'
            @($script:scripts | Where-Object { $_ -match 'delete settings set' }).Count | Should -Be 0
        }

        It '-Clean never deletes a numbered profile it has no record of making' {
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            $script:sets | Should -Contain 'eva 1'
            & $script:deletesOf 'eva 1' | Should -Be 0
            $script:sets | Should -Not -Contain 'eva 2'
            & $script:said | Should -CMatch 'Terminal\.app confirmed 1 of 1 removed'
            @((Get-AppleTerminalImportRecord -Copies).Keys) -ccontains 'eva 2' | Should -BeFalse
        }

        It 'names every profile it will delete before asking, and says an open tab switches' {
            Mock Confirm-Action { $false }
            Invoke-TerminalStyleProfiles -Clean
            Should -Invoke Confirm-Action -Times 1 -Exactly
            $t = & $script:said
            @($script:written | Where-Object { $_ -ceq '  - eva 2' }).Count | Should -Be 1
            $t | Should -Not -Match 'any window already open'
            $t | Should -CMatch 'switches to your default profile'
            $t | Should -CMatch 'not your default or startup profile'
            $t | Should -Match 'Cancelled'
            @($script:scripts | Where-Object { $_ -match 'delete settings set' }).Count | Should -Be 0
        }

        It '-Clean never deletes the default or startup profile, even a copy it recorded: <Which>' -ForEach @(
            @{ Which = 'default' }
            @{ Which = 'startup' }
        ) {
            [void]$script:sets.Add('eva 3')
            Set-AppleTerminalImportRecord -Copies -Name 'eva 3' -Hash 'h'
            if ($Which -eq 'default') { $script:defaultSet = 'eva 3' } else { $script:startupSet = 'eva 3' }
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            $script:sets | Should -Contain 'eva 3'
            & $script:deletesOf 'eva 3' | Should -Be 0
            & $script:said | Should -CMatch "eva 3 -- your $Which profile"
            $script:sets | Should -Not -Contain 'eva 2' -Because 'control: the other recorded copy goes'
        }

        It 'says nothing will be deleted, without asking, when every recorded copy is kept' {
            $script:defaultSet = 'eva 2'
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            Should -Invoke Confirm-Action -Times 0 -Exactly
            & $script:said | Should -Match 'nothing will be deleted'
            $script:sets | Should -Contain 'eva 2'
        }

        It '-Clean keeps a recorded copy whose name differs from another profile only in case' {
            [void]$script:sets.Add('eva 3'); [void]$script:sets.Add('Eva 3')
            Set-AppleTerminalImportRecord -Copies -Name 'eva 3' -Hash 'h'
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            & $script:deletesOf 'eva 3' | Should -Be 0
            & $script:deletesOf 'Eva 3' | Should -Be 0
            & $script:said | Should -CMatch "also has 'Eva 3'"
            $script:sets | Should -Not -Contain 'eva 2'
        }

        It 'forgets a recorded copy Terminal.app no longer lists, so a later profile of that name is not claimed' {
            $script:sets.Remove('eva 2')
            Invoke-TerminalStyleProfiles
            @((Get-AppleTerminalImportRecord -Copies).Keys) -ccontains 'eva 2' | Should -BeFalse
            [void]$script:sets.Add('eva 2')
            $script:written.Clear()
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            $script:sets | Should -Contain 'eva 2'
            & $script:said | Should -CMatch 'no record of making: eva 1 eva 2'
            Should -Not -Invoke Confirm-Action
        }

        It 'does not report a removal Terminal.app did not confirm' {
            $script:refuseDelete = $true
            Mock Confirm-Action { $true }
            Invoke-TerminalStyleProfiles -Clean
            & $script:deletesOf 'eva 2' | Should -Be 1 -Because 'the delete was attempted, or this measures nothing'
            $t = & $script:said
            $t | Should -Not -CMatch 'Removed eva 2'
            $t | Should -Match 'could not confirm eva 2 was removed'
            $t | Should -Match 'Terminal\.app confirmed 0 of 1 removed'
            @((Get-AppleTerminalImportRecord -Copies).Keys) -ccontains 'eva 2' | Should -BeTrue
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
        It 'says -Clean deletes only copies it recorded making' {
            $h = Get-TerminalStyleHelpData | Where-Object Name -eq 'profiles'
            $t = ($h.Detail -join ' ') -replace '\s+', ' '
            $t | Should -CMatch 'deletes only the numbered copies TerminalStyles recorded making'
            $t | Should -CMatch 'Duplicate Profile'
            $t | Should -Not -Match 'deletes the numbered ones'
        }

        It 'says when -NewWindow replaces the profile, and when it leaves it alone' {
            $h = InModuleScope TerminalStyles { Get-TerminalStyleHelpData }
            $prof  = ((@($h | Where-Object Name -eq 'profiles')[0].Detail) -join ' ') -replace '\s+', ' '
            $apply = ((@($h | Where-Object Name -eq 'apply')[0].Detail) -join ' ') -replace '\s+', ' '
            $prof  | Should -Match 'Once the style changes'
            $prof  | Should -Match 'default or startup profile'
            $apply | Should -Match 'replaced once the style changes'
            $apply | Should -Match 'default or startup profile'
        }

        It 'is in the known-subcommand list, so it is not read as a style name' {
            # The VALUE, not the source text: the list is a script variable, and
            # asserting on where it is written would pass or fail on layout.
            $script:TStylesSubcommands | Should -Contain 'profiles'
        }
    }
}
