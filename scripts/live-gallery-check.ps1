# live-gallery-check.ps1 -- TerminalStyles as a user meets it: installed from
# the PowerShell Gallery, told that a newer release is out, updated to it, and
# uninstalled.
#
# Run by .github/workflows/live-gallery.yml, under Windows PowerShell 5.1 and
# under pwsh 7, each on a GitHub-hosted runner that is thrown away after the
# job. Everything under tests/ mocks the Gallery and every remover, so this is
# the one place the update notice, `tstyles update` and `tstyles uninstall`
# meet the real Gallery and the real PowerShellGet. Above all on 5.1, which has
# no PSResourceGet: update and uninstall take the Update-Module and
# Uninstall-Module fallbacks there, and 0.9.1 and 0.9.2 shipped them without
# either ever having run against the Gallery.
#
# NOT FOR A MACHINE ANYONE USES. It installs TerminalStyles for the current
# user and ends with `tstyles uninstall -Yes`, which removes every installed
# version -- the operator's own included. It refuses to start anywhere but a
# GitHub-hosted runner. tests/Live-Gallery-Check.Tests.ps1 dot-sources it for
# its functions, which is all it does when dot-sourced.
#
# Each step runs in a new process of the engine under test, as a user's next
# command would: a fresh session, the engine's default TLS setting, and the
# version a fresh Import-Module finds -- `tstyles update` leaves the session
# that ran it on the old copy.
[CmdletBinding()]
param(
    # The release installed first. Default: the newest one published before
    # the version this checkout's TerminalStyles.psd1 declares.
    [string]$From = $env:LIVE_FROM,
    # The installed version whose `tstyles uninstall` runs. Default: the
    # newest. Naming the older one shows what that release's uninstall did.
    [string]$UninstallWith = $env:LIVE_UNINSTALL_WITH
)

function Test-GitHubHostedRunner {
    # True only on a runner GitHub hosts: a new machine for each job, discarded
    # after it. GITHUB_ACTIONS alone is not enough -- a self-hosted runner sets
    # it too, and a self-hosted runner is somebody's machine.
    [CmdletBinding()]
    param(
        [string]$GitHubActions = $env:GITHUB_ACTIONS,
        [string]$RunnerEnvironment = $env:RUNNER_ENVIRONMENT
    )
    return ($GitHubActions -eq 'true' -and $RunnerEnvironment -eq 'github-hosted')
}

function Select-StartVersion {
    # The newest release published before $Newest -- the one its users are
    # updating from -- or $null. Compared as versions: as text, 0.9.10 sorts
    # before 0.9.9.
    [CmdletBinding()]
    param(
        [string[]]$Published,
        [Parameter(Mandatory)][string]$Newest
    )
    $limit = [version]$Newest
    $older = @(foreach ($p in $Published) {
        $v = $null
        if ([version]::TryParse("$p", [ref]$v) -and $v -lt $limit) { $v }
    })
    if ($older.Count -eq 0) { return $null }
    return ($older | Sort-Object -Descending | Select-Object -First 1).ToString()
}

function Get-NoticeVerdict {
    # Why the update notice let a $From install down, or $null when it told it
    # that $Newest is out -- and, on 5.1, left the session's SecurityProtocol
    # as it found it. $Result is the notice as printed, read back into
    # { Installed; Remote }, or $null when nothing was printed.
    [CmdletBinding()]
    param(
        $Result,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$Newest,
        [string]$ProtocolBefore = '',
        [string]$ProtocolAfter = ''
    )
    if ($null -eq $Result -or -not "$($Result.Remote)") {
        return "no update notice: $From was not told that $Newest is out"
    }
    if ("$($Result.Installed)" -ne $From -or "$($Result.Remote)" -ne $Newest) {
        return "the notice offered $($Result.Installed) -> $($Result.Remote), not $From -> $Newest"
    }
    if ($ProtocolBefore -ne $ProtocolAfter) {
        return "the check left SecurityProtocol at '$ProtocolAfter'; it found '$ProtocolBefore'"
    }
    return $null
}

