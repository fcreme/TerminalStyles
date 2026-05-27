# tstyles.ps1 -- TerminalStyles loader + interactive picker.
#
# Dot-sourced from $PROFILE by install.ps1. Provides:
#   * `tstyles` (alias of Invoke-TerminalStyle) -- arrow-key live-preview picker.
#   * Auto-loads the currently selected style's profile.ps1 on shell startup.
#
# All write operations restore on Escape; the original settings.json bytes are
# snapshotted on entry so a cancel is byte-exact.

#Requires -Version 5.1

$script:TStylesModuleRoot = $PSScriptRoot
if (-not $script:TStylesModuleRoot) {
    $script:TStylesModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# Stable per-user data dir. Survives module version upgrades (PSResourceGet
# installs a new version to a sibling dir; state stays here). For bootstrap-
# installed users, this happens to equal $script:TStylesModuleRoot --
# backward-compatible by design.
$script:TStylesDataRoot = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
}
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

# === Internals ===

function Find-WTSettingsPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-CurrentWTProfileName {
    param($Settings)
    if (-not $env:WT_PROFILE_ID) { return $null }
    $entry = $Settings.profiles.list | Where-Object { $_.guid -eq $env:WT_PROFILE_ID } | Select-Object -First 1
    if ($entry) { return $entry.name }
    return $null
}

function Get-StyleBundledBackground {
    # Three-tier resolution:
    #   1. Bundled file under $StyleDir (module root, read-only-ish on PSGallery)
    #   2. Cached file under $DataRoot\cache\<name>\ (writable, persistent)
    #   3. Lazy-fetch from gifs branch -> write to $DataRoot\cache\<name>\
    #
    # The negative-cache marker (.no-background) lives in the cache dir, never
    # in the bundled dir, so we can write it on PSGallery installs.
    param([Parameter(Mandatory)][string]$StyleDir)

    # 1. Bundled (under module root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $bundled = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }

    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir  = Join-Path $script:TStylesDataRoot "cache\$styleName"

    # 2. Cached (under data root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $cached = Join-Path $cacheDir "background.$ext"
        if (Test-Path -LiteralPath $cached) { return $cached }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch into cache
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $cacheDir "background.$ext"
            try {
                Invoke-WebRequest -Uri $url -OutFile $local -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                    return $local
                } else {
                    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # All extensions failed -- write negative-cache marker in CACHE dir
    try {
        New-Item -ItemType File -Path (Join-Path $cacheDir '.no-background') -Force | Out-Null
    } catch { }
    return $null
}

function Invoke-TerminalStylesStateMigration {
    # Migrates pre-0.2.0 data layout to 0.2.0:
    #   - Cached background.<ext> files move from $ModuleRoot\styles\<name>\
    #     to $DataRoot\cache\<name>\.
    #   - .no-background negative-cache markers move similarly.
    # Idempotent. Skips work if the marker file exists.
    $marker = Join-Path $script:TStylesDataRoot '.migrated-0.2.0'
    if (Test-Path -LiteralPath $marker) { return }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) {
        # No styles dir to migrate from. Mark done so we don't re-check.
        try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }
        return
    }

    foreach ($styleDir in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        $styleName = $styleDir.Name
        $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"

        # Move cached background files
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $src = Join-Path $styleDir.FullName "background.$ext"
            if (Test-Path -LiteralPath $src) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
                }
                $dest = Join-Path $cacheDir "background.$ext"
                try {
                    Move-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                } catch {
                    # Source might be read-only (PSGallery install with stale
                    # bundled file from manual user copy). Acceptable -- the
                    # bundled file stays readable in place.
                }
            }
        }

        # Move negative-cache marker
        $srcMarker = Join-Path $styleDir.FullName '.no-background'
        if (Test-Path -LiteralPath $srcMarker) {
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
            }
            try {
                Move-Item -LiteralPath $srcMarker -Destination (Join-Path $cacheDir '.no-background') -Force -ErrorAction Stop
            } catch { }
        }
    }

    try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }
}

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
    $bootstrapDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
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

