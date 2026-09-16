# Pester 5 tests for shell/tstyles.sh and the per-style prompt.sh files.
#
# These RUN real zsh and bash. A prompt that looks right in a string comparison
# can still be wrong in the shell -- unmarked escape sequences make the shell
# miscount the prompt width, and a stray '%' or '\' changes meaning entirely.
# The only way to catch that is to let the shell parse it.
#
# Skipped where the shell is absent (the Windows CI legs), so this file adds
# coverage on macOS/Linux without failing anywhere else.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    $script:StyleNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'styles') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name } | Sort-Object
    )

    # Unix only. Presence of a `bash` on PATH is NOT sufficient: the Windows CI
    # runners ship Git Bash, which would pick these up and then fail on the
    # Windows-shaped paths this harness passes it (a single-quoted C:\a\b is a
    # string of escapes to bash). The zsh/bash loader is a macOS/Linux feature;
    # Git Bash is not a supported host for it.
    $script:IsUnixHost = ($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows
    $script:HasZsh  = $script:IsUnixHost -and [bool](Get-Command zsh  -ErrorAction SilentlyContinue)
    $script:HasBash = $script:IsUnixHost -and [bool](Get-Command bash -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:lib      = Join-Path (Join-Path $script:repoRoot 'shell') 'tstyles.sh'

    # Render a style's prompt by sourcing the library + the style in a real
    # shell, then printing the resulting PS1/PROMPT. TSTYLES_DATA is pointed at
    # a path that cannot exist so ts_load finds no staged state and the only
    # thing under test is the style file itself.
    function script:Get-RenderedPrompt {
        param([string]$Shell, [string]$StyleName)
        $styleFile = Join-Path (Join-Path (Join-Path $script:repoRoot 'styles') $StyleName) 'prompt.sh'
        # A style may print a banner when sourced, and a banner legitimately
        # contains unmarked escapes (it is output, not prompt). Fence the prompt
        # with a marker so the assertions below see ONLY the prompt.
        $script = @"
TSTYLES_DATA=/nonexistent/terminalstyles
. '$script:lib'
. '$styleFile'
printf '<<<TSPROMPT>>>'
if [ -n "`$ZSH_VERSION" ]; then printf '%s' "`$PROMPT"; else printf '%s' "`$PS1"; fi
"@
        $all = (& $Shell -c $script 2>&1 | Out-String)
        $marker = '<<<TSPROMPT>>>'
        $i = $all.IndexOf($marker)
        if ($i -lt 0) { return $all }
        return $all.Substring($i + $marker.Length)
    }

    # Everything the style prints when sourced -- the banner, without the prompt.
    function script:Get-RenderedBanner {
        param([string]$Shell, [string]$StyleName)
        $styleFile = Join-Path (Join-Path (Join-Path $script:repoRoot 'styles') $StyleName) 'prompt.sh'
        $script = @"
TSTYLES_DATA=/nonexistent/terminalstyles
. '$script:lib'
. '$styleFile'
"@
        return (& $Shell -c $script 2>&1 | Out-String)
    }

    # Source the runtime (and, given one, a style) in a real zsh and diff the
    # variable table across it. Whatever the syntax -- eval, a for loop, a
    # heredoc, typeset -- a name that exists afterwards and did not before is a
    # name the user just lost.
    #
    # TWO THINGS THIS FIXES, both of which let a leaking style pass.
    #
    # 1. EVERY interpolated path is single-quoted. It was not, and zsh
    #    word-splits an unquoted path: a checkout whose directory contains a
    #    space made BOTH `source` lines fail, the before and after tables came
    #    back identical, and "the style never loaded" produced the same green
    #    result as "the style leaked nothing". Measured with a real leak
    #    (MYVAR, PATH_BACKUP appended to gitbash/prompt.sh): from
    #    '<scratch>/repo space' 17 passed and 0 failed; from
    #    '<scratch>/reponospace' the same files failed, naming both variables.
    #    Every developer whose checkout lives under "My Documents" or
    #    "Google Drive" ran a green no-op.
    #
    # 2. A SENTINEL after each source, checked before the diff is believed.
    #    Quoting closes the space; it does not close the shape. This assertion
    #    compares two captures that stay perfectly valid when the thing under
    #    test never ran, so the probe now has to prove it ran -- which also
    #    covers a path containing a single quote, an unreadable file, and every
    #    other reason a source can fail silently.
    #
    # The inner `2>&1` on each source is NOT what hid it: lines below already
    # discard zsh's stderr at the PowerShell level (`& zsh -f $sf 2>$null`), so
    # dropping it changes nothing. Measured: unquoted paths with the inner
    # redirect removed still passed 17/0.
    function script:Invoke-ShellLeakProbe {
        param(
            [Parameter(Mandatory)][string]$RuntimeSh,
            # Omitted to measure the runtime itself rather than a style.
            [string]$PromptSh,
            [Parameter(Mandatory)][string]$ScriptPath,
            # Names that are a documented contract rather than a leak.
            [string[]]$Keep = @()
        )

        # Each marker is printed by a PREDICATE, never unconditionally: a
        # `printf` on the next line proves only that the shell reached that
        # line, which a failed `source` does too. The runtime marker asks
        # whether ts_c is now callable; the style marker asks whether $PROMPT
        # changed, which is the style's whole job.
        $lines = @()
        if ($PromptSh) {
            # The runtime's own names are not this style's leak, so the BEFORE
            # table is taken after it has loaded.
            $lines += "source '$RuntimeSh' >/dev/null 2>&1"
            $lines += 'command -v ts_c >/dev/null 2>&1 && printf ''%s\n'' ''<TSRUNTIME>'''
            # Assigned before the BEFORE table so the probe's own name is in
            # both and cannot read as a leak.
            $lines += '_ts_probe_prompt="$PROMPT"'
            $lines += 'ts_before=$(typeset +m "*" 2>/dev/null)'
            $lines += "source '$PromptSh' >/dev/null 2>&1"
            $lines += '[ "$PROMPT" != "$_ts_probe_prompt" ] && printf ''%s\n'' ''<TSSTYLE>'''
        } else {
            $lines += 'ts_before=$(typeset +m "*" 2>/dev/null)'
            $lines += "source '$RuntimeSh' >/dev/null 2>&1"
            $lines += 'command -v ts_c >/dev/null 2>&1 && printf ''%s\n'' ''<TSRUNTIME>'''
        }
        # `typeset +m '*'` prints names only. The two capture variables are
        # themselves new names, so they are filtered with the namespaced ones.
        $lines += 'ts_after=$(typeset +m "*" 2>/dev/null)'
        $lines += 'comm -13 <(print -r -- "$ts_before" | sort -u) <(print -r -- "$ts_after" | sort -u)'

        [System.IO.File]::WriteAllText($ScriptPath, ($lines -join "`n"),
            [System.Text.UTF8Encoding]::new($false))

        $out = @(& zsh -f $ScriptPath 2>$null)

        $keepPattern = '^(_ts_|ts_before$|ts_after$'
        foreach ($k in $Keep) { $keepPattern += '|' + [regex]::Escape($k) + '$' }
        $keepPattern += ')'

        [pscustomobject]@{
            RuntimeLoaded = ($out -contains '<TSRUNTIME>')
            StyleLoaded   = ($out -contains '<TSSTYLE>')
            Leaked        = @($out |
                               Where-Object { $_ -and $_ -notmatch '^<TS(RUNTIME|STYLE)>$' } |
                               Where-Object { $_ -notmatch $keepPattern } |
                               Sort-Object -Unique)
            Raw           = ($out -join "`n")
        }
    }
}

Describe 'every style ships a shell prompt' {
    It '<_> has a prompt.sh alongside its profile.ps1' -ForEach $script:StyleNames {
        # A style with a PowerShell prompt but no shell prompt would apply only
        # half of itself for a zsh user.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $repoRoot 'styles') $_) 'prompt.sh') |
            Should -BeTrue
    }
}

Describe 'shell library' {
    It 'parses under bash' -Skip:(-not $script:HasBash) {
        $out = & bash -n (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell') 'tstyles.sh') 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out | Out-String)
    }

    It 'parses under zsh' -Skip:(-not $script:HasZsh) {
        $out = & zsh -n (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell') 'tstyles.sh') 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out | Out-String)
    }

    It 'emits nothing at all in a NON-interactive shell' -Skip:(-not $script:HasBash) {
        # `ssh host command`, scp and rsync all break if the remote shell writes
        # anything unexpected to stdout at startup. This is the guard for that.
        $lib = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'shell') 'tstyles.sh'
        $out = & bash -c ". '$lib'; printf 'BODY'" 2>&1 | Out-String
        # Out-String appends a trailing newline of its own; the point is that
        # nothing was emitted BEFORE 'BODY'.
        $out.Trim() | Should -Be 'BODY'
    }
}

Describe 'prompts render in bash' -Skip:(-not $script:HasBash) {
    It '<_> produces a non-empty PS1' -ForEach $script:StyleNames {
        (script:Get-RenderedPrompt -Shell 'bash' -StyleName $_).Trim() | Should -Not -BeNullOrEmpty
    }

    It '<_> marks every escape sequence as non-printing' -ForEach $script:StyleNames {
        # bash counts anything outside \[...\] toward the prompt width. An
        # unmarked escape makes it believe the prompt is ~20 columns wider than
        # it is, and the redraw walks over the prompt on long lines and Ctrl-R.
        $ps1 = script:Get-RenderedPrompt -Shell 'bash' -StyleName $_
        # Every ESC introducer must sit immediately after a \[ opener.
        $bare = [regex]::Matches($ps1, '(?<!\\\[)\\033\[')
        $bare.Count | Should -Be 0 -Because "unmarked escapes in: $ps1"
    }
}

Describe 'prompts render in zsh' -Skip:(-not $script:HasZsh) {
    It '<_> produces a non-empty PROMPT' -ForEach $script:StyleNames {
        (script:Get-RenderedPrompt -Shell 'zsh' -StyleName $_).Trim() | Should -Not -BeNullOrEmpty
    }

    It '<_> marks every escape sequence as non-printing' -ForEach $script:StyleNames {
        # zsh's equivalent of bash's \[...\] is %{...%}.
        $prompt = script:Get-RenderedPrompt -Shell 'zsh' -StyleName $_
        $esc = [char]27
        $bare = [regex]::Matches($prompt, "(?<!%\{)$([regex]::Escape($esc))\[")
        $bare.Count | Should -Be 0 -Because "unmarked escapes in: $prompt"
    }

    It '<_> emits no error output while loading' -ForEach $script:StyleNames {
        $rendered = script:Get-RenderedPrompt -Shell 'zsh' -StyleName $_
        $rendered | Should -Not -Match 'command not found'
        $rendered | Should -Not -Match 'parse error'
    }
}

Describe 'cwd tracks the shell, not the load-time directory' {
    It 'bash uses \w rather than a captured path' -Skip:(-not $script:HasBash) {
        # If the generator ever interpolated $PWD at load time instead of
        # emitting the shell's own escape, the prompt would freeze at whatever
        # directory the shell started in.
        script:Get-RenderedPrompt -Shell 'bash' -StyleName 'forest' | Should -Match '\\w'
    }

    It 'zsh uses %~ rather than a captured path' -Skip:(-not $script:HasZsh) {
        script:Get-RenderedPrompt -Shell 'zsh' -StyleName 'forest' | Should -Match '%~'
    }
}

Describe 'banners survive shell quoting' -Skip:(-not $script:HasBash) {
    # Regression guard. Several styles carry a quoted tagline ("Look up. Look
    # closer."). PowerShell writes those as `" inside a double-quoted string; if
    # the shell port emits a BARE " it closes the printf argument early, and the
    # tagline prints one word per line instead of one banner row -- turning the
    # ASCII box into ragged text.
    It '<_> renders each banner row on a single line' -ForEach $script:StyleNames {
        $banner = script:Get-RenderedBanner -Shell 'bash' -StyleName $_
        $rows = @($banner -split "`r?`n" | Where-Object { $_.Trim() })
        foreach ($row in $rows) {
            # Every non-blank row of a boxed banner starts and ends with the box
            # character; a split row would start with a bare word instead.
            $plain = ($row -replace "$([char]27)\[[0-9;]*m", '').Trim()
            if ($plain -match '^\+' -or $plain -match '^\|') {
                $plain | Should -Match '(\+|\|)$' -Because "banner row was split: $plain"
            }
        }
    }
}

Describe 'a style prompt does not clobber the user''s shell variables' {
    # ts_load sources the staged prompt.sh straight into the user's interactive
    # shell, with no isolation. Eleven of the sixteen styles assigned bare
    # single-letter names at top level -- X, W, D, M, P, R, Y, C, B, G, L, O and
    # Mist/Moss/Slate -- so opening a terminal silently overwrote anything the
    # user had by those names. $X and $D are not exotic choices for a person's
    # own scratch variables.
    #
    # _ts_ ONLY. The whitelist used to read ^(TS_|_ts_), which excused the very
    # prefix 0.8.22 declared a leak when it renamed the runtime's TS_LOADED and
    # TS_SHELL -- so gitbash went on defining TS_GIT_OPEN and TS_GIT_CLOSE in
    # the user's shell and this check reported green. A leak check that
    # whitelists the leak is the shape CLAUDE.md warns about.
    # Everything is prefixed _ts_ now. Verified in a real interactive zsh: a
    # .zshrc setting X and D keeps both after the style loads.
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:PromptFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'prompt.sh') } |
                ForEach-Object { $_.Name })
    }

    It '<_>/prompt.sh assigns only namespaced names at top level' -ForEach $script:PromptFiles {
        $path = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') $_) 'prompt.sh'
        $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))

        # NOT anchored at ^. It was, and the styles put a second assignment in
        # the second column of the same physical line --
        # `_ts_R=$(ts_raw '...')        pR=$(ts_c '...')` -- so the lint saw
        # only `_ts_R`, reported green, and nine styles went on clobbering the
        # user's $pX, $pW, $pMist and friends for four releases after the
        # CHANGELOG said the defect was closed.
        $bare = @([regex]::Matches($text, '(?m)(?:^|[\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -notmatch '^_ts_' } |
            Sort-Object -Unique)

        $bare | Should -BeNullOrEmpty `
            -Because "$_ would overwrite the user's own $($bare -join ', ') on every new shell"
    }
}

Describe 'a style leaks nothing into the user shell -- measured, not linted' {
    # The regex lint above is a proxy, and every proxy has a blind spot: it was
    # anchored at ^ and missed a second assignment in the second column, so it
    # certified nine leaking styles as clean for four releases. Widening it
    # closes THAT shape. It does not close the next one -- `eval`, a `for` loop,
    # `read x`, a heredoc, `typeset x=` all assign without matching.
    #
    # So this asks the only authority that cannot be fooled by formatting: a
    # real zsh. Source the file and diff the variable table across it. Whatever
    # the syntax, a name that exists afterwards and did not before is a name the
    # user just lost.
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:LeakStyles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'prompt.sh') } |
                ForEach-Object { $_.Name })

        # Decided HERE, at discovery. A -Skip reading a variable set in
        # BeforeAll gets $null, which is falsy, so the test neither runs nor
        # reports as skipped -- it silently passes. This suite has been bitten
        # by that once already.
        $script:NoZsh = -not (Get-Command zsh -ErrorAction SilentlyContinue)
    }

    It '<_> defines no bare name in a real zsh' -ForEach $script:LeakStyles -Skip:$script:NoZsh {
        $repoRoot  = Split-Path $PSScriptRoot -Parent
        $probe = script:Invoke-ShellLeakProbe `
            -RuntimeSh (Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh') `
            -PromptSh  (Join-Path (Join-Path (Join-Path $repoRoot 'styles') $_) 'prompt.sh') `
            -ScriptPath (Join-Path $TestDrive "leak-$_.zsh")

        # BEFORE the diff is believed. Two identical tables are what a failed
        # source produces, and they are indistinguishable from a clean style.
        $probe.RuntimeLoaded | Should -BeTrue `
            -Because "shell/tstyles.sh must really have loaded, or nothing below measures anything: $($probe.Raw)"
        $probe.StyleLoaded | Should -BeTrue `
            -Because "$_/prompt.sh must really have loaded, or nothing below measures anything: $($probe.Raw)"

        $probe.Leaked -join ', ' | Should -BeNullOrEmpty `
            -Because "sourcing $_/prompt.sh replaced the user's own $($probe.Leaked -join ', ')"
    }

    It 'measures a style whose checkout path contains a space' -Skip:$script:NoZsh {
        # THE HOLE THE SENTINEL AND THE QUOTING CLOSE, on every machine rather
        # than only on a developer whose checkout happens to live under
        # "My Documents". The paths are interpolated into a zsh script; zsh
        # word-splits an unquoted one, so from a directory with a space in it
        # both `source` lines failed and every style in the Describe above
        # passed while nothing had been loaded at all.
        #
        # gitbash is the style used to measure it: with MYVAR and PATH_BACKUP
        # appended to its prompt.sh, the shipped harness reported
        # Passed=17 Failed=0 from '<scratch>/repo space' and Failed=1 naming
        # both variables from '<scratch>/reponospace'.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $spacey   = Join-Path $TestDrive 'spacey path'
        New-Item -ItemType Directory -Path $spacey -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh') `
                  -Destination (Join-Path $spacey 'tstyles.sh') -Force
        Copy-Item -LiteralPath (Join-Path (Join-Path (Join-Path $repoRoot 'styles') 'gitbash') 'prompt.sh') `
                  -Destination (Join-Path $spacey 'prompt.sh') -Force

        $probe = script:Invoke-ShellLeakProbe `
            -RuntimeSh  (Join-Path $spacey 'tstyles.sh') `
            -PromptSh   (Join-Path $spacey 'prompt.sh') `
            -ScriptPath (Join-Path $spacey 'leak-spacey.zsh')

        $probe.RuntimeLoaded | Should -BeTrue `
            -Because "the runtime must load from a path with a space in it: $($probe.Raw)"
        $probe.StyleLoaded | Should -BeTrue `
            -Because "the style must load from a path with a space in it: $($probe.Raw)"
        $probe.Leaked -join ', ' | Should -BeNullOrEmpty `
            -Because "sourcing gitbash/prompt.sh replaced the user's own $($probe.Leaked -join ', ')"
    }
}

Describe 'the runtime itself leaks nothing into the user shell -- measured, not linted' {
    # The Describe above measures styles/<name>/prompt.sh. It never measured
    # shell/tstyles.sh, which is sourced from the user's rc file on EVERY
    # interactive shell -- so the one file guaranteed to run for every user was
    # the one file outside the leak check. It was carrying TS_LOADED and
    # TS_SHELL, bare names in the user's namespace, while the project enforced
    # `_ts_` on the sixteen styles.
    #
    # TSTYLES_DATA is the deliberate exception and stays: the runtime reads it
    # before deriving a default (`if [ -z "${TSTYLES_DATA-}" ]`), and this suite
    # depends on that seam to point a shell at a scratch data root. It is a
    # documented-by-use contract, not a leak. Anything else is.
    BeforeDiscovery {
        # Decided HERE, at discovery, for the reason spelled out above: a -Skip
        # reading a BeforeAll variable gets $null and silently passes.
        $script:NoZshRuntime = -not (Get-Command zsh -ErrorAction SilentlyContinue)
    }

    It 'defines no bare name in a real zsh' -Skip:$script:NoZshRuntime {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        # The same probe the style half uses -- so the quoting and the "did it
        # actually load" sentinel are one implementation, not two. This half
        # carried the identical unquoted interpolation and the identical blind
        # spot.
        $probe = script:Invoke-ShellLeakProbe `
            -RuntimeSh  (Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh') `
            -ScriptPath (Join-Path $TestDrive 'leak-runtime.zsh') `
            -Keep 'TSTYLES_DATA'

        $probe.RuntimeLoaded | Should -BeTrue `
            -Because "shell/tstyles.sh must really have loaded, or nothing below measures anything: $($probe.Raw)"

        $probe.Leaked -join ', ' | Should -BeNullOrEmpty `
            -Because "sourcing shell/tstyles.sh replaced the user's own $($probe.Leaked -join ', ')"
    }
}
