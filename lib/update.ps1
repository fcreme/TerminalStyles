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
    # delegate to the right mechanism, and by Test-UpdateAvailable to skip the
    # SHA-based check entirely for PSResourceGet installs.
    #
    # Note: $script:TStylesModuleRoot is set during module load. For installs
    # made before the dual-root refactor (sub-project C), the variable still
    # has the right value because the init block sets it from $PSScriptRoot.
    $bootstrapDir = Get-TStylesDataRoot
    if ($script:TStylesModuleRoot -eq $bootstrapDir) { return 'Bootstrap' }
    return 'PSResourceGet'
}

function Test-UpdateAvailable {
    # Returns a pscustomobject with short SHAs if a newer commit is available
    # on origin/main, or $null if local already matches / no .installed-sha /
    # we're inside the 24h throttle window / the API call fails.
    #
    # Throttled to <= 1 HTTP request per 24 hours per machine via
    # .last-update-check. The timestamp is rewritten on every attempt
    # (success or failure), so an offline machine doesn't retry the
    # 2s timeout on every single tstyles invocation.
    # PSResourceGet installs update via Update-PSResource, not git. Skip
    # the SHA-based check entirely; the user runs `tstyles update` whenever.
    if ((Get-TerminalStylesInstallKind) -eq 'PSResourceGet') { return $null }

    $shaFile   = Join-Path $script:TStylesDataRoot '.installed-sha'
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

    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        $resp = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
            -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
            -TimeoutSec 2 -ErrorAction Stop
        $remote = $resp.sha
    } catch { }

    # --- Throttle write ---
    # Always write the timestamp, even on API failure. Without this, an
    # offline machine would retry the 2s timeout on every invocation.
    try {
        $now = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $now, [System.Text.UTF8Encoding]::new($false))
    } catch { }

    if ($remote -and $remote -ne $installed) {
        return [pscustomobject]@{
            Installed = $installed.Substring(0, [Math]::Min(7, $installed.Length))
            Remote    = $remote.Substring(0, [Math]::Min(7, $remote.Length))
        }
    }
    return $null
}

function Show-UpdateNoticeIfAvailable {
    # Prints the one-line yellow update notice if there's a newer commit
    # on origin/main. Called from every non-updating tstyles invocation
    # (picker, direct apply, list, current, random), but Test-UpdateAvailable
    # short-circuits inside the 24h throttle window, so the notice displays
    # at most once per day while an update is pending.
    $pending = Test-UpdateAvailable
    if ($pending) {
        Write-Host ("Update available ({0} -> {1}). Run: tstyles update" -f $pending.Installed, $pending.Remote) -ForegroundColor Yellow
        Write-Host ""
    }
}

