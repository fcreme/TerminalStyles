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
# cache\<name>\background.* beneath the data root.
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
                    New-Item -ItemType File -Force -Path (Join-Path (Get-StyleCacheDir -StyleName $Name) '.no-background') | Out-Null
                }
                return $dir
            }
            $script:themeBody = $themeBody
            $script:withBgDir = script:New-Style -Name 'withbg' -WithBackground
            $script:noBgDir   = script:New-Style -Name 'nobg'
        }

        function script:New-Settings {
            param([hashtable]$ProfileProps = @{})
            $p = [pscustomobject](@{ name = 'PowerShell'; guid = '{x}' } + $ProfileProps)
            [pscustomobject]@{ profiles = [pscustomobject]@{ list = @($p) } }
        }
        function script:Merge {
            param($Settings, [string]$StyleDir)
            Merge-StyleIntoSettings -Settings $Settings -StyleDir $StyleDir `
                -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
        }
        function script:GetProfile { param($S) $S.profiles.list | Where-Object name -eq 'PowerShell' }

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
    }
}
