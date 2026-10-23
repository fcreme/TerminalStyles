# wt-live-check.ps1 -- opens a real Windows Terminal Preview tab on a runner
# where Stable is installed too, runs scripts/wt-live-probe.ps1 inside it under
# the engine under test, and judges what it reports.
#
# Run by .github/workflows/wt-live-spike.yml after scripts/wt-live-install.ps1.
# What it is for: Find-WTSettingsPath (PR #120) decides which build's
# settings.json to edit by walking the process tree up to the nearest
# WindowsTerminal.exe and mapping its install folder to that build's
# settings.json. Its tests mock the tree. Here the tree is real: a Preview tab
# whose shell is Preview's own child, Stable's settings.json present beside
# Preview's -- the case that, before #120, wrote Stable's file -- and an apply
# and a reset that go through the module's real write path.
#
# Each check is one claim with its own verdict function below, and every
# verdict refuses to pass on a missing reading: two absent hashes are equal,
# and equal proves nothing. tests/WT-Live-Check.Tests.ps1 pins them.
#
# The tab is opened one of two ways (-Launch): 'alias', Preview's own
# per-package execution alias started with CreateProcess, as a user's `wt`
# would; or 'activate', IApplicationActivationManager::ActivateApplication on
# Preview's AppUserModelId. The bare wt.exe is never used: both builds claim it.
#
# NOT FOR A MACHINE ANYONE USES: the probe applies a style to the tab's profile
# and resets it. This refuses to start anywhere but a GitHub-hosted runner.
[CmdletBinding()]
param(
    # The shell the tab runs: 'powershell' (Windows PowerShell 5.1) or 'pwsh'.
    [string]$Engine = $env:WT_LIVE_ENGINE,
    # How the tab is opened: 'alias' or 'activate'.
    [string]$Launch = $env:WT_LIVE_LAUNCH,
    # tstyles.ps1 as it was before #120, for the control. The workflow fetches it.
    [string]$Pre120Path,
    # Where the config, the probe's output and the evidence go. Default:
    # wt-live under the runner's temp folder, which the workflow uploads.
    [string]$RunRoot,
    [int]$StartTimeoutSeconds = 120,
    [int]$ResultTimeoutSeconds = 300
)

. (Join-Path $PSScriptRoot 'wt-live-common.ps1')

$script:StyleName = 'eva'
$script:StableName = 'Microsoft.WindowsTerminal'
$script:PreviewName = 'Microsoft.WindowsTerminalPreview'

# What a never-launched Stable gets, if it has no settings.json: the two inbox
# profiles, under the GUIDs defaults.json fixes for them in every build.
$script:SeedSettingsJson = @'
{
    "$help": "https://aka.ms/terminal-documentation",
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": {
        "defaults": {},
        "list": [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "hidden": false,
                "name": "Windows PowerShell"
            },
            {
                "commandline": "%SystemRoot%\\System32\\cmd.exe",
                "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}",
                "hidden": false,
                "name": "Command Prompt"
            }
        ]
    },
    "schemes": []
}
'@

function Get-PackagedSettingsPath {
    # Where a packaged build keeps settings.json: %LOCALAPPDATA%\Packages\<family>\LocalState.
    param([Parameter(Mandatory)][string]$LocalAppData, [Parameter(Mandatory)][string]$FamilyName)
    Join-Path (Join-Path (Join-Path (Join-Path $LocalAppData 'Packages') $FamilyName) 'LocalState') 'settings.json'
}

function Get-ProbeProfileName {
    # The profile the tab opens in, so WT_PROFILE_ID names one the engine
    # belongs to: the inbox Windows PowerShell one, or the generated PowerShell one.
    param([Parameter(Mandatory)][string]$Engine)
    if ($Engine -eq 'powershell') { return 'Windows PowerShell' }
    return 'PowerShell'
}

function Get-WTArgumentString {
    # The command line handed to Windows Terminal: a new window with one tab,
    # the engine under test running the probe. WT splits its arguments on ';'
    # and joins the tab's command line back together with spaces, quoting only
    # an argument that contains one, and escaping nothing (AppCommandlineArgs.cpp).
    # So the probe's own paths may hold no whitespace, ';' or '"', and the
    # engine's path no ';' or '"'. '--' ends WT's options: everything after it
    # is the tab's command line.
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$EnginePath,
        [Parameter(Mandatory)][string]$ProbePath,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    foreach ($p in @($ProbePath, $ConfigPath)) {
        if ($p -match '[\s;"]') { throw "Windows Terminal would split or mangle the path '$p'; the probe needs one without whitespace, ';' or '""'" }
    }
    if ($EnginePath -match '[;"]') { throw "Windows Terminal would split or mangle the engine path '$EnginePath'" }
    if ($ProfileName -match '[;"]') { throw "Windows Terminal would split or mangle the profile name '$ProfileName'" }
    $engineArg = $EnginePath
    if ($EnginePath -match '\s') { $engineArg = '"' + $EnginePath + '"' }
    return ('-w new new-tab -p "{0}" -- {1} -NoProfile -NonInteractive -ExecutionPolicy Bypass -File {2} -ConfigPath {3}' -f
            $ProfileName, $engineArg, $ProbePath, $ConfigPath)
}

function Get-ActivationErrorText {
    # A name for the ActivateApplication HRESULTs that explain themselves (winerror.h).
    param([int]$HResult)
    $hex = '0x{0:X8}' -f $HResult
    $names = @{
        '0x80270250' = 'E_MONITOR_RESOLUTION_TOO_LOW'
        '0x80270251' = 'E_ELEVATED_ACTIVATION_NOT_SUPPORTED: cannot be activated from an elevated context'
        '0x80270252' = 'E_UAC_DISABLED'
        '0x80270253' = 'E_FULL_ADMIN_NOT_SUPPORTED: not as the built-in Administrator'
        '0x80270254' = 'E_APPLICATION_NOT_REGISTERED'
        '0x80270257' = 'E_APPLICATION_MANAGER_NOT_RUNNING'
        '0x8027025A' = 'activation timed out'
        '0x8027025B' = 'activation failed to start the process'
    }
    if ($names.ContainsKey($hex)) { return "$hex $($names[$hex])" }
    return $hex
}

