# TerminalStyles -- style installer for Windows Terminal + PowerShell 7.
#
# Usage:
#   pwsh -File .\apply.ps1                                            # interactive
#   pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell"       # non-interactive
#   pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
#   pwsh -File .\apply.ps1 -Style umbrella -Target defaults           # apply globally
#   pwsh -File .\apply.ps1 -Style kitty -Target "PowerShell" -KeepPrompt
#
# Always backs up settings.json (and $PROFILE if overwriting one) before
# making changes.

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Style,
    [string]$Target,
    [string]$BackgroundImage,
    [string]$SettingsPath,
    # Apply visuals but not the style's prompt/banner. -NoProfile is the
    # original name, kept as an alias for back-compat.
    [Alias('NoProfile')]
    [switch]$KeepPrompt
)

$ErrorActionPreference = 'Stop'

# The library. apply.ps1 used to carry copy-pasted forks of these functions,
# each with a "keep in sync" note; two of them drifted anyway, in ways that lost
# user data:
#
#   Merge-ThemeIntoEntry stripped the background fields whenever no background
#   resolved, with no ownership check -- so it deleted a background the USER had
#   set (their own image, or Windows Terminal's desktopWallpaper), which the
#   module deliberately leaves alone. tests/Background-Carryover.Tests.ps1 pins
#   that distinction, and only ever covered the module.
#
#   Get-StyleBundledBackground was the pre-0.2.0 shape: it wrote fetched images
#   AND the .no-background marker into the STYLE directory rather than the data
#   root's cache, swallowing the failure -- and this script ships to PSGallery,
#   where that directory belongs to the installed module. It also wrote the old
#   undated marker format, which 0.8.6 reads as expired, so the two had diverged
#   on where the cache lives AND what a marker means.
#
# $TStylesNoAutoLoad keeps the load from re-emitting the currently applied
# style's palette, which would repaint the terminal with the old style just
# before this script applies the new one.
$TStylesNoAutoLoad = $true
. (Join-Path $PSScriptRoot 'tstyles.ps1')

