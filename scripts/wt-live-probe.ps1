# wt-live-probe.ps1 -- runs INSIDE the Windows Terminal Preview tab that
# scripts/wt-live-check.ps1 opens, under the engine under test, and records
# what the module does there. It judges nothing: the check reads result.json
# and decides.
#
# Everything it needs comes from the config file named by -ConfigPath, never
# from the environment. A tab's environment is rebuilt from the registry
# unless Windows Terminal was handed a command line, and then it is the one
# Windows Terminal itself started with (AppCommandlineArgs.cpp): the CI
# step's, when wt was run from the step, and a fresh one for the user when
# Terminal was activated instead. The probe records which it got.
#
# In order: who and where it runs; the process tree above it, read here
# independently of the module; the checked-out module, imported with its data
# root moved to a scratch folder, and the style's background put in that
# folder's cache; what Find-WTHostExePath and Find-WTSettingsPath answer, and
# what the lookup #120 replaced answers in the same tab; then `tstyles eva` and
# `tstyles reset` exactly as a user types them, reading both builds'
# settings.json after each. result.json is written whatever happens, in a
# finally.
#
# Prompts: neither command asks anything on this path. The update notice is
# held back by a fresh .last-update-check in the scratch data root, and
# Read-Host is replaced by a function that records and throws -- a prompt
# reached here is a failure, and is never answered.
#
# The network: neither command makes a request. The same .last-update-check
# means the update check sends none, and the background in the cache comes
# with a fresh revalidation marker, so the apply neither downloads the style's
# image from the gifs branch on raw.githubusercontent.com nor asks there
# whether it changed (Initialize-ProbeBackground). A seed that did not take is
# in the notes.
#
# NOT FOR A MACHINE ANYONE USES: it styles and resets the tab's own profile in
# the Terminal it runs under, so it refuses a config that was not written on a
# GitHub-hosted runner.
param(
    # config.json, written by wt-live-check.ps1. Its folder receives
    # started.json, transcript.txt, the screenshots and result.json.
    [string]$ConfigPath
)

. (Join-Path $PSScriptRoot 'wt-live-common.ps1')

function ConvertTo-HostText {
    # What Write-Host printed, from the information records -InformationVariable
    # collected: one line per call, except where -NoNewline joined two.
    param($Records)
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in @($Records)) {
        if ($null -eq $r) { continue }
        $m = $r.MessageData
        $text = "$m"
        $joined = $false
        if ($m -is [System.Management.Automation.HostInformationMessage]) {
            $text = "$($m.Message)"
            $joined = [bool]$m.NoNewLine
        }
        [void]$sb.Append($text)
        if (-not $joined) { [void]$sb.Append("`n") }
    }
    return $sb.ToString()
}

function Get-SettingsFacts {
    # One reading of a settings.json: its SHA-256, and what the check asks of
    # it, all from the same bytes. Whether the style's scheme is there is asked
    # twice -- of the module's own JSONC reader, and of the raw text -- and the
    # check wants both to agree.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Module,
        [AllowEmptyString()][string]$ProfileGuid,
        [Parameter(Mandatory)][string]$SchemeName
    )
    $facts = [ordered]@{
        Path = $Path; Exists = $false; Sha256 = $null
        Parsed = $false; ParseError = $null
        HasScheme = $null; TextHasScheme = $null
        ProfileFound = $null; ProfileName = $null; ProfileColorScheme = $null
    }
    $bytes = Read-SharedBytes -Path $Path
    if ($null -eq $bytes) {
        $facts.Exists = [System.IO.File]::Exists($Path)
        return [pscustomobject]$facts
    }
    $facts.Exists = $true
    $facts.Sha256 = Get-BytesSha256 -Bytes $bytes
    $text = ConvertFrom-Utf8Bytes -Bytes $bytes
    # Case-sensitive: the scheme is named 'eva', and -match would also take 'EVA'.
    $facts.TextHasScheme = [bool]($text -cmatch ('"name"\s*:\s*"' + [regex]::Escape($SchemeName) + '"'))
    try {
        $settings = & $Module { param($t) ConvertFrom-JsoncText -Json $t } $text
        $facts.Parsed = $true
        $schemes = @()
        if ($null -ne $settings -and $settings.PSObject.Properties.Match('schemes').Count -gt 0) {
            $schemes = @($settings.schemes | Where-Object { $null -ne $_ })
        }
        $facts.HasScheme = (@($schemes | Where-Object { "$($_.name)" -ceq $SchemeName }).Count -gt 0)
        $list = @((& $Module { param($s) Get-WTProfileShape -Settings $s } $settings).List)
        $entry = $null
        if ($ProfileGuid) { $entry = @($list | Where-Object { "$($_.guid)" -eq $ProfileGuid }) | Select-Object -First 1 }
        $facts.ProfileFound = ($null -ne $entry)
        if ($null -ne $entry) {
            $facts.ProfileName = "$($entry.name)"
            if ($entry.PSObject.Properties.Match('colorScheme').Count -gt 0) { $facts.ProfileColorScheme = "$($entry.colorScheme)" }
        }
    } catch {
        $facts.ParseError = "$($_.Exception.Message)"
    }
    return [pscustomobject]$facts
}

