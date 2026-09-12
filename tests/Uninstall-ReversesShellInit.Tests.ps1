# Pester 5 tests: `tstyles uninstall` must undo `tstyles shell-init` too, and a
# single unwritable rc file must not take the whole command down.
#
# The bugs:
#   - uninstall stripped only the PowerShell $PROFILE loader. Afterwards every
#     new zsh/bash tab still repainted the palette, set the window title, printed
#     the style's banner and took over the prompt. And the documented way back --
#     `tstyles shell-remove` -- was already dead, because uninstall deletes
#     TerminalStyles.psd1, the exact path baked into the generated
#     tstyles-cli.ps1, so the shell's own `tstyles` could no longer load the
#     module. Hand-editing ~/.zshrc was the only recovery left.
#   - the install-managed list omitted terminals.ps1 (dot-sourced by tstyles.ps1)
#     and the staged shell runtime, so an orphaned rc block kept working: the
#     loader block guards on `[ -r "$runtime" ]`, and the runtime was still there.
#   - Register-/Unregister-ShellLoader wrote with no try/catch, so one read-only
#     rc file aborted the loop with a raw MethodInvocationException, after some
#     files had been written and before anything was reported.
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

Describe 'Register-ShellLoader fails softly' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:rc = Join-Path $TestDrive '.zshrc'
            [System.IO.File]::WriteAllText($script:rc, "# my own rc`n", [System.Text.UTF8Encoding]::new($false))
        }

        It 'returns failed rather than throwing when the file cannot be written' {
            if ($IsWindows) { Set-ItResult -Skipped -Because 'chmod is the POSIX way to make this unwritable'; return }
            & chmod 444 $script:rc
            try {
                # Two calls on purpose: an assignment made INSIDE the
                # Should -Not -Throw scriptblock lands in that scriptblock's own
                # child scope and is invisible out here. The call is idempotent
                # while the file stays unwritable.
                { Register-ShellLoader -Path $script:rc } | Should -Not -Throw
                Register-ShellLoader -Path $script:rc | Should -Be 'failed'
            } finally { & chmod 644 $script:rc }
        }

        It 'leaves the unwritable file untouched' {
            if ($IsWindows) { Set-ItResult -Skipped -Because 'chmod is the POSIX way to make this unwritable'; return }
            & chmod 444 $script:rc
            try {
                Register-ShellLoader -Path $script:rc | Out-Null
                [System.IO.File]::ReadAllText($script:rc) | Should -Not -Match 'TerminalStyles BEGIN'
            } finally { & chmod 644 $script:rc }
        }

        It 'still adds the block to a writable file' {
            Register-ShellLoader -Path $script:rc | Should -Be 'added'
            [System.IO.File]::ReadAllText($script:rc) | Should -Match 'TerminalStyles BEGIN'
        }

        It 'reports unchanged on a second run' {
            Register-ShellLoader -Path $script:rc | Out-Null
            Register-ShellLoader -Path $script:rc | Should -Be 'unchanged'
        }

        It 'skips a file that does not exist unless -Create' {
            $missing = Join-Path $TestDrive '.bashrc'
            Register-ShellLoader -Path $missing | Should -Be 'skipped'
            Test-Path -LiteralPath $missing | Should -BeFalse
        }

        It 'Unregister returns false rather than throwing on an unwritable file' {
            if ($IsWindows) { Set-ItResult -Skipped -Because 'chmod is the POSIX way to make this unwritable'; return }
            Register-ShellLoader -Path $script:rc | Out-Null
            & chmod 444 $script:rc
            try {
                { Unregister-ShellLoader -Path $script:rc } | Should -Not -Throw
                # 'failed', distinctly from 'none'. Reporting an unwritable file as
            # "there was no block here" told the user the opposite of the truth
            # and sent them hunting for a block still sitting in the file.
            Unregister-ShellLoader -Path $script:rc | Should -Be 'failed'
            } finally { & chmod 644 $script:rc }
        }
    }
}

