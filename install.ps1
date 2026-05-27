# TerminalStyles one-liner installer.
#
# Intended to be run via:
#   iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
#
# What it does:
#   1. Downloads the latest TerminalStyles ZIP from GitHub
#   2. Extracts it to %LOCALAPPDATA%\TerminalStyles
#   3. Registers a loader block in your pwsh 7 $PROFILE (idempotent)
#   4. Detects if your existing $PROFILE matches a bundled style and migrates it
#
# After install, open a new pwsh tab and run:  tstyles

#Requires -Version 5.1

# Force UTF-8 console output as defense-in-depth. The installer's own
# output is pure 7-bit ASCII (so it renders identically in any codepage,
# including WinPS 5.1's CP437 default where Unicode mid-process encoding
# changes are unreliable). These settings still apply for any downstream
# code that emits Unicode -- harmless if not needed.
$null = & chcp 65001 2>&1
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
# Suppress the IWR / Expand-Archive progress UI. On Windows PowerShell 5.1
# this is the dominant cost of the install -- the progress-bar rendering
# can make a ~10MB download take 30+ seconds. Silencing it gives 5-10x
# speedups. Doesn't affect pwsh 7 noticeably but doesn't hurt either.
$ProgressPreference = 'SilentlyContinue'

$repo       = 'fcreme/TerminalStyles'
$branch     = 'main'
$installDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
$zipUrl     = "https://github.com/$repo/archive/refs/heads/$branch.zip"
# GUID-suffix both temp paths so back-to-back runs (or a crashed prior
# run leaving a locked file behind) never collide. AV scanners and
# OneDrive sync can hold transient locks on $env:TEMP files; a fresh
# name per invocation sidesteps that entirely.
$runId      = [guid]::NewGuid().Guid.Substring(0,8)
$tempZip    = Join-Path $env:TEMP "TerminalStyles-$branch-$runId.zip"
$tempDir    = Join-Path $env:TEMP "TerminalStyles-extract-$runId"

$loaderBegin = '# ===== TerminalStyles BEGIN ====='
$loaderEnd   = '# ===== TerminalStyles END ====='
$loaderBody  = @"
$loaderBegin
Import-Module "`$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking
$loaderEnd
"@

# --- Output helpers ---
# Branded banner + step list + bordered "Ready" panel. Pure 7-bit ASCII
# so rendering is identical in any codepage / shell / terminal -- no
# Unicode box-drawing or arrows that might become `?` substitutes on
# WinPS 5.1's CP437 default.

function Write-InstallBanner {
    # Cyan rule + wordmark + tagline + cyan rule.
    $rule = '-' * 52
    Write-Host ''
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host '   tstyles' -ForegroundColor White -NoNewline
    Write-Host '  --  Windows Terminal themes for pwsh' -ForegroundColor DarkGray
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host ''
}

function Write-InstallStep {
    # Single-line step indicator. -Check appends a green [ok] tag to
    # signal completion of an action whose "in progress" version printed
    # on the previous line.
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Check
    )
    Write-Host '  > ' -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -NoNewline
    if ($Check) {
        Write-Host ' [ok]' -ForegroundColor Green
    } else {
        Write-Host ''
    }
}