# --- Verdicts. Each returns $null when its claim held, or why it did not. ---

function Get-PackagesVerdict {
    # Both builds registered for this user, once each.
    param($Stable, $Preview)
    $s = @($Stable | Where-Object { $null -ne $_ })
    $p = @($Preview | Where-Object { $null -ne $_ })
    if ($s.Count -ne 1) { return "Stable ($script:StableName) is registered $($s.Count) times for this user, not once" }
    if ($p.Count -ne 1) { return "Preview ($script:PreviewName) is registered $($p.Count) times for this user, not once" }
    if (-not "$($s[0].InstallLocation)") { return 'Stable is registered with no InstallLocation' }
    if (-not "$($p[0].InstallLocation)") { return 'Preview is registered with no InstallLocation' }
    return $null
}

function Get-SettingsVerdict {
    # Both settings.json files exist before the tab opens, Stable's has stopped
    # changing, and both read. Without Stable's, the old Stable-first lookup and
    # the fix pick the same file, and the run could not tell them apart.
    param($Stable, $Preview, $StableQuiet)
    if (-not $Stable -or -not $Stable.Exists) { return "Stable's settings.json is missing; without it nothing here tells the old Stable-first lookup from the fix" }
    if (-not "$($Stable.Sha256)") { return "Stable's settings.json is there but could not be read" }
    if ($StableQuiet -and -not $StableQuiet.Settled) { return "Stable's settings.json kept changing ($($StableQuiet.Changes) rewrites while waiting): something rewrites it, so its byte-identity cannot be measured" }
    if (-not $Preview -or -not $Preview.Exists) { return "Preview's settings.json is missing" }
    if (-not "$($Preview.Sha256)") { return "Preview's settings.json is there but could not be read" }
    return $null
}

function Get-TabVerdict {
    # The result came from the tab this run opened, under the engine under test,
    # running the checked-out module in a session the module takes for a
    # Windows Terminal tab.
    param($Result, [string]$Nonce, [string]$Engine, [string]$Workspace)
    if ($null -eq $Result) { return 'no result from the tab' }
    if (-not $Nonce -or "$($Result.Nonce)" -ne $Nonce) { return "the result belongs to another run (nonce '$($Result.Nonce)', expected '$Nonce')" }
    $fatal = @($Result.Errors | Where-Object { $_ })
    if ($fatal.Count -gt 0) { return "the probe failed: $($fatal -join '; ')" }
    # Every prompt on this path is meant to be held back; one that was reached
    # was refused unanswered, and what followed it is not the user's path.
    $asked = @($Result.Prompts | Where-Object { $_ })
    if ($asked.Count -gt 0) { return "a prompt was reached in the tab, and refused unanswered: $($asked -join '; ')" }
    $edition = 'Core'
    if ($Engine -eq 'powershell') { $edition = 'Desktop' }
    if ("$($Result.PSEdition)" -ne $edition) { return "the tab ran PowerShell $($Result.PSEdition) $($Result.PSVersion), not $Engine" }
    if (-not "$($Result.Env.WT_SESSION)") { return 'the tab''s shell has no WT_SESSION: Windows Terminal did not start it as a tab' }
    if (-not "$($Result.Env.WT_PROFILE_ID)") { return 'the tab''s shell has no WT_PROFILE_ID, so no profile to apply a style to' }
    if (-not $Result.Module -or -not (Test-SamePath $Result.Module.ModuleBase $Workspace)) { return "the tab loaded TerminalStyles from '$($Result.Module.ModuleBase)', not the checkout at $Workspace" }
    if (-not $Result.Module.Sandboxed) { return "the module's data root was not moved to the sandbox (it is '$($Result.Module.DataRoot)')" }
    if ("$($Result.TerminalKind)" -ne 'WindowsTerminal') { return "the module took the tab for '$($Result.TerminalKind)', not a Windows Terminal tab (TERM_PROGRAM='$($Result.Env.TERM_PROGRAM)')" }
    return $null
}

function Get-HostVerdict {
    # The tab's nearest WindowsTerminal.exe ancestor is Preview's, and
    # Find-WTHostExePath -- the module's own walk -- names the same one.
    param($Result, [string]$PreviewInstallLocation)
    $hostRec = $Result.NearestHost
    if ($null -eq $hostRec -or -not "$($hostRec.ExecutablePath)") {
        $names = @($Result.Chain | ForEach-Object { "$($_.Name)" }) -join ' <- '
        if ($Result.ChainError) { return "the tab could not read its process tree: $($Result.ChainError)" }
        return "no WindowsTerminal.exe above the tab's shell (shell and ancestors: $names)"
    }
    if (-not (Test-PathUnder -Path $hostRec.ExecutablePath -Root $PreviewInstallLocation)) {
        return "the tab's nearest WindowsTerminal.exe is $($hostRec.ExecutablePath), which is not under Preview's $PreviewInstallLocation"
    }
    if (-not (Test-SamePath $Result.HostExePath $hostRec.ExecutablePath)) {
        return "Find-WTHostExePath returned '$($Result.HostExePath)', but the tab's nearest WindowsTerminal.exe is $($hostRec.ExecutablePath)"
    }
    return $null
}

function Get-IdentityVerdict {
    # That WindowsTerminal.exe runs AS Preview's package -- package identity,
    # read off the process -- and nothing ran unpackaged: an unpackaged
    # WindowsTerminal.exe keeps its settings in %LOCALAPPDATA%\Microsoft\Windows
    # Terminal, which is where the PR's mapping would then be wrong.
    param($Result, [string]$PreviewPackageFullName, $UnpackagedBefore, $UnpackagedAfter)
    $hostRec = $Result.NearestHost
    if ($null -eq $hostRec) { return 'no WindowsTerminal.exe above the tab''s shell to ask' }
    if (-not "$($hostRec.Package)") {
        $why = "error $($hostRec.PackageError)"
        if ("$($hostRec.PackageError)" -eq '15700') { $why = 'it has no package identity (APPMODEL_ERROR_NO_PACKAGE): it ran unpackaged' }
        return "Windows named no package for WindowsTerminal.exe (pid $($hostRec.ProcessId)): $why"
    }
    if ("$($hostRec.Package)" -ne $PreviewPackageFullName) {
        return "WindowsTerminal.exe (pid $($hostRec.ProcessId)) runs as package $($hostRec.Package), not $PreviewPackageFullName"
    }
    if ($UnpackagedBefore -and $UnpackagedAfter) {
        if (-not $UnpackagedBefore.Exists -and $UnpackagedAfter.Exists) { return "an unpackaged settings.json appeared during the run: $($UnpackagedAfter.Path)" }
        if ($UnpackagedBefore.Exists -and "$($UnpackagedBefore.Sha256)" -ne "$($UnpackagedAfter.Sha256)") { return "the unpackaged settings.json changed during the run: $($UnpackagedAfter.Path)" }
    }
    return $null
}