Describe 'uninstall reverses shell-init' {
    InModuleScope TerminalStyles {

        It 'strips the loader from every rc file it registered into' {
            # Get-ShellRcRemovalCandidate, not Get-ShellRcCandidate: the file set
            # written to is a SUBSET of the file set that must be swept, because
            # shell-init also registers into ~/.profile. Asserting the narrow name
            # here is what let that block become unremovable.
            #
            # The strip itself goes through Remove-ShellLoaderBlock, which is the
            # one implementation of "unregister each file and report every
            # status" -- uninstall's own copy of that loop kept one of the four
            # statuses and dropped the rest. Either name satisfies the second
            # assertion, so moving the call back inline does not fail it; the
            # behavioural cases further down are what hold that shape.
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $src | Should -Match 'Get-ShellRcRemovalCandidate'
            $src | Should -Match '(Unregister-ShellLoader|Remove-ShellLoaderBlock)'
        }

        It 'clears the staged shell state the loader reads' {
            # current-style.osc and current-prompt.sh are what make a new zsh tab
            # come up themed. Leaving them is what kept the palette and banner
            # alive after an "uninstall".
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $src | Should -Match 'Clear-ShellStyleState'
        }

        It 'counts terminals.ps1 and the shell runtime as install-managed' {
            # tstyles.ps1 dot-sources terminals.ps1, and an orphaned rc block
            # loads the staged tstyles.sh -- the loader's own `[ -r ... ]` guard
            # only disarms it if the runtime is actually gone.
            #
            # Asked of Get-UninstallPlan rather than scraped out of the caller's
            # source: the list is data now, and a test that reads it as text
            # passes or fails on where it happens to be written.
            $plan = Get-UninstallPlan -DataDir (Join-Path $TestDrive 'no-manifest-here')
            foreach ($f in 'terminals.ps1', 'shell', 'tstyles.sh', 'tstyles-cli.ps1') {
                $plan.Items | Should -Contain $f -Because "$f is written by the install"
            }
        }

        It 'still removes what it always removed' {
            $plan = Get-UninstallPlan -DataDir (Join-Path $TestDrive 'no-manifest-here')
            foreach ($f in 'tstyles.ps1', 'apply.ps1', 'TerminalStyles.psd1') {
                $plan.Items | Should -Contain $f
            }
        }

        It 'removes the rest of what the bootstrap actually extracts' {
            # The hand-maintained list named 14 of the ~20 entries the bootstrap
            # unpacks, so CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md,
            # SECURITY.md, docs/, tests/, .github/ and .gitignore all survived an
            # uninstall -- verified by running one against a real sandboxed
            # install.
            $plan = Get-UninstallPlan -DataDir (Join-Path $TestDrive 'no-manifest-here')
            foreach ($f in 'CHANGELOG.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md',
                           'SECURITY.md', 'docs', 'tests', '.github', '.gitignore') {
                $plan.Items | Should -Contain $f -Because "the bootstrap extracts $f into the data root"
            }
        }
    }
}

Describe 'Get-UninstallPlan' {
    InModuleScope TerminalStyles {

        It 'never removes styles wholesale' {
            # The bug this exists to prevent, and the worst one found in this
            # project: bundled themes sit BESIDE the user's own under
            # <data-root>/styles (the README documents dropping a folder named
            # after a bundled theme to override it). The old list named 'styles'
            # and removed the tree, so a plain `tstyles uninstall` deleted every
            # style the user had authored or tuned -- one line after printing
            # "PRESERVE user state ... pass -DeleteData to wipe". Reproduced end
            # to end against a real sandboxed install before this was written.
            $plan = Get-UninstallPlan -DataDir (Join-Path $TestDrive 'no-manifest-here')
            $plan.Items | Should -Not -Contain 'styles'
        }

        It 'falls back when there is no manifest, and says so' {
            $plan = Get-UninstallPlan -DataDir (Join-Path $TestDrive 'no-manifest-here')
            $plan.Source | Should -Be 'fallback'
            @($plan.Items).Count | Should -BeGreaterThan 0
        }

        It 'removes exactly what the manifest names' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir '.installed-files'),
                "tstyles.ps1`nlib`nstyles/eva`nstyles/kitty`n",
                [System.Text.UTF8Encoding]::new($false))

            $plan = Get-UninstallPlan -DataDir $dir
            $plan.Source | Should -Be 'manifest'
            $plan.Items | Should -Contain 'styles/eva'
            foreach ($staged in 'tstyles.sh', 'tstyles-cli.ps1') {
                $plan.Items | Should -Contain $staged `
                    -Because 'shell-init stages it at runtime, so the extract manifest cannot name it'
            }
            $plan.Items | Should -Contain 'styles/kitty'
            $plan.Items | Should -Not -Contain 'styles'
            $plan.Items | Should -Contain '.installed-files' -Because 'the manifest is install-managed too'
        }

        It 'leaves a style the manifest does not name' {
            # The whole point of recording per style folder: the user's own are
            # not in it.
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir '.installed-files'),
                "styles/eva`n", [System.Text.UTF8Encoding]::new($false))

            (Get-UninstallPlan -DataDir $dir).Items | Should -Not -Contain 'styles/my-own'
        }

        It 'refuses a manifest line that would escape the data root' {
            # The manifest is written by the installer, but it sits in a
            # user-writable directory and drives Remove-Item -Recurse -Force.
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir '.installed-files'),
                "tstyles.ps1`n../../../etc/passwd`n/etc/passwd`nC:\Windows`nstyles/../../evil`n",
                [System.Text.UTF8Encoding]::new($false))

            $plan = Get-UninstallPlan -DataDir $dir
            $plan.Items | Should -Contain 'tstyles.ps1'
            foreach ($bad in '../../../etc/passwd', '/etc/passwd', 'C:\Windows', 'styles/../../evil') {
                $plan.Items | Should -Not -Contain $bad
            }
        }

        It 'falls back rather than removing nothing when the manifest is empty' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir '.installed-files'), "`n  `n",
                [System.Text.UTF8Encoding]::new($false))
            (Get-UninstallPlan -DataDir $dir).Source | Should -Be 'fallback'
        }
    }
}

