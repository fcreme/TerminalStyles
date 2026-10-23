# Pester 5 tests for the live Windows Terminal check behind
# .github/workflows/wt-live-spike.yml: scripts/wt-live-install.ps1,
# scripts/wt-live-check.ps1 and scripts/wt-live-probe.ps1.
#
# Those scripts install Windows Terminal packages, open a Terminal window, and
# apply and reset a style on that tab's profile. That is the point on a
# throwaway GitHub-hosted runner and wrong anywhere else, so these tests never
# run them. They dot-source them for their functions, which is all each does
# when dot-sourced, and pin three things: the guards that keep all three off
# every machine but a GitHub-hosted runner; the verdicts, so that a check
# meant to catch the wrong settings.json being written cannot pass by
# comparing nothing; and the readers those verdicts trust.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    . (Join-Path $script:repoRoot 'scripts/wt-live-install.ps1')
    . (Join-Path $script:repoRoot 'scripts/wt-live-check.ps1')
    . (Join-Path $script:repoRoot 'scripts/wt-live-probe.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:PreviewInstall = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe'
    $script:PreviewExe = $script:PreviewInstall + '\WindowsTerminal.exe'
    $script:PreviewFull = 'Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe'
    $script:StableSettings = 'C:\Users\runneradmin\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $script:PreviewSettings = 'C:\Users\runneradmin\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
    $script:Workspace = 'D:\a\TerminalStyles\TerminalStyles'

    # A probe result as result.json carries it, read back the way the check
    # reads it: through ConvertFrom-Json. This one passes every check.
    # Preview's file starts as a copy of Stable's ('aaa'), as a seeded one does.
    $script:GoodResultJson = @'
{
  "Nonce": "n1", "PSEdition": "Desktop", "PSVersion": "5.1.26100.1", "ProcessId": 4242, "Elevated": true,
  "UserSid": "S-1-5-21-1111111111-2222222222-3333333333-500",
  "Env": { "WT_SESSION": "f00", "WT_PROFILE_ID": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "TERM_PROGRAM": null, "InheritedStepEnvironment": true },
  "Module": { "ModuleBase": "D:\\a\\TerminalStyles\\TerminalStyles", "DataRoot": "D:\\a\\_temp\\wt-live-sandbox-powershell", "Sandboxed": true },
  "TerminalKind": "WindowsTerminal",
  "Chain": [
    { "ProcessId": 4242, "Name": "powershell.exe", "ExecutablePath": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "Package": null, "PackageError": null },
    { "ProcessId": 4000, "Name": "WindowsTerminal.exe", "ExecutablePath": "C:\\Program Files\\WindowsApps\\Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe\\WindowsTerminal.exe", "Package": "Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe", "PackageError": 0 }
  ],
  "ChainError": null,
  "NearestHost": { "ProcessId": 4000, "Name": "WindowsTerminal.exe", "ExecutablePath": "C:\\Program Files\\WindowsApps\\Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe\\WindowsTerminal.exe", "Package": "Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe", "PackageError": 0 },
  "HostDepth": 1,
  "HostExePath": "C:\\Program Files\\WindowsApps\\Microsoft.WindowsTerminalPreview_1.26.2734.0_x64__8wekyb3d8bbwe\\WindowsTerminal.exe",
  "SettingsPath": [ "C:\\Users\\runneradmin\\AppData\\Local\\Packages\\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\\LocalState\\settings.json" ],
  "SettingsPathErrors": [],
  "StableExistedAtLookup": true,
  "Pre120": { "Path": "C:\\Users\\runneradmin\\AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json", "Error": null },
  "Before": {
    "Stable":  { "Exists": true, "Sha256": "aaa", "Parsed": true, "HasScheme": false, "TextHasScheme": false, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": null },
    "Preview": { "Exists": true, "Sha256": "aaa", "Parsed": true, "HasScheme": false, "TextHasScheme": false, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": null }
  },
  "Apply": {
    "Errors": [], "Threw": null,
    "Immediate": {
      "Stable":  { "Exists": true, "Sha256": "aaa", "HasScheme": false },
      "Preview": { "Exists": true, "Sha256": "bbb", "Parsed": true, "HasScheme": true, "TextHasScheme": true, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": "eva" }
    },
    "Settled": {
      "Stable":  { "Exists": true, "Sha256": "aaa", "HasScheme": false },
      "Preview": { "Exists": true, "Sha256": "bbb", "Parsed": true, "HasScheme": true, "TextHasScheme": true, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": "eva" }
    }
  },
  "Reset": {
    "Errors": [], "Threw": null,
    "Immediate": {
      "Stable":  { "Exists": true, "Sha256": "aaa", "HasScheme": false },
      "Preview": { "Exists": true, "Sha256": "ccc", "Parsed": true, "HasScheme": false, "TextHasScheme": false, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": null }
    },
    "Settled": {
      "Stable":  { "Exists": true, "Sha256": "aaa", "HasScheme": false },
      "Preview": { "Exists": true, "Sha256": "ccc", "Parsed": true, "HasScheme": false, "TextHasScheme": false, "ProfileFound": true, "ProfileName": "Windows PowerShell", "ProfileColorScheme": null }
    }
  },
  "Errors": []
}
'@
    $script:NewResult = { $script:GoodResultJson | ConvertFrom-Json }
    $script:GoodFinal = [pscustomobject]@{ Stable = [pscustomobject]@{ Exists = $true; Sha256 = 'aaa' } }
    $script:Missing = [pscustomobject]@{ Exists = $false; Sha256 = $null }
    # There, but unreadable: Exists without a hash.
    $script:Unread = [pscustomobject]@{ Exists = $true; Sha256 = $null }

    # Get-CimInstance is Windows-only. Elsewhere a stand-in takes its place, so
    # the tests that mock it run, and mean the same, on every leg; unmocked, it
    # fails, as a WMI query can.
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance {
            [CmdletBinding()]
            param([string]$ClassName, [string]$Filter, [int]$OperationTimeoutSec, [string[]]$Property)
            throw 'Get-CimInstance is not available on this platform'
        }
    }

    # A zip, from { entry name = string or bytes }.
    $script:NewZipBytes = {
        param([hashtable]$Entries)
        $ms = New-Object System.IO.MemoryStream
        $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in $Entries.Keys) {
                $bytes = $Entries[$name]
                if ($bytes -is [string]) { $bytes = [System.Text.Encoding]::UTF8.GetBytes($bytes) }
                $s = $zip.CreateEntry($name).Open()
                try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
            }
        } finally { $zip.Dispose() }
        return ,$ms.ToArray()
    }
    $script:Manifest = {
        param([string]$Name, [string]$Arch, [string]$MinXaml)
        @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="$Name" Publisher="CN=Microsoft Corporation" Version="9.9.9.0" ProcessorArchitecture="$Arch" />
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
    <PackageDependency Name="Microsoft.UI.Xaml.2.8" MinVersion="$MinXaml" Publisher="CN=Microsoft Corporation" />
  </Dependencies>
</Package>
"@
    }
}

AfterAll {
    Remove-Variable -Name WtLivePrompts -Scope Global -ErrorAction SilentlyContinue
}

Describe 'wt-live: where it runs' {
    It 'runs only on a GitHub-hosted runner' {
        Test-GitHubHostedRunner -GitHubActions '' -RunnerEnvironment '' | Should -BeFalse
        Test-GitHubHostedRunner -GitHubActions '' -RunnerEnvironment 'github-hosted' | Should -BeFalse
        Test-GitHubHostedRunner -GitHubActions 'true' -RunnerEnvironment 'self-hosted' |
            Should -BeFalse -Because 'GITHUB_ACTIONS is set on a self-hosted runner too, and that is somebody''s machine'
        Test-GitHubHostedRunner -GitHubActions 'true' -RunnerEnvironment 'github-hosted' | Should -BeTrue
    }

    It 'answers as the live Gallery check''s guard does, for every input' {
        # Two copies of one rule (CLAUDE.md): the Gallery check's is read out of
        # its own file and asked the same questions.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:repoRoot 'scripts/live-gallery-check.ps1'), [ref]$tokens, [ref]$errors)
        $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                                         $n.Name -eq 'Test-GitHubHostedRunner' }, $true))
        $fn.Count | Should -Be 1
        $gallery = $fn[0].Body.GetScriptBlock()
        $asked = 0
        foreach ($actions in @('', 'true', 'false', 'TRUE')) {
            foreach ($environment in @('', 'github-hosted', 'self-hosted', 'GitHub-Hosted')) {
                (Test-GitHubHostedRunner -GitHubActions $actions -RunnerEnvironment $environment) |
                    Should -Be (& $gallery -GitHubActions $actions -RunnerEnvironment $environment) -Because "GITHUB_ACTIONS='$actions', RUNNER_ENVIRONMENT='$environment'"
                $asked++
            }
        }
        $asked | Should -Be 16
    }

    It 'the check refuses before it reads the runner, seeds a file, or opens a tab' {
        Mock Test-GitHubHostedRunner { $false }
        Mock Get-RunnerFacts { throw 'read the runner' }
        Mock Initialize-SettingsFile { throw 'seeded a settings.json' }
        Mock Start-PreviewTab { throw 'opened a tab' }
        Mock Stop-CheckProcess { throw 'stopped a process' }

        $code = Invoke-WTLiveCheck -Engine 'powershell' -Launch 'alias' 6>$null
        $code | Should -Be 2 -Because 'one exit code, and nothing else on the pipeline'
        Should -Invoke Test-GitHubHostedRunner -Times 1 -Exactly
        Should -Invoke Get-RunnerFacts -Times 0 -Exactly
        Should -Invoke Initialize-SettingsFile -Times 0 -Exactly
        Should -Invoke Start-PreviewTab -Times 0 -Exactly
        Should -Invoke Stop-CheckProcess -Times 0 -Exactly
    }

    It 'the installer refuses before it installs anything' {
        Mock Test-GitHubHostedRunner { $false }
        Mock Install-WTBuild { throw 'installed a package' }
        Mock Get-WTBuildReport { throw 'asked Appx' }

        $code = Invoke-WTLiveInstall 6>$null
        $code | Should -Be 2
        # Off a runner the real guard says no as well, so a mock that did not
        # take would pass here too; this is what shows it was the one asked.
        Should -Invoke Test-GitHubHostedRunner -Times 1 -Exactly
        Should -Invoke Install-WTBuild -Times 0 -Exactly
        Should -Invoke Get-WTBuildReport -Times 0 -Exactly
    }

    It 'the probe refuses a config not written on a GitHub-hosted runner, and says so in result.json' {
        Mock Import-ProbeModule { throw 'imported the module' }
        Mock Get-ProcessChain { throw 'read the process tree' }
        $dir = Join-Path $TestDrive 'refuse'
        $null = New-Item -ItemType Directory -Force -Path $dir
        $config = Join-Path $dir 'config.json'
        [System.IO.File]::WriteAllText($config, '{ "Nonce": "n9", "Engine": "pwsh", "GitHubActions": "", "RunnerEnvironment": "" }',
                                       (New-Object System.Text.UTF8Encoding($false)))

        $code = Invoke-WTLiveProbe -ConfigPath $config 6>$null
        $code | Should -Be 0 -Because 'the refusal is reported in result.json, which was written'
        Should -Invoke Import-ProbeModule -Times 0 -Exactly
        Should -Invoke Get-ProcessChain -Times 0 -Exactly
        [System.IO.File]::Exists((Join-Path $dir 'started.json')) | Should -BeFalse
        $result = Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
        $result.Nonce | Should -Be 'n9'
        @($result.Errors).Count | Should -Be 1
        $result.Errors[0] | Should -Match 'GitHub-hosted runner'
    }
}