function Get-LookupVerdict {
    # Find-WTSettingsPath, asked in the tab, named Preview's LocalState
    # settings.json -- while Stable's existed beside it.
    param($Result, [string]$PreviewSettingsPath, [string]$StableSettingsPath)
    $found = @($Result.SettingsPath | Where-Object { $_ })
    $said = @($Result.SettingsPathErrors | Where-Object { $_ })
    if (-not $Result.StableExistedAtLookup) { return "Stable's settings.json was not there when Find-WTSettingsPath ran, so this lookup could not have picked it either way" }
    if ($found.Count -ne 1) {
        $why = ''
        if ($said.Count -gt 0) { $why = ': ' + ($said -join ' ') }
        return "Find-WTSettingsPath returned $($found.Count) paths, not one$why"
    }
    if (Test-SamePath $found[0] $StableSettingsPath) { return "Find-WTSettingsPath returned Stable's settings.json ($StableSettingsPath) in a Preview tab: the bug #120 is meant to fix" }
    if (-not (Test-SamePath $found[0] $PreviewSettingsPath)) { return "Find-WTSettingsPath returned $($found[0]), not Preview's $PreviewSettingsPath" }
    return $null
}

function Get-ControlVerdict {
    # The lookup #120 replaced, run in the same tab, picks Stable's file. If it
    # does not, this tab does not reproduce the bug, and the lookup check passing
    # proves less than it says.
    param($Result, [string]$StableSettingsPath)
    if ($null -eq $Result.Pre120) { return 'the pre-#120 lookup was not run' }
    if ("$($Result.Pre120.Error)") { return "the pre-#120 lookup could not run: $($Result.Pre120.Error)" }
    if (-not (Test-SamePath $Result.Pre120.Path $StableSettingsPath)) {
        return "the pre-#120 lookup returned '$($Result.Pre120.Path)', not Stable's $StableSettingsPath, so this tab does not reproduce the bug"
    }
    return $null
}

function Get-RigVerdict {
    # Stable's settings.json did not change between the launch and the apply,
    # before TerminalStyles wrote anything. If it did, something else on the
    # runner rewrites it, and the byte-identity check measures a moving file.
    param([string]$BaselineSha256, $Result)
    if (-not $BaselineSha256) { return 'no reading of Stable''s settings.json from before the launch' }
    $before = $Result.Before.Stable
    if ($null -eq $before -or -not $before.Exists -or -not "$($before.Sha256)") { return 'the tab could not read Stable''s settings.json before the apply' }
    if ("$($before.Sha256)" -ne $BaselineSha256) {
        return "Stable's settings.json changed between the launch and the apply (sha256 $BaselineSha256 -> $($before.Sha256)), before TerminalStyles wrote anything"
    }
    return $null
}

function Get-StableVerdict {
    # Stable's settings.json stayed byte-identical through the apply and the
    # reset, and after the tab closed. Every reading has to exist and hash, and
    # something has to have been written somewhere: if the apply changed no
    # file at all, Stable's staying the same proves nothing.
    param($Result, $Final, [string]$StyleName)
    $readings = [ordered]@{
        'before the apply'           = $Result.Before.Stable
        'right after the apply'      = $Result.Apply.Immediate.Stable
        'once the apply had settled' = $Result.Apply.Settled.Stable
        'right after the reset'      = $Result.Reset.Immediate.Stable
        'once the reset had settled' = $Result.Reset.Settled.Stable
        'after the tab closed'       = $Final.Stable
    }
    $first = $null
    foreach ($when in $readings.Keys) {
        $r = $readings[$when]
        if ($null -eq $r -or -not $r.Exists) { return "Stable's settings.json was missing $when" }
        if (-not "$($r.Sha256)") { return "Stable's settings.json could not be read $when" }
        if ($null -eq $first) { $first = "$($r.Sha256)"; continue }
        if ("$($r.Sha256)" -ne $first) {
            $what = "Stable's settings.json changed $when (sha256 $first -> $($r.Sha256))"
            if ($r.PSObject.Properties.Match('HasScheme').Count -and $r.HasScheme) { $what += ", and now carries the '$StyleName' scheme: TerminalStyles wrote Stable's file" }
            return $what
        }
    }
    $pb = $Result.Before.Preview
    $pa = $Result.Apply.Settled.Preview
    if ($null -eq $pb -or $null -eq $pa -or -not "$($pb.Sha256)" -or "$($pb.Sha256)" -eq "$($pa.Sha256)") {
        return "not measured: the apply changed neither file, so Stable's staying the same proves nothing"
    }
    return $null
}

function Get-ApplyVerdict {
    # `tstyles <style>` changed Preview's settings.json, which now carries the
    # style's scheme, and gave the tab's own profile its colorScheme.
    param($Result, [string]$StyleName)
    if ($null -eq $Result.Apply) { return 'the apply never ran' }
    $before = $Result.Before.Preview
    $after = $Result.Apply.Settled.Preview
    $tail = ''
    $said = @($Result.Apply.Errors | Where-Object { $_ })
    if ($Result.Apply.Threw) { $said += "threw: $($Result.Apply.Threw)" }
    if ($said.Count -gt 0) { $tail = ' (it said: ' + ($said -join '; ') + ')' }
    if ($null -eq $before -or -not $before.Exists -or -not "$($before.Sha256)") { return "Preview's settings.json could not be read before the apply" }
    if ($null -eq $after -or -not $after.Exists -or -not "$($after.Sha256)") { return "Preview's settings.json could not be read after the apply$tail" }
    if ("$($before.Sha256)" -eq "$($after.Sha256)") { return "Preview's settings.json is byte-identical after tstyles $StyleName$tail" }
    if (-not $after.Parsed) { return "Preview's settings.json does not parse after the apply: $($after.ParseError)" }
    if (-not $after.HasScheme -or -not $after.TextHasScheme) { return "Preview's settings.json changed but carries no '$StyleName' scheme$tail" }
    if (-not $after.ProfileFound) { return "the tab's profile ($($Result.Env.WT_PROFILE_ID)) is not in Preview's settings.json$tail" }
    if ("$($after.ProfileColorScheme)" -cne $StyleName) { return "the tab's profile '$($after.ProfileName)' has colorScheme '$($after.ProfileColorScheme)', not '$StyleName'$tail" }
    return $null
}

