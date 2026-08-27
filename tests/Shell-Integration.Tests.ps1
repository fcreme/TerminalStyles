# Pester 5 tests for the zsh/bash integration: the staged state the shell
# loader reads, and registration of the loader block in the user's rc files.
#
# The shell side itself (shell/tstyles.sh) is exercised by running real zsh and
# bash in Shell-Prompt.Tests.ps1; this file covers the PowerShell half.
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

Describe 'Register-ShellLoader' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:rc = Join-Path $TestDrive '.zshrc'
        }

        It 'adds the block to an existing rc file' {
            [System.IO.File]::WriteAllText($script:rc, "export PATH=/usr/bin`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Should -Be 'added'
            $c = [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))
            $c | Should -Match 'TerminalStyles BEGIN'
            $c | Should -Match 'TerminalStyles END'
        }

        It "preserves the user's existing content" {
            [System.IO.File]::WriteAllText($script:rc, "alias ll='ls -la'`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Should -Be 'added'
            [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false)) |
                Should -Match "alias ll='ls -la'"
        }

        It 'is idempotent -- a second run reports unchanged and adds no second block' {
            [System.IO.File]::WriteAllText($script:rc, '', [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Should -Be 'added'
            Register-ShellLoader -Path $script:rc | Should -Be 'unchanged'
            $c = [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))
            ([regex]::Matches($c, 'TerminalStyles BEGIN')).Count | Should -Be 1
        }

        It 'refreshes a stale block rather than appending a new one' {
            $stale = "# ===== TerminalStyles BEGIN =====`n. /old/dangling/path.sh`n# ===== TerminalStyles END ====="
            [System.IO.File]::WriteAllText($script:rc, "$stale`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Should -Be 'updated'
            $c = [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))
            ([regex]::Matches($c, 'TerminalStyles BEGIN')).Count | Should -Be 1
            $c | Should -Not -Match '/old/dangling/path.sh'
        }

        It 'skips a file that does not exist unless -Create is given' {
            # Creating ~/.bashrc on a machine that only uses zsh would be a
            # surprising side effect of styling a terminal.
            $missing = Join-Path $TestDrive '.bashrc'
            Register-ShellLoader -Path $missing | Should -Be 'skipped'
            Test-Path -LiteralPath $missing | Should -BeFalse
        }

        It 'creates the file when -Create is given' {
            $missing = Join-Path $TestDrive '.bash_profile'
            Register-ShellLoader -Path $missing -Create | Should -Be 'added'
            Test-Path -LiteralPath $missing | Should -BeTrue
        }

        It 'does not glue the block onto an rc file with no trailing newline' {
            [System.IO.File]::WriteAllText($script:rc, 'export FOO=1', [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $script:rc | Should -Be 'added'
            [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false)) |
                Should -Not -Match 'export FOO=1#'
        }
    }
}

Describe 'Unregister-ShellLoader' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:rc = Join-Path $TestDrive '.zshrc'
        }

        It 'removes the block and leaves the rest intact' {
            [System.IO.File]::WriteAllText($script:rc, "alias g=git`n", [System.Text.UTF8Encoding]::new($false))
            [void](Register-ShellLoader -Path $script:rc)
            Unregister-ShellLoader -Path $script:rc | Should -Be 'removed'
            $c = [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))
            $c | Should -Not -Match 'TerminalStyles'
            $c | Should -Match 'alias g=git'
        }

        It 'reports false when there is no block to remove' {
            [System.IO.File]::WriteAllText($script:rc, "alias g=git`n", [System.Text.UTF8Encoding]::new($false))
            # A STATUS, not a boolean: 'none', 'malformed' and 'failed' were all
            # $false, and two of them made shell-remove report success while
            # leaving a live loader in the file.
            Unregister-ShellLoader -Path $script:rc | Should -Be 'none'
        }

        It 'reports false for a missing file' {
            Unregister-ShellLoader -Path (Join-Path $TestDrive 'nope') | Should -Be 'none'
        }

        It 'round-trips: register then unregister restores the original bytes' {
            $original = "# my zshrc`nexport EDITOR=vim`n"
            [System.IO.File]::WriteAllText($script:rc, $original, [System.Text.UTF8Encoding]::new($false))
            [void](Register-ShellLoader -Path $script:rc)
            [void](Unregister-ShellLoader -Path $script:rc)
            # Trailing whitespace may differ by a newline; compare trimmed.
            ([System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false))).Trim() |
                Should -Be $original.Trim()
        }
    }
}