Describe 'shell-init and uninstall agree on where the loader lives' {
    InModuleScope TerminalStyles {

        It 'both resolve their file list from the shared helpers' {
            # If uninstall ever hardcoded its own list, a candidate added to
            # shell-init would silently stop being removable.
            #
            # Removal deliberately walks the WIDER list: shell-init can register
            # into ~/.profile, which is not a registration candidate. This
            # assertion is a text lint and proves only that the names are
            # referenced -- the behavioural proof that the two are actually
            # inverse is the round-trip Describe below, which is what this one
            # failed to catch.
            $init      = (Get-Command Invoke-TerminalStylesShellInit).ScriptBlock.ToString()
            $uninstall = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $init      | Should -Match 'Get-ShellRcCandidate'
            $init      | Should -Match 'Get-ShellRcRemovalCandidate'
            $uninstall | Should -Match 'Get-ShellRcRemovalCandidate'
        }

        It 'the removal list is a superset of the registration list, plus ~/.profile' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null

            $reg = @((Get-ShellRcCandidate        -HomeDir $h).Path)
            $rem = @((Get-ShellRcRemovalCandidate -HomeDir $h).Path)

            foreach ($p in $reg) {
                $rem | Should -Contain $p -Because 'anything written must be sweepable'
            }
            $rem | Should -Contain (Join-Path $h '.profile') `
                -Because 'shell-init registers there when it is the only file login bash reads'
        }

        It 'Get-ShellRcCandidate covers zsh and both bash rc files' {
            $paths = @((Get-ShellRcCandidate).Path)
            ($paths | Where-Object { $_ -like '*.zshrc' })        | Should -Not -BeNullOrEmpty
            ($paths | Where-Object { $_ -like '*.bashrc' })       | Should -Not -BeNullOrEmpty
            ($paths | Where-Object { $_ -like '*.bash_profile' }) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'shell-init and shell-remove are actually inverse -- measured, not linted' {
    # The lint above ("both walk Get-ShellRcCandidate") passed for the whole life
    # of this bug. Sharing a helper name proves nothing about behaviour: shell-init
    # registers into ~/.profile in two branches, ~/.profile was not on the list
    # removal walked, and so `tstyles shell-remove` printed "removed from
    # ~/.bashrc" and "Open a new tab to get your original prompt back" while the
    # block stayed in the one file the login shell actually reads. After
    # `tstyles uninstall` it pointed at a deleted data root, forever, with nothing
    # left on the machine that could remove it.
    #
    # So do not ask what the source says. Run init, run remove, and count the
    # markers left on disk -- across every rc layout that reaches a different
    # branch of shell-init.
    InModuleScope TerminalStyles {

        It 'leaves no loader block behind for the <label> layout' -ForEach @(
            @{ label = 'nothing at all';        files = @() }
            @{ label = '~/.profile only';       files = @('.profile') }
            @{ label = '.bashrc + ~/.profile';  files = @('.bashrc', '.profile') }
            @{ label = '.bashrc only';          files = @('.bashrc') }
            @{ label = '.zshrc only';           files = @('.zshrc') }
            @{ label = 'bashrc + bash_profile'; files = @('.bashrc', '.bash_profile') }
        ) {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in $files) {
                [System.IO.File]::WriteAllText((Join-Path $h $f), "# original $f`n",
                    [System.Text.UTF8Encoding]::new($false))
            }

            # Pin $env:SHELL: the "nothing existed" fallback picks its target from
            # it, so an ambient value would make this depend on the machine.
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h -Force          *> $null
                Invoke-TerminalStylesShellInit -HomeDir $h -Remove         *> $null
            } finally { $env:SHELL = $prev }

            $left = @(Get-ChildItem -LiteralPath $h -File -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    [System.IO.File]::ReadAllText($_.FullName,
                        [System.Text.UTF8Encoding]::new($false)) -match 'TerminalStyles BEGIN'
                } | ForEach-Object { $_.Name })

            $left -join ', ' | Should -BeNullOrEmpty `
                -Because "shell-remove reported success, so nothing may still source the runtime (left in: $($left -join ', '))"
        }

        It 'gives the user back the file it found, for the <label> layout' -ForEach @(
            @{ label = '~/.profile only';      files = @('.profile') }
            @{ label = '.bashrc + ~/.profile'; files = @('.bashrc', '.profile') }
        ) {
            # Removing the block must not take the user's own lines with it.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in $files) {
                [System.IO.File]::WriteAllText((Join-Path $h $f), "# original $f`nexport MINE=1`n",
                    [System.Text.UTF8Encoding]::new($false))
            }

            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h -Force  *> $null
                Invoke-TerminalStylesShellInit -HomeDir $h -Remove *> $null
            } finally { $env:SHELL = $prev }

            foreach ($f in $files) {
                $text = [System.IO.File]::ReadAllText((Join-Path $h $f),
                    [System.Text.UTF8Encoding]::new($false))
                $text | Should -Match 'export MINE=1' -Because "$f was the user's file first"
            }
        }
    }
}

Describe 'shell-remove tells the truth about what it did' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:home = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:home -Force | Out-Null
            $script:rc = Join-Path $script:home '.zshrc'
            [System.IO.File]::WriteAllText($script:rc, "# mine`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Out-Null
        }

        It 'reports a BEGIN with no matching END instead of claiming success' {
            # Hand-edited rc, or an interrupted write. The strip pattern needs
            # both markers, so it matched nothing, the unchanged text was written
            # back, and $true was returned -- shell-remove said the loader was
            # gone and a new tab would restore the prompt, while every new shell
            # still sourced the runtime.
            $text = [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))
            $text = $text -replace '# ===== TerminalStyles END =====\r?\n?', ''
            [System.IO.File]::WriteAllText($script:rc, $text, [System.Text.UTF8Encoding]::new($false))

            Unregister-ShellLoader -Path $script:rc | Should -Be 'malformed'
            [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false)) |
                Should -Match 'TerminalStyles BEGIN' -Because 'nothing was removed, and the caller must not say otherwise'
        }

        It 'distinguishes an unwritable file from an empty one' {
            if ((Get-TStylesPlatform) -eq 'Windows') {
                Set-ItResult -Skipped -Because 'chmod is the POSIX way to make this unwritable'; return
            }
            & chmod 444 $script:rc
            try {
                Unregister-ShellLoader -Path $script:rc | Should -Be 'failed' `
                    -Because '"none" would tell the user there was never a block here'
            } finally { & chmod 644 $script:rc }
        }

        It 'still reports a clean removal as removed' {
            Unregister-ShellLoader -Path $script:rc | Should -Be 'removed'
            Unregister-ShellLoader -Path $script:rc | Should -Be 'none'
        }

        It 'every caller compares the status explicitly' {
            # Every status is a truthy STRING, so `if (Unregister-ShellLoader ...)`
            # is now true even for 'none' -- it would strip nothing and report
            # success for every rc file the user has.
            #
            # This lint passed for the whole life of the uninstall bug above:
            # `if ((Unregister-ShellLoader ...) -eq 'removed')` is not a bare
            # boolean, and it still threw 'failed' and 'malformed' away. So the
            # behavioural cases are the ones that matter, and the counter here
            # is the other half of the lesson -- the loop stopped covering
            # Invoke-TerminalStylesUninstall the moment it began routing through
            # the shared helper, and a `continue` with nothing behind it reports
            # green.
            $checked = 0
            foreach ($fn in 'Invoke-TerminalStylesShellInit', 'Invoke-TerminalStylesUninstall',
                            'Remove-ShellLoaderBlock', 'Remove-PowerShellProfileLoader') {
                $src = (Get-Command $fn).ScriptBlock.ToString()
                if ($src -notmatch 'Unregister-ShellLoader') { continue }
                $checked++
                $src | Should -Not -Match 'if \(Unregister-ShellLoader[^)]*\)\s*\{' `
                    -Because "$fn must not use the status as a bare boolean"
            }
            $checked | Should -BeGreaterThan 0 -Because 'a loop that never iterates reports green'
        }
    }
}