function Get-BothSettingsFacts {
    # Stable's and Preview's settings.json, read one after the other.
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)]$Module, [AllowEmptyString()][string]$ProfileGuid)
    return [pscustomobject]@{
        Stable  = Get-SettingsFacts -Path $Config.StableSettings -Module $Module -ProfileGuid $ProfileGuid -SchemeName $Config.StyleName
        Preview = Get-SettingsFacts -Path $Config.PreviewSettings -Module $Module -ProfileGuid $ProfileGuid -SchemeName $Config.StyleName
    }
}

function Get-Pre120Lookup {
    # The lookup #120 replaced, run in this tab: Find-WTSettingsPath's body as
    # tstyles.ps1 shipped it before the PR, lifted out of that file by its AST
    # so it is the old code itself, not a retelling. It reads WT_SETTINGS_PATH
    # (which no Windows Terminal sets) and then takes the first settings.json
    # it finds, Stable's first. Returns { Path; Error }.
    param([AllowEmptyString()][string]$Path)
    $out = [ordered]@{ Path = $null; Error = $null }
    try {
        if (-not $Path -or -not [System.IO.File]::Exists($Path)) { throw "no pre-#120 tstyles.ps1 at '$Path'" }
        $text = ConvertFrom-Utf8Bytes -Bytes (Read-SharedBytes -Path $Path)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        $fn = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-WTSettingsPath'
        }, $true)) | Select-Object -First 1
        if ($null -eq $fn) { throw "$Path defines no Find-WTSettingsPath" }
        $found = @(& ($fn.Body.GetScriptBlock()) | Where-Object { $_ })
        if ($found.Count -gt 1) { throw "it returned $($found.Count) paths" }
        if ($found.Count -eq 1) { $out.Path = "$($found[0])" }
    } catch {
        $out.Error = "$($_.Exception.Message)"
    }
    return [pscustomobject]$out
}

