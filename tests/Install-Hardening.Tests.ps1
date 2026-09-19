#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Pester 5 tests for install.ps1 hardening. The installer is dot-sourced
# with $TStylesInstallNoRun = $true so its functions load WITHOUT running
# the download/install flow -- mirrors apply.ps1's $TStylesApplyNoRun seam.

Describe 'install.ps1 test seam' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath   # if the guard fails, this would attempt a network download
    }

    It 'loads functions without running the installer' {
        Get-Command Get-ShellInfo            -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Register-LoaderInProfile -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Resolve-ExecutionPolicy  -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Assert-ValidArchive' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        function script:New-ZipFrom {
            param([string[]]$Entries, [string]$ZipPath)
            $src = Join-Path $TestDrive ('src-' + [guid]::NewGuid().Guid.Substring(0,8))
            foreach ($e in $Entries) {
                $full = Join-Path $src $e
                New-Item -ItemType Directory -Force -Path (Split-Path $full -Parent) | Out-Null
                Set-Content -LiteralPath $full -Value 'x' -NoNewline
            }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $ZipPath)
        }
    }

    It 'passes for a valid archive containing the manifest' {
        $zip = Join-Path $TestDrive 'good.zip'
        New-ZipFrom -Entries @('TerminalStyles-main/TerminalStyles.psd1') -ZipPath $zip
        { Assert-ValidArchive -Path $zip } | Should -Not -Throw
    }

    It 'throws for a zero-byte file' {
        $empty = Join-Path $TestDrive 'empty.zip'
        New-Item -ItemType File -Path $empty | Out-Null
        { Assert-ValidArchive -Path $empty } | Should -Throw -ExpectedMessage '*empty*'
    }

    It 'throws for a non-ZIP file' {
        $bogus = Join-Path $TestDrive 'bogus.zip'
        Set-Content -LiteralPath $bogus -Value '<html>404: Not Found</html>'
        { Assert-ValidArchive -Path $bogus } | Should -Throw -ExpectedMessage '*not a valid ZIP*'
    }

    It 'throws for a ZIP without the module manifest' {
        $zip = Join-Path $TestDrive 'nomanifest.zip'
        New-ZipFrom -Entries @('TerminalStyles-main/README.md') -ZipPath $zip
        { Assert-ValidArchive -Path $zip } | Should -Throw -ExpectedMessage '*does not look like TerminalStyles*'
    }
}

Describe 'Assert-InstallLanded' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'passes when the manifest is present' {
        $dir = Join-Path $TestDrive 'landed'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'TerminalStyles.psd1') -Value '@{}'
        { Assert-InstallLanded -InstallDir $dir } | Should -Not -Throw
    }

    It 'throws when the manifest is missing (nested/broken install)' {
        $dir = Join-Path $TestDrive 'broken'
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'TerminalStyles-main') | Out-Null
        { Assert-InstallLanded -InstallDir $dir } | Should -Throw -ExpectedMessage '*did not complete*'
    }
}