function Get-ResetVerdict {
    # `tstyles reset` took the style back out of Preview's settings.json: no
    # scheme, and no colorScheme on the tab's profile. Only after an apply that
    # put them there -- a reset of nothing removes nothing and proves nothing.
    param($Result, [string]$StyleName)
    if ($null -eq $Result.Reset) { return 'the reset never ran' }
    $applied = $Result.Apply.Settled.Preview
    if ($null -eq $applied -or -not $applied.HasScheme) { return "not measured: the apply never put the '$StyleName' scheme in Preview's settings.json, so there was nothing to remove" }
    $after = $Result.Reset.Settled.Preview
    $tail = ''
    $said = @($Result.Reset.Errors | Where-Object { $_ })
    if ($Result.Reset.Threw) { $said += "threw: $($Result.Reset.Threw)" }
    if ($said.Count -gt 0) { $tail = ' (it said: ' + ($said -join '; ') + ')' }
    if ($null -eq $after -or -not $after.Exists -or -not "$($after.Sha256)") { return "Preview's settings.json could not be read after the reset$tail" }
    if ("$($after.Sha256)" -eq "$($applied.Sha256)") { return "Preview's settings.json is byte-identical after tstyles reset$tail" }
    if (-not $after.Parsed) { return "Preview's settings.json does not parse after the reset: $($after.ParseError)" }
    if ($after.HasScheme -or $after.TextHasScheme) { return "Preview's settings.json still carries the '$StyleName' scheme after tstyles reset$tail" }
    if ("$($after.ProfileColorScheme)" -ceq $StyleName) { return "the tab's profile still has colorScheme '$StyleName' after tstyles reset$tail" }
    return $null
}

# --- Reporting, in the shape of scripts/live-gallery-check.ps1. ---

function Add-Result {
    [CmdletBinding()]
    param(
        [System.Collections.ArrayList]$Results,
        [Parameter(Mandatory)][string]$Step,
        [string]$Failure,
        [string]$Detail
    )
    $ok = -not $Failure
    $text = $Detail
    if (-not $ok) { $text = $Failure }
    $null = $Results.Add([pscustomobject]@{ Step = $Step; Ok = $ok; Text = $text })
    if (-not $ok) { Write-Host ('::error title=WT live check: {0}::{1}' -f $Step, ($Failure -replace '\r?\n', ' ')) }
}

function Complete-Run {
    # Prints the checks and the facts, adds both to the job's summary page, and
    # returns the exit code: 1 when any check failed.
    [CmdletBinding()]
    param(
        [System.Collections.ArrayList]$Results,
        [Parameter(Mandatory)][string]$Title,
        [System.Collections.Specialized.OrderedDictionary]$Facts
    )
    Write-Host ''
    Write-Host $Title
    foreach ($r in $Results) {
        Write-Host ('  {0}  {1,-9} {2}' -f $(if ($r.Ok) { 'PASS' } else { 'FAIL' }), $r.Step, $r.Text)
    }
    if ($Facts) {
        Write-Host ''
        foreach ($k in $Facts.Keys) { Write-Host ('  {0,-22} {1}' -f $k, $Facts[$k]) }
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $md = New-Object System.Collections.Generic.List[string]
        $md.Add("### $Title")
        $md.Add('')
        $md.Add('| | Check | What happened |')
        $md.Add('|---|---|---|')
        foreach ($r in $Results) {
            $md.Add(('| {0} | {1} | {2} |' -f $(if ($r.Ok) { 'pass' } else { '**FAIL**' }), $r.Step, ($r.Text -replace '\|', '\|' -replace '\r?\n', ' ')))
        }
        if ($Facts) {
            $md.Add('')
            $md.Add('| Fact | |')
            $md.Add('|---|---|')
            foreach ($k in $Facts.Keys) { $md.Add(('| {0} | {1} |' -f $k, ("$($Facts[$k])" -replace '\|', '\|' -replace '\r?\n', ' '))) }
        }
        $md.Add('')
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $md -Encoding ASCII
    }
    if (@($Results | Where-Object { -not $_.Ok }).Count -gt 0) { return 1 }
    return 0
}

# --- The runner, the launch, and the evidence. ---

function Get-TerminalProcess {
    # Every running WindowsTerminal.exe: { ProcessId; ExecutablePath; Created; Package }.
    $rows = @()
    foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'WindowsTerminal.exe'" -ErrorAction SilentlyContinue)) {
        $pkg = Get-ProcessPackageName -ProcessId ([int]$p.ProcessId)
        $rows += [pscustomobject]@{
            ProcessId      = [int]$p.ProcessId
            ExecutablePath = [string]$p.ExecutablePath
            Created        = Format-Utc $p.CreationDate
            Package        = $pkg.Name
        }
    }
    return $rows
}

function Get-RunnerFacts {
    # What this job runs as and on, for the record. Nothing here is judged.
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $chain = @()
    try { $chain = @(Get-ProcessChain -StartId $PID) } catch { }
    $delegation = [ordered]@{ DelegationConsole = $null; DelegationTerminal = $null }
    try {
        $d = Get-ItemProperty -LiteralPath 'HKCU:\Console\%%Startup' -ErrorAction Stop
        $delegation.DelegationConsole = "$($d.DelegationConsole)"
        $delegation.DelegationTerminal = "$($d.DelegationTerminal)"
    } catch { }
    $xaml = @(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -PackageTypeFilter Framework -ErrorAction SilentlyContinue |
        ForEach-Object { '{0} {1}' -f $_.Version, $_.Architecture })
    return [ordered]@{
        ImageOS              = $env:ImageOS
        ImageVersion         = $env:ImageVersion
        OSVersion            = [Environment]::OSVersion.VersionString
        User                 = $identity.Name
        UserSid              = $identity.User.Value
        BuiltInAdministrator = $identity.User.Value.EndsWith('-500')
        Elevated             = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        SessionId            = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
        UserInteractive      = [Environment]::UserInteractive
        StepChain            = $chain
        Terminals            = @(Get-TerminalProcess)
        DefaultTerminal      = $delegation
        XamlFrameworks       = $xaml
    }
}

