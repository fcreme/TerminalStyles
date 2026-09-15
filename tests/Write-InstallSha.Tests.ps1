# Pester 5 tests for Write-InstallSha -- the installer's record of the commit it
# just landed, and the file the update checker reads.
#
# THE DEFECT. The record step caught its failed api.github.com call, printed
# "update checker will be disabled" and left a PRE-EXISTING .installed-sha
# exactly where it was. That sentence is true only of a FIRST install, where
# there is no file and Test-UpdateAvailable's missing-file branch really does
# turn the check off. The common way in is a RE-install -- `tstyles update` on a
# bootstrap install re-runs install.ps1, and Sync-InstallTree preserves
# .installed-sha because the download does not ship it (pinned in
# tests/Sync-InstallTree.Tests.ps1) -- so the tree was the new code while the
# record still named the previous commit. Far from disabled, the checker then
# read that stale commit and reported an update the user had already applied,
# once every 24 hours; and the `tstyles update` it told them to run compared the
# same stale value, missed its "Already up to date" short-circuit, and
# re-downloaded the ~10 MB ZIP. A 200 carrying no `sha` produced the identical
# state with nothing printed at all.
#
# So these tests are about what is left ON DISK when the record fails, not about
# the wording: "we do not know what is installed" is the state the checker's
# missing-file branch is for, and a record known to be wrong can only produce a
# wrong answer.
#
# The installer is dot-sourced with $TStylesInstallNoRun = $true so its functions
# load WITHOUT running the download/install flow.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null

    $script:installPath = Join-Path $repoRoot 'install.ps1'
    $TStylesInstallNoRun = $true
    . $script:installPath

    $script:enc = [System.Text.UTF8Encoding]::new($false)
}

Describe 'Write-InstallSha' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('inst-' + [guid]::NewGuid().Guid.Substring(0, 8))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
        $script:shaFile = Join-Path $script:dir '.installed-sha'
        # What the PREVIOUS install left. This is the value that must not survive
        # a failed record: the tree is new, so it now names the wrong commit.
        $script:stale = '1' * 40
        [System.IO.File]::WriteAllText($script:shaFile, $script:stale, $script:enc)
        # -Force on every Remove-Item of this file, here and in the code: the name
        # starts with a dot, and on macOS/Linux Remove-Item skips a hidden item
        # without it -- which would leave the stale value in place and let these
        # tests pass while measuring nothing.
    }

    It 'removes a stale record when the API call fails' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (rate limit exceeded).' }

        Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly `
            -Because 'the mock must be the thing that answered, not the network'
        [System.IO.File]::Exists($script:shaFile) | Should -BeFalse `
            -Because 'a record naming the commit we just replaced is worse than none'
    }

    It 'says what went wrong and what it means, on the failing path' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (rate limit exceeded).' }

        $out = Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-String

        $out | Should -Match '403' -Because 'a rate limit and a dead proxy are not the same advice'
        $out | Should -Match 'update check is off until the next install'
    }

    It 'removes a stale record when the API answers 200 with no sha' {
        # A proxy error page, a rate-limit body: 200, JSON, no commit in it. This
        # fell through the `if ($commitInfo.sha)` guard and printed nothing at
        # all -- the same broken state, silently.
        Mock Invoke-RestMethod { [pscustomobject]@{ message = 'Not Found' } }

        $out = Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-String

        [System.IO.File]::Exists($script:shaFile) | Should -BeFalse
        $out | Should -Match 'update check is off until the next install' `
            -Because 'the silent fall-through was the same defect with no notice'
    }

    It 'records the sha exactly, UTF-8 with no BOM, on the normal path' {
        Mock Invoke-RestMethod { [pscustomobject]@{ sha = ('2' * 40) } }

        Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-Null

        [System.IO.File]::ReadAllText($script:shaFile, $script:enc) | Should -Be ('2' * 40)
        $bytes = [System.IO.File]::ReadAllBytes($script:shaFile)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
            Should -BeFalse -Because 'Test-UpdateAvailable compares the text, and a BOM is not part of a sha'
    }

    It 'is quiet about a file that was never there, and does not throw' {
        Remove-Item -LiteralPath $script:shaFile -Force
        Mock Invoke-RestMethod { throw 'no network' }

        { Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-Null } |
            Should -Not -Throw
        [System.IO.File]::Exists($script:shaFile) | Should -BeFalse
    }
}

Describe 'a failed record really does turn the check off' {
    # The message is a claim about what the OTHER half of this pair will do, so
    # the other half is what has to be measured. This is the end of the loop:
    # installer records nothing -> checker says nothing.
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('e2e-' + [guid]::NewGuid().Guid.Substring(0, 8))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:dir '.installed-sha'), ('1' * 40), $script:enc)
    }

    It 'prints no update notice after the record failed' {
        Mock Invoke-RestMethod { throw 'api.github.com is not reachable' }
        Write-InstallSha -InstallDir $script:dir -Repo 'fcreme/TerminalStyles' -Branch 'main' 6>&1 | Out-Null

        $notice = InModuleScope TerminalStyles -Parameters @{ dataRoot = $script:dir } {
            param($dataRoot)
            $script:TStylesDataRoot = $dataRoot
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            # The checker's own API call succeeds -- this is the split that made
            # the stale record visible: recording failed while checking works.
            Mock Invoke-RestMethod { [pscustomobject]@{ sha = ('2' * 40) } }
            Show-UpdateNoticeIfAvailable 6>&1 | Out-String
        }

        $notice | Should -Not -Match 'Update available' `
            -Because 'the stale record named the commit the user is already running'
    }
}
