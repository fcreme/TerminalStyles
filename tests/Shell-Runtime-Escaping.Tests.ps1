# Pester 5 tests for the zsh/bash runtime's escaping and the generated CLI shim.
#
# Everything here is sourced by an interactive shell on every new tab, so a fault
# is a broken prompt rather than a wrong colour. None of it had a test.
#
# Bugs pinned:
#   - a '%' in a git branch name was re-scanned by zsh as a prompt escape, so a
#     branch called 100%done rendered as "100", the CURRENT DIRECTORY, "one";
#     and 'feat%(x' swallowed the rest of the prompt as a malformed ternary.
#   - bash decodes PS1 backslash escapes BEFORE command substitution, so the
#     colours ts_c produces arrived too late and printed as literal
#     \[\033[38;2;...m\] text around the branch name.
#   - the generated tstyles-cli.ps1 imported the module normally, which re-emits
#     the CURRENTLY applied style and dot-sources its profile.ps1 -- so
#     `tstyles list` from zsh repainted the terminal and printed the old style's
#     banner before listing anything.
#   - that same shim interpolated the module path into a single-quoted string
#     with no escaping, so an apostrophe in the path produced a shim that could
#     not parse while Sync-ShellRuntime reported success.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:HasZsh  = [bool](Get-Command zsh  -ErrorAction SilentlyContinue)
    $script:HasBash = [bool](Get-Command bash -ErrorAction SilentlyContinue)
    $script:HasGit  = [bool](Get-Command git  -ErrorAction SilentlyContinue)
    # `script` is the only portable way to hand a shell a real pty, and ts_load
    # returns early without one. Two incompatible flavours exist:
    #   BSD (macOS)       script -q <file> <cmd...>
    #   util-linux (Linux) script -q -c "<cmd>" <file>
    # Windows has neither.
    $script:HasScript = [bool](Get-Command script -ErrorAction SilentlyContinue)
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:runtime = Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh'

    # A throwaway repo whose branch name we can make hostile.
    function script:New-BranchRepo {
        param([string]$Branch)
        $d = Join-Path $TestDrive ('repo-' + [guid]::NewGuid().Guid.Substring(0, 8))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        & git -C $d init -q . 2>$null
        & git -C $d -c user.email=t@t -c user.name=t commit -q --allow-empty -m x 2>$null
        & git -C $d branch -m $Branch 2>$null
        return $d
    }
    function script:Invoke-Shell {
        param([string]$Shell, [string]$Script)
        & $Shell -c $Script 2>&1 | Out-String
    }

    # Run a command under a real pty and return everything it printed.
    function script:Invoke-UnderPty {
        param([string]$Command, [string]$LogPath)
        $isUtilLinux = $false
        try {
            # util-linux prints "util-linux" in its version banner; BSD script
            # has no --version and exits non-zero.
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

Describe 'ts_git_branch survives a hostile branch name' {

    It 'zsh renders a % in a branch literally rather than as a prompt escape' -Skip:(-not ($script:HasZsh -and $script:HasGit)) {
        # The exact failure: zsh read %d as "current directory".
        $repo = script:New-BranchRepo -Branch '100%done'
        $out = script:Invoke-Shell -Shell 'zsh' -Script @"
cd '$repo'
. '$($script:runtime)' 2>/dev/null
TS_GIT_OPEN=''; TS_GIT_CLOSE=''
setopt PROMPT_SUBST
PROMPT="`$(ts_git_branch)"
print -rP "[`$PROMPT]"
"@
        $out | Should -Match '\[ \(100%done\)\]'
        $out | Should -Not -Match '/private|/Users'   # no directory leaked in
    }

    It 'zsh does not let %( swallow the rest of the prompt' -Skip:(-not ($script:HasZsh -and $script:HasGit)) {
        # '%(' starts a zsh ternary; unterminated, it ate everything after it.
        $repo = script:New-BranchRepo -Branch 'feat%(danger'
        $out = script:Invoke-Shell -Shell 'zsh' -Script @"
cd '$repo'
. '$($script:runtime)' 2>/dev/null
TS_GIT_OPEN=''; TS_GIT_CLOSE=''
setopt PROMPT_SUBST
PROMPT="`$(ts_git_branch) END"
print -rP "[`$PROMPT]"
"@
        $out | Should -Match 'END'   # the tail survived
        $out | Should -Match 'feat%\(danger'
    }

    It 'bash leaves the branch name alone' -Skip:(-not ($script:HasBash -and $script:HasGit)) {
        # bash performs no such re-scan, so it must NOT be double-escaped either.
        $repo = script:New-BranchRepo -Branch '100%done'
        $out = script:Invoke-Shell -Shell 'bash' -Script @"
cd '$repo'
. '$($script:runtime)' 2>/dev/null
TS_GIT_OPEN=''; TS_GIT_CLOSE=''
ts_git_branch
"@
        $out | Should -Match '\(100%done\)'
        $out | Should -Not -Match '100%%done'
    }
}

Describe 'colours used inside a command substitution' {

    It 'bash gets real bytes, not literal backslash escapes' -Skip:(-not $script:HasBash) {
        # bash decodes \[ and \033 when it parses PS1, which happens BEFORE
        # command substitution -- so ts_c's output arrives too late to be
        # decoded and shows up as literal text in the prompt. ts_cs emits the
        # bytes bash would have produced: \001 ESC ... \002.
        $out = script:Invoke-Shell -Shell 'bash' -Script @"
. '$($script:runtime)' 2>/dev/null
ts_cs '187;0;187' | od -An -c | tr -s ' '
"@
        $out | Should -Match '001'      # real start-non-printing byte
        $out | Should -Match '033'      # real ESC
        $out | Should -Not -Match '\\\\\['   # not the literal two-char \[
    }

    It 'zsh keeps the %{...%} form, which it does re-scan' -Skip:(-not $script:HasZsh) {
        $out = script:Invoke-Shell -Shell 'zsh' -Script @"
. '$($script:runtime)' 2>/dev/null
ts_cs '187;0;187'
"@
        $out | Should -Match '%\{'
        $out | Should -Match '%\}'
    }

    It 'gitbash uses the substitution-safe helper for its branch colours' {
        $p = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles/gitbash') 'prompt.sh'
        $src = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match 'TS_GIT_OPEN=\$\(ts_cs'
        $src | Should -Match 'TS_GIT_CLOSE=\$\(ts_xs\)'
    }
}

Describe 'the tstyles shell function does not reprint the banner' {

    It 'only re-sources the prompt when the staged prompt actually changed' {
        # The guard used to be exit-code-only, so every read-only subcommand
        # (list, current, help) re-sourced current-prompt.sh and reprinted the
        # style's whole ASCII banner. The comment above it claimed the exit code
        # prevented exactly that; it never did.
        $src = [System.IO.File]::ReadAllText($script:runtime, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match '_ts_before='
        $src | Should -Match '_ts_after='
        $src | Should -Match '\$_ts_before" != "\$_ts_after'
    }

    It 'still re-sources when there is no hashing tool available' {
        # Failing open matters: a missed prompt swap is worse than a stray banner.
        $src = [System.IO.File]::ReadAllText($script:runtime, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match '-z "\$_ts_before" \] \|\| \[ -z "\$_ts_after"'
    }
}

Describe 'the generated tstyles-cli.ps1 shim' {
    InModuleScope TerminalStyles {

        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
        }

        It 'suppresses the shell-startup auto-load' {
            $script:TStylesModuleRoot = Split-Path $PSScriptRoot -Parent
            Sync-ShellRuntime | Out-Null
            $cli = [System.IO.File]::ReadAllText((Get-ShellCliPath), [System.Text.UTF8Encoding]::new($false))
            $cli | Should -Match '\$global:TStylesNoAutoLoad\s*=\s*\$true'
            # ...and it must come BEFORE the import, or it does nothing.
            $cli.IndexOf('TStylesNoAutoLoad') | Should -BeLessThan $cli.IndexOf('Import-Module')
        }

        It 'produces a parseable shim when the module path contains an apostrophe' {
            $awkward = Join-Path $TestDrive "o'brien"
            New-Item -ItemType Directory -Path $awkward -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $awkward 'shell') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell/tstyles.sh') `
                      -Destination (Join-Path $awkward 'shell/tstyles.sh') -Force
            $script:TStylesModuleRoot = $awkward
            # BOOTSTRAP layout on purpose. Only a bootstrap install bakes the
            # module path into the shim -- a PSGallery one imports by name, so
            # there is no path to escape and this assertion would hold
            # vacuously against any escaping at all.
            Mock Get-TStylesDataRoot { $script:TStylesModuleRoot }

            Sync-ShellRuntime | Out-Null
            $cliPath = Get-ShellCliPath
            $errs = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($cliPath, [ref]$null, [ref]$errs)
            $errs | Should -BeNullOrEmpty -Because 'an apostrophe in the path must not break the shim'
        }

        It 'doubles the apostrophe rather than dropping it' {
            $awkward = Join-Path $TestDrive "o'brien2"
            New-Item -ItemType Directory -Path (Join-Path $awkward 'shell') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell/tstyles.sh') `
                      -Destination (Join-Path $awkward 'shell/tstyles.sh') -Force
            $script:TStylesModuleRoot = $awkward
            # BOOTSTRAP layout on purpose. Only a bootstrap install bakes the
            # module path into the shim -- a PSGallery one imports by name, so
            # there is no path to escape and this assertion would hold
            # vacuously against any escaping at all.
            Mock Get-TStylesDataRoot { $script:TStylesModuleRoot }
            Sync-ShellRuntime | Out-Null
            $cli = [System.IO.File]::ReadAllText((Get-ShellCliPath), [System.Text.UTF8Encoding]::new($false))
            $cli | Should -Match "o''brien2"
        }
    }
}

Describe 'the loader is idempotent' {

    It 'runs once even when the runtime is sourced twice' -Skip:(-not ($script:HasBash -and $script:HasScript)) {
        # shell-init registers the SAME block into both ~/.bashrc and
        # ~/.bash_profile -- .bash_profile because macOS Terminal.app starts bash
        # as a login shell and never reads .bashrc. The widespread convention is
        # for .bash_profile to source .bashrc, so both fired: the palette was
        # re-emitted and the style's whole ASCII banner printed twice on every
        # new window.
        #
        # Driven through a real pty, because ts_load returns early in a
        # non-interactive shell and that is the branch a piped bash takes.
        # Note macOS ships bash 3.2, which requires long options BEFORE short
        # ones -- `bash -i --init-file X` is a usage error there.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $data = Join-Path $TestDrive 'data'
        New-Item -ItemType Directory -Path $data -Force | Out-Null
        Copy-Item (Join-Path $repoRoot 'styles/umbrella/prompt.sh') (Join-Path $data 'current-prompt.sh')
        [System.IO.File]::WriteAllText((Join-Path $data 'current-style.osc'), '')

        $rc = Join-Path $TestDrive 'rc.sh'
        # The rc file exits at the end on purpose. util-linux's `script -c` gives
        # the shell the pty as stdin, so an interactive bash left at a prompt
        # would wait forever and hang CI; BSD's flavour is fed 'exit' on stdin
        # instead. Exiting from the rc works for both.
        [System.IO.File]::WriteAllText($rc, @"
export TSTYLES_DATA='$data'
. '$repoRoot/shell/tstyles.sh'
. '$repoRoot/shell/tstyles.sh'
exit
"@)
        $wrapper = Join-Path $TestDrive 'w.sh'
        [System.IO.File]::WriteAllText($wrapper, "#!/bin/sh`nexec bash --init-file '$rc' -i`n")
        & chmod +x $wrapper

        $log = Join-Path $TestDrive 'log'
        $text = script:Invoke-UnderPty -Command $wrapper -LogPath $log
        ([regex]::Matches($text, 'UMBRELLA CORP')).Count | Should -Be 1
    }

    It 'still says nothing at all in a non-interactive shell' -Skip:(-not $script:HasBash) {
        # The guard sits AFTER the interactivity check on purpose: a
        # non-interactive shell must stay silent (ssh host command, scp, rsync
        # all break if startup writes to stdout) and must not set the flag in a
        # way that would suppress a later interactive load.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $out = script:Invoke-Shell -Shell 'bash' -Script @"
export TSTYLES_DATA='$TestDrive'
. '$repoRoot/shell/tstyles.sh'
echo READY
"@
        $out.Trim() | Should -Be 'READY'
    }

    It 'sets the guard only after the interactivity check' {
        $src = [System.IO.File]::ReadAllText($script:runtime, [System.Text.UTF8Encoding]::new($false))
        $body = [regex]::Match($src, '(?s)ts_load\(\) \{.*?\n\}').Value
        $body.IndexOf('case "$-"') | Should -BeLessThan $body.IndexOf('TS_LOADED=1')
    }
}

Describe 'the runtime stays out of captured output' {
    # Found by driving a real interactive shell, which nothing had ever done.
    #
    # ts_load gated on $- alone. That says the shell is INTERACTIVE; it says
    # nothing about where fd 1 goes. `zsh -ic 'cmd'` sets the i flag with stdout
    # on a pipe -- the shape every editor and IDE uses to learn a user's real
    # PATH -- and got the OSC palette plus the style's whole ASCII banner glued
    # to the front of the captured value. Measured on a sandbox HOME: 14 bytes
    # without the runtime, 854 with it, and the result unusable as a path.
    #
    # The PowerShell half has always checked [Console]::IsOutputRedirected. The
    # shell half never did.
    BeforeAll {
        $script:runtime = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell/tstyles.sh'),
            [System.Text.UTF8Encoding]::new($false))
    }

    It 'ts_load requires stdout to be a terminal, not just an interactive shell' {
        $fn = [regex]::Match($script:runtime, '(?s)ts_load\(\)\s*\{.*?\n\}').Value
        $fn | Should -Not -BeNullOrEmpty
        $fn | Should -Match '\[ -t 1 \]' `
            -Because 'an interactive shell with a redirected stdout must stay silent'
        # And the tty test must come before anything that writes.
        $fn.IndexOf('[ -t 1 ]') | Should -BeLessThan $fn.IndexOf('current-style.osc') `
            -Because 'the guard is worthless after the packet has been written'
    }

    It 'ts_title does the same' {
        # tstyles <style> re-sources the staged prompt, which calls ts_title
        # outside ts_load's guard.
        $fn = [regex]::Match($script:runtime, '(?s)ts_title\(\)\s*\{.*?\n\}').Value
        $fn | Should -Not -BeNullOrEmpty
        $fn | Should -Match '\[ -t 1 \]'
    }

    It 'the guard the PowerShell half uses is still there to match' {
        # If that check ever leaves terminals.ps1, these two halves have drifted
        # and the shell one is alone again.
        $terminals = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'terminals.ps1'),
            [System.Text.UTF8Encoding]::new($false))
        $terminals | Should -Match 'IsOutputRedirected'
    }
}