Describe 'the loader block never fails the rc file' {

    It 'uses an if, not a && that leaves exit status 1 when orphaned' {
        # The block is the LAST content of the rc file, so `[ -r x ] && . x`
        # with the runtime gone made the whole file exit 1: `set -e; source
        # ~/.bashrc` aborted before doing any work, `source ~/.bashrc &&
        # next-step` skipped next-step, and every new terminal opened showing a
        # failed status with no failing command behind it. Verified: healthy 0,
        # orphaned 1, both shells. Now 0 either way.
        $block = InModuleScope TerminalStyles { Get-ShellLoaderBlock }
        $block | Should -Match 'if \[ -r ' -Because 'the && form propagates a false exit status'
        $block | Should -Not -Match '\]\s*&&\s*\.'
    }
}

Describe 'bash login shells get the style' {
    InModuleScope TerminalStyles {

        It 'registers a .bash_profile for a user who has only .bashrc' {
            # macOS Terminal.app starts bash as a LOGIN shell, which reads
            # ~/.bash_profile and never ~/.bashrc. Register-ShellLoader skips a
            # file that does not exist, and the -Create fallback only fired when
            # NOTHING was registered -- so this user got a green "added
            # ~/.bashrc", opened a new window, and saw nothing at all.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $h '.bashrc'), "export FOO=1`n",
                [System.Text.UTF8Encoding]::new($false))

            # Pin $env:SHELL, like the round-trip above and for the same reason.
            # Creating a bash LOGIN file is now gated on the login shell being
            # bash -- unguarded, it also fired for a zsh user with a stale
            # ~/.bashrc and invented a ~/.bash_profile they never had. So this It
            # measured the zsh arm on a zsh machine and the bash arm on a bash
            # one, which is not what its name says it tests.
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            } finally { $env:SHELL = $prev }

            $bp = Join-Path $h '.bash_profile'
            Test-Path -LiteralPath $bp | Should -BeTrue -Because 'login bash reads this file, not .bashrc'
            $text = [System.IO.File]::ReadAllText($bp, [System.Text.UTF8Encoding]::new($false))
            $text | Should -Match 'TerminalStyles BEGIN'
            $text | Should -Match '\.bashrc' `
                -Because 'a bare .bash_profile would leave the user''s own .bashrc unloaded in login shells'
        }

        It 'uses an existing ~/.profile rather than shadowing it' {
            # Creating .bash_profile stops bash reading ~/.profile. If they have
            # one, that is where the loader belongs.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in '.bashrc', '.profile') {
                [System.IO.File]::WriteAllText((Join-Path $h $f), "# $f`n", [System.Text.UTF8Encoding]::new($false))
            }

            # Pinned for the same reason as the It above: ~/.profile is written
            # only when it is the file the LOGIN shell reads, which a zsh login
            # shell's never is (tests/Shell-Integration.Tests.ps1 asserts that
            # side), so leaving the ambient value in made the outcome depend on
            # whoever ran the suite.
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            } finally { $env:SHELL = $prev }

            Test-Path -LiteralPath (Join-Path $h '.bash_profile') | Should -BeFalse `
                -Because 'it would shadow the ~/.profile bash reads today'
            [System.IO.File]::ReadAllText((Join-Path $h '.profile'), [System.Text.UTF8Encoding]::new($false)) |
                Should -Match 'TerminalStyles BEGIN'
        }

        It 'uses an existing ~/.profile when there is no rc file at all' {
            # The same rule as the test above, on the other branch. That one has
            # a .bashrc, so the loader is registered before the "nothing existed"
            # fallback is reached. Here NOTHING exists except ~/.profile, which
            # is not an rc candidate -- so the fallback creates ~/.bashrc, and
            # used to stop there: it declined to write a .bash_profile (correctly,
            # it would shadow ~/.profile) but never registered in ~/.profile
            # either. Login bash reads ~/.profile, which sources nothing, so the
            # user got a green "added ~/.bashrc" and a shell that never loaded it
            # -- the exact failure the fallback exists to prevent, in the one
            # layout it did not cover.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $h '.profile'), "# .profile`n",
                [System.Text.UTF8Encoding]::new($false))

            # The fallback picks its target from $env:SHELL, so pin it: on a zsh
            # machine this would take the zsh arm and test nothing.
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            } finally { $env:SHELL = $prev }

            Test-Path -LiteralPath (Join-Path $h '.bash_profile') | Should -BeFalse `
                -Because 'it would shadow the ~/.profile bash reads today'
            [System.IO.File]::ReadAllText((Join-Path $h '.profile'), [System.Text.UTF8Encoding]::new($false)) |
                Should -Match 'TerminalStyles BEGIN' `
                -Because 'it is the only file this login shell will read'
        }

        It 'leaves an existing .bash_profile alone apart from the block' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in '.bashrc', '.bash_profile') {
                [System.IO.File]::WriteAllText((Join-Path $h $f), "# original $f`n", [System.Text.UTF8Encoding]::new($false))
            }
            Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            [System.IO.File]::ReadAllText((Join-Path $h '.bash_profile'), [System.Text.UTF8Encoding]::new($false)) |
                Should -Match 'original \.bash_profile'
        }
    }
}

