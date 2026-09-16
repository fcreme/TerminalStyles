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
            # The $PROFILE discovery lives in Resolve-PowerShellProfileTarget
            # now -- one implementation shared by uninstall (through
            # Get-PowerShellProfileTarget, which only adds "files that exist")
            # and by register, which used to carry its own copy without the
            # "two engines, one file" merge. This assertion follows the
            # discovery rather than the caller; asserting on
            # Invoke-TerminalStylesUninstall's source would now pass or fail on
            # where the code sits rather than on what it does.
            $src = (Get-Command Resolve-PowerShellProfileTarget).ScriptBlock.ToString()
            $src | Should -Match 'Get-PowerShellEngineCandidate'
            $src | Should -Not -Match "'pwsh\.exe'"
            $src | Should -Not -Match "'powershell\.exe'"
        }

        It 'uninstall reaches its $PROFILE discovery' {
            # The half a source grep cannot see: that the caller still calls it.
            # Without this the check above is satisfied by a function nothing
            # runs, which is how a passing suite hid the last two defects here.
            $uninstall = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $uninstall | Should -Match 'Remove-PowerShellProfileLoader'
            $uninstall | Should -Match 'Get-PowerShellProfileTarget' `
                -Because 'the listing resolves the targets, and hands that same list to the strip'
            (Get-Command Get-PowerShellProfileTarget).ScriptBlock.ToString() |
                Should -Match 'Resolve-PowerShellProfileTarget'
        }

        It 'register reaches the same discovery, and does not re-implement it' {
            # The half that was missing. register had its own copy of "ask each
            # engine where its $PROFILE is", without the merge, so on a Mac with
            # the preview build it listed one file on two rows and wrote it
            # twice.
            $src = (Get-Command Invoke-TerminalStylesRegister).ScriptBlock.ToString()
            $src | Should -Match 'Resolve-PowerShellProfileTarget'
            $src | Should -Not -Match 'Write-Output \$PROFILE' `
                -Because 'asking each engine directly is the copy that diverged'
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
            #
            # Asked of .Labels, the list, rather than .Label: a target that
            # covers two engines now joins their names ("PowerShell 7 /
            # PowerShell 7 (preview)") so the row says what it really covers,
            # and the joined string is deliberately not one of the probe's own
            # labels. The list is where the individual names still live, and it
            # is what install.ps1's panel subtracts the current engine from.
            $labels = @((Get-PowerShellEngineCandidate).Label)
            foreach ($t in @(Get-PowerShellProfileTarget)) {
                @($t.Labels).Count | Should -BeGreaterThan 0
                foreach ($l in @($t.Labels)) { $labels | Should -Contain $l }
                $t.Label | Should -Be (@($t.Labels) -join ' / ')
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

    It 'de-duplicates a shared $PROFILE the same way the module does' {
        # The second copy of a rule, which is the shape most of CHANGELOG.md is.
        # install.ps1 cannot dot-source lib/, so "two engines, one $PROFILE,
        # one row" is written twice: Resolve-PowerShellProfileTarget in the
        # module, Get-EngineProfilePlan here. Both are run over the SAME pair of
        # stand-in engines and their answers compared, so a fix to one that
        # misses the other turns this red rather than shipping a register and an
        # installer that disagree about how many files they are about to write.
        $d = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $shared = Join-Path $d 'Microsoft.PowerShell_profile.ps1'
        # One stub answers BOTH question forms: the module asks for $PROFILE
        # alone, the installer asks for PROFILE= and POLICY= in one launch.
        $stubs = foreach ($n in 'a', 'b') {
            $path = Join-Path $d "engine-$n.ps1"
            $src = @'
param([switch]$NoProfile, [switch]$NonInteractive, [string]$Command)
if ($Command -match 'PROFILE=') {
    Write-Output ('PROFILE=' + '__P__')
    Write-Output 'POLICY=RemoteSigned'
} else {
    Write-Output '__P__'
}
'@.Replace('__P__', $shared)
            [System.IO.File]::WriteAllText($path, $src, [System.Text.UTF8Encoding]::new($false))
            $path
        }
        $labels = @('PowerShell 7', 'PowerShell 7 (preview)')

        $mine = @(Get-EngineProfilePlan -Engine @(
            [pscustomobject]@{ Exe = $stubs[0]; Label = $labels[0] }
            [pscustomobject]@{ Exe = $stubs[1]; Label = $labels[1] }
        ))
        $theirs = @(InModuleScope TerminalStyles -Parameters @{ s = $stubs; l = $labels } {
            param($s, $l)
            Mock Get-PowerShellEngineCandidate {
                @([pscustomobject]@{ Exe = $s[0]; Label = $l[0] },
                  [pscustomobject]@{ Exe = $s[1]; Label = $l[1] })
            }
            Resolve-PowerShellProfileTarget -IncludeMissing
        })

        $mine.Count | Should -Be 1 -Because 'this test is anchored on one file'
        $mine.Count | Should -Be $theirs.Count
        @($mine[0].Labels)      | Should -Be @($theirs[0].Labels)
        $mine[0].Label          | Should -Be $theirs[0].Label
        $mine[0].ProfilePath    | Should -Be $theirs[0].ProfilePath
    }

    It 'no longer throws when no engine is found' {
        # The files are already on disk by the time this runs, so throwing left
        # the user installed-but-unloaded with a stack trace instead of the one
        # line that fixes it.
        $src = [System.IO.File]::ReadAllText($script:installPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Not -Match 'throw "Neither pwsh\.exe nor powershell\.exe'
    }

    It 'advises the loader line THIS install needs, not a second literal of it' {
        # That advice is the only thing a user in this state has -- nothing
        # registered a loader for them, so they paste it into their own $PROFILE
        # by hand. It was a literal `Import-Module TerminalStyles
        # -DisableNameChecking` while the installer three lines up had written
        # the full-path form, and this branch only fires on a bootstrap install,
        # which is precisely where the bare name resolves to nothing.
        $loader = 'Import-Module "/somewhere/TerminalStyles/TerminalStyles.psd1" -DisableNameChecking'
        $out = Write-NoEngineNotice -InstallDir '/somewhere/TerminalStyles' -LoaderImport $loader 6>&1 | Out-String

        $out | Should -Match ([regex]::Escape($loader))
        $out | Should -Not -Match '(?m)^\s*Import-Module TerminalStyles -DisableNameChecking\s*$' `
            -Because 'the by-name form is not what this install got'
        $out | Should -Match ([regex]::Escape('/somewhere/TerminalStyles'))
    }
}