function Initialize-SettingsFile {
    # Makes sure both builds have a settings.json before the tab opens: a build
    # that has never run has none, and Windows Terminal writes one on its first
    # launch only. Stable's is seeded with the two inbox profiles if missing;
    # Preview's, if missing, with Stable's bytes -- what Preview's own first run
    # starts from (it reads Stable's file and writes its own), so both carry the
    # same profile GUIDs, which is the bug's precondition. Then waits for
    # Stable's to stop changing: the Stable already running on the runner
    # rewrites its own file when it changes.
    param([Parameter(Mandatory)][string]$StablePath, [Parameter(Mandatory)][string]$PreviewPath)
    $out = [ordered]@{ StableSeeded = $false; PreviewSeeded = $false; StableQuiet = $null; Stable = $null; Preview = $null }
    if (-not [System.IO.File]::Exists($StablePath)) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StablePath)
        [System.IO.File]::WriteAllText($StablePath, $script:SeedSettingsJson, (New-Object System.Text.UTF8Encoding($false)))
        $out.StableSeeded = $true
    }
    $out.StableQuiet = Wait-FileQuiet -Path $StablePath -QuietSeconds 5 -TimeoutSeconds 60
    if (-not [System.IO.File]::Exists($PreviewPath)) {
        $bytes = Read-SharedBytes -Path $StablePath
        if ($null -ne $bytes) {
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PreviewPath)
            [System.IO.File]::WriteAllBytes($PreviewPath, $bytes)
            $out.PreviewSeeded = $true
        }
    }
    $out.Stable = Get-FileFacts -Path $StablePath
    $out.Preview = Get-FileFacts -Path $PreviewPath
    return [pscustomobject]$out
}

function Start-PreviewTab {
    # Opens the Preview tab. Returns { Ok; Detail }.
    param(
        [Parameter(Mandatory)][string]$Launch,
        [Parameter(Mandatory)][string]$FamilyName,
        [Parameter(Mandatory)][string]$Arguments
    )
    if ($Launch -eq 'alias') {
        # Preview's own alias, which names the build; the bare wt.exe beside it
        # belongs to whichever build claimed it first.
        $alias = Join-Path $env:LOCALAPPDATA ('Microsoft\WindowsApps\{0}\wt.exe' -f $FamilyName)
        # An execution alias is a zero-byte reparse point; ask both ways.
        if (-not (Wait-Until -Condition { [System.IO.File]::Exists($alias) -or (Test-Path -LiteralPath $alias) } -TimeoutSeconds 60)) {
            return [pscustomobject]@{ Ok = $false; Detail = "Preview's own execution alias never appeared: $alias" }
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $alias
        $psi.Arguments = $Arguments
        # CreateProcess, as a shell runs `wt`, rather than ShellExecute.
        $psi.UseShellExecute = $false
        # A tab given a command line inherits the environment of whoever ran
        # wt. Nothing may answer for the process tree, and PowerShell 7 must
        # not inherit Windows PowerShell's module path.
        foreach ($name in @('TSTYLES_WT_SETTINGS', 'WT_SESSION', 'WT_PROFILE_ID', 'WT_SETTINGS_DIR', 'PSModulePath')) {
            if ($psi.EnvironmentVariables.ContainsKey($name)) { $psi.EnvironmentVariables.Remove($name) }
        }
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
            return [pscustomobject]@{ Ok = $true; Detail = "started $alias (pid $($p.Id))" }
        } catch {
            return [pscustomobject]@{ Ok = $false; Detail = "could not start ${alias}: $($_.Exception.Message)" }
        }
    }
    $aumid = '{0}!App' -f $FamilyName
    try {
        Initialize-WtLiveNative
        $activatedPid = [uint32]0
        # 2 = AO_NOERRORUI: fail with an HRESULT rather than a dialog nobody can close.
        $hr = [WtLive.Native]::Activate($aumid, $Arguments, 2, [ref]$activatedPid)
        if ($hr -ne 0) {
            return [pscustomobject]@{ Ok = $false; Detail = "ActivateApplication($aumid) failed: $(Get-ActivationErrorText -HResult $hr)" }
        }
        return [pscustomobject]@{ Ok = $true; Detail = "activated $aumid (pid $activatedPid)" }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = "ActivateApplication($aumid) threw: $($_.Exception.Message)" }
    }
}

function Save-ProcessList {
    # Every process, as JSON. Command lines only for Windows Terminal's own and
    # for processes running this check's files, which are what the evidence
    # needs; a runner's other command lines are none of its business.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Marker)
    try {
        $rows = @()
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) {
            $cmd = [string]$p.CommandLine
            $keep = ([string]$p.Name -match '^(WindowsTerminal|wt|OpenConsole)\.exe$') -or
                    ($cmd.IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            $rows += [pscustomobject]@{
                ProcessId       = [int]$p.ProcessId
                ParentProcessId = [int]$p.ParentProcessId
                Name            = [string]$p.Name
                ExecutablePath  = [string]$p.ExecutablePath
                SessionId       = [int]$p.SessionId
                Created         = Format-Utc $p.CreationDate
                CommandLine     = $(if ($keep) { $cmd } else { $null })
            }
        }
        Write-JsonAtomic -Path $Path -InputObject $rows
    } catch {
        Write-Host "process list not saved: $($_.Exception.Message)"
    }
}