Describe 'both rc-removal callers report every file they could not strip' {
    # The consent screen NAMES the rc files uninstall is about to change, one
    # per line, and then step 2 compared Unregister-ShellLoader's four-state
    # status against exactly one of its values. 'failed' (an unwritable rc file
    # -- the managed-dotfile case that function's own docstring names) and
    # 'malformed' (a BEGIN with no END) printed nothing, were counted as
    # nothing, and the command signed off on "TerminalStyles uninstalled." with
    # the block still in two of the files it had just listed. Step 1 has removed
    # the module by then, so `tstyles shell-remove` -- the documented way out --
    # is gone too, and the user was never told there was anything to remove.
    #
    # Run over BOTH callers of the same rule, because that is the shape of the
    # defect: shell-remove switched on all four statuses and uninstall kept its
    # own single-arm copy. Whichever way a future edit breaks them apart, one of
    # these two cases goes red.
    #
    # Driven through the real commands, past consent, with every path they can
    # reach inside TestDrive: -HomeDir for the rc half, a mocked data root for
    # the staged files, the Bootstrap branch so Uninstall-PSResource is never
    # reached, and both seams of the $PROFILE half pinned to an empty list.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:savedData = $script:TStylesDataRoot
            $script:TStylesDataRoot = $script:data
            Mock Get-TStylesDataRoot { $script:data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            # -ProfileTarget @() already pins this; the mock is the second lock
            # on the one seam whose failure would reach the operator's own
            # $PROFILE, because that list is discovered by RUNNING each engine.
            Mock Get-PowerShellProfileTarget { @() }
            Mock Confirm-Action { $true }

            # Three rc files, each carrying a block this code wrote itself, in
            # the three states Unregister-ShellLoader distinguishes.
            $script:clean = Join-Path $script:h '.zshrc'
            $script:stuck = Join-Path $script:h '.bashrc'
            $script:broke = Join-Path $script:h '.profile'
            foreach ($p in $script:clean, $script:stuck, $script:broke) {
                [System.IO.File]::WriteAllText($p, "# original`nexport MINE=1`n",
                    [System.Text.UTF8Encoding]::new($false))
                Register-ShellLoader -Path $p | Should -Be 'added' -Because 'the fixture must plant a real block'
            }
            $t = [System.IO.File]::ReadAllText($script:broke, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($script:broke,
                ($t -replace '# ===== TerminalStyles END =====\r?\n?', ''),
                [System.Text.UTF8Encoding]::new($false))
            # IsReadOnly rather than chmod: one .NET attribute on every platform
            # the suite runs on, where chmod is an external binary that only
            # happens to exist on the Windows runners.
            (Get-Item -LiteralPath $script:stuck -Force).IsReadOnly = $true
        }
        AfterEach {
            (Get-Item -LiteralPath $script:stuck -Force).IsReadOnly = $false
            $script:TStylesDataRoot = $script:savedData
        }

        It '<caller> names both files it could not strip, and does not claim it finished' -ForEach @(
            @{ caller = 'shell-remove'; falseClaim = 'original prompt back'
               qualifier = 'NOT fully removed' }
            @{ caller = 'uninstall';    falseClaim = '(?m)^TerminalStyles uninstalled\.\s*$'
               qualifier = 'EXCEPT' }
        ) {
            $out = if ($caller -eq 'uninstall') {
                Invoke-TerminalStylesUninstall -HomeDir $script:h -Yes -ProfileTarget @() 6>&1 | Out-String
            } else {
                Invoke-TerminalStylesShellInit -HomeDir $script:h -Remove 6>&1 | Out-String
            }

            $out | Should -Match ([regex]::Escape($script:stuck))
            $out | Should -Match 'could not write'
            $out | Should -Match ([regex]::Escape($script:broke))
            $out | Should -Match 'no matching END'
            $out | Should -Match 'by hand'

            # The last line the user reads. uninstall printed its unconditionally.
            $out | Should -Not -Match $falseClaim
            $out | Should -Match $qualifier

            # The half that makes the silence a lie rather than a cosmetic slip.
            foreach ($p in $script:stuck, $script:broke) {
                [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false)) |
                    Should -Match 'TerminalStyles BEGIN' -Because "$p would otherwise have been reported gone"
            }

            # ...and the ordinary file still comes out clean, with the user's
            # own line still in it.
            $after = [System.IO.File]::ReadAllText($script:clean, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Not -Match 'TerminalStyles BEGIN'
            $after | Should -Match 'export MINE=1'
        }
    }
}