Describe 'wt-live: the command line Windows Terminal is handed' {
    It 'opens one new tab in the named profile and runs the probe after --' {
        $a = Get-WTArgumentString -ProfileName 'Windows PowerShell' -EnginePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
                                  -ProbePath 'D:\a\r\r\scripts\wt-live-probe.ps1' -ConfigPath 'D:\a\_temp\wt-live\config.json'
        $a | Should -BeExactly ('-w new new-tab -p "Windows PowerShell" -- C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe ' +
                                '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\a\r\r\scripts\wt-live-probe.ps1 -ConfigPath D:\a\_temp\wt-live\config.json')
    }

    It 'quotes an engine path with a space, as WT itself re-quotes it' {
        $a = Get-WTArgumentString -ProfileName 'PowerShell' -EnginePath 'C:\Program Files\PowerShell\7\pwsh.exe' `
                                  -ProbePath 'D:\a\p.ps1' -ConfigPath 'D:\a\c.json'
        $a | Should -Match ([regex]::Escape('-- "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile'))
    }

    It 'refuses a probe or config path that WT would split or mangle' {
        foreach ($bad in @('D:\a b\p.ps1', 'D:\a;b\p.ps1', 'D:\a"b\p.ps1')) {
            { Get-WTArgumentString -ProfileName 'PowerShell' -EnginePath 'C:\x\pwsh.exe' -ProbePath $bad -ConfigPath 'D:\c.json' } |
                Should -Throw -Because "'$bad' as the probe path"
            { Get-WTArgumentString -ProfileName 'PowerShell' -EnginePath 'C:\x\pwsh.exe' -ProbePath 'D:\p.ps1' -ConfigPath $bad } |
                Should -Throw -Because "'$bad' as the config path"
        }
        { Get-WTArgumentString -ProfileName 'PowerShell' -EnginePath 'C:\x;y\pwsh.exe' -ProbePath 'D:\p.ps1' -ConfigPath 'D:\c.json' } | Should -Throw
    }

    It 'opens the profile each engine belongs to' {
        Get-ProbeProfileName -Engine 'powershell' | Should -Be 'Windows PowerShell'
        Get-ProbeProfileName -Engine 'pwsh' | Should -Be 'PowerShell'
    }
}

Describe 'wt-live: the verdicts pass on a good run' {
    It 'every check passes on a run that did what it should' {
        $r = & $script:NewResult
        Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -BeNullOrEmpty
        Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -BeNullOrEmpty
        Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull -UnpackagedBefore $script:Missing -UnpackagedAfter $script:Missing | Should -BeNullOrEmpty
        Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings | Should -BeNullOrEmpty
        Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -BeNullOrEmpty
        Get-RigVerdict -BaselineSha256 'aaa' -Result $r | Should -BeNullOrEmpty
        Get-StableVerdict -Result $r -Final $script:GoodFinal -StyleName 'eva' | Should -BeNullOrEmpty
        Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -BeNullOrEmpty
        Get-ResetVerdict -Result $r -StyleName 'eva' | Should -BeNullOrEmpty
    }

    It 'compares paths as Windows does: case and a trailing separator do not matter' {
        $r = & $script:NewResult
        $r.SettingsPath = @($script:PreviewSettings.ToUpperInvariant())
        Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings | Should -BeNullOrEmpty
        Test-SamePath 'C:\A\B\' 'c:\a\b' | Should -BeTrue
        Test-SamePath '' '' | Should -BeFalse -Because 'two empty answers are not the same file'
    }
}

Describe 'wt-live: the verdicts fail where they should' {
    Context 'the tab' {
        It 'rejects a result from another run' {
            Get-TabVerdict -Result (& $script:NewResult) -Nonce 'n2' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'another run'
            Get-TabVerdict -Result (& $script:NewResult) -Nonce '' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'another run'
            Get-TabVerdict -Result $null -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'no result'
        }

        It 'rejects the wrong engine, a shell no tab started, another copy of the module, an unsandboxed one, and a non-WT session' {
            Get-TabVerdict -Result (& $script:NewResult) -Nonce 'n1' -Engine 'pwsh' -Workspace $script:Workspace | Should -Match 'not pwsh'
            $r = & $script:NewResult; $r.Env.WT_SESSION = $null
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'WT_SESSION'
            $r = & $script:NewResult; $r.Module.ModuleBase = 'C:\Users\x\Documents\PowerShell\Modules\TerminalStyles\0.9.2'
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'not the checkout'
            $r = & $script:NewResult; $r.Module.Sandboxed = $false
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'sandbox'
            $r = & $script:NewResult; $r.TerminalKind = 'Unknown'
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'not a Windows Terminal tab'
            $r = & $script:NewResult; $r.Errors = @('Import-Module failed')
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'Import-Module failed'
        }

        It 'rejects a run in which a prompt was reached, even one the files survived' {
            $r = & $script:NewResult
            $r | Add-Member -NotePropertyName Prompts -NotePropertyValue @('Target profile') -Force
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'prompt was reached.*Target profile'
        }

        It 'rejects a tab with no profile to style' {
            $r = & $script:NewResult; $r.Env.WT_PROFILE_ID = $null
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'no WT_PROFILE_ID'
        }

        It 'reports a probe that failed before it read its config as that failure, not as another run''s result' {
            # The probe writes result.json in a finally; one that could not read
            # the config never learned the nonce, and says why in Errors.
            $r = & $script:NewResult; $r.Nonce = $null; $r.Errors = @('cannot read D:\a\_temp\wt-live\config.json (line 256)')
            $v = Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace
            $v | Should -Match 'failed before it recorded this run''s nonce: cannot read D:'
            $v | Should -Not -Match 'another run'
            # With no error to report, a missing nonce is still not this run's.
            $r = & $script:NewResult; $r.Nonce = $null
            Get-TabVerdict -Result $r -Nonce 'n1' -Engine 'powershell' -Workspace $script:Workspace | Should -Match 'another run'
        }
    }

    Context 'the host and its identity' {
        It 'rejects a tab with no WindowsTerminal.exe above it, and names what is above it' {
            $r = & $script:NewResult; $r.NearestHost = $null; $r.Chain = @($r.Chain[0])
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall |
                Should -Match 'no WindowsTerminal.exe above the tab''s shell \(shell and ancestors: powershell\.exe\)'
        }

        It 'tells a WindowsTerminal.exe whose path Windows withholds from no WindowsTerminal.exe at all' {
            # The PR's second premise failing, not its first: the ancestor is
            # there and named, only its ExecutablePath is not given.
            $r = & $script:NewResult; $r.NearestHost.ExecutablePath = ''; $r.HostExePath = ''
            $v = Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall
            $v | Should -Match ('WindowsTerminal\.exe \(pid 4000, package ' + [regex]::Escape($script:PreviewFull) + '\) is the nearest ancestor of the tab''s shell, but Win32_Process returned no ExecutablePath for it')
            $v | Should -Match 'Find-WTHostExePath returned nothing'
            $v | Should -Not -Match 'no WindowsTerminal\.exe'
            # Package identity is read off the process, not its path, so that
            # check can still pass on the same result; the host row is the one that fails.
            Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull -UnpackagedBefore $script:Missing -UnpackagedAfter $script:Missing |
                Should -BeNullOrEmpty

            $r = & $script:NewResult; $r.NearestHost.ExecutablePath = $null; $r.NearestHost.Package = $null; $r.NearestHost.PackageError = 5
            $v = Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall
            $v | Should -Match '\(pid 4000, no package named \(error 5\)\)'
            $v | Should -Match ("Find-WTHostExePath returned '" + [regex]::Escape($script:PreviewExe) + "'")
        }

        It 'says when the tab could not read its process tree, or found no process in it' {
            $r = & $script:NewResult; $r.NearestHost = $null; $r.Chain = @(); $r.ChainError = 'Access denied'
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -Match 'could not read its process tree: Access denied'
            $r = & $script:NewResult; $r.NearestHost = $null; $r.Chain = @()
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -Match 'not even the shell'
        }

        It 'rejects Stable''s WindowsTerminal.exe, and a folder that only starts like Preview''s' {
            $r = & $script:NewResult
            $r.NearestHost.ExecutablePath = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.23.20211.0_x64__8wekyb3d8bbwe\WindowsTerminal.exe'
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -Match 'not under Preview'
            $r = & $script:NewResult
            $r.NearestHost.ExecutablePath = $script:PreviewInstall + '-copy\WindowsTerminal.exe'
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -Match 'not under Preview'
        }

        It 'rejects a module walk that disagrees with the tree, or found nothing' {
            $r = & $script:NewResult; $r.HostExePath = ''
            Get-HostVerdict -Result $r -PreviewInstallLocation $script:PreviewInstall | Should -Match 'Find-WTHostExePath'
        }

        It 'rejects a WindowsTerminal.exe with no package identity, or another package''s' {
            $r = & $script:NewResult; $r.NearestHost.Package = $null; $r.NearestHost.PackageError = 15700
            Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull | Should -Match 'unpackaged'
            $r = & $script:NewResult; $r.NearestHost.Package = $null; $r.NearestHost.PackageError = 5
            Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull | Should -Match 'named no package .*: error 5$'
            $r = & $script:NewResult; $r.NearestHost.Package = 'Microsoft.WindowsTerminal_1.23.20211.0_x64__8wekyb3d8bbwe'
            Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull | Should -Match 'not Microsoft.WindowsTerminalPreview'
            $r = & $script:NewResult; $r.NearestHost = $null
            Get-IdentityVerdict -Result $r -PreviewPackageFullName $script:PreviewFull | Should -Match 'no WindowsTerminal.exe above the tab''s shell to ask'
        }

        It 'says on a passing host row that premise 2 was read elevated only' {
            # A green summary must not read as proof that a standard user can
            # read the path: on a hosted runner the reader is elevated.
            $r = & $script:NewResult
            $c = Get-HostCaveat -Result $r
            $c | Should -Match 'elevated process running as the built-in Administrator: premise 2 is exercised elevated only, and the standard-user case is not covered'
            $r.UserSid = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
            $c = Get-HostCaveat -Result $r
            $c | Should -Match '^The path was read by an elevated process: premise 2 is exercised elevated only'
            $c | Should -Not -Match 'built-in'
            $r.Elevated = $false
            Get-HostCaveat -Result $r | Should -BeExactly 'The path was read by a process that is not elevated'
            $r.Elevated = $null
            Get-HostCaveat -Result $r | Should -Match 'not recorded'
        }

        It 'rejects an unpackaged settings.json that appeared or changed during the run' {
            $after = [pscustomobject]@{ Path = 'C:\x\settings.json'; Exists = $true; Sha256 = 'u2' }
            Get-IdentityVerdict -Result (& $script:NewResult) -PreviewPackageFullName $script:PreviewFull -UnpackagedBefore $script:Missing -UnpackagedAfter $after |
                Should -Match 'appeared'
            $before = [pscustomobject]@{ Path = 'C:\x\settings.json'; Exists = $true; Sha256 = 'u1' }
            Get-IdentityVerdict -Result (& $script:NewResult) -PreviewPackageFullName $script:PreviewFull -UnpackagedBefore $before -UnpackagedAfter $after |
                Should -Match 'changed'
        }
    }

    Context 'the lookup and the control' {
        It 'names the bug when the lookup returns Stable''s file' {
            $r = & $script:NewResult; $r.SettingsPath = @($script:StableSettings)
            Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings |
                Should -Match 'the bug #120 is meant to fix'
        }

        It 'reports the refusal when the lookup returns nothing' {
            $r = & $script:NewResult; $r.SettingsPath = @(); $r.SettingsPathErrors = @('expected its settings.json at X and found none')
            Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings |
                Should -Match 'returned 0 paths.*found none'
        }

        It 'does not count a lookup made while Stable''s file was absent' {
            $r = & $script:NewResult; $r.StableExistedAtLookup = $false
            Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings |
                Should -Match 'could not have picked it'
        }

        It 'fails a lookup that names some third file' {
            $r = & $script:NewResult; $r.SettingsPath = @('C:\elsewhere\settings.json')
            Get-LookupVerdict -Result $r -PreviewSettingsPath $script:PreviewSettings -StableSettingsPath $script:StableSettings |
                Should -Match ('returned C:\\elsewhere\\settings\.json, not Preview''s ' + [regex]::Escape($script:PreviewSettings))
        }

        It 'fails the control when the old lookup does not pick Stable''s file' {
            $r = & $script:NewResult; $r.Pre120.Path = $script:PreviewSettings
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'does not reproduce the bug'
            $r = & $script:NewResult; $r.Pre120.Path = $null; $r.Pre120.Error = 'no pre-#120 tstyles.ps1'
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'could not run'
            $r = & $script:NewResult; $r.Pre120 = $null
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'was not run'
        }

        It 'fails the control when Stable''s file lacks the tab''s profile, since the old apply then refused instead' {
            # Pre-#120 Apply-StyleDirect looked WT_PROFILE_ID up in the file the
            # lookup returned, and with no such profile wrote nothing.
            $r = & $script:NewResult; $r.Before.Stable.ProfileFound = $false
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings |
                Should -Match 'has no profile \{61c54bbd-c2c6-5271-96e7-009a87ff44bf\} \(the tab''s WT_PROFILE_ID\), so the pre-#120 apply would have refused.*does not reproduce the bug'
            $r = & $script:NewResult; $r.Env.WT_PROFILE_ID = $null
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'has no WT_PROFILE_ID, so the pre-#120 apply would have refused'
            $r = & $script:NewResult; $r.Before.Stable = $script:Unread
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'could not read Stable''s settings.json before the apply.*unknown'
            $r = & $script:NewResult; $r.Before.Stable.Parsed = $false; $r.Before.Stable | Add-Member -NotePropertyName ParseError -NotePropertyValue 'bad token' -Force
            Get-ControlVerdict -Result $r -StableSettingsPath $script:StableSettings | Should -Match 'did not parse in the tab \(bad token\).*unknown'
        }
    }

    Context 'Stable''s file' {
        It 'fails when Stable''s file moved before the apply' {
            Get-RigVerdict -BaselineSha256 'zzz' -Result (& $script:NewResult) | Should -Match 'before TerminalStyles wrote anything'
            Get-RigVerdict -BaselineSha256 '' -Result (& $script:NewResult) | Should -Match 'no reading'
        }

        It 'fails when the tab found Stable''s file but could not read it' {
            $r = & $script:NewResult; $r.Before.Stable = $script:Unread
            Get-RigVerdict -BaselineSha256 'aaa' -Result $r | Should -Match 'could not read Stable''s settings.json before the apply'
        }

        It 'fails on any one changed reading, and names TerminalStyles when the style landed in it' {
            $r = & $script:NewResult; $r.Apply.Settled.Stable.Sha256 = 'ddd'; $r.Apply.Settled.Stable.HasScheme = $true
            Get-StableVerdict -Result $r -Final $script:GoodFinal -StyleName 'eva' | Should -Match 'once the apply had settled.*TerminalStyles wrote Stable''s file'
            $final = [pscustomobject]@{ Stable = [pscustomobject]@{ Exists = $true; Sha256 = 'eee' } }
            Get-StableVerdict -Result (& $script:NewResult) -Final $final -StyleName 'eva' | Should -Match 'after the tab closed'
        }

        It 'does not pass on readings that are missing, even when they agree' {
            # The two-$null-hashes trap: absent on both sides compares equal.
            $r = & $script:NewResult
            foreach ($step in @($r.Before, $r.Apply.Immediate, $r.Apply.Settled, $r.Reset.Immediate, $r.Reset.Settled)) {
                $step.Stable = [pscustomobject]@{ Exists = $false; Sha256 = $null }
            }
            Get-StableVerdict -Result $r -Final ([pscustomobject]@{ Stable = $script:Missing }) -StyleName 'eva' | Should -Match 'missing before the apply'
            $r = & $script:NewResult; $r.Reset.Immediate.Stable.Sha256 = $null
            Get-StableVerdict -Result $r -Final $script:GoodFinal -StyleName 'eva' | Should -Match 'could not be read right after the reset'
            Get-StableVerdict -Result (& $script:NewResult) -Final $null -StyleName 'eva' | Should -Match 'after the tab closed'
        }

        It 'does not pass when the apply wrote nothing anywhere' {
            $r = & $script:NewResult; $r.Apply.Settled.Preview.Sha256 = 'aaa'
            Get-StableVerdict -Result $r -Final $script:GoodFinal -StyleName 'eva' | Should -Match 'not measured'
        }
    }

    Context 'the apply and the reset' {
        It 'fails an apply that left Preview''s file as it was' {
            $r = & $script:NewResult; $r.Apply.Settled.Preview.Sha256 = 'aaa'; $r.Apply.Errors = @('This session runs under the Windows Terminal at X...')
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'byte-identical after tstyles eva.*This session runs under'
        }

        It 'fails an apply whose file changed without the scheme, or where the reader and the text disagree' {
            $r = & $script:NewResult; $r.Apply.Settled.Preview.HasScheme = $false; $r.Apply.Settled.Preview.TextHasScheme = $false
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'carries no ''eva'' scheme'
            $r = & $script:NewResult; $r.Apply.Settled.Preview.TextHasScheme = $false
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'carries no ''eva'' scheme'
        }

        It 'fails an apply that styled some other profile, or the same one in another case' {
            $r = & $script:NewResult; $r.Apply.Settled.Preview.ProfileColorScheme = 'Campbell'
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'colorScheme ''Campbell'''
            $r = & $script:NewResult; $r.Apply.Settled.Preview.ProfileColorScheme = 'EVA'
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'colorScheme ''EVA'''
        }

        It 'fails a reset that left the scheme or the colorScheme behind, or changed nothing' {
            $r = & $script:NewResult; $r.Reset.Settled.Preview.HasScheme = $true
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'still carries'
            $r = & $script:NewResult; $r.Reset.Settled.Preview.TextHasScheme = $true
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'still carries'
            $r = & $script:NewResult; $r.Reset.Settled.Preview.ProfileColorScheme = 'eva'
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'still has colorScheme'
            $r = & $script:NewResult; $r.Reset.Settled.Preview.Sha256 = 'bbb'
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'byte-identical after tstyles reset'
            # And says what the command said, when it said something.
            $r = & $script:NewResult; $r.Reset.Settled.Preview.Sha256 = 'bbb'; $r.Reset.Errors = @('', 'Could not locate Windows Terminal settings.json.')
            Get-ResetVerdict -Result $r -StyleName 'eva' |
                Should -BeExactly "Preview's settings.json is byte-identical after tstyles reset (it said: Could not locate Windows Terminal settings.json.)"
        }

        It 'does not pass a reset after an apply that never put the style there' {
            # Nothing was there to remove, so "it is gone" proves nothing.
            $r = & $script:NewResult; $r.Apply.Settled.Preview.HasScheme = $false
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'not measured'
        }

        It 'does not pass a reset after which the tab''s profile is gone' {
            # A profile that is not there has no colorScheme either.
            $r = & $script:NewResult; $r.Reset.Settled.Preview.ProfileFound = $false; $r.Reset.Settled.Preview.ProfileName = $null
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'tab''s profile \(\{61c54bbd-c2c6-5271-96e7-009a87ff44bf\}\) is not in Preview''s settings.json after tstyles reset'
        }

        It 'fails an apply or a reset that never ran, or whose file could not be read or parsed' {
            $r = & $script:NewResult; $r.Apply = $null
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'the apply never ran'
            $r = & $script:NewResult; $r.Before.Preview = $script:Unread
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'could not be read before the apply'
            $r = & $script:NewResult; $r.Apply.Settled.Preview = $script:Unread
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'could not be read after the apply'
            $r = & $script:NewResult; $r.Apply.Settled.Preview.Parsed = $false
            $r.Apply.Settled.Preview | Add-Member -NotePropertyName ParseError -NotePropertyValue 'bad token' -Force
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'does not parse after the apply: bad token'

            $r = & $script:NewResult; $r.Reset = $null
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'the reset never ran'
            $r = & $script:NewResult; $r.Reset.Settled.Preview = $script:Unread
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'could not be read after the reset'
            $r = & $script:NewResult; $r.Reset.Settled.Preview.Parsed = $false
            $r.Reset.Settled.Preview | Add-Member -NotePropertyName ParseError -NotePropertyValue 'bad token' -Force
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match 'does not parse after the reset: bad token'
        }

        It 'fails an apply that styled a profile its file does not hold' {
            $r = & $script:NewResult; $r.Apply.Settled.Preview.ProfileFound = $false
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match 'tab''s profile .* is not in Preview''s settings.json'
        }

        It 'fails an apply or a reset that stopped on an error, even where every file came out right' {
            # Inside the probe's try, a statement-terminating error ends the
            # command where a user's session would run on past it.
            $r = & $script:NewResult; $r.Apply.Threw = 'Exception calling "Parse"'
            Get-ApplyVerdict -Result $r -StyleName 'eva' | Should -Match '^tstyles eva stopped on an error the probe caught: Exception calling "Parse"\. .*not known to be the user''s path'
            $r = & $script:NewResult; $r.Reset.Threw = 'boom'
            Get-ResetVerdict -Result $r -StyleName 'eva' | Should -Match '^tstyles reset stopped on an error the probe caught: boom\.'
        }
    }

    Context 'the preconditions' {
        It 'wants each build registered exactly once' {
            $one = [pscustomobject]@{ InstallLocation = 'C:\x' }
            Get-PackagesVerdict -Stable @($one) -Preview @() | Should -Match 'Preview .* 0 times'
            Get-PackagesVerdict -Stable @($one, $one) -Preview @($one) | Should -Match 'Stable .* 2 times'
            Get-PackagesVerdict -Stable @($one) -Preview @($one) | Should -BeNullOrEmpty
        }

        It 'wants each build registered at a folder' {
            $one = [pscustomobject]@{ InstallLocation = 'C:\x' }
            $none = [pscustomobject]@{ InstallLocation = '' }
            Get-PackagesVerdict -Stable @($none) -Preview @($one) | Should -Match '^Stable is registered with no InstallLocation'
            Get-PackagesVerdict -Stable @($one) -Preview @($none) | Should -Match '^Preview is registered with no InstallLocation'
        }

        It 'wants Stable''s file there, readable and still' {
            $ok = [pscustomobject]@{ Exists = $true; Sha256 = 'aaa' }
            Get-SettingsVerdict -Stable $script:Missing -Preview $ok -StableQuiet $null | Should -Match 'old Stable-first lookup'
            Get-SettingsVerdict -Stable $ok -Preview $ok -StableQuiet ([pscustomobject]@{ Settled = $false; Changes = 4 }) | Should -Match 'kept changing'
            Get-SettingsVerdict -Stable $ok -Preview $script:Missing -StableQuiet $null | Should -Match 'Preview''s settings.json is missing'
            Get-SettingsVerdict -Stable $ok -Preview $ok -StableQuiet ([pscustomobject]@{ Settled = $true; Changes = 0 }) | Should -BeNullOrEmpty
        }

        It 'tells a file that is there but unreadable from a missing one' {
            $ok = [pscustomobject]@{ Exists = $true; Sha256 = 'aaa' }
            Get-SettingsVerdict -Stable $script:Unread -Preview $ok -StableQuiet $null | Should -Match '^Stable''s settings.json is there but could not be read'
            Get-SettingsVerdict -Stable $ok -Preview $script:Unread -StableQuiet $null | Should -Match '^Preview''s settings.json is there but could not be read'
        }
    }
}

Describe 'wt-live: the cleanup stops what the check started, and nothing else' {
    BeforeAll {
        $script:LaunchedAt = [datetime]::new(2026, 10, 23, 9, 30, 0, [System.DateTimeKind]::Utc)
        $script:Marker = 'D:\a\_temp\wt-live\config.json'
        # A hosted runner's processes: a Stable WindowsTerminal.exe from before
        # the job, hosting the runner agent's console (pid 3960 in the job log
        # the review quoted); then the Preview one this check opened, the probe
        # in its tab, and the step's own shell.
        $script:StableWT = [pscustomobject]@{ ProcessId = 3960; Name = 'WindowsTerminal.exe'; CommandLine = $null
            ExecutablePath = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.23.20211.0_x64__8wekyb3d8bbwe\WindowsTerminal.exe'
            CreationDate = $script:LaunchedAt.AddMinutes(-20) }
        $script:PreviewWT = [pscustomobject]@{ ProcessId = 5100; Name = 'WindowsTerminal.exe'; CommandLine = $null
            ExecutablePath = $script:PreviewExe; CreationDate = $script:LaunchedAt.AddSeconds(2) }
        $script:ProbeProc = [pscustomobject]@{ ProcessId = 5200; Name = 'pwsh.exe'; ExecutablePath = 'C:\Program Files\PowerShell\7\pwsh.exe'
            CommandLine = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -File D:\a\r\r\scripts\wt-live-probe.ps1 -ConfigPath D:\a\_temp\wt-live\config.json'
            CreationDate = $script:LaunchedAt.AddSeconds(3) }
        $script:StepShell = [pscustomobject]@{ ProcessId = 1200; Name = 'powershell.exe'; ExecutablePath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            CommandLine = 'powershell -command ". ''D:\a\_temp\1234.ps1''"'; CreationDate = $script:LaunchedAt.AddMinutes(-1) }
        $script:Running = @($script:StableWT, $script:PreviewWT, $script:ProbeProc, $script:StepShell)
        $script:Snap = { param([int[]]$Ids) [pscustomobject]@{ Ok = $true; Ids = @($Ids); Error = $null } }
        $script:StopWith = {
            param($Snapshot)
            Stop-CheckProcess -Snapshot $Snapshot -PreviewInstallLocation $script:PreviewInstall -LaunchedAt $script:LaunchedAt `
                              -Marker $script:Marker -Processes $script:Running
        }
    }

    It 'an empty before-launch snapshot does not make the Stable terminal hosting the runner look new' {
        Mock Stop-Process { }
        $report = & $script:StopWith (& $script:Snap @())
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 3960 } -Times 0 -Exactly
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 1200 } -Times 0 -Exactly
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 5100 } -Times 1 -Exactly
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 5200 } -Times 1 -Exactly
        Should -Invoke Stop-Process -Times 2 -Exactly
        @($report.Stopped).Count | Should -Be 2
        $report.Note | Should -BeNullOrEmpty
    }

    It 'a snapshot that failed stops no terminal, says so, and still stops the probe' {
        Mock Stop-Process { }
        $report = & $script:StopWith ([pscustomobject]@{ Ok = $false; Ids = @(); Error = 'WMI hiccup' })
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 3960 } -Times 0 -Exactly
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 5100 } -Times 0 -Exactly
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 5200 } -Times 1 -Exactly
        Should -Invoke Stop-Process -Times 1 -Exactly
        $report.Note | Should -Match 'no WindowsTerminal\.exe was stopped: the ones running before the launch could not be listed \(WMI hiccup\)'
        Format-StopReport $report | Should -Match '^stopped pwsh\.exe \(pid 5200\).*\. no WindowsTerminal\.exe was stopped'
    }

    It 'keeps a terminal that was running before the launch' {
        Mock Stop-Process { }
        $null = & $script:StopWith (& $script:Snap @(3960, 5100))
        Should -Invoke Stop-Process -ParameterFilter { $Id -contains 3960 -or $Id -contains 5100 } -Times 0 -Exactly
    }

    It 'keeps a terminal outside Preview''s folder, or from before the launch, or one Windows gives no path or start time for' {
        $snap = & $script:Snap @()
        $keep = @(
            [pscustomobject]@{ ProcessId = 1; Name = 'WindowsTerminal.exe'; ExecutablePath = $script:StableWT.ExecutablePath; CreationDate = $script:LaunchedAt.AddSeconds(5) },
            [pscustomobject]@{ ProcessId = 2; Name = 'WindowsTerminal.exe'; ExecutablePath = $script:PreviewInstall + '-copy\WindowsTerminal.exe'; CreationDate = $script:LaunchedAt.AddSeconds(5) },
            [pscustomobject]@{ ProcessId = 3; Name = 'WindowsTerminal.exe'; ExecutablePath = $script:PreviewExe; CreationDate = $script:LaunchedAt.AddSeconds(-5) },
            [pscustomobject]@{ ProcessId = 4; Name = 'WindowsTerminal.exe'; ExecutablePath = $script:PreviewExe; CreationDate = $script:LaunchedAt },
            [pscustomobject]@{ ProcessId = 5; Name = 'WindowsTerminal.exe'; ExecutablePath = ''; CreationDate = $script:LaunchedAt.AddSeconds(5) },
            [pscustomobject]@{ ProcessId = 6; Name = 'WindowsTerminal.exe'; ExecutablePath = $script:PreviewExe; CreationDate = $null }
        )
        $picked = @(Select-ProcessToStop -Processes $keep -Snapshot $snap -PreviewInstallLocation $script:PreviewInstall `
                                         -LaunchedAt $script:LaunchedAt -Marker $script:Marker)
        $picked.Count | Should -Be 0 -Because 'each fails one of: Preview''s folder, created after the launch, a path, a start time'
        # And with no Preview folder to compare against, no terminal at all.
        @(Select-ProcessToStop -Processes @($script:PreviewWT) -Snapshot $snap -PreviewInstallLocation '' `
                               -LaunchedAt $script:LaunchedAt -Marker $script:Marker).Count | Should -Be 0
    }

    It 'reports a stop that failed instead of dropping it' {
        Mock Stop-Process { throw 'Access is denied' }
        $report = & $script:StopWith (& $script:Snap @(3960))
        @($report.Stopped).Count | Should -Be 0
        @($report.Failed).Count | Should -Be 2
        Format-StopReport $report | Should -Match '^could not stop WindowsTerminal\.exe \(pid 5100\).*: Access is denied; pwsh\.exe \(pid 5200\).*: Access is denied$'
    }

    It 'stops nothing when the processes cannot be listed, and says why' {
        Mock Get-CimInstance { Write-Error 'The RPC server is unavailable' }
        Mock Stop-Process { }
        $report = Stop-CheckProcess -Snapshot (& $script:Snap @()) -PreviewInstallLocation $script:PreviewInstall -LaunchedAt $script:LaunchedAt -Marker $script:Marker
        Should -Invoke Get-CimInstance -Times 1 -Exactly
        Should -Invoke Stop-Process -Times 0 -Exactly
        $report.Note | Should -Match '^nothing was stopped: the running processes could not be listed \(The RPC server is unavailable\)'
        Format-StopReport ([pscustomobject]@{ Stopped = @(); Failed = @(); Note = $null }) | Should -BeExactly 'nothing'
    }

    It 'takes the snapshot so that a failure is a failure, not an empty list' {
        # Written, not thrown: CIM reports a failed query as a non-terminating
        # error, which -ErrorAction SilentlyContinue would turn into no rows.
        Mock Get-CimInstance { Write-Error 'WMI hiccup' }
        $s = Get-TerminalSnapshot
        $s.Ok | Should -BeFalse
        $s.Error | Should -Match 'WMI hiccup'
        Mock Get-CimInstance { }
        $s = Get-TerminalSnapshot
        $s.Ok | Should -BeTrue -Because 'no terminal running is an answer'
        @($s.Ids).Count | Should -Be 0
        Mock Get-CimInstance { [pscustomobject]@{ ProcessId = 3960 }; [pscustomobject]@{ ProcessId = 77 } }
        (@((Get-TerminalSnapshot).Ids) -join ',') | Should -Be '3960,77'
    }

    It 'knows the probe by the run''s config path on a PowerShell command line, and never takes this process' {
        Test-ProbeProcess -Process $script:ProbeProc -Marker $script:Marker | Should -BeTrue
        Test-ProbeProcess -Process $script:ProbeProc -Marker $script:Marker.ToUpperInvariant() | Should -BeTrue -Because 'Windows paths ignore case'
        Test-ProbeProcess -Process $script:ProbeProc -Marker $script:Marker -SelfId 5200 | Should -BeFalse
        Test-ProbeProcess -Process $script:StepShell -Marker $script:Marker | Should -BeFalse
        $wt = [pscustomobject]@{ ProcessId = 9; Name = 'WindowsTerminal.exe'; CommandLine = $script:ProbeProc.CommandLine }
        Test-ProbeProcess -Process $wt -Marker $script:Marker | Should -BeFalse -Because 'only a PowerShell is the probe'
        Test-ProbeProcess -Process ([pscustomobject]@{ ProcessId = 9; Name = 'pwsh.exe'; CommandLine = $null }) -Marker $script:Marker | Should -BeFalse
        Test-ProbeProcess -Process $null -Marker $script:Marker | Should -BeFalse
    }

    It 'says whether the probe still runs, and does not take a failed listing for an exit' {
        Mock Get-CimInstance { $script:StepShell; $script:ProbeProc }
        Test-ProbeRunning -Marker $script:Marker | Should -BeTrue
        Mock Get-CimInstance { $script:StepShell }
        Test-ProbeRunning -Marker $script:Marker | Should -BeFalse
        Mock Get-CimInstance { Write-Error 'WMI hiccup' }
        Test-ProbeRunning -Marker $script:Marker | Should -BeNullOrEmpty
        $null -eq (Test-ProbeRunning -Marker $script:Marker) | Should -BeTrue
    }
}

