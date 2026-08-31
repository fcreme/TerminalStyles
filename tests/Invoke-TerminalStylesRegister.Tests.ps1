# Pester 5 tests for Invoke-TerminalStylesRegister.
#
# Function adds `Import-Module TerminalStyles -DisableNameChecking` to
# both PowerShell engines' $PROFILE files (wrapped in BEGIN/END markers
# so uninstall can strip it). Tests use the function's -Targets
# parameter to inject a synthetic single-target list pointing at
# $TestDrive, bypassing the real engine discovery.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

# These exercise the WRITE, not the consent gate, so they pass -Yes. Without it
# they now refuse: Pester's host is redirected, and the confirm prompt no longer
# assumes yes when nobody can answer. That change is the point -- `tstyles
# register < /dev/null` used to write the loader into both engines' $PROFILE
# files unattended, because `$ans -match '^(?i)n'` is FALSY against the
# AutomationNull that Read-Host returns at EOF.
Describe 'Invoke-TerminalStylesRegister' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive 'fake-profile.ps1'
            $script:loaderBegin = '# ===== TerminalStyles BEGIN ====='
            $script:loaderEnd   = '# ===== TerminalStyles END ====='
            $script:blockPattern = "(?ms)$([regex]::Escape($script:loaderBegin)).*?$([regex]::Escape($script:loaderEnd))\r?\n?"
            Mock Read-Host { '' }  # default Y on confirm prompt
        }

        It 'writes the loader block to a fresh $PROFILE' {
            # Pre-condition: fakeProfile doesn't exist
            Test-Path -LiteralPath $script:fakeProfile | Should -BeFalse

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $false
                HasLoader   = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            Test-Path -LiteralPath $script:fakeProfile | Should -BeTrue
            $content = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $content | Should -Match $script:blockPattern
            $content | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
        }

        It 'is idempotent: re-running with existing loader skips' {
            # Pre-populate with a BEGIN/END block
            $existingContent = "# my existing profile`r`n`r`n$script:loaderBegin`r`nImport-Module TerminalStyles -DisableNameChecking`r`n$script:loaderEnd`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            # Content unchanged
            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Be $before
            # Exactly one BEGIN/END block (no duplicates)
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
        }

        It '-Force replaces an existing loader block' {
            # Pre-populate with a BEGIN/END block whose body is DIFFERENT (legacy format)
            $oldBody = "$script:loaderBegin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:loaderEnd"
            $existingContent = "# my existing profile`r`n`r`n$oldBody`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Force -Targets @($target) -Yes

            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            # Exactly one BEGIN/END block
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
            # The new body is the canonical PSGallery loader (NOT the legacy dot-source)
            $after | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
            $after | Should -Not -Match 'LOCALAPPDATA\\TerminalStyles\\tstyles\.ps1'
        }
    }
}

Describe 'register writes a loader the install can actually resolve' {
    # A bootstrap install lives in the data root, which is NOT on
    # $env:PSModulePath. install.ps1 writes the full-path form for exactly that
    # reason and says so; terminals.ps1 repeats the rule where it stages the
    # shell shim. register wrote `Import-Module TerminalStyles` regardless.
    #
    # Because it uses the installer's own BEGIN/END markers, `tstyles register
    # -Force` on a bootstrap install stripped the working loader and wrote a
    # broken one over it, printed "Registered in <profile>" and "TerminalStyles
    # will auto-load on every new shell tab", and every new tab then opened with
    # a red "no valid module file was found in any module directory" and no
    # tstyles command -- from a session that had been working seconds earlier.
    # install.ps1 also tells a user whose engines were not found to add that
    # by-name line by hand, so there were two ways in.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
            $script:savedModule = $script:TStylesModuleRoot
            Mock Read-Host { '' }
        }
        AfterEach { $script:TStylesModuleRoot = $script:savedModule }

        It 'a BOOTSTRAP install gets the full path, not the bare name' {
            $fakeRoot = Join-Path $TestDrive 'bootstrap-root'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { $fakeRoot }
            $script:TStylesModuleRoot = $fakeRoot
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap' -Because 'the fixture must set the branch under test'

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false })

            $written = [System.IO.File]::ReadAllText($script:fakeProfile)
            $written | Should -Match 'TerminalStyles\.psd1' `
                -Because 'the bootstrap directory is not on $env:PSModulePath'
            $written | Should -Not -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$' `
                -Because 'the bare name resolves to nothing there'
        }

        It 'a PSGallery install still gets the bare name' {
            $modRoot = Join-Path $TestDrive 'psgallery-root'
            New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { Join-Path $TestDrive 'a-different-data-root' }
            $script:TStylesModuleRoot = $modRoot
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false })

            [System.IO.File]::ReadAllText($script:fakeProfile) |
                Should -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$' `
                -Because 'PSModulePath resolves it, and the version-stamped path would pin an old one'
        }
    }
}

Describe 'register and install.ps1 agree on what a loader line looks like' {
    # install.ps1 is fetched and piped to iex before the module exists, so it
    # cannot dot-source lib/ and the two loader forms are necessarily written
    # twice. They must not drift: register uses the installer's BEGIN/END
    # markers, so whichever runs last wins, and a mismatch means one of them
    # silently replaces a working loader with a broken one.
    BeforeAll {
        $script:repoRoot   = Split-Path $PSScriptRoot -Parent
        $script:installSrc = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install.ps1'))
        $script:updateSrc  = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'lib/update.ps1'))
    }

    It 'the Windows form in install.ps1 also appears in register' {
        $win = 'Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking'
        $script:installSrc | Should -BeLike "*$win*" -Because 'this test is anchored on the installer'
        $script:updateSrc  | Should -BeLike "*$win*" -Because 'register must write what the installer writes'
    }

    It 'both build the non-Windows form from a resolved path to TerminalStyles.psd1' {
        $shape = 'Import-Module "{0}" -DisableNameChecking'
        $script:installSrc | Should -BeLike "*$shape*"
        $script:updateSrc  | Should -BeLike "*$shape*" `
            -Because 'off Windows there is no %LOCALAPPDATA% equivalent, so the absolute path is baked in'
    }
}