Describe 'Write-TextFileAtomic' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        $script:enc = [System.Text.UTF8Encoding]::new($false)
    }

    It 'writes the exact content to a new file' {
        $p = Join-Path $TestDrive 'new.txt'
        Write-TextFileAtomic -Path $p -Content "hello`r`nworld"
        [System.IO.File]::ReadAllText($p, $script:enc) | Should -Be "hello`r`nworld"
    }

    It 'writes UTF-8 with no BOM' {
        $p = Join-Path $TestDrive 'nobom.txt'
        Write-TextFileAtomic -Path $p -Content 'abc'
        $bytes = [System.IO.File]::ReadAllBytes($p)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'overwrites an existing file' {
        $p = Join-Path $TestDrive 'over.txt'
        Set-Content -LiteralPath $p -Value 'old'
        Write-TextFileAtomic -Path $p -Content 'new'
        [System.IO.File]::ReadAllText($p, $script:enc) | Should -Be 'new'
    }

    It 'leaves no temp file behind' {
        $dir = Join-Path $TestDrive 'tmpcheck'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $p = Join-Path $dir 'f.txt'
        Write-TextFileAtomic -Path $p -Content 'data'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp-*' -Force).Count | Should -Be 0
    }

    Context 'the destination cannot be written at all' {
        # Existing coverage stopped at the success path. The failure path is
        # where the temp file was left behind: the catch printed "atomic write
        # unavailable on this volume", called WriteAllText, and THEN removed the
        # temp -- as a trailing statement, not in a finally. When the direct
        # write also fails (a read-only $PROFILE, a cloud-synced placeholder,
        # the exact state lib/update.ps1:412 names out loud) the exception
        # escaped past that line and `.<profile>.tmp-<guid>` stayed beside the
        # user's $PROFILE, with a fresh GUID per call so re-running the
        # installer piled them up. Measured with `chflags uchg` on a real
        # profile: 1 orphan after the first attempt, 2 after the second.
        # lib/wtsettings.ps1's Write-SettingsAtomic is the same shape and was
        # fixed for exactly this; this copy never was.
        #
        # A DIRECTORY at the destination forces both halves to fail on every
        # platform and both engines, with no privileges and no filesystem
        # flags: Test-Path says the path exists, File.Replace refuses it, and
        # File.WriteAllText refuses it too. The temp sibling is still created
        # first, because its parent is writable -- which is the whole point.
        BeforeEach {
            $script:leakDir = Join-Path $TestDrive ('leak-' + [guid]::NewGuid().Guid.Substring(0,8))
            New-Item -ItemType Directory -Force -Path $script:leakDir | Out-Null
            $script:leakTarget = Join-Path $script:leakDir 'Microsoft.PowerShell_profile.ps1'
            New-Item -ItemType Directory -Force -Path $script:leakTarget | Out-Null
        }

        It 'leaves no temp file beside an unwritable target' {
            try { Write-TextFileAtomic -Path $script:leakTarget -Content 'x' } catch { }
            try { Write-TextFileAtomic -Path $script:leakTarget -Content 'x' } catch { }
            # -Force, and PSIsContainer filtered out: the temp name starts with
            # a dot, so without -Force this counts nothing on Unix and passes
            # while measuring nothing.
            @(Get-ChildItem -LiteralPath $script:leakDir -Filter '*.tmp-*' -Force |
                Where-Object { -not $_.PSIsContainer }).Count |
                Should -Be 0 -Because 'two failed attempts must not leave two temp files in the user''s profile directory'
        }

        It 'blames the permissions it can see, not the volume it cannot' {
            # The message is a claim. "atomic write unavailable on this volume"
            # was printed BEFORE the write it describes, so it was printed on a
            # run where nothing was written at all -- and the next line then
            # died with a raw .NET "Access to the path ... is denied", which is
            # the diagnosis lib/update.ps1 turns into an instruction for the
            # very same file.
            $err = $null
            try { Write-TextFileAtomic -Path $script:leakTarget -Content 'x' } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty -Because 'an unwritable destination has to be reported'
            "$err" | Should -Match "permissions" `
                -Because 'the failure must carry the same guidance the module half prints'
            "$err" | Should -Not -Match 'atomic write unavailable' `
                -Because 'the volume is not what refused the write'
        }
    }

    Context 'the destination is a symlink into a dotfiles repo' {
        # File.Replace operates on the LINK: it swapped a $PROFILE symlinked
        # into stow / chezmoi / nix home-manager for a regular file, orphaning
        # the repo copy. Nothing is lost on either side, which is what made it
        # silent -- the repo simply stops governing the profile, and the next
        # `chezmoi apply` / `home-manager switch` / `stow -R` conflicts on an
        # unexpected regular file or overwrites it, taking the loader with it.
        # Every other writer of a user-owned file in this repo is a plain
        # WriteAllText and follows the link; this was the lone outlier.
        BeforeEach {
            $script:sl = Join-Path $TestDrive ('sl-' + [guid]::NewGuid().Guid.Substring(0,8))
            New-Item -ItemType Directory -Force -Path (Join-Path $script:sl 'dotfiles') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $script:sl 'home')     | Out-Null
            $script:slReal = Join-Path $script:sl 'dotfiles/powershell_profile.ps1'
            $script:slLink = Join-Path $script:sl 'home/Microsoft.PowerShell_profile.ps1'
            [System.IO.File]::WriteAllText($script:slReal,
                "# managed by my dotfiles repo`r`nSet-Alias ll Get-ChildItem`r`n",
                [System.Text.UTF8Encoding]::new($false))
            $script:slMade = $false
            try {
                New-Item -ItemType SymbolicLink -Path $script:slLink -Target $script:slReal -ErrorAction Stop | Out-Null
                $script:slMade = $true
            } catch { $script:slMade = $false }
        }

        It 'writes THROUGH a symlinked $PROFILE instead of replacing the link' {
            if (-not $script:slMade) {
                # Windows without Developer Mode or an elevated account cannot
                # create one. Skipped at RUN time, not with -Skip:, which is
                # evaluated at discovery and would never see this flag.
                Set-ItResult -Skipped -Because 'this platform or account cannot create symlinks'
                return
            }
            Write-TextFileAtomic -Path $script:slLink -Content 'LOADER-BLOCK'

            # -Force on Get-Item is load-bearing: without it a dotfile-shaped
            # path answers nothing on Unix and both sides compare $null.
            (Get-Item -LiteralPath $script:slLink -Force).LinkType |
                Should -Be 'SymbolicLink' -Because 'the link must survive the write'
            [System.IO.File]::ReadAllText($script:slReal, $script:enc) |
                Should -Be 'LOADER-BLOCK' -Because 'the dotfiles copy is what the link points at'
        }

        It 'still swaps atomically when the destination is a real file' {
            # The guard must not have turned the atomic replace off everywhere.
            # A hard link observes the difference: an atomic Replace swaps in a
            # brand-new file, so the original -- still reachable through the
            # second name -- keeps its OLD bytes. (PowerShell reports LinkType
            # 'HardLink' here, which is why the symlink test above is spelled
            # -eq 'SymbolicLink' and not "LinkType says anything".)
            $f    = Join-Path $script:sl 'plain.txt'
            $hard = Join-Path $script:sl 'plain.hardlink.txt'
            [System.IO.File]::WriteAllText($f, 'OLD', $script:enc)
            $made = $true
            try { New-Item -ItemType HardLink -Path $hard -Target $f -ErrorAction Stop | Out-Null }
            catch { $made = $false }
            if (-not $made) {
                Set-ItResult -Skipped -Because 'this platform or account cannot create hard links'
                return
            }
            Write-TextFileAtomic -Path $f -Content 'NEW'
            [System.IO.File]::ReadAllText($f, $script:enc)    | Should -Be 'NEW'
            [System.IO.File]::ReadAllText($hard, $script:enc) | Should -Be 'OLD'
        }
    }
}