function Save-TerminalEvents {
    # Application and app-model events since the launch that mention Windows
    # Terminal or its XAML: an elevated Terminal crashing in Windows.UI.Xaml.dll
    # (0xc000027b) is an open upstream issue, and this is where it would show.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][datetime]$Since)
    $rows = @()
    foreach ($log in @('Application', 'Microsoft-Windows-AppModel-Runtime/Admin')) {
        try {
            foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $Since } -ErrorAction Stop)) {
                if ("$($e.Message)" -notmatch 'WindowsTerminal|OpenConsole|Xaml') { continue }
                $rows += [pscustomobject]@{
                    Log      = $log
                    Time     = Format-Utc $e.TimeCreated
                    Id       = $e.Id
                    Provider = $e.ProviderName
                    Level    = $e.LevelDisplayName
                    Message  = "$($e.Message)"
                }
            }
        } catch { }
    }
    try { Write-JsonAtomic -Path $Path -InputObject $rows } catch { }
}

function Stop-NewTerminal {
    # Stops what this check started and nothing else: WindowsTerminal.exe
    # processes that were not running before the launch, and a probe still
    # running. The Stable Terminal hosting the runner's own console was running
    # before the launch, so it is never touched. Returns what was stopped.
    param([int[]]$Before = @(), [Parameter(Mandatory)][string]$Marker)
    $stopped = @()
    foreach ($p in @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)) {
        $id = [int]$p.ProcessId
        $isNewTerminal = ([string]$p.Name -eq 'WindowsTerminal.exe') -and ($Before -notcontains $id)
        $isProbe = ([string]$p.Name -match '^(powershell|pwsh)\.exe$') -and $id -ne $PID -and
                   ([string]$p.CommandLine).IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        if (-not ($isNewTerminal -or $isProbe)) { continue }
        try {
            Stop-Process -Id $id -Force -ErrorAction Stop
            $stopped += ('{0} (pid {1}) {2}' -f $p.Name, $id, $p.ExecutablePath)
        } catch { }
    }
    return $stopped
}

function Show-ProbeTranscript {
    # The end of the probe's transcript, in the job log, when something failed:
    # the log is read first, the uploaded evidence second.
    param([Parameter(Mandatory)][string]$Path, [int]$Tail = 80)
    if (-not [System.IO.File]::Exists($Path)) { return }
    Write-Host "::group::Probe transcript, last $Tail lines"
    try { Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction Stop | ForEach-Object { Write-Host $_ } } catch { Write-Host "(could not read it: $($_.Exception.Message))" }
    Write-Host '::endgroup::'
}

