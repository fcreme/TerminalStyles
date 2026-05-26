# Umbrella Terminal -- installer for the pwsh 7 profile.
# Run from the repo root:    pwsh -File .\install.ps1
#
# What it does:
#   * Copies pwsh\Microsoft.PowerShell_profile.ps1 into your $PROFILE path
#     (backs up the existing profile if one exists)
#
# What it does NOT do (manual steps -- see README):
#   * Add the `umbrella` color scheme to Windows Terminal's settings.json
#   * Override the pwsh profile fields in settings.json
#   * Download a background GIF
#
# These are left manual because editing settings.json programmatically is
# risky -- a bad merge can break your Windows Terminal config.

#Requires -Version 7

$source = Join-Path $PSScriptRoot 'pwsh\Microsoft.PowerShell_profile.ps1'
if (-not (Test-Path -LiteralPath $source)) {
    throw "Could not find $source. Run this script from the repo root."
}

$destDir = Split-Path $PROFILE -Parent
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Write-Host "Created profile directory: $destDir"
}

if (Test-Path -LiteralPath $PROFILE) {
    $backup = "$PROFILE.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $PROFILE -Destination $backup
    Write-Host "Existing profile backed up to: $backup"
}

Copy-Item -LiteralPath $source -Destination $PROFILE -Force
Write-Host ""
Write-Host "Profile installed at: $PROFILE"
Write-Host ""
Write-Host "Next steps (manual):"
Write-Host "  1. Open Windows Terminal -> Settings -> Open JSON file."
Write-Host "  2. Add the contents of windows-terminal\umbrella-scheme.json to the `schemes` array."
Write-Host "  3. Add the fields from windows-terminal\profile-fragment.json to your PowerShell 7"
Write-Host "     profile entry (replace <YOUR_GIF_PATH> or remove the backgroundImage* fields)."
Write-Host "  4. Open a new pwsh tab to see the result."
