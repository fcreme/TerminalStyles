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
            Where-Object { $_ -notmatch '^(TS_|_ts_)' } |
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
        $promptSh  = Join-Path (Join-Path (Join-Path $repoRoot 'styles') $_) 'prompt.sh'
        $runtimeSh = Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh'

        # `typeset +m '*'` prints names only. The two capture variables are
        # themselves new names, so they are filtered with the namespaced ones.
        $script = @(
            "source ${runtimeSh} >/dev/null 2>&1"
            'ts_before=$(typeset +m "*" 2>/dev/null)'
            "source ${promptSh} >/dev/null 2>&1"
            'ts_after=$(typeset +m "*" 2>/dev/null)'
            'comm -13 <(print -r -- "$ts_before" | sort -u) <(print -r -- "$ts_after" | sort -u)'
        ) -join "`n"

        $sf = Join-Path $TestDrive ("leak-$_.zsh")
        [System.IO.File]::WriteAllText($sf, $script, [System.Text.UTF8Encoding]::new($false))

        $out = & zsh -f $sf 2>$null
        $leaked = @($out | Where-Object { $_ -and $_ -notmatch '^(TS_|_ts_|ts_before$|ts_after$)' } |
                   Sort-Object -Unique)

        $leaked -join ', ' | Should -BeNullOrEmpty `
            -Because "sourcing $_/prompt.sh replaced the user's own $($leaked -join ', ')"
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
    # before deriving a default (`if [ -z "$TSTYLES_DATA" ]`), and this suite
    # depends on that seam to point a shell at a scratch data root. It is a
    # documented-by-use contract, not a leak. Anything else is.
    BeforeDiscovery {
        # Decided HERE, at discovery, for the reason spelled out above: a -Skip
        # reading a BeforeAll variable gets $null and silently passes.
        $script:NoZshRuntime = -not (Get-Command zsh -ErrorAction SilentlyContinue)
    }

    It 'defines no bare name in a real zsh' -Skip:$script:NoZshRuntime {
        $repoRoot  = Split-Path $PSScriptRoot -Parent
        $runtimeSh = Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh'

        $script = @(
            'ts_before=$(typeset +m "*" 2>/dev/null)'
            "source ${runtimeSh} >/dev/null 2>&1"
            'ts_after=$(typeset +m "*" 2>/dev/null)'
            'comm -13 <(print -r -- "$ts_before" | sort -u) <(print -r -- "$ts_after" | sort -u)'
        ) -join "`n"

        $sf = Join-Path $TestDrive 'leak-runtime.zsh'
        [System.IO.File]::WriteAllText($sf, $script, [System.Text.UTF8Encoding]::new($false))

        $out = & zsh -f $sf 2>$null
        $leaked = @($out | Where-Object {
                       $_ -and $_ -notmatch '^(_ts_|ts_before$|ts_after$|TSTYLES_DATA$)'
                   } | Sort-Object -Unique)

        $leaked -join ', ' | Should -BeNullOrEmpty `
            -Because "sourcing shell/tstyles.sh replaced the user's own $($leaked -join ', ')"
    }
}