Describe 'Register-LoaderInProfile round-trips the user''s own bytes' {
    # The $PROFILE is the USER's file and predates us, and this function reads
    # the whole of it and writes the whole of it back. Read as UTF-8, a byte
    # that is not valid UTF-8 -- a latin-1 comment, a stray byte from an old
    # editor, anything at all in a Windows PowerShell 5.1 profile saved in the
    # ANSI codepage, which is its default -- decodes to U+FFFD and is written
    # back as ef bf bd. terminals.ps1's rc half (CHANGELOG 554) and
    # lib/update.ps1's $PROFILE half (CHANGELOG 292, this exact `# café`
    # fixture) were both moved to Get-RcFileEncoding for it. install.ps1's copy,
    # the third and the only one that runs on `iwr | iex`, never was.
    #
    # Measured on the shipped function before the fix:
    #   BEFORE 23 20 63 61 66 e9 0d 0a ...
    #   AFTER  23 20 63 61 66 ef bf bd 0d ...
    # on the first install AND on the re-install -- which is the path `tstyles
    # update` takes on every bootstrap install, and the one that keeps no copy.
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        $script:begin = '# ===== TerminalStyles BEGIN ====='
        $script:end   = '# ===== TerminalStyles END ====='
        $script:body  = "$script:begin`r`nImport-Module 'X' -DisableNameChecking`r`n$script:end"
    }
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ('enc-' + [guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:fixture 'styles') | Out-Null
        $script:profileDir = Join-Path $script:fixture 'profile'
        New-Item -ItemType Directory -Force -Path $script:profileDir | Out-Null
        $script:profilePath = Join-Path $script:profileDir 'Microsoft.PowerShell_profile.ps1'
        # "# caf" + 0xE9 + CRLF -- a latin-1 'é', which is not valid UTF-8.
        $script:cafe = [byte[]]@(0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A)
    }
    function script:RegisterFixture {
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end `
            -LoaderBody $script:body 6>&1 | Out-Null
    }
    function script:ProfileHex {
        ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($script:profilePath)) -replace '-', '')
    }

    It 'keeps a byte that is not valid UTF-8 (first install)' {
        [System.IO.File]::WriteAllBytes($script:profilePath,
            $script:cafe + [System.Text.Encoding]::ASCII.GetBytes("Set-Alias ll Get-ChildItem`r`n"))
        RegisterFixture
        [System.IO.File]::ReadAllBytes($script:profilePath) | Should -Contain 0xE9 `
            -Because 'the user''s own byte must survive a tool that was only asked to append a loader'
        ProfileHex | Should -Not -Match 'EFBFBD' `
            -Because 'U+FFFD in their file means the original byte is gone for good'
    }

    It 'keeps it on a RE-install too, where no backup is taken' {
        # The sharp one. `tstyles update` on a bootstrap install re-runs this
        # whole script, and the first-touch rule skips the backup for a file
        # that already carries our block -- so on this path the corruption is
        # unrecoverable. The count is asserted first, so the test proves there
        # is no copy to fall back on rather than assuming it.
        [System.IO.File]::WriteAllBytes($script:profilePath,
            $script:cafe + [System.Text.Encoding]::ASCII.GetBytes("`r`n$script:body`r`n"))
        RegisterFixture
        @(Get-ChildItem -LiteralPath $script:profileDir -Filter '*.bak-*' -Force).Count |
            Should -Be 0 -Because 'a re-register only swaps our own block, so no backup is taken'
        [System.IO.File]::ReadAllBytes($script:profilePath) | Should -Contain 0xE9
        ProfileHex | Should -Not -Match 'EFBFBD'
    }

    It 'still recognises a bundled style profile it has to migrate' {
        # The other side of the same change: the migration compares the user's
        # $PROFILE against every shipped profile.ps1, and reading the two with
        # DIFFERENT encodings would make a style whose banner is not pure ASCII
        # -- which is most of the sixteen -- never match itself, silently
        # switching the migration off.
        $styleDir = Join-Path $script:fixture 'styles/eva'
        New-Item -ItemType Directory -Force -Path $styleDir | Out-Null
        $styleBytes = [System.Text.Encoding]::UTF8.GetBytes(
            "# eva`r`nWrite-Host '" + [char]0x2500 + [char]0x2500 + " NERV " + [char]0x2500 + [char]0x2500 + "'`r`n")
        [System.IO.File]::WriteAllBytes((Join-Path $styleDir 'profile.ps1'), $styleBytes)
        [System.IO.File]::WriteAllBytes($script:profilePath, $styleBytes)

        RegisterFixture

        Test-Path -LiteralPath (Join-Path $script:fixture 'current-style.ps1') |
            Should -BeTrue -Because 'a $PROFILE that IS a bundled style must still be migrated into TerminalStyles'
    }
}

Describe 'Register-LoaderInProfile backup rule' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        $script:begin = '# ===== TerminalStyles BEGIN ====='
        $script:end   = '# ===== TerminalStyles END ====='
        $script:body  = "$script:begin`r`nImport-Module `"`$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1`" -DisableNameChecking`r`n$script:end"
    }
    BeforeEach {
        # Fresh per-test install fixture with an empty styles dir (no migration match)
        $script:fixture = Join-Path $TestDrive ('inst-' + [guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:fixture 'styles') | Out-Null
        $script:profileDir = Join-Path $script:fixture 'profile'
        New-Item -ItemType Directory -Force -Path $script:profileDir | Out-Null
        $script:profilePath = Join-Path $script:profileDir 'Microsoft.PowerShell_profile.ps1'
    }
    function script:CountBaks {
        @(Get-ChildItem -LiteralPath $script:profileDir -Filter '*.ps1.bak-*' -Force).Count
    }

    It 'creates no backup for a fresh (nonexistent) profile' {
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        Test-Path -LiteralPath $script:profilePath | Should -BeTrue
        CountBaks | Should -Be 0
    }

    It 'backs up once when touching a profile with pre-existing user content' {
        [System.IO.File]::WriteAllText($script:profilePath, "# my custom prompt`r`nSet-Alias ll Get-ChildItem", [System.Text.UTF8Encoding]::new($false))
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        CountBaks | Should -Be 1
        $bak = Get-ChildItem -LiteralPath $script:profileDir -Filter '*.ps1.bak-*' -Force | Select-Object -First 1
        (Get-Content -LiteralPath $bak.FullName -Raw) | Should -Match 'my custom prompt'
    }

    It 'makes no new backup when a loader block is already present' {
        [System.IO.File]::WriteAllText($script:profilePath, "# existing`r`n`r`n$script:body`r`n", [System.Text.UTF8Encoding]::new($false))
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        CountBaks | Should -Be 0
    }

    # THE ENCODING HALF. Register-LoaderInProfile reads the WHOLE $PROFILE and
    # Write-TextFileAtomic writes the WHOLE file back, so the encoding it picks
    # decides whether the user's own bytes survive being appended to. Under
    # UTF-8 -- what both halves used -- any byte that is not valid UTF-8 decoded
    # to U+FFFD and was written back as EF BF BD. lib/update.ps1 was fixed for
    # exactly this in 0.8.24 (Get-RcFileEncoding, ISO-8859-1, which round-trips
    # every byte 0-255); the installer was the last writer in the repo that
    # still corrupted.
    #
    # Bytes, through [System.IO.File]::ReadAllBytes -- not Get-Content and not
    # Get-Item, which without -Force answers nothing at all for a dotfile on
    # Unix and lets both sides of an assertion pass while comparing nothing.
    #
    # 0xE9 is 'e' with an acute accent in latin-1: one byte, and not valid UTF-8
    # on its own.
    It 'preserves a byte that is not valid UTF-8 on first touch' {
        [System.IO.File]::WriteAllBytes($script:profilePath,
            [byte[]]@(0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A))   # "# cafe<0xE9>"
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body

        $bytes = [System.IO.File]::ReadAllBytes($script:profilePath)
        $bytes | Should -Contain 0xE9 -Because "the installer was asked to append three lines, not to rewrite the user's text"
        ($bytes -join ',') | Should -Not -Match '239,191,189' -Because 'EF BF BD is the replacement character being written back'
        # Not vacuous: the loader really did go in, so the write under test ran.
        [System.IO.File]::ReadAllText($script:profilePath, (Get-ProfileFileEncoding)) |
            Should -Match ([regex]::Escape($script:begin))
    }

    It 'preserves it on a RE-register, where no backup is taken' {
        # The half the severity turns on. The first-touch backup is deliberately
        # skipped once our BEGIN marker is in the file -- and that is every
        # `iwr -useb ... | iex` re-run, which install.ps1 documents as the
        # upgrade path and which registers unconditionally. So on this path the
        # round-trip ran with no .bak written and nothing printed about it:
        # nothing recovered, nothing announced.
        $head = [System.Text.Encoding]::GetEncoding(28591).GetBytes("$script:body`r`n# caf")
        [System.IO.File]::WriteAllBytes($script:profilePath, ($head + [byte[]]@(0xE9, 0x0D, 0x0A)))

        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body

        CountBaks | Should -Be 0 -Because 'this is the path that takes no backup, which is why the bytes have to survive it'
        $bytes = [System.IO.File]::ReadAllBytes($script:profilePath)
        $bytes | Should -Contain 0xE9
        ($bytes -join ',') | Should -Not -Match '239,191,189'
    }

    It 'replaces only its own block when a stray BEGIN sits above it' {
        # install.ps1 keeps its own copy of the marker pattern -- it is fetched
        # and piped to iex before the module exists -- and had the same hole the
        # module half did: `BEGIN .*? END` under (?s) starts at the FIRST BEGIN
        # in the file and runs to the first END after it, so a $PROFILE carrying
        # a stray or duplicated marker lost every line in between. And this is
        # the branch that takes no backup, since the file already carries a
        # BEGIN -- the test directly above pins that.
        $stray = "$script:begin`r`nfunction prompt { 'keep-me> ' }`r`n"
        [System.IO.File]::WriteAllText($script:profilePath, "# existing`r`n$stray$script:body`r`n", [System.Text.UTF8Encoding]::new($false))

        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body

        $after = [System.IO.File]::ReadAllText($script:profilePath, [System.Text.UTF8Encoding]::new($false))
        $after | Should -Match 'keep-me'
        $after | Should -Match '# existing'
        # One loader written, and the stray marker left where the user put it.
        ([regex]::Matches($after, [regex]::Escape($script:end))).Count   | Should -Be 1
        ([regex]::Matches($after, [regex]::Escape($script:begin))).Count | Should -Be 2
        CountBaks | Should -Be 0
    }
}

