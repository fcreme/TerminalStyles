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

$ErrorActionPreference = 'Stop'

$repo       = 'fcreme/TerminalStyles'
$branch     = 'main'
$installDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
$zipUrl     = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$tempZip    = Join-Path $env:TEMP "TerminalStyles-$branch.zip"
$tempDir    = Join-Path $env:TEMP "TerminalStyles-extract-$([guid]::NewGuid().Guid.Substring(0,8))"

$loaderBegin = '# ===== TerminalStyles BEGIN ====='
$loaderEnd   = '# ===== TerminalStyles END ====='
$loaderBody  = @"
$loaderBegin
. "`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"
$loaderEnd
"@

Write-Host ""
Write-Host "TerminalStyles installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

# --- Download ---
Write-Host "Downloading from $zipUrl ..."
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

# --- Extract ---
Write-Host "Extracting ..."
if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

$extractedRoot = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
if (-not $extractedRoot) { throw "Failed to locate extracted folder under $tempDir" }

# --- Install to %LOCALAPPDATA% (preserve current-style.ps1 across reinstalls) ---
$preservedCurrentStyle = Join-Path $installDir 'current-style.ps1'
$preservedBytes = $null
if (Test-Path -LiteralPath $preservedCurrentStyle) {
    $preservedBytes = [System.IO.File]::ReadAllBytes($preservedCurrentStyle)
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
}
Move-Item -LiteralPath $extractedRoot.FullName -Destination $installDir

if ($preservedBytes) {
    [System.IO.File]::WriteAllBytes((Join-Path $installDir 'current-style.ps1'), $preservedBytes)
    Write-Host "Preserved your existing style selection."
}

# Cleanup temp
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Files installed at: $installDir" -ForegroundColor Green

# --- Helper: get a shell's $PROFILE path by invoking that engine directly ---
function Get-ShellProfilePath {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Label)
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "  $Label not detected on PATH, skipping." -ForegroundColor DarkGray
        return $null
    }
    $p = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
    if ([string]::IsNullOrWhiteSpace($p)) {
        Write-Host "  Could not determine $Label profile path, skipping." -ForegroundColor Yellow
        return $null
    }
    return $p.Trim()
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

    $existing = if (Test-Path -LiteralPath $ProfilePath) {
        Get-Content -LiteralPath $ProfilePath -Raw
    } else { '' }

    if ($existing.Trim().Length -gt 0) {
        $styleDirs = Get-ChildItem -LiteralPath (Join-Path $InstallDir 'styles') -Directory
        foreach ($s in $styleDirs) {
            $sp = Join-Path $s.FullName 'profile.ps1'
            if (Test-Path -LiteralPath $sp) {
                $styleContent = Get-Content -LiteralPath $sp -Raw
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

    Write-Host "  Loader registered in: $ProfilePath" -ForegroundColor Green
}

# --- Helper: detect Restricted/AllSigned execution policy for an engine and offer to fix ---
function Resolve-ExecutionPolicy {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Label)
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) { return }

    $eff = & $cmd.Source -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' 2>$null
    if ([string]::IsNullOrWhiteSpace($eff)) { return }
    $eff = $eff.Trim()

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
    Write-Host ""
    Write-Host "[$($s.Label)]" -ForegroundColor Cyan
    $p = Get-ShellProfilePath -Exe $s.Exe -Label $s.Label
    if (-not $p) { continue }
    Register-LoaderInProfile -ProfilePath $p -Label $s.Label -InstallDir $installDir `
        -LoaderBegin $loaderBegin -LoaderEnd $loaderEnd -LoaderBody $loaderBody
    Resolve-ExecutionPolicy -Exe $s.Exe -Label $s.Label
    $registered += $s.Label
}

if (-not $registered) {
    throw "Neither pwsh.exe nor powershell.exe was found on PATH. Cannot register TerminalStyles loader."
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  Registered for: $($registered -join ', ')"
Write-Host "  1. Open a new tab in one of those shells (or run: . `$PROFILE)"
Write-Host "  2. Run:  tstyles"
Write-Host "     -> Arrow keys to preview each style live, Enter to keep, Esc to cancel."
Write-Host ""
