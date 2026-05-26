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

#Requires -Version 7

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

# --- Register loader in $PROFILE ---
$profilePath = $PROFILE
$profileDir  = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$existing = if (Test-Path -LiteralPath $profilePath) {
    Get-Content -LiteralPath $profilePath -Raw
} else { '' }

# --- Migrate: does the existing $PROFILE exactly match a bundled style? ---
$migrated = $false
if ($existing.Trim().Length -gt 0) {
    $styleDirs = Get-ChildItem -LiteralPath (Join-Path $installDir 'styles') -Directory
    foreach ($s in $styleDirs) {
        $sp = Join-Path $s.FullName 'profile.ps1'
        if (Test-Path -LiteralPath $sp) {
            $styleContent = Get-Content -LiteralPath $sp -Raw
            if ($styleContent.TrimEnd() -eq $existing.TrimEnd()) {
                # Back up just in case
                $bak = "$profilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -LiteralPath $profilePath -Destination $bak -Force
                Write-Host "Detected '$($s.Name)' style in your `$PROFILE -- migrating it into TerminalStyles." -ForegroundColor Yellow
                Write-Host "Original profile backed up to: $bak" -ForegroundColor Gray

                Copy-Item -LiteralPath $sp -Destination (Join-Path $installDir 'current-style.ps1') -Force
                $existing = ''  # We'll rewrite $PROFILE with just the loader
                $migrated = $true
                break
            }
        }
    }
}

# --- Add / replace the loader block ---
$escBegin = [regex]::Escape($loaderBegin)
$escEnd   = [regex]::Escape($loaderEnd)
$blockPattern = "(?ms)$escBegin.*?$escEnd\r?\n?"

if ($existing -match $blockPattern) {
    $existing = [regex]::Replace($existing, $blockPattern, '')
}

$final = ($existing.TrimEnd() + "`r`n`r`n" + $loaderBody + "`r`n").TrimStart()
[System.IO.File]::WriteAllText($profilePath, $final, [System.Text.UTF8Encoding]::new($false))

Write-Host "Registered loader in: $profilePath" -ForegroundColor Green

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  1. Open a new pwsh tab (or run: . `$PROFILE)"
Write-Host "  2. Run:  tstyles"
Write-Host "     -> Arrow keys to preview each style live, Enter to keep, Esc to cancel."
Write-Host ""
