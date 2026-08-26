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
            Sync-ShellRuntime | Out-Null
            $cli = [System.IO.File]::ReadAllText((Get-ShellCliPath), [System.Text.UTF8Encoding]::new($false))
            $cli | Should -Match "o''brien2"
        }
    }
}
