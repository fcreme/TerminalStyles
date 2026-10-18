# update.ps1 -- install kind, the update check, and register / update / uninstall.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Everything here branches on HOW TerminalStyles was installed. A PSGallery copy
# updates through Update-PSResource and uninstalls through Uninstall-PSResource;
# a bootstrap copy re-runs the installer and removes an install-managed list by
# hand. Getting that wrong is how an "uninstall" used to leave every new zsh tab
# fully themed.

function Get-TerminalStylesInstallKind {
    # Returns 'Bootstrap' if the module loaded from %LOCALAPPDATA%\TerminalStyles\
    # (the iwr-installer path), else 'PSResourceGet' (PSModulePath-based install).
    # Used by Invoke-TerminalStylesUpdate / Invoke-TerminalStylesUninstall to
    # delegate to the right mechanism, and by Test-UpdateAvailable to pick what
    # "newer" is measured against: a commit on main, or a Gallery release.
    #
    # Note: $script:TStylesModuleRoot is set during module load. For installs
    # made before the dual-root refactor (sub-project C), the variable still
    # has the right value because the init block sets it from $PSScriptRoot.
    $bootstrapDir = Get-TStylesDataRoot
    if ($script:TStylesModuleRoot -eq $bootstrapDir) { return 'Bootstrap' }
    return 'PSResourceGet'
}

function Test-UpdateAvailable {
    # Returns a pscustomobject naming what is installed and what is newer, or
    # $null when nothing newer is known: already current, nothing on record to
    # compare, inside the 24h throttle window, or the request failed.
    #
    # Newer means whatever `tstyles update` would fetch, so it follows the
    # install kind:
    #   Bootstrap      the commit on origin/main against .installed-sha, as
    #                  7-char SHAs -- the installer tracks main.
    #   PSResourceGet  the PowerShell Gallery's newest stable version against
    #                  the newest one installed, as version strings --
    #                  Update-PSResource installs the Gallery's.
    #
    # Throttled to <= 1 HTTP request per 24 hours per machine via
    # .last-update-check. The timestamp is rewritten on every attempt
    # (success or failure), so an offline machine doesn't retry the
    # 2s timeout on every single tstyles invocation.
    $stampFile = Join-Path $script:TStylesDataRoot '.last-update-check'

    # --- Throttle gate ---
    # If the stamp file is present and parses as a datetime less than 24h old,
    # skip everything below. Unparseable / missing -> fall through and the
    # timestamp write at the end will overwrite with a valid value (self-heal).
    if (Test-Path -LiteralPath $stampFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false)).Trim()
            $stamp = [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (((Get-Date) - $stamp).TotalHours -lt 24) { return $null }
        } catch { }
    }

    if ((Get-TerminalStylesInstallKind) -eq 'PSResourceGet') {
        # This arm returned $null outright, on the reasoning that a Gallery copy
        # is updated by Update-PSResource whenever the user runs `tstyles
        # update`. But this notice is how they learn there is anything to run
        # it for, and 0.9.0 went out without one Gallery install hearing of it.
        #
        # Against the newest version INSTALLED rather than the one this session
        # loaded: after `tstyles update` an open tab keeps the old copy until it
        # is reopened, and telling it to update again would ask for what is
        # already done. Nothing installed to compare against -- a source
        # checkout imported by path -- gets the answer the bootstrap arm gives a
        # missing .installed-sha: no request, nothing said.
        $installed = Get-NewestInstalledVersion
        if (-not $installed) { return $null }
        $latest = Get-GalleryLatestVersion
        Write-UpdateCheckStamp -Path $stampFile

        # As versions: as text, '0.9.9' sorts after '0.9.10'.
        $have = $null; $offered = $null
        if ($latest -and [version]::TryParse($installed, [ref]$have) -and
            [version]::TryParse($latest, [ref]$offered) -and $offered -gt $have) {
            return [pscustomobject]@{ Installed = $installed; Remote = $latest }
        }
        return $null
    }

    $shaFile = Join-Path $script:TStylesDataRoot '.installed-sha'
    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        $resp = Invoke-UpdateCheckRequest -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main'
        $remote = $resp.sha
    } catch { }

    # --- Throttle write ---
    # Always write the timestamp, even on API failure. Without this, an
    # offline machine would retry the 2s timeout on every invocation.
    Write-UpdateCheckStamp -Path $stampFile

    if ($remote -and $remote -ne $installed) {
        return [pscustomobject]@{
            Installed = $installed.Substring(0, [Math]::Min(7, $installed.Length))
            Remote    = $remote.Substring(0, [Math]::Min(7, $remote.Length))
        }
    }
    return $null
}

function Enable-Tls12 {
    # Adds TLS 1.2 to the session's SecurityProtocol where it is missing, and
    # returns the value to put back afterwards -- or $null when nothing was
    # changed. Windows PowerShell 5.1 only: pwsh does not read
    # ServicePointManager at all.
    #
    # Every host the update path talks to -- api.github.com,
    # raw.githubusercontent.com, the PowerShell Gallery -- refuses anything
    # older, and on .NET Framework the default SecurityProtocol can leave it
    # out. install.ps1 opens the same door for its own downloads and shuts it
    # after; Restore-SecurityProtocol is the other half, so a tstyles command
    # leaves the session's setting as it found it.
    #
    # 0 is SystemDefault, and is left alone: Windows chooses then, and from
    # Windows 8 on it offers TLS 1.2 by itself, so adding the flag would only
    # narrow the session to TLS 1.2 -- and take TLS 1.3 away. Compared as a
    # number because the name exists only from .NET 4.7.
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSEdition -ne 'Desktop') { return $null }
    try {
        $current = [Net.ServicePointManager]::SecurityProtocol
        if ([int]$current -eq 0 -or $current.HasFlag([Net.SecurityProtocolType]::Tls12)) { return $null }
        [Net.ServicePointManager]::SecurityProtocol = $current -bor [Net.SecurityProtocolType]::Tls12
        return $current
    } catch { return $null }
}

function Restore-SecurityProtocol {
    # Puts back what Enable-Tls12 returned. $null means it changed nothing.
    [CmdletBinding()]
    param([AllowNull()]$Previous)
    if ($null -eq $Previous) { return }
    try { [Net.ServicePointManager]::SecurityProtocol = $Previous } catch { }
}

function Invoke-UpdateCheckRequest {
    # The update check's one GET, for either install kind, with a two-second
    # timeout: it runs inside an ordinary tstyles command, and an unreachable
    # host should cost the user about that and nothing else (on 5.1 a stalled
    # DNS lookup is not covered by it). Without TLS 1.2 on a 5.1 session
    # that lacks it, the request failed into the caller's silent catch and the
    # notice could never appear.
    #
    # Our own User-Agent: GitHub's API requires one, and PowerShell's default
    # names the OS, its own version and the locale, which README's "no payload
    # sent" does not cover.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    $restoreTls = Enable-Tls12
    try {
        Invoke-RestMethod -Uri $Uri -UserAgent 'TerminalStyles-UpdateCheck' -TimeoutSec 2 -ErrorAction Stop
    } finally {
        Restore-SecurityProtocol -Previous $restoreTls
    }
}

function Get-GalleryLatestVersion {
    # The newest stable TerminalStyles on the PowerShell Gallery, as a string,
    # or $null when that could not be read.
    #
    # The Gallery's v2 feed rather than Find-PSResource, which takes no
    # timeout. IsLatestVersion is the newest non-prerelease, which is what
    # Update-PSResource installs. The quotes around the id are load-bearing:
    # without them the Gallery answers with an empty feed, not an error.
    #
    # Invoke-RestMethod hands an Atom feed back as its <entry> elements, and
    # through the XML adapter a property that carries an attribute comes back
    # as the element rather than its text -- the feed's typed flags already do
    # -- so Version is read for its text either way. Anything else (a captive
    # portal's HTML page, an empty feed) has no Version, and reads as $null.
    [CmdletBinding()]
    param()
    try {
        $entry = @(Invoke-UpdateCheckRequest -Uri 'https://www.powershellgallery.com/api/v2/FindPackagesById()?id=''TerminalStyles''&$filter=IsLatestVersion')[0]
        $version = $entry.properties.Version
        if ($version -is [System.Xml.XmlNode]) { $version = $version.InnerText }
        if ($version -is [string] -and $version.Trim()) { return $version.Trim() }
    } catch { }
    return $null
}

function Write-UpdateCheckStamp {
    # Spends the day's check. Culture-pinned because the throttle gate parses it
    # back with InvariantCulture, and a current-culture date written under a
    # non-Gregorian calendar reads back centuries off. Best effort: a stamp
    # that cannot be written means the next command checks again, not that
    # this one fails.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $now = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($Path, $now, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Show-UpdateNoticeIfAvailable {
    # Prints the one-line yellow update notice if something newer is out: a
    # commit on origin/main for a bootstrap install, a release on the
    # PowerShell Gallery for a Gallery one. Called by list, current, random, a
    # direct apply and reset; the picker and the tuner call
    # Test-UpdateAvailable themselves and hold the notice until they give the
    # screen back. Test-UpdateAvailable short-circuits inside the 24h throttle
    # window, so the notice displays at most once per day while an update is
    # pending.
    #
    # Not when stdout is redirected. zsh and bash run tstyles as a child pwsh,
    # where Write-Host goes to stdout, so `x=$(tstyles current)` captured the
    # notice ahead of the name `current` promises to print alone -- and spent
    # the day's check on output nobody would read, so no later command showed
    # it either. The picker and the tuner hold their check back from a
    # redirected run for the same reason. Nothing is asked and no stamp is
    # written, so the next command a person sees still gets to show it.
    param(
        # A parameter for the reason Show-CurrentStyle has the same one: the
        # .NET static cannot be mocked, and every CI leg runs redirected.
        [bool]$OutputRedirected = [Console]::IsOutputRedirected
    )
    if ($OutputRedirected) { return }
    $pending = Test-UpdateAvailable
    if ($pending) {
        Write-Host ("Update available ({0} -> {1}). Run: tstyles update" -f $pending.Installed, $pending.Remote) -ForegroundColor Yellow
        Write-Host ""
    }
}

