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

            # Named, not set in the environment. These two used to assign
            # $env:ZDOTDIR and restore it in a finally -- correct as far as it
            # went, but it made the ambient variable the interface, and the
            # next test file to sandbox -HomeDir without knowing that wrote a
            # loader block into the developer's own zsh config. The parameter
            # is the interface now.
            @(Get-ShellRcCandidate -HomeDir $h -ZDotDir $z | ForEach-Object { $_.Path }) |
                Should -Contain (Join-Path $z '.zshrc')
        }

        It 'does not duplicate it when ZDOTDIR is just $HOME' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $paths = @(Get-ShellRcCandidate -HomeDir $h -ZDotDir $h | ForEach-Object { $_.Path })
            @($paths | Where-Object { $_ -eq (Join-Path $h '.zshrc') }).Count | Should -Be 1
        }

        It 'a sandboxed -HomeDir does not reach the ambient $env:ZDOTDIR' {
            # The seam itself. -HomeDir is what every test in this suite uses
            # to stay inside TestDrive, and one candidate of the four used to
            # ignore it and read the live environment, so running the suite on
            # any machine with ZDOTDIR set -- the XDG layout this candidate
            # exists to support -- permanently appended a loader block to the
            # developer's real .zshrc, pointing at a Pester temp directory that
            # is deleted when the run ends. Nothing removed it and the run
            # reported all green.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null

            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $outside
                $paths = @(Get-ShellRcCandidate -HomeDir $h | ForEach-Object { $_.Path })
                $paths | Should -Not -Contain (Join-Path $outside '.zshrc') `
                    -Because 'a sandboxed home must not reach a zsh config dir outside it'
                foreach ($p in $paths) {
                    $p | Should -BeLike "$h*" -Because 'every candidate must sit inside the sandbox'
                }
            } finally { $env:ZDOTDIR = $prev }
        }

        It 'shell-init with a sandboxed -HomeDir writes nothing outside it' {
            # End to end through the entry point the offending test file calls,
            # which is where the leak actually did its damage.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            $victim = Join-Path $outside '.zshrc'
            [System.IO.File]::WriteAllText($victim, "# a developer's real zsh config`nexport EDITOR=vim`n")
            $before = [System.IO.File]::ReadAllText($victim)

            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $outside
                Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            } finally { $env:ZDOTDIR = $prev }

            [System.IO.File]::ReadAllText($victim) | Should -Be $before `
                -Because 'running the test suite must not edit the developer''s own shell config'
        }

        It 'still registers in $ZDOTDIR when the caller names one' {
            # The other direction: the sandbox rule must not disable the
            # feature for a caller that asks for it, or for a real user.
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $z = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $z -Force | Out-Null

            # The rc file must EXIST. shell-init registers in the files it
            # finds, and when it finds none at all it falls back to creating
            # one for the login shell -- picked from $env:SHELL. Leaving both
            # directories empty therefore made this assertion depend on the
            # ambient shell: it passed on a zsh machine and failed on bash,
            # which is every CI leg here (ubuntu's runner shell is bash, and on
            # Windows $env:SHELL is not set at all, so the check short-circuits
            # to bash). Creating the file first makes the registration
            # deterministic and tests the thing this It is named for.
            $zshrc = Join-Path $z '.zshrc'
            [System.IO.File]::WriteAllText($zshrc, "# a relocated zsh config`n")

            Invoke-TerminalStylesShellInit -HomeDir $h -ZDotDir $z -Force *> $null

            [System.IO.File]::ReadAllText($zshrc) | Should -Match 'TerminalStyles BEGIN'
        }

        It 'a bare call still reads the live $env:ZDOTDIR' {
            # The branch every REAL user takes, and the one the rest of this
            # Describe stopped covering when the other tests moved onto the
            # -ZDotDir parameter. Without this, deleting $ZDOTDIR support
            # outright left the entire suite green -- verified by mutation:
            # replacing the ambient read with $null scored PASS=1249 FAIL=0,
            # identical to the unmutated tree, while the built module silently
            # registered in ~/.zshrc and told the user to source a file zsh
            # never opens. That is the 0.8.18 defect, undetectable.
            #
            # Read-only on purpose: it asks for the candidate LIST and writes
            # nothing, so it can exercise the unsandboxed path safely.
            $z = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $z -Force | Out-Null

            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $z
                @(Get-ShellRcCandidate | ForEach-Object { $_.Path }) |
                    Should -Contain (Join-Path $z '.zshrc') `
                    -Because 'a caller that sandboxes nothing must still get the live ZDOTDIR'
            } finally { $env:ZDOTDIR = $prev }
        }
    }
}

Describe 'the shell shim does not pin a PSGallery install to one version' {
    # The shim bakes an absolute Import-Module into $DataRoot/tstyles-cli.ps1.
    # That is REQUIRED for a bootstrap install, which is not on
    # $env:PSModulePath. It is wrong for a PSGallery install, whose module root
    # is version-stamped and whose updates install ALONGSIDE rather than in
    # place -- 0.8.17, 0.8.18 and 0.8.19 sitting side by side is the ordinary
    # state of that directory.
    #
    # Baking the versioned path in pinned the shell's `tstyles` to whichever
    # version was current when shell-init last ran. `tstyles update` from zsh
    # ran Update-PSResource, printed "Update complete", and the next `tstyles`
    # still executed the old code -- so the user silently kept every bug that
    # release fixed and never saw a new bundled style.
    #
    # The old comment claimed regeneration on every apply refreshed the path.
    # It cannot: the regeneration runs inside the module the shim just loaded,
    # so it rewrites the same stale root. A fixed point, with no way out from
    # the shell.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:shimData = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:shimData -Force | Out-Null
            $script:TStylesDataRoot = $script:shimData
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'a PSGallery install imports by NAME, so autoload picks the newest version' {
            Mock Get-TStylesDataRoot { Join-Path $TestDrive 'some-other-data-root' }
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet' -Because 'the fixture must set the branch under test'

            Sync-ShellRuntime | Should -BeTrue
            $shim = [System.IO.File]::ReadAllText((Get-ShellCliPath))

            $shim | Should -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$'
            $shim | Should -Not -Match 'TerminalStyles\.psd1' `
                -Because 'a version-stamped path is exactly what pins the shell to an old release'
        }

        It 'a BOOTSTRAP install still gets the absolute path, which it needs' {
            Mock Get-TStylesDataRoot { $script:TStylesModuleRoot }
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap'

            Sync-ShellRuntime | Should -BeTrue
            $shim = [System.IO.File]::ReadAllText((Get-ShellCliPath))

            $shim | Should -Match 'TerminalStyles\.psd1' `
                -Because 'the bootstrap directory is not on $env:PSModulePath'
        }

        It 'the shim still suppresses the auto-load side effects either way' {
            # `tstyles list` from zsh used to repaint the terminal and print the
            # previous style's banner before listing anything. Whatever the
            # import form, that guard has to survive.
            Mock Get-TStylesDataRoot { Join-Path $TestDrive 'yet-another-root' }
            Sync-ShellRuntime | Out-Null
            [System.IO.File]::ReadAllText((Get-ShellCliPath)) |
                Should -Match '\$global:TStylesNoAutoLoad\s*=\s*\$true'
        }
    }
}