function Get-UpdateVerdict {
    # Why `tstyles update` did not take a $From install to $Newest, or $null.
    # Its report AND the disk: the report is the command's own word, and the
    # point of this check is not to take it.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Output,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$Newest,
        [string[]]$Versions = @()
    )
    $line = 'Updated {0} -> {1}' -f $From, $Newest
    if (-not "$Output".Contains($line)) {
        return "tstyles update did not report ""$line"""
    }
    $have = @($Versions | Where-Object { $_ } | Sort-Object -Unique)
    $want = @(@($From, $Newest) | Sort-Object -Unique)
    if (($have -join ', ') -ne ($want -join ', ')) {
        $now = if ($have.Count -gt 0) { $have -join ', ' } else { 'nothing' }
        return "it reported ""$line"", but installed now: $now"
    }
    return $null
}

function Get-UninstallVerdict {
    # Why `tstyles uninstall` did not leave the machine clean, or $null. The
    # sign-off has to be the plain line -- "TerminalStyles uninstalled,
    # EXCEPT ..." opens a list of what is left -- and the disk has to agree.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Output,
        [string[]]$CopiesLeft = @()
    )
    $signedOff = "$Output" -cmatch '(?m)^TerminalStyles uninstalled\.\s*$'
    $left = @($CopiesLeft | Where-Object { $_ })
    if ($left.Count -gt 0 -and $signedOff) {
        return ("it signed off ""TerminalStyles uninstalled."" with {0} still installed: {1}" -f
                $(if ($left.Count -eq 1) { 'a copy' } else { "$($left.Count) copies" }), ($left -join '; '))
    }
    if ($left.Count -gt 0) {
        return "still installed: $($left -join '; ')"
    }
    if (-not $signedOff) {
        return 'nothing is left, but it did not sign off "TerminalStyles uninstalled."'
    }
    return $null
}

function Get-TerminalStylesCopy {
    # Every TerminalStyles folder on this machine that an engine could load,
    # as { Path; Version }. Read off the disk rather than asked of the module
    # or of either engine: whether the uninstall worked is the question, so the
    # uninstall's own answer cannot be the evidence. Both engines' per-user and
    # all-users module folders, and everything on this engine's module path.
    [CmdletBinding()]
    param()
    $roots = New-Object System.Collections.Generic.List[string]
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($docs) {
        $roots.Add((Join-Path $docs 'PowerShell\Modules'))
        $roots.Add((Join-Path $docs 'WindowsPowerShell\Modules'))
    }
    if ($env:ProgramFiles) {
        $roots.Add((Join-Path $env:ProgramFiles 'PowerShell\Modules'))
        $roots.Add((Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))
    }
    foreach ($p in ("$env:PSModulePath" -split [IO.Path]::PathSeparator)) {
        if ($p) { $roots.Add($p) }
    }

    # A hashtable's keys ignore case, as Windows paths do.
    $seen = @{}
    foreach ($root in $roots) {
        $dir = Join-Path $root 'TerminalStyles'
        if (-not [IO.Directory]::Exists($dir)) { continue }
        $found = @()
        if ([IO.File]::Exists((Join-Path $dir 'TerminalStyles.psd1'))) {
            $found += [pscustomobject]@{ Path = $dir; Version = '(unversioned)' }
        }
        foreach ($sub in [IO.Directory]::GetDirectories($dir)) {
            if ([IO.File]::Exists((Join-Path $sub 'TerminalStyles.psd1'))) {
                $found += [pscustomobject]@{ Path = $sub; Version = (Split-Path $sub -Leaf) }
            }
        }
        foreach ($f in $found) {
            $key = $f.Path.TrimEnd('\', '/')
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $f
            }
        }
    }
}

function Initialize-GalleryClient {
    # What this script's own Gallery queries need, in this process only: TLS
    # 1.2 on Windows PowerShell 5.1, which the Gallery requires and the .NET
    # Framework default can leave out, and the NuGet provider PowerShellGet
    # asks to install before its first query -- the "yes" a user gives that
    # prompt. Each step starts its own process, with the engine's defaults.
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSEdition -ne 'Desktop') { return }
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
}

function Get-PublishedVersion {
    # Every TerminalStyles version the Gallery lists, asked through the client
    # this engine's users have: PSResourceGet on pwsh 7, PowerShellGet on 5.1.
    [CmdletBinding()]
    param()
    if (Get-Command Find-PSResource -ErrorAction SilentlyContinue) {
        Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' -ErrorAction Stop |
            ForEach-Object { $_.Version.ToString() }
    } else {
        Find-Module -Name TerminalStyles -Repository PSGallery -AllVersions -ErrorAction Stop |
            ForEach-Object { $_.Version.ToString() }
    }
}