function Invoke-WTLiveCheck {
    # The whole check. Returns the exit code -- 0 when every check passed, 1
    # when one failed, 2 when it refused to start -- and nothing else.
    [CmdletBinding()]
    param(
        [string]$Engine,
        [string]$Launch,
        [string]$Pre120Path,
        [string]$RunRoot,
        [int]$StartTimeoutSeconds = 120,
        [int]$ResultTimeoutSeconds = 300
    )
    if (-not (Test-GitHubHostedRunner)) {
        Write-Host 'wt-live-check.ps1 runs only on a GitHub-hosted runner. Its probe applies a'
        Write-Host 'style to a Windows Terminal profile and resets it -- here, yours.'
        return 2
    }

    $results = New-Object System.Collections.ArrayList
    $facts = [ordered]@{}
    $title = 'Windows Terminal Preview tab: {0}, opened by {1}' -f $Engine, $Launch
    if (@('powershell', 'pwsh') -notcontains $Engine -or @('alias', 'activate') -notcontains $Launch) {
        Add-Result -Results $results -Step 'setup' -Failure "unknown -Engine '$Engine' or -Launch '$Launch'"
        return (Complete-Run -Results $results -Title $title)
    }

    $repoRoot = Split-Path -Parent $PSScriptRoot
    if (-not $RunRoot) { $RunRoot = Join-Path $env:RUNNER_TEMP 'wt-live' }
    if (Test-Path -LiteralPath $RunRoot) { Remove-Item -LiteralPath $RunRoot -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $RunRoot
    # Outside the uploaded folder: the style's background image lands in it.
    $sandbox = Join-Path $env:RUNNER_TEMP ('wt-live-sandbox-' + $Engine)
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }

    # 0. Where this runs. A tab needs a desktop to open on.
    $runner = Get-RunnerFacts
    try { Write-JsonAtomic -Path (Join-Path $RunRoot 'runner.json') -InputObject $runner } catch { }
    $facts['Runner image'] = '{0} {1}' -f $runner.ImageOS, $runner.ImageVersion
    $facts['Runs as'] = '{0}, elevated: {1}, built-in Administrator: {2}, session {3}' -f $runner.User, $runner.Elevated, $runner.BuiltInAdministrator, $runner.SessionId
    $stepHost = @($runner.StepChain | Where-Object { $_.Name -eq 'WindowsTerminal.exe' }) | Select-Object -First 1
    $facts['This step under a WT'] = $(if ($stepHost) { "yes, $($stepHost.ExecutablePath)" } else { 'no' })
    $facts['WT already running'] = (@($runner.Terminals | ForEach-Object { '{0} pid {1}' -f $_.Package, $_.ProcessId }) -join '; ')
    if (-not $runner.UserInteractive -or $runner.SessionId -eq 0) {
        Add-Result -Results $results -Step 'desktop' -Failure ("this job has no interactive desktop (session {0}, UserInteractive {1}), so no tab can open" -f $runner.SessionId, $runner.UserInteractive)
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }

    # 1. Both builds registered.
    $stable = @(Get-AppxPackage -Name $script:StableName -ErrorAction SilentlyContinue)
    $preview = @(Get-AppxPackage -Name $script:PreviewName -ErrorAction SilentlyContinue)
    $verdict = Get-PackagesVerdict -Stable $stable -Preview $preview
    if ($verdict) {
        Add-Result -Results $results -Step 'packages' -Failure $verdict
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    $stable = $stable[0]
    $preview = $preview[0]
    Add-Result -Results $results -Step 'packages' -Detail ('Stable {0} and Preview {1}, each registered once' -f $stable.Version, $preview.Version)
    $facts['Stable'] = '{0}, at {1}' -f $stable.PackageFullName, $stable.InstallLocation
    $facts['Preview'] = '{0}, at {1}' -f $preview.PackageFullName, $preview.InstallLocation

    # 2. Both settings.json files, seeded where a build never ran.
    $stablePath = Get-PackagedSettingsPath -LocalAppData $env:LOCALAPPDATA -FamilyName $stable.PackageFamilyName
    $previewPath = Get-PackagedSettingsPath -LocalAppData $env:LOCALAPPDATA -FamilyName $preview.PackageFamilyName
    $unpackagedPath = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'Windows Terminal') 'settings.json'
    $seed = Initialize-SettingsFile -StablePath $stablePath -PreviewPath $previewPath
    $unpackagedBefore = Get-FileFacts -Path $unpackagedPath
    $verdict = Get-SettingsVerdict -Stable $seed.Stable -Preview $seed.Preview -StableQuiet $seed.StableQuiet
    $detail = "Stable's {0} ({1}), Preview's {2} ({3})" -f $(if ($seed.StableSeeded) { 'seeded' } else { 'was there' }),
        "$($seed.Stable.Sha256)".Substring(0, [Math]::Min(12, "$($seed.Stable.Sha256)".Length)),
        $(if ($seed.PreviewSeeded) { "seeded from Stable's" } else { 'was there' }),
        "$($seed.Preview.Sha256)".Substring(0, [Math]::Min(12, "$($seed.Preview.Sha256)".Length))
    Add-Result -Results $results -Step 'settings' -Failure $verdict -Detail $detail
    try { Write-JsonAtomic -Path (Join-Path $RunRoot 'before-launch.json') -InputObject ([ordered]@{ Seed = $seed; Unpackaged = $unpackagedBefore }) } catch { }
    if ($verdict) { return (Complete-Run -Results $results -Title $title -Facts $facts) }

    # 3. The engine, the probe's config, and Windows Terminal's command line.
    $enginePath = $null
    if ($Engine -eq 'powershell') {
        $enginePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        $cmd = Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $enginePath = $cmd.Path }
    }
    if (-not $enginePath -or -not [System.IO.File]::Exists($enginePath)) {
        Add-Result -Results $results -Step 'launch' -Failure "no $Engine on this runner"
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    $pre120Copy = ''
    if ($Pre120Path -and [System.IO.File]::Exists($Pre120Path)) {
        $pre120Copy = Join-Path $RunRoot 'pre120-tstyles.ps1'
        Copy-Item -LiteralPath $Pre120Path -Destination $pre120Copy -Force
    }
    $nonce = [guid]::NewGuid().ToString('N')
    $configPath = Join-Path $RunRoot 'config.json'
    $probePath = Join-Path $PSScriptRoot 'wt-live-probe.ps1'
    $config = [ordered]@{
        Nonce              = $nonce
        Engine             = $Engine
        Launch             = $Launch
        GitHubActions      = $env:GITHUB_ACTIONS
        RunnerEnvironment  = $env:RUNNER_ENVIRONMENT
        Workspace          = $repoRoot
        ModuleManifest     = Join-Path $repoRoot 'TerminalStyles.psd1'
        Pre120Path         = $pre120Copy
        StyleName          = $script:StyleName
        StableSettings     = $stablePath
        PreviewSettings    = $previewPath
        UnpackagedSettings = $unpackagedPath
        SandboxDataRoot    = $sandbox
    }
    Write-JsonAtomic -Path $configPath -InputObject $config
    try {
        $arguments = Get-WTArgumentString -ProfileName (Get-ProbeProfileName -Engine $Engine) -EnginePath $enginePath `
                                          -ProbePath $probePath -ConfigPath $configPath
    } catch {
        Add-Result -Results $results -Step 'launch' -Failure "$($_.Exception.Message)"
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    Write-Host "Windows Terminal arguments: $arguments"

    # 4. Open the tab.
    $terminalsBefore = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'WindowsTerminal.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { [int]$_.ProcessId })
    $launchedAt = Get-Date
    $opened = Start-PreviewTab -Launch $Launch -FamilyName $preview.PackageFamilyName -Arguments $arguments
    $facts['Launch'] = $opened.Detail
    if (-not $opened.Ok) {
        Add-Result -Results $results -Step 'launch' -Failure $opened.Detail
        $null = Save-DesktopScreenshot -Path (Join-Path $RunRoot 'screenshot-launch.png')
        Save-ProcessList -Path (Join-Path $RunRoot 'processes.json') -Marker $configPath
        Save-TerminalEvents -Path (Join-Path $RunRoot 'events.json') -Since $launchedAt
        $null = Stop-NewTerminal -Before $terminalsBefore -Marker $configPath
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    Add-Result -Results $results -Step 'launch' -Detail $opened.Detail

    # 5. Wait for the probe: first that the tab started it, then for its result.
    $startedPath = Join-Path $RunRoot 'started.json'
    $resultPath = Join-Path $RunRoot 'result.json'
    $started = Wait-Until -Condition { [System.IO.File]::Exists($startedPath) } -TimeoutSeconds $StartTimeoutSeconds -IntervalMs 1000
    $finished = $false
    if ($started) { $finished = Wait-Until -Condition { [System.IO.File]::Exists($resultPath) } -TimeoutSeconds $ResultTimeoutSeconds -IntervalMs 1000 }
    if (-not $finished) {
        $shot = Save-DesktopScreenshot -Path (Join-Path $RunRoot 'screenshot-timeout.png')
        if ($shot) { Write-Host $shot }
        Save-ProcessList -Path (Join-Path $RunRoot 'processes.json') -Marker $configPath
        Save-TerminalEvents -Path (Join-Path $RunRoot 'events.json') -Since $launchedAt
        $stopped = @(Stop-NewTerminal -Before $terminalsBefore -Marker $configPath)
        $facts['Stopped'] = $(if ($stopped.Count -gt 0) { $stopped -join '; ' } else { 'nothing' })
        if ($started) {
            $why = "the probe started in the tab but wrote no result within $ResultTimeoutSeconds s; transcript.txt shows how far it got"
            Show-ProbeTranscript -Path (Join-Path $RunRoot 'transcript.txt')
        } else {
            $why = "no tab ran the probe within $StartTimeoutSeconds s: Windows Terminal Preview never opened the tab, or the shell in it never started the script (see screenshot-timeout.png, processes.json, events.json)"
        }
        Add-Result -Results $results -Step 'tab' -Failure $why
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    $result = $null
    $readError = $null
    try { $result = Read-JsonFile -Path $resultPath } catch { $readError = "$($_.Exception.Message)" }

    # 6. Let the tab close, stop what is left, and take the last readings.
    $null = Wait-Until -Condition {
        @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            [string]$_.Name -match '^(powershell|pwsh)\.exe$' -and [int]$_.ProcessId -ne $PID -and
            ([string]$_.CommandLine).IndexOf($configPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -eq 0
    } -TimeoutSeconds 30 -IntervalMs 1000
    $stopped = @(Stop-NewTerminal -Before $terminalsBefore -Marker $configPath)
    $facts['Stopped'] = $(if ($stopped.Count -gt 0) { $stopped -join '; ' } else { 'nothing' })
    $final = [pscustomobject]@{
        Stable     = Get-FileFacts -Path $stablePath
        Preview    = Get-FileFacts -Path $previewPath
        Unpackaged = Get-FileFacts -Path $unpackagedPath
    }
    try { Write-JsonAtomic -Path (Join-Path $RunRoot 'after.json') -InputObject $final } catch { }
    Save-ProcessList -Path (Join-Path $RunRoot 'processes.json') -Marker $configPath

    # 7. The checks. Only a result that is not this run's stops here: past
    # that, every check is judged on what the probe recorded, so one failure
    # does not hide what the rest of the run showed.
    if ($readError -or $null -eq $result -or "$($result.Nonce)" -ne $nonce) {
        $why = "result.json did not read: $readError"
        if (-not $readError) { $why = Get-TabVerdict -Result $result -Nonce $nonce -Engine $Engine -Workspace $repoRoot }
        Add-Result -Results $results -Step 'tab' -Failure $why
        return (Complete-Run -Results $results -Title $title -Facts $facts)
    }
    $hostRec = $result.NearestHost
    $facts['Tab shell'] = '{0} (pid {1}), WT_PROFILE_ID {2}, package: {3}' -f $result.EnginePath, $result.ProcessId, $result.Env.WT_PROFILE_ID,
        $(if ($result.Package) { $result.Package } else { "none (error $($result.PackageError))" })
    $facts['Tab ancestry'] = (@($result.Chain | ForEach-Object { '{0} {1}' -f $_.Name, $_.ProcessId }) -join ' <- ')
    $facts['Tab environment'] = $(if ($result.Env.InheritedStepEnvironment) { 'inherited from the CI step (GITHUB_ACTIONS present)' } else { 'not the CI step''s (no GITHUB_ACTIONS)' })
    if (@($result.Notes).Count -gt 0) { $facts['Probe notes'] = (@($result.Notes) -join '; ') }

    Add-Result -Results $results -Step 'tab' -Failure (Get-TabVerdict -Result $result -Nonce $nonce -Engine $Engine -Workspace $repoRoot) `
        -Detail ('{0} {1}, pid {2}, elevated: {3}, ran the checkout with its data root in {4}' -f
                 $result.PSEdition, $result.PSVersion, $result.ProcessId, $result.Elevated, $result.Module.DataRoot)

    Add-Result -Results $results -Step 'host' -Failure (Get-HostVerdict -Result $result -PreviewInstallLocation $preview.InstallLocation) `
        -Detail ('{0} (pid {1}), {2} level(s) above the shell; Find-WTHostExePath names the same file' -f $hostRec.ExecutablePath, $hostRec.ProcessId, $result.HostDepth)
    Add-Result -Results $results -Step 'identity' -Failure (Get-IdentityVerdict -Result $result -PreviewPackageFullName $preview.PackageFullName `
                                                           -UnpackagedBefore $unpackagedBefore -UnpackagedAfter $final.Unpackaged) `
        -Detail ('that WindowsTerminal.exe runs as package {0}; no unpackaged settings.json appeared' -f $hostRec.Package)
    Add-Result -Results $results -Step 'lookup' -Failure (Get-LookupVerdict -Result $result -PreviewSettingsPath $previewPath -StableSettingsPath $stablePath) `
        -Detail "Find-WTSettingsPath returned $previewPath while Stable's $stablePath existed"
    Add-Result -Results $results -Step 'control' -Failure (Get-ControlVerdict -Result $result -StableSettingsPath $stablePath) `
        -Detail "the pre-#120 lookup, in the same tab, returns Stable's $stablePath"
    Add-Result -Results $results -Step 'rig' -Failure (Get-RigVerdict -BaselineSha256 $seed.Stable.Sha256 -Result $result) `
        -Detail "Stable's settings.json unchanged from before the launch to the apply ($($seed.Stable.Sha256))"
    Add-Result -Results $results -Step 'stable' -Failure (Get-StableVerdict -Result $result -Final $final -StyleName $script:StyleName) `
        -Detail ("Stable's settings.json byte-identical before the apply, after it, after the reset and after the tab closed (sha256 {0})" -f $result.Before.Stable.Sha256)
    Add-Result -Results $results -Step 'apply' -Failure (Get-ApplyVerdict -Result $result -StyleName $script:StyleName) `
        -Detail ("tstyles {0}: Preview's settings.json {1} -> {2}, carries the '{0}' scheme, and profile '{3}' has colorScheme '{0}'" -f
                 $script:StyleName, $result.Before.Preview.Sha256, $result.Apply.Settled.Preview.Sha256, $result.Apply.Settled.Preview.ProfileName)
    Add-Result -Results $results -Step 'reset' -Failure (Get-ResetVerdict -Result $result -StyleName $script:StyleName) `
        -Detail ("tstyles reset: Preview's settings.json {0} -> {1}, no '{2}' scheme, no colorScheme '{2}' on the profile" -f
                 $result.Apply.Settled.Preview.Sha256, $result.Reset.Settled.Preview.Sha256, $script:StyleName)
    if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) { Show-ProbeTranscript -Path (Join-Path $RunRoot 'transcript.txt') }
    return (Complete-Run -Results $results -Title $title -Facts $facts)
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-WTLiveCheck -Engine $Engine -Launch $Launch -Pre120Path $Pre120Path -RunRoot $RunRoot `
                             -StartTimeoutSeconds $StartTimeoutSeconds -ResultTimeoutSeconds $ResultTimeoutSeconds)
}