Describe 'Test-PolicyResolved' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'returns true for policies that allow scripts' {
        foreach ($p in 'RemoteSigned','Bypass','Unrestricted') {
            Test-PolicyResolved -Policy $p | Should -BeTrue
        }
    }

    It 'returns false for blocking or empty policies' {
        foreach ($p in 'Restricted','AllSigned','') {
            Test-PolicyResolved -Policy $p | Should -BeFalse
        }
        Test-PolicyResolved -Policy $null | Should -BeFalse
    }

    It "rejects 'Undefined' -- it is the absence of an answer, not permission" {
        # An EFFECTIVE Get-ExecutionPolicy never returns it (an all-Undefined
        # machine resolves to the platform default), so this is the value of a
        # single SCOPE that was never written. It used to return $true, and the
        # post-check in Resolve-ExecutionPolicy was handing it the CurrentUser
        # scope: a write that did not land was announced as
        # "Done. CurrentUser policy is now Undefined" in green.
        Test-PolicyResolved -Policy 'Undefined'    | Should -BeFalse
        Test-PolicyResolved -Policy '  undefined ' | Should -BeFalse
    }

    It 'tolerates surrounding whitespace' {
        Test-PolicyResolved -Policy "  RemoteSigned `r`n" | Should -BeTrue
        Test-PolicyResolved -Policy "  Restricted  "       | Should -BeFalse
    }
}

