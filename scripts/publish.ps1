# scripts/publish.ps1
#
# Stages the TerminalStyles module from the repo + publishes to PSGallery.
# Run from any pwsh; prompts for the API key (input hidden, never written
# to history or env). See docs/RELEASING.md for the full release procedure.

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ApiKey,                       # optional; prompts if not supplied and not -WhatIf
    [string]$Repository = 'PSGallery'
)
$ErrorActionPreference = 'Stop'

# --- 1. Stage the allowlist into out/TerminalStyles/ ---
$repoRoot  = Split-Path $PSScriptRoot -Parent
$stageRoot = Join-Path $repoRoot 'out\TerminalStyles'

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -WhatIf:$false
}
New-Item -ItemType Directory -Path $stageRoot -Force -WhatIf:$false | Out-Null

# Allowlist: every item here must exist in the repo root (relative path).
# Excluded by definition: docs/, tests/, .github/, install.ps1, .git/,
# .gitignore, out/ itself, any runtime state files.
$allowlist = @(
    'TerminalStyles.psd1',
    'TerminalStyles.psm1',
    'tstyles.ps1',
    'apply.ps1',
    'README.md',
    'LICENSE',
    'fonts.json',
    'styles',                              # whole tree, 16 themes
    'scripts\capture-screenshots.ps1'      # useful for theme authors
)

foreach ($item in $allowlist) {
    $src = Join-Path $repoRoot $item
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Allowlist item missing from repo: $item"
    }
    # Preserve the relative structure (e.g. scripts\capture-screenshots.ps1
    # lands under scripts\ inside the stage dir).
    $dest = Join-Path $stageRoot $item
    $destDir = Split-Path -Parent $dest
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force -WhatIf:$false | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force -WhatIf:$false
}

# --- 2. Sanity-check the staged manifest BEFORE asking for the key ---
# Better to fail here than have PSGallery reject after upload. This also
# lets -WhatIf runs (which never prompt for a key) catch manifest issues.
$manifest = Test-ModuleManifest (Join-Path $stageRoot 'TerminalStyles.psd1')

Write-Host ''
Write-Host "Staged TerminalStyles $($manifest.Version) at:" -ForegroundColor Cyan
Write-Host "  $stageRoot" -ForegroundColor Gray
Write-Host ''

# --- 3. If -WhatIf, stop here ---
# ShouldProcess returns $false under -WhatIf, which prints the standard
# "What if: Performing the operation..." line and short-circuits.
if (-not $PSCmdlet.ShouldProcess($stageRoot, "Publish-PSResource to $Repository")) {
    return
}

# --- 4. Resolve the API key (prompt if not provided) ---
if (-not $ApiKey) {
    $secure = Read-Host "PSGallery API key (input hidden)" -AsSecureString
    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if (-not $ApiKey) { throw "No API key provided." }
}

# --- 5. Publish ---
Publish-PSResource -Path $stageRoot -ApiKey $ApiKey -Repository $Repository

Write-Host ''
Write-Host "Published TerminalStyles $($manifest.Version) to $Repository." -ForegroundColor Green
Write-Host "Verify at: https://www.powershellgallery.com/packages/TerminalStyles/$($manifest.Version)" -ForegroundColor Gray