function Merge-StyleIntoSettings {
    param(
        $Settings,
        [string]$StyleDir,
        [string]$TargetName,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided
    )

    $scheme = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    if (-not $Settings.PSObject.Properties.Match('schemes').Count) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
    }
    $Settings.schemes = @($Settings.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme

    $themePath = Join-Path $StyleDir 'theme.json'
    if (-not (Test-Path -LiteralPath $themePath)) { return $Settings }
    $theme = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $entry = if ($TargetName -eq 'defaults') {
        if (-not $Settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $Settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $Settings.profiles.defaults
    } else {
        $Settings.profiles.list | Where-Object name -eq $TargetName | Select-Object -First 1
    }
    if (-not $entry) { return $Settings }

    # Resolve effective background:
    #   1. User passed -BackgroundImage <path>  -> use that
    #   2. User passed -BackgroundImage ""      -> strip (remove fields entirely)
    #   3. Style ships a bundled background.*   -> use that
    #   4. Otherwise                            -> leave user's existing bg alone
    $effectiveBg = $BackgroundImage
    $applyBg = $BackgroundImageProvided
    if (-not $applyBg) {
        $bundled = Get-StyleBundledBackground -StyleDir $StyleDir
        if ($bundled) {
            $effectiveBg = $bundled
            $applyBg = $true
        }
    }

    # Three actions for bg fields:
    #   skip   : don't touch them
    #   remove : strip them from the profile (explicit empty path => disable)
    #   apply  : substitute the placeholder and write all bg fields
    $bgAction = if (-not $applyBg) { 'skip' }
                elseif ([string]::IsNullOrEmpty($effectiveBg)) { 'remove' }
                else { 'apply' }

    $bgFields = @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode', 'backgroundImageAlignment')
    foreach ($prop in $theme.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($name -in $bgFields) {
            if ($bgAction -eq 'skip') { continue }
            if ($bgAction -eq 'remove') {
                if ($entry.PSObject.Properties.Match($name).Count -gt 0) {
                    $entry.PSObject.Properties.Remove($name)
                }
                continue
            }
            # bgAction = 'apply'
            if ($name -eq 'backgroundImage' -and $value -eq '{{BACKGROUND_IMAGE}}') {
                $value = $effectiveBg
            }
        }

        if ($entry.PSObject.Properties.Match($name).Count -gt 0) {
            $entry.$name = $value
        } else {
            $entry | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }

    return $Settings
}

function Write-SettingsFile {
    param([string]$Path, $Settings)
    $json = $Settings | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-StyleDir {
    # Resolves a style name to its on-disk directory, checking the user
    # dir first ($DataRoot\styles\<name>\) then the bundled dir
    # ($ModuleRoot\styles\<name>\). Returns $null if neither has a
    # scheme.json for that name. User-wins matches Get-AvailableStyles'
    # union-and-dedup precedence.
    param([Parameter(Mandatory)][string]$StyleName)

    $userDir = Join-Path $script:TStylesDataRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) { return $userDir }

    $bundledDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"
    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) { return $bundledDir }

    return $null
}

function Get-AvailableStyles {
    # Returns DirectoryInfo for every styles/<name>/ that has a scheme.json,
    # merged from two locations:
    #   1. $DataRoot\styles\<name>\ -- user dir, persistent across updates
    #   2. $ModuleRoot\styles\<name>\ -- bundled, install-managed
    # User-wins on name collision (matches Get-StyleDir's precedence).
    # Sorted alphabetically by name.
    $userStylesDir    = Join-Path $script:TStylesDataRoot   'styles'
    $bundledStylesDir = Join-Path $script:TStylesModuleRoot 'styles'

    $user = if (Test-Path -LiteralPath $userStylesDir) {
        @(Get-ChildItem -LiteralPath $userStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $bundled = if (Test-Path -LiteralPath $bundledStylesDir) {
        @(Get-ChildItem -LiteralPath $bundledStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $userNames = @($user | ForEach-Object Name)
    @(@($user) + @($bundled | Where-Object { $_.Name -notin $userNames })) | Sort-Object Name
}

function Get-CurrentStyleName {
    # Detects which bundled style is currently active by byte-comparing
    # current-style.ps1 against each style's profile.ps1. Returns $null
    # if nothing matches (custom profile, no current style, etc).
    if (-not (Test-Path -LiteralPath $script:TStylesCurrent)) { return $null }
    $current = [System.IO.File]::ReadAllText($script:TStylesCurrent, [System.Text.UTF8Encoding]::new($false))
    foreach ($style in (Get-AvailableStyles)) {
        $sp = Join-Path $style.FullName 'profile.ps1'
        if (-not (Test-Path -LiteralPath $sp)) { continue }
        $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
        if ($current -eq $styleContent) { return $style.Name }
    }
    return $null
}

function Test-StyleResolved {
    # A style is "resolved" if we know its background state -- either a
    # bundled background.<ext> exists under $StyleDir (module root), or a
    # cached background.<ext>/.no-background exists under $DataRoot\cache\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $cacheDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }
    return $false
}

function Get-SchemeSwatch {
    # Returns a one-line ANSI swatch (up to 5 colored blocks) summarising a
    # theme. Picks slots that actually distinguish themes from each other --
    # background, foreground, cursor accent, and two anchor ANSI hues -- and
    # falls back to other ANSI slots when those duplicate (e.g. sober has
    # cursorColor == foreground, eva has cursorColor == brightRed, which
    # would otherwise show the same color twice). Renders each slot as a
    # background-colored cell so even near-black colors stay visible against
    # the terminal background. Trailing reset.
    param([Parameter(Mandatory)]$Scheme)
    # Primary picks first, then fallbacks in order of theme-distinguishing
    # power. The first 5 unique hex values from this list are rendered.
    $candidates = @(
        $Scheme.background,
        $Scheme.foreground,
        $Scheme.cursorColor,
        $Scheme.brightRed,
        $Scheme.brightCyan,
        $Scheme.selectionBackground,
        $Scheme.brightPurple,
        $Scheme.brightYellow,
        $Scheme.brightGreen,
        $Scheme.brightBlue
    )
    $seen = @{}
    $picks = @()
    foreach ($hex in $candidates) {
        if ($picks.Count -ge 5) { break }
        if (-not $hex) { continue }
        $key = ([string]$hex).TrimStart('#').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $picks += $hex
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($hex in $picks) {
        $h = ([string]$hex).TrimStart('#')
        if ($h.Length -lt 6) { continue }
        $r = [Convert]::ToInt32($h.Substring(0,2), 16)
        $g = [Convert]::ToInt32($h.Substring(2,2), 16)
        $b = [Convert]::ToInt32($h.Substring(4,2), 16)
        [void]$sb.Append([char]27).Append("[48;2;${r};${g};${b}m    ").Append([char]27).Append('[49m ')
    }
    [void]$sb.Append([char]27).Append('[0m')
    return $sb.ToString()
}

function Show-StyleList {
    # `tstyles list` -- print available styles, marking the active one.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $styles = Get-AvailableStyles
    Write-Host ""
    Write-Host "Available styles:" -ForegroundColor Cyan
    foreach ($s in $styles) {
        $marker = if ($s.Name -eq $current) { '*' } else { ' ' }
        $schemePath = Join-Path $s.FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatch = Get-SchemeSwatch -Scheme $scheme
        Write-Host ("  {0} {1,-16}  {2}" -f $marker, $s.Name, $swatch)
    }
    Write-Host ""
    if ($current) {
        Write-Host "$([char]27)[38;2;160;160;160m  (* = currently active)$([char]27)[0m"
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m  (no bundled style currently active)$([char]27)[0m"
    }
    Write-Host ""
}

function Show-CurrentStyle {
    # `tstyles current` -- print the active style name. Interactive callers
    # see name + swatch (visual self-check); piped/redirected callers get
    # just the name on stdout, preserving scriptability for `tstyles current
    # | grep ...` etc.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    if ($current) {
        if ([Console]::IsOutputRedirected) {
            Write-Output $current
        } else {
            $styleDir = Get-StyleDir -StyleName $current
            $schemePath = if ($styleDir) { Join-Path $styleDir 'scheme.json' } else { $null }
            if ($schemePath -and (Test-Path -LiteralPath $schemePath)) {
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                Write-Host ("{0,-16}  {1}" -f $current, (Get-SchemeSwatch -Scheme $scheme))
            } else {
                Write-Host $current
            }
        }
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m(no bundled style currently active)$([char]27)[0m"
    }
}

function Invoke-RandomStyle {
    # `tstyles random` -- pick a random bundled style and apply it.
    # Excludes the currently active one so it actually changes.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $candidates = @(Get-AvailableStyles | Where-Object { $_.Name -ne $current })
    if (-not $candidates) {
        Write-Host "No other styles to switch to." -ForegroundColor Yellow
        return
    }
    $pick = $candidates | Get-Random
    Write-Host ""
    Write-Host "Rolling the dice... -> " -NoNewline
    Write-Host $pick.Name -ForegroundColor Cyan
    Apply-StyleDirect -StyleName $pick.Name
}

function Apply-StyleDirect {
    # Apply a style directly (no picker UI). Used by `tstyles <name>` and
    # `tstyles random`. Mirrors the picker's confirm path -- merge into
    # settings.json, copy profile.ps1 to current-style.ps1, dot-source for
    # live reload.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided = $false
    )

    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    Show-UpdateNoticeIfAvailable

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = $originalJson | ConvertFrom-Json

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile. Pass -Target <name>."
        return
    }

    # Rolling backup: copy the on-disk settings.json to settings.json.bak
    # before any mutation. Single file, overwritten on each direct apply --
    # gives the user a one-line undo without filling LocalState with timestamped
    # backups over time. The picker doesn't need this (Esc reverts in-memory);
    # apply.ps1 keeps its own timestamped audit trail. -ErrorAction Stop so
    # non-terminating errors (permission denied, etc.) enter the catch block
    # rather than silently logging via $Error.
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
        -TargetName $Target -BackgroundImage $BackgroundImage `
        -BackgroundImageProvided $BackgroundImageProvided
    Write-SettingsFile -Path $settingsPath -Settings $settings

    # Detect pwsh target for profile.ps1 install + live reload
    $isPwshTarget = $false
    if ($Target -eq 'defaults') {
        $isPwshTarget = $true
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
        $cmd = "$($entry.commandline)"
        $src = "$($entry.source)"
        if ($src -eq 'Windows.Terminal.PowershellCore' -or
            $cmd -match '(?i)\bpwsh\.exe\b' -or
            $cmd -match '(?i)\bpowershell\.exe\b') {
            $isPwshTarget = $true
        }
    }

    $styleProfile = Join-Path $styleDir 'profile.ps1'
    if ($isPwshTarget) {
        if (Test-Path -LiteralPath $styleProfile) {
            Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
        } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
            Remove-Item -LiteralPath $script:TStylesCurrent -Force
        }
    }

    Write-Host ""
    Write-Host "  Style applied: " -NoNewline
    Write-Host $StyleName -ForegroundColor Green
    Write-Host ""

    # Live reload (same pattern as the picker's confirm path)
    if ($isPwshTarget -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
        . $script:TStylesCurrent
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
        [object[]]$Targets
    )

    $loaderBegin = '# ===== TerminalStyles BEGIN ====='
    $loaderEnd   = '# ===== TerminalStyles END ====='
    $loaderBody  = @"
$loaderBegin
Import-Module TerminalStyles -DisableNameChecking
$loaderEnd
"@

    if (-not $Targets) {
        # Discover both engines, get $PROFILE per engine
        $shells = @(
            @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
            @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
        )
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
        Write-Host "Neither pwsh.exe nor powershell.exe was found on PATH. Nothing to do." -ForegroundColor Yellow
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
    $ans = Read-Host "Continue? [Y/n]"
    if ($ans -match '^(?i)n') {
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
        [System.IO.File]::WriteAllText($t.ProfilePath, $final, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Registered in $($t.ProfilePath)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "TerminalStyles will auto-load on every new shell tab." -ForegroundColor Cyan
    Write-Host "To verify in this session: Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData    # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
    )

    $dataDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
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
    $ans = Read-Host "Continue? [y/N]"
    if ($ans -notmatch '^(?i)y') {
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
            $installManagedItems = @(
                'tstyles.ps1', 'apply.ps1', 'install.ps1',
                'TerminalStyles.psd1', 'TerminalStyles.psm1',
                'styles', 'scripts',
                'README.md', 'LICENSE'
            )
            foreach ($item in $installManagedItems) {
                $path = Join-Path $dataDir $item
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  Removed install-managed files from $dataDir" -ForegroundColor Green
        }
    }

    # 2. Strip the loader from both PowerShell engines' $PROFILE
    foreach ($exe in 'pwsh.exe', 'powershell.exe') {
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

    # 3. Optionally remove user state
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

# === Public command ===

function Invoke-TerminalStyle {
    [CmdletBinding()]
    param(
        # Positional argument: a subcommand (list / current / random / update /
        # uninstall), a bundled style name (umbrella / eva / ...), or -- as a
        # backward-compat fallback -- a Windows Terminal profile name to
        # target with the interactive picker.
        [Parameter(Position=0)]
        [string]$Arg,
        # Explicit Windows Terminal profile to apply to (defaults to the
        # current tab's profile via $env:WT_PROFILE_ID).
        [string]$Target,
        [string]$BackgroundImage,
        [switch]$Update,
        # Used with `tstyles update -Force` to skip the same-SHA optimization
        # and force a full reinstall (e.g., after a botched install).
        [switch]$Force
    )

    $bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')

    # --- Subcommand dispatch ---
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall;  return }

    # If $Arg matches a bundled style, apply it directly (no picker).
    if ($Arg) {
        $styleMatch = Get-AvailableStyles | Where-Object Name -eq $Arg | Select-Object -First 1
        if ($styleMatch) {
            Apply-StyleDirect -StyleName $Arg -Target $Target `
                -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
            return
        }
        # Backward compat: $Arg wasn't a subcommand or a style name, so treat
        # it as a Windows Terminal profile name for the picker (old behavior).
        if (-not $Target) { $Target = $Arg }
    }

    # Update-notice path runs on every passive invocation (picker included),
    # but Test-UpdateAvailable short-circuits inside the 24h throttle window.
    Show-UpdateNoticeIfAvailable

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    $styles = @(Get-ChildItem -LiteralPath $stylesDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'scheme.json')
    } | Sort-Object Name)
    if (-not $styles) {
        Write-Error "No styles found at $stylesDir"
        return
    }

    # Snapshot original (byte-exact for revert)
    # MUST be UTF-8 explicit: Get-Content -Raw in Windows PowerShell 5.1
    # defaults to the system ANSI codepage (Windows-1252 on Spanish locale),
    # which mangles non-ASCII profile names (e.g. "Símbolo del sistema").
    # The mangled string then round-trips through ConvertTo-Json + WriteAllText
    # as UTF-8, doubling the byte count of non-ASCII chars on every call.
    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $originalSettings = $originalJson | ConvertFrom-Json

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $originalSettings }
    if (-not $Target) {
        Write-Host "Could not auto-detect the current Windows Terminal profile."
        Write-Host "Available: $((@('defaults') + @($originalSettings.profiles.list.name)) -join ', ')"
        $Target = (Read-Host "Target profile").Trim()
        if (-not $Target) { return }
    }

    if (-not $env:WT_SESSION) {
        Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
    }

    # Start on the currently active style if we can detect one -- opening
    # the picker should land where the user already is, not at the first
    # alphabetical entry. Falls back to 0 for custom/unrecognized profiles.
    $idx = 0
    $currentName = Get-CurrentStyleName
    if ($currentName) {
        for ($i = 0; $i -lt $styles.Count; $i++) {
            if ($styles[$i].Name -eq $currentName) { $idx = $i; break }
        }
    }
    $confirmed = $false

    # Pre-load each style's color swatch AND the parsed scheme object.
    # Schemes are reused per-arrow to emit OSC color escapes (see the
    # render loop below) so the terminal repaints colors in <5ms, well
    # before the eventual settings.json write triggers Windows Terminal's
    # full reload cycle.
    $swatches = @{}
    $schemes  = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $sp = Join-Path $styles[$i].FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatches[$i] = Get-SchemeSwatch -Scheme $scheme
        $schemes[$i]  = $scheme
    }

    # Pre-load each style's tabTitle (from theme.json). settings.json's
    # tabTitle isn't honored by Windows Terminal for a tab whose shell has
    # already set $Host.UI.RawUI.WindowTitle (every theme's profile.ps1
    # does), so we have to set WindowTitle explicitly on each arrow change
    # to make the title preview live. Themes without a tabTitle simply
    # leave the current title untouched while highlighted.
    $titles = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $tp = Join-Path $styles[$i].FullName 'theme.json'
        if (-not (Test-Path -LiteralPath $tp)) { continue }
        try {
            $theme = [System.IO.File]::ReadAllText($tp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($theme.PSObject.Properties.Match('tabTitle').Count -gt 0) {
                $titles[$i] = $theme.tabTitle
            }
        } catch { }
    }

    # Background prefetch: kick off ONE job that downloads any missing GIFs
    # from the gifs branch serially. The picker stays interactive while this
    # runs; by the time the user arrow-keys through a few styles, the rest
    # are usually already cached locally. Worst case: the user reaches a
    # style before its GIF arrives -- the synchronous fetch in
    # Get-StyleBundledBackground handles it (same code path as today).
    $missingPaths = @()
    foreach ($s in $styles) {
        if (-not (Test-StyleResolved -StyleDir $s.FullName)) {
            $missingPaths += $s.FullName
        }
    }
    $prefetchJob = $null
    if ($missingPaths.Count -gt 0) {
        # Prefer Start-ThreadJob if available -- it's ~10x faster to start
        # than Start-Job (pwsh 7 ships it; WinPS 5.1 has it only if the
        # user installed the ThreadJob module). Falls back to Start-Job.
        $jobStarter = if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            'Start-ThreadJob'
        } else {
            'Start-Job'
        }
        $prefetchJob = & $jobStarter -ScriptBlock {
            param($Paths)
            $ProgressPreference = 'SilentlyContinue'
            foreach ($styleDir in $Paths) {
                $styleName = Split-Path -Leaf $styleDir
                $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
                $success = $false
                foreach ($ext in 'gif','png','jpg','jpeg') {
                    $local = Join-Path $styleDir "background.$ext"
                    try {
                        Invoke-WebRequest -Uri "$remoteBase.$ext" -OutFile $local `
                            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                            $success = $true
                            break
                        } else {
                            Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
                    }
                }
                if (-not $success) {
                    try { New-Item -ItemType File -Path (Join-Path $styleDir '.no-background') -Force | Out-Null } catch { }
                }
            }
        } -ArgumentList (,$missingPaths)
    }

    # Memoization: cache the final JSON string per style index. Only cache
    # AFTER the style is resolved (so we don't pin a JSON that was computed
    # while the GIF was still pending). Arrow-keying back to a previously-
    # visited resolved style writes the cached string straight to disk --
    # skips ConvertFrom-Json + Merge + ConvertTo-Json (~100ms per cycle).
    $mergedCache = @{}

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle
    try {
        # Apply first preview before showing the menu
        $preview = $originalJson | ConvertFrom-Json
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$idx].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
        $initialJson = $preview | ConvertTo-Json -Depth 32
        [System.IO.File]::WriteAllText($settingsPath, $initialJson, [System.Text.UTF8Encoding]::new($false))
        if (Test-StyleResolved -StyleDir $styles[$idx].FullName) {
            $mergedCache[$idx] = $initialJson
        }
        if ($titles.ContainsKey($idx)) { $Host.UI.RawUI.WindowTitle = $titles[$idx] }

        # Truecolor mid-gray for the picker's secondary text. PowerShell's
        # "DarkGray" maps to each scheme's brightBlack slot, which on
        # low-contrast themes (rain, forest, golden-forest) sits too close
        # to the background to read. A fixed #a0a0a0 stays legible on every
        # background -- dark themes and the light gitbash alike.
        $hintColor  = "$([char]27)[38;2;160;160;160m"
        $resetColor = "$([char]27)[0m"

        # Clear once, then capture the buffer Y of the picker's home row.
        # Subsequent iterations reposition the cursor here and overwrite in
        # place instead of Clear-Host-ing per arrow press -- the per-arrow
        # clear was the source of the visible flicker. The number of lines
        # is constant (header + hint + blank + N styles + blank), so the
        # overwrite covers the previous frame exactly with no leftover
        # characters. \e[K appended to each potentially shrinking line
        # would defend against future content-width changes; not needed
        # today since every row has stable width.
        Clear-Host
        $renderHomeY = [Console]::CursorTop

        # Non-blocking render loop with three responsibilities, in
        # strict priority order:
        #   1. Process pending keypresses -- update $idx, redraw the
        #      menu IMMEDIATELY so the cursor visually moves, but do
        #      NOT apply the theme yet. Set $pendingApply = $idx and
        #      loop back to drain any further keypresses.
        #   2. Apply the pending theme (settings.json write + tab
        #      title) once the keypress queue is empty. Mashed arrows
        #      collapse to a single apply at the final position --
        #      Windows Terminal does one reload instead of N.
        #   3. Prebuild the next uncached resolved theme's merged
        #      JSON during idle slices so future applies are pure
        #      WriteAllText (no parse / merge / serialize).
        #
        # Net effect:
        #   Single tap  -> cursor jumps in ~5ms, theme applies after
        #                  ~50-100ms once the gap is detected.
        #   Mash 5 keys -> cursor moves through all 5 visually, only
        #                  the final position is written to settings.json,
        #                  WT does one reload instead of five.
        # Build pre-serialized OSC color packets, one per theme. Each
        # packet is a single string of ANSI OSC sequences that, when
        # written to stdout, instantly retints the terminal's
        # foreground / background / cursor / selection / 16-color
        # palette to that theme -- no settings.json write, no Windows
        # Terminal reload. The eventual settings.json write (deferred
        # to when the keypress queue drains) still happens and brings
        # the background image, cursor shape, font, etc. into line a
        # few hundred ms later, but the colors have already shifted
        # so the perceived freeze drops to near-zero.
        $oscPackets = @{}
        $BEL  = [char]7
        $oscEsc = [char]27
        $palette = 'black','red','green','yellow','blue','purple','cyan','white',
                   'brightBlack','brightRed','brightGreen','brightYellow',
                   'brightBlue','brightPurple','brightCyan','brightWhite'
        for ($i = 0; $i -lt $styles.Count; $i++) {
            $s = $schemes[$i]
            $sb = [System.Text.StringBuilder]::new()
            if ($s.foreground)          { [void]$sb.Append("${oscEsc}]10;$($s.foreground)$BEL") }
            if ($s.background)          { [void]$sb.Append("${oscEsc}]11;$($s.background)$BEL") }
            if ($s.cursorColor)         { [void]$sb.Append("${oscEsc}]12;$($s.cursorColor)$BEL") }
            if ($s.selectionBackground) { [void]$sb.Append("${oscEsc}]17;$($s.selectionBackground)$BEL") }
            for ($p = 0; $p -lt $palette.Count; $p++) {
                $color = $s.($palette[$p])
                if ($color) {
                    [void]$sb.Append("${oscEsc}]4;${p};${color}$BEL")
                }
            }
            $oscPackets[$i] = $sb.ToString()
        }

        $drawMenu = {
            [Console]::SetCursorPosition(0, $renderHomeY)
            Write-Host ""
            Write-Host "  Choose a style for " -NoNewline
            Write-Host "'$Target'" -ForegroundColor Cyan
            Write-Host "$hintColor  Up/Down to preview, Enter to keep, Esc to cancel$resetColor"
            Write-Host ""
            for ($i = 0; $i -lt $styles.Count; $i++) {
                $name = $styles[$i].Name
                $resolved = Test-StyleResolved -StyleDir $styles[$i].FullName
                $color = if ($i -eq $idx) { 'Yellow' } else { 'Gray' }
                $prefix = if ($i -eq $idx) { '   > ' } else { '     ' }
                Write-Host ($prefix + ('{0,-16}  ' -f $name)) -ForegroundColor $color -NoNewline
                if ($resolved) {
                    Write-Host $swatches[$i]
                } else {
                    Write-Host "$hintColor...fetching background$resetColor"
                }
            }
            Write-Host ""
        }

        $applyTheme = {
            param([int]$i)
            $resolved = Test-StyleResolved -StyleDir $styles[$i].FullName
            if ($resolved -and $mergedCache.ContainsKey($i)) {
                [System.IO.File]::WriteAllText($settingsPath, $mergedCache[$i], [System.Text.UTF8Encoding]::new($false))
            } else {
                $preview = $originalJson | ConvertFrom-Json
                $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$i].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $json = $preview | ConvertTo-Json -Depth 32
                [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
                if ($resolved) { $mergedCache[$i] = $json }
            }
            if ($titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
        }

        $needsRedraw = $true
        $pendingApply = -1

        while (-not $confirmed) {
            if ($needsRedraw) {
                & $drawMenu
                $needsRedraw = $false
            }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' {
                        if ($idx -gt 0) {
                            $idx--; $needsRedraw = $true; $pendingApply = $idx
                            [Console]::Out.Write($oscPackets[$idx])
                        }
                    }
                    'DownArrow' {
                        if ($idx -lt $styles.Count - 1) {
                            $idx++; $needsRedraw = $true; $pendingApply = $idx
                            [Console]::Out.Write($oscPackets[$idx])
                        }
                    }
                    'Enter' {
                        # Drain any pending apply so the confirmed theme
                        # is in settings.json before we copy profile.ps1.
                        if ($pendingApply -ge 0) {
                            & $applyTheme $pendingApply
                            $pendingApply = -1
                        }
                        $confirmed = $true
                    }
                    'Escape' {
                        [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
                        Clear-Host
                        Write-Host "Reverted." -ForegroundColor Yellow
                        return
                    }
                }
                continue
            }

            # Keypress queue empty. Apply the latest pending theme (if
            # any) before doing anything else. This is the "debounce
            # tail" -- only the final position from a mash sequence
            # actually gets written to settings.json.
            if ($pendingApply -ge 0) {
                $applyIdx = $pendingApply
                $pendingApply = -1
                & $applyTheme $applyIdx
                continue
            }

            # Truly idle. Prebuild the next uncached resolved theme.
            # Skips themes whose backgrounds haven't been fetched yet
            # (the prefetch job is still downloading them) -- those
            # cache lazily once resolved, or via on-demand merge if
            # the user arrows there first.
            $nextPrebuild = -1
            for ($j = 0; $j -lt $styles.Count; $j++) {
                if ($mergedCache.ContainsKey($j)) { continue }
                if (-not (Test-StyleResolved -StyleDir $styles[$j].FullName)) { continue }
                $nextPrebuild = $j
                break
            }
            if ($nextPrebuild -ge 0) {
                $pp = $originalJson | ConvertFrom-Json
                $pp = Merge-StyleIntoSettings -Settings $pp -StyleDir $styles[$nextPrebuild].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $mergedCache[$nextPrebuild] = $pp | ConvertTo-Json -Depth 32
            } else {
                Start-Sleep -Milliseconds 50
            }
        }

        # Confirmed -- maybe install profile.ps1
        $selectedStyle = $styles[$idx]
        $styleProfile  = Join-Path $selectedStyle.FullName 'profile.ps1'

        $isPwshTarget = $false
        if ($Target -eq 'defaults') {
            $isPwshTarget = $true
        } else {
            $entry = $originalSettings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
            $cmd = "$($entry.commandline)"
            $src = "$($entry.source)"
            if ($src -eq 'Windows.Terminal.PowershellCore' -or
                $cmd -match '(?i)\bpwsh\.exe\b' -or
                $cmd -match '(?i)\bpowershell\.exe\b') {
                $isPwshTarget = $true
            }
        }

        if ($isPwshTarget) {
            if (Test-Path -LiteralPath $styleProfile) {
                Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
            } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
                Remove-Item -LiteralPath $script:TStylesCurrent -Force
            }
        }

        Clear-Host
        Write-Host ""
        Write-Host "  Style applied: " -NoNewline
        Write-Host $selectedStyle.Name -ForegroundColor Green
        Write-Host ""

        # Live-reload: dot-source the newly active profile so the title,
        # prompt, banner, and PSReadLine colors update in THIS session
        # without requiring the user to open a new tab. Each theme's
        # profile.ps1 uses `function global:prompt` so the binding escapes
        # this function's scope.
        if ($isPwshTarget -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
            . $script:TStylesCurrent
        }
    } finally {
        [Console]::CursorVisible = $true
        # Restore the original window title on cancel / exception. The
        # confirm path already had the selected theme's profile.ps1
        # dot-sourced (which sets its own title), so we only restore when
        # the user didn't confirm.
        if (-not $confirmed) {
            $Host.UI.RawUI.WindowTitle = $originalTitle
        }
        # Clean up the background prefetch job. If it's still mid-fetch
        # (user picked quickly), the downloads in progress may be cut off
        # -- the next Get-StyleBundledBackground call will fall back to
        # synchronous fetch for whatever didn't complete.
        if ($prefetchJob) {
            Stop-Job -Job $prefetchJob -ErrorAction SilentlyContinue
            Remove-Job -Job $prefetchJob -Force -ErrorAction SilentlyContinue
        }
    }
}

Set-Alias -Name tstyles -Value Invoke-TerminalStyle -Force

# Tab completion: complete the positional Arg with subcommands + style names.
# Applies to both the function and the tstyles alias (PowerShell extends
# argument completers across aliases automatically).
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = @('list', 'current', 'random', 'register', 'update', 'uninstall')
    # Get-AvailableStyles already unions $DataRoot\styles\ + $ModuleRoot\styles\
    # with user-wins dedup -- single source of truth for what `tstyles <name>`
    # can target.
    $styleNames = @(Get-AvailableStyles | ForEach-Object Name)
    $all = @($subcommands + $styleNames | Sort-Object -Unique)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# One-time data-layout migration for users upgrading from pre-0.2.0.
# Idempotent; gated by a marker file.
Invoke-TerminalStylesStateMigration

# === Auto-load the currently selected style's profile.ps1 ===
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}