Describe 'install.ps1 hardens its download' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $script:installSrc = [System.IO.File]::ReadAllText(
            $script:installPath, [System.Text.UTF8Encoding]::new($false))
        $script:installAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:installPath, [ref]$null, [ref]$null)

        # The two tests below used to ask the whole FILE for `} finally {` and
        # `} catch {` with a (?s) match across it. install.ps1 has an unrelated
        # finally at line 363 and an unrelated catch at 576, either of which
        # satisfied the pattern on its own -- so deleting the try/catch the test
        # was named for left it green. Ask the AST which try statement actually
        # contains the code, instead of asking the text whether the keyword
        # appears anywhere after it.
        function script:Get-EnclosingTry {
            param([Parameter(Mandatory)][string]$Needle)
            $tries = @($script:installAst.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.TryStatementAst] }, $true))
            # Innermost wins: a nested try is the one that actually guards the line.
            @($tries | Where-Object { $_.Body.Extent.Text -match $Needle } |
                Sort-Object { $_.Extent.Text.Length } | Select-Object -First 1)
        }
    }

    It 'raises the TLS floor to 1.2 before downloading' {
        # On .NET Framework -- i.e. stock Windows PowerShell 5.1, which is
        # exactly who runs the bootstrap one-liner -- the default
        # SecurityProtocol can still omit TLS 1.2, and GitHub refuses anything
        # older. The failure reads as "the underlying connection was closed",
        # which looks like a network fault rather than a protocol one.
        $script:installSrc | Should -Match 'SecurityProtocol'
        $script:installSrc | Should -Match 'SecurityProtocolType\]::Tls12'
        $script:installSrc.IndexOf('Tls12') |
            Should -BeLessThan $script:installSrc.IndexOf('-OutFile $tempZip') `
            -Because 'raising the floor after the download would be pointless'
    }

    It 'does not lower the TLS floor, only raise it' {
        # -bor, never assignment: clobbering the value would disable protocols
        # the user's environment had deliberately enabled.
        $script:installSrc | Should -Match 'SecurityProtocol -bor'
    }

    It 'bounds the main download with a timeout' {
        # The far less important update-check call already had one. Without it a
        # stalled connection hangs on "Downloading" indefinitely.
        $script:installSrc | Should -Match '-OutFile \$tempZip -UseBasicParsing -TimeoutSec \d+'
    }

    It 'restores the preferences it changes' {
        # `iwr | iex` runs this body in the CALLER's scope, so a preference set
        # here outlives the install. Leaving $ErrorActionPreference on 'Stop'
        # turns every later non-terminating error in that session terminating.
        $script:installSrc | Should -Match '\$tstylesPrevEAP\s*=\s*\$ErrorActionPreference'
        $script:installSrc | Should -Match '\$ErrorActionPreference\s*=\s*\$tstylesPrevEAP'
        $script:installSrc | Should -Match '\$ProgressPreference\s*=\s*\$tstylesPrevProgress'
    }

    It 'restores them on the failure paths too' {
        # A finally, not a few lines at the end: the installer throws on plenty
        # of paths, and every one of them leaves the user's shell behind -- and
        # under `iwr | iex` that shell is the user's own, for the rest of the
        # session.
        $restoring = @($script:installAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.TryStatementAst] -and
            $n.Finally -and
            $n.Finally.Extent.Text -match '\$ErrorActionPreference\s*=\s*\$tstylesPrevEAP' }, $true))
        @($restoring).Count | Should -BeGreaterThan 0 `
            -Because 'the preference restore must sit in a finally, not merely somewhere after one'
        $restoring[0].Finally.Extent.Text |
            Should -Match '\$ProgressPreference\s*=\s*\$tstylesPrevProgress' `
            -Because 'both preferences are the caller''s, so both restore on the same path'
    }

    It 'runs chcp only on Windows' {
        # chcp is a Windows console command. `$null = & chcp ... 2>&1` does NOT
        # swallow its absence: a missing native command is a PowerShell error,
        # not stderr output, so on macOS and Linux the documented `iwr | iex`
        # one-liner opened with a red "The term 'chcp' is not recognized" block.
        # The install worked; it looked like it had failed before it started.
        $chcp = @($script:installAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'chcp' }, $true))
        @($chcp).Count | Should -Be 1

        $guards = @($script:installAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -match "Get-TStylesPlatform\)\s*-eq\s*'Windows'" -and
            $n.Extent.StartOffset -lt $chcp[0].Extent.StartOffset -and
            $n.Extent.EndOffset -gt $chcp[0].Extent.EndOffset }, $true))
        @($guards).Count | Should -BeGreaterThan 0 `
            -Because 'the chcp call must sit inside a Windows-only branch'
    }

    It 'still installs when the TLS floor cannot be raised' {
        # pwsh 7 on Unix negotiates through the OS and may not expose
        # ServicePointManager at all. Not being able to raise the floor is not a
        # reason to refuse to install.
        $guard = script:Get-EnclosingTry -Needle 'SecurityProtocol\s*-bor'
        @($guard).Count | Should -Be 1 `
            -Because 'the SecurityProtocol write must sit inside a try, not merely before some later catch'
        $guard[0].CatchClauses.Count | Should -BeGreaterThan 0 `
            -Because 'a host without ServicePointManager must still reach the install'
    }
}