function Get-NewestInstalledVersion {
    # The highest TerminalStyles version on the module path, as a string, or
    # $null when that cannot be read. Its own function because the update path
    # asks twice -- once either side of the install -- and the two readings have
    # to be taken the same way to be comparable.
    [CmdletBinding()]
    param()
    try {
        $m = @(Get-Module -ListAvailable -Name TerminalStyles -ErrorAction Stop |
               Sort-Object Version -Descending)
        if (-not $m) { return $null }
        return $m[0].Version.ToString()
    } catch { return $null }
}

function Get-InstalledReleaseNotes {
    # The ReleaseNotes of an installed version, or '' when unreadable. Read from
    # the manifest on disk rather than from the loaded module: after an update
    # the session still holds the OLD one, so $MyInvocation and the imported
    # module would both report what was just replaced.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)
    try {
        $m = @(Get-Module -ListAvailable -Name TerminalStyles -ErrorAction Stop |
               Where-Object { $_.Version.ToString() -eq $Version })
        if (-not $m) { return '' }
        $data = Test-ModuleManifest -Path $m[0].Path -ErrorAction Stop
        return "$($data.ReleaseNotes)"
    } catch { return '' }
}

function Get-UpdateOutcome {
    <#
    .SYNOPSIS
    Did the update change anything: 'updated', 'current', or 'unknown'.

    .DESCRIPTION
    `Update-PSResource` is a no-op when the newest version is already installed,
    and says nothing either way -- so the PSGallery arm printed "Update
    complete" whether it had updated or not. Running `tstyles update` on the
    latest version reported success for work it had not done, which is this
    project's most-shipped defect class and the one the Bootstrap arm already
    gets right ("Already up to date (abc1234)").

    'unknown' is a real answer, not a failure: the version can be unreadable
    before or after (a repository that answers slowly, a module path the user
    has since changed), and claiming either outcome would be guessing. The
    caller says what it knows and no more.

    Pure so it can be tested; the command around it cannot be.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Before, [AllowNull()][string]$After)

    if (-not $Before -or -not $After) { return 'unknown' }
    $b = $null; $a = $null
    if (-not [version]::TryParse($Before, [ref]$b)) { return 'unknown' }
    if (-not [version]::TryParse($After,  [ref]$a)) { return 'unknown' }
    if ($a -gt $b) { return 'updated' }
    if ($a -eq $b) { return 'current' }
    # After < Before. Not a state the gallery produces, but a pinned or
    # side-loaded copy can, and calling that an update would be false.
    return 'unknown'
}


