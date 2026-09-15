# Pester 5 tests: shell-init promises a styled zsh/bash tab exactly where the
# two halves of this tool agree on where the style is staged.
#
# THE DEFECT THIS EXISTS FOR. `tstyles help shell-init` said, on every platform:
#
#   Adds a loader to your ~/.zshrc, ~/.bashrc and ~/.bash_profile so a zsh
#   or bash tab comes up in the applied style -- colors, prompt, and banner.
#
# and no Windows configuration can produce that. Three measurements, all on
# 0.8.27:
#
#   * The apply path stages current-style.osc and current-prompt.sh -- the two
#     files shell/tstyles.sh reads -- only off Windows Terminal.
#     Set-ShellStyleState has exactly two non-test call sites and both are on
#     the non-WT path; after a Windows Terminal apply the data root holds
#     current-style.json and nothing else.
#   * shell/tstyles.sh has no MINGW/MSYS/CYGWIN arm: `grep -nE
#     'MINGW|MSYS|CYGWIN|LOCALAPPDATA|AppData' shell/tstyles.sh` matches
#     nothing, and under a `uname` stub returning MINGW64_NT-10.0, MSYS_NT-10.0
#     or CYGWIN_NT-10.0 it resolves TSTYLES_DATA to
#     $HOME/.local/share/TerminalStyles -- while the PowerShell side answers
#     %LOCALAPPDATA%\TerminalStyles.
#   * shell-init does not merely edit rc files there, it INVENTS them: with
#     $env:SHELL unset (which is the Windows shape -- the code's own comment
#     says so) an empty home came out of the run with a .bashrc and a
#     .bash_profile that did not exist before, two green "added" lines, and
#     "Open a new tab, or run: source ~/.bashrc".
#
# The exposure is NOT WSL. A WSL bash reads /home/<user>, which a shell-init run
# from Windows PowerShell never touches, and pwsh inside WSL is an ordinary
# Linux install where both halves already agree. It is an MSYS/Cygwin bash --
# Git Bash -- sharing the Windows $HOME.
#
# The fix taken is the messages, not the mechanism: making it TRUE needs both an
# MSYS arm in the shell runtime AND the Windows Terminal apply path staging the
# shell state, and neither half alone delivers anything. So the test below is
# the one that keeps the two honest with each other -- it MEASURES where the two
# data roots agree and asserts the help promises a styled tab exactly there. If
# someone later makes Windows work, this test fails and says the help is now
# understating what the command does.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null

    # Decided HERE, at discovery: a -Skip reading a variable set in BeforeAll
    # gets $null, which is falsy, so the test would neither run nor report as
    # skipped -- it would silently pass.
    #
    # Unix only, and a `bash` on PATH is not sufficient: the Windows runners
    # ship Git Bash, which would pick this up and then be handed
    # Windows-shaped paths (a single-quoted C:\a\b is a string of escapes to
    # bash).
    $script:NoShellHost = -not (
        ($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows -and
        [bool](Get-Command bash -ErrorAction SilentlyContinue))
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'shell-init promises a styled tab exactly where the two halves agree' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:repoRoot = Split-Path $PSScriptRoot -Parent

            # The data root the SHELL half derives, asked of the shell half.
            # HOME is set inside the generated script rather than in this
            # process, and `uname` is shadowed by a function, which is what
            # lets a macOS runner measure the MSYS answer.
            function script:Get-ShellDataRoot {
                param([string]$Uname, [string]$HomeDir)
                $lines = @(
                    "HOME='$HomeDir'"
                    "uname() { printf '%s\n' '$Uname'; }"
                    'unset TSTYLES_DATA'
                    ". '$(Join-Path (Join-Path $script:repoRoot 'shell') 'tstyles.sh')' >/dev/null 2>&1"
                    'printf "%s\n" "$TSTYLES_DATA"'
                )
                $sf = Join-Path $TestDrive "root-$Uname.sh"
                [System.IO.File]::WriteAllText($sf, ($lines -join "`n"),
                    [System.Text.UTF8Encoding]::new($false))
                return ((& bash --noprofile --norc $sf 2>$null) | Select-Object -Last 1)
            }

            # The sentence that IS the promise. One phrase, so "does the help
            # promise a styled tab" is a question with an answer rather than a
            # judgement call.
            $script:StyledTabPromise = 'comes up in the applied style'
        }

        It 'the help promises a styled tab on <Platform> iff the runtime looks where the apply stages' -Skip:$script:NoShellHost -ForEach @(
            @{ Platform = 'MacOS';   Uname = 'Darwin' }
            @{ Platform = 'Linux';   Uname = 'Linux' }
            @{ Platform = 'Windows'; Uname = 'MINGW64_NT-10.0-22631' }
        ) {
            $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

            $shellRoot = script:Get-ShellDataRoot -Uname $Uname -HomeDir $sandbox
            $shellRoot | Should -Not -BeNullOrEmpty `
                -Because 'the runtime must report a data root, or nothing here is measured'

            $psRoot = Get-TStylesDataRoot -Platform $Platform -HomeDir $sandbox
            $psRoot | Should -Not -BeNullOrEmpty

            # Compared after normalising the separator only: on Windows the
            # PowerShell half answers with backslashes and the shell half never
            # would, and that is a spelling difference, not the defect.
            $agree = (($shellRoot -replace '\\', '/') -eq ($psRoot -replace '\\', '/'))

            $detail = ((Get-TerminalStyleHelpData -Platform $Platform |
                        Where-Object { $_.Name -eq 'shell-init' }).Detail -join ' ')
            $detail | Should -Not -BeNullOrEmpty
            $promises = $detail.Contains($script:StyledTabPromise)

            $promises | Should -Be $agree -Because (
                "on $Platform the shell runtime reads '$shellRoot' and an apply stages to " +
                "'$psRoot'; the help may promise a styled tab only where those are the same place")
        }

        It 'the Windows topic names both of the paths that disagree' -Skip:$script:NoShellHost {
            # Not a word-grep on a hand-typed phrase: the shell-side path is the
            # MEASURED one, so an MSYS arm added to shell/tstyles.sh later makes
            # this fail rather than leaving a stale explanation standing.
            $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

            $shellRoot = script:Get-ShellDataRoot -Uname 'MSYS_NT-10.0' -HomeDir $sandbox
            $tail = $shellRoot.Substring($sandbox.Length).TrimStart('/')
            $tail | Should -Not -BeNullOrEmpty

            $detail = ((Get-TerminalStyleHelpData -Platform 'Windows' |
                        Where-Object { $_.Name -eq 'shell-init' }).Detail -join ' ')
            $detail | Should -Match ([regex]::Escape($tail)) `
                -Because 'the topic must name where the runtime really looks'
            $detail | Should -Match 'LOCALAPPDATA' `
                -Because 'and where the apply really stages'
        }
    }
}

Describe 'shell-init says what it can deliver before it writes anything' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # -HomeDir alone is NOT a sandbox: shell-init reaches
            # Sync-ShellRuntime, which writes to the data root and has no seam
            # of its own.
            $script:savedRoot = $script:TStylesDataRoot
            $script:dataRoot  = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:dataRoot -Force | Out-Null
            $script:TStylesDataRoot = $script:dataRoot

            $script:home = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:home -Force | Out-Null
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'warns before the first rc file is written, on Windows' {
            $out = Invoke-TerminalStylesShellInit -Platform 'Windows' -HomeDir $script:home 6>&1 | Out-String -Width 500

            $out | Should -Match 'does not produce a styled zsh/bash tab' `
                -Because 'the limit belongs where consent is given, not after the files are written'

            # BEFORE, not merely somewhere: this command creates rc files for a
            # user who has none, and a caveat printed under the "added" lines is
            # a caveat printed after the fact.
            # A plain loop, not [array]::FindIndex with a [Predicate[string]]
            # cast: this file runs on the Windows PowerShell 5.1 leg too, and
            # the cheap thing that works on both engines is the one to write.
            $lines   = @($out -split "`r?`n")
            $caveat  = -1
            $written = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($caveat -lt 0 -and $lines[$i] -match 'does not produce a styled') { $caveat = $i }
                if ($written -lt 0 -and $lines[$i] -match '^\s+(added|updated)\s')   { $written = $i }
            }
            $written | Should -BeGreaterThan -1 -Because 'the run must really have written something'
            $caveat  | Should -BeGreaterThan -1
            $caveat  | Should -BeLessThan $written
        }

        It 'says nothing of the sort on macOS, where the loader works' {
            $out = Invoke-TerminalStylesShellInit -Platform 'MacOS' -HomeDir $script:home 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'does not produce a styled zsh/bash tab' `
                -Because 'a caveat printed where it does not apply is its own false claim'
        }
    }
}