Describe 'the install panel names the engines it actually registered' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'identifies the running engine without inverting the edition' {
        # The panel used to name "the other" engine as
        #   if ($PSVersionTable.PSEdition -eq 'Core') { 'Windows PowerShell 5.1' } else { 'PowerShell 7' }
        # which assumed the only two engines are pwsh 7 and Windows PowerShell
        # 5.1. That held while the probe looked for pwsh.exe / powershell.exe. It
        # stopped holding when the probe became platform-aware: on macOS the pair
        # is pwsh and pwsh-preview -- both Core -- so "more than one engine" became
        # true off Windows and Mac users were told the install was "Also wired up
        # for Windows PowerShell 5.1".
        $label = Get-CurrentEngineLabel
        $label | Should -BeIn @(Get-PowerShellEngineCandidate | ForEach-Object { $_.Label }) `
            -Because 'the running engine must be one of the ones this script probes for'

        # For EVERY platform, not just this one. The first version of this test
        # asked only about the default platform, which on macOS/Linux does list
        # 'PowerShell 7 (preview)' -- so it passed while the answer was wrong on
        # Windows, where the probe looks for pwsh.exe / powershell.exe and a
        # 7-preview build installs AS pwsh.exe. Returning a label absent from the
        # platform's list makes Write-InstallPanel's subtraction a no-op, and the
        # panel then tells the user to open a new tab for the engine they are
        # already in -- the same defect this function exists to fix, on the
        # platform this suite cannot run on.
        foreach ($platform in 'Windows', 'MacOS', 'Linux') {
            $expected = @((Get-PowerShellEngineCandidate -Platform $platform).Label)
            (Get-CurrentEngineLabel -Platform $platform) | Should -BeIn $expected `
                -Because "on $platform the label must be one the installer actually registers"
        }

        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $label | Should -Be 'Windows PowerShell 5.1'
        } elseif ($PSVersionTable.PSVersion.PSObject.Properties.Match('PreReleaseLabel').Count -gt 0 -and
                  $PSVersionTable.PSVersion.PreReleaseLabel) {
            $label | Should -Be 'PowerShell 7 (preview)'
        } else {
            $label | Should -Be 'PowerShell 7'
        }
    }

    It 'never names a Windows-only engine off Windows' {
        if ((Get-TStylesPlatform) -eq 'Windows') {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is a real answer here'
            return
        }
        Get-CurrentEngineLabel | Should -Not -Match 'Windows PowerShell' `
            -Because 'Windows PowerShell does not exist on macOS or Linux'
        @(Get-PowerShellEngineCandidate | ForEach-Object { $_.Label }) |
            Should -Not -Contain 'Windows PowerShell 5.1'
    }

    It 'the panel subtracts the current engine from what it announces' {
        # AST, not source text: the comment explaining this fix names PSEdition
        # a few lines above the code, so a -Match over the body finds the
        # explanation and fails for the wrong reason. Comments are not in the AST.
        $ast = (Get-Command Write-InstallPanel).ScriptBlock.Ast

        $asks = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Get-CurrentEngineLabel' }, $true))
        @($asks).Count | Should -BeGreaterThan 0 `
            -Because 'the other engines are the registered ones minus the current one'

        $editionReads = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
            "$($n.Member.Extent.Text)" -eq 'PSEdition' }, $true))
        @($editionReads).Count | Should -Be 0 `
            -Because 'inverting the edition is what named Windows PowerShell 5.1 on a Mac'
    }

    It 'says nothing about a row that already names the engine the user is in' {
        # The trap a de-duplicated list walks straight into. Once a row can name
        # more than one engine -- "PowerShell 7 / PowerShell 7 (preview)", the
        # two names for ONE $PROFILE on a Mac carrying the preview build --
        # `$_ -ne (Get-CurrentEngineLabel)` matches it, and the panel goes back
        # to telling the user to open a new tab for the engine they are already
        # sitting in. That is the 0.8.21 defect arriving by a third route, so the
        # subtraction has to be membership, not string equality.
        #
        # Positional, filling the same two positions the installer fills, so this
        # measures what the panel DOES with the list rather than failing to bind.
        $current = Get-CurrentEngineLabel
        $rows = @(
            [pscustomobject]@{ ProfilePath = '/x/shared-profile.ps1'
                               Label  = "$current / Some Other Engine"
                               Labels = @($current, 'Some Other Engine') }
        )
        $out = Write-InstallPanel @('sober') $rows 6>&1 | Out-String

        $out | Should -Not -Match 'Also wired up' `
            -Because 'that one file is the one the caller is already loading out of'
        $out | Should -Match 'themes installed' -Because 'the panel itself must still print'
    }

    It 'still names a row whose $PROFILE really is a different file' {
        # The other direction: the subtraction must not swallow a genuine second
        # profile (Windows' two engines keep separate ones).
        $current = Get-CurrentEngineLabel
        $rows = @(
            [pscustomobject]@{ ProfilePath = '/x/shared-profile.ps1'
                               Label  = "$current / Some Other Engine"
                               Labels = @($current, 'Some Other Engine') }
            [pscustomobject]@{ ProfilePath = '/x/third-profile.ps1'
                               Label  = 'A Third Engine'; Labels = @('A Third Engine') }
        )
        $out = Write-InstallPanel @('sober') $rows 6>&1 | Out-String

        $out | Should -Match 'Also wired up for A Third Engine'
        $out | Should -Not -Match 'Also wired up for[^\r\n]*Some Other Engine' `
            -Because 'the user is already in the engine that shares that file'
    }
}

Describe 'the installer registers one loader per $PROFILE, not one per engine' {
    # install.ps1 probes for two engines. Off Windows they are `pwsh` and
    # `pwsh-preview`, and on a machine carrying the 7-preview build both report
    # the same $PROFILE -- so the loop wrote that one file twice, printed
    # "Registered loader:" twice, and handed the panel two labels for one file,
    # which is what made its "more than one engine" branch true and told the user
    # the install was "Also wired up for PowerShell 7" for the binary they were
    # running in.
    #
    # The module half of this rule lives in Resolve-PowerShellProfileTarget;
    # install.ps1 is fetched and piped to iex before the module exists, so the
    # copy is unavoidable and the parity test lives in
    # tests/Get-PowerShellEngineCandidate.Tests.ps1 with the other one.
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }
    BeforeEach {
        $script:d = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path $script:d | Out-Null

        # A stand-in engine, never a real one -- the same device
        # Resolve-ExecutionPolicy's tests use. Get-Command hands back an
        # ExternalScriptInfo for a .ps1 path, and Get-ShellInfo's single
        # `& $cmd.Source -NoProfile -NonInteractive -Command '<one string>'`
        # binds to its param block exactly as a real engine's command line does.
        # Named apart from the Resolve-ExecutionPolicy stub further down: both
        # would otherwise live in the file's shared `script:` scope, and which
        # one a test got would depend on Describe order.
        function script:New-ProfileStubEngine {
            param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$ProfilePath)
            $path = Join-Path $script:d "$Name.ps1"
            $src = @'
param([switch]$NoProfile, [switch]$NonInteractive, [string]$Command)
Write-Output ('PROFILE=' + '__P__')
Write-Output 'POLICY=RemoteSigned'
'@.Replace('__P__', $ProfilePath)
            [System.IO.File]::WriteAllText($path, $src, [System.Text.UTF8Encoding]::new($false))
            # Every assertion below reads an empty plan if Get-Command cannot
            # resolve the stub, which would pass some of them vacuously. Fail
            # here, where the reason is legible.
            if (-not (Get-Command -Name $path -ErrorAction SilentlyContinue)) {
                throw "Stub engine '$path' is not resolvable by Get-Command on this platform."
            }
            $path
        }
    }

    It 'merges two engines that answer with the same file' {
        $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
        $plan = @(Get-EngineProfilePlan -Engine @(
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'a' -ProfilePath $shared); Label = 'PowerShell 7' }
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'b' -ProfilePath $shared); Label = 'PowerShell 7 (preview)' }
        ))

        $plan.Count | Should -Be 1 -Because 'it is one file'
        $plan[0].ProfilePath | Should -Be $shared
        @($plan[0].Labels) | Should -Be @('PowerShell 7', 'PowerShell 7 (preview)')
        $plan[0].Label | Should -Be 'PowerShell 7 / PowerShell 7 (preview)'
        @($plan[0].Engines).Count | Should -Be 2 `
            -Because 'the execution policy is per engine even where the profile is shared'
    }

    It 'keeps two engines with separate profiles apart' {
        $pa = Join-Path $script:d 'a-profile.ps1'
        $pb = Join-Path $script:d 'b-profile.ps1'
        $plan = @(Get-EngineProfilePlan -Engine @(
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'a' -ProfilePath $pa); Label = 'PowerShell 7' }
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'b' -ProfilePath $pb); Label = 'Windows PowerShell 5.1' }
        ))

        $plan.Count | Should -Be 2
        @($plan | ForEach-Object { $_.ProfilePath }) | Should -Be @($pa, $pb)
    }

    It 'skips an engine that is not on PATH without dropping the others' {
        $pa = Join-Path $script:d 'a-profile.ps1'
        $plan = @(Get-EngineProfilePlan -Engine @(
            [pscustomobject]@{ Exe = (Join-Path $script:d 'not-installed.ps1'); Label = 'PowerShell 7 (preview)' }
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'a' -ProfilePath $pa); Label = 'PowerShell 7' }
        ) 6>$null)

        $plan.Count | Should -Be 1
        $plan[0].Label | Should -Be 'PowerShell 7'
    }

    It 'the panel says nothing extra for a plan that resolves to one shared file' {
        # The two halves together, which is where the user actually meets this:
        # the plan the loop builds, fed to the panel that describes it.
        $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
        $current = Get-CurrentEngineLabel
        $plan = @(Get-EngineProfilePlan -Engine @(
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'a' -ProfilePath $shared); Label = $current }
            [pscustomobject]@{ Exe = (script:New-ProfileStubEngine -Name 'b' -ProfilePath $shared); Label = 'Some Other Engine' }
        ))

        $out = Write-InstallPanel -ThemeNames @('sober') -RegisteredProfile $plan 6>&1 | Out-String
        $out | Should -Not -Match 'Also wired up' `
            -Because 'both engines load out of the file the caller is already using'
    }
}

Describe 'Resolve-ExecutionPolicy verifies the effective policy, not the scope it wrote' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath

        # A stand-in engine, never a real one. The only thing
        # Resolve-ExecutionPolicy asks of an engine is
        #   & $cmd.Source -NoProfile -NonInteractive -Command '<one string>'
        # plus the last non-empty line of its stdout -- and a .ps1 path answers
        # that exactly as powershell.exe does: Get-Command hands back an
        # ExternalScriptInfo whose .Source is the path, and the three arguments
        # bind to a param block. Nothing in this suite may launch the real
        # thing: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`
        # would rewrite the execution policy of the machine running the tests.
        #
        # The stub answers the two questions DIFFERENTLY, which is the whole
        # point of the fix. On a GPO-locked machine the CurrentUser scope reads
        # back the value just written to it while the EFFECTIVE policy -- the
        # one that decides whether the loader runs -- is unchanged.
        function script:New-StubEngine {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Effective,   # answer to `Get-ExecutionPolicy`
                [Parameter(Mandatory)][string]$CurrentUser  # answer to `... -Scope CurrentUser`
            )
            $dir = Join-Path $TestDrive ('engine-' + $Name)
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $log  = Join-Path $dir 'asked.log'
            $path = Join-Path $dir 'engine.ps1'
            # An unrecognised question is answered with a value no branch treats
            # as success, so changing the shape of the command string without
            # updating this stub fails the tests instead of quietly passing them.
            $src = @'
