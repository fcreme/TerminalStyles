# Pester 5 tests: `tstyles uninstall` closes on "TerminalStyles uninstalled."
# only when nothing it set out to remove is left.
#
# The bugs:
#   - The sign-off knew two kinds of leftover: a loader block it could not
#     strip, and a VS Code style it could not take out. Every other failure
#     printed its own red line and was then forgotten, so the command still
#     closed on the plain "TerminalStyles uninstalled.":
#       * the Gallery remover failing, or returning without removing anything;
#       * a bootstrap install file the delete loop could not remove -- the loop
#         is silent on failure, and "Removed install-managed files" was printed
#         after it unconditionally;
#       * the generated WezTerm module, when it could not be deleted;
#       * whatever -DeleteData could not wipe.
#   - A Gallery copy on an engine without PSResourceGet -- Windows PowerShell
#     5.1 ships only PowerShellGet -- was removed with Uninstall-PSResource,
#     which does not exist there. The module stayed installed, under a red "is
#     not recognized" and that same plain sign-off.
#   - Under $ErrorActionPreference = 'Stop', a -DeleteData wipe that could not
#     remove everything threw out of the command before the sign-off.
#
# Every case is driven past consent with every path it can reach inside
# TestDrive, by the rules in CLAUDE.md: -HomeDir for the rc half, a mocked data
# root for the staged files and the VS Code records, and both seams of the
# $PROFILE half pinned.
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

