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

    $script:HasZsh  = [bool](Get-Command zsh  -ErrorAction SilentlyContinue)
    $script:HasBash = [bool](Get-Command bash -ErrorAction SilentlyContinue)
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