function Get-FeedLatestVersion {
    # The newest version by the request the update notice makes -- the v2
    # feed's IsLatestVersion, as Get-GalleryLatestVersion in lib/update.ps1
    # asks it -- or $null.
    [CmdletBinding()]
    param()
    try {
        $entry = @(Invoke-RestMethod -Uri 'https://www.powershellgallery.com/api/v2/FindPackagesById()?id=''TerminalStyles''&$filter=IsLatestVersion' `
                       -UserAgent 'TerminalStyles-LiveCheck' -TimeoutSec 30 -ErrorAction Stop)[0]
        $v = $entry.properties.Version
        if ($v -is [System.Xml.XmlNode]) { $v = $v.InnerText }
        if ("$v".Trim()) { return "$v".Trim() }
    } catch { }
    return $null
}

function Wait-GalleryNewest {
    # Whether the notice's feed names $Newest several times running. For a few
    # minutes after a publish it can answer with the version before, and a
    # tag is pushed right after one.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Newest,
        [int]$InARow = 3,
        [int]$IntervalSeconds = 10,
        [int]$TimeoutMinutes = 10
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $streak = 0
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $last = Get-FeedLatestVersion
        if ($last -eq $Newest) { $streak++ } else { $streak = 0 }
        if ($streak -ge $InARow) { return [pscustomobject]@{ Settled = $true; Last = $last } }
        Start-Sleep -Seconds $IntervalSeconds
    }
    return [pscustomobject]@{ Settled = $false; Last = $last }
}

function Invoke-Phase {
    # Runs $Body as a script in a new process of this same engine, prints what
    # it wrote, and returns { Output; ExitCode }, the output without colour
    # codes, since the verdicts read it line by line.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$WorkDir
    )
    $file = Join-Path $WorkDir ($Name + '.ps1')
    [IO.File]::WriteAllText($file, $Body, (New-Object System.Text.UTF8Encoding($false)))
    $engine = (Get-Process -Id $PID).Path
    # Not Stop: under it, 5.1 turns the first line a child writes to stderr
    # into a terminating error, and that line is evidence, not a failure.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file 2>&1 |
                   ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $text = ($lines -join "`n") -replace ([string][char]27 + '\[[0-9;?]*[ -/]*[@-~]'), ''
    Write-Host ''
    Write-Host ('----- {0} (exit {1}) -----' -f $Name, $code)
    Write-Host $text
    return [pscustomobject]@{ Output = $text; ExitCode = $code }
}

function Get-PhaseResult {
    # The JSON a step printed on its `RESULT ` line, or $null.
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Output)
    $line = @("$Output" -split "`n" | Where-Object { $_ -like 'RESULT *' }) | Select-Object -Last 1
    if (-not $line) { return $null }
    try { return ($line.Substring(7).Trim() | ConvertFrom-Json) } catch { return $null }
}

function Add-Result {
    [CmdletBinding()]
    param(
        [System.Collections.ArrayList]$Results,
        [Parameter(Mandatory)][string]$Step,
        [string]$Failure,
        [string]$Detail
    )
    $ok = -not $Failure
    $text = if ($ok) { $Detail } else { $Failure }
    $null = $Results.Add([pscustomobject]@{ Step = $Step; Ok = $ok; Text = $text })
    if (-not $ok) { Write-Host ('::error title=Live Gallery check: {0}::{1}' -f $Step, $Failure) }
}

function Complete-Run {
    # Prints the summary, adds it to the job's summary page, and returns the
    # exit code: 1 when any step failed.
    [CmdletBinding()]
    param(
        [System.Collections.ArrayList]$Results,
        [Parameter(Mandatory)][string]$Title
    )
    Write-Host ''
    Write-Host $Title
    foreach ($r in $Results) {
        Write-Host ('  {0}  {1,-12} {2}' -f $(if ($r.Ok) { 'PASS' } else { 'FAIL' }), $r.Step, $r.Text)
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $md = New-Object System.Collections.Generic.List[string]
        $md.Add("### $Title")
        $md.Add('')
        $md.Add('| | Step | What happened |')
        $md.Add('|---|---|---|')
        foreach ($r in $Results) {
            $md.Add(('| {0} | {1} | {2} |' -f $(if ($r.Ok) { 'pass' } else { '**FAIL**' }), $r.Step, ($r.Text -replace '\|', '\|')))
        }
        $md.Add('')
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $md -Encoding ASCII
    }
    if (@($Results | Where-Object { -not $_.Ok }).Count -gt 0) { return 1 }
    return 0
}

# The steps, as scripts for a new process. Single-quoted: nothing in them
# expands here. @VERSION@ and @FROM@ are replaced with a version that has
# already parsed as one, so nothing else can reach them.

$script:ImportPrologue = @'
# A stock Windows PowerShell 5.1 session can start without TLS 1.2 -- the .NET
# Framework default leaves it out where strong crypto is not switched on, and
# the runner's may well include it. Take it out: that is the session
# Enable-Tls12 is there for.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
}
$global:TStylesNoAutoLoad = $true
try {
    Import-Module TerminalStyles -RequiredVersion '@VERSION@' -DisableNameChecking -ErrorAction Stop
} catch {
    "STEP ERROR: could not import TerminalStyles @VERSION@: $_"
    exit 3
}
$m = Get-Module TerminalStyles
"Loaded TerminalStyles $($m.Version) from $($m.ModuleBase)"
'@