function Get-ProbeIdentity {
    # This shell: its executable, session, account, and whether it is elevated
    # -- on a hosted runner, everything a step starts is.
    $self = Get-Process -Id $PID
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return [pscustomobject]@{
        EnginePath = $self.Path
        SessionId  = $self.SessionId
        UserSid    = $identity.User.Value
        Elevated   = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

function Import-ProbeModule {
    # The checked-out module, imported as a user's Import-Module loads it, with
    # its data root moved to a scratch folder before anything runs.
    #
    # The module computes its data root at import, from LOCALAPPDATA, and keeps
    # it in $script:TStylesDataRoot; it does not read TSTYLES_DATA, which is the
    # shell side's name for the same folder (shell/tstyles.sh). So the data root
    # is moved inside the module, as the test suite does, and TSTYLES_DATA is
    # set to match. The import itself still creates the real data root folder
    # and its migration marker, on a runner thrown away after the job.
    param([Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string]$DataRoot)
    $global:TStylesNoAutoLoad = $true
    Import-Module $ManifestPath -Force -DisableNameChecking -ErrorAction Stop
    $module = Get-Module TerminalStyles | Select-Object -First 1
    if ($null -eq $module) { throw "Import-Module $ManifestPath loaded no TerminalStyles" }
    $null = New-Item -ItemType Directory -Force -Path $DataRoot
    & $module {
        param($root)
        $script:TStylesDataRoot = $root
        $script:TStylesCurrent = Join-Path $root 'current-style.ps1'
        # The day's update check, spent: Test-UpdateAvailable answers inside the
        # 24-hour throttle without a request, and nothing is printed.
        Write-UpdateCheckStamp -Path (Join-Path $root '.last-update-check')
    } $DataRoot
    $env:TSTYLES_DATA = $DataRoot
    $root = & $module { $script:TStylesDataRoot }
    $current = & $module { $script:TStylesCurrent }
    return [pscustomobject]@{
        Module     = $module
        ModuleBase = $module.ModuleBase
        Version    = "$($module.Version)"
        DataRoot   = $root
        Current    = $current
        Sandboxed  = ((Test-SamePath $root $DataRoot) -and (Test-PathUnder -Path $current -Root $DataRoot))
    }
}

function Initialize-ProbeBackground {
    # Puts a background for the style in its cache, inside the sandboxed data
    # root, beside a revalidation marker stamped now. The apply then takes the
    # image from disk (Get-StyleBundledBackground's second tier) and, with the
    # marker fresh, does not ask the gifs branch whether it changed: so it
    # reaches neither raw.githubusercontent.com nor any other host. The image
    # is a 1x1 transparent GIF, not the style's own -- what the run checks is
    # which settings.json is written, and the path written into it is the
    # cache file either way. Where the cache is and what the marker means are
    # the module's own answers (Get-StyleCacheDir, Test-BackgroundRefreshDue),
    # asked here rather than restated. Returns { Path; RefreshDue; Error }.
    param([Parameter(Mandatory)]$Module, [Parameter(Mandatory)][string]$StyleName)
    $gif = [byte[]](0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
                    0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B)
    $out = [ordered]@{ Path = $null; RefreshDue = $null; Error = $null }
    try {
        $dir = & $Module { param($n) Get-StyleCacheDir -StyleName $n } $StyleName
        $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop
        $path = Join-Path $dir 'background.gif'
        [System.IO.File]::WriteAllBytes($path, $gif)
        # The shape Update-CachedBackground writes, culture-pinned as its reader is.
        $marker = ConvertTo-Json -Compress -InputObject ([ordered]@{
            kind = 'checked'
            at   = [datetime]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        })
        [System.IO.File]::WriteAllText((Join-Path $dir '.background-checked'), $marker, (New-Object System.Text.UTF8Encoding($false)))
        $out.Path = $path
        $out.RefreshDue = [bool](& $Module { param($t) Test-BackgroundRefreshDue -MarkerText $t } $marker)
    } catch {
        $out.Error = "$($_.Exception.Message)"
    }
    return [pscustomobject]$out
}

function Invoke-ProbeCommand {
    # One tstyles command exactly as a user types it -- the exported command,
    # the session's own profile, no -Target -- and both settings.json files read
    # twice afterwards: at once, and again once Preview's has been quiet for a
    # few seconds, since Windows Terminal reloads it on every change and may
    # write it back.
    param(
        [Parameter(Mandatory)][string]$Argument,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Module,
        [AllowEmptyString()][string]$ProfileGuid
    )
    $step = [ordered]@{
        Command = "tstyles $Argument"; Output = ''; PipelineOutput = @(); Errors = @(); Threw = $null
        Immediate = $null; PreviewQuiet = $null; Settled = $null
    }
    $ev = $null
    $iv = $null
    $piped = $null
    try {
        # Assigned, so nothing the command writes to the pipeline joins this
        # function's own output: the result's Apply and Reset stay one object.
        $piped = Invoke-TerminalStyle -Arg $Argument -ErrorVariable ev -InformationVariable iv
    } catch {
        # Inside a try -- this one, or the one around the whole probe -- a
        # statement-terminating error ends the command, where a user's session
        # would print it and run on. So a Threw here means the run may have
        # left the user's path at that error, and the check fails it.
        $step.Threw = "$($_.Exception.Message)"
    }
    # Filtered first: a $null piped into ForEach-Object still runs it once.
    $step.PipelineOutput = @(@($piped) | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    $step.Output = ConvertTo-HostText -Records $iv
    $step.Errors = @($ev | ForEach-Object { "$_" })
    $step.Immediate = Get-BothSettingsFacts -Config $Config -Module $Module -ProfileGuid $ProfileGuid
    $quiet = Wait-FileQuiet -Path $Config.PreviewSettings -QuietSeconds 3 -TimeoutSeconds 20
    $step.PreviewQuiet = [ordered]@{ Settled = $quiet.Settled; RewritesSeen = $quiet.Changes }
    $step.Settled = Get-BothSettingsFacts -Config $Config -Module $Module -ProfileGuid $ProfileGuid
    return [pscustomobject]$step
}

function Invoke-WTLiveProbe {
    # The whole probe. Returns the exit code: 0 once result.json is written --
    # the verdict is the check's -- and 1 when even that failed.
    [CmdletBinding()]
    param([string]$ConfigPath)

    $result = [ordered]@{
        Nonce = $null; Engine = $null
        Started = Format-Utc ([datetime]::UtcNow); Finished = $null
        ProcessId = $PID; EnginePath = $null; CommandLine = [Environment]::CommandLine
        PSEdition = "$($PSVersionTable.PSEdition)"; PSVersion = "$($PSVersionTable.PSVersion)"
        Elevated = $null; UserSid = $null; SessionId = $null; Package = $null; PackageError = $null
        Env = $null
        Chain = @(); ChainError = $null; NearestHost = $null; HostDepth = $null
        Module = $null; TerminalKind = $null; HostExePath = $null
        SettingsPath = @(); SettingsPathErrors = @(); StableExistedAtLookup = $null
        Pre120 = $null
        PreviewReady = $null
        Background = $null
        Before = $null; Apply = $null; Reset = $null
        DataRootFiles = @()
        Prompts = @(); Notes = @(); Errors = @()
    }
    $notes = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $global:WtLivePrompts = New-Object System.Collections.ArrayList
    $outDir = $null
    if ($ConfigPath) { $outDir = Split-Path -Parent $ConfigPath }
    $transcribing = $false
    try {
        if (-not $ConfigPath -or -not [System.IO.File]::Exists($ConfigPath)) { throw "no config at '$ConfigPath'" }
        $config = Read-JsonFile -Path $ConfigPath
        $result.Nonce = "$($config.Nonce)"
        $result.Engine = "$($config.Engine)"
        if (-not (Test-GitHubHostedRunner -GitHubActions "$($config.GitHubActions)" -RunnerEnvironment "$($config.RunnerEnvironment)")) {
            throw 'the config was not written on a GitHub-hosted runner; this probe styles and resets the tab''s own profile, so it runs nowhere else'
        }
        Write-JsonAtomic -Path (Join-Path $outDir 'started.json') -InputObject ([ordered]@{ Nonce = $result.Nonce; ProcessId = $PID; Started = $result.Started })
        try {
            Start-Transcript -LiteralPath (Join-Path $outDir 'transcript.txt') -Force | Out-Null
            $transcribing = $true
        } catch { [void]$notes.Add("no transcript: $($_.Exception.Message)") }

        # A prompt would hang a tab nobody is watching. Reaching one is a
        # failure of the check, recorded and thrown; it is never answered.
        function global:Read-Host {
            [void]$global:WtLivePrompts.Add("$args")
            throw "wt-live-probe: a prompt was reached, and this tab does not answer prompts: $args"
        }

        # Who and where this is.
        $me = Get-ProbeIdentity
        $result.EnginePath = $me.EnginePath
        $result.SessionId = $me.SessionId
        $result.UserSid = $me.UserSid
        $result.Elevated = $me.Elevated
        $own = Get-CurrentPackageName
        $result.Package = $own.Name
        $result.PackageError = $own.Error
        $result.Env = [ordered]@{
            WT_SESSION          = $env:WT_SESSION
            WT_PROFILE_ID       = $env:WT_PROFILE_ID
            WT_SETTINGS_DIR     = $env:WT_SETTINGS_DIR
            TERM_PROGRAM        = $env:TERM_PROGRAM
            TSTYLES_WT_SETTINGS = $env:TSTYLES_WT_SETTINGS
            LOCALAPPDATA        = $env:LOCALAPPDATA
            # GITHUB_ACTIONS reaches the tab only if the CI step's environment did.
            InheritedStepEnvironment = [bool]$env:GITHUB_ACTIONS
        }

        # The process tree above this shell, read here, apart from the module.
        try {
            $chain = @(Get-ProcessChain -StartId $PID)
            for ($i = 0; $i -lt $chain.Count; $i++) {
                if ($chain[$i].Name -ne 'WindowsTerminal.exe') { continue }
                $pkg = Get-ProcessPackageName -ProcessId $chain[$i].ProcessId
                $chain[$i].Package = $pkg.Name
                $chain[$i].PackageError = $pkg.Error
                if ($null -eq $result.NearestHost) {
                    $result.NearestHost = $chain[$i]
                    $result.HostDepth = $i
                }
            }
            $result.Chain = $chain
        } catch { $result.ChainError = "$($_.Exception.Message)" }

        # Nothing but the process tree may answer which build this is.
        if ($env:TSTYLES_WT_SETTINGS) {
            [void]$notes.Add("TSTYLES_WT_SETTINGS was '$env:TSTYLES_WT_SETTINGS' in the tab; removed, so the walk answers")
            Remove-Item -LiteralPath Env:TSTYLES_WT_SETTINGS
        }

        $imported = Import-ProbeModule -ManifestPath "$($config.ModuleManifest)" -DataRoot "$($config.SandboxDataRoot)"
        $module = $imported.Module
        $result.Module = [ordered]@{
            ModuleBase = $imported.ModuleBase; Version = $imported.Version
            DataRoot = $imported.DataRoot; Current = $imported.Current; Sandboxed = $imported.Sandboxed
        }
        if (-not $imported.Sandboxed) { throw "the module's data root is '$($imported.DataRoot)', not the sandbox $($config.SandboxDataRoot)" }

        # The style's background, from disk: the apply then reaches no host.
        $result.Background = Initialize-ProbeBackground -Module $module -StyleName "$($config.StyleName)"
        if ($result.Background.Error) {
            [void]$notes.Add("the style's background was not seeded ($($result.Background.Error)), so the apply may fetch it from raw.githubusercontent.com")
        } elseif ($result.Background.RefreshDue) {
            [void]$notes.Add("the module takes the seeded background as due for a re-check, so the apply may ask raw.githubusercontent.com about it")
        }

        # Preview writes its settings.json before it opens the first tab; wait
        # for it anyway, and for it to stop changing.
        $ready = Wait-Until -Condition { [System.IO.File]::Exists("$($config.PreviewSettings)") } -TimeoutSeconds 30
        $quiet = Wait-FileQuiet -Path "$($config.PreviewSettings)" -QuietSeconds 3 -TimeoutSeconds 30
        $result.PreviewReady = [ordered]@{ Exists = $ready; Settled = $quiet.Settled; RewritesSeen = $quiet.Changes }

        # What the module answers before anything is written.
        $result.TerminalKind = "$(& $module { Get-TerminalKind })"
        $result.HostExePath = "$(& $module { Find-WTHostExePath })"
        $lookup = & $module {
            $e = $null
            $p = Find-WTSettingsPath -ErrorVariable e -ErrorAction SilentlyContinue
            [pscustomobject]@{ Path = @($p | Where-Object { $_ }); Errors = @($e | ForEach-Object { "$_" }) }
        }
        $result.StableExistedAtLookup = [System.IO.File]::Exists("$($config.StableSettings)")
        $result.SettingsPath = @($lookup.Path | ForEach-Object { "$_" })
        $result.SettingsPathErrors = @($lookup.Errors)

        # The control: the lookup #120 replaced, in this same tab.
        $result.Pre120 = Get-Pre120Lookup -Path "$($config.Pre120Path)"

        $guid = "$env:WT_PROFILE_ID"
        $result.Before = Get-BothSettingsFacts -Config $config -Module $module -ProfileGuid $guid
        $shot = Save-DesktopScreenshot -Path (Join-Path $outDir 'before-apply.png')
        if ($shot) { [void]$notes.Add($shot) }

        $result.Apply = Invoke-ProbeCommand -Argument "$($config.StyleName)" -Config $config -Module $module -ProfileGuid $guid
        $shot = Save-DesktopScreenshot -Path (Join-Path $outDir 'after-apply.png')
        if ($shot) { [void]$notes.Add($shot) }

        $result.Reset = Invoke-ProbeCommand -Argument 'reset' -Config $config -Module $module -ProfileGuid $guid
        $shot = Save-DesktopScreenshot -Path (Join-Path $outDir 'after-reset.png')
        if ($shot) { [void]$notes.Add($shot) }

        $result.DataRootFiles = @(Get-ChildItem -LiteralPath "$($config.SandboxDataRoot)" -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { '{0} ({1} bytes)' -f $_.FullName, $_.Length })
    } catch {
        [void]$errors.Add(('{0} (line {1})' -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber))
    } finally {
        $result.Finished = Format-Utc ([datetime]::UtcNow)
        $result.Prompts = @($global:WtLivePrompts)
        $result.Notes = @($notes)
        $result.Errors = @($errors)
        if ($transcribing) { try { Stop-Transcript | Out-Null } catch { } }
        $code = 1
        if ($outDir) {
            try {
                Write-JsonAtomic -Path (Join-Path $outDir 'result.json') -InputObject $result
                $code = 0
            } catch {
                Write-Host "result.json not written: $($_.Exception.Message)"
            }
        }
    }
    return $code
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-WTLiveProbe -ConfigPath $ConfigPath)
}