Describe 'uninstall says nothing extra when every rc file came out clean' {
    # The other direction: a command that now qualifies its sign-off must not
    # qualify it on the ordinary path, or the qualifier stops meaning anything.
    InModuleScope TerminalStyles {
        It 'closes on the plain line when there was nothing to report' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $data = Join-Path $h 'data'
            New-Item -ItemType Directory -Path $data -Force | Out-Null
            $saved = $script:TStylesDataRoot
            $script:TStylesDataRoot = $data
            Mock Get-TStylesDataRoot { $data }
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            Mock Get-PowerShellProfileTarget { @() }
            Mock Confirm-Action { $true }

            $rc = Join-Path $h '.zshrc'
            [System.IO.File]::WriteAllText($rc, "# original`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $rc | Should -Be 'added'

            try {
                $out = Invoke-TerminalStylesUninstall -HomeDir $h -Yes -ProfileTarget @() 6>&1 | Out-String
            } finally { $script:TStylesDataRoot = $saved }

            $out | Should -Match '(?m)^TerminalStyles uninstalled\.\s*$'
            $out | Should -Not -Match 'EXCEPT'
            [System.IO.File]::ReadAllText($rc, [System.Text.UTF8Encoding]::new($false)) |
                Should -Not -Match 'TerminalStyles BEGIN'
        }
    }
}