$script:InstallBody = @'
# As each engine's users install it. On 5.1 that is PowerShellGet's
# Install-Module, with TLS 1.2 switched on as the Gallery's instructions say,
# and PSGallery left untrusted, as it is out of the box: -Force answers the
# trust prompt for this install only.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    "SecurityProtocol at start: $([Net.ServicePointManager]::SecurityProtocol)"
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
    "PowerShellGet $($client.Version)"
    Install-Module -Name TerminalStyles -RequiredVersion '@FROM@' -Repository PSGallery -Scope CurrentUser -Force
} else {
    $client = Get-Module -ListAvailable Microsoft.PowerShell.PSResourceGet | Sort-Object Version -Descending | Select-Object -First 1
    "PSResourceGet $($client.Version)"
    Install-PSResource -Name TerminalStyles -Version '@FROM@' -Repository PSGallery -TrustRepository
}
"Installed TerminalStyles @FROM@"
'@

$script:NoticeBody = $script:ImportPrologue + @'

# The notice exactly as a terminal shows it. Told the output is not
# redirected, because here it is -- and from 0.9.1 on, a redirected run skips
# the check. 0.9.0 has no such parameter, and no gate to pass.
$before = ''
if ($PSVersionTable.PSEdition -eq 'Desktop') { $before = "$([Net.ServicePointManager]::SecurityProtocol)" }
# The check runs once a day; a stamp from an earlier attempt would hold it back.
$root = & $m { $script:TStylesDataRoot }
if ($root) { Remove-Item -LiteralPath (Join-Path $root '.last-update-check') -Force -ErrorAction SilentlyContinue }
$show = & $m { Get-Command Show-UpdateNoticeIfAvailable -ErrorAction SilentlyContinue }
if (-not $show) {
    'This version has no update notice.'
} elseif ($show.Parameters.ContainsKey('OutputRedirected')) {
    & $m { Show-UpdateNoticeIfAvailable -OutputRedirected:$false }
} else {
    & $m { Show-UpdateNoticeIfAvailable }
}
$after = ''
if ($PSVersionTable.PSEdition -eq 'Desktop') { $after = "$([Net.ServicePointManager]::SecurityProtocol)" }
'RESULT ' + (ConvertTo-Json -Compress -InputObject @{ Before = $before; After = $after })
'@

$script:UpdateBody = $script:ImportPrologue + @'

tstyles update
'@

$script:NextSessionBody = @'
# What the next tab gets: a plain import, the newest version it can find.
$global:TStylesNoAutoLoad = $true
Import-Module TerminalStyles -DisableNameChecking -ErrorAction Stop
"NEXT SESSION LOADS $((Get-Module TerminalStyles).Version)"
'@

$script:UninstallBody = $script:ImportPrologue + @'

tstyles uninstall -Yes
'@