function Read-Choice {
    param([string]$Title, [string[]]$Options)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $answer = Read-Host "Pick a number"
        if ($answer -match '^\d+$') {
            $n = [int]$answer
            if ($n -ge 1 -and $n -le $Options.Count) { return $Options[$n - 1] }
        }
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# Main flow. Guarded so tests can dot-source this script for its functions
# (set $TStylesApplyNoRun = $true before dot-sourcing) without running the
# installer. A normal `pwsh -File apply.ps1` run never sets the var, so main runs.
if (-not $TStylesApplyNoRun) {

# --- Banner ---
Write-Host ""
Write-Host "TerminalStyles installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

# --- Style selection ---
$styles = Get-AvailableStyles
if (-not $Style) {
    $Style = Read-Choice 'Available styles:' @($styles.Name)
}
$styleDir = ($styles | Where-Object Name -eq $Style | Select-Object -First 1).FullName
if (-not $styleDir) {
    throw "Style '$Style' not found. Available: $(($styles.Name) -join ', ')"
}
Write-Host "Style: $Style" -ForegroundColor Green

# --- Settings.json location ---
if (-not $SettingsPath) { $SettingsPath = Find-WTSettingsPath }
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    throw "Settings file not found at $SettingsPath"
}
Write-Host "Settings file: $SettingsPath"

# UTF-8 explicit: Get-Content -Raw in WinPS 5.1 defaults to Windows-1252,
# which mangles non-ASCII WT profile names (e.g. "Símbolo del sistema").
$settings = ConvertFrom-WTJson ([System.IO.File]::ReadAllText($SettingsPath, [System.Text.UTF8Encoding]::new($false)))

# --- Target profile selection ---
$profileNames = @('defaults') + @($settings.profiles.list | ForEach-Object { $_.name })
if (-not $Target) {
    $Target = Read-Choice 'Which Windows Terminal profile to apply this style to?' $profileNames
}
if ($Target -ne 'defaults' -and -not ($settings.profiles.list | Where-Object name -eq $Target)) {
    throw "Profile '$Target' not found. Available: $($profileNames -join ', ')"
}
Write-Host "Target: $Target" -ForegroundColor Green

# --- Background image ---
# Precedence: explicit -BackgroundImage > interactive prompt > bundled style
# background. $bgProvided is the module's contract: $true means "the caller
# decided" (a path applies it, an empty string removes it), $false means "work
# it out from the style", which is what leaves a background the USER set in
# place rather than deleting it.
$bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')

if (-not $bgProvided) {
    $bundledBg = Get-StyleBundledBackground -StyleDir $styleDir
    Write-Host ""
    $hint = if ($bundledBg) { "blank = use bundled '$([System.IO.Path]::GetFileName($bundledBg))', 'none' = no background" }
            else            { "blank = no background" }
    $answer = (Read-Host "Background image absolute path ($hint)").Trim()
    if ($answer -eq '') {
        # Let the merge resolve the bundled image itself -- and, when the style
        # ships none, decide by ownership whether an existing background is ours
        # to clear or the user's to keep.
        $BackgroundImage = ''
    } elseif ($answer -eq 'none') {
        $BackgroundImage = ''
        $bgProvided = $true
    } else {
        $BackgroundImage = $answer
        $bgProvided = $true
    }
}
if ($BackgroundImage -and -not (Test-Path -LiteralPath $BackgroundImage)) {
    Write-Warning "Background image path doesn't exist: $BackgroundImage (will still apply the setting)"
}

# --- Backup settings.json ---
# Timestamped, unlike the module's rolling .bak: this script is the scriptable
# path, so it keeps a full audit trail of every run.
$bak = "$SettingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $SettingsPath -Destination $bak
Write-Host "Backed up settings to: $bak" -ForegroundColor Gray

# --- Merge scheme + theme (the module's own merge, not a fork of it) ---
$settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
    -TargetName $Target -BackgroundImage $BackgroundImage `
    -BackgroundImageProvided $bgProvided

# --- Save settings.json (UTF-8 no BOM, atomic, full depth) ---
Write-SettingsFile -Path $SettingsPath -Settings $settings
Write-Host "settings.json updated." -ForegroundColor Green

# --- Install profile.ps1 (if applicable) ---
$profilePs1 = Join-Path $styleDir 'profile.ps1'
$hasProfile = Test-Path -LiteralPath $profilePs1
if ($hasProfile -and -not $KeepPrompt) {
    $isPwshTarget = $false
    if ($Target -eq 'defaults') {
        $isPwshTarget = $true
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
        $cmd = "$($entry.commandline)"
        $src = "$($entry.source)"
        if ($src -eq 'Windows.Terminal.PowershellCore' -or $cmd -match '(?i)\bpwsh\.exe\b' -or $cmd -match '(?i)\bpowershell\.exe\b') {
            $isPwshTarget = $true
        }
    }

    if ($isPwshTarget) {
        $profileDest = $PROFILE
        $destDir = Split-Path $profileDest -Parent
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }

        # If $PROFILE already contains the tstyles loader block (from
        # install.ps1), this user is on the loader-managed install path:
        # writing the theme's profile.ps1 over $PROFILE would obliterate
        # the loader and break `tstyles`, live-reload, and update-check.
        # Write to current-style.ps1 instead -- the same target the
        # interactive picker uses for live reload.
        $hasLoader = $false
        if (Test-Path -LiteralPath $profileDest) {
            $profileContent = [System.IO.File]::ReadAllText($profileDest, [System.Text.UTF8Encoding]::new($false))
            if ($profileContent -match '(?m)^# =+ TerminalStyles BEGIN =+') {
                $hasLoader = $true
            }
        }

        if ($hasLoader) {
            # The data root, which is where the module READS it from. This used
            # to write beside the script, which only coincides for bootstrap
            # installs -- on PSGallery the module looked somewhere else entirely.
            $currentStyleDest = $script:TStylesCurrent
            Copy-Item -LiteralPath $profilePs1 -Destination $currentStyleDest -Force
            Write-Host "Updated current-style.ps1 (tstyles loader detected; `$PROFILE left intact)" -ForegroundColor Green
        } else {
            if (Test-Path -LiteralPath $profileDest) {
                $profileBak = "$profileDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -LiteralPath $profileDest -Destination $profileBak
                Write-Host "Backed up existing profile to: $profileBak" -ForegroundColor Gray
            }
            Copy-Item -LiteralPath $profilePs1 -Destination $profileDest -Force
            Write-Host "Installed profile.ps1 to: $profileDest" -ForegroundColor Green
        }
    } else {
        Write-Host "Note: '$Target' is not a PowerShell profile -- skipping profile.ps1 install." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Open a new '$Target' tab in Windows Terminal to see the result." -ForegroundColor Cyan

}