Describe 'an rc file that cannot even be READ is a status, not a stack trace' {
    # Found while reproducing the one above. Unregister-ShellLoader guards its
    # WRITE and not its READ, so a file the tool has no read permission on threw
    # a raw MethodInvocationException out of the middle of both callers -- past
    # every remaining rc file, past the WezTerm cleanup and past the $PROFILE
    # strip. The whole point of the status vocabulary is that one bad rc file
    # cannot take the command down.
    InModuleScope TerminalStyles {
        It 'reports failed rather than throwing' {
            if ((Get-TStylesPlatform) -eq 'Windows') {
                Set-ItResult -Skipped -Because 'chmod is the POSIX way to make a file unreadable'; return
            }
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $script:TStylesDataRoot = $TestDrive
            $rc = Join-Path $h '.zshrc'
            [System.IO.File]::WriteAllText($rc, "# mine`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $rc | Should -Be 'added'
            & chmod 000 $rc
            $readable = $true
            try { [System.IO.File]::ReadAllText($rc) | Out-Null } catch { $readable = $false }
            try {
                if ($readable) {
                    # root reads anything. Saying so beats asserting on a
                    # fixture that never took.
                    Set-ItResult -Skipped -Because 'this user can read a mode-000 file, so the fixture did not take'
                    return
                }
                { Unregister-ShellLoader -Path $rc } | Should -Not -Throw
                Unregister-ShellLoader -Path $rc | Should -Be 'failed'
            } finally { & chmod 644 $rc }
        }
    }
}