function Invoke-LiveGalleryCheck {
    # The whole check. Returns the exit code -- 0 when every step passed, 1
    # when one failed, 2 when it refused to start -- and nothing else.
    [CmdletBinding()]
    param(
        [string]$From,
        [string]$UninstallWith
    )
    if (-not (Test-GitHubHostedRunner)) {
        Write-Host 'live-gallery-check.ps1 runs only on a GitHub-hosted runner. It ends with'
        Write-Host '`tstyles uninstall -Yes`, which removes every installed version of'
        Write-Host 'TerminalStyles for the current user -- here, yours.'
        return 2
    }

    $results = New-Object System.Collections.ArrayList
    $desktop = $PSVersionTable.PSEdition -eq 'Desktop'
    $title = '{0} {1}' -f $(if ($desktop) { 'Windows PowerShell' } else { 'pwsh' }), $PSVersionTable.PSVersion
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('live-gallery-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $workDir

    # What the 5.1 leg exists for: no PSResourceGet, so update and uninstall
    # take the Update-Module and Uninstall-Module fallbacks.
    if ($desktop -and (Get-Command Update-PSResource -ErrorAction SilentlyContinue)) {
        Add-Result -Results $results -Step 'engine' -Failure ('this Windows PowerShell has PSResourceGet, so it would not take the ' +
            'Update-Module and Uninstall-Module fallbacks this leg is for')
        return (Complete-Run -Results $results -Title $title)
    }

    $newest = (Import-PowerShellDataFile -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1')).ModuleVersion
    Initialize-GalleryClient
    try {
        $published = @(Get-PublishedVersion)
    } catch {
        Add-Result -Results $results -Step 'gallery' -Failure "could not list TerminalStyles on the Gallery: $($_.Exception.Message)"
        return (Complete-Run -Results $results -Title $title)
    }
    if ($published -notcontains $newest) {
        Add-Result -Results $results -Step 'gallery' -Failure ("TerminalStyles.psd1 says $newest, which the Gallery does not list. " +
            'Publish first: docs/RELEASING.md pushes the tag once the Gallery serves the version.')
        return (Complete-Run -Results $results -Title $title)
    }
    if (-not $From) { $From = Select-StartVersion -Published $published -Newest $newest }
    $fromVersion = $null
    if (-not $From -or -not [version]::TryParse($From, [ref]$fromVersion) -or
        $published -notcontains $From -or $fromVersion -ge [version]$newest) {
        Add-Result -Results $results -Step 'gallery' -Failure "nothing to start from: '$From' is not a release on the Gallery older than $newest"
        return (Complete-Run -Results $results -Title $title)
    }
    if (-not $UninstallWith) { $UninstallWith = $newest }
    if (@($From, $newest) -notcontains $UninstallWith) {
        Add-Result -Results $results -Step 'gallery' -Failure ("the uninstall can only run with $From or $newest, " +
            "the two versions installed by then; asked for '$UninstallWith'")
        return (Complete-Run -Results $results -Title $title)
    }
    $title = '{0}: {1} -> {2}, uninstalled with {3}' -f $title, $From, $newest, $UninstallWith
    Write-Host $title

    $feed = Wait-GalleryNewest -Newest $newest
    if (-not $feed.Settled) {
        Add-Result -Results $results -Step 'gallery' -Failure ("the update feed did not name $newest three times running " +
            "within 10 minutes; last answer: '$($feed.Last)'")
        return (Complete-Run -Results $results -Title $title)
    }

    # 1. Install the release its users are updating from.
    $step = Invoke-Phase -Name 'install' -Body $script:InstallBody.Replace('@FROM@', $From) -WorkDir $workDir
    $copies = @(Get-TerminalStylesCopy)
    $versions = @($copies | ForEach-Object { $_.Version })
    if ($step.ExitCode -ne 0 -or ($versions -join ', ') -ne $From) {
        $now = if ($versions.Count -gt 0) { $versions -join ', ' } else { 'nothing' }
        Add-Result -Results $results -Step 'install' -Failure "installing $From failed (exit $($step.ExitCode)); installed now: $now"
        return (Complete-Run -Results $results -Title $title)
    }
    Add-Result -Results $results -Step 'install' -Detail "$From, in $($copies[0].Path)"

    # 2. The update notice. Tried again only when nothing was offered: the
    # request has a two-second timeout, as it does for every user.
    $verdict = $null
    $result = $null
    $protocol = $null
    for ($i = 1; $i -le 3; $i++) {
        $step = Invoke-Phase -Name "notice-$i" -Body $script:NoticeBody.Replace('@VERSION@', $From) -WorkDir $workDir
        $said = [regex]::Match($step.Output, 'Update available \(([^ ]+) -> ([^ )]+)\)\. Run: tstyles update')
        $result = $null
        if ($said.Success) {
            $result = [pscustomobject]@{ Installed = $said.Groups[1].Value; Remote = $said.Groups[2].Value }
        }
        $protocol = Get-PhaseResult -Output $step.Output
        $before = ''
        $after = ''
        if ($protocol) { $before = "$($protocol.Before)"; $after = "$($protocol.After)" }
        $verdict = Get-NoticeVerdict -Result $result -From $From -Newest $newest -ProtocolBefore $before -ProtocolAfter $after
        if (-not $verdict -or $result) { break }
        if ($i -lt 3) { Start-Sleep -Seconds 20 }
    }
    $detail = "Update available ($From -> $newest)"
    if ($desktop -and $protocol) { $detail += "; SecurityProtocol back to '$($protocol.After)' afterwards" }
    if ($i -gt 1) { $detail += " (attempt $i of 3)" }
    Add-Result -Results $results -Step 'notice' -Failure $verdict -Detail $detail

    # 3. tstyles update. Tried again only while nothing has changed on disk,
    # which is what a feed still answering with the old version looks like.
    $versions = @()
    for ($i = 1; $i -le 3; $i++) {
        $step = Invoke-Phase -Name "update-$i" -Body $script:UpdateBody.Replace('@VERSION@', $From) -WorkDir $workDir
        $versions = @(Get-TerminalStylesCopy | ForEach-Object { $_.Version })
        $verdict = Get-UpdateVerdict -Output $step.Output -From $From -Newest $newest -Versions $versions
        if (-not $verdict -or ($versions -join ', ') -ne $From) { break }
        if ($i -lt 3) { Start-Sleep -Seconds 30 }
    }
    $detail = "Updated $From -> $newest; installed now: $($versions -join ', ')"
    if ($i -gt 1) { $detail += " (attempt $i of 3)" }
    Add-Result -Results $results -Step 'update' -Failure $verdict -Detail $detail

    # 4. The next session, which "Open a new tab to use it" promises.
    if (-not $verdict) {
        $step = Invoke-Phase -Name 'next-session' -Body $script:NextSessionBody -WorkDir $workDir
        $loads = [regex]::Match($step.Output, 'NEXT SESSION LOADS (\S+)').Groups[1].Value
        $failure = $null
        if ($loads -ne $newest) { $failure = "a new session loads '$loads', not $newest" }
        Add-Result -Results $results -Step 'new session' -Failure $failure -Detail "a new session loads $newest"
    }

    # 5. tstyles uninstall, with both versions installed side by side -- the
    # case Uninstall-Module without -AllVersions gets wrong.
    $before = @(Get-TerminalStylesCopy)
    $beforeVersions = @($before | ForEach-Object { $_.Version })
    if ($beforeVersions -notcontains $UninstallWith) {
        $now = if ($beforeVersions.Count -gt 0) { $beforeVersions -join ', ' } else { 'nothing' }
        Add-Result -Results $results -Step 'uninstall' -Failure "could not run it: $UninstallWith is not installed (installed: $now)"
    } else {
        $step = Invoke-Phase -Name 'uninstall' -Body $script:UninstallBody.Replace('@VERSION@', $UninstallWith) -WorkDir $workDir
        $left = @(Get-TerminalStylesCopy | ForEach-Object { $_.Path })
        $verdict = Get-UninstallVerdict -Output $step.Output -CopiesLeft $left
        Add-Result -Results $results -Step 'uninstall' -Failure $verdict -Detail ('signed off "TerminalStyles uninstalled.", and none of the {0} installed is left' -f
            $(if ($before.Count -eq 1) { 'one copy' } else { "$($before.Count) copies" }))
    }

    return (Complete-Run -Results $results -Title $title)
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-LiveGalleryCheck -From $From -UninstallWith $UninstallWith)
}
