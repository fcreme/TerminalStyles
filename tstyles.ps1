# tstyles.ps1 -- TerminalStyles loader + interactive picker.
#
# Dot-sourced from $PROFILE by install.ps1. Provides:
#   * `tstyles` (alias of Invoke-TerminalStyle) -- arrow-key live-preview picker.
#   * Auto-loads the currently selected style's profile.ps1 on shell startup.
#
# All write operations restore on Escape; the original settings.json bytes are
# snapshotted on entry so a cancel is byte-exact.

#Requires -Version 5.1

$script:TStylesRoot = $PSScriptRoot
if (-not $script:TStylesRoot) {
    $script:TStylesRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$script:TStylesCurrent = Join-Path $script:TStylesRoot 'current-style.ps1'

# === Auto-load the currently selected style's profile.ps1 ===
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}

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
    #   1. Local file in $StyleDir (covers dev workflow + previously-fetched cache)
    #   2. Negative cache (.no-background marker) -- skip fetch, return $null
    #   3. Fetch from the `gifs` branch on GitHub, cache locally, return path
    #
    # This keeps the main install ZIP code-only (~100 KB instead of ~10 MB)
    # and pulls each background on first use of its style. After the first
    # fetch, subsequent runs are instant -- the GIF lives next to the rest
    # of the style files in %LOCALAPPDATA%\TerminalStyles\styles\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir)

    # 1. Local file already present
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    # 2. Negative cache (we've tried and the remote has nothing for this style)
    $noBgMarker = Join-Path $StyleDir '.no-background'
    if (Test-Path -LiteralPath $noBgMarker) { return $null }

    # 3. Lazy-fetch from the gifs branch
    $styleName = Split-Path -Leaf $StyleDir
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $StyleDir "background.$ext"
            try {
                Invoke-WebRequest -Uri $url -OutFile $local -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                    return $local
                } else {
                    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                }
            } catch {
                # Try next extension; remove any partial file
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # All extensions failed -- write negative-cache marker so we don't re-probe
    # on every arrow-key press in the picker.
    try {
        New-Item -ItemType File -Path $noBgMarker -Force | Out-Null
    } catch { }
    return $null
}

