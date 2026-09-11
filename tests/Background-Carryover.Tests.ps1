# Pester 5 tests for background carryover between styles.
#
# Every theme.json declares the backgroundImage placeholder, but a style that
# ships no background.* resolves nothing -- and the merge used to skip the
# background fields wholesale in that case. The skip exists to protect a
# background the USER set, yet it could not tell that apart from one a
# previously applied style had written, so switching from a style with a GIF to
# a style without one left the old GIF showing (README "Known limitations").
#
# The distinguishing fact: every background TerminalStyles writes lives under a
# root it owns -- styles\<name>\background.* beneath the module root, or
# cache\<name>\background.* beneath the data root -- and is written as an
# ABSOLUTE path, which is what makes ownership answerable without reference to
# the directory the process happens to be running in.
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

Describe 'Background carryover between styles' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'

            # Both themes declare the placeholder, exactly like the real ones.
            $themeBody = @'
{
  "colorScheme": "%NAME%",
  "backgroundImage": "{{BACKGROUND_IMAGE}}",
  "backgroundImageOpacity": 0.45,
  "backgroundImageStretchMode": "uniformToFill",
  "backgroundImageAlignment": "center"
}
'@
            function script:New-Style {
                param([string]$Name, [switch]$WithBackground)
                $dir = Join-Path $script:TStylesModuleRoot "styles\$Name"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'),
                    "{`"name`":`"$Name`"}", $script:enc)
                [System.IO.File]::WriteAllText((Join-Path $dir 'theme.json'),
                    ($script:themeBody -replace '%NAME%', $Name), $script:enc)
                if ($WithBackground) {
                    [System.IO.File]::WriteAllText((Join-Path $dir 'background.gif'), 'GIFDATA', $script:enc)
                } else {
                    # Negative-cache marker: resolution stops here, no network.
                    # Negative-cache marker: resolution stops here, no network.
                    # It must be DATED -- an empty marker now reads as expired and
                    # would send every one of these cases to raw.githubusercontent.
                    $mk = Get-StyleCacheDir -StyleName $Name
                    New-Item -ItemType Directory -Path $mk -Force | Out-Null
                    [System.IO.File]::WriteAllText((Join-Path $mk '.no-background'),
                        ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress), $script:enc)
                }
                return $dir
            }
            $script:themeBody = $themeBody
            $script:withBgDir = script:New-Style -Name 'withbg' -WithBackground
            $script:noBgDir   = script:New-Style -Name 'nobg'
        }

        function script:New-Settings {
            # -Defaults builds the profiles.defaults block Windows Terminal
            # inherits into every named profile. Without it the file has no
            # defaults at all, which is the only shape the cases below this
            # could express -- and the reason none of them could see a
            # background carried on defaults.
            param([hashtable]$ProfileProps = @{}, [hashtable]$Defaults)
            $p = [pscustomobject](@{ name = 'PowerShell'; guid = '{x}' } + $ProfileProps)
            $profiles = [pscustomobject]@{ list = @($p) }
            if ($PSBoundParameters.ContainsKey('Defaults')) {
                $profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]$Defaults)
            }
            [pscustomobject]@{ profiles = $profiles }
        }
        function script:Merge {
            param($Settings, [string]$StyleDir, [string]$TargetName = 'PowerShell')
            Merge-StyleIntoSettings -Settings $Settings -StyleDir $StyleDir `
                -TargetName $TargetName -BackgroundImage '' -BackgroundImageProvided $false
        }
        function script:GetProfile { param($S) $S.profiles.list | Where-Object name -eq 'PowerShell' }
        function script:GetDefaults { param($S) $S.profiles.defaults }
        function script:BgFieldCount {
            param($Entry)
            @(@('backgroundImage','backgroundImageOpacity','backgroundImageStretchMode','backgroundImageAlignment') |
                Where-Object { $Entry.PSObject.Properties.Match($_).Count -gt 0 }).Count
        }

        Context 'Test-ManagedBackgroundPath' {
            It 'is true for a bundled background under the module root' {
                Test-ManagedBackgroundPath -Path (Join-Path $script:withBgDir 'background.gif') | Should -BeTrue
            }
            It 'is true for a lazily-fetched background under the data root cache' {
                $cached = Join-Path (Get-StyleCacheDir -StyleName 'rain') 'background.gif'
                Test-ManagedBackgroundPath -Path $cached | Should -BeTrue
            }
            It 'is false for a background the user chose themselves' {
                Test-ManagedBackgroundPath -Path 'C:\Users\someone\Pictures\wallpaper.png' | Should -BeFalse
            }
            It 'is false for the Windows Terminal desktopWallpaper keyword' {
                Test-ManagedBackgroundPath -Path 'desktopWallpaper' | Should -BeFalse
            }
            It 'is false for an empty or absent value' {
                Test-ManagedBackgroundPath -Path ''    | Should -BeFalse
                Test-ManagedBackgroundPath -Path $null | Should -BeFalse
            }
            It 'is true for a background left by a PREVIOUS module version' {
                # PSResourceGet installs each version to a sibling dir, so a
                # background written by 0.6.3 sits outside 0.7.0's module root.
                # Those users are exactly the ones upgrading with a stale GIF
                # (0.6.2/0.6.3 shipped bundled backgrounds by accident).
                $modules = Join-Path $TestDrive 'Modules\TerminalStyles'
                $script:TStylesModuleRoot = Join-Path $modules '0.7.0'
                $old = Join-Path $modules '0.6.3\styles\forest\background.gif'
                Test-ManagedBackgroundPath -Path $old | Should -BeTrue
            }
            It 'is false for a same-depth path under a differently named module' {
                $script:TStylesModuleRoot = Join-Path $TestDrive 'Modules\TerminalStyles\0.7.0'
                $other = Join-Path $TestDrive 'Modules\SomeOtherModule\1.0.0\background.gif'
                Test-ManagedBackgroundPath -Path $other | Should -BeFalse
            }
            It 'is not decided by the directory the process was launched in' {
                # [Path]::GetFullPath resolves anything that is not an absolute
                # path against [Environment]::CurrentDirectory -- the directory
                # the PROCESS was started in, which Set-Location does not move
                # (a child pwsh inherits it from the parent's location instead).
                # Launch pwsh inside the clone or the data root, which
                # `cd TerminalStyles; pwsh -File .\apply.ps1 ...` does, and the
                # user's own 'desktopWallpaper' normalised to
                # <cwd>\desktopWallpaper -- under a root, "ours", deleted.
                #
                # Set the ambient directory itself, NOT Set-Location: the two
                # are different, and Set-Location would leave this case passing
                # while measuring nothing.
                $roots = @($script:TStylesModuleRoot, $script:TStylesDataRoot)
                @($roots | Where-Object { $_ }).Count |
                    Should -Be 2 -Because 'the fixture must supply two real roots for this case to be hostile'

                $bundled = Join-Path $script:withBgDir 'background.gif'
                $saved   = [System.Environment]::CurrentDirectory
                foreach ($hostile in $roots) {
                    New-Item -ItemType Directory -Path $hostile -Force | Out-Null
                    try {
                        [System.Environment]::CurrentDirectory = $hostile
                        foreach ($theirs in @(
                            'desktopWallpaper'                # WT's own keyword
                            'my-wallpaper.png'                # a relative path
                            '%USERPROFILE%\Pictures\bg.png'   # WT expands this; GetFullPath does not
                            'C:bg.png'                        # rooted, but drive-RELATIVE on Windows
                        )) {
                            Test-ManagedBackgroundPath -Path $theirs |
                                Should -BeFalse -Because "'$theirs' is the user's whatever the process working directory is (here: $hostile)"
                        }
                        # Control: the guard must still recognise what we wrote,
                        # so a blanket $false cannot satisfy the case above.
                        Test-ManagedBackgroundPath -Path $bundled |
                            Should -BeTrue -Because "a bundled background is still ours from cwd $hostile"
                    } finally {
                        [System.Environment]::CurrentDirectory = $saved
                    }
                }
            }
            It 'is false for a sibling directory that merely shares a name prefix' {
                # "<dataroot>Evil\x.gif" must not count as living under "<dataroot>".
                Test-ManagedBackgroundPath -Path ($script:TStylesDataRoot + "Evil\x.gif") | Should -BeFalse
            }
        }

        Context 'switching styles' {
            It 'clears the previous style background when the new style ships none' {
                $afterWithBg = script:Merge -Settings (script:New-Settings) -StyleDir $script:withBgDir
                (script:GetProfile $afterWithBg).backgroundImage | Should -Not -BeNullOrEmpty

                $afterNoBg = script:Merge -Settings $afterWithBg -StyleDir $script:noBgDir
                $p = script:GetProfile $afterNoBg
                $p.colorScheme | Should -Be 'nobg'
                $p.PSObject.Properties.Match('backgroundImage').Count            | Should -Be 0
                $p.PSObject.Properties.Match('backgroundImageOpacity').Count     | Should -Be 0
                $p.PSObject.Properties.Match('backgroundImageStretchMode').Count | Should -Be 0
                $p.PSObject.Properties.Match('backgroundImageAlignment').Count   | Should -Be 0
            }

            It 'clears it even when the new theme.json never mentions background fields' {
                # All 16 bundled styles declare the placeholder, which is why the
                # case above passes -- the clear rode along inside the loop over
                # the new theme's OWN properties. A style that ships no background
                # has no reason to name background fields at all, and theme.json
                # keys are optional by contract, so a user-authored style like
                # this was left showing the PREVIOUS style's image behind its new
                # palette. The clear is driven by what is on the profile now, not
                # by what the incoming theme happens to mention.
                $bare = Join-Path $script:TStylesModuleRoot 'styles\bare'
                New-Item -ItemType Directory -Path $bare -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $bare 'scheme.json'), '{"name":"bare"}', $script:enc)
                [System.IO.File]::WriteAllText((Join-Path $bare 'theme.json'),
                    '{"colorScheme":"bare","opacity":95}', $script:enc)
                $bareCache = Get-StyleCacheDir -StyleName 'bare'
                New-Item -ItemType Directory -Path $bareCache -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $bareCache '.no-background'),
                    ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } |
                        ConvertTo-Json -Compress), $script:enc)

                $afterWithBg = script:Merge -Settings (script:New-Settings) -StyleDir $script:withBgDir
                (script:GetProfile $afterWithBg).backgroundImage | Should -Not -BeNullOrEmpty

                $afterBare = script:Merge -Settings $afterWithBg -StyleDir $bare
                $p = script:GetProfile $afterBare
                $p.colorScheme | Should -Be 'bare'
                $p.opacity     | Should -Be 95
                foreach ($f in 'backgroundImage','backgroundImageOpacity',
                               'backgroundImageStretchMode','backgroundImageAlignment') {
                    $p.PSObject.Properties.Match($f).Count | Should -Be 0 -Because "$f must not survive the switch"
                }
            }

            It "preserves a background the user set themselves" {
                $s = script:New-Settings -ProfileProps @{ backgroundImage = 'C:\Users\someone\Pictures\me.png' }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                (script:GetProfile $out).backgroundImage | Should -Be 'C:\Users\someone\Pictures\me.png'
            }

            It 'preserves the desktopWallpaper keyword' {
                $s = script:New-Settings -ProfileProps @{ backgroundImage = 'desktopWallpaper' }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                (script:GetProfile $out).backgroundImage | Should -Be 'desktopWallpaper'
            }

            It 'preserves the desktopWallpaper keyword when pwsh was launched inside a root' {
                # The end-to-end half of "is not decided by the directory the
                # process was launched in": the merge, not just the predicate.
                $saved = [System.Environment]::CurrentDirectory
                try {
                    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
                    [System.Environment]::CurrentDirectory = $script:TStylesDataRoot
                    $s = script:New-Settings -ProfileProps @{
                        backgroundImage        = 'desktopWallpaper'
                        backgroundImageOpacity = 0.6
                    }
                    $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                    $p = script:GetProfile $out
                    $p.colorScheme            | Should -Be 'nobg'
                    $p.backgroundImage        | Should -Be 'desktopWallpaper'
                    $p.backgroundImageOpacity | Should -Be 0.6
                } finally {
                    [System.Environment]::CurrentDirectory = $saved
                }
            }

            It 'still applies a bundled background when the style ships one' {
                $out = script:Merge -Settings (script:New-Settings) -StyleDir $script:withBgDir
                (script:GetProfile $out).backgroundImage | Should -Match 'withbg[\\/]background\.gif$'
            }

            It 'adds no background fields when neither the profile nor the style has one' {
                $out = script:Merge -Settings (script:New-Settings) -StyleDir $script:noBgDir
                (script:GetProfile $out).PSObject.Properties.Match('backgroundImage').Count | Should -Be 0
            }

            It 'still honours an explicit -BackgroundImage over a managed one' {
                $afterWithBg = script:Merge -Settings (script:New-Settings) -StyleDir $script:withBgDir
                $out = Merge-StyleIntoSettings -Settings $afterWithBg -StyleDir $script:noBgDir `
                    -TargetName 'PowerShell' -BackgroundImage 'C:\pics\chosen.png' -BackgroundImageProvided $true
                (script:GetProfile $out).backgroundImage | Should -Be 'C:\pics\chosen.png'
            }
        }

        Context 'a background the target profile INHERITS from profiles.defaults' {
            # Windows Terminal resolves every named profile against
            # profiles.defaults, so an image written there is live on this
            # profile too -- with nothing on the profile's own entry to show for
            # it. The carry-over check read the entry alone, so
            # `tstyles eva -Target defaults` followed by a bundle-less style on
            # the profile the user is sitting in left eva's GIF drawn behind the
            # new palette: verbatim the outcome the clear exists to prevent.
            # `tstyles reset -Target defaults` is the only thing that cleared it,
            # and that target is documented nowhere the user can read.
            BeforeEach {
                $script:managedBg = Join-Path $script:withBgDir 'background.gif'
                $script:usersBg   = 'C:\Users\someone\Pictures\me.png'
            }

            It "clears the previous style's image off defaults when the new style ships none" {
                $s = script:New-Settings -Defaults @{
                    colorScheme            = 'withbg'
                    backgroundImage        = $script:managedBg
                    backgroundImageOpacity = 0.45
                }
                Test-ManagedBackgroundPath -Path $script:managedBg |
                    Should -BeTrue -Because 'the fixture image must be one this tool owns, or nothing here may touch it'

                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                (script:GetProfile $out).colorScheme | Should -Be 'nobg'
                script:BgFieldCount (script:GetDefaults $out) | Should -Be 0 `
                    -Because 'what the profile SHOWS is what bleeds, wherever the key lives'
                # Bounded: the background fields, and nothing else on defaults.
                (script:GetDefaults $out).colorScheme | Should -Be 'withbg' `
                    -Because 'this apply was not asked to restyle profiles.defaults'
            }

            It "leaves an image the USER put on defaults exactly where it is" {
                $s = script:New-Settings -Defaults @{ backgroundImage = $script:usersBg }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                (script:GetDefaults $out).backgroundImage | Should -Be $script:usersBg
            }

            It "leaves the user's defaults image alone while clearing ours off the profile" {
                # The guard that must not be dropped: both entries carry an
                # image, only one of them is ours.
                $s = script:New-Settings -ProfileProps @{ backgroundImage = $script:managedBg } `
                                         -Defaults     @{ backgroundImage = $script:usersBg }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                script:BgFieldCount (script:GetProfile $out) | Should -Be 0
                (script:GetDefaults $out).backgroundImage | Should -Be $script:usersBg
            }

            It 'clears both when the profile and defaults each carry one of ours' {
                $s = script:New-Settings -ProfileProps @{ backgroundImage = $script:managedBg } `
                                         -Defaults     @{ backgroundImage = $script:managedBg }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir
                script:BgFieldCount (script:GetProfile $out)  | Should -Be 0
                script:BgFieldCount (script:GetDefaults $out) | Should -Be 0 `
                    -Because 'stripping only the entry hands the profile straight back to the inherited copy'
            }

            It 'honours an explicit -BackgroundImage "" against the inherited image' {
                # The plainest form of the contract: the user typed "no
                # background" and got "Style applied" in green with the GIF
                # still on screen.
                $s = script:New-Settings -Defaults @{ backgroundImage = $script:managedBg }
                $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:noBgDir `
                    -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $true
                script:BgFieldCount (script:GetDefaults $out) | Should -Be 0
            }

            It 'leaves defaults alone when the new style writes its own image onto the profile' {
                # Deliberate boundary, not an oversight: a profile-level
                # backgroundImage shadows defaults, so nothing of the old style
                # is visible on this profile -- and clearing defaults here would
                # silently restyle every OTHER profile the user did not name.
                $s = script:New-Settings -Defaults @{ backgroundImage = $script:managedBg }
                $out = script:Merge -Settings $s -StyleDir $script:withBgDir
                (script:GetProfile $out).backgroundImage  | Should -Match 'withbg[\\/]background\.gif$'
                (script:GetDefaults $out).backgroundImage | Should -Be $script:managedBg
            }

            It 'still styles profiles.defaults itself when defaults IS the target' {
                # The inherited lookup must not turn the defaults target into a
                # reader of its own entry.
                $s = script:New-Settings -Defaults @{ backgroundImage = $script:managedBg }
                $out = script:Merge -Settings $s -StyleDir $script:noBgDir -TargetName 'defaults'
                (script:GetDefaults $out).colorScheme | Should -Be 'nobg'
                script:BgFieldCount (script:GetDefaults $out) | Should -Be 0
            }

            It 'is unmoved by a settings.json with no defaults block at all' {
                $out = script:Merge -Settings (script:New-Settings) -StyleDir $script:noBgDir
                (script:GetProfile $out).colorScheme | Should -Be 'nobg'
                $out.profiles.PSObject.Properties.Match('defaults').Count | Should -Be 0 `
                    -Because 'reading defaults must not create it'
            }
        }
    }
}
