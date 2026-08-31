# Pester 5 tests: a style's PowerShell half and its zsh/bash half must render
# the same prompt.
#
# Every prompt.sh carries a header saying the two are meant to look the same and
# to keep them in sync, and nothing ever checked it. They had drifted in three
# separate ways, all of them invisible on Windows and all of them permanent on
# macOS and Linux:
#
#   * gitbash, neon-rain and umbrella read $env:USERNAME (and gitbash also
#     $env:COMPUTERNAME) -- Windows-only variables that pwsh does not set on
#     Unix. gitbash rendered "@ MINGW64 <path>" with the identity segment
#     blank, on the one style whose entire point is that line.
#   * fourteen styles printed an absolute path where the shell half printed a
#     ~-abbreviated one, because {CWD} maps to %~ / \w and $PWD.Path abbreviates
#     nothing.
#   * sober took the leaf of $HOME instead of '~', and did it before
#     abbreviating rather than after, so the home directory showed as the user's
#     own folder name.
#
# A static lint cannot see any of this: each half is valid on its own and the
# drift only exists between them. So render both and compare.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'a style renders the same prompt in PowerShell and in zsh' {
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:ParityStyles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object {
                    (Test-Path -LiteralPath (Join-Path $_.FullName 'prompt.sh')) -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName 'profile.ps1'))
                } | ForEach-Object { $_.Name })

        # Decided at DISCOVERY. A -Skip that reads a variable set in BeforeAll
        # gets $null -- falsy -- so the test neither runs nor reports skipped:
        # it silently passes. Windows CI has no zsh and must skip honestly.
        $script:NoParityShell = -not (Get-Command zsh -ErrorAction SilentlyContinue)
    }

    It '<_> renders identically in both halves' -ForEach $script:ParityStyles -Skip:$script:NoParityShell {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $styleDir = Join-Path (Join-Path $repoRoot 'styles') $_
        $runtime  = Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh'

        # $HOME is the cwd on purpose: it is the case the drift actually showed
        # up in (~ vs the absolute path, ~ vs the folder's own name) and both
        # shells agree on what it is. A temp directory would not do -- macOS
        # puts those behind a symlink, and pwsh reports the resolved path while
        # zsh keeps the logical one, which is a shell difference rather than
        # anything a style controls.
        $strip = { param($s) ($s -replace "`e\[[0-9;]*m", '') }

        # The PowerShell half in a CHILD process: profile.ps1 defines
        # global:prompt and sets PSReadLine options, neither of which belongs in
        # the test host.
        $psOut = & pwsh -NoProfile -Command @"
`$ErrorActionPreference = 'SilentlyContinue'
Set-Location -LiteralPath '$HOME'
. '$(Join-Path $styleDir 'profile.ps1')' *> `$null
[Console]::Out.Write((prompt))
"@ 2>$null
        if (-not $psOut) {
            $psOut = & pwsh-preview -NoProfile -Command @"
`$ErrorActionPreference = 'SilentlyContinue'
Set-Location -LiteralPath '$HOME'
. '$(Join-Path $styleDir 'profile.ps1')' *> `$null
[Console]::Out.Write((prompt))
"@ 2>$null
        }

        $zshScript = @(
            "cd '$HOME'"
            "source '$runtime' >/dev/null 2>&1"
            "source '$(Join-Path $styleDir 'prompt.sh')' >/dev/null 2>&1"
            'print -Pn -- "$PROMPT"'
        ) -join "`n"
        $sf = Join-Path $TestDrive "parity-$_.zsh"
        [System.IO.File]::WriteAllText($sf, $zshScript, [System.Text.UTF8Encoding]::new($false))
        $zshOut = & zsh -f $sf 2>$null

        $psText  = & $strip (($psOut  -join "`n").TrimEnd())
        $zshText = & $strip (($zshOut -join "`n").TrimEnd())

        $psText | Should -Not -BeNullOrEmpty -Because 'the PowerShell half must render something'
        $psText | Should -Be $zshText -Because "$_'s two halves must show the same prompt"
    }
}

Describe 'a style does not rebind the line editor outside Windows' {
    # Every profile.ps1 called `Set-PSReadLineOption -EditMode Windows`
    # unconditionally. On Windows that is already the default and costs nothing.
    # On macOS and Linux, where PSReadLine defaults to Emacs, it UNBINDS Ctrl+E,
    # Ctrl+K, Ctrl+U and Ctrl+D and turns Ctrl+A into SelectAll -- so applying a
    # colour theme took away Ctrl+D (end session) and Ctrl+U (clear line), on
    # every new tab, with nothing on screen to explain it and no README
    # mentioning edit mode at all.
    #
    # Static, so it also runs on the Windows 5.1 job, where the damage cannot be
    # observed and the regression would otherwise land unseen.
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:ProfileStyles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'profile.ps1') } |
                ForEach-Object { $_.Name })
    }

    It '<_>/profile.ps1 guards any EditMode call behind a platform test' -ForEach $script:ProfileStyles {
        $path = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') $_) 'profile.ps1'
        $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))

        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match 'Set-PSReadLineOption\s+-EditMode') {
                # The call must sit inside a platform branch. Indentation deeper
                # than the `if` that guards it is the observable trace of that.
                $text | Should -Match '\$IsWindows' `
                    -Because "$_ sets EditMode, so it must test the platform first"
            }
        }
    }

    It 'the platform test admits Windows PowerShell 5.1, which predates $IsWindows' -ForEach $script:ProfileStyles {
        # Referencing $IsWindows under 5.1 yields $null, not $true, so a bare
        # `if ($IsWindows)` would stop setting EditMode on the one engine where
        # it is genuinely wanted. Get-TStylesPlatform tests the major version
        # first for exactly this reason; the styles must do the same.
        $path = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') $_) 'profile.ps1'
        $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))

        if ($text -match 'Set-PSReadLineOption\s+-EditMode') {
            $text | Should -Match 'PSVersion\.Major\s+-lt\s+6' `
                -Because "$_ must still set EditMode on Windows PowerShell 5.1"
        }
    }
}