param([switch]$NoProfile, [switch]$NonInteractive, [string]$Command)
Add-Content -LiteralPath '{LOG}' -Value "$Command"
$asked = @("$Command" -split ';')[-1].Trim()
if     ($asked -match '^Get-ExecutionPolicy$')                       { '{EFFECTIVE}' }
elseif ($asked -match '^Get-ExecutionPolicy\s+-Scope\s+CurrentUser$') { '{CURRENTUSER}' }
else                                                                  { 'Restricted' }
'@
            $src = $src.Replace('{LOG}', $log).Replace('{EFFECTIVE}', $Effective).Replace('{CURRENTUSER}', $CurrentUser)
            [System.IO.File]::WriteAllText($path, $src, [System.Text.UTF8Encoding]::new($false))
            # Resolve-ExecutionPolicy returns at its first line if Get-Command
            # cannot resolve -Exe, and every assertion below would then be
            # reading an empty string. Fail here, where the reason is legible.
            if (-not (Get-Command -Name $path -ErrorAction SilentlyContinue)) {
                throw "Stub engine '$path' is not resolvable by Get-Command on this platform."
            }
            [pscustomobject]@{ Path = $path; Log = $log }
        }

        # Read with [System.IO.File] and project with @(): an empty log must
        # count 0, and a missing one must not throw before the assertion runs.
        function script:Get-EngineCall {
            param([Parameter(Mandatory)]$Stub)
            if (-not [System.IO.File]::Exists($Stub.Log)) { return @() }
            @([System.IO.File]::ReadAllLines($Stub.Log) | Where-Object { "$_".Trim() })
        }
    }

    BeforeEach {
        # There is a human at the console and they answered yes. Without both,
        # Resolve-ExecutionPolicy returns before it launches anything -- which is
        # why every case below also counts the calls the stub actually received.
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
    }

    It 'does not claim success when a Group Policy overrides the CurrentUser write' {
        # `Set-ExecutionPolicy -Scope CurrentUser` SUCCEEDS under a
        # MachinePolicy/UserPolicy GPO -- it writes HKCU and only warns -- so the
        # scope reads back RemoteSigned while the effective policy stays
        # Restricted and the loader still cannot run. Asking the scope it just
        # wrote is structurally incapable of detecting that, and the installer
        # printed "Done. CurrentUser policy is now RemoteSigned" in green on
        # exactly the machines the prompt exists for.
        $stub = script:New-StubEngine -Name 'gpo' -Effective 'Restricted' -CurrentUser 'RemoteSigned'

        $out = (Resolve-ExecutionPolicy -Exe $stub.Path -Label 'Windows PowerShell 5.1' `
                    -EffectivePolicy 'Restricted' 6>&1 | Out-String)

        @(script:Get-EngineCall $stub).Count | Should -Be 1 `
            -Because 'the engine must actually have been launched, or this test measures nothing'
        $out | Should -Match 'Script execution is disabled' `
            -Because 'the prompt path must have been reached'
        $out | Should -Not -Match 'Done' `
            -Because 'the loader still cannot run on this machine'
        # Only the scope-free question can produce this value, whatever the
        # wording around it.
        $out | Should -Match "still 'Restricted'"
        $out | Should -Match 'overriding CurrentUser'
    }

    It 'does not claim success when the CurrentUser write never lands' {
        # The other half: when the HKCU write does not stick, the scoped
        # read-back is the string 'Undefined' -- and the success line then read
        # "Done. CurrentUser policy is now Undefined", a success claim naming the
        # word for "nothing is set here", with no error output anywhere.
        $stub = script:New-StubEngine -Name 'nowrite' -Effective 'Restricted' -CurrentUser 'Undefined'

        $out = (Resolve-ExecutionPolicy -Exe $stub.Path -Label 'Windows PowerShell 5.1' `
                    -EffectivePolicy 'Restricted' 6>&1 | Out-String)

        @(script:Get-EngineCall $stub).Count | Should -Be 1 `
            -Because 'the engine must actually have been launched, or this test measures nothing'
        $out | Should -Not -Match 'Done'
        $out | Should -Not -Match 'Undefined' `
            -Because 'Undefined is never an answer worth printing as a result'
        $out | Should -Match "still 'Restricted'"
    }

    It 'does claim success when the effective policy really changed' {
        # The complement, so a fix that simply always reports failure fails here.
        $stub = script:New-StubEngine -Name 'ok' -Effective 'RemoteSigned' -CurrentUser 'RemoteSigned'

        $out = (Resolve-ExecutionPolicy -Exe $stub.Path -Label 'PowerShell 7' `
                    -EffectivePolicy 'Restricted' 6>&1 | Out-String)

        @(script:Get-EngineCall $stub).Count | Should -Be 1
        $out | Should -Match 'Done'
        $out | Should -Match 'RemoteSigned' `
            -Because 'the value printed is the one the engine reported'
        $out | Should -Not -Match 'still'
    }
}

Describe 'the installer banner' {
    # Every user-facing message is a claim, and this one is three lines into a
    # first run: "tstyles  --  Windows Terminal themes for pwsh". The bootstrap
    # installer is the path README offers to macOS and Linux users, where there
    # is no Windows Terminal at all -- and the module styles Terminal.app,
    # iTerm2, kitty, WezTerm, Ghostty, Alacritty and VS Code on Windows too.
    # `tstyles help` has said "themed styles for your terminal" since 0.8.21,
    # with a comment above it recording exactly this reasoning; the banner was
    # never revisited.
    #
    # Behavioural, not a source-text match: the banner is captured and read.
    BeforeAll {
        $script:repoRoot    = Split-Path $PSScriptRoot -Parent
        $script:installPath = Join-Path $script:repoRoot 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        Import-Module (Join-Path $script:repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null

        $script:banner = (Write-InstallBanner 6>&1 | Out-String)
    }

    It 'prints a banner at all' {
        # A capture that came back empty would make every assertion below pass
        # while measuring nothing.
        #
        # Not matched on the literal 'tstyles' any more: the wordmark DRAWS the
        # name in slab lettering, so the word itself does not appear in the
        # output. What still has to be true is that something substantial was
        # printed -- several lines of it -- and the tagline check below is what
        # pins the wording.
        $script:banner | Should -Not -BeNullOrEmpty
        @($script:banner -split "`n" | Where-Object { $_.Trim() }).Count |
            Should -BeGreaterOrEqual 5 -Because 'a wordmark plus a tagline is more than a line or two'
    }

    It 'fits the 80-column floor the rest of the project assumes' {
        # Art that wraps is worse than no art: the first thing a new user sees
        # would arrive broken across lines.
        foreach ($line in ($script:banner -split "`n")) {
            $line.TrimEnd().Length | Should -BeLessOrEqual 78 -Because "'$($line.TrimEnd())' has to fit"
        }
    }

    It 'does not name one terminal' {
        $script:banner | Should -Not -Match 'Windows Terminal' `
            -Because 'the reader of this line is as likely to be on Terminal.app or kitty'
    }

    It 'prints the same tagline the module itself prints' {
        # install.ps1 is standalone -- it cannot dot-source lib/help.ps1, so this
        # test is the only place the two literals meet. Compared with .Contains,
        # not -match: -match is case-insensitive and would accept a drifted case.
        $help = (& (Get-Module TerminalStyles) { Show-TerminalStyleHelp } 6>&1 | Out-String)
        $m = [regex]::Match($help, '(?m)^tstyles - (?<tag>.+?)(?:\s*\(v[^)]*\))?\s*$')
        $m.Success | Should -BeTrue -Because 'the module title is where the wording is settled'
        $tag = $m.Groups['tag'].Value
        $tag | Should -Be 'themed styles for your terminal'
        $script:banner.Contains($tag) | Should -BeTrue `
            -Because "the banner must carry the module's own tagline, not a second literal of it"
    }
}