Describe 'wt-live: the wait for the probe' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path $script:dir
        $script:startedPath = Join-Path $script:dir 'started.json'
        $script:resultPath = Join-Path $script:dir 'result.json'
        $script:WaitFor = {
            param([double]$Start = 2, [double]$Result = 2)
            Wait-ProbeResult -StartedPath $script:startedPath -ResultPath $script:resultPath -Marker 'D:\a\_temp\wt-live\config.json' `
                             -StartTimeoutSeconds $Start -ResultTimeoutSeconds $Result -IntervalMs 50
        }
    }

    It 'takes the result.json of a probe that failed before it wrote started.json, and reads it at once' {
        [System.IO.File]::WriteAllText($script:resultPath, '{}')
        Mock Test-ProbeRunning { throw 'asked the process list' }
        $w = & $script:WaitFor
        $w.Started | Should -BeTrue
        $w.Finished | Should -BeTrue
        $w.Exited | Should -BeFalse
        Should -Invoke Test-ProbeRunning -Times 0 -Exactly
    }

    It 'stops waiting once the probe has exited without a result' {
        [System.IO.File]::WriteAllText($script:startedPath, '{}')
        $script:answers = @($true, $false, $false)
        $script:asked = 0
        Mock Test-ProbeRunning { $a = $script:answers[[Math]::Min($script:asked, 2)]; $script:asked++; $a }
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $w = & $script:WaitFor -Result 60
        $clock.Stop()
        $w.Exited | Should -BeTrue
        $w.Finished | Should -BeFalse
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 30 -Because 'it did not wait out the 60 s'
        Should -Invoke Test-ProbeRunning -Times 3 -Exactly -Because 'seen once, then two listings in a row without it'
    }

    It 'waits in full for a probe it never saw running, since not finding one then says nothing' {
        # A probe whose command line Windows does not give is never found, from
        # the first listing to the last; that is not an exit.
        [System.IO.File]::WriteAllText($script:startedPath, '{}')
        Mock Test-ProbeRunning { $false }
        $w = & $script:WaitFor -Result 1
        $w.Exited | Should -BeFalse
        $w.Finished | Should -BeFalse
        Should -Invoke Test-ProbeRunning -Times 3 -Because 'it kept asking until the deadline'
    }

    It 'does not take one missing reading, or a failed listing, for an exit' {
        [System.IO.File]::WriteAllText($script:startedPath, '{}')
        $script:answers = @($false, $true, $null, $false, $null)
        $script:asked = 0
        Mock Test-ProbeRunning { $a = $script:answers[$script:asked % $script:answers.Count]; $script:asked++; $a }
        $w = & $script:WaitFor -Result 1
        $w.Exited | Should -BeFalse
        $w.Finished | Should -BeFalse
        Mock Test-ProbeRunning { $null }
        (& $script:WaitFor -Result 0.5).Exited | Should -BeFalse
    }

    It 'reads a result the probe wrote on its way out' {
        # Seen, then gone twice; the result lands during the second listing
        # that misses it, after this loop last looked for it.
        [System.IO.File]::WriteAllText($script:startedPath, '{}')
        $script:asked = 0
        Mock Test-ProbeRunning {
            $script:asked++
            if ($script:asked -eq 1) { return $true }
            if ($script:asked -ge 3) { [System.IO.File]::WriteAllText($script:resultPath, '{}') }
            $false
        }
        $w = & $script:WaitFor
        $w.Finished | Should -BeTrue
        $w.Exited | Should -BeFalse
        Should -Invoke Test-ProbeRunning -Times 3 -Exactly
    }

    It 'says no tab started the probe when nothing appears' {
        Mock Test-ProbeRunning { $true }
        $w = & $script:WaitFor -Start 0.3
        $w.Started | Should -BeFalse
        $w.Finished | Should -BeFalse
        Should -Invoke Test-ProbeRunning -Times 0 -Exactly -Because 'a probe that has not started has not exited either'
    }
}

Describe 'wt-live: what the probe records of a command' {
    BeforeAll {
        $script:Cfg = [pscustomobject]@{ PreviewSettings = 'C:\nowhere\settings.json'; StableSettings = 'C:\nowhere\s.json'; StyleName = 'eva' }
    }
    BeforeEach {
        Mock Get-BothSettingsFacts { [pscustomobject]@{ Stable = $null; Preview = $null } }
        Mock Wait-FileQuiet { [pscustomobject]@{ Settled = $true; Sha256 = $null; Changes = 0; Exists = $false } }
    }

    It 'keeps what the command writes to the pipeline out of its own result' {
        Mock Invoke-TerminalStyle { 'stray line'; 42 }
        $step = @(Invoke-ProbeCommand -Argument 'eva' -Config $script:Cfg -Module 'unused' -ProfileGuid 'g')
        $step.Count | Should -Be 1 -Because 'result.Apply has to stay one object'
        $step[0].Command | Should -Be 'tstyles eva'
        (@($step[0].PipelineOutput) -join '|') | Should -Be 'stray line|42'
        $step[0].Threw | Should -BeNullOrEmpty
    }

    It 'records an error the command stopped on' {
        Mock Invoke-TerminalStyle { throw 'boom' }
        $step = @(Invoke-ProbeCommand -Argument 'reset' -Config $script:Cfg -Module 'unused' -ProfileGuid 'g')
        $step.Count | Should -Be 1
        $step[0].Threw | Should -Be 'boom'
        @($step[0].PipelineOutput).Count | Should -Be 0
    }
}

Describe 'wt-live: the probe puts the style''s background on disk' {
    It 'seeds the cache in the sandbox, and the module then fetches nothing' {
        $m = Get-Module TerminalStyles
        $saved = & $m { $script:TStylesDataRoot }
        $root = Join-Path $TestDrive 'data'
        try {
            & $m { param($r) $script:TStylesDataRoot = $r } $root
            $b = Initialize-ProbeBackground -Module $m -StyleName 'eva'
            $b.Error | Should -BeNullOrEmpty
            $b.Path | Should -Be (Join-Path (Join-Path (Join-Path $root 'cache') 'eva') 'background.gif')
            [System.IO.File]::ReadAllBytes($b.Path).Length | Should -Be 43
            $b.RefreshDue | Should -BeFalse -Because 'the module reads the marker as fresh'

            # The module's own resolver, with the network out of reach: a style
            # folder named eva with no image of its own, as the checkout's is.
            Mock -ModuleName TerminalStyles Invoke-WebRequest { throw 'the apply reached the network' }
            $style = Join-Path (Join-Path $TestDrive 'styles') 'eva'
            $null = New-Item -ItemType Directory -Force -Path $style
            & $m { param($d) Get-StyleBundledBackground -StyleDir $d } $style | Should -Be $b.Path
            Should -Invoke -ModuleName TerminalStyles Invoke-WebRequest -Times 0 -Exactly
        } finally {
            & $m { param($r) $script:TStylesDataRoot = $r } $saved
        }
    }

    It 'says why when the cache cannot be written' {
        $m = Get-Module TerminalStyles
        $saved = & $m { $script:TStylesDataRoot }
        # A file where the data root's folder should be.
        $blocker = Join-Path $TestDrive 'blocked'
        [System.IO.File]::WriteAllText($blocker, 'x')
        try {
            & $m { param($r) $script:TStylesDataRoot = $r } $blocker
            $b = Initialize-ProbeBackground -Module $m -StyleName 'eva'
            $b.Error | Should -Not -BeNullOrEmpty
            $b.Path | Should -BeNullOrEmpty
        } finally {
            & $m { param($r) $script:TStylesDataRoot = $r } $saved
        }
    }
}

Describe 'wt-live: the readers the verdicts trust' {
    It 'reads a settings.json the way the check asks of it' {
        $path = Join-Path $TestDrive 'settings.json'
        [System.IO.File]::WriteAllText($path, @'
// Windows Terminal writes comments and trailing commas; the module's reader takes both.
{
    "profiles": {
        "defaults": {},
        "list": [
            { "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell", "colorScheme": "eva", },
            { "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}", "name": "Command Prompt" }
        ]
    },
    "schemes": [ { "name": "eva", "background": "#0a0006" } ]
}
'@, (New-Object System.Text.UTF8Encoding($false)))
        $f = Get-SettingsFacts -Path $path -Module (Get-Module TerminalStyles) -ProfileGuid '{61C54BBD-C2C6-5271-96E7-009A87FF44BF}' -SchemeName 'eva'
        $f.Exists | Should -BeTrue
        $f.Parsed | Should -BeTrue
        $f.HasScheme | Should -BeTrue
        $f.TextHasScheme | Should -BeTrue
        $f.ProfileFound | Should -BeTrue -Because 'GUIDs compare without regard to case'
        $f.ProfileName | Should -Be 'Windows PowerShell'
        $f.ProfileColorScheme | Should -BeExactly 'eva'
        $f.Sha256 | Should -BeExactly ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())
    }

    It 'does not take a scheme in another case for the style''s' {
        $path = Join-Path $TestDrive 'upper.json'
        [System.IO.File]::WriteAllText($path, '{ "profiles": { "list": [] }, "schemes": [ { "name": "EVA" } ] }', (New-Object System.Text.UTF8Encoding($false)))
        $f = Get-SettingsFacts -Path $path -Module (Get-Module TerminalStyles) -ProfileGuid '' -SchemeName 'eva'
        $f.HasScheme | Should -BeFalse
        $f.TextHasScheme | Should -BeFalse
        $f.ProfileFound | Should -BeFalse
    }

    It 'says a missing file is missing, with no hash to compare' {
        $f = Get-SettingsFacts -Path (Join-Path $TestDrive 'nope.json') -Module (Get-Module TerminalStyles) -ProfileGuid '' -SchemeName 'eva'
        $f.Exists | Should -BeFalse
        $f.Sha256 | Should -BeNullOrEmpty
        (Get-FileFacts -Path (Join-Path $TestDrive 'nope.json')).Exists | Should -BeFalse
    }

    It 'joins Write-Host -NoNewline output back into the line it printed' {
        function script:Write-TwoParts { [CmdletBinding()] param() Write-Host '  Style applied: ' -NoNewline; Write-Host 'eva'; Write-Host 'next' }
        $iv = $null
        Write-TwoParts -InformationVariable iv 6>$null
        ConvertTo-HostText -Records $iv | Should -BeExactly "  Style applied: eva`nnext`n"
    }

    It 'runs the old lookup''s own body, lifted out of its file' {
        $old = Join-Path $TestDrive 'old-tstyles.ps1'
        [System.IO.File]::WriteAllText($old, "function Other { 'x' }`nfunction Find-WTSettingsPath {`n    if (`$env:WT_LIVE_TEST_NEVER_SET) { return 'env' }`n    return 'C:\first\settings.json'`n}`n",
                                       (New-Object System.Text.UTF8Encoding($false)))
        $r = Get-Pre120Lookup -Path $old
        $r.Error | Should -BeNullOrEmpty
        $r.Path | Should -BeExactly 'C:\first\settings.json'
        $none = Join-Path $TestDrive 'no-lookup.ps1'
        [System.IO.File]::WriteAllText($none, "function Other { 'x' }`n", (New-Object System.Text.UTF8Encoding($false)))
        (Get-Pre120Lookup -Path $none).Error | Should -Match 'defines no Find-WTSettingsPath'
        (Get-Pre120Lookup -Path '').Error | Should -Match 'no pre-#120'
    }

    It 'walks a process table up to its root, and stops at a reused parent ID or a cycle' {
        $t = [datetime]::new(2026, 10, 23, 9, 0, 0, [System.DateTimeKind]::Utc)
        $row = { param($id, $parent, $name, $minutes) [pscustomobject]@{ ProcessId = $id; ParentProcessId = $parent; Name = $name; ExecutablePath = "C:\$name"; CreationDate = $t.AddMinutes($minutes) } }
        $table = @{ 30 = (& $row 30 20 'pwsh.exe' 3); 20 = (& $row 20 10 'WindowsTerminal.exe' 2); 10 = (& $row 10 4 'explorer.exe' 1) }
        @(Get-ProcessChain -StartId 30 -Table $table | ForEach-Object { $_.Name }) -join ',' | Should -Be 'pwsh.exe,WindowsTerminal.exe,explorer.exe'
        $table[10] = & $row 10 4 'explorer.exe' 9
        @(Get-ProcessChain -StartId 30 -Table $table | ForEach-Object { $_.Name }) -join ',' |
            Should -Be 'pwsh.exe,WindowsTerminal.exe' -Because 'a parent younger than its child holds a reused ID'
        $table[10] = & $row 10 30 'explorer.exe' 1
        @(Get-ProcessChain -StartId 30 -Table $table).Count | Should -Be 3 -Because 'the walk stops when it comes back round'
    }

    It 'settles on a file that does not change, and on a missing one only with Exists false' {
        $path = Join-Path $TestDrive 'quiet.txt'
        [System.IO.File]::WriteAllText($path, 'x')
        $q = Wait-FileQuiet -Path $path -QuietSeconds 0.3 -TimeoutSeconds 5 -IntervalMs 100
        $q.Settled | Should -BeTrue
        $q.Changes | Should -Be 0
        $q.Sha256 | Should -Not -BeNullOrEmpty
        $m = Wait-FileQuiet -Path (Join-Path $TestDrive 'absent.txt') -QuietSeconds 0.3 -TimeoutSeconds 5 -IntervalMs 100
        $m.Exists | Should -BeFalse -Because 'a missing file is "quiet" too, so callers must ask Exists'
        $m.Sha256 | Should -BeNullOrEmpty
    }
}