function Test-UpdateAvailable {
    # Returns a pscustomobject with short SHAs if a newer commit is available
    # on origin/main, or $null if not / can't tell. Throttled to one API
    # call per 24h via .last-update-check; the timestamp is always written
    # (even on network failure) so a transient outage doesn't trigger
    # retries on every tstyles invocation.
    $shaFile   = Join-Path $script:TStylesRoot '.installed-sha'
    $stampFile = Join-Path $script:TStylesRoot '.last-update-check'

    if (Test-Path -LiteralPath $stampFile) {
        try {
            $stamp = [datetime]::Parse((Get-Content -LiteralPath $stampFile -Raw).Trim())
            if (((Get-Date) - $stamp).TotalHours -lt 24) { return $null }
        } catch { }
    }

    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = (Get-Content -LiteralPath $shaFile -Raw).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        # GitHub's API documents User-Agent as required for unauthenticated
        # requests. Without it you can sporadically hit 403 even under the
        # rate limit. Identify the tool so requests are well-formed.
        $resp = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
            -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
            -TimeoutSec 3 -ErrorAction Stop
        $remote = $resp.sha
    } catch { }

    try {
        Set-Content -LiteralPath $stampFile -Value (Get-Date -Format 'o') `
                    -Encoding UTF8 -NoNewline -ErrorAction Stop
    } catch { }

    if ($remote -and $remote -ne $installed) {
        return [pscustomobject]@{
            Installed = $installed.Substring(0, [Math]::Min(7, $installed.Length))
            Remote    = $remote.Substring(0, [Math]::Min(7, $remote.Length))
        }
    }
    return $null
}

function Invoke-TerminalStylesUpdate {
    [CmdletBinding()]
    param([switch]$Force)

    Write-Host ""
    Write-Host "Updating TerminalStyles from GitHub..." -ForegroundColor Cyan

    # Cheap check first: if we already have the current main SHA, skip the
    # ~10MB ZIP download entirely. -Force overrides (for recovery from a
    # botched install).
    $shaFile = Join-Path $script:TStylesRoot '.installed-sha'
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
            # If the check fails (offline, rate-limited), fall through to the
            # full download path. Better to update than to fail silently.
        }
    }

    # Suppress the IWR progress bar -- dominant cost on WinPS 5.1.
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $installerScript = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1' -UseBasicParsing).Content
        Invoke-Expression $installerScript
        # Files on disk are new; this session is still running the OLD
        # tstyles.ps1 (functions are bound at dot-source time, not per call).
        # Tell the user how to pick up the new code.
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

function Get-AvailableStyles {
    # Returns an array of DirectoryInfo for every styles/<name>/ that has a
    # scheme.json. Sorted alphabetically by name.
    $stylesDir = Join-Path $script:TStylesRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) { return @() }
    @(Get-ChildItem -LiteralPath $stylesDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'scheme.json')
    } | Sort-Object Name)
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

function Get-SchemeSwatch {
    # Returns a one-line ANSI swatch (5 colored blocks) summarising a theme.
    # Picks colors that show character: warm accent, secondary warm, green,
    # cool, accent magenta. Trailing reset.
    param([Parameter(Mandatory)]$Scheme)
    $picks = @($Scheme.brightRed, $Scheme.yellow, $Scheme.brightGreen, $Scheme.brightCyan, $Scheme.brightPurple)
    $sb = New-Object System.Text.StringBuilder
    foreach ($hex in $picks) {
        if (-not $hex) { continue }
        $h = ([string]$hex).TrimStart('#')
        if ($h.Length -lt 6) { continue }
        $r = [Convert]::ToInt32($h.Substring(0,2), 16)
        $g = [Convert]::ToInt32($h.Substring(2,2), 16)
        $b = [Convert]::ToInt32($h.Substring(4,2), 16)
        [void]$sb.Append([char]27).Append("[38;2;${r};${g};${b}m").Append([char]0x2588).Append([char]0x2588)
    }
    [void]$sb.Append([char]27).Append('[0m')
    return $sb.ToString()
}

function Show-StyleList {
    # `tstyles list` -- print available styles, marking the active one.
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
        Write-Host "  (* = currently active)" -ForegroundColor DarkGray
    } else {
        Write-Host "  (no bundled style currently active)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-CurrentStyle {
    # `tstyles current` -- print just the active style name on stdout.
    $current = Get-CurrentStyleName
    if ($current) {
        Write-Output $current
    } else {
        Write-Host "(no bundled style currently active)" -ForegroundColor DarkGray
    }
}

function Invoke-RandomStyle {
    # `tstyles random` -- pick a random bundled style and apply it.
    # Excludes the currently active one so it actually changes.
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

    $styleDir = Join-Path $script:TStylesRoot "styles\$StyleName"
    if (-not (Test-Path -LiteralPath (Join-Path $styleDir 'scheme.json'))) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

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

function Invoke-TerminalStylesUninstall {
    # `tstyles uninstall` -- remove %LOCALAPPDATA%\TerminalStyles and the
    # loader block from both PowerShell engines' $PROFILE. Asks confirmation.
    # Does NOT modify settings.json (user keeps whatever scheme/bg they had).
    Write-Host ""
    Write-Host "This will remove TerminalStyles:" -ForegroundColor Yellow
    Write-Host ("  - " + (Join-Path $env:LOCALAPPDATA 'TerminalStyles') + " (entire folder)") -ForegroundColor Yellow
    Write-Host "  - The loader block from pwsh 7 and Windows PowerShell 5.1 `$PROFILE files" -ForegroundColor Yellow
    Write-Host "  - It will NOT modify Windows Terminal's settings.json." -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Host "Continue? [y/N]"
    if ($ans -notmatch '^(?i)y') {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

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

    $installDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
        Write-Host "  Removed $installDir" -ForegroundColor Green
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

    # Once-per-day update notice. Non-blocking, silent on any error.
    $pending = Test-UpdateAvailable
    if ($pending) {
        Write-Host ("Update available ({0} -> {1}). Run: tstyles update" -f $pending.Installed, $pending.Remote) -ForegroundColor Yellow
        Write-Host ""
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $stylesDir = Join-Path $script:TStylesRoot 'styles'
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

    $idx = 0
    $confirmed = $false

    # Pre-load each style's color swatch once so the render loop doesn't
    # re-read scheme.json on every arrow press.
    $swatches = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $sp = Join-Path $styles[$i].FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatches[$i] = Get-SchemeSwatch -Scheme $scheme
    }

    [Console]::CursorVisible = $false
    try {
        # Apply first preview before showing the menu
        $preview = $originalJson | ConvertFrom-Json
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$idx].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
        Write-SettingsFile -Path $settingsPath -Settings $preview

        while (-not $confirmed) {
            Clear-Host
            Write-Host ""
            Write-Host "  Choose a style for " -NoNewline
            Write-Host "'$Target'" -ForegroundColor Cyan
            Write-Host "  Up/Down to preview, Enter to keep, Esc to cancel" -ForegroundColor DarkGray
            Write-Host ""
            for ($i = 0; $i -lt $styles.Count; $i++) {
                $name = $styles[$i].Name
                $swatch = $swatches[$i]
                if ($i -eq $idx) {
                    Write-Host ("   > {0,-16}  " -f $name) -ForegroundColor Yellow -NoNewline
                    Write-Host $swatch
                } else {
                    Write-Host ("     {0,-16}  " -f $name) -ForegroundColor Gray -NoNewline
                    Write-Host $swatch
                }
            }
            Write-Host ""

            $key = [Console]::ReadKey($true)
            $changed = $false
            switch ($key.Key) {
                'UpArrow'   { if ($idx -gt 0) { $idx--; $changed = $true } }
                'DownArrow' { if ($idx -lt $styles.Count - 1) { $idx++; $changed = $true } }
                'Enter'     { $confirmed = $true }
                'Escape' {
                    [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
                    Clear-Host
                    Write-Host "Reverted." -ForegroundColor Yellow
                    return
                }
            }

            if ($changed) {
                $preview = $originalJson | ConvertFrom-Json
                $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$idx].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                Write-SettingsFile -Path $settingsPath -Settings $preview
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
    }
}

Set-Alias -Name tstyles -Value Invoke-TerminalStyle -Force

# Tab completion: complete the positional Arg with subcommands + style names.
# Applies to both the function and the tstyles alias (PowerShell extends
# argument completers across aliases automatically).
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = @('list', 'current', 'random', 'update', 'uninstall')
    $stylesDir = Join-Path $script:TStylesRoot 'styles'
    $styleNames = if (Test-Path -LiteralPath $stylesDir) {
        @(Get-ChildItem -LiteralPath $stylesDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name })
    } else { @() }
    $all = @($subcommands + $styleNames | Sort-Object)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