function Write-InstallPanel {
    # Bordered "Ready" panel listing the count, the one command to run,
    # and all theme names wrapped to fit. ASCII corners (+) + sides (|)
    # + dashes (-) for cross-codepage rendering.
    param(
        [Parameter(Mandatory)][string[]]$ThemeNames,
        [Parameter(Mandatory)][string[]]$RegisteredEngines
    )
    $width = 56   # interior width, between | chars (not counting them)

    # Borders -- both 58 visible chars (1 corner + 56 interior + 1 corner)
    $labelPart = '- Ready '                                  # 8 chars
    $top    = '+' + $labelPart + ('-' * ($width - $labelPart.Length)) + '+'
    $bottom = '+' + ('-' * $width) + '+'

    # Row writer: writes one panel row with the leading '  ' indent,
    # green borders, and middle content padded to exactly $width chars.
    # The middle content is rendered as up to three colored segments.
    function WriteRow {
        param(
            [Parameter(Mandatory)][int]$Width,
            [string[]]$Segments = @(),
            [string[]]$Colors
        )
        Write-Host '  |' -ForegroundColor Green -NoNewline
        $printed = 0
        for ($i = 0; $i -lt $Segments.Count; $i++) {
            $seg = $Segments[$i]
            $color = if ($Colors -and $i -lt $Colors.Count -and $Colors[$i]) { $Colors[$i] } else { $null }
            if ($color) {
                Write-Host $seg -ForegroundColor $color -NoNewline
            } else {
                Write-Host $seg -NoNewline
            }
            $printed += $seg.Length
        }
        if ($printed -lt $Width) {
            Write-Host (' ' * ($Width - $printed)) -NoNewline
        }
        Write-Host '|' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "  $top" -ForegroundColor Green

    # Row: "  N themes installed."
    WriteRow -Width $width -Segments @('  ', "$($ThemeNames.Count) themes installed.")

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Row: "      tstyles" with the command in cyan
    WriteRow -Width $width -Segments @('      ', 'tstyles') -Colors @($null, 'Cyan')

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Theme-name rows: wrap at $width chars. ' * ' separator (ASCII).
    $line = '  '
    foreach ($name in $ThemeNames) {
        $candidate = if ($line.Trim().Length -eq 0) { "$line$name" } else { "$line * $name" }
        if ($candidate.Length -gt $width) {
            WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
            $line = "  $name"
        } else {
            $line = $candidate
        }
    }
    if ($line.Trim().Length -gt 0) {
        WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
    }

    Write-Host "  $bottom" -ForegroundColor Green
    Write-Host ''

    # If both engines were registered, mention the one the user isn't
    # currently in -- they need a new tab for that side.
    if ($RegisteredEngines.Count -gt 1) {
        $current    = $PSVersionTable.PSEdition  # 'Core' for pwsh 7, 'Desktop' for WinPS 5.1
        $otherLabel = if ($current -eq 'Core') { 'Windows PowerShell 5.1' } else { 'PowerShell 7' }
        Write-Host "  Also wired up for $otherLabel -- available in any new tab there." -ForegroundColor DarkGray
        Write-Host ''
    }
}

Write-InstallBanner

# --- Download ---
Write-InstallStep "Downloading"
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
Write-InstallStep "Downloading" -Check

# --- Extract ---
Write-InstallStep "Extracting"
if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
Write-InstallStep "Extracting" -Check

$extractedRoot = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
if (-not $extractedRoot) { throw "Failed to locate extracted folder under $tempDir" }

# --- Install to %LOCALAPPDATA% (preserve current-style.ps1 + cached GIFs across reinstalls) ---
$preservedCurrentStyle = Join-Path $installDir 'current-style.ps1'
$preservedBytes = $null
if (Test-Path -LiteralPath $preservedCurrentStyle) {
    $preservedBytes = [System.IO.File]::ReadAllBytes($preservedCurrentStyle)
}

# Preserve any previously-fetched background images so they don't have to be
# re-downloaded from the gifs branch on every update.
$preservedBackgrounds = @()
$existingStylesDir = Join-Path $installDir 'styles'
if (Test-Path -LiteralPath $existingStylesDir) {
    foreach ($styleFolder in Get-ChildItem -LiteralPath $existingStylesDir -Directory) {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $bg = Join-Path $styleFolder.FullName "background.$ext"
            if (Test-Path -LiteralPath $bg) {
                $preservedBackgrounds += [pscustomobject]@{
                    StyleName = $styleFolder.Name
                    Ext       = $ext
                    Bytes     = [System.IO.File]::ReadAllBytes($bg)
                }
                break  # at most one background per style
            }
        }
    }
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
}
Move-Item -LiteralPath $extractedRoot.FullName -Destination $installDir