Describe 'wt-live: what the installer reads out of a bundle' {
    It 'reads the x64 package''s own manifest from inside the bundle' {
        $x64 = & $script:NewZipBytes @{ 'AppxManifest.xml' = (& $script:Manifest 'Microsoft.WindowsTerminalPreview' 'x64' '8.2305.5001.0') }
        $x86 = & $script:NewZipBytes @{ 'AppxManifest.xml' = (& $script:Manifest 'Wrong.Package' 'x86' '1.0.0.0') }
        $bundleXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle">
  <Identity Name="Microsoft.WindowsTerminalPreview" Publisher="CN=Microsoft Corporation" Version="3001.9.9.0"/>
  <Packages>
    <Package Type="application" Version="9.9.9.0" Architecture="x86" FileName="CascadiaPackage_9.9.9.0_x86.msix"/>
    <Package Type="application" Version="9.9.9.0" Architecture="x64" FileName="CascadiaPackage_9.9.9.0_x64.msix"/>
  </Packages>
</Bundle>
'@
        $bundle = Join-Path $TestDrive 'test.msixbundle'
        [System.IO.File]::WriteAllBytes($bundle, (& $script:NewZipBytes @{
            'AppxMetadata/AppxBundleManifest.xml' = $bundleXml
            'CascadiaPackage_9.9.9.0_x64.msix'    = $x64
            'CascadiaPackage_9.9.9.0_x86.msix'    = $x86
        }))
        $info = Get-BundlePackageInfo -BundlePath $bundle -Architecture 'x64'
        $info.Name | Should -Be 'Microsoft.WindowsTerminalPreview'
        $info.Architecture | Should -Be 'x64'
        @($info.Dependencies).Count | Should -Be 1 -Because 'TargetDeviceFamily is not a package'
        $info.Dependencies[0].Name | Should -Be 'Microsoft.UI.Xaml.2.8'
        $info.Dependencies[0].MinVersion | Should -Be '8.2305.5001.0'
    }

    It 'refuses a bundle that does not name exactly one x64 package it holds' {
        $empty = Join-Path $TestDrive 'none.msixbundle'
        [System.IO.File]::WriteAllBytes($empty, (& $script:NewZipBytes @{
            'AppxMetadata/AppxBundleManifest.xml' = '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle"><Packages><Package Type="application" Architecture="x86" FileName="a.msix"/></Packages></Bundle>'
        }))
        { Get-BundlePackageInfo -BundlePath $empty -Architecture 'x64' } | Should -Throw '*0 x64 application packages*'
        $hollow = Join-Path $TestDrive 'hollow.msixbundle'
        [System.IO.File]::WriteAllBytes($hollow, (& $script:NewZipBytes @{
            'AppxMetadata/AppxBundleManifest.xml' = '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle"><Packages><Package Type="application" Architecture="x64" FileName="gone.msix"/></Packages></Bundle>'
        }))
        { Get-BundlePackageInfo -BundlePath $hollow -Architecture 'x64' } | Should -Throw '*does not hold it*'
    }

    It 'takes a framework only at the same name, x64, and at least the minimum version' {
        $dep = [pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; MinVersion = '8.2305.5001.0' }
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; Version = '8.2511.26001.0'; Architecture = 'X64' }) -Dependency $dep | Should -BeTrue
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; Version = '8.2305.5001.0'; Architecture = 'x64' }) -Dependency $dep | Should -BeTrue
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; Version = '8.2305.4999.0'; Architecture = 'X64' }) -Dependency $dep | Should -BeFalse
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; Version = '8.2511.26001.0'; Architecture = 'X86' }) -Dependency $dep | Should -BeFalse
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.7'; Version = '9.0.0.0'; Architecture = 'X64' }) -Dependency $dep | Should -BeFalse
        Test-FrameworkSatisfies -Package ([pscustomobject]@{ Name = 'Microsoft.UI.Xaml.2.8'; Version = '8.300.0.0'; Architecture = 'X64' }) -Dependency $dep |
            Should -BeFalse -Because 'as versions 8.300 is below 8.2305; as text it would sort above it'
    }
}