function Invoke-TerminalStylesUpdate {
    [CmdletBinding()]
    param([switch]$Force)

    Write-Host ""
    Write-Host "Updating TerminalStyles..." -ForegroundColor Cyan

    switch (Get-TerminalStylesInstallKind) {
        'PSResourceGet' {
            try {
                Update-PSResource -Name TerminalStyles -TrustRepository -ErrorAction Stop
                Write-Host ""
                Write-Host "Update complete. To use the new version in THIS session," -ForegroundColor Yellow
                Write-Host "open a new tab, or run:" -ForegroundColor Yellow
                Write-Host "  Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Cyan
            } catch {
                Write-Host "Update failed: $_" -ForegroundColor Red
                Write-Host "You can retry manually:" -ForegroundColor Yellow
                Write-Host "  Update-PSResource -Name TerminalStyles -TrustRepository" -ForegroundColor Cyan
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

    if (-not $Targets) {
        # Discover both engines, get $PROFILE per engine
        $shells = @(Get-PowerShellEngineCandidate)
        $targets = @()
        foreach ($s in $shells) {
            $cmd = Get-Command -Name $s.Exe -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
            if (-not $profilePath) { continue }
            $profilePath = "$profilePath".Trim()
            if (-not $profilePath) { continue }
            $targets += [pscustomobject]@{
                Label       = $s.Label
                ProfilePath = $profilePath
                Exists      = Test-Path -LiteralPath $profilePath
                HasLoader   = $false
            }
        }
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
        if ($t.Exists) {
            $content = [System.IO.File]::ReadAllText($t.ProfilePath, (Get-RcFileEncoding))
            $t.HasLoader = ($content -match $blockPattern)
        }
    }

    # Decide what to do per target
    $toWrite = @()
    foreach ($t in $targets) {
        if ($t.HasLoader -and -not $Force) {
            Write-Host "  Already registered in $($t.ProfilePath) (use -Force to replace)" -ForegroundColor Gray
            continue
        }
        $toWrite += $t
    }

    if (-not $toWrite) {
        Write-Host ""
        Write-Host "Nothing to do." -ForegroundColor Yellow
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
    Write-Host "  Import-Module TerminalStyles -DisableNameChecking" -ForegroundColor Cyan
    Write-Host ""
    # `$ans -match '^(?i)n'` was falsy at EOF -- AutomationNull compares as an
    # empty collection -- so `tstyles register < /dev/null` wrote the loader
    # into BOTH engines' $PROFILE files with nobody having answered.
    if (-not (Confirm-Action -Question 'Continue? [y/N]' -Yes:$Yes `
                -Consequence "writes the loader block into $($toWrite.Count) PowerShell profile file(s)")) {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # Write the block per target (strip first for -Force path)
    foreach ($t in $toWrite) {
        $profileDir = Split-Path -Parent $t.ProfilePath
        if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        $existing = if ($t.Exists) {
            [System.IO.File]::ReadAllText($t.ProfilePath, (Get-RcFileEncoding))
        } else { '' }

        if ($existing -match $blockPattern) {
            $existing = [regex]::Replace($existing, $blockPattern, '')
        }

        $final = ($existing.TrimEnd() + "`r`n`r`n" + $loaderBody + "`r`n").TrimStart()
        # Same first-touch rule the bootstrap installer has always applied to
        # $PROFILE. The module half never did, so `tstyles register` rewrote a
        # hand-maintained profile with no copy kept.
        $bak = Save-FirstTouchBackup -Path $t.ProfilePath -Content $existing -BlockPattern ([regex]::Escape($loaderBegin))
        if ($bak) { Write-Host "  Backed up your existing $($t.Label) profile to: $bak" -ForegroundColor Gray }
        [System.IO.File]::WriteAllText($t.ProfilePath, $final, (Get-RcFileEncoding))

        Write-Host "  Registered in $($t.ProfilePath)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "TerminalStyles will auto-load on every new shell tab." -ForegroundColor Cyan
    Write-Host "To verify in this session: Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Gray
    Write-Host ""
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
            # A style the install shipped, that the user has since tuned in
            # place, is no longer only the install's to remove. Saving a tune
            # with "[1] Overwrite" writes it under a BUNDLED name -- which is
            # the option's purpose -- and that name is exactly what the manifest
            # always contains, so uninstall deleted the tuned style one line
            # after printing "PRESERVE user state ... pass -DeleteData to wipe".
            # A Save-As tune under a fresh name survived, which made the loss
            # silent and inconsistent. tune.json marks it as the user's.
            $items = @($items | Where-Object {
                if ($_ -notmatch '^styles[\\/][^\\/]+[\\/]?$') { return $true }
                -not (Test-Path -LiteralPath (Join-Path (Join-Path $DataDir $_) 'tune.json'))
            })
            if ($items.Count -gt 0) {
                return @{ Items = @($items + $script:TStylesStagedRuntimeFiles + '.installed-files')
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

function Get-PowerShellProfileTarget {
    <#
    .SYNOPSIS
    The $PROFILE files of the PowerShell engines present on this machine.

    .DESCRIPTION
    Pulled out of Invoke-TerminalStylesUninstall so the strip below can be run
    against a sandbox. It could not be before: the paths come from RUNNING each
    engine, so the only $PROFILE any test could reach was the one belonging to
    the operator, and step 3 was therefore never exercised by anything. That is
    the same reason the rc half's omission went four releases unnoticed, and the
    same seam Invoke-TerminalStylesRegister already carries as -Targets.

    Only files that exist: a $PROFILE that was never created has no block in it.

    Distinct by path. Two engines can share one $PROFILE -- on this machine
    `pwsh` and `pwsh-preview` both report
    ~/.config/powershell/Microsoft.PowerShell_profile.ps1 -- and processing it
    twice would print the malformed and unwritable warnings twice for one file.
    Windows' two engines keep separate directories, so nothing merges there.
    #>
    [CmdletBinding()]
    param()

    $seen = @{}
    @(foreach ($e in (Get-PowerShellEngineCandidate)) {
        $cmd = Get-Command -Name $e.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $profilePath = $profilePath.Trim()
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }
        if ($seen.ContainsKey($profilePath)) { continue }
        $seen[$profilePath] = $true
        [pscustomobject]@{ ProfilePath = $profilePath; Label = $e.Label }
    })
}

function Remove-PowerShellProfileLoader {
    <#
    .SYNOPSIS
    Strip the loader block from each engine's $PROFILE. Returns how many went.

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
    #>
    [CmdletBinding()]
    param([object[]]$Target)

    if (-not $PSBoundParameters.ContainsKey('Target')) {
        $Target = @(Get-PowerShellProfileTarget)
    }

    $removed = 0
    foreach ($t in $Target) {
        switch (Unregister-ShellLoader -Path $t.ProfilePath) {
            'removed' {
                Write-Host "  Removed loader from $($t.ProfilePath)" -ForegroundColor Green
                $removed++
            }
            'malformed' {
                Write-Host ("  ! {0} has a TerminalStyles BEGIN marker with no matching END." -f $t.ProfilePath) -ForegroundColor Red
                Write-Host "    Nothing was removed. Delete the block by hand -- it still loads on every tab." -ForegroundColor Red
            }
            'failed' {
                Write-Host ("  ! could not write {0}" -f $t.ProfilePath) -ForegroundColor Red
                Write-Host "    The loader is still there. Check the file's permissions (a read-only" -ForegroundColor Red
                Write-Host "    profile, or one managed by nix or chezmoi) and remove the block by hand." -ForegroundColor Red
            }
            # 'none' is the ordinary case for an engine that was never
            # registered, and says nothing on purpose.
        }
    }
    return $removed
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
        [object[]]$ProfileTarget
    )

    $rcSplat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $rcSplat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('ZDotDir')) { $rcSplat.ZDotDir = $ZDotDir }

    $profileSplat = @{}
    if ($PSBoundParameters.ContainsKey('ProfileTarget')) { $profileSplat.Target = $ProfileTarget }

    $dataDir = Get-TStylesDataRoot
    $kind = Get-TerminalStylesInstallKind

    Write-Host ""
    Write-Host "This will uninstall TerminalStyles (detected: $kind):" -ForegroundColor Yellow
    switch ($kind) {
        'PSResourceGet' {
            Write-Host "  - Uninstall-PSResource -Name TerminalStyles" -ForegroundColor Yellow
        }
        'Bootstrap' {
            Write-Host "  - Remove install-managed files from $dataDir" -ForegroundColor Yellow
        }
    }
    Write-Host "  - Strip the loader block from pwsh 7 and Windows PowerShell 5.1 `$PROFILE files" -ForegroundColor Yellow
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
    if ($DeleteData) {
        Write-Host "  - DELETE the entire $dataDir (user state: active style, cached GIFs, throttle stamp)" -ForegroundColor Red
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
    if (-not (Confirm-Action -Question 'Continue? [y/N]' -Yes:$Yes -Consequence $consequence)) {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # 1. Remove the module / install-managed files
    switch ($kind) {
        'PSResourceGet' {
            try {
                Uninstall-PSResource -Name TerminalStyles -ErrorAction Stop
                Write-Host "  Removed module via Uninstall-PSResource" -ForegroundColor Green
            } catch {
                Write-Host "  Uninstall-PSResource failed: $_" -ForegroundColor Red
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
            Write-Host "  Removed install-managed files from $dataDir" -ForegroundColor Green
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
    $shellRemoved = 0
    # The removal superset, not the registration list: shell-init can register
    # into ~/.profile, and sweeping the narrow list orphaned that block forever.
    foreach ($c in (Get-ShellRcRemovalCandidate @rcSplat)) {
        # Explicit comparison: Unregister-ShellLoader returns a STATUS now, and
        # every status -- including 'none' -- is a truthy string.
        if ((Unregister-ShellLoader -Path $c.Path) -eq 'removed') {
            Write-Host "  Removed shell loader from $($c.Path)" -ForegroundColor Green
            $shellRemoved++
        }
    }
    Clear-ShellStyleState

    # The generated WezTerm module. Removal is a single delete because nothing
    # of the user's was ever written into: their wezterm.lua carries only the
    # pcall-guarded require they added by hand, which degrades to a no-op the
    # moment this file stops existing. That is the property that made this
    # design preferable to a marker block in a Lua program -- see the header of
    # lib/wezterm.ps1.
    $wezPath = Get-WezTermModulePath @wezSplat
    if (Test-Path -LiteralPath $wezPath) {
        try {
            Remove-Item -LiteralPath $wezPath -Force -ErrorAction Stop
            Write-Host "  Removed the WezTerm style module ($wezPath)" -ForegroundColor Green
        } catch {
            Write-Host "  ! could not remove $wezPath" -ForegroundColor Red
            Write-Host "    Delete it by hand; until then WezTerm keeps applying the last style." -ForegroundColor Red
        }
    }

    if ($shellRemoved) {
        Write-Host "  Open a new zsh/bash tab to get your original prompt back." -ForegroundColor Gray
    }

    # 3. Strip the loader from both PowerShell engines' $PROFILE
    Remove-PowerShellProfileLoader @profileSplat | Out-Null

    # 4. Optionally remove user state
    if ($DeleteData) {
        if (Test-Path -LiteralPath $dataDir) {
            Remove-Item -LiteralPath $dataDir -Recurse -Force
            Write-Host "  Removed $dataDir (full wipe via -DeleteData)" -ForegroundColor Green
        }
    } else {
        Write-Host ""
        Write-Host "  User state preserved at $dataDir" -ForegroundColor Gray
        Write-Host "  Pass -DeleteData to remove that too." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    Write-Host "Open a new pwsh tab to confirm the loader is gone." -ForegroundColor Gray
    Write-Host "Your settings.json was NOT modified. If you want a default look back," -ForegroundColor Gray
    Write-Host "restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
    Write-Host ""
}
