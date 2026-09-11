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