function Invoke-TerminalStylesUpdate {
    [CmdletBinding()]
    param(
        [switch]$Force,
        # Whether this engine has PSResourceGet's Update-PSResource. A parameter
        # so both answers can be driven on every CI leg: Windows PowerShell 5.1
        # has no PSResourceGet, and pwsh 7.4+ always does. DontShow because
        # this command is exported, and a test seam is not part of its surface.
        [Parameter(DontShow)]
        [bool]$HasPSResourceGet = [bool](Get-Command Update-PSResource -ErrorAction SilentlyContinue)
    )

    Write-Host ""
    Write-Host "Updating TerminalStyles..." -ForegroundColor Cyan

    # TLS 1.2 for every request below, put back on the way out. The update
    # notice allows it for its own request, so on a 5.1 session whose default
    # leaves it out the notice now appears -- and sends the user here, where the
    # Gallery, api.github.com and raw.githubusercontent.com need it just as
    # much. Without it the command the notice recommends failed, and so did the
    # retry hint printed beneath the failure.
    $restoreTls = Enable-Tls12
    try {
        switch (Get-TerminalStylesInstallKind) {
            'PSResourceGet' {
                # Update-PSResource where PSResourceGet is present, and
                # Update-Module where it is not. Windows PowerShell 5.1 ships
                # PowerShellGet but not PSResourceGet, and the Gallery's own
                # page leads with Install-Module, so a copy installed that way
                # could only fail here -- "The term 'Update-PSResource' is not
                # recognized" -- above a retry hint naming the same command.
                # The update notice, which now reaches Gallery installs, would
                # have sent them here once a day.
                #
                # -Force is the answer -TrustRepository gives Update-PSResource.
                # Update-Module has no such switch, and PSGallery is untrusted
                # unless the user said otherwise, so it asks -- default No --
                # and a No installs nothing while raising no error: the version
                # would not move, and this arm would print "Already the latest"
                # over an update that never happened. -Force also reinstalls a
                # copy that is already current, which costs a download and
                # claims nothing false.
                $retry = if ($HasPSResourceGet) { 'Update-PSResource -Name TerminalStyles -TrustRepository' }
                         else                   { 'Update-Module -Name TerminalStyles -Force' }
                try {
                    # What was here BEFORE, so the report afterwards can be true.
                    # Update-PSResource is a no-op when the newest version is already
                    # installed and says nothing either way, so this arm reported
                    # "Update complete" for work it had not done -- while the
                    # Bootstrap arm below already distinguished the two. One command,
                    # two install kinds, two different answers to "did anything
                    # happen?".
                    $before = Get-NewestInstalledVersion
                    if ($HasPSResourceGet) {
                        Update-PSResource -Name TerminalStyles -TrustRepository -ErrorAction Stop
                    } else {
                        Update-Module -Name TerminalStyles -Force -ErrorAction Stop
                    }
                    $after  = Get-NewestInstalledVersion

                    Write-Host ""
                    switch (Get-UpdateOutcome -Before $before -After $after) {
                        'current' {
                            Write-Host "  Already the latest ($after). Nothing to do." -ForegroundColor Green
                        }
                        'updated' {
                            Write-Host ("  Updated {0} -> {1}" -f $before, $after) -ForegroundColor Green
                            $notes = Get-SentenceSummary -Notes (Get-InstalledReleaseNotes -Version $after)
                            if ($notes) {
                                Write-Host ""
                                Write-Host "  $notes" -ForegroundColor Gray
                            }
                            Write-Host ""
                            Write-Host "  Open a new tab to use it, or run:" -ForegroundColor Yellow
                            Write-Host "    Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Cyan
                        }
                        default {
                            # The version could not be read on one side or the other.
                            # Say what happened and what was not established, rather
                            # than picking the cheerful branch.
                            Write-Host "  Update ran. Could not read the installed version, so this cannot say" -ForegroundColor Yellow
                            Write-Host "  whether anything changed. Check with: tstyles help" -ForegroundColor Yellow
                            Write-Host "  Open a new tab, or run:" -ForegroundColor Yellow
                            Write-Host "    Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Cyan
                        }
                    }
                } catch {
                    Write-Host "Update failed: $_" -ForegroundColor Red
                    Write-Host "You can retry manually:" -ForegroundColor Yellow
                    Write-Host "  $retry" -ForegroundColor Cyan
                }
            }
            'Bootstrap' {
                # Re-run the iwr installer one-liner. Existing behavior, preserved
                # so users who installed via iwr|iex keep updating that way.

                # Cheap check first: if we already have the current main SHA, skip
                # the ~10MB ZIP download entirely. -Force overrides.
                $shaFile = Join-Path $script:TStylesDataRoot '.installed-sha'
                if (-not $Force -and (Test-Path -LiteralPath $shaFile)) {
                    try {
                        $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
                        $resp = Invoke-RestMethod `
                            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
                            -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
                            -TimeoutSec 5 -ErrorAction Stop
                        if ($resp.sha -and $resp.sha -eq $installed) {
                            Write-Host "Already up to date ($($installed.Substring(0,7))). Use -Force to reinstall anyway." -ForegroundColor Green
                            return
                        }
                    } catch {
                        # Network failure -- fall through to full download.
                    }
                }

                # Suppress IWR progress bar (dominant cost on WinPS 5.1).
                $prevProgress = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                try {
                    $installerScript = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1' -UseBasicParsing).Content
                    Invoke-Expression $installerScript
                    Write-Host ""
                    Write-Host "Update complete. To use the new tstyles code in THIS session," -ForegroundColor Yellow
                    Write-Host "open a new pwsh tab, or run:" -ForegroundColor Yellow
                    Write-Host "  . `$PROFILE" -ForegroundColor Cyan
                } catch {
                    Write-Host "Update failed: $_" -ForegroundColor Red
                    Write-Host "You can retry manually:" -ForegroundColor Yellow
                    Write-Host "  iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex" -ForegroundColor Cyan
                } finally {
                    $ProgressPreference = $prevProgress
                }
            }
        }
    } finally {
        Restore-SecurityProtocol -Previous $restoreTls
    }
}

function Invoke-TerminalStylesRegister {
    # Adds `Import-Module TerminalStyles -DisableNameChecking` to both
    # PowerShell engines' $PROFILE files, wrapped in the same
    # # ===== TerminalStyles BEGIN ===== / END markers that
    # Invoke-TerminalStylesUninstall knows how to strip.
    #
    # Idempotent: skips an engine whose $PROFILE already has the block.
    # -Force replaces the existing block (strip + re-add).
    #
    # -Targets is an internal/test injection: tests pass a synthetic
    # array of objects with ProfilePath/Exists/HasLoader/Label fields,
    # bypassing the real engine discovery (which Pester 5 can't cleanly
    # mock because it goes through the call-operator `& $cmd.Source`).
    # Real callers never pass -Targets and get the normal discovery.
    [CmdletBinding()]
    param(
        [switch]$Force,
        [object[]]$Targets,
        # Pre-granted consent, for automation that means it. Without this a
        # session with no console refuses rather than assuming yes.
        [switch]$Yes
    )

    $loaderBegin = '# ===== TerminalStyles BEGIN ====='
    $loaderEnd   = '# ===== TerminalStyles END ====='

    # Get-RcFileEncoding, not UTF-8, for the reason its docstring gives: this
    # reads the WHOLE of a file the user owns and writes the WHOLE of it back,
    # so a byte that is not valid UTF-8 -- a latin-1 comment, a stray byte from
    # an old editor -- decoded to U+FFFD and was written back as the
    # replacement character. That was fixed for rc files and the $PROFILE half
    # never got it. ISO-8859-1 round-trips every byte 0-255 unchanged, and the
    # markers and the loader line are ASCII either way.

    # By NAME only when the module is somewhere PowerShell will look. A
    # bootstrap install is not on $env:PSModulePath -- which is exactly why
    # install.ps1 writes the full-path form, and why Get-ShellRcCandidate's
    # neighbours in terminals.ps1 say so out loud -- so `Import-Module
    # TerminalStyles` there resolves to nothing.
    #
    # This wrote the by-name form unconditionally, and it uses the same
    # BEGIN/END markers the installer does, so `tstyles register -Force` on a
    # bootstrap install stripped the loader that worked and replaced it with one
    # that does not. It then printed "Registered in <profile>" and
    # "TerminalStyles will auto-load on every new shell tab", while every new
    # tab in fact opened with a red "no valid module file was found in any
    # module directory" and no tstyles command at all. Recovery meant editing
    # $PROFILE by hand, which nothing told the user.
    #
    # The two forms below must stay identical to install.ps1's -- there is a
    # test that compares them, because install.ps1 is fetched and piped to iex
    # before the module exists and so cannot dot-source this file.
    $loaderImport = if ((Get-TerminalStylesInstallKind) -eq 'Bootstrap') {
        if ((Get-TStylesPlatform) -eq 'Windows') {
            'Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking'
        } else {
            'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1')
        }
    } else {
        'Import-Module TerminalStyles -DisableNameChecking'
    }

    $loaderBody  = @"
$loaderBegin
$loaderImport
$loaderEnd
"@

    if (-not $PSBoundParameters.ContainsKey('Targets')) {
        # Discover every engine's $PROFILE -- one target per distinct FILE.
        #
        # This was its own copy of the discovery loop, with no merge step, while
        # the uninstall half had been de-duplicated. Off Windows the two
        # candidates are `pwsh` and `pwsh-preview`, which on a machine carrying
        # the 7-preview build both answer with the same path: the listing below
        # printed that one file on two rows, consent said "2 PowerShell profile
        # file(s)", and the write loop rewrote it twice.
        #
        # -IncludeMissing because registration CREATES a $PROFILE that is not
        # there yet; removal is the half that wants existing files only.
        #
        # Bound, not truthy: `-Targets @()` is a caller asking for an empty list,
        # and reading it as "no targets given" sent a test's empty sandbox
        # straight back to the real engines on the operator's machine.
        $targets = @(Resolve-PowerShellProfileTarget -IncludeMissing)
    } else {
        $targets = @($Targets)
        # For test-injected targets, ensure required fields exist
        foreach ($t in $targets) {
            if ($null -eq $t.Exists)    { $t | Add-Member -NotePropertyName Exists    -NotePropertyValue (Test-Path -LiteralPath $t.ProfilePath) -Force }
            if ($null -eq $t.HasLoader) { $t | Add-Member -NotePropertyName HasLoader -NotePropertyValue $false -Force }
            if ($null -eq $t.Label)     { $t | Add-Member -NotePropertyName Label     -NotePropertyValue 'PowerShell' -Force }
        }
    }

    if (-not $targets) {
        Write-Host ""
        Write-Host ("No PowerShell engine found on PATH (looked for: {0}). Nothing to do." -f
                    ((Get-PowerShellEngineCandidate).Exe -join ', ')) -ForegroundColor Yellow
        return
    }

    # Detect existing loader block per target.
    #
    # The span may not cross a second BEGIN, the same tempering Register-ShellLoader
    # carries and for the same reason: this pattern is also what -Force STRIPS with
    # below, and `.*?` under (?s) runs from the first BEGIN to the first END
    # anywhere after it. A $PROFILE with a stray or duplicated marker -- a hand
    # edit, a merged dotfile, an interrupted write -- lost every one of the user's
    # own lines in between, and lost them outright, since the strip replaces with
    # nothing rather than with the block. No backup either: the first-touch rule
    # skips a file that already carries a BEGIN.
    $blockPattern = "(?ms)$([regex]::Escape($loaderBegin))(?:(?!$([regex]::Escape($loaderBegin)))[\s\S])*?$([regex]::Escape($loaderEnd))\r?\n?"
    foreach ($t in $targets) {
        $malformed = $false
        if ($t.Exists) {
            $content = [System.IO.File]::ReadAllText($t.ProfilePath, (Get-RcFileEncoding))
            $t.HasLoader = ($content -match $blockPattern)
            # A BEGIN marker with no END to close it: the state
            # Register-ShellLoader and Unregister-ShellLoader both call
            # 'malformed', on the rc half of this same job. This half had no
            # such arm, and the two halves of the pair may not disagree about
            # what a file IS. Without it a $PROFILE carrying an orphan marker --
            # a hand edit, a merged dotfile, an interrupted write -- was written
            # anyway: the tempered pattern above matches nothing, so the strip
            # was a no-op and a second, complete block was appended below the
            # orphan. It was also the one shape that got NO backup, because the
            # first-touch rule was being asked about the bare BEGIN marker
            # rather than about a block we own. Refusing is the answer the rc
            # half already gives.
            $malformed = (-not $t.HasLoader) -and ($content -match [regex]::Escape($loaderBegin))
        }
        $t | Add-Member -NotePropertyName Malformed -NotePropertyValue $malformed -Force
    }

    # Decide what to do per target
    $toWrite = @()
    $refused = @()
    foreach ($t in $targets) {
        if ($t.Malformed) {
            Write-Host ("  ! {0} has a TerminalStyles BEGIN marker with no matching END." -f $t.ProfilePath) -ForegroundColor Red
            Write-Host "    Nothing was written. Complete or delete that block by hand and run this" -ForegroundColor Red
            Write-Host "    again -- registering around it would leave two markers we cannot tell apart." -ForegroundColor Red
            $refused += $t
            continue
        }
        if ($t.HasLoader -and -not $Force) {
            Write-Host "  Already registered in $($t.ProfilePath) (use -Force to replace)" -ForegroundColor Gray
            continue
        }
        $toWrite += $t
    }

    if (-not $toWrite) {
        Write-Host ""
        # "Nothing to do." is true for a file that is already registered and
        # false for one we refused to touch, and the second is the user's cue to
        # go and fix it.
        if ($refused.Count -gt 0) {
            Write-Host ("Not registered in: {0}" -f (($refused | ForEach-Object { $_.Label }) -join ', ')) -ForegroundColor Red
        } else {
            Write-Host "Nothing to do." -ForegroundColor Yellow
        }
        return
    }

    # Single confirm prompt covering all targets
    Write-Host ""
    Write-Host "Will register the TerminalStyles loader in:" -ForegroundColor Cyan
    foreach ($t in $toWrite) {
        Write-Host "  $($t.Label): $($t.ProfilePath)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "The loader is one line wrapped in BEGIN/END markers:" -ForegroundColor Gray
    # $loaderImport, not a second literal of it. The whole job of this screen is
    # "here is the one line I am about to put in your $PROFILE", and it named the
    # by-name form on a bootstrap install, where the line actually written is the
    # full-path one -- the same half-a-symmetry 0.8.21 left behind when it fixed
    # the WRITE. Printing the variable is what stops the two drifting again.
    Write-Host "  $loaderImport" -ForegroundColor Cyan
    Write-Host ""
    # `$ans -match '^(?i)n'` was falsy at EOF -- AutomationNull compares as an
    # empty collection -- so `tstyles register < /dev/null` wrote the loader
    # into BOTH engines' $PROFILE files with nobody having answered.
    if (-not (Confirm-Action -Question 'Continue? [y/N]' -Yes:$Yes `
                -Consequence "writes the loader block into $($toWrite.Count) PowerShell profile file(s)")) {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # Write the block per target (strip first for -Force path).
    #
    # Guarded, with a per-target status, which is the contract Register-ShellLoader
    # documents for the rc half of the same job -- "'failed' rather than an
    # exception ... so the user saw a stack trace and had no idea which of their
    # rc files had been touched". This half had none of it: the read and the
    # write were bare, and "Registered in <path>" printed unconditionally on the
    # line after. An unwritable $PROFILE (read-only bit, root-owned, a OneDrive
    # lock or a Files-On-Demand placeholder) therefore produced a red .NET error
    # AND a green success line for the same file, and the command still closed
    # on "TerminalStyles will auto-load on every new shell tab."
    $failed = @()
    foreach ($t in $toWrite) {
        $bak = $null
        try {
            $profileDir = Split-Path -Parent $t.ProfilePath
            if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
                New-Item -ItemType Directory -Path $profileDir -Force -ErrorAction Stop | Out-Null
            }

            $existing = if ($t.Exists) {
                [System.IO.File]::ReadAllText($t.ProfilePath, (Get-RcFileEncoding))
            } else { '' }
            # The file as the USER last left it. Both arguments to the
            # first-touch rule below are about this, not about what is left
            # after the strip.
            $original = $existing

            if ($existing -match $blockPattern) {
                $existing = [regex]::Replace($existing, $blockPattern, '')
            }

            $final = ($existing.TrimEnd() + "`r`n`r`n" + $loaderBody + "`r`n").TrimStart()
            # Same first-touch rule the bootstrap installer has always applied to
            # $PROFILE. The module half never did, so `tstyles register` rewrote a
            # hand-maintained profile with no copy kept.
            #
            # Asked with the ORIGINAL content and with the block pattern, which
            # is what install.ps1's Register-LoaderInProfile has always asked
            # (`$originalContent -notmatch $blockPattern`). This asked with the
            # POST-STRIP content and with the bare BEGIN marker, so both halves
            # of the question were wrong and in opposite directions: on a
            # $PROFILE already carrying our block, -Force had just stripped the
            # marker out of the string being examined, so the rule saw a file it
            # had never touched and copied it again on EVERY run -- measured as
            # four .bak- files from four runs, against a CHANGELOG entry (0.8.18)
            # promising "Re-running does not pile up backups". The malformed arm
            # above covers the other direction, where the bare marker matched a
            # file that carried no block of ours at all and skipped the copy.
            $bak = Save-FirstTouchBackup -Path $t.ProfilePath -Content $original -BlockPattern $blockPattern
            [System.IO.File]::WriteAllText($t.ProfilePath, $final, (Get-RcFileEncoding))
        } catch {
            # The backup was taken of a file we then never modified, and the
            # block never landed -- so the next run took another one, and the
            # one after that. Announced only after the write, for the same
            # reason: a backup line for an unchanged file reads as success.
            if ($bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
            $failed += $t
            Write-Host "  ! could not write $($t.ProfilePath)" -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    Check the file's permissions (a read-only profile, one managed by nix" -ForegroundColor Red
            Write-Host "    or chezmoi, or a cloud-synced placeholder) and run this again." -ForegroundColor Red
            continue
        }

        if ($bak) { Write-Host "  Backed up your existing $($t.Label) profile to: $bak" -ForegroundColor Gray }
        Write-Host "  Registered in $($t.ProfilePath)" -ForegroundColor Green
    }

    Write-Host ""
    # The refused ones too: a file we would not touch is as unregistered as one
    # we could not write, and the line that names them is the only place either
    # is summarised.
    $notRegistered = @($failed + $refused)
    if ($notRegistered.Count -gt 0) {
        Write-Host ("Not registered in: {0}" -f (($notRegistered | ForEach-Object { $_.Label }) -join ', ')) -ForegroundColor Red
        Write-Host ""
    }
    # Only when something really was written. The promise is about what a new
    # tab will load, and nothing loads out of a file the block never reached.
    if ($failed.Count -lt @($toWrite).Count) {
        Write-Host "TerminalStyles will auto-load on every new shell tab." -ForegroundColor Cyan
        # Same variable again, with -Force appended rather than spliced in: on a
        # bootstrap install the by-name form this used to print resolves to
        # nothing, so the hint died with a red "no valid module file was found in
        # any module directory" immediately under "Registered in <profile>" --
        # reading as a registration that had just failed when it had succeeded.
        Write-Host "To verify in this session: $loaderImport -Force" -ForegroundColor Gray
        Write-Host ""
    }
}


# Staged by `tstyles shell-init` at RUNTIME, not extracted by the installer, so
# the file manifest cannot know about them -- but they are install-managed all
# the same, and tstyles.sh in particular is what an orphaned rc block loads. Both
# uninstall paths remove them.
$script:TStylesStagedRuntimeFiles = @('tstyles.sh', 'tstyles-cli.ps1')

function Get-UninstallPlan {
    <#
    .SYNOPSIS
    Which entries under the data root does the install own?

    .DESCRIPTION
    The bootstrap install shares its directory with the module's writable state,
    so uninstall has to be exact. install.ps1 records what it placed in
    .installed-files; this reads it back.

    Two failures come from guessing instead. A hand-maintained list named
    'styles' and removed the whole tree -- but bundled themes sit BESIDE the
    user's own there, so a plain `tstyles uninstall` destroyed every style the
    user had authored or tuned, one line after printing "PRESERVE user state".
    The same list also named only 13 of the 21 entries the bootstrap extracts,
    leaving CHANGELOG.md, CONTRIBUTING.md, docs/, tests/ and .github/ behind.

    .OUTPUTS
    @{ Items = <repo-relative paths>; Source = 'manifest' | 'fallback' }

    The fallback covers installs made before the manifest existed. It leaves
    styles/ ALONE -- both bundled and user. The risks are not symmetric: a
    leftover bundled theme is untidy, and a deleted style the user wrote is gone.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataDir)

    $manifestPath = Join-Path $DataDir '.installed-files'
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $lines = [System.IO.File]::ReadAllLines($manifestPath, [System.Text.UTF8Encoding]::new($false))
            $items = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            # Never let a manifest line escape the data root, however it got there.
            $items = @($items | Where-Object { $_ -notmatch '(^|[\\/])\.\.([\\/]|$)' -and
                                               $_ -notmatch '^([a-zA-Z]:|[\\/])' })
            # A style the install shipped, that the user has since made theirs,
            # is no longer only the install's to remove. Saving a tune with
            # "[1] Overwrite" writes it under a BUNDLED name -- which is the
            # option's purpose -- and that name is exactly what the manifest
            # always contains, so uninstall deleted the tuned style one line
            # after printing "PRESERVE user state ... pass -DeleteData to wipe".
            # A Save-As tune under a fresh name survived, which made the loss
            # silent and inconsistent.
            #
            # Through Test-StyleDirectoryIsUsers rather than a second tune.json
            # test, because tune.json was only half the rule: README documents
            # dropping a folder named after a bundled theme to override it, and
            # a hand-drop carries no tune.json. Measured before the fix, on a
            # bootstrap fixture: styles/eva (hand-dropped, no tune.json) in the
            # delete list True, styles/sober (tuned) False. The installer's
            # fingerprint record is what tells the two apart.
            $recorded = Get-InstalledStyleHash -DataDir $DataDir
            $items = @($items | Where-Object {
                if ($_ -notmatch '^styles[\\/][^\\/]+[\\/]?$') { return $true }
                -not (Test-StyleDirectoryIsUsers -StyleDir (Join-Path $DataDir $_) -Recorded $recorded)
            })
            if ($items.Count -gt 0) {
                return @{ Items = @($items + $script:TStylesStagedRuntimeFiles +
                                    '.installed-files' + '.installed-styles')
                          Source = 'manifest' }
            }
        } catch { }
    }

    return @{
        Items = @(
            'tstyles.ps1', 'terminals.ps1', 'lib', 'apply.ps1', 'install.ps1',
            'TerminalStyles.psd1', 'TerminalStyles.psm1',
            'scripts', 'shell', 'fonts.json',
            'README.md', 'LICENSE',
            'CHANGELOG.md', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md', 'SECURITY.md',
            'docs', 'tests', '.github', '.gitignore'
        ) + $script:TStylesStagedRuntimeFiles
        Source = 'fallback'
    }
}

function Resolve-PowerShellProfileTarget {
    <#
    .SYNOPSIS
    One target per DISTINCT $PROFILE file, naming every engine that reports it.

    .DESCRIPTION
    The ONE implementation of "ask each engine where its $PROFILE is, and merge
    the engines that turn out to share one file". There are three consumers of
    that rule -- uninstall (through Get-PowerShellProfileTarget),
    `tstyles register`, and install.ps1's own copy -- and only the first of them
    had it.

    Two engines can share one $PROFILE. On a Mac carrying the 7-preview build,
    `pwsh` and `pwsh-preview` both report
    ~/.config/powershell/Microsoft.PowerShell_profile.ps1. So `tstyles register`
    listed

        PowerShell 7: ~/.config/powershell/Microsoft.PowerShell_profile.ps1
        PowerShell 7 (preview): ~/.config/powershell/Microsoft.PowerShell_profile.ps1

    asked consent for "2 PowerShell profile file(s)", wrote that one file twice
    and printed two "Registered in" lines -- two rows, two writes and a count,
    for one file. Uninstall was de-duplicated when its strip moved into this
    file; nothing else was.

    Label is every engine sharing the file, joined, so a row names what it
    really covers instead of picking one engine and silently dropping the other.
    Labels keeps them apart for the caller that has to decide about ONE engine:
    install.ps1's panel subtracts the engine the user is already sitting in, and
    string equality against a merged label never matches.

    -IncludeMissing is why this could not simply be reused as-is. Removal wants
    only files that EXIST -- a $PROFILE that was never created has no block in
    it -- and registration must be able to create one.

    Paths are compared Ordinal off Windows and OrdinalIgnoreCase on it, the way
    the two filesystems compare them; two engines with genuinely separate
    profile directories (Windows' pair) stay two targets.
    #>
    [CmdletBinding()]
    param([switch]$IncludeMissing)

    $cmp = if ((Get-TStylesPlatform) -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase }
           else                                     { [System.StringComparison]::Ordinal }

    $targets = @()
    foreach ($e in (Get-PowerShellEngineCandidate)) {
        $cmd = Get-Command -Name $e.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        # Cast before Trim: an engine that answered with more than one line
        # hands back an array here, which has no .Trim().
        $profilePath = "$profilePath".Trim()
        if (-not $profilePath) { continue }
        $exists = Test-Path -LiteralPath $profilePath
        if (-not $exists -and -not $IncludeMissing) { continue }

        $seen = $null
        foreach ($t in $targets) {
            if ([string]::Equals($t.ProfilePath, $profilePath, $cmp)) { $seen = $t; break }
        }
        if ($seen) {
            $seen.Labels = @($seen.Labels + $e.Label)
            $seen.Label  = ($seen.Labels -join ' / ')
            continue
        }
        $targets += [pscustomobject]@{
            ProfilePath = $profilePath
            Label       = $e.Label
            Labels      = @($e.Label)
            Exists      = $exists
            HasLoader   = $false
        }
    }
    @($targets)
}

function Get-PowerShellProfileTarget {
    <#
    .SYNOPSIS
    The EXISTING $PROFILE files of the PowerShell engines on this machine.

    .DESCRIPTION
    Pulled out of Invoke-TerminalStylesUninstall so the strip below can be run
    against a sandbox. It could not be before: the paths come from RUNNING each
    engine, so the only $PROFILE any test could reach was the one belonging to
    the operator, and step 3 was therefore never exercised by anything. That is
    the same reason the rc half's omission went four releases unnoticed, and the
    same seam Invoke-TerminalStylesRegister already carries as -Targets.

    Only files that exist: a $PROFILE that was never created has no block in it.
    That, and nothing else, is what this adds to Resolve-PowerShellProfileTarget
    -- which is also where the "two engines, one file" merge lives, so the
    uninstall listing and the strip cannot count a file twice.
    #>
    [CmdletBinding()]
    param()

    @(Resolve-PowerShellProfileTarget)
}

function Remove-PowerShellProfileLoader {
    <#
    .SYNOPSIS
    Strip the loader block from each engine's $PROFILE, and report what happened
    to each.

    .DESCRIPTION
    This was a second, open-coded implementation of Unregister-ShellLoader, and
    it never received any of the three fixes that one did. A $PROFILE is a file
    the USER owns and that predates us, exactly like an rc file, and uninstall
    reads the whole of it and writes the whole of it back:

      * It read and wrote through UTF-8. Get-RcFileEncoding is ISO-8859-1
        precisely because that round-trips every byte 0-255 unchanged, and its
        own docstring describes what UTF-8 does instead: a latin-1 comment or a
        stray byte from an old editor decodes to U+FFFD and is written back as
        the replacement character. Measured on a $PROFILE whose first line was
        `# caf\xe9`: the byte e9 came back as ef bf bd, permanently, from a
        command that was only asked to remove three lines -- and unlike the
        register path, removal takes no backup, because the FIRST TOUCH rule
        deliberately skips a file that already carries our block.
      * A BEGIN with no matching END left the string unchanged, so nothing was
        written AND nothing was said, while the command signed off with "Open a
        new pwsh tab to confirm the loader is gone." Unregister-ShellLoader
        calls that 'malformed' and the rc half prints it in red.
      * The write was unguarded. A read-only $PROFILE -- the nix or chezmoi
        store case Unregister-ShellLoader's own docstring names -- threw out of
        the middle of uninstall, after the module and the rc blocks were
        already gone and before the user-state step ran. The rc half calls that
        'failed', says so, and carries on.

    So it does not re-derive any of that: it calls Unregister-ShellLoader, and
    reports each status the way Invoke-TerminalStylesShellInit -Remove does.

    -Target is an internal/test injection of {ProfilePath, Label} objects, the
    same shape and the same purpose as Invoke-TerminalStylesRegister -Targets.
    Real callers omit it and get Get-PowerShellProfileTarget.

    .OUTPUTS
    [pscustomobject] Removed  = how many blocks went
                     Problems = the $PROFILE paths still carrying one

    The same shape Remove-ShellLoaderBlock returns for the rc half, and for the
    same reason. This returned a COUNT, so 'malformed' and 'failed' were printed
    per file and then thrown away -- they never reached the caller, and
    uninstall's sign-off has no other source of truth. The command therefore
    closed on the unqualified "TerminalStyles uninstalled." and "Open a new pwsh
    tab to confirm the loader is gone" with the block still in a $PROFILE it had
    just said it could not write, one step after step 1 removed the module: every
    new tab then opens on a red module-not-found, and the last two lines the user
    read said the opposite. The rc half of this exact rule has been pinned since
    it was fixed; the $PROFILE half was covered by nothing.
    #>
    [CmdletBinding()]
    param([object[]]$Target)

    if (-not $PSBoundParameters.ContainsKey('Target')) {
        $Target = @(Get-PowerShellProfileTarget)
    }

    $removed = 0
    $problems = @()
    foreach ($t in $Target) {
        switch (Unregister-ShellLoader -Path $t.ProfilePath) {
            'removed' {
                Write-Host "  Removed loader from $($t.ProfilePath)" -ForegroundColor Green
                $removed++
            }
            'malformed' {
                Write-Host ("  ! {0} has a TerminalStyles BEGIN marker with no matching END." -f $t.ProfilePath) -ForegroundColor Red
                Write-Host "    Nothing was removed. Delete the block by hand -- it still loads on every tab." -ForegroundColor Red
                $problems += $t.ProfilePath
            }
            'failed' {
                Write-Host ("  ! could not write {0}" -f $t.ProfilePath) -ForegroundColor Red
                Write-Host "    The loader is still there. Check the file's permissions (a read-only" -ForegroundColor Red
                Write-Host "    profile, or one managed by nix or chezmoi) and remove the block by hand." -ForegroundColor Red
                $problems += $t.ProfilePath
            }
            # 'none' is the ordinary case for an engine that was never
            # registered, and says nothing on purpose.
        }
    }
    [pscustomobject]@{ Removed = $removed; Problems = @($problems) }
}

function Get-OtherEngineModuleRoot {
    # The other PowerShell engine's per-user module folder, as
    # { Path; Engine; Remover }, or nothing.
    #
    # Windows only. PowerShell 7 keeps its per-user modules in
    # Documents\PowerShell\Modules and Windows PowerShell 5.1 in
    # Documents\WindowsPowerShell\Modules, and neither engine's module path has
    # the other's. `register` writes `Import-Module TerminalStyles` by name into
    # both engines' $PROFILE, so a user of both installs it twice -- and an
    # uninstall from one engine removed its own copy, stripped both loaders and
    # signed off "TerminalStyles uninstalled." over the other. Elsewhere pwsh
    # and pwsh-preview share one folder, and there is no other to look in.
    #
    # MyDocuments is the folder both engines build that path from, so a
    # Documents folder redirected into OneDrive is followed here as it is there.
    [CmdletBinding()]
    param()
    if ((Get-TStylesPlatform) -ne 'Windows') { return }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { return }
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [pscustomobject]@{ Path    = (Join-Path $docs 'PowerShell\Modules')
                           Engine  = 'PowerShell 7'
                           Remover = 'Uninstall-PSResource -Name TerminalStyles' }
    } else {
        [pscustomobject]@{ Path    = (Join-Path $docs 'WindowsPowerShell\Modules')
                           Engine  = 'Windows PowerShell 5.1'
                           Remover = 'Uninstall-Module -Name TerminalStyles -AllVersions' }
    }
}

function Get-InstalledModuleCopy {
    # The folder of every TerminalStyles copy a PowerShell engine here could
    # load, or nothing: each one on this engine's module path, which
    # `Import-Module TerminalStyles` searches, and -- on Windows -- each in the
    # other engine's per-user module folder, which it does not
    # (Get-OtherEngineModuleRoot).
    #
    # How uninstall knows whether the module is gone, because the remover's own
    # word cannot be taken for it: Uninstall-PSResource that finds nothing it
    # can remove warns and returns, and -ErrorAction Stop does not fire.
    # Measured against a copy it did not recognise, which stayed installed
    # with no error to catch. A folder this user cannot read is passed over
    # rather than failing the listing: a copy they cannot list is not one they
    # can import.
    [CmdletBinding()]
    param()
    $copies = @(Get-Module -ListAvailable -Name TerminalStyles -ErrorAction SilentlyContinue |
                ForEach-Object { $_.ModuleBase })
    $other = Get-OtherEngineModuleRoot
    if ($other) {
        # Both layouts a module folder can have: versioned, and the manifest
        # directly inside.
        $dir = Join-Path $other.Path 'TerminalStyles'
        if ([System.IO.File]::Exists((Join-Path $dir 'TerminalStyles.psd1'))) { $copies += $dir }
        $copies += @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue |
                     Where-Object { [System.IO.File]::Exists((Join-Path $_.FullName 'TerminalStyles.psd1')) } |
                     ForEach-Object { $_.FullName })
    }
    # Unique without regard to case: on Windows one folder can come back from
    # both listings, spelled the same but for case.
    $copies | Sort-Object -Unique
}

function Write-UninstallLeftoverLead {
    # The line that opens one leftover in uninstall's sign-off. The first one
    # opens the sentence -- "TerminalStyles uninstalled, EXCEPT the loader block
    # in:" -- and every one after it continues it with "...and". One place,
    # because that choice was written out at each leftover, against conditions
    # only some leftovers fed -- and a leftover none of them named never reached
    # the sign-off at all.
    #
    # -Opening is for the one leftover that cannot open that way: "uninstalled,
    # EXCEPT the module" contradicts itself. It goes through here all the same,
    # so whether the sentence has opened is decided in one place and the plain
    # "TerminalStyles uninstalled." cannot follow it.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$What,
        [string]$Opening = 'TerminalStyles uninstalled, EXCEPT'
    )
    $lead = if ($State.Opened) { '...and' } else { $Opening }
    $State.Opened = $true
    Write-Host "$lead $What" -ForegroundColor Yellow
}

