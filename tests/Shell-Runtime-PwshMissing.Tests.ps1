# Pester 5 tests: what shell/tstyles.sh says when it cannot find PowerShell.
#
# The `tstyles` wrapper this file defines is the whole CLI for a zsh or bash
# user, and TerminalStyles is a PowerShell module, so "PowerShell not found" is
# the one message that has to tell them how to get out of it. It said:
#
#     tstyles: PowerShell not found. Install it with: brew install powershell
#
# unconditionally -- on a host where the same file had, 275 lines earlier,
# derived an XDG data root because `uname -s` said Linux. Homebrew is not the
# route there, and this is the message a Linux user gets at the moment they have
# no working command to ask anything else with. CI runs the zsh/bash legs on
# ubuntu-latest as well as macos-latest, so Linux is a first-class host for it.
#
# Measured before the fix, under `env -i` with a stub `uname` reporting Linux:
#   data root the file derived for this platform: <HOME>/.local/share/TerminalStyles
#   tstyles: PowerShell not found. Install it with: brew install powershell
#
# Both halves of the platform split are asserted here: Darwin must still say
# `brew install powershell` verbatim -- that exact string is the 0.8.3 fix that
# corrected a cask to a formula, and a regression in that direction would be the
# same defect pointing the other way.
#
# Everything runs under `env -i` with HOME in $TestDrive and a PATH holding
# NOTHING but the stub directory, so no real rc file, $HOME, data root or
# installed pwsh is reachable from here -- and the absence of pwsh is a property
# of the harness rather than of the machine it runs on.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    # Decided HERE, at discovery. `-Skip:` is evaluated at DISCOVERY, so a flag
    # set in BeforeAll is $null there: the test would neither run nor report as
    # skipped, and the file would go green having measured nothing.
    $script:IsUnixHost = ($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows
    # A `bash` on PATH is not enough on its own: the Windows runners ship Git
    # Bash, and the zsh/bash runtime is a macOS/Linux feature.
    $script:NoBash = -not ($script:IsUnixHost -and (Get-Command bash -ErrorAction SilentlyContinue))
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:runtime  = Join-Path (Join-Path $script:repoRoot 'shell') 'tstyles.sh'

    # Source the runtime and call `tstyles` in a bash that has a stub `uname`
    # and no PowerShell of any name on its PATH.
    #
    # PATH is the stub directory ALONE. The runtime needs exactly one external
    # command to reach the branch under test (`uname -s`, for the data root and
    # for the message); printf and command are shell builtins. So an empty PATH
    # is what proves `command -v pwsh` fails for the reason the test intends,
    # on a machine that has pwsh installed -- which every machine running this
    # suite does.
    function script:Invoke-TstylesWithoutPwsh {
        param([Parameter(Mandatory)][string]$Kernel)

        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $bin  = Join-Path $case 'bin'
        $home2 = Join-Path $case 'home'
        New-Item -ItemType Directory -Path $bin   -Force | Out-Null
        New-Item -ItemType Directory -Path $home2 -Force | Out-Null

        $uname = Join-Path $bin 'uname'
        [System.IO.File]::WriteAllText($uname, "#!/bin/sh`nprintf '$Kernel\n'`n")
        & chmod +x $uname

        $errFile = Join-Path $case 'err.txt'
        $body = @"
. '$($script:runtime)'
printf 'DATA[%s]\n' "`$TSTYLES_DATA"
printf 'PWSH[%s%s]\n' "`$(command -v pwsh)" "`$(command -v pwsh-preview)"
tstyles list
printf 'RC[%s]\n' "`$?"
"@
        $wrapped = "{ $body`n} 2>'$errFile'"
        $out = & env -i "HOME=$home2" "PATH=$bin" 'TERM=dumb' `
                   (Get-Command bash).Source -c $wrapped 2>&1 | Out-String
        $err = if (Test-Path -LiteralPath $errFile) {
            [System.IO.File]::ReadAllText($errFile)
        } else { '' }

        return [pscustomobject]@{
            Kernel   = $Kernel
            StdOut   = $out
            StdErr   = $err
            Home     = $home2
            DataRoot = [regex]::Match($out, 'DATA\[(?<v>[^\]]*)\]').Groups['v'].Value
            FoundPwsh = [regex]::Match($out, 'PWSH\[(?<v>[^\]]*)\]').Groups['v'].Value
            ExitCode = [regex]::Match($out, 'RC\[(?<v>[^\]]*)\]').Groups['v'].Value
        }
    }
}

Describe 'the PowerShell-not-found message names a route that exists on this platform' {

    It 'does not send a Linux user to Homebrew' -Skip:$script:NoBash {
        $r = script:Invoke-TstylesWithoutPwsh -Kernel 'Linux'

        # The harness first: a wrapper that found a pwsh never reaches the
        # branch, and would pass this file while measuring nothing.
        $r.FoundPwsh | Should -BeNullOrEmpty `
            -Because "the branch under test is only reached with no PowerShell on PATH; stdout was:`n$($r.StdOut)"
        $r.ExitCode | Should -Be '127' -Because "that is the not-found branch; stdout was:`n$($r.StdOut)"
        # And the file really did take its Linux branch for this same host.
        $r.DataRoot | Should -Be (Join-Path $r.Home '.local/share/TerminalStyles') `
            -Because 'the XDG root is what makes the Homebrew advice wrong on this host'

        $r.StdErr | Should -Match 'PowerShell not found'
        $r.StdErr | Should -Not -Match '(?i)brew' `
            -Because "Homebrew is not how PowerShell arrives on Linux; it said: $($r.StdErr)"
        $r.StdErr | Should -Match 'aka\.ms/powershell' `
            -Because "a user with no working command needs somewhere to go; it said: $($r.StdErr)"
    }

    It 'still gives macOS the Homebrew formula, verbatim' -Skip:$script:NoBash {
        # The other half of the split. `brew install powershell` is the exact
        # string 0.8.3 landed (it had been the retired cask), so this pins the
        # text and not just the presence of the word.
        $r = script:Invoke-TstylesWithoutPwsh -Kernel 'Darwin'

        $r.FoundPwsh | Should -BeNullOrEmpty `
            -Because "the branch under test is only reached with no PowerShell on PATH; stdout was:`n$($r.StdOut)"
        $r.ExitCode | Should -Be '127'
        $r.DataRoot | Should -Be (Join-Path $r.Home 'Library/Application Support/TerminalStyles') `
            -Because 'the macOS branch is what makes the Homebrew advice right here'

        $r.StdErr | Should -Match 'PowerShell not found'
        $r.StdErr | Should -Match 'brew install powershell'
    }

    It 'pays for the platform question only when it has something to say' -Skip:$script:NoBash {
        # This file is sourced on EVERY interactive shell start, and its header
        # forbids spending a subprocess there. The `uname` for the message must
        # therefore live inside the not-found branch, not at file scope -- which
        # would double the cost of every new tab to answer a question almost no
        # tab asks. Measured by counting what the stub is asked: sourcing the
        # runtime with TSTYLES_DATA already set must not run it at all.
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $bin  = Join-Path $case 'bin'
        $home2 = Join-Path $case 'home'
        New-Item -ItemType Directory -Path $bin   -Force | Out-Null
        New-Item -ItemType Directory -Path $home2 -Force | Out-Null

        # A counting stub: one line appended per call.
        $tally = Join-Path $case 'uname-calls.txt'
        $uname = Join-Path $bin 'uname'
        [System.IO.File]::WriteAllText($uname, "#!/bin/sh`nprintf 'called\n' >> '$tally'`nprintf 'Linux\n'`n")
        & chmod +x $uname

        $body = "TSTYLES_DATA='$case/data'`n. '$($script:runtime)'`nprintf 'SOURCED\n'"
        $out = & env -i "HOME=$home2" "PATH=$bin" 'TERM=dumb' `
                   (Get-Command bash).Source -c $body 2>&1 | Out-String
        $out | Should -Match 'SOURCED'

        $calls = if (Test-Path -LiteralPath $tally) {
            @([System.IO.File]::ReadAllLines($tally)).Count
        } else { 0 }
        $calls | Should -Be 0 `
            -Because 'sourcing the runtime must spend no subprocess on the platform question'
    }
}

# A file that skips everything is indistinguishable from a file that passes, so
# say out loud where it is expected to have run.
Describe 'the not-found measurements actually ran somewhere' {
    It 'found a bash to measure on a platform that has one' {
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
            Set-ItResult -Skipped -Because 'Windows has no POSIX shell; the Its above are skipped too'
            return
        }
        (Get-Command bash -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty `
            -Because 'on macOS or Linux bash must be found, or this file measured nothing'
    }
}
