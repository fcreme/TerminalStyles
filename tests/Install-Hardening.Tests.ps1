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
}