function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData,   # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
        # Pre-granted consent. Required for a non-interactive uninstall, which
        # used to happen by accident whenever stdin was at EOF.
        [switch]$Yes,
        # Test seams: real callers omit them and the live $HOME is used. Without
        # these the rc half of this command could not be exercised at all --
        # it resolves rc paths from the live $HOME independently of the data
        # root, so a data-root-only sandbox still edits the operator's own
        # ~/.zshrc. Forwarded by what the caller BOUND, the rule
        # Get-ShellRcCandidate documents.
        [string]$HomeDir,
        [string]$ZDotDir,
        # The same kind of seam for the $PROFILE half, which resolves its paths
        # by RUNNING each engine and so otherwise reaches only the operator's
        # own profile. Same shape as Invoke-TerminalStylesRegister -Targets.
        [object[]]$ProfileTarget,
        # Whether this engine has PSResourceGet's Uninstall-PSResource. A
        # parameter so both answers can be driven on every CI leg, as on
        # Invoke-TerminalStylesUpdate: Windows PowerShell 5.1 has no
        # PSResourceGet, and pwsh 7.4+ always does.
        [bool]$HasPSResourceGet = [bool](Get-Command Uninstall-PSResource -ErrorAction SilentlyContinue)
    )

    $rcSplat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $rcSplat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('ZDotDir')) { $rcSplat.ZDotDir = $ZDotDir }

    # Resolved ONCE, before the listing, and handed to step 3 further down --
    # the listing and the sweep are then the same list by construction. It is
    # resolved once for cost as much as for truth: each entry comes from
    # LAUNCHING an engine, about half a second apiece, so asking a second time
    # at step 3 would pay for it twice and could still answer differently.
    # The @() wraps the WHOLE if, not each arm. A single-element array emitted
    # from an if block is unrolled on its way out, so `= if (...) { @($x) }`
    # assigns $x itself -- and `.Count` on a bare PSCustomObject answers 1 under
    # pwsh 7 and $null under Windows PowerShell 5.1. That is enough to omit the
    # bullet below on exactly one engine, on exactly the leg that has it: the
    # machine with ONE $PROFILE carrying the loader was never told the file was
    # about to be edited, while a machine with two was.
    $profileTargets = @(if ($PSBoundParameters.ContainsKey('ProfileTarget')) { $ProfileTarget }
                        else { Get-PowerShellProfileTarget })

    # Get-WezTermModulePath takes no -ZDotDir, so it gets its own splat rather
    # than $rcSplat. These two lines were on the branch that added the WezTerm
    # writer and were lost resolving the merge with the $PROFILE-strip change
    # above, which touched the same few lines -- while both USES of $wezSplat
    # survived further down the function.
    $wezSplat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $wezSplat.HomeDir = $HomeDir }

    $dataDir = Get-TStylesDataRoot
    $kind = Get-TerminalStylesInstallKind

    # The command step 1 runs on a Gallery install, named here as it will run.
    # Windows PowerShell 5.1 ships PowerShellGet but not PSResourceGet, and the
    # Gallery's own page leads with Install-Module, so a copy installed that
    # way could only fail at Uninstall-PSResource -- "is not recognized" -- and
    # stay installed. -AllVersions because Update-Module installs side by side
    # and Uninstall-Module alone removes only the newest; Uninstall-PSResource
    # removes every version.
    $galleryRemove = if ($HasPSResourceGet) { 'Uninstall-PSResource -Name TerminalStyles' }
                     else                   { 'Uninstall-Module -Name TerminalStyles -AllVersions' }

    Write-Host ""
    # The install kind by what people call it. 'PSResourceGet' is this code's
    # name for every Gallery install, and printed as it is, it told an engine
    # without PSResourceGet that PSResourceGet had been detected.
    $kindLabel = if ($kind -eq 'PSResourceGet') { 'a PowerShell Gallery install' } else { 'a bootstrap install' }
    Write-Host "This will uninstall TerminalStyles (detected: $kindLabel):" -ForegroundColor Yellow
    switch ($kind) {
        'PSResourceGet' {
            Write-Host "  - $galleryRemove" -ForegroundColor Yellow
        }
        'Bootstrap' {
            Write-Host "  - Remove install-managed files from $dataDir" -ForegroundColor Yellow
        }
    }
    # The $PROFILE bullet, from the same list step 3 actually sweeps rather than
    # from a literal. It read "Strip the loader block from pwsh 7 and Windows
    # PowerShell 5.1 $PROFILE files" on every platform -- and Windows PowerShell
    # 5.1 does not exist on macOS or Linux, where the pair is pwsh and
    # pwsh-preview, so the screen named an engine the machine cannot have and a
    # file that cannot exist. The rc bullet below already prints its real paths
    # for the same reason; this is the other half of that. Omitted entirely when
    # no $PROFILE carries anything, because listing files it will not touch
    # would be its own kind of wrong.
    if ($profileTargets.Count -gt 0) {
        Write-Host "  - Strip the loader block from:" -ForegroundColor Yellow
        foreach ($t in $profileTargets) {
            Write-Host ("      {0}: {1}" -f $t.Label, $t.ProfilePath) -ForegroundColor Yellow
        }
    }
    # The zsh/bash half of step 2, which this listing did not mention at all.
    # Step 2 was ADDED because uninstall used to leave the shell side running;
    # the behaviour was fixed and the consent text never caught up, so the
    # command edited ~/.zshrc, ~/.bashrc, ~/.bash_profile and ~/.profile after
    # a prompt that named only the two $PROFILE files -- and that named them
    # precisely, and went on to promise what it would NOT touch, which is
    # exactly what invites a reader to treat the list as complete. The files
    # are printed rather than described: which of them carry a block is
    # knowable here, and is the difference between naming four files and
    # naming the one that is really about to change.
    $shellRcTargets = @(Get-UninstallShellRcTarget @rcSplat)
    if ($shellRcTargets.Count -gt 0) {
        Write-Host "  - Strip the zsh/bash loader block from:" -ForegroundColor Yellow
        foreach ($t in $shellRcTargets) {
            Write-Host ("      {0}" -f $t.Path) -ForegroundColor Yellow
        }
    }
    $wezModule = Get-WezTermModulePath @wezSplat
    if (Test-Path -LiteralPath $wezModule) {
        Write-Host "  - Delete the generated WezTerm style module:" -ForegroundColor Yellow
        Write-Host ("      {0}" -f $wezModule) -ForegroundColor Yellow
        Write-Host "      (your wezterm.lua is NOT edited; its require line is pcall-guarded" -ForegroundColor DarkGray
        Write-Host "       and becomes a no-op once this file is gone)" -ForegroundColor DarkGray
    }
    # VS Code-family settings.json files a style was saved into. Every editor
    # on record, not just the one this terminal belongs to: uninstall can run
    # from anywhere, and once the module is gone nothing can take those keys
    # out again. Named by path, like every other file this prompt lists.
    $vscodeState   = Read-VSCodeState
    $vscodeTargets = @(Get-VSCodeUninstallTarget -State $vscodeState)
    if ($vscodeTargets.Count -gt 0) {
        Write-Host "  - Take the saved style back out of:" -ForegroundColor Yellow
        foreach ($t in $vscodeTargets) {
            Write-Host ("      {0}: {1}" -f $t.Variant, $t.Path) -ForegroundColor Yellow
        }
    }
    if (-not $vscodeState.Ok) {
        Write-Host ("  - Leave VS Code's settings alone: {0} could not be read" -f $vscodeState.Path) -ForegroundColor Yellow
    }
    if ($DeleteData) {
        # The parenthetical is a bounded listing, so it has to be complete: the
        # styles the user made and the ones waiting in .deleted are the two
        # things in there that nothing else can give back. `tstyles restore`
        # makes the trash look like a safety net, and this is the one command
        # that empties it without naming it.
        Write-Host "  - DELETE the entire $dataDir (user state: active style, cached GIFs, throttle stamp," -ForegroundColor Red
        Write-Host "      the styles you made, every style in the trash awaiting tstyles restore, and the" -ForegroundColor Red
        Write-Host "      VS Code consent answers and undo records)" -ForegroundColor Red
    } else {
        Write-Host "  - PRESERVE user state ($dataDir contents -- pass -DeleteData to wipe)" -ForegroundColor Gray
    }
    Write-Host "  - Will NOT modify Windows Terminal's settings.json." -ForegroundColor Yellow
    Write-Host ""
    # The sharp one. `$ans -notmatch '^(?i)y'` is ALSO falsy at EOF, so this
    # "[y/N]" prompt -- which reads as fail-safe -- ran a complete uninstall
    # unattended: install-managed files gone from the data root, the loader
    # stripped out of the user's rc files and both $PROFILE files. With
    # -DeleteData it would have removed the data root outright, taking the
    # user's own authored and tuned styles with it.
    $consequence = if ($DeleteData) { "DELETES $dataDir entirely, including your own styles" }
                   else             { "removes install-managed files and the shell loader" }
    if ($vscodeTargets.Count -gt 0) { $consequence += ", and takes the saved style out of VS Code's settings.json" }
    if (-not (Confirm-Action -Question 'Continue? [y/N]' -Yes:$Yes -Consequence $consequence)) {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # 1. Remove the module / install-managed files
    #
    # What is left afterwards is read back, not assumed, and handed to the
    # sign-off: it closed on "TerminalStyles uninstalled." under either arm's
    # own failure line, because nothing here ever told it about one.
    $installLeft = @()
    $moduleRemoved = $false
    switch ($kind) {
        'PSResourceGet' {
            $remover = ($galleryRemove -split ' ')[0]
            $before  = @(Get-InstalledModuleCopy)
            $failure = $null
            try {
                if ($HasPSResourceGet) {
                    Uninstall-PSResource -Name TerminalStyles -ErrorAction Stop
                } else {
                    Uninstall-Module -Name TerminalStyles -AllVersions -ErrorAction Stop
                }
            } catch { $failure = $_ }
            $installLeft = @(Get-InstalledModuleCopy)
            # Each line for what happened, and none for what did not. The error
            # is shown whenever there was something to remove, even when the
            # listing afterwards finds nothing left: it was the remover's own
            # report. With nothing installed it is only the remover saying so.
            if ($failure -and $before.Count -gt 0) {
                Write-Host "  $remover reported an error: $failure" -ForegroundColor Red
            }
            $moduleRemoved = @($before | Where-Object { $installLeft -notcontains $_ }).Count -gt 0
            if ($moduleRemoved) {
                Write-Host "  Removed module via $remover" -ForegroundColor Green
            }
            if ($installLeft.Count -gt 0) {
                Write-Host "  ! TerminalStyles is still installed; the end of this output says where." -ForegroundColor Red
            } elseif ($before.Count -eq 0) {
                # A module imported from outside the module path, a checkout
                # say, is a Gallery kind too -- and "Removed module" would claim
                # a removal there was nothing to make.
                Write-Host "  No installed copy of the module was found, so there was none to remove." -ForegroundColor Gray
            }
        }
        'Bootstrap' {
            # terminals.ps1 and shell/ were missing: tstyles.ps1 dot-sources
            # terminals.ps1, and the staged shell runtime is what an orphaned rc
            # block loads. Leaving them behind kept a "removed" install working.
            $plan = Get-UninstallPlan -DataDir $dataDir
            foreach ($item in $plan.Items) {
                $path = Join-Path $dataDir $item
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            # styles/ is left in place when it still holds the user's own; drop
            # it only once it is empty, so an uninstall does not leave a bare
            # directory behind either.
            $stylesDir = Join-Path $dataDir 'styles'
            if ((Test-Path -LiteralPath $stylesDir) -and
                -not (Get-ChildItem -LiteralPath $stylesDir -Force)) {
                Remove-Item -LiteralPath $stylesDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            # Said only when it is so. The loop is silent on failure, so one
            # locked file cannot stop the rest -- and this line was printed
            # after it whatever it had managed.
            $installLeft = @(foreach ($item in $plan.Items) {
                $path = Join-Path $dataDir $item
                if (Test-Path -LiteralPath $path) { $path }
            })
            if ($installLeft.Count -eq 0) {
                Write-Host "  Removed install-managed files from $dataDir" -ForegroundColor Green
            } else {
                Write-Host "  ! could not remove every install-managed file; the end of this output names any still left." -ForegroundColor Red
            }
            if ($plan.Source -eq 'fallback') {
                Write-Host "  This install predates the file manifest, so the bundled styles were left" -ForegroundColor Gray
                Write-Host "  in $stylesDir rather than risk deleting your own alongside them." -ForegroundColor Gray
            }
        }
    }

    # 2. Strip the zsh/bash loader too, and clear what it reads.
    #
    # Uninstall used to remove only the PowerShell $PROFILE loader, so after it
    # every new zsh/bash tab still repainted the palette, set the window title,
    # printed the style's banner and took over the prompt -- the shell side was
    # untouched. Worse, the documented way back (`tstyles shell-remove`) was
    # already dead by then: step 1 deletes TerminalStyles.psd1, which is the
    # exact path baked into the generated tstyles-cli.ps1, so the shell's own
    # `tstyles` command could no longer load the module. That left hand-editing
    # ~/.zshrc as the only recovery.
    # The removal superset, not the registration list: shell-init can register
    # into ~/.profile, and sweeping the narrow list orphaned that block forever.
    #
    # Through the same helper `tstyles shell-remove` uses. This loop used to be
    # its own copy of the rule, comparing the four-state status against exactly
    # one value -- an explicit comparison, so the lint for "don't use the status
    # as a boolean" passed, while 'failed' and 'malformed' were thrown away in
    # silence. The consent screen above NAMES these files one per line, and two
    # of them could be left carrying the block with nothing said about it.
    $sweep = Remove-ShellLoaderBlock -Path @(Get-ShellRcRemovalCandidate @rcSplat |
                                             ForEach-Object { $_.Path })
    $shellRemoved  = $sweep.Removed
    $shellProblems = $sweep.Problems
    Clear-ShellStyleState

    # The generated WezTerm module. Removal is a single delete because nothing
    # of the user's was ever written into: their wezterm.lua carries only the
    # pcall-guarded require they added by hand, which degrades to a no-op the
    # moment this file stops existing. That is the property that made this
    # design preferable to a marker block in a Lua program -- see the header of
    # lib/wezterm.ps1.
    $wezPath = Get-WezTermModulePath @wezSplat
    $wezLeft = $null
    if (Test-Path -LiteralPath $wezPath) {
        try { Remove-Item -LiteralPath $wezPath -Force -ErrorAction Stop } catch { }
        # Read back, like every other removal here, and kept for the sign-off
        # as well -- which closed on the plain "TerminalStyles uninstalled." a
        # few lines under the warning.
        if (Test-Path -LiteralPath $wezPath) {
            $wezLeft = $wezPath
            Write-Host "  ! could not remove $wezPath" -ForegroundColor Red
            Write-Host "    Delete it by hand; until then WezTerm keeps applying the last style." -ForegroundColor Red
        } else {
            Write-Host "  Removed the WezTerm style module ($wezPath)" -ForegroundColor Green
        }
    }

    # The saved VS Code styles, from their records -- the same list the prompt
    # named. Each says what it did. One that could not be undone is collected
    # for the sign-off: its record survives only until -DeleteData, and once
    # the module is gone no `tstyles reset` can retry it.
    $vscodeUncleared = @()
    $vscodeProblems = @(foreach ($t in $vscodeTargets) {
        $vr = Reset-StyleVSCodeConfig -Variant $t.Variant
        # -DeleteData removes the data root, and this record with it, further
        # down: a warning that the record could not be cleared would be about
        # one that is gone. Held back rather than dropped, in case the wipe
        # fails too. On 'reset' a record left uncleared is all Detail says.
        if ($DeleteData -and $vr.Status -eq 'reset' -and $vr.Detail) {
            $vscodeUncleared += $vr.Variant
            $vr.Detail = $null
        }
        Show-VSCodeResetResult -Result $vr -Uninstalling
        if ($vr.Status -ne 'reset' -and $vr.Status -ne 'norecord') { $t.Path }
    })

    if ($shellRemoved) {
        Write-Host "  Open a new zsh/bash tab to get your original prompt back." -ForegroundColor Gray
    }

    # 3. Strip the loader from every PowerShell engine's $PROFILE.
    #
    # The same list the consent screen named, and its problems join the rc
    # half's: an unwritable or malformed $PROFILE was reported per file and then
    # dropped, so the sign-off below could not know about it.
    $profileSweep    = Remove-PowerShellProfileLoader -Target $profileTargets
    $profileProblems = @($profileSweep.Problems)

    # 4. Optionally remove user state
    $dataLeft = $false
    if ($DeleteData) {
        if (Test-Path -LiteralPath $dataDir) {
            # -ErrorAction Continue whatever the caller prefers. Under 'Stop'
            # the first file that would not go was an error out of this
            # command, before the line below or the sign-off could say what it
            # had left; its own errors still show.
            Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction Continue
            # Said only when it is so: a wipe that fails part-way leaves files
            # behind, and Remove-Item's own errors scroll past.
            if (Test-Path -LiteralPath $dataDir) {
                $dataLeft = $true
                Write-Host "  ! could not remove all of $dataDir -- delete what is left by hand." -ForegroundColor Red
            } else {
                Write-Host "  Removed $dataDir (full wipe via -DeleteData)" -ForegroundColor Green
            }
        }
        # A record held back above that outlived the wipe after all.
        if ($vscodeUncleared.Count -gt 0 -and [System.IO.File]::Exists((Get-VSCodeStatePath))) {
            $names = (@($vscodeUncleared) | ForEach-Object { "$_'s settings.json" }) -join ' and '
            Write-Host ("  The record of what was saved to {0} could not be cleared, and is still in" -f $names) -ForegroundColor Yellow
            Write-Host ("  {0}, so a reinstall's next apply or reset may wrongly call some of your settings hand edits." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "  User state preserved at $dataDir" -ForegroundColor Gray
        Write-Host "  Pass -DeleteData to remove that too." -ForegroundColor Gray
    }

    Write-Host ""
    # The last line the user reads, and it was printed unconditionally. A file
    # this command could not strip is one the user now has to find and edit by
    # hand: step 1 has removed the module, so `tstyles shell-remove` -- the
    # documented way out -- cannot run any more.
    #
    # Both halves, not just the rc one. The $PROFILE strip reported an unwritable
    # or malformed file and then returned a bare count, so its problems reached
    # nothing: the command closed on the plain "TerminalStyles uninstalled." with
    # the block still in a file it had just said it could not write.
    #
    # And every other leftover, not those two alone. Step 1 failing or quietly
    # leaving files behind, the WezTerm module refusing to go and a -DeleteData
    # wipe that stopped part-way each reached nothing past their own step, so
    # the command closed on the plain "TerminalStyles uninstalled." regardless.
    $allProblems = @($shellProblems + $profileProblems)
    # Read again here: under -DeleteData a bootstrap leftover is in the data
    # root, and step 4 may have taken it after all.
    $installLeft = @($installLeft | Where-Object { Test-Path -LiteralPath $_ })
    # Whether the module itself is still installed, which is not the same as
    # whether anything is left. A Gallery copy anywhere is the module. A
    # bootstrap install is the module while its manifest is there -- the
    # $PROFILE loader and the rc shim both import it by path -- and once that
    # has gone, a leftover docs/ is a file, not an install.
    $moduleLeft = if ($kind -eq 'Bootstrap') { Test-Path -LiteralPath (Join-Path $dataDir 'TerminalStyles.psd1') }
                  else                       { $installLeft.Count -gt 0 }
    # What three pieces of advice below rest on: step 1 removed the module those
    # loaders import, and none of it is left. Not the same as nothing left
    # either -- a checkout had no installed copy to remove, and the loaders
    # still import it.
    $moduleGone = if ($kind -eq 'Bootstrap') { -not $moduleLeft }
                  else                       { $moduleRemoved -and -not $moduleLeft }
    $lead = @{ Opened = $false }

    if ($installLeft.Count -gt 0) {
        $one = $installLeft.Count -eq 1
        if ($moduleLeft) {
            Write-UninstallLeftoverLead -State $lead -Opening 'TerminalStyles is NOT fully uninstalled.' -What 'Still in place:'
        } else {
            Write-UninstallLeftoverLead -State $lead -What $(if ($one) { 'this file it installed:' } else { 'these files it installed:' })
        }
        foreach ($p in $installLeft) { Write-Host ("  {0}" -f $p) -ForegroundColor Yellow }
        if ($kind -eq 'Bootstrap') {
            Write-Host $(if ($one) { 'Delete it by hand.' } else { 'Delete them by hand.' }) -ForegroundColor Yellow
        } else {
            # The remover first, because a copy installed for all users needs an
            # elevated shell to delete, and "by hand" said nothing of it. A copy
            # in the other engine's folder is out of this one's reach, so that
            # engine's own remover is named for it.
            $other  = Get-OtherEngineModuleRoot
            $theirs = @(if ($other) {
                $installLeft | Where-Object { $_.StartsWith($other.Path, [System.StringComparison]::OrdinalIgnoreCase) }
            })
            $ours   = @($installLeft | Where-Object { $theirs -notcontains $_ })
            if ($ours.Count -gt 0) {
                Write-Host ("To finish, run {0} -- from an elevated shell for a copy" -f $galleryRemove) -ForegroundColor Yellow
                Write-Host ("installed for all users -- or delete the {0} by hand." -f $(if ($ours.Count -eq 1) { 'folder' } else { 'folders' })) -ForegroundColor Yellow
            }
            if ($theirs.Count -gt 0) {
                Write-Host ("{0}'s own copy is out of this engine's reach: run {1} there." -f $other.Engine, $other.Remover) -ForegroundColor Yellow
            }
        }
    }
    if ($allProblems.Count -gt 0) {
        Write-UninstallLeftoverLead -State $lead -What 'the loader block in:'
        foreach ($p in $allProblems) {
            Write-Host ("  {0}" -f $p) -ForegroundColor Yellow
        }
        if ($moduleGone) {
            # Single-quoted: a backtick opens an escape in a double-quoted
            # string, and `t is a tab.
            Write-Host 'Delete those blocks by hand -- the module is gone, so `tstyles shell-remove`' -ForegroundColor Yellow
            Write-Host "cannot do it for you now." -ForegroundColor Yellow
        } else {
            Write-Host "Delete those blocks by hand." -ForegroundColor Yellow
        }
        # What is safe to promise about the leftovers, and no more: the staged
        # style state has just been cleared, so whatever the block still finds
        # to source has nothing left to paint. Whether the runtime file itself
        # survives depends on the install kind, and this is not the line to
        # explain that in.
        if ($shellProblems.Count -gt 0) {
            Write-Host "Until you do, the rc files above paint nothing: the staged style state is gone," -ForegroundColor Gray
            Write-Host "so there is nothing left for them to apply." -ForegroundColor Gray
        }
        # A leftover $PROFILE block is not inert in that way, and saying so is
        # the difference between "untidy" and "every new tab opens broken": the
        # block is an Import-Module of the module step 1 has just removed. Not
        # said when step 1 left it installed -- the import then still works.
        if ($profileProblems.Count -gt 0 -and $moduleGone) {
            Write-Host "A PowerShell profile is not inert like that: the block there imports a module" -ForegroundColor Gray
            Write-Host "step 1 has just removed, so every new tab opens on a red error until you delete it." -ForegroundColor Gray
        }
    }
    if ($wezLeft) {
        Write-UninstallLeftoverLead -State $lead -What 'the WezTerm style module:'
        Write-Host ("  {0}" -f $wezLeft) -ForegroundColor Yellow
        Write-Host "Delete it by hand; until then WezTerm keeps applying the last style." -ForegroundColor Yellow
    }
    # A VS Code style that could not be taken out. Its record is the only thing
    # that names those keys, and with the module gone no reset can use it -- so
    # the user is told where they are, rather than "uninstalled".
    if ($vscodeProblems.Count -gt 0) {
        Write-UninstallLeftoverLead -State $lead -What 'the style saved in:'
        foreach ($p in $vscodeProblems) { Write-Host ("  {0}" -f $p) -ForegroundColor Yellow }
        Write-Host "Take its keys out of those files by hand: the terminal colors in" -ForegroundColor Yellow
        Write-Host "workbench.colorCustomizations, and terminal.integrated.fontFamily, fontSize," -ForegroundColor Yellow
        Write-Host "fontWeight and cursorStyle. Or restore a settings.json.bak-* copy beside one," -ForegroundColor Yellow
        if ($moduleGone) {
            Write-Host "if there is one -- restoring it also undoes your edits since. The module is" -ForegroundColor Yellow
            Write-Host "gone, so tstyles cannot." -ForegroundColor Yellow
        } else {
            Write-Host "if there is one -- restoring it also undoes your edits since." -ForegroundColor Yellow
        }
    }
    # The record of what was saved could not be read, so no editor's
    # settings.json was touched and nothing here can say which of them holds a
    # style. Said again at the end: the consent screen has scrolled away.
    if (-not $vscodeState.Ok) {
        Write-UninstallLeftoverLead -State $lead -What 'any style saved to a VS Code-family settings.json:'
        Write-Host ("{0} could not be read, so none was taken out. Check those files by hand." -f $vscodeState.Path) -ForegroundColor Yellow
    }
    if ($dataLeft) {
        Write-UninstallLeftoverLead -State $lead -What 'part of the data folder:'
        Write-Host ("  {0}" -f $dataDir) -ForegroundColor Yellow
        Write-Host "-DeleteData could not remove all of it. Delete what is left by hand." -ForegroundColor Yellow
    }
    if (-not $lead.Opened) {
        Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    }
    # Only when the $PROFILE side really did come out clean. This was printed
    # unconditionally, directly under a warning that the loader is still in a
    # profile file -- the same sentence, about the same file, in both directions.
    if ($profileProblems.Count -eq 0) {
        Write-Host "Open a new pwsh tab to confirm the loader is gone." -ForegroundColor Gray
    }
    Write-Host "Windows Terminal's settings.json was NOT modified. If you want its default look" -ForegroundColor Gray
    Write-Host "back, restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
    Write-Host ""
}
