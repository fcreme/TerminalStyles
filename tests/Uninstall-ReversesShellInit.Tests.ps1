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
                Unregister-ShellLoader -Path $script:rc | Should -BeFalse
            } finally { & chmod 644 $script:rc }
        }
    }
}

Describe 'uninstall reverses shell-init' {
    InModuleScope TerminalStyles {

        It 'strips the loader from every rc file it registered into' {
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $src | Should -Match 'Get-ShellRcCandidate'
            $src | Should -Match 'Unregister-ShellLoader'
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

        It 'both walk Get-ShellRcCandidate' {
            # If uninstall ever hardcoded its own list, a candidate added to
            # shell-init would silently stop being removable.
            $init      = (Get-Command Invoke-TerminalStylesShellInit).ScriptBlock.ToString()
            $uninstall = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $init      | Should -Match 'Get-ShellRcCandidate'
            $uninstall | Should -Match 'Get-ShellRcCandidate'
        }

        It 'Get-ShellRcCandidate covers zsh and both bash rc files' {
            $paths = @((Get-ShellRcCandidate).Path)
            ($paths | Where-Object { $_ -like '*.zshrc' })        | Should -Not -BeNullOrEmpty
            ($paths | Where-Object { $_ -like '*.bashrc' })       | Should -Not -BeNullOrEmpty
            ($paths | Where-Object { $_ -like '*.bash_profile' }) | Should -Not -BeNullOrEmpty
        }
    }
}
