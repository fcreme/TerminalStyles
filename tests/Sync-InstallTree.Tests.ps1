# Pester 5 tests for Sync-InstallTree -- the bootstrap installer's file-placing
# step, and the reason `tstyles update` no longer destroys your data.
#
# The bug it replaces: the installer did `Remove-Item -Recurse -Force` on the
# install directory, which IS the module's writable data root, then copied a
# hand-listed subset back. Anything off that list died on every update. The list
# read styles/<name>/background.* -- the PRE-0.2.0 cache location -- so on any
# current install it preserved nothing while deleting the real cache (tens of
# megabytes) and every tuned style. The restore path also hardcoded a backslash
# separator, so it could not have worked off Windows regardless.
#
# The second contract, from the two failure contexts at the bottom: a sync that
# cannot finish leaves a WORKING install, or says in as many words that it did
# not. Copying into staging before anything is removed is what buys the first
# half; the two messages are the second half, and they are asserted because the
# only caller, `tstyles update`, prints "You can retry manually" under both --
# which on its own reads as "nothing was changed".
#
# The installer is dot-sourced with $TStylesInstallNoRun = $true so its functions
# load WITHOUT running the download/install flow. Note the tests deliberately do
# NOT set $ErrorActionPreference: the real installer does, but the guarantee has
# to hold without it, so Sync-InstallTree sets its own.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Sync-InstallTree' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    BeforeEach {
        # The freshly downloaded tree: what a release actually ships.
        $script:extracted = Join-Path $TestDrive ('new-' + [guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Path $script:extracted -Force | Out-Null
        foreach ($f in 'TerminalStyles.psd1','TerminalStyles.psm1','tstyles.ps1','terminals.ps1','install.ps1') {
            Set-Content -LiteralPath (Join-Path $script:extracted $f) -Value 'NEW' -NoNewline
        }
        New-Item -ItemType Directory -Path (Join-Path $script:extracted 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:extracted 'docs/DEMO.md') -Value 'NEW' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:extracted 'styles/eva') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:extracted 'styles/eva/scheme.json') -Value 'NEW' -NoNewline

        # The existing install: shipped files from the OLD version, plus a data
        # root full of the user's own things.
        $script:installDir = Join-Path $TestDrive ('inst-' + [guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Path $script:installDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'tstyles.ps1') -Value 'OLD' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'styles/eva') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'styles/eva/scheme.json') -Value 'OLD' -NoNewline

        # --- user state, none of which the install owns ---
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'cache/eva') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'cache/eva/background.gif') -Value 'MY-CACHED-GIF' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'styles/felitest') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'styles/felitest/scheme.json') -Value 'MY-TUNED-STYLE' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'styles/felitest/tune.json') -Value 'MY-TUNE' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'fonts/JetBrainsMono') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'fonts/JetBrainsMono/download.bin') -Value 'FONT' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'profiles') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'profiles/eva.terminal') -Value 'PROFILE' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'current-style.ps1')  -Value 'MY-PROMPT' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'current-style.json') -Value 'MY-RECORD' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'current-style.osc')  -Value 'MY-OSC' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'current-prompt.sh')  -Value 'MY-SH' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir 'tstyles.sh')         -Value 'STAGED-RUNTIME' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir '.installed-sha')     -Value 'SHA' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:installDir '.fonts-prompted')    -Value '' -NoNewline

        function script:Content { param([string]$Rel) Get-Content -LiteralPath (Join-Path $script:installDir $Rel) -Raw }
        function script:Exists  { param([string]$Rel) Test-Path -LiteralPath (Join-Path $script:installDir $Rel) }
    }

    Context 'user state survives an update' {
        BeforeEach { Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir }

        It 'keeps the cached backgrounds' {
            # The headline loss: tens of megabytes, re-downloaded from the gifs
            # branch one 10-second request at a time.
            script:Exists 'cache/eva/background.gif' | Should -BeTrue
            script:Content 'cache/eva/background.gif' | Should -Be 'MY-CACHED-GIF'
        }

        It 'keeps tuned and user-authored styles' {
            script:Content 'styles/felitest/scheme.json' | Should -Be 'MY-TUNED-STYLE'
            script:Content 'styles/felitest/tune.json'   | Should -Be 'MY-TUNE'
        }

        It 'keeps the active style and its shell staging' {
            script:Content 'current-style.ps1'  | Should -Be 'MY-PROMPT'
            script:Content 'current-style.json' | Should -Be 'MY-RECORD'
            script:Content 'current-style.osc'  | Should -Be 'MY-OSC'
            script:Content 'current-prompt.sh'  | Should -Be 'MY-SH'
            script:Content 'tstyles.sh'         | Should -Be 'STAGED-RUNTIME'
        }

        It 'keeps the font cache and generated Terminal.app profiles' {
            script:Content 'fonts/JetBrainsMono/download.bin' | Should -Be 'FONT'
            script:Content 'profiles/eva.terminal'            | Should -Be 'PROFILE'
        }

        It 'keeps the update-check markers' {
            script:Exists '.installed-sha'  | Should -BeTrue
            script:Exists '.fonts-prompted' | Should -BeTrue
        }
    }

    Context 'shipped files are actually updated' {
        BeforeEach { Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir }

        It 'replaces the old module files' {
            script:Content 'tstyles.ps1' | Should -Be 'NEW'
        }

        It 'lands files the previous version did not ship' {
            script:Content 'terminals.ps1'      | Should -Be 'NEW'
            script:Content 'TerminalStyles.psd1'| Should -Be 'NEW'
            script:Content 'docs/DEMO.md'       | Should -Be 'NEW'
        }

        It 'updates a bundled style in place' {
            script:Content 'styles/eva/scheme.json' | Should -Be 'NEW'
        }
    }

    It 'works on a first install, where nothing is there yet' {
        $fresh = Join-Path $TestDrive ('fresh-' + [guid]::NewGuid().Guid.Substring(0,8))
        { Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $fresh } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $fresh 'TerminalStyles.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fresh 'styles/eva/scheme.json') | Should -BeTrue
    }

    It 'removes a stale file from a shipped directory' {
        # docs/ is wholly install-owned, so a file dropped between releases must
        # not linger. This is what replacing the whole entry -- rather than
        # merging the new tree over the old one -- is for.
        New-Item -ItemType Directory -Path (Join-Path $script:installDir 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:installDir 'docs/GONE.md') -Value 'stale' -NoNewline
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir
        script:Exists 'docs/GONE.md' | Should -BeFalse
        script:Exists 'docs/DEMO.md' | Should -BeTrue
    }

    It 'never deletes the styles tree wholesale' {
        # styles/ is the one shared directory. The README documents dropping a
        # folder named after a bundled theme to override it, so on a bootstrap
        # install a user's override and the shipped theme are the same path --
        # deleting the tree would take the user's work with it.
        Set-Content -LiteralPath (Join-Path $script:installDir 'styles/eva/my-extra-note.txt') `
            -Value 'MINE' -NoNewline
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir
        script:Content 'styles/eva/my-extra-note.txt' | Should -Be 'MINE'
        script:Content 'styles/eva/scheme.json'       | Should -Be 'NEW'
    }

    Context 'a downloaded file cannot be copied' {
        # The failure this sync has to survive. It used to remove every
        # install-owned entry in one loop and copy them back in the next, under
        # the installer's $ErrorActionPreference = 'Stop' -- so one unreadable
        # source file, or a disk that filled up part-way, ended the installer
        # with TerminalStyles.psd1 already deleted and the $PROFILE loader still
        # importing it. Every new tab then opened on "no valid module file was
        # found" and had no `tstyles` to fix it with.
        BeforeEach {
            # The manifest the loader imports. The install seeded above ships an
            # old tstyles.ps1 but no .psd1, and what a new tab finds is the whole
            # point here, so give it the full set of shipped entries.
            Set-Content -LiteralPath (Join-Path $script:installDir 'TerminalStyles.psd1') -Value 'OLD' -NoNewline
            Set-Content -LiteralPath (Join-Path $script:installDir 'terminals.ps1')       -Value 'OLD' -NoNewline
            New-Item -ItemType Directory -Path (Join-Path $script:installDir 'docs') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:installDir 'docs/DEMO.md') -Value 'OLD' -NoNewline

            # A real lock rather than a mocked Copy-Item: the downloaded file is
            # held open with FileShare.None, which is exactly the cause the
            # installer's own message already names ("another PowerShell tab,
            # OneDrive, or antivirus"). .NET enforces the share mode on Windows
            # and on Unix, so it is the same fault on all four CI legs.
            $locked = Join-Path $script:extracted 'TerminalStyles.psm1'
            $handle = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open,
                                             [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            $script:syncError = $null
            try {
                try   { Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir }
                catch { $script:syncError = $_ }
            } finally {
                $handle.Dispose()
            }
        }

        It 'fails, rather than reporting a half-finished install as done' {
            # Guards the two below: if the lock did not bite on some platform the
            # sync would succeed, and "the old files are still there" would be
            # measuring nothing.
            $script:syncError | Should -Not -BeNullOrEmpty
        }

        It 'leaves the previous install complete and still importable' {
            script:Content 'TerminalStyles.psd1' | Should -Be 'OLD'
            script:Content 'tstyles.ps1'         | Should -Be 'OLD'
            script:Content 'terminals.ps1'       | Should -Be 'OLD'
            script:Content 'docs/DEMO.md'        | Should -Be 'OLD'
        }

        It 'still leaves the user state alone' {
            script:Content 'cache/eva/background.gif' | Should -Be 'MY-CACHED-GIF'
            script:Content 'styles/felitest/tune.json' | Should -Be 'MY-TUNE'
            script:Content 'current-style.json'        | Should -Be 'MY-RECORD'
        }

        It 'says nothing was removed, so the caller cannot imply the opposite' {
            # `tstyles update` prints "Update failed: <this> / You can retry
            # manually", which on its own reads as "nothing happened". It is only
            # true because this message says it is.
            "$script:syncError" | Should -BeLike '*was removed or replaced*'
            "$script:syncError" | Should -Match ([regex]::Escape($script:installDir)) `
                -Because 'the one thing the user has to be told is WHICH tree is intact'
        }

        It 'leaves no staging directory behind' {
            @(Get-ChildItem -LiteralPath $TestDrive -Force -Directory |
                Where-Object { $_.Name -like '*.staging-*' }).Count | Should -Be 0
        }
    }

    Context 'the swap into place fails' {
        It 'says the install may now be incomplete, and does not claim it is untouched' {
            # There is no cross-platform way to make a rename fail for real -- a
            # Windows handle blocks the unlink under it, a Unix one does not --
            # so the fault goes in at the one call the swap makes. Should -Invoke
            # is what keeps this from being a mock that never fires: before the
            # fix nothing called Move-Item at all.
            Mock Move-Item { throw 'The process cannot access the file because it is being used by another process.' }
            $err = $null
            try   { Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:installDir }
            catch { $err = $_ }

            Should -Invoke Move-Item -Times 1
            "$err" | Should -BeLike '*may now be incomplete*'
            "$err" | Should -Not -BeLike '*was removed or replaced*' `
                -Because 'the reassurance the staging half prints would be a lie here'
        }
    }
}
