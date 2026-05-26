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
    param([Parameter(Mandatory)][string]$StyleDir)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Merge-StyleIntoSettings {
    param(
        $Settings,
        [string]$StyleDir,
        [string]$TargetName,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided
    )

    $scheme = Get-Content -LiteralPath (Join-Path $StyleDir 'scheme.json') -Raw | ConvertFrom-Json

    if (-not $Settings.PSObject.Properties.Match('schemes').Count) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
    }
    $Settings.schemes = @($Settings.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme

    $themePath = Join-Path $StyleDir 'theme.json'
    if (-not (Test-Path -LiteralPath $themePath)) { return $Settings }
    $theme = Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json

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
    #   1. User passed -BackgroundImage <path> (incl. "")   -> use that
    #   2. Style ships a bundled background.{gif,png,jpg}   -> use that
    #   3. Otherwise                                        -> leave user's bg alone
    $effectiveBg = $BackgroundImage
    $applyBg = $BackgroundImageProvided
    if (-not $applyBg) {
        $bundled = Get-StyleBundledBackground -StyleDir $StyleDir
        if ($bundled) {
            $effectiveBg = $bundled
            $applyBg = $true
        }
    }

    $bgFields = @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode', 'backgroundImageAlignment')
    foreach ($prop in $theme.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($name -in $bgFields) {
            if (-not $applyBg) { continue }
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

# === Public command ===

function Invoke-TerminalStyle {
    [CmdletBinding()]
    param(
        [string]$Target,
        [string]$BackgroundImage
    )

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
    $originalJson = Get-Content -LiteralPath $settingsPath -Raw
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

    $bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')
    $idx = 0
    $confirmed = $false

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
                if ($i -eq $idx) {
                    Write-Host ("   > {0}" -f $styles[$i].Name) -ForegroundColor Yellow
                } else {
                    Write-Host ("     {0}" -f $styles[$i].Name) -ForegroundColor Gray
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