Describe 'uninstall removes a Gallery install, and says so only once it is gone' {
    # The module path is narrowed to one folder holding one Gallery-style copy,
    # so "still installed" can only ever see that copy -- never one of the
    # machine's, and never the developer's own. Both removers are mocked to
    # fail the test if anything reaches them that a case did not plan for.
    InModuleScope TerminalStyles {
        BeforeAll {
            # Windows PowerShell 5.1 has no PSResourceGet, so Uninstall-PSResource
            # does not exist there, and Pester cannot mock a command that is
            # absent. The arm is still reachable on 5.1 -- PSResourceGet can be
            # installed alongside -- so a stub is defined for Mock to attach to,
            # as tests/Update-SaysWhatChanged.Tests.ps1 does for Update-PSResource.
            # Never invoked for real: every case mocks it.
            if (-not (Get-Command Uninstall-PSResource -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Uninstall-PSResource { param([string]$Name) }
            }
            if (-not (Get-Command Uninstall-Module -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Uninstall-Module { param([string]$Name, [switch]$AllVersions) }
            }
        }

        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'PSResourceGet' }
            Mock Get-PowerShellProfileTarget { @() }
            Mock Confirm-Action { $true }
            Mock Uninstall-PSResource { throw 'Uninstall-PSResource reached without a plan' }
            Mock Uninstall-Module     { throw 'Uninstall-Module reached without a plan' }

            $script:mods = Join-Path $script:h 'Modules'
            $script:copy = Join-Path (Join-Path $script:mods 'TerminalStyles') '9.9.9'
            New-Item -ItemType Directory -Path $script:copy -Force | Out-Null
            New-ModuleManifest -Path (Join-Path $script:copy 'TerminalStyles.psd1') -ModuleVersion '9.9.9'
            $script:savedModulePath = $env:PSModulePath
            $env:PSModulePath = $script:mods
        }
        AfterEach {
            $env:PSModulePath = $script:savedModulePath
            $script:TStylesDataRoot = $script:savedData
        }

        It 'removes it with Uninstall-PSResource, and signs off once it is gone' {
            Mock Uninstall-PSResource { Remove-Item -LiteralPath $script:copy -Recurse -Force }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() `
                       -HasPSResourceGet:$true 6>&1 | Out-String

            Should -Invoke Uninstall-PSResource -Times 1 -Exactly -ParameterFilter { $Name -eq 'TerminalStyles' }
            $out | Should -Match 'Removed module via Uninstall-PSResource'
            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'removes every version with Uninstall-Module where PSResourceGet is not installed' {
            # The engine the Gallery's own page sends people to Install-Module
            # on. -AllVersions because Update-Module installs side by side and
            # Uninstall-Module alone removes only the newest: measured with two
            # versions installed, it left the older one behind.
            Mock Uninstall-Module { Remove-Item -LiteralPath $script:copy -Recurse -Force }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() `
                       -HasPSResourceGet:$false 6>&1 | Out-String

            Should -Invoke Uninstall-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'TerminalStyles' -and $AllVersions }
            Should -Invoke Uninstall-PSResource -Times 0
            $out | Should -Match 'Uninstall-Module -Name TerminalStyles -AllVersions' `
                -Because 'the consent screen names the command that will run'
            $out | Should -Not -Match 'PSResourceGet|Uninstall-PSResource' `
                -Because 'this engine has neither, so a screen naming them describes another machine'
            $out | Should -Match 'Removed module via Uninstall-Module'
            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'names the copy still installed when removal fails, and does not sign off' {
            Mock Uninstall-PSResource { throw 'Access to the path is denied.' }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() `
                       -HasPSResourceGet:$true 6>&1 | Out-String

            $out | Should -Match 'Access to the path is denied' -Because 'the reason is the first thing to fix'
            $out | Should -Match 'TerminalStyles[\\/]9\.9\.9'
            $out | Should -Match 'NOT fully uninstalled'
            $out | Should -Not -Match 'Removed module via'
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'reads the module path rather than taking the remover''s word for it' {
            # Uninstall-PSResource that finds nothing it can remove warns and
            # returns, and -ErrorAction Stop does not fire: measured, against a
            # copy it did not recognise, which stayed installed with no error to
            # catch.
            Mock Uninstall-PSResource { }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() `
                       -HasPSResourceGet:$true 6>&1 | Out-String

            $out | Should -Match 'TerminalStyles[\\/]9\.9\.9'
            $out | Should -Match 'NOT fully uninstalled'
            $out | Should -Not -Match 'Removed module via'
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'does not claim a removal when no copy was installed' {
            # A module imported from a folder that is not on the module path --
            # a checkout -- is a Gallery kind too. There is nothing to remove,
            # and "Removed module" would say otherwise.
            Remove-Item -LiteralPath (Join-Path $script:mods 'TerminalStyles') -Recurse -Force
            Mock Uninstall-PSResource { }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() `
                       -HasPSResourceGet:$true 6>&1 | Out-String

            $out | Should -Not -Match 'Removed module via'
            $out | Should -Match 'No installed copy of the module was found'
            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$' -Because 'nothing of it is left'
        }

        It 'does not say the module is gone, anywhere, while it is still installed' {
            # The advice under three other leftovers rests on "the module is
            # gone": tstyles shell-remove cannot run, a $PROFILE block imports a
            # module that is no longer there, and tstyles cannot take a VS Code
            # style out. Each is false while a copy is still installed.
            Mock Uninstall-PSResource { throw 'Access to the path is denied.' }

            # An rc file it cannot strip.
            $rc = Join-Path $script:h '.zshrc'
            [System.IO.File]::WriteAllText($rc, "# original`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $rc | Should -Be 'added' -Because 'the fixture must plant a real block'
            # A $PROFILE it cannot strip.
            $prof = Join-Path $script:h 'profile.ps1'
            [System.IO.File]::WriteAllText($prof, "function prompt { 'mine> ' }`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $prof | Should -Be 'added'
            $target = [pscustomobject]@{ ProfilePath = $prof; Label = 'PowerShell 7'; Labels = @('PowerShell 7') }
            # A VS Code style it cannot take out. The writer's own cases cover
            # how a reset fails; this one only needs the sign-off to hear of it.
            $script:settings = Join-Path $script:h 'settings.json'
            Mock Get-VSCodeUninstallTarget { [pscustomobject]@{ Variant = 'Code'; Path = $script:settings } }
            Mock Reset-StyleVSCodeConfig { @{ Variant = 'Code'; Status = 'failed'; Detail = 'locked' } }
            Mock Show-VSCodeResetResult { }

            (Get-Item -LiteralPath $rc -Force).IsReadOnly = $true
            (Get-Item -LiteralPath $prof -Force).IsReadOnly = $true
            try {
                $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @($target) `
                           -HasPSResourceGet:$true 6>&1 | Out-String
            } finally {
                (Get-Item -LiteralPath $rc -Force).IsReadOnly = $false
                (Get-Item -LiteralPath $prof -Force).IsReadOnly = $false
            }

            # Every leftover is still named...
            $out | Should -Match 'TerminalStyles[\\/]9\.9\.9'
            $out | Should -Match ([regex]::Escape($rc))
            $out | Should -Match ([regex]::Escape($prof))
            $out | Should -Match ([regex]::Escape($script:settings))
            $out | Should -Match 'by hand'
            # ...and none of the three is explained by a module that is not gone.
            $out | Should -Not -Match 'the module is gone'
            $out | Should -Not -Match 'just removed'
            $out | Should -Not -Match 'module is\s+gone, so tstyles cannot'
        }
    }
}

Describe 'uninstall says it removed the install files only when they are gone' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path (Join-Path $script:data 'lib') -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Get-PowerShellProfileTarget { @() }
            Mock Confirm-Action { $true }

            # A bootstrap install as install.ps1 leaves one: the files it
            # placed, and the manifest that names them.
            foreach ($f in 'tstyles.ps1', 'TerminalStyles.psd1', 'lib/update.ps1') {
                [System.IO.File]::WriteAllText((Join-Path $script:data $f), "# placed by install.ps1`n",
                    [System.Text.UTF8Encoding]::new($false))
            }
            [System.IO.File]::WriteAllText((Join-Path $script:data '.installed-files'),
                "tstyles.ps1`nTerminalStyles.psd1`nlib`n", [System.Text.UTF8Encoding]::new($false))
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedData
        }

        It 'says so when every file it placed is gone' {
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String

            $out | Should -Match 'Removed install-managed files'
            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$'
            foreach ($f in 'tstyles.ps1', 'TerminalStyles.psd1', 'lib') {
                Test-Path -LiteralPath (Join-Path $script:data $f) | Should -BeFalse -Because "$f is the install's"
            }
        }

        It 'names a file it could not remove, and does not sign off' {
            # The delete loop is silent on failure by design -- one locked file
            # must not stop the rest -- so what it left can only be known by
            # looking afterwards.
            $script:stuck = Join-Path $script:data 'tstyles.ps1'
            # Every other delete is real. Pester 6 refuses a call no filter
            # matches unless a default mock exists, so the default passes
            # through -- to the cmdlet object itself, because Pester intercepts
            # the module-qualified name too, and that recursed until the call
            # stack overflowed.
            Mock Remove-Item { & (Get-Command -Name Remove-Item -CommandType Cmdlet) @PesterBoundParameters }
            Mock Remove-Item { } -ParameterFilter { $LiteralPath -eq $script:stuck }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String

            $out | Should -Not -Match 'Removed install-managed files'
            $out | Should -Match ([regex]::Escape($script:stuck))
            $out | Should -Match 'NOT fully uninstalled'
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
            Test-Path -LiteralPath (Join-Path $script:data 'lib') | Should -BeFalse -Because 'the rest still went'
        }

        It 'lets a leftover go once -DeleteData has removed it after all' {
            # Step 1's leftover is inside the data root, and the wipe in step 4
            # can take what the delete loop could not. The sign-off reads the
            # file system again rather than step 1's list.
            $script:stuck = Join-Path $script:data 'tstyles.ps1'
            Mock Remove-Item { & (Get-Command -Name Remove-Item -CommandType Cmdlet) @PesterBoundParameters }
            Mock Remove-Item { } -ParameterFilter { $LiteralPath -eq $script:stuck }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -DeleteData -ProfileTarget @() 6>&1 | Out-String

            Test-Path -LiteralPath $script:data | Should -BeFalse -Because 'the fixture needs the wipe to have worked'
            $out | Should -Not -Match 'NOT fully uninstalled'
            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }
    }
}

Describe 'uninstall does not sign off over a file it could not delete' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Get-PowerShellProfileTarget { @() }
            Mock Confirm-Action { $true }
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedData
        }

        It 'names the WezTerm module when it could not be deleted' {
            $script:wez = Get-WezTermModulePath -HomeDir $script:h
            New-Item -ItemType Directory -Path (Split-Path $script:wez -Parent) -Force | Out-Null
            [System.IO.File]::WriteAllText($script:wez, "-- generated`n", [System.Text.UTF8Encoding]::new($false))
            Mock Remove-Item { throw 'The process cannot access the file because it is being used by another process.' } `
                -ParameterFilter { $LiteralPath -eq $script:wez }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String

            $out | Should -Match 'could not remove'
            $out | Should -Match 'EXCEPT the WezTerm style module'
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'names the data folder when -DeleteData could not remove all of it' {
            Mock Remove-Item { } -ParameterFilter { $LiteralPath -eq $script:data }

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -DeleteData -ProfileTarget @() 6>&1 | Out-String

            $out | Should -Match 'could not remove all of'
            $out | Should -Match 'EXCEPT part of the data folder'
            $out | Should -Not -Match '(?m)^TerminalStyles uninstalled\.\s*$'
        }

        It 'still reaches the sign-off when that wipe fails under ErrorActionPreference Stop' {
            # A real failure rather than a mock: the case is about how the
            # error is raised. A file held open with no sharing on Windows, a
            # folder without write permission elsewhere -- either way Remove-Item
            # reports a non-terminating error, which a caller's 'Stop' turned
            # into one that left the command before step 4 had said anything.
            $lockedDir = Join-Path $script:data 'cache'
            $locked = Join-Path $lockedDir 'in-use.bin'
            New-Item -ItemType Directory -Path $lockedDir -Force | Out-Null
            [System.IO.File]::WriteAllText($locked, 'x')
            $onWindows = (Get-TStylesPlatform) -eq 'Windows'
            $hold = $null
            if ($onWindows) {
                $hold = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
            } else {
                & chmod 555 $lockedDir
            }
            try {
                $deletable = $true
                if (-not $onWindows) {
                    # root deletes anything. Saying so beats asserting on a
                    # fixture that never took.
                    try { [System.IO.File]::Delete($locked) } catch { $deletable = $false }
                    if ($deletable) {
                        Set-ItResult -Skipped -Because 'this user can delete inside a mode-555 folder, so the fixture did not take'
                        return
                    }
                }
                $ErrorActionPreference = 'Stop'
                $script:out = $null
                { $script:out = Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -DeleteData -ProfileTarget @() `
                                    2>$null 6>&1 | Out-String } | Should -Not -Throw
                $script:out | Should -Match 'could not remove all of'
                $script:out | Should -Match 'EXCEPT part of the data folder'
            } finally {
                if ($hold) { $hold.Dispose() } else { & chmod 755 $lockedDir }
            }
        }
    }
}
