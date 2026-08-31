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

    # Detect existing loader block per target
    $blockPattern = "(?ms)$([regex]::Escape($loaderBegin)).*?$([regex]::Escape($loaderEnd))\r?\n?"
    foreach ($t in $targets) {
        if ($t.Exists) {
            $content = [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
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
            [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
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
        [System.IO.File]::WriteAllText($t.ProfilePath, $final, [System.Text.UTF8Encoding]::new($false))

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

function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData,   # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
        # Pre-granted consent. Required for a non-interactive uninstall, which
        # used to happen by accident whenever stdin was at EOF.
        [switch]$Yes
    )

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
    foreach ($c in (Get-ShellRcCandidate)) {
        # Explicit comparison: Unregister-ShellLoader returns a STATUS now, and
        # every status -- including 'none' -- is a truthy string.
        if ((Unregister-ShellLoader -Path $c.Path) -eq 'removed') {
            Write-Host "  Removed shell loader from $($c.Path)" -ForegroundColor Green
            $shellRemoved++
        }
    }
    Clear-ShellStyleState
    if ($shellRemoved) {
        Write-Host "  Open a new zsh/bash tab to get your original prompt back." -ForegroundColor Gray
    }

    # 3. Strip the loader from both PowerShell engines' $PROFILE
    foreach ($exe in (Get-PowerShellEngineCandidate).Exe) {
        $cmd = Get-Command -Name $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $profilePath = $profilePath.Trim()
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }

        $content = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
        $newContent = [regex]::Replace($content, '(?ms)# ===== TerminalStyles BEGIN =====.*?# ===== TerminalStyles END =====\r?\n?', '')
        if ($newContent -ne $content) {
            [System.IO.File]::WriteAllText($profilePath, $newContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Removed loader from $profilePath" -ForegroundColor Green
        }
    }

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