Describe 'Set-ShellStyleState / Clear-ShellStyleState' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:styleDir = Join-Path $TestDrive 'styles/fake'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'prompt.sh'),
                "# fake shell prompt`n", [System.Text.UTF8Encoding]::new($false))
            $script:scheme = [pscustomobject]@{
                name = 'fake'; background = '#101010'; foreground = '#f0f0f0'
            }
        }

        It 'writes the OSC packet the shell loader replays' {
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme
            $osc = [System.IO.File]::ReadAllText((Get-ShellOscPath), [System.Text.UTF8Encoding]::new($false))
            # Must be the exact same packet the PowerShell path emits, or a new
            # zsh tab would render a different palette from the pwsh one.
            $osc | Should -Be (Get-SchemeOscPacket -Scheme $script:scheme)
        }

        It "stages the style's shell prompt" {
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme
            Test-Path -LiteralPath (Get-ShellPromptPath) | Should -BeTrue
        }

        It '-KeepPrompt stages colors but no prompt' {
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme -KeepPrompt
            Test-Path -LiteralPath (Get-ShellOscPath)    | Should -BeTrue
            Test-Path -LiteralPath (Get-ShellPromptPath) | Should -BeFalse
        }

        It "drops a previous style's prompt when the new one ships none" {
            # Otherwise the old prompt would outlive the style that installed it.
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme
            Test-Path -LiteralPath (Get-ShellPromptPath) | Should -BeTrue

            $bare = Join-Path $TestDrive 'styles/bare'
            New-Item -ItemType Directory -Force -Path $bare | Out-Null
            Set-ShellStyleState -StyleName 'bare' -StyleDir $bare -Scheme $script:scheme
            Test-Path -LiteralPath (Get-ShellPromptPath) | Should -BeFalse
        }

        It 'clears both staged files' {
            Set-ShellStyleState -StyleName 'fake' -StyleDir $script:styleDir -Scheme $script:scheme
            Clear-ShellStyleState
            Test-Path -LiteralPath (Get-ShellOscPath)    | Should -BeFalse
            Test-Path -LiteralPath (Get-ShellPromptPath) | Should -BeFalse
        }

        It 'leaves the staged runtime in place on clear' {
            # The rc block sources it; deleting it would break the shell loader
            # rather than merely unstyling it.
            [void](Sync-ShellRuntime)
            $runtime = Get-ShellRuntimePath
            if (Test-Path -LiteralPath $runtime) {
                Clear-ShellStyleState
                Test-Path -LiteralPath $runtime | Should -BeTrue
            }
        }
    }
}

Describe 'Get-ShellRcCandidate' {
    InModuleScope TerminalStyles {
        It 'covers .zshrc, .bashrc and .bash_profile' {
            $paths = (Get-ShellRcCandidate -HomeDir '/home/x') | ForEach-Object { Split-Path -Leaf $_.Path }
            $paths | Should -Contain '.zshrc'
            $paths | Should -Contain '.bashrc'
            # Terminal.app launches bash as a LOGIN shell, which reads
            # .bash_profile and never .bashrc -- omitting it would leave macOS
            # bash users unstyled.
            $paths | Should -Contain '.bash_profile'
        }
    }
}

Describe 'the rc file survives contact with shell-init' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
        }

        It 'is byte-identical after repeated init/remove cycles' {
            # Register appended a blank line before the block and Unregister gave
            # back only one newline, so every cycle grew the file. shell-remove
            # is documented as a byte-exact reversal.
            $rc = Join-Path $script:h '.zshrc'
            $orig = "# mine`nexport A=1`n"
            [System.IO.File]::WriteAllText($rc, $orig, (Get-RcFileEncoding))
            $before = (Get-FileHash -Path $rc -Algorithm SHA256).Hash
            foreach ($i in 1..3) {
                Register-ShellLoader -Path $rc | Out-Null
                Unregister-ShellLoader -Path $rc | Out-Null
            }
            (Get-FileHash -Path $rc -Algorithm SHA256).Hash | Should -Be $before
        }

        It 'preserves bytes that are not valid UTF-8' {
            # Both halves read the WHOLE file and write it back, so one latin-1
            # byte in the user's own comment became U+FFFD on the first
            # shell-init and was gone for good.
            $rc = Join-Path $script:h '.zshrc'
            $bytes = [byte[]](0x23,0x20,0x63,0x61,0x66,0xE9,0x0A)   # "# caf<e9>\n"
            [System.IO.File]::WriteAllBytes($rc, $bytes)
            Register-ShellLoader -Path $rc | Out-Null
            Unregister-ShellLoader -Path $rc | Out-Null
            $after = [System.IO.File]::ReadAllBytes($rc)
            $after[0..5] | Should -Be $bytes[0..5] -Because 'the 0xE9 must still be 0xE9'
            [System.Linq.Enumerable]::Contains([byte[]]$after, [byte]0xEF) | Should -BeFalse `
                -Because '0xEF starts the UTF-8 replacement character'
        }
    }
}

Describe 'the loader block quotes the path safely' {
    InModuleScope TerminalStyles {

        It 'uses single quotes, so a $ in the path stays literal' {
            # A home directory containing '$' is legal, and inside "..." the
            # shell expanded it: the path came out wrong and the runtime silently
            # never loaded. No colours, no prompt, no error, on every shell.
            $block = Get-ShellLoaderBlock
            $block | Should -Match "\[ -r '" -Because 'double quotes do not protect $, ` or \'
            $block | Should -Not -Match '\[ -r "'
        }

        It 'closes and reopens around an apostrophe, the one char it cannot carry' {
            $src = (Get-Command Get-ShellLoaderBlock).ScriptBlock.ToString()
            $src | Should -Match "Replace\(" -Because 'an apostrophe in the path needs escaping'
        }
    }
}

Describe 'shell-init finds the rc file zsh actually reads' {
    InModuleScope TerminalStyles {

        It 'includes $ZDOTDIR/.zshrc when ZDOTDIR is set' {
            # zsh reads $ZDOTDIR/.zshrc and does NOT read ~/.zshrc, so for the
            # standard XDG layout the block went into a file zsh never opens --
            # and shell-init reported success.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $z = Join-Path $h '.config/zsh'
            New-Item -ItemType Directory -Path $z -Force | Out-Null
            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $z
                @(Get-ShellRcCandidate -HomeDir $h | ForEach-Object { $_.Path }) |
                    Should -Contain (Join-Path $z '.zshrc')
            } finally { $env:ZDOTDIR = $prev }
        }

        It 'does not duplicate it when ZDOTDIR is just $HOME' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $h
                $paths = @(Get-ShellRcCandidate -HomeDir $h | ForEach-Object { $_.Path })
                @($paths | Where-Object { $_ -eq (Join-Path $h '.zshrc') }).Count | Should -Be 1
            } finally { $env:ZDOTDIR = $prev }
        }
    }
}