if ($preservedBytes) {
    [System.IO.File]::WriteAllBytes((Join-Path $installDir 'current-style.ps1'), $preservedBytes)
    Write-InstallStep "Preserved your active style" -Check
}

if ($preservedBackgrounds) {
    foreach ($p in $preservedBackgrounds) {
        $destDir = Join-Path $installDir "styles\$($p.StyleName)"
        if (Test-Path -LiteralPath $destDir) {
            [System.IO.File]::WriteAllBytes((Join-Path $destDir "background.$($p.Ext)"), $p.Bytes)
        }
    }
    Write-InstallStep ("Preserved {0} cached background(s)" -f $preservedBackgrounds.Count) -Check
}

# Cleanup temp
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# --- Record install SHA for the update checker ---
try {
    # GitHub's API documents User-Agent as required for unauthenticated requests.
    $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" `
                                    -Headers @{ 'User-Agent' = 'TerminalStyles-Installer' } `
                                    -TimeoutSec 5 -ErrorAction Stop
    if ($commitInfo.sha) {
        [System.IO.File]::WriteAllText(
            (Join-Path $installDir '.installed-sha'),
            $commitInfo.sha,
            [System.Text.UTF8Encoding]::new($false))
    }
} catch {
    Write-Host "Note: couldn't record install SHA (network?); update checker will be disabled." -ForegroundColor DarkGray
}

# --- Helper: get a shell's $PROFILE + execution policy in ONE launch ---
# Each shell launch (pwsh.exe / powershell.exe) costs ~500ms on cold start.
# We previously launched each shell twice (once for $PROFILE, once for
# Get-ExecutionPolicy). Combining cuts ~1s off install on dual-shell systems.
function Get-ShellInfo {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Label)
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "  $Label not detected on PATH, skipping." -ForegroundColor DarkGray
        return $null
    }
    # Marker-separated output keeps parsing simple across both engines.
    $out = & $cmd.Source -NoProfile -NonInteractive -Command "Write-Output ('PROFILE='+`$PROFILE); Write-Output ('POLICY='+(Get-ExecutionPolicy))" 2>$null
    $profilePath = $null
    $policy = $null
    foreach ($line in @($out)) {
        $s = "$line".Trim()
        if ($s.StartsWith('PROFILE=')) { $profilePath = $s.Substring(8) }
        elseif ($s.StartsWith('POLICY=')) { $policy = $s.Substring(7) }
    }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-Host "  Could not determine $Label profile path, skipping." -ForegroundColor Yellow
        return $null
    }
    return [pscustomobject]@{
        ProfilePath = $profilePath
        Policy      = $policy
    }
}

# --- Helper: write the loader block into a profile, migrating bundled-style content if matched ---
function Register-LoaderInProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$LoaderBegin,
        [Parameter(Mandatory)][string]$LoaderEnd,
        [Parameter(Mandatory)][string]$LoaderBody
    )

    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    # UTF-8 explicit (WinPS 5.1's Get-Content -Raw defaults to ANSI codepage).
    $existing = if (Test-Path -LiteralPath $ProfilePath) {
        [System.IO.File]::ReadAllText($ProfilePath, [System.Text.UTF8Encoding]::new($false))
    } else { '' }

    if ($existing.Trim().Length -gt 0) {
        $styleDirs = Get-ChildItem -LiteralPath (Join-Path $InstallDir 'styles') -Directory
        foreach ($s in $styleDirs) {
            $sp = Join-Path $s.FullName 'profile.ps1'
            if (Test-Path -LiteralPath $sp) {
                $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
                if ($styleContent.TrimEnd() -eq $existing.TrimEnd()) {
                    $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Copy-Item -LiteralPath $ProfilePath -Destination $bak -Force
                    Write-Host "  Detected '$($s.Name)' style in $Label profile -- migrating into TerminalStyles." -ForegroundColor Yellow
                    Write-Host "  Original profile backed up to: $bak" -ForegroundColor Gray
                    Copy-Item -LiteralPath $sp -Destination (Join-Path $InstallDir 'current-style.ps1') -Force
                    $existing = ''
                    break
                }
            }
        }
    }

    $escBegin = [regex]::Escape($LoaderBegin)
    $escEnd   = [regex]::Escape($LoaderEnd)
    $blockPattern = "(?ms)$escBegin.*?$escEnd\r?\n?"
    if ($existing -match $blockPattern) {
        $existing = [regex]::Replace($existing, $blockPattern, '')
    }

    $final = ($existing.TrimEnd() + "`r`n`r`n" + $LoaderBody + "`r`n").TrimStart()
    [System.IO.File]::WriteAllText($ProfilePath, $final, [System.Text.UTF8Encoding]::new($false))
}

