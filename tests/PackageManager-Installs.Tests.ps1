# Pester 5 tests: a copy installed by Scoop or Homebrew is left to its package
# manager.
#
# The bug: Get-TerminalStylesInstallKind knew two kinds, Bootstrap and
# everything else, and everything else was called a PowerShell Gallery install.
# A copy Scoop or Homebrew put on disk was therefore updated with
# Update-PSResource -- against a module PSResourceGet never installed, failing
# or installing a second copy beside it -- announced by a daily notice telling
# the user to run that, and "uninstalled" with Uninstall-PSResource, which left
# the package's copy where it was.
#
# The package marks itself: the Scoop manifest's post_install and the Homebrew
# formula's install step each write `.package-manager` into the module folder.
# Every case here builds that folder inside TestDrive, and the uninstall cases
# follow CLAUDE.md's sandbox rules: -HomeDir for the rc half, the data root
# mocked, -ProfileTarget pinned, and both Gallery removers mocked to throw and
# asserted uncalled.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'package-manager installs' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # Stubs for Mock to attach to on an engine without these commands,
            # defined in the module scope for the reason
            # tests/Uninstall-SaysWhatIsLeft.Tests.ps1 gives. Never run for real.
            if (-not (Get-Command Update-PSResource -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Update-PSResource { param([string]$Name, [switch]$TrustRepository) }
            }
            if (-not (Get-Command Update-Module -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Update-Module { param([string]$Name, [switch]$Force) }
            }
            if (-not (Get-Command Uninstall-PSResource -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Uninstall-PSResource { param([string]$Name) }
            }
            if (-not (Get-Command Uninstall-Module -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Uninstall-Module { param([string]$Name, [switch]$AllVersions) }
            }

            function New-MarkedModuleRoot {
                param([AllowNull()][string]$Marker)
                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                if ($null -ne $Marker) {
                    [System.IO.File]::WriteAllText((Join-Path $root '.package-manager'), $Marker,
                        [System.Text.UTF8Encoding]::new($false))
                }
                return $root
            }
        }
        BeforeEach {
            $script:savedModuleRoot = $script:TStylesModuleRoot
            $script:savedData       = $script:TStylesDataRoot
            $script:data = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
        }
        AfterEach {
            $script:TStylesModuleRoot = $script:savedModuleRoot
            $script:TStylesDataRoot   = $script:savedData
        }

        Context 'Get-TerminalStylesInstallKind reads the marker' {
            It 'calls a folder marked <Name> a <Kind> install' -ForEach @(
                @{ Name = 'scoop';                       Marker = 'scoop';            Kind = 'Scoop' }
                @{ Name = 'homebrew and a newline';      Marker = "homebrew`n";       Kind = 'Homebrew' }
                @{ Name = 'Scoop in blank lines, CRLF';  Marker = "`n  Scoop  `r`n";  Kind = 'Scoop' }
                @{ Name = 'HOMEBREW';                    Marker = 'HOMEBREW';         Kind = 'Homebrew' }
            ) {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker $Marker
                Get-TerminalStylesInstallKind | Should -Be $Kind
            }

            It 'ignores a marker naming anything else' {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker 'chocolatey'
                Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet' -Because 'an unknown manager is not guessed at'
            }

            It 'ignores an empty marker' {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker ''
                Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
            }

            It 'calls an unmarked folder a Gallery install, as before' {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker $null
                Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
            }

            It 'still calls the data root a bootstrap install, marker or not' {
                $script:TStylesModuleRoot = $script:data
                [System.IO.File]::WriteAllText((Join-Path $script:data '.package-manager'), 'scoop')
                Get-TerminalStylesInstallKind | Should -Be 'Bootstrap'
            }

            It 'the repo does not ship a marker' {
                # A marker in the source tree would make every Gallery install,
                # and every checkout, a package-manager one.
                $repoRoot = Split-Path $PSScriptRoot -Parent
                [System.IO.File]::Exists((Join-Path $repoRoot '.package-manager')) | Should -BeFalse
            }
        }

        Context 'Get-HomebrewStableModuleRoot' {
            It 'maps a versioned Cellar folder to its opt/ link' {
                $sep = [System.IO.Path]::DirectorySeparatorChar
                $prefix = Join-Path $TestDrive 'homebrew'
                $cellar = ($prefix, 'Cellar', 'terminalstyles', '0.9.8', 'libexec') -join $sep
                Get-HomebrewStableModuleRoot -ModuleRoot $cellar |
                    Should -Be (($prefix, 'opt', 'terminalstyles', 'libexec') -join $sep)
            }

            It 'leaves any other path as it was' {
                $p = Join-Path $TestDrive 'opt/terminalstyles/libexec'
                Get-HomebrewStableModuleRoot -ModuleRoot $p | Should -Be $p
            }
        }

        Context 'the update notice stays quiet' {
            It 'asks nothing and announces nothing for a <Kind> install' -ForEach @(
                @{ Kind = 'Scoop' }, @{ Kind = 'Homebrew' }
            ) {
                Mock Get-TerminalStylesInstallKind { $Kind }
                Mock Get-NewestInstalledVersion { '0.9.7' }
                Mock Get-GalleryLatestVersion { '9.9.9' }
                Mock Invoke-UpdateCheckRequest { [pscustomobject]@{ sha = 'f' * 40 } }
                # Both arms would speak here: the Gallery one has 9.9.9 over
                # 0.9.7, and the bootstrap one a recorded SHA that is not
                # main's. Without the SHA file the bootstrap arm returns nothing
                # by itself, and a kind that fell through to it passed this case.
                [System.IO.File]::WriteAllText((Join-Path $script:data '.installed-sha'), ('a' * 40))

                Test-UpdateAvailable | Should -BeNullOrEmpty
                Should -Invoke Get-GalleryLatestVersion -Times 0 -Exactly
                Should -Invoke Invoke-UpdateCheckRequest -Times 0 -Exactly
            }
        }

        Context 'tstyles update names the package manager''s command' {
            BeforeEach {
                Mock Update-PSResource { throw 'Update-PSResource reached from a package-manager install' }
                Mock Update-Module     { throw 'Update-Module reached from a package-manager install' }
                Mock Invoke-WebRequest { throw 'the bootstrap installer reached from a package-manager install' }
            }
            AfterEach {
                Should -Invoke Update-PSResource -Times 0 -Exactly
                Should -Invoke Update-Module -Times 0 -Exactly
                Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            }

            It 'tells a <Kind> install to run <Command>, and changes nothing' -ForEach @(
                @{ Kind = 'Scoop';    Command = 'scoop update terminalstyles' }
                @{ Kind = 'Homebrew'; Command = 'brew upgrade terminalstyles' }
            ) {
                Mock Get-TerminalStylesInstallKind { $Kind }
                $out = Invoke-TerminalStylesUpdate 6>&1 | Out-String -Width 500
                $out | Should -Match ([regex]::Escape($Command))
                $out | Should -Match 'Nothing was changed\.'
                $out | Should -Not -Match 'Update complete|Updated '
            }
        }

        Context 'tstyles register' {
            BeforeEach {
                $script:fakeProfile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
                Mock Read-Host { '' }
            }

            It 'writes a Homebrew install''s loader through opt/, not the versioned Cellar folder' {
                $sep = [System.IO.Path]::DirectorySeparatorChar
                $prefix = Join-Path $TestDrive 'homebrew'
                $cellar = ($prefix, 'Cellar', 'terminalstyles', '0.9.8', 'libexec') -join $sep
                New-Item -ItemType Directory -Path $cellar -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $cellar '.package-manager'), 'homebrew')
                $script:TStylesModuleRoot = $cellar
                Get-TerminalStylesInstallKind | Should -Be 'Homebrew' -Because 'the fixture must set the branch under test'

                Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                    Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false }) 6>$null

                $line = @([System.IO.File]::ReadAllText($script:fakeProfile) -split "`r?`n" |
                          Where-Object { $_ -match '^Import-Module ' })[0]
                $expected = Join-Path (($prefix, 'opt', 'terminalstyles', 'libexec') -join $sep) 'TerminalStyles.psd1'
                $line | Should -Be ('Import-Module "{0}" -DisableNameChecking' -f $expected) `
                    -Because 'Homebrew''s prefix is not on the module path, and brew upgrade deletes the Cellar folder'
            }

            It 'writes a Scoop install''s loader by name' {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker 'scoop'
                Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                    Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false }) 6>$null

                [System.IO.File]::ReadAllText($script:fakeProfile) |
                    Should -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$' `
                    -Because 'Scoop puts its modules folder on PSModulePath'
            }
        }

        Context 'tstyles uninstall leaves the module to the package manager' {
            BeforeEach {
                $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                New-Item -ItemType Directory -Path $script:h -Force | Out-Null
                Mock Get-PowerShellProfileTarget { @() }
                Mock Get-OtherEngineModuleRoot { }
                Mock Confirm-Action { $true }
                Mock Uninstall-PSResource { throw 'Uninstall-PSResource reached from a package-manager install' }
                Mock Uninstall-Module     { throw 'Uninstall-Module reached from a package-manager install' }
            }
            AfterEach {
                # Step 1 catches what a remover throws, so the throw alone could
                # never fail a case.
                Should -Invoke Uninstall-PSResource -Times 0 -Exactly
                Should -Invoke Uninstall-Module -Times 0 -Exactly
            }

            It 'keeps a <Kind> copy, says so up front, and closes on <Command>' -ForEach @(
                @{ Kind = 'Scoop';    Marker = 'scoop';    Command = 'scoop uninstall terminalstyles' }
                @{ Kind = 'Homebrew'; Marker = 'homebrew'; Command = 'brew uninstall terminalstyles' }
            ) {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker $Marker
                [System.IO.File]::WriteAllText((Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1'), '@{}')

                $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 |
                       Out-String -Width 500

                $out | Should -Match ("detected: a {0} install" -f $Kind)
                $out | Should -Match ("Leave the module itself in place: {0} installed it" -f $Kind)
                $out | Should -Match ("To finish, run: {0}" -f [regex]::Escape($Command))
                $out | Should -Match 'TerminalStyles is NOT fully uninstalled\.'
                $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$' `
                    -Because 'the module is still installed until the package manager removes it'
                $out | Should -Not -Match 'Uninstall-PSResource|Uninstall-Module'
                [System.IO.File]::Exists((Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1')) |
                    Should -BeTrue -Because 'the package manager''s files are not this command''s to delete'
            }

            It 'says what the confirm is for' {
                $script:TStylesModuleRoot = New-MarkedModuleRoot -Marker 'scoop'
                Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-Null
                Should -Invoke Confirm-Action -Times 1 -Exactly -ParameterFilter {
                    $Consequence -eq 'removes the shell loader; the module stays until scoop uninstall terminalstyles'
                }
            }
        }
    }
}
