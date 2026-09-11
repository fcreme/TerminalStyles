# Pester 5 tests for Reset-StyleDirect: strips the TerminalStyles field set
# from a profile, removes the orphan scheme, clears current-style.ps1.
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

Describe 'Reset-StyleDirect' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesCurrent = Join-Path $TestDrive 'current-style.ps1'
            $script:fakeSettings   = Join-Path $TestDrive 'fake-settings.json'

            $settingsObj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' }, [pscustomobject]@{ name = 'other' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'
                        colorScheme = 'eva'; opacity = 80; cursorShape = 'vintage'
                        font = [pscustomobject]@{ face = 'Cascadia Code' }
                        backgroundImage = 'C:\bg.gif'; tabTitle = 'EVA'
                        historySize = 9001
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($settingsObj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName     { 'PowerShell' }
            Mock Write-SettingsFile           { param($Path, $Settings) $script:written = $Settings }
        }

        It 'strips every TerminalStyles field from the target profile' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            foreach ($f in @('colorScheme','opacity','cursorShape','font','backgroundImage','tabTitle')) {
                $p.PSObject.Properties.Match($f).Count | Should -Be 0
            }
        }
        It 'leaves foreign (non-TerminalStyles) profile fields intact' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $p.historySize | Should -Be 9001
            $p.name        | Should -Be 'PowerShell'
        }
        It 'removes the orphan scheme from schemes[]' {
            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'other').Count | Should -Be 1
        }
        It 'keeps a scheme still referenced by another profile' {
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $obj.profiles.list += [pscustomobject]@{ name = 'Other'; guid = '{y}'; colorScheme = 'eva' }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 1
        }
        It 'clears an existing current-style.ps1' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old prompt', [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'writes the rolling settings.json.bak with the prior contents' {
            $prior = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            $bak = "$script:fakeSettings.bak"
            Test-Path $bak | Should -BeTrue
            [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $prior
        }
        It 'writes nothing at all when the profile has no colorScheme' {
            # A profile with no colorScheme is one this tool never styled, so
            # there is nothing of ours to remove and no reason to touch the file.
            #
            # This used to strip all thirteen $TStylesThemeFields anyway -- the
            # user's own useAcrylic, opacity, padding, cursorShape, font,
            # backgroundImage and tabTitle -- and rewrite settings.json, which
            # re-serialises the parsed object and drops every JSONC comment in
            # it. The assertion here was only that schemes[] survived, so the
            # field destruction went unnoticed.
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $p = $obj.profiles.list | Where-Object name -eq 'PowerShell'
            $p.PSObject.Properties.Remove('colorScheme')   # profile with no colorScheme
            $p | Add-Member -NotePropertyName useAcrylic -NotePropertyValue $true -Force
            $p | Add-Member -NotePropertyName opacity    -NotePropertyValue 60    -Force
            $p | Add-Member -NotePropertyName padding    -NotePropertyValue '8, 8, 8, 8' -Force
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            $script:written = $null
            Reset-StyleDirect -Target 'PowerShell'

            $script:written | Should -BeNullOrEmpty `
                -Because 'a profile this tool never styled must not be rewritten at all'
        }

        It 'leaves hand-set profile fields alone on a profile it never styled' {
            # The failure this guards: a user configures acrylic, opacity,
            # padding, cursor, font, wallpaper and tab title through the Windows
            # Terminal UI, never applies a style, runs `tstyles reset` out of
            # curiosity, and every one of those keys is deleted while the command
            # reports success in green. README.md promises the opposite in as many
            # words: "Fields you set on the profile by hand are left alone."
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name        = 'PowerShell'
                        guid        = '{x}'
                        useAcrylic  = $true
                        opacity     = 60
                        padding     = '8, 8, 8, 8'
                        cursorShape = 'bar'
                        tabTitle    = 'mine'
                        font        = [pscustomobject]@{ face = 'Consolas'; size = 14 }
                        backgroundImage = 'C:\Users\me\Pictures\wallpaper.png'
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            $script:written = $null
            Reset-StyleDirect -Target 'PowerShell'

            $script:written | Should -BeNullOrEmpty -Because 'nothing of ours is on that profile'

            # And the file on disk is untouched, byte for byte.
            $after = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Match 'useAcrylic'
            $after | Should -Match 'wallpaper.png'
            $after | Should -Match 'cursorShape'
        }

        It 'still resets a profile whose colorScheme names a real style' {
            # The other direction: the guard must not disable the feature.
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'; colorScheme = 'eva'; opacity = 80
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            $script:written = $null
            Reset-StyleDirect -Target 'PowerShell'

            $script:written | Should -Not -BeNullOrEmpty -Because 'eva is a real bundled style'
            $w = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $w.PSObject.Properties.Match('colorScheme').Count | Should -Be 0
            $w.PSObject.Properties.Match('opacity').Count     | Should -Be 0
        }
        It 'strips a style the caller has already proved is ours but the disk no longer has' {
            # The ownership marker asks Get-AvailableStyles whether the
            # profile's colorScheme names a style. `tstyles delete` calls this
            # AFTER moving that style into .deleted/, which is a sibling of
            # styles/ -- so the marker failed for the one profile it is
            # guaranteed to be true of, and the reset the delete prompt had just
            # itemised refused. -KnownStyleName is how the caller carries the
            # proof it already had across the move.
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'trashed-style' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'; colorScheme = 'trashed-style'; opacity = 80
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            @(Get-AvailableStyles | Where-Object Name -eq 'trashed-style').Count | Should -Be 0 `
                -Because 'the marker must have no other way to find it, or this measures nothing'

            $script:written = $null
            Reset-StyleDirect -Target 'PowerShell' -KnownStyleName 'trashed-style'

            $script:written | Should -Not -BeNullOrEmpty
            $w = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $w.PSObject.Properties.Match('colorScheme').Count | Should -Be 0
            $w.PSObject.Properties.Match('opacity').Count     | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'trashed-style').Count | Should -Be 0
        }

        It 'still refuses a profile carrying some other tool''s scheme name' {
            # The seam is one name, not a bypass: -KnownStyleName must not turn
            # the marker off for a profile this tool never styled.
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'someone-elses' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'; colorScheme = 'someone-elses'; opacity = 60
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            $script:written = $null
            Reset-StyleDirect -Target 'PowerShell' -KnownStyleName 'trashed-style'

            $script:written | Should -BeNullOrEmpty -Because 'the caller proved ownership of a different name'
        }

        It 'resets the defaults profile when -Target defaults' {
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' })
                profiles = [pscustomobject]@{
                    defaults = [pscustomobject]@{ colorScheme = 'eva'; opacity = 80 }
                    list     = @([pscustomobject]@{ name = 'PowerShell'; guid = '{x}' })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'defaults'
            $script:written.profiles.defaults.PSObject.Properties.Match('colorScheme').Count | Should -Be 0
            $script:written.profiles.defaults.PSObject.Properties.Match('opacity').Count     | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 0
        }
        It 'errors gracefully when the target profile is not found' {
            Mock Write-Host {}
            { Reset-StyleDirect -Target 'NoSuchProfile' } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'nothing to reset' }
            Should -Not -Invoke Write-SettingsFile
        }
    }
}