# --- Helper: offer to fix Restricted/AllSigned execution policy for an engine ---
# Takes the already-queried policy value to avoid a second shell launch.
function Resolve-ExecutionPolicy {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string]$Label,
        [string]$EffectivePolicy
    )
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) { return }

    if ([string]::IsNullOrWhiteSpace($EffectivePolicy)) { return }
    $eff = $EffectivePolicy.Trim()

    if ($eff -notin @('Restricted', 'AllSigned')) { return }

    Write-Host ""
    Write-Host "  ! Script execution is disabled for $Label (effective policy: $eff)." -ForegroundColor Yellow
    Write-Host "    Without changing this, the TerminalStyles loader cannot run on shell startup." -ForegroundColor Yellow
    $ans = Read-Host "    Set CurrentUser policy to RemoteSigned for $Label? [Y/n]"
    if (-not ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(?i)y')) {
        Write-Host "    Skipped. To fix later, run in ${Label}:" -ForegroundColor DarkGray
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        return
    }

    try {
        & $cmd.Source -NoProfile -NonInteractive -Command 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force'
        Write-Host "    Done. CurrentUser policy is now RemoteSigned for $Label." -ForegroundColor Green
    } catch {
        Write-Host "    Could not set policy automatically: $_" -ForegroundColor Red
        Write-Host "    A machine-wide policy (LocalMachine / GPO) may be blocking CurrentUser overrides." -ForegroundColor Yellow
        Write-Host "    Run this manually, elevated if needed:" -ForegroundColor Yellow
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
    }
}

# --- Register loader in every detected shell ---
$shells = @(
    @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
    @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
)

$registered = @()
foreach ($s in $shells) {
    $info = Get-ShellInfo -Exe $s.Exe -Label $s.Label
    if (-not $info) { continue }
    Register-LoaderInProfile -ProfilePath $info.ProfilePath -Label $s.Label -InstallDir $installDir `
        -LoaderBegin $loaderBegin -LoaderEnd $loaderEnd -LoaderBody $loaderBody
    Resolve-ExecutionPolicy -Exe $s.Exe -Label $s.Label -EffectivePolicy $info.Policy
    Write-InstallStep "Registered loader: $($s.Label)" -Check
    $registered += $s.Label
}

if (-not $registered) {
    throw "Neither pwsh.exe nor powershell.exe was found on PATH. Cannot register TerminalStyles loader."
}

# Gather the bundled theme names for the "Ready" panel
$themeNames = @(
    Get-ChildItem -LiteralPath (Join-Path $installDir 'styles') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
        Sort-Object Name |
        ForEach-Object Name
)

Write-InstallPanel -ThemeNames $themeNames -RegisteredEngines $registered

# --- Same-tab handoff ---
# Import the freshly-installed module into the GLOBAL scope (not the
# script's child scope) so the `tstyles` command is available in the
# caller's session immediately. Without -Global, the import would be
# scoped to this script and disappear when install.ps1 returns.
$installedManifest = Join-Path $installDir 'TerminalStyles.psd1'
if (Test-Path -LiteralPath $installedManifest) {
    Import-Module $installedManifest -Force -Global -DisableNameChecking *> $null
}
