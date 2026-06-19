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

    It 'tolerates surrounding whitespace' {
        Test-PolicyResolved -Policy "  RemoteSigned `r`n" | Should -BeTrue
        Test-PolicyResolved -Policy "  Restricted  "       | Should -BeFalse
    }
}
