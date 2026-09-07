# Pester 5 tests for Get-PowerShellEngineCandidate -- which PowerShell binaries
# `tstyles register` and `tstyles uninstall` look for.
#
# The bug: both probed only `pwsh.exe` and `powershell.exe`. Off Windows the
# binary is `pwsh`, with no extension, and Windows PowerShell does not exist at
# all -- so on macOS and Linux `tstyles register` printed "Neither pwsh.exe nor
# powershell.exe was found on PATH. Nothing to do." and did exactly that, while
# the README told those users to run it. `tstyles uninstall` used the same probe
# and so could not strip the loader either. Both on the platforms 0.8.0 added.
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

Describe 'Get-PowerShellEngineCandidate' {
    InModuleScope TerminalStyles {

        It 'offers both Windows engines on Windows' {
            $c = @(Get-PowerShellEngineCandidate -Platform 'Windows')
            $c.Exe | Should -Contain 'pwsh.exe'
            $c.Exe | Should -Contain 'powershell.exe'
        }

        It 'offers the extension-less binary on <_>' -ForEach @('MacOS', 'Linux') {
            $c = @(Get-PowerShellEngineCandidate -Platform $_)
            $c.Exe | Should -Contain 'pwsh'
        }

        It 'also offers pwsh-preview off Windows' -ForEach @('MacOS', 'Linux') {
            # Not a nicety: Homebrew's stable cask went away, so some macOS
            # machines have pwsh-preview INSTEAD of pwsh, not alongside it.
            $c = @(Get-PowerShellEngineCandidate -Platform $_)
            $c.Exe | Should -Contain 'pwsh-preview'
        }

        It 'never offers a .exe off Windows' -ForEach @('MacOS', 'Linux') {
            $c = @(Get-PowerShellEngineCandidate -Platform $_)
            ($c.Exe | Where-Object { $_ -like '*.exe' }) | Should -BeNullOrEmpty
        }

        It 'never offers Windows PowerShell off Windows' -ForEach @('MacOS', 'Linux') {
            # It does not exist there, so probing for it is pure noise.
            $c = @(Get-PowerShellEngineCandidate -Platform $_)
            ($c.Exe | Where-Object { $_ -like 'powershell*' }) | Should -BeNullOrEmpty
        }

        It 'labels every candidate' {
            foreach ($p in 'Windows','MacOS','Linux') {
                foreach ($c in @(Get-PowerShellEngineCandidate -Platform $p)) {
                    $c.Exe   | Should -Not -BeNullOrEmpty
                    $c.Label | Should -Not -BeNullOrEmpty
                }
            }
        }

        It 'finds a real engine on the machine running these tests' {
            # The point of the whole fix: whatever platform CI is on, at least
            # one candidate must actually resolve -- otherwise register is a
            # no-op there, which is the bug.
            $found = @((Get-PowerShellEngineCandidate).Exe |
                Where-Object { Get-Command $_ -ErrorAction SilentlyContinue })
            $found | Should -Not -BeNullOrEmpty -Because 'register/uninstall probe this list'
        }
    }
}

Describe 'register and uninstall use the shared probe' {
    InModuleScope TerminalStyles {

        It 'Invoke-TerminalStylesRegister hardcodes no engine name' {
            $src = (Get-Command Invoke-TerminalStylesRegister).ScriptBlock.ToString()
            $src | Should -Match 'Get-PowerShellEngineCandidate'
            $src | Should -Not -Match "'pwsh\.exe'"
            $src | Should -Not -Match "'powershell\.exe'"
        }

        It 'the uninstall side hardcodes no engine name' {
            # Uninstall's $PROFILE discovery lives in Get-PowerShellProfileTarget
            # now -- pulled out so the strip below it can be run against a
            # sandbox at all. This assertion follows the discovery rather than
            # the caller; asserting on Invoke-TerminalStylesUninstall's source
            # would now pass or fail on where the code sits rather than on what
            # it does.
            $src = (Get-Command Get-PowerShellProfileTarget).ScriptBlock.ToString()
            $src | Should -Match 'Get-PowerShellEngineCandidate'
            $src | Should -Not -Match "'pwsh\.exe'"
            $src | Should -Not -Match "'powershell\.exe'"
        }

        It 'uninstall reaches its $PROFILE discovery' {
            # The half a source grep cannot see: that the caller still calls it.
            # Without this the check above is satisfied by a function nothing
            # runs, which is how a passing suite hid the last two defects here.
            (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString() |
                Should -Match 'Remove-PowerShellProfileLoader'
            (Get-Command Remove-PowerShellProfileLoader).ScriptBlock.ToString() |
                Should -Match 'Get-PowerShellProfileTarget'
        }

        It 'names each $PROFILE once, even when two engines share one' {
            # pwsh and pwsh-preview report the same path on a macOS machine that
            # has both; processing it twice would print the malformed and
            # unwritable warnings twice for one file.
            #
            # ForEach-Object, not @((...).ProfilePath): member access on an
            # EMPTY array yields a single $null rather than nothing, so the
            # first draft compared 1 against 0 and failed on every CI machine
            # -- none of which has a $PROFILE file at all. Vacuous where there
            # are no targets, which is the honest thing for it to be: it cannot
            # create a $PROFILE to test against without writing to a real one.
            $paths = @(Get-PowerShellProfileTarget | ForEach-Object { $_.ProfilePath })
            ($paths | Select-Object -Unique).Count | Should -Be $paths.Count
        }

        It 'every discovered target carries a label from the shared probe' {
            # Behavioural, not textual: whatever engines this machine has, each
            # target names one of them.
            $labels = @((Get-PowerShellEngineCandidate).Label)
            foreach ($t in @(Get-PowerShellProfileTarget)) {
                $labels | Should -Contain $t.Label
                $t.ProfilePath | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'install.ps1 keeps its own copy in step' {
    # The bootstrap runs via `iwr | iex` BEFORE the module exists on disk, so it
    # cannot dot-source the library the way apply.ps1 does. The duplication is
    # unavoidable; the divergence is not.
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'defines the same helper' {
        Get-Command Get-PowerShellEngineCandidate -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'returns the same engines as the module for <_>' -ForEach @('Windows','MacOS','Linux') {
        $mine   = @((Get-PowerShellEngineCandidate -Platform $_).Exe)
        $theirs = @(InModuleScope TerminalStyles -Parameters @{ p = $_ } {
            param($p) (Get-PowerShellEngineCandidate -Platform $p).Exe
        })
        $mine | Should -Be $theirs
    }

    It 'no longer throws when no engine is found' {
        # The files are already on disk by the time this runs, so throwing left
        # the user installed-but-unloaded with a stack trace instead of the one
        # line that fixes it.
        $src = [System.IO.File]::ReadAllText($script:installPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Not -Match 'throw "Neither pwsh\.exe nor powershell\.exe'
        $src | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
    }
}
