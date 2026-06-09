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
$repoRoot  = $PSScriptRoot
$stylesDir = Join-Path $repoRoot 'styles'

function Remove-JsonComment {
    # NOTE: duplicated from tstyles.ps1 -- keep in sync. (apply.ps1 is a
    # standalone script that doesn't yet dot-source the library.) Strips // and
    # /* */ comments outside string literals so Windows Terminal's commented
    # settings.json parses on Windows PowerShell 5.1, whose ConvertFrom-Json
    # rejects comments.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $n) {
            $next = $Text[$i + 1]
            if ($next -eq '/') {
                $i += 2
                while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($next -eq '*') {
                $i += 2
                while ($i -lt $n -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function Remove-JsonTrailingComma {
    # NOTE: duplicated from tstyles.ps1 -- keep in sync. Drop trailing commas
    # (a ',' whose next non-whitespace char is '}' or ']') OUTSIDE string literals.
    # pwsh 7 tolerates them but Windows PowerShell 5.1's ConvertFrom-Json rejects
    # them ("extra trailing ','"); commas inside string values are preserved. Run
    # AFTER Remove-JsonComment so a comment can't hide the trailing comma.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq ',') {
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $n -and ($Text[$j] -eq '}' -or $Text[$j] -eq ']')) {
                $i++
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function ConvertFrom-WTJson {
    # NOTE: duplicated from tstyles.ps1 -- keep in sync. Parse WT settings.json
    # tolerating // and /* */ comments and trailing commas; throw one actionable
    # error otherwise.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $clean = Remove-JsonComment -Text $Json
    $clean = Remove-JsonTrailingComma -Text $clean
    try {
        $clean | ConvertFrom-Json
    } catch {
        throw ("TerminalStyles: could not parse Windows Terminal settings.json. " +
               "On Windows PowerShell 5.1, JSON comments other than // and /* */ are not supported -- " +
               "open WT Settings and Save once, or remove the offending text. " +
               "Underlying error: $($_.Exception.Message)")
    }
}

function Get-AvailableStyles {
    if (-not (Test-Path -LiteralPath $stylesDir)) {
        throw "No styles directory at $stylesDir"
    }
    Get-ChildItem -LiteralPath $stylesDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'scheme.json')
    }
}

function Get-StyleBundledBackground {
    # See tstyles.ps1 for full notes. Three-tier resolution: local file ->
    # negative-cache marker -> lazy-fetch from the `gifs` branch with caching.
    param([Parameter(Mandatory)][string]$StyleDir)

    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $noBgMarker = Join-Path $StyleDir '.no-background'
    if (Test-Path -LiteralPath $noBgMarker) { return $null }

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
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    try {
        New-Item -ItemType File -Path $noBgMarker -Force | Out-Null
    } catch { }
    return $null
}

function Find-SettingsPath {
    # Prefer the live WT build's settings.json ($env:WT_SETTINGS_PATH) before the
    # static Stable > Preview > unpackaged list -- otherwise a user on WT Preview
    # silently edits Stable's file. NOTE: mirrors tstyles.ps1 Find-WTSettingsPath.
    if ($env:WT_SETTINGS_PATH -and (Test-Path -LiteralPath $env:WT_SETTINGS_PATH)) {
        return $env:WT_SETTINGS_PATH
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw "Could not locate Windows Terminal settings.json. Pass -SettingsPath."
}

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

function Merge-ThemeIntoEntry {
    param($Entry, $Theme, [string]$BackgroundImagePath)

    $bgFields = @(
        'backgroundImage', 'backgroundImageOpacity',
        'backgroundImageStretchMode', 'backgroundImageAlignment'
    )

    foreach ($prop in $Theme.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($name -in $bgFields -and -not $BackgroundImagePath) {
            if ($Entry.PSObject.Properties.Match($name).Count -gt 0) {
                $Entry.PSObject.Properties.Remove($name)
            }
            continue
        }
        if ($name -eq 'backgroundImage' -and $value -eq '{{BACKGROUND_IMAGE}}') {
            $value = $BackgroundImagePath
        }

        if ($Entry.PSObject.Properties.Match($name).Count -gt 0) {
            $Entry.$name = $value
        } else {
            $Entry | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }
}

function Write-WTSettingsFile {
    # Serialize + write Windows Terminal settings.json durably.
    # NOTE: mirrors tstyles.ps1's Write-SettingsFile/Write-SettingsAtomic -- keep
    # in sync. (apply.ps1 is standalone and doesn't dot-source the library.)
    #   * Depth 100 (the JSON max), NOT 32: a user settings.json nested deeper
    #     than 32 is silently stringified (corrupted) by ConvertTo-Json -- with no
    #     warning at all on Windows PowerShell 5.1.
    #   * Atomic replace via a sibling temp file: WriteAllText truncates-then-
    #     writes, so a crash/kill or a concurrent Windows Terminal reload can
    #     observe a half-written/empty settings.json. A same-volume rename is
    #     atomic on NTFS. Falls back to a direct write if Replace/Move is
    #     unsupported. UTF-8 no BOM.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Settings)
    $json = $Settings | ConvertTo-Json -Depth 100
    $enc = [System.Text.UTF8Encoding]::new($false)
    $tmp = "$Path.tstmp"
    [System.IO.File]::WriteAllText($tmp, $json, $enc)
    try {
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($tmp, $Path, $null)
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        [System.IO.File]::WriteAllText($Path, $json, $enc)
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
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
if (-not $SettingsPath) { $SettingsPath = Find-SettingsPath }
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
# Precedence: explicit -BackgroundImage > interactive prompt > bundled style background
$bundledBg = Get-StyleBundledBackground -StyleDir $styleDir

if (-not $PSBoundParameters.ContainsKey('BackgroundImage')) {
    Write-Host ""
    $hint = if ($bundledBg) { "blank = use bundled '$([System.IO.Path]::GetFileName($bundledBg))', 'none' = no background" }
            else            { "blank = no background" }
    $answer = (Read-Host "Background image absolute path ($hint)").Trim()
    if ($answer -eq '') {
        $BackgroundImage = if ($bundledBg) { $bundledBg } else { '' }
    } elseif ($answer -eq 'none') {
        $BackgroundImage = ''
    } else {
        $BackgroundImage = $answer
    }
}
if ($BackgroundImage -and -not (Test-Path -LiteralPath $BackgroundImage)) {
    Write-Warning "Background image path doesn't exist: $BackgroundImage (will still apply the setting)"
}

# --- Load style content ---
$schemePath = Join-Path $styleDir 'scheme.json'
$themePath  = Join-Path $styleDir 'theme.json'
$scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$theme  = if (Test-Path -LiteralPath $themePath) {
    [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
} else { $null }

# --- Backup settings.json ---
$bak = "$SettingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $SettingsPath -Destination $bak
Write-Host "Backed up settings to: $bak" -ForegroundColor Gray

# --- Merge scheme ---
if (-not $settings.PSObject.Properties.Match('schemes').Count) {
    $settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
}
$settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme

# --- Apply theme to target ---
if ($theme) {
    if ($Target -eq 'defaults') {
        if (-not $settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        Merge-ThemeIntoEntry -Entry $settings.profiles.defaults -Theme $theme -BackgroundImagePath $BackgroundImage
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
        Merge-ThemeIntoEntry -Entry $entry -Theme $theme -BackgroundImagePath $BackgroundImage
    }
}

# --- Save settings.json (UTF-8 no BOM, atomic, full depth) ---
Write-WTSettingsFile -Path $SettingsPath -Settings $settings
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
            $currentStyleDest = Join-Path $repoRoot 'current-style.ps1'
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
