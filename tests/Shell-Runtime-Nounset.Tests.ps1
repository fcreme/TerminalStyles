# Pester 5 tests: shell/tstyles.sh under `set -u` (nounset).
#
# This file is sourced from the user's rc file on EVERY interactive shell, so it
# runs with whatever shell options that rc has already set. Under `set -u` an
# unset parameter is an ERROR, and every ambient read here was bare -- so the
# runtime did not degrade, it fell over, differently in each shell:
#
#   bash: the error aborts the enclosing COMPOUND COMMAND and the file keeps
#         running, so it loads half of itself. Line 22 ($TSTYLES_DATA) went
#         first, then $ZSH_VERSION, then $_ts_shell twice, then $_ts_loaded --
#         five "unbound variable" lines before the prompt, on every new tab.
#         The `if` at line 52 that defines ts_c/ts_x/ts_cs/ts_xs is one of the
#         aborted compounds, so the colour helpers never exist; `tstyles` does,
#         which is why the tool looked installed while applying nothing.
#   zsh:  the FIRST error aborts the whole `source` (rc 126). Nothing at all is
#         defined -- not ts_load, not ts_raw, not even the `tstyles` command --
#         and zsh is the macOS default shell.
#
# The measurements are made by running real shells with TSTYLES_DATA UNSET,
# which is the default-install shape: the loader block shell-init writes is only
# `if [ -r '<runtime>' ]; then . '<runtime>'; fi` and nothing exports the
# variable. Exporting it for sandboxing would mask the very first read and this
# whole file would pass against the bug.
#
# Everything runs under `env -i` with HOME pointed at $TestDrive, so no real rc
# file, $HOME or data root is reachable from here.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    # Decided HERE, at discovery. A -Skip reading a variable set in BeforeAll
    # gets $null, which is falsy, so the test neither runs nor reports as
    # skipped -- it silently passes. This suite has been bitten by that already.
    #
    # A `bash` on PATH is not enough on its own: the Windows runners ship Git
    # Bash, and the zsh/bash loader is a macOS/Linux feature.
    $script:IsUnixHost = ($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows
    $script:NoBash = -not ($script:IsUnixHost -and (Get-Command bash -ErrorAction SilentlyContinue))
    $script:NoZsh  = -not ($script:IsUnixHost -and (Get-Command zsh  -ErrorAction SilentlyContinue))
    $script:NoBoth = $script:NoBash -or $script:NoZsh
    # `script` is the only portable way to hand a shell a real pty, and ts_load
    # returns early without one.
    $script:NoPty  = $script:NoBoth -or -not (Get-Command script -ErrorAction SilentlyContinue)

    $script:Shells = @(
        if (-not $script:NoBash) { 'bash' }
        if (-not $script:NoZsh)  { 'zsh' }
    )
    # Pester 6 FAILS DISCOVERY on an empty -ForEach rather than producing no
    # tests, so on a Windows runner -- no bash, no zsh -- an empty $Shells took
    # this whole file down with "Value can not be null or empty array", which is
    # a red build for a platform the file has nothing to say about. A
    # placeholder keeps discovery valid and the Its below skip on $NoBoth, so
    # those legs report SKIPPED with a name that says why.
    $script:ShellsOrNone = if ($script:Shells) { $script:Shells } else { @('no POSIX shell on this runner') }
    $script:StyleNames = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'prompt.sh') } |
            ForEach-Object { $_.Name } | Sort-Object
    )
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:runtime  = Join-Path (Join-Path $script:repoRoot 'shell') 'tstyles.sh'

    # A scratch HOME. TSTYLES_DATA is deliberately NOT set for the child: the
    # runtime derives its data root from HOME, which lands inside $TestDrive.
    function script:New-SandboxHome {
        $h = Join-Path $TestDrive ('home-' + [guid]::NewGuid().Guid.Substring(0, 8))
        New-Item -ItemType Directory -Path $h -Force | Out-Null
        return $h
    }

    # Run $Body in $Shell with an EMPTY environment apart from HOME/PATH/TERM,
    # capturing stdout, stderr and the exit code separately. stderr goes to a
    # file rather than through PowerShell's error stream so an empty-stderr
    # assertion is about the shell, not about how PowerShell merged the streams.
    function script:Invoke-Sandboxed {
        param([string]$Shell, [string]$Body)

        $exe = (Get-Command $Shell).Source
        $binDirs = @('/usr/bin', '/bin', '/usr/local/bin', (Split-Path $exe -Parent)) |
            Sort-Object -Unique
        $errFile = Join-Path $TestDrive ('err-' + [guid]::NewGuid().Guid.Substring(0, 8) + '.txt')
        $home2   = script:New-SandboxHome

        # The redirect wraps the whole body, so anything the shell says about it
        # -- including an error that kills the shell mid-way -- lands in the file.
        $wrapped = "{ $Body`n} 2>'$errFile'"
        $out = & env -i "HOME=$home2" "PATH=$($binDirs -join ':')" 'TERM=dumb' `
                   $exe -c $wrapped 2>&1 | Out-String
        $code = $LASTEXITCODE
        $err = if (Test-Path -LiteralPath $errFile) {
            [System.IO.File]::ReadAllText($errFile)
        } else { '' }

        return [pscustomobject]@{
            Shell    = $Shell
            ExitCode = $code
            StdOut   = $out
            StdErr   = $err
            Home     = $home2
        }
    }

    # Source the runtime, then report what the shell actually ended up with.
    # Reported as data rather than asserted inside the shell, so a failure shows
    # WHAT was missing instead of just a non-zero exit.
    $script:ReportBody = @'
_ts_report() { if type "$1" >/dev/null 2>&1; then printf 'yes'; else printf 'NO'; fi; }
printf 'shell=[%s] ts_c=[%s] ts_x=[%s] ts_cs=[%s] ts_raw=[%s] ts_prompt_expand=[%s] ts_prompt_apply=[%s] ts_title=[%s] ts_load=[%s] tstyles=[%s]\n' \
    "${_ts_shell-MISSING}" "$(_ts_report ts_c)" "$(_ts_report ts_x)" "$(_ts_report ts_cs)" \
    "$(_ts_report ts_raw)" "$(_ts_report ts_prompt_expand)" "$(_ts_report ts_prompt_apply)" \
    "$(_ts_report ts_title)" "$(_ts_report ts_load)" "$(_ts_report tstyles)"
'@

    # Drive a command under a real pty and return everything it printed. Two
    # incompatible flavours of `script` exist:
    #   BSD (macOS)        script -q <file> <cmd...>
    #   util-linux (Linux) script -q -c "<cmd>" <file>
    function script:Invoke-UnderPty {
        param([string]$Command, [string]$LogPath)
        $isUtilLinux = $false
        try {
            $v = (& script --version 2>&1 | Out-String)
            $isUtilLinux = $v -match 'util-linux'
        } catch { $isUtilLinux = $false }

        if ($isUtilLinux) {
            & script -q -c $Command $LogPath *> $null
        } else {
            'exit' | & script -q $LogPath $Command *> $null
        }
        if (Test-Path -LiteralPath $LogPath) {
            return [System.IO.File]::ReadAllText($LogPath)
        }
        return ''
    }
}

Describe 'the runtime loads under set -u' {

    It '<_> sources it in silence, with TSTYLES_DATA unset' -ForEach $script:ShellsOrNone -Skip:$script:NoBoth {
        # The default-install shape. Before the fix: bash died on line 22 with
        # `TSTYLES_DATA: unbound variable` and exit 127; zsh aborted the source
        # with rc 126 and defined nothing at all.
        $r = script:Invoke-Sandboxed -Shell $_ -Body @"
set -u
. '$($script:runtime)'
$script:ReportBody
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty `
            -Because "sourcing the runtime under nounset must say nothing, and $($r.Shell) said: $($r.StdErr)"
        $r.ExitCode | Should -Be 0 -Because "$($r.Shell) exited $($r.ExitCode): $($r.StdErr)"
    }

    It '<_> ends up with every helper the styles call' -ForEach $script:ShellsOrNone -Skip:$script:NoBoth {
        # The half-loaded state is the part the error count hides: in bash the
        # aborted compound at line 52 takes ts_c/ts_x/ts_cs/ts_xs with it, so
        # the staged prompt.sh -- which calls all of them -- fails on every line
        # while `tstyles` is still defined and the tool looks installed.
        $r = script:Invoke-Sandboxed -Shell $_ -Body @"
set -u
. '$($script:runtime)' 2>/dev/null
$script:ReportBody
"@
        $line = ($r.StdOut -split "`r?`n" | Where-Object { $_ -like 'shell=*' } | Select-Object -First 1)
        $line | Should -Not -BeNullOrEmpty `
            -Because 'the shell must survive the source far enough to report at all'
        $line | Should -BeExactly ("shell=[$($r.Shell)] ts_c=[yes] ts_x=[yes] ts_cs=[yes] ts_raw=[yes] " +
            'ts_prompt_expand=[yes] ts_prompt_apply=[yes] ts_title=[yes] ts_load=[yes] tstyles=[yes]')
    }

    It '<_> behaves the same with nounset OFF' -ForEach $script:ShellsOrNone -Skip:$script:NoBoth {
        # The other half of the claim: ${VAR-} costs nothing when the option is
        # not set. If this ever diverges from the case above, the fix has
        # changed behaviour rather than added tolerance.
        $r = script:Invoke-Sandboxed -Shell $_ -Body @"
. '$($script:runtime)'
$script:ReportBody
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
        $line = ($r.StdOut -split "`r?`n" | Where-Object { $_ -like 'shell=*' } | Select-Object -First 1)
        $line | Should -BeExactly ("shell=[$($r.Shell)] ts_c=[yes] ts_x=[yes] ts_cs=[yes] ts_raw=[yes] " +
            'ts_prompt_expand=[yes] ts_prompt_apply=[yes] ts_title=[yes] ts_load=[yes] tstyles=[yes]')
    }

    It '<_> survives set -e as well' -ForEach $script:ShellsOrNone -Skip:$script:NoBoth {
        # errexit is the other option people put at the top of an rc file. The
        # loader block is already shaped for it (an `if`, not `[ -r x ] && . x`,
        # so an orphaned runtime does not make the rc file exit 1); this pins
        # that the runtime itself never returns non-zero either, under both
        # options at once.
        $r = script:Invoke-Sandboxed -Shell $_ -Body @"
set -eu
. '$($script:runtime)'
printf 'REACHED-END\n'
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'REACHED-END'
    }
}

Describe 'a style prompt loads under set -u too' {
    # styles/<name>/prompt.sh is sourced by the same runtime, in the same shell,
    # with the same options in force. None of the sixteen reads an ambient
    # variable today -- gitbash assigns _ts_git_open/_ts_git_close itself before
    # ts_git_branch can run -- and this is what keeps the next one from
    # introducing one.
    It '<_> sources cleanly in bash' -ForEach $script:StyleNames -Skip:$script:NoBash {
        $style = Join-Path (Join-Path (Join-Path $script:repoRoot 'styles') $_) 'prompt.sh'
        $r = script:Invoke-Sandboxed -Shell 'bash' -Body @"
set -u
. '$($script:runtime)'
. '$style' >/dev/null
printf 'STYLE-OK\n'
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty -Because "bash said: $($r.StdErr)"
        $r.StdOut | Should -Match 'STYLE-OK'
    }

    It '<_> sources cleanly in zsh' -ForEach $script:StyleNames -Skip:$script:NoZsh {
        $style = Join-Path (Join-Path (Join-Path $script:repoRoot 'styles') $_) 'prompt.sh'
        $r = script:Invoke-Sandboxed -Shell 'zsh' -Body @"
set -u
. '$($script:runtime)'
. '$style' >/dev/null
printf 'STYLE-OK\n'
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty -Because "zsh said: $($r.StdErr)"
        $r.StdOut | Should -Match 'STYLE-OK'
    }

    It 'ts_git_branch renders with _ts_git_open and _ts_git_close never assigned' -Skip:$script:NoBash {
        # Only gitbash's prompt.sh sets those two, so any other style whose
        # template ever carries {GITBRANCH} reaches the printf with both unset.
        # Under nounset that is an error inside the prompt of every command.
        $r = script:Invoke-Sandboxed -Shell 'bash' -Body @"
set -u
. '$($script:runtime)'
cd /
ts_git_branch
printf 'BRANCH-OK\n'
"@
        $r.StdErr.Trim() | Should -BeNullOrEmpty -Because "bash said: $($r.StdErr)"
        $r.StdOut | Should -Match 'BRANCH-OK'
    }
}

Describe 'an interactive shell under set -u still gets its style' {
    # The non-interactive cases above never enter ts_load, which returns early
    # without a tty. This is the one that reproduces what the user actually
    # sees: a real pty, an rc that sets nounset and then carries the verbatim
    # loader block `tstyles shell-init` writes.
    #
    # Before the fix, this printed five "unbound variable" lines in bash / one
    # "parameter not set" in zsh, and left the shell's own default prompt.
    It '<_> loads, prints no error, and installs the style prompt' -ForEach $script:ShellsOrNone -Skip:($script:NoPty -or $script:NoBoth) {
        $shell = $_
        $exe   = (Get-Command $shell).Source
        $home2 = script:New-SandboxHome
        $style = Join-Path (Join-Path $script:repoRoot 'styles') 'eva/prompt.sh'

        # The verbatim block from Get-ShellLoaderBlock. TSTYLES_DATA is left
        # unset on purpose; the style is sourced directly afterwards so this
        # test does not have to restate where the data root lives.
        $rcBody = @"
set -u
# ===== TerminalStyles BEGIN =====
if [ -r '$($script:runtime)' ]; then . '$($script:runtime)'; fi
# ===== TerminalStyles END =====
. '$style'
if [ -n "`${ZSH_VERSION-}" ]; then printf 'REPORT<%s>\n' "`$PROMPT"; else printf 'REPORT<%s>\n' "`$PS1"; fi
exit
"@
        # The rc exits at the end on purpose. util-linux's `script -c` hands the
        # shell the pty as stdin, so an interactive shell left at a prompt would
        # wait forever and hang CI; BSD's flavour is fed 'exit' on stdin instead.
        $rc = Join-Path $TestDrive "rc-$shell.sh"
        [System.IO.File]::WriteAllText($rc, $rcBody)

        # macOS ships bash 3.2, which requires long options BEFORE short ones --
        # `bash -i --init-file X` is a usage error there. zsh takes its rc from
        # ZDOTDIR, so the file has to be named .zshrc in a directory of its own.
        if ($shell -eq 'zsh') {
            $zdot = Join-Path $TestDrive 'zdot'
            New-Item -ItemType Directory -Path $zdot -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $zdot '.zshrc'), $rcBody)
            $inner = "exec env -i HOME='$home2' ZDOTDIR='$zdot' PATH=/usr/bin:/bin:/usr/local/bin TERM=xterm-256color '$exe' -i"
        } else {
            $inner = "exec env -i HOME='$home2' PATH=/usr/bin:/bin:/usr/local/bin TERM=xterm-256color '$exe' --init-file '$rc' -i"
        }
        $wrapper = Join-Path $TestDrive "pty-$shell.sh"
        [System.IO.File]::WriteAllText($wrapper, "#!/bin/sh`n$inner`n")
        & chmod +x $wrapper

        $log  = Join-Path $TestDrive "pty-$shell.log"
        $text = script:Invoke-UnderPty -Command $wrapper -LogPath $log

        $complaints = @([regex]::Matches($text, 'unbound variable|parameter not set|command not found'))
        $complaints.Count | Should -Be 0 `
            -Because "a new $shell tab must come up clean; transcript was:`n$text"

        # And the prompt is the style's, not the shell's own default.
        $report = [regex]::Match($text, 'REPORT<(?<p>[^>]*)').Groups['p'].Value
        $report | Should -Match 'PILOT' `
            -Because "the EVA prompt must reach $shell; transcript was:`n$text"
    }
}

# A file that skips everything is indistinguishable from a file that passes, so
# say out loud where it is expected to have run. Windows has no POSIX shell and
# is legitimately skipped above; a Unix runner that found neither shell is a
# broken runner, not a clean run.
Describe 'the nounset measurements actually ran somewhere' {
    It 'found a shell to measure on a platform that has one' {
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
            Set-ItResult -Skipped -Because 'Windows has neither bash nor zsh; the Its above are skipped too'
            return
        }
        @($script:Shells).Count | Should -BeGreaterThan 0 `
            -Because 'on macOS or Linux at least one of bash/zsh must be found, or this file measured nothing'
    }
}
