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

Describe 'the loader span never crosses a second BEGIN' {
    # An rc file carrying a stray or duplicated BEGIN -- a hand edit, a merged
    # dotfile, an interrupted write, the inputs Unregister-ShellLoader's own
    # docstring names -- used to cost the user every line between that marker
    # and the next END. `BEGIN .*? END` under Singleline is lazy in the END
    # only: the match still starts at the FIRST BEGIN in the file. Register
    # overwrote that whole span with its three-line block, Unregister deleted it
    # outright, and both reported success -- with nothing to undo it, because
    # the first-touch rule skips a file that already carries a BEGIN, so neither
    # of those two paths takes a backup. The pattern is the only thing standing
    # between a stray marker and the user's own lines.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            # Its own directory per test, so the backup count below can only
            # ever see files this test made.
            $script:rcDir = Join-Path $TestDrive ('rc-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Force -Path $script:rcDir | Out-Null
            $script:rc        = Join-Path $script:rcDir '.zshrc'
            $script:beginMark = '# ===== TerminalStyles BEGIN ====='
            $script:endMark   = '# ===== TerminalStyles END ====='
            $script:staleBlk  = "$script:beginMark`n. '/old/dangling/path.sh'`n$script:endMark"
            $script:utf8      = [System.Text.UTF8Encoding]::new($false)
        }

        It 'refreshes only its own block, byte for byte, when a stray BEGIN sits above it' {
            $before = "alias ll='ls -la'`n$script:beginMark`nexport MY_KEEP=1`n$script:staleBlk`nalias gs='git status'`n"
            [System.IO.File]::WriteAllText($script:rc, $before, $script:utf8)

            Register-ShellLoader -Path $script:rc | Should -Be 'updated'

            # Everything outside the well-formed block is untouched, and the
            # block itself really was refreshed -- so this cannot pass by the
            # function having declined to do anything.
            $expected = "alias ll='ls -la'`n$script:beginMark`nexport MY_KEEP=1`n" +
                        (Get-ShellLoaderBlock).Trim() + "`nalias gs='git status'`n"
            [System.IO.File]::ReadAllText($script:rc, $script:utf8) | Should -Be $expected

            # And no copy was taken, which is the point: on the refresh path
            # there is no backup to recover those lines from, so the pattern is
            # the only thing protecting them. The listing needs -Force -- without
            # it a dotfile-named backup reads as absent on Unix and the count
            # would be comparing nothing.
            @(Get-ChildItem -LiteralPath $script:rcDir -Filter '.zshrc.bak-*' -Force).Count |
                Should -Be 0 -Because 'the refresh path takes no first-touch backup, by design'
        }

        It 'keeps the rc lines when several stray BEGINs stack above the block' {
            $before = "$script:beginMark`nexport A=1`n$script:beginMark`nexport B=2`n$script:staleBlk`nexport C=3`n"
            [System.IO.File]::WriteAllText($script:rc, $before, $script:utf8)

            Register-ShellLoader -Path $script:rc | Should -Be 'updated'

            $after = [System.IO.File]::ReadAllText($script:rc, $script:utf8)
            $after | Should -Match 'export A=1'
            $after | Should -Match 'export B=2'
            $after | Should -Match 'export C=3'
            $after | Should -Not -Match 'dangling'
        }

        It 'keeps the rc lines when the file uses CRLF endings' {
            # An rc file that has been through a Windows editor -- Git Bash and
            # WSL interop both produce them -- carries CRLF, and the span has to
            # stop at the right marker across those endings too.
            $crlfStale = "$script:beginMark`r`n. '/old/dangling/path.sh'`r`n$script:endMark"
            $before = "alias ll='ls -la'`r`n$script:beginMark`r`nexport MY_KEEP=1`r`n$crlfStale`r`nalias gs='git status'`r`n"
            [System.IO.File]::WriteAllText($script:rc, $before, $script:utf8)

            Register-ShellLoader -Path $script:rc | Should -Be 'updated'

            $after = [System.IO.File]::ReadAllText($script:rc, $script:utf8)
            $after | Should -Match 'export MY_KEEP=1'
            $after | Should -Match "alias ll='ls -la'"
            $after | Should -Match "alias gs='git status'"
            $after | Should -Not -Match 'dangling'
        }

        It 'leaves the file untouched when there is a BEGIN and no END anywhere' {
            # Nothing here can be OUR block, so nothing may be rewritten. The
            # status Register-ShellLoader returns for this input is a separate
            # defect and is deliberately not asserted: it says 'updated' while
            # writing nothing, which is a lie about a file it left intact, not a
            # file it destroyed.
            $before = "alias ll='ls -la'`n$script:beginMark`nexport MY_KEEP=1`n"
            [System.IO.File]::WriteAllText($script:rc, $before, $script:utf8)

            [void](Register-ShellLoader -Path $script:rc)

            [System.IO.File]::ReadAllText($script:rc, $script:utf8) | Should -Be $before
        }

        It 'strips only its own block when a stray BEGIN sits above it' {
            # shell-remove, and uninstall, which strips rc files and the
            # $PROFILE through this same function. 'malformed' could not save
            # this input: that guard fires only when there is no END ANYWHERE.
            $before = "alias ll='ls -la'`n$script:beginMark`nexport MY_KEEP=1`n$script:staleBlk`nalias gs='git status'`n"
            [System.IO.File]::WriteAllText($script:rc, $before, $script:utf8)

            Unregister-ShellLoader -Path $script:rc | Should -Be 'removed'

            $after = [System.IO.File]::ReadAllText($script:rc, $script:utf8)
            $after | Should -Match 'export MY_KEEP=1'
            $after | Should -Match "alias ll='ls -la'"
            $after | Should -Match "alias gs='git status'"
            $after | Should -Not -Match 'dangling'
            ([regex]::Matches($after, [regex]::Escape($script:endMark))).Count | Should -Be 0
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

Describe 'shell-init reaches the shell the user actually logs in to' {
    # 0.8.21 and 0.8.22 each fixed a layout where the loader landed in a file the
    # login shell never reads. Both were bash's. The decision underneath them --
    # which shell the user logs IN to -- was computed inside the "nothing existed
    # at all" fallback, which fires only when not one rc file was found, so every
    # home with a single stale ~/.bashrc in it took the bash branch by default.
    #
    # A zsh user with a ~/.bashrc and no ~/.zshrc therefore got two green "added"
    # lines naming bash files, a ~/.bash_profile invented for them, "source
    # ~/.bashrc" -- and a new zsh tab with nothing in it. Measured with a real
    # zsh started in that home: `tstyles` ABSENT, no TSTYLES_* state, stock
    # prompt. macOS never writes a ~/.zshrc for you (there is no newuser hook in
    # /etc/zshrc), while a pre-Catalina ~/.bashrc survives forever, so the layout
    # is ordinary rather than contrived.
    #
    # $env:SHELL is a DIMENSION in here, not a constant. Every other test that
    # drives shell-init pins it to '/bin/bash' for determinism -- correct for
    # what those assert, and exactly why nothing in the suite ever ran this
    # command as a zsh user.
    InModuleScope TerminalStyles {
        BeforeEach {
            # -HomeDir alone is NOT a sandbox here: shell-init reaches
            # Sync-ShellRuntime before it registers anything, and that writes to
            # the data root with no seam of its own.
            $script:savedRoot = $script:TStylesDataRoot
            $script:dataRoot  = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:dataRoot -Force | Out-Null
            $script:TStylesDataRoot = $script:dataRoot
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        function script:New-Home([string[]]$Files) {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in $Files) {
                [System.IO.File]::WriteAllText((Join-Path $h $f), "# original $f`n", (Get-RcFileEncoding))
            }
            $h
        }
        # [System.IO.File] rather than Get-Item: without -Force that returns
        # nothing at all for a dotfile on Unix, and an assertion whose both sides
        # are $null passes while comparing nothing.
        function script:RcText([string]$Path) {
            if (-not [System.IO.File]::Exists($Path)) { return $null }
            [System.IO.File]::ReadAllText($Path, (Get-RcFileEncoding))
        }
        function script:InitAs([string]$Shell, [string]$HomeDir, [string]$ZDotDir) {
            $prev = $env:SHELL
            try {
                $env:SHELL = $Shell
                if ($PSBoundParameters.ContainsKey('ZDotDir')) {
                    Invoke-TerminalStylesShellInit -HomeDir $HomeDir -ZDotDir $ZDotDir -Force 6>&1 | Out-String
                } else {
                    Invoke-TerminalStylesShellInit -HomeDir $HomeDir -Force 6>&1 | Out-String
                }
            } finally { $env:SHELL = $prev }
        }

        # The literal array can never be empty at discovery. Pester 6 fails the
        # whole FILE on an empty -ForEach rather than producing no tests, so a
        # collection computed per-platform would take a CI leg down with it.
        It 'a zsh login shell ends up with a loaded zsh, for the <label> layout' -ForEach @(
            @{ label = '.bashrc only';            files = @('.bashrc') }
            @{ label = '.bashrc + .bash_profile'; files = @('.bashrc', '.bash_profile') }
            @{ label = '.bashrc + .profile';      files = @('.bashrc', '.profile') }
        ) {
            $h = script:New-Home $files
            script:InitAs '/bin/zsh' $h | Out-Null

            # NOT VACUOUS. Every layout here has a bash rc, and registering it is
            # what emptied the -Create fallback and caused the bug. If the layout
            # failed to land on disk this fails first, instead of the zsh
            # assertion below passing for the wrong reason (an empty home always
            # reached the fallback and always got a .zshrc).
            script:RcText (Join-Path $h '.bashrc') | Should -Match 'TerminalStyles BEGIN' `
                -Because 'the layout must be the one that disarms the fallback'

            $zshrc = Join-Path $h '.zshrc'
            [System.IO.File]::Exists($zshrc) | Should -BeTrue `
                -Because 'zsh is the login shell, so a new zsh tab has to come up styled'
            script:RcText $zshrc | Should -Match 'TerminalStyles BEGIN'
        }

        It 'tells a zsh user to source their zsh file, not the bash one' {
            # Its own It because it is its own claim, and it failed separately:
            # the hint took whichever file came first in $touched, which is
            # candidate order, so a zsh user was told "source ~/.bashrc" -- a
            # line that does nothing in the shell they are sitting in.
            $h   = script:New-Home @('.bashrc')
            $out = script:InitAs '/bin/zsh' $h

            # [\\/] rather than /: the hint shortens the path by cutting $HomeDir
            # off the front, so the separator it prints is the platform's, and
            # this file runs on the Windows legs too.
            $out | Should -Match 'source ~[\\/]\.zshrc'
            $out | Should -Not -Match 'source ~[\\/]\.bashrc'
        }

        It 'does not invent a ~/.bash_profile for a zsh login shell' {
            # The bash rescue had no login-shell guard, so it fired here too and
            # created a file the user never had. shell-remove strips the block
            # and leaves the file (plus a .bak of a file TerminalStyles itself
            # wrote seconds earlier) in their home for good.
            $h = script:New-Home @('.bashrc')
            script:InitAs '/bin/zsh' $h | Out-Null

            [System.IO.File]::Exists((Join-Path $h '.bash_profile')) | Should -BeFalse `
                -Because 'nothing asked for a bash login file on a machine that logs into zsh'
        }

        It 'leaves ~/.profile alone for a zsh login shell' {
            # The stock Debian/Ubuntu skel. `tstyles help shell-init` bounds this
            # write -- "your ~/.profile, WHEN THAT IS THE ONLY FILE your login
            # shell reads" -- and for a zsh login shell it is not; the branch
            # checked which files exist and never which shell was running.
            $h = script:New-Home @('.bashrc', '.profile')
            script:InitAs '/bin/zsh' $h | Out-Null

            script:RcText (Join-Path $h '.profile') | Should -Not -Match 'TerminalStyles BEGIN' `
                -Because 'login zsh never reads ~/.profile, and the help text says so'
        }

        It 'creates the zsh rc inside $ZDOTDIR, which is the file zsh opens' {
            # ~/.zshrc EXISTS here, so "a .zshrc was written" is true and still
            # useless: with ZDOTDIR set, zsh reads $ZDOTDIR/.zshrc and never
            # ~/.zshrc. Get-ShellRcCandidate already orders the two that way;
            # the rescue has to take the first rather than any of them.
            $h = script:New-Home @('.zshrc')
            $z = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $z -Force | Out-Null

            script:InitAs '/bin/zsh' $h $z | Out-Null

            $zdotRc = Join-Path $z '.zshrc'
            [System.IO.File]::Exists($zdotRc) | Should -BeTrue `
                -Because 'ZDOTDIR is set, so this is the only zsh rc a new tab reads'
            script:RcText $zdotRc | Should -Match 'TerminalStyles BEGIN'
        }

        # The mirror. A rule that only ever runs for one shell is half-tested,
        # and creating files is the half that surprises people.
        It 'a bash login shell still gets its login file, for the <label> layout' -ForEach @(
            @{ label = '.bashrc only';       files = @('.bashrc');              login = '.bash_profile' }
            @{ label = '.bashrc + .profile'; files = @('.bashrc', '.profile');  login = '.profile' }
        ) {
            $h = script:New-Home $files
            script:InitAs '/bin/bash' $h | Out-Null

            script:RcText (Join-Path $h $login) | Should -Match 'TerminalStyles BEGIN' `
                -Because 'login bash reads this file and never ~/.bashrc'
        }

        It 'shell-remove still takes back the zsh rc shell-init created' {
            # A new WRITE path is a new way to break the round-trip the suite
            # measures in tests/Uninstall-ReversesShellInit.Tests.ps1, whose six
            # layouts all pin a bash login shell. The zsh candidates are on the
            # removal list, so this should hold -- assert it rather than assume.
            $h = script:New-Home @('.bashrc')
            script:InitAs '/bin/zsh' $h | Out-Null
            script:RcText (Join-Path $h '.zshrc') | Should -Match 'TerminalStyles BEGIN' `
                -Because 'there has to be something to remove'

            Invoke-TerminalStylesShellInit -HomeDir $h -Remove *> $null

            $left = @(Get-ChildItem -LiteralPath $h -File -Force |
                Where-Object { (script:RcText $_.FullName) -match 'TerminalStyles BEGIN' } |
                ForEach-Object { $_.Name })
            $left -join ', ' | Should -BeNullOrEmpty `
                -Because "shell-remove reports success, so nothing may still source the runtime (left in: $($left -join ', '))"
        }

        It 'does not invent a ~/.zshrc for a bash login shell' {
            # The other direction of the same rule: "silently creating ~/.bashrc
            # on a machine that only uses zsh would be a surprise" is
            # Register-ShellLoader's own reason for -Create, and it is symmetric.
            $h = script:New-Home @('.bashrc')
            script:InitAs '/bin/bash' $h | Out-Null

            [System.IO.File]::Exists((Join-Path $h '.zshrc')) | Should -BeFalse `
                -Because 'they log into bash; a zsh rc file is not ours to create'
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

            # -Be 'ok', not -BeTrue. Every status this returns is a non-empty
            # string, so -BeTrue is now satisfied by 'failed' as well.
            Sync-ShellRuntime | Should -Be 'ok'
            $shim = [System.IO.File]::ReadAllText((Get-ShellCliPath))

            $shim | Should -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$'
            $shim | Should -Not -Match 'TerminalStyles\.psd1' `
                -Because 'a version-stamped path is exactly what pins the shell to an old release'
        }

        It 'a BOOTSTRAP install still gets the absolute path, which it needs' {
            Mock Get-TStylesDataRoot { $script:TStylesModuleRoot }
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap'

            Sync-ShellRuntime | Should -Be 'ok'
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

Describe 'Register-ShellLoader refuses a BEGIN with no matching END' {
    # The registration half of the pair had no answer for a state its own
    # sibling has a name for. Given a file whose END marker is gone --
    # hand-edited rc, interrupted write, a half-finished manual cleanup, the
    # inputs Unregister-ShellLoader's docstring already enumerates -- the
    # refresh branch matched nothing, wrote the identical bytes back, and
    # returned 'updated'. shell-init printed `updated  ~/.zshrc` in cyan and
    # told the user to `source` it, with no loader line in the file at all, and
    # every re-run said the same thing: an absorbing state the tool could never
    # talk the user out of.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:rc = Join-Path $script:h '.zshrc'
            # The state the finding was measured on, and the one a user reaches
            # by following shell-remove's own advice ("Delete the block by
            # hand") imprecisely: the marker left behind, the loader line gone.
            # Nothing sources anything out of this file.
            [System.IO.File]::WriteAllText($script:rc,
                "alias g=git`n# ===== TerminalStyles BEGIN =====`n",
                [System.Text.UTF8Encoding]::new($false))
        }

        It 'reports malformed rather than updated' {
            Register-ShellLoader -Path $script:rc | Should -Be 'malformed'
        }

        It 'says the same under -Force, which used to write the file back anyway' {
            Register-ShellLoader -Path $script:rc -Force | Should -Be 'malformed'
        }

        It 'says the same when it is the END line alone that was deleted' {
            # The other route in, and the fixture shell-remove's own malformed
            # test uses: a block this code wrote, with the END marker taken out.
            # The loader line survives there, so the file still works -- but the
            # refresh can no longer maintain it, and shell-remove will not strip
            # it, which is exactly what the status is for.
            $rc2 = Join-Path $script:h '.bashrc'
            [System.IO.File]::WriteAllText($rc2, "alias g=git`n", [System.Text.UTF8Encoding]::new($false))
            Register-ShellLoader -Path $rc2 | Should -Be 'added'
            $t = [System.IO.File]::ReadAllText($rc2, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($rc2,
                ($t -replace '# ===== TerminalStyles END =====\r?\n?', ''),
                [System.Text.UTF8Encoding]::new($false))

            Register-ShellLoader -Path $rc2 | Should -Be 'malformed'
        }

        It 'gives the same answer as Unregister-ShellLoader on the same bytes' {
            # One file, one state, one name for it. The status vocabulary exists
            # so the two halves of the pair cannot disagree about what happened.
            $status = Register-ShellLoader -Path $script:rc
            $status | Should -Be (Unregister-ShellLoader -Path $script:rc)
        }

        It 'leaves the file exactly as it found it' {
            $before = [System.IO.File]::ReadAllBytes($script:rc)
            [void](Register-ShellLoader -Path $script:rc -Force)
            [System.IO.File]::ReadAllBytes($script:rc) | Should -Be $before
        }

        It 'shell-init says so and does not send the user to source that file' {
            # The line the user actually acts on. It is chosen by a filter that
            # only excluded 'failed', so a file reported as 'updated' with no
            # loader in it was the file they were told to source.
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/zsh'
                $out = Invoke-TerminalStylesShellInit -HomeDir $script:h 6>&1 | Out-String
            } finally { $env:SHELL = $prev }

            $out | Should -Match 'malformed'
            $out | Should -Match 'no matching END'
            $out | Should -Not -Match 'source ' `
                -Because 'sourcing a file with no loader in it does nothing, twice'
            $out | Should -Not -Match '(?m)^\s+updated\s'

            [System.IO.File]::ReadAllText($script:rc, [System.Text.UTF8Encoding]::new($false)) |
                Should -Not -Match 'tstyles\.sh' -Because 'nothing was registered, whatever it printed'
        }
    }
}

Describe 'Sync-ShellRuntime says WHICH staging failure happened' {
    # One boolean for two unrelated causes: "shell/tstyles.sh is absent from the
    # module" and "the data root would not take the copy". shell-init turned
    # that single bit into "Could not stage the shell runtime (shell/tstyles.sh
    # missing from the module)" -- a cause it cannot know, and one that sends a
    # user whose data root is read-only, root-owned or full off to reinstall the
    # module, the one action that cannot help. The path really at fault was
    # never printed at all.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            $script:data = Join-Path $script:h 'data'
            New-Item -ItemType Directory -Path $script:data -Force | Out-Null
            $script:TStylesDataRoot = $script:data
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'returns ok when it staged the runtime' {
            Sync-ShellRuntime | Should -Be 'ok'
            Test-Path -LiteralPath (Get-ShellRuntimePath) | Should -BeTrue
        }

        It 'returns nosource when the module really is missing shell/tstyles.sh' {
            $script:TStylesModuleRoot = Join-Path $script:h 'no-shell-dir'
            New-Item -ItemType Directory -Path $script:TStylesModuleRoot -Force | Out-Null
            Sync-ShellRuntime | Should -Be 'nosource'
        }

        It 'returns failed when the source is there and the write is refused' {
            # A mock rather than chmod: the Windows legs of CI have no chmod
            # semantics for a directory, and the cause under test is "the copy
            # was refused", whatever refused it.
            Test-Path -LiteralPath (Join-Path (Join-Path $script:TStylesModuleRoot 'shell') 'tstyles.sh') |
                Should -BeTrue -Because 'the fixture must set the branch under test'
            Mock Copy-Item { throw [System.UnauthorizedAccessException]::new('Access to the path is denied.') }
            Sync-ShellRuntime | Should -Be 'failed'
        }

        It 'shell-init blames the module only when the module is what is missing' {
            $script:TStylesModuleRoot = Join-Path $script:h 'no-shell-dir'
            New-Item -ItemType Directory -Path $script:TStylesModuleRoot -Force | Out-Null

            $ev = $null
            Invoke-TerminalStylesShellInit -HomeDir $script:h -ErrorVariable ev -ErrorAction SilentlyContinue *> $null
            # The LAST record is the command's own diagnostic -- the sentence
            # the user is left with. Matching the whole collection would also
            # match anything that merely leaked out of the failure underneath.
            # @() first: -ErrorVariable hands back an ArrayList, and indexing one
            # from the end is an array trick.
            "$(@($ev)[-1])" | Should -Match 'missing from the module'
        }

        It 'shell-init names the data root when the data root is what refused' {
            Mock Copy-Item { throw [System.UnauthorizedAccessException]::new('Access to the path is denied.') }

            $ev = $null
            Invoke-TerminalStylesShellInit -HomeDir $script:h -ErrorVariable ev -ErrorAction SilentlyContinue *> $null

            $said = "$(@($ev)[-1])"
            $said | Should -Not -Match 'missing from the module' `
                -Because 'the file is there; reinstalling the module cannot help'
            $said | Should -Match ([regex]::Escape($script:data)) `
                -Because 'the directory that refused the write is the one the user has to fix'
            $said | Should -Match 'denied' -Because 'the reason the write failed is the actionable half'
        }
    }
}
