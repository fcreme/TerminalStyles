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
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $items = [regex]::Match($src, '(?s)\$installManagedItems = @\((.*?)\)').Groups[1].Value
            $items | Should -Not -BeNullOrEmpty
            foreach ($f in "'terminals.ps1'", "'shell'", "'tstyles.sh'", "'tstyles-cli.ps1'") {
                $items | Should -Match ([regex]::Escape($f)) -Because "$f is written by the install"
            }
        }

        It 'still removes what it always removed' {
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            $items = [regex]::Match($src, '(?s)\$installManagedItems = @\((.*?)\)').Groups[1].Value
            foreach ($f in "'tstyles.ps1'", "'apply.ps1'", "'TerminalStyles.psd1'", "'styles'") {
                $items | Should -Match ([regex]::Escape($f))
            }
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
