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
            # BOTH halves of the sandbox, or this test writes to the operator's
            # own files. $script:TStylesCurrent is computed from the data root at
            # MODULE LOAD (tstyles.ps1:239), so overriding the data root here does
            # not move it; current-style.json/.osc and the staged shell runtime are
            # computed from the data root at CALL time, so overriding
            # TStylesCurrent alone does not move them. Setting one and not the
            # other is how this file leaked for four months -- invisibly, because
            # what it wrote happened to match what was already there.
            $script:TStylesDataRoot = $TestDrive
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

# `tstyles reset` and the background a profile INHERITS.
#
# THE DEFECT. Windows Terminal resolves every named profile against
# profiles.defaults, so "what the profile shows" is not the same question as
# "what its own entry spells out". Merge-StyleIntoSettings was taught that in
# 0.8.26: its 'remove' branch strips the four background fields off
# profiles.defaults too when Test-ManagedBackgroundPath says the inherited image
# is ours, with the reason in the code -- "stripping the entry alone hands the
# profile straight back to the inherited copy, which is the same bleed one level
# up".
#
# Reset-StyleDirect is the other remove, and it never learned it. Its strip loop
# walked $script:TStylesThemeFields over $entry alone and then printed
# "Reset '<name>' to its unstyled default." in green. Measured on 0.8.28, on the
# state `tstyles eva -Target defaults` then `tstyles rain` leaves behind:
#
#   named profile bg fields left          : (none)
#   profiles.defaults.backgroundImage     : <module>/styles/eva/background.gif
#   profiles.defaults.colorScheme         : eva
#   Test-ManagedBackgroundPath on it      : True
#   EFFECTIVE background after reset      : <module>/styles/eva/background.gif
#   green success line printed?           : True
#
# So the window still showed eva's GIF and eva's palette while the command
# reported a plain default. The ownership proof it needed was already imported
# and already true in the same run.
Describe 'Reset-StyleDirect and what the profile INHERITS' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # BOTH halves of the sandbox, or this test writes to the operator's
            # own files. $script:TStylesCurrent is computed from the data root at
            # MODULE LOAD (tstyles.ps1:239), so overriding the data root here does
            # not move it; current-style.json/.osc and the staged shell runtime are
            # computed from the data root at CALL time, so overriding
            # TStylesCurrent alone does not move them. Setting one and not the
            # other is how this file leaked for four months -- invisibly, because
            # what it wrote happened to match what was already there.
            $script:TStylesDataRoot = $TestDrive
            $script:TStylesCurrent = Join-Path $TestDrive 'current-style.ps1'
            $script:fakeSettings   = Join-Path $TestDrive 'inherit-settings.json'
            $script:written        = $null
            $script:out            = [System.Collections.ArrayList]::new()

            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-TerminalKind             { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName     { 'PowerShell' }
            Mock Write-SettingsFile           { param($Path, $Settings) $script:written = $Settings }
            Mock Write-Host                   { [void]$script:out.Add("$Object") }
            # Nothing on this path should ask for consent; if something starts
            # to, it must not be answered by console detection.
            Mock Confirm-Action               { $false }

            # Under the module root, which is what Test-ManagedBackgroundPath
            # calls ours -- the same shape Get-StyleBundledBackground writes and
            # the merge recognises. The file need not exist: the shipped
            # ownership check is path math, and so is this.
            $script:ourEvaBg  = Join-Path $script:TStylesModuleRoot 'styles/eva/background.gif'
            $script:ourRainBg = Join-Path $script:TStylesModuleRoot 'styles/rain/background.gif'

            # Exactly what `tstyles eva -Target defaults` then `tstyles rain`
            # leaves behind. Both scheme names are real bundled styles, because
            # the ownership marker asks Get-AvailableStyles.
            function script:Write-InheritFixture {
                param([string]$DefaultsBackground, [string]$DefaultsScheme = 'eva')
                $defaults = [pscustomobject]@{ }
                if ($DefaultsScheme) {
                    $defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue $DefaultsScheme
                }
                if ($DefaultsBackground) {
                    $defaults | Add-Member -NotePropertyName backgroundImage            -NotePropertyValue $DefaultsBackground
                    $defaults | Add-Member -NotePropertyName backgroundImageOpacity     -NotePropertyValue 0.35
                    $defaults | Add-Member -NotePropertyName backgroundImageStretchMode -NotePropertyValue 'uniformToFill'
                    $defaults | Add-Member -NotePropertyName backgroundImageAlignment   -NotePropertyValue 'center'
                }
                $obj = [pscustomobject]@{
                    schemes  = @([pscustomobject]@{ name = 'eva' }, [pscustomobject]@{ name = 'rain' })
                    profiles = [pscustomobject]@{
                        defaults = $defaults
                        list     = @([pscustomobject]@{
                            name = 'PowerShell'; guid = '{x}'
                            colorScheme = 'rain'
                            backgroundImage = $script:ourRainBg
                            historySize = 9001
                        })
                    }
                }
                [System.IO.File]::WriteAllText($script:fakeSettings,
                    ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))
            }

            function script:Get-DefaultsBgFieldsLeft {
                # Projected with Where-Object, never read off the object as a
                # member: member access on an empty array yields one $null, and
                # a count of 1 would read as "one field left" forever.
                $d = $script:written.profiles.defaults
                return @($script:TStylesBgFields | Where-Object {
                    $d.PSObject.Properties.Match($_).Count -gt 0 })
            }
        }

        It 'clears a TerminalStyles background off profiles.defaults, which is what the profile was showing' {
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg

            Reset-StyleDirect -Target 'PowerShell'

            $script:written | Should -Not -BeNullOrEmpty -Because 'rain is a real bundled style'
            @(script:Get-DefaultsBgFieldsLeft).Count | Should -Be 0 `
                -Because 'stripping the entry alone hands the profile back to the inherited image'
        }

        It 'leaves the profile showing no TerminalStyles background at all' {
            # The same thing asked the way the user experiences it: resolve what
            # Windows Terminal would actually render, then ask the shipped
            # ownership test about it.
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg

            Reset-StyleDirect -Target 'PowerShell'

            $entry = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $shown = if ($entry.PSObject.Properties.Match('backgroundImage').Count) {
                        [string]$entry.backgroundImage
                     } elseif ($script:written.profiles.defaults.PSObject.Properties.Match('backgroundImage').Count) {
                        [string]$script:written.profiles.defaults.backgroundImage
                     } else { $null }
            Test-ManagedBackgroundPath -Path $shown | Should -BeFalse `
                -Because 'reset says "unstyled default" and the window was still showing our GIF'
        }

        It 'leaves a background the USER put on profiles.defaults exactly where it is' {
            # The guard the fix must not overshoot, mirrored from the apply side
            # (tests/Background-Carryover.Tests.ps1): an image the user chose for
            # every profile is theirs, and reset removes only what an apply put
            # there. README says so in as many words.
            # Shaped for the engine running the test, so the ownership check
            # does the real root comparison rather than bailing at "not even
            # rooted here". NOT $IsWindows: that is PowerShell Core only, and on
            # the 5.1 leg it is $null -- which would silently pick the other
            # branch and measure the early return instead.
            $theirs = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
                          'C:\Users\me\Pictures\wallpaper.png'
                      } else { '/Users/me/Pictures/wallpaper.png' }
            script:Write-InheritFixture -DefaultsBackground $theirs

            Reset-StyleDirect -Target 'PowerShell'

            $d = $script:written.profiles.defaults
            $d.backgroundImage | Should -Be $theirs
            @(script:Get-DefaultsBgFieldsLeft).Count | Should -Be 4 `
                -Because 'every field of a background the user set stays'

            # ...and the profile it was asked about is still reset.
            $entry = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $entry.PSObject.Properties.Match('backgroundImage').Count | Should -Be 0
            $entry.PSObject.Properties.Match('colorScheme').Count     | Should -Be 0
        }

        It 'says it cleared the image off profiles.defaults, because that reaches every profile' {
            # Removing a key from defaults changes every profile inheriting it,
            # which is more than the one the user named. A command that does that
            # silently is the defect this project ships most.
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg

            Reset-StyleDirect -Target 'PowerShell'

            $text = $script:out -join "`n"
            $text | Should -Match 'profiles\.defaults'
            $text | Should -Match 'inheriting'
        }

        It 'stops claiming an unstyled default while profiles.defaults still styles the profile' {
            # The colorScheme is deliberately NOT stripped from defaults -- that
            # would restyle every other profile on a command that named one -- so
            # the sign-off has to say what is still coming from there.
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg -DefaultsScheme 'eva'

            Reset-StyleDirect -Target 'PowerShell'

            $text = $script:out -join "`n"
            $text | Should -Not -Match 'unstyled default' `
                -Because 'the profile still renders eva''s palette, inherited from defaults'
            $text | Should -Match "colorScheme 'eva'"
            $text | Should -Match 'tstyles reset -Target defaults'
            # And it really is left there, rather than quietly removed.
            $script:written.profiles.defaults.colorScheme | Should -Be 'eva'
        }

        It 'still reports an unstyled default when nothing is inherited' {
            # The counterweight: the new sentences must not replace the old one
            # on the ordinary case. No defaults block at all here.
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'rain' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'; colorScheme = 'rain'; opacity = 80
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'

            $text = $script:out -join "`n"
            $text | Should -Match "Reset 'PowerShell' to its unstyled default"
            $text | Should -Not -Match 'profiles\.defaults'
        }

        It 'says nothing about inheriting when the target IS defaults' {
            # -Target defaults resolves to the defaults block itself; telling the
            # user it still inherits from the thing they just reset would be a
            # message about nothing.
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg

            Reset-StyleDirect -Target 'defaults'

            $text = $script:out -join "`n"
            $text | Should -Match 'unstyled default'
            $text | Should -Not -Match 'tstyles reset -Target defaults'
            @(script:Get-DefaultsBgFieldsLeft).Count | Should -Be 0
        }

        It 'leaves a foreign field on profiles.defaults alone' {
            # Only the four background keys come off defaults -- nothing else
            # the user configured there.
            script:Write-InheritFixture -DefaultsBackground $script:ourEvaBg
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $obj.profiles.defaults | Add-Member -NotePropertyName historySize -NotePropertyValue 4242
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'

            $script:written.profiles.defaults.historySize | Should -Be 4242
        }
    }
}