Describe 'an apply prints its banner once, not twice' {
    It 'the pwsh-side live reload is skipped for a non-interactive host' {
        # `tstyles <style>` from zsh/bash runs the generated tstyles-cli.ps1 in a
        # one-shot pwsh process that exits immediately, so dot-sourcing the
        # style's profile.ps1 to "live reload the prompt in THIS shell" reloads
        # nothing -- and printed the style's whole ASCII banner. The shell
        # function then re-sourced the staged prompt.sh to swap the prompt for
        # real, printing it a SECOND time. Two banners per apply, for every zsh
        # and bash user.
        #
        # $TStylesNoAutoLoad is the signal the shim already sets.
        $src = InModuleScope TerminalStyles {
            (Get-Command Apply-StyleNonWT).ScriptBlock.ToString()
        }
        $src | Should -Match '-not \$global:TStylesNoAutoLoad[^\n]*TStylesCurrent' `
            -Because 'the reload must be gated on the shim''s own signal'
    }

    It 'the shim still sets that signal' {
        # The shim is a here-string in terminals.ps1, not inside the shell-init
        # function, so it has to be read from the file.
        $terminals = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'terminals.ps1'),
            [System.Text.UTF8Encoding]::new($false))
        $terminals | Should -Match 'TStylesNoAutoLoad' `
            -Because 'the gate above is inert if the generated shim stops setting it'
    }
}
