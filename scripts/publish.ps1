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

# Allowlist: every item here must exist in the repo root (relative path) AND be
# tracked by git -- the plan below resolves each entry through `git ls-files`, so
# gitignored runtime cache inside an allowlisted directory (styles/*/background.*,
# .no-background markers) never reaches the package.
# Excluded by definition: docs/, tests/, .github/, install.ps1, .git/,
# .gitignore, out/ itself, any runtime state files.
$allowlist = @(
    'TerminalStyles.psd1',
    'TerminalStyles.psm1',
    'tstyles.ps1',
    'terminals.ps1',                       # dot-sourced by tstyles.ps1 -- import fails without it
    'lib',                                 # the rest of the library, also dot-sourced; a
                                           # directory entry so a new lib file needs no
                                           # registration here and cannot be forgotten
    'apply.ps1',
    'README.md',
    'LICENSE',
    'fonts.json',
    'styles',                              # whole tree, 16 themes + their shell prompts
    'shell'                                # zsh/bash runtime + the Terminal.app profile helper
    # NOTE: scripts/ is deliberately NOT shipped. capture-screenshots.ps1 used to
    # be, as "useful for theme authors" -- but it requires $env:WT_SESSION, the
    # bootstrap layout at %LOCALAPPDATA%\TerminalStyles, and a repo checkout to
    # write docs/screenshots into. A PSGallery user has none of those, so it
    # could only ever fail for the people receiving it. Theme authors work from
    # a clone, which is what README and CONTRIBUTING both tell them to do.
)

. (Join-Path $PSScriptRoot 'Get-PublishStagePlan.ps1')
$plan = Get-PublishStagePlan -RepoRoot $repoRoot -Allowlist $allowlist

foreach ($relPath in $plan) {
    # $relPath is forward-slashed and repo-relative; preserve that structure
    # (e.g. scripts/capture-screenshots.ps1 lands under scripts\ in the stage dir).
    $src  = Join-Path $repoRoot $relPath
    $dest = Join-Path $stageRoot $relPath
    $destDir = Split-Path -Parent $dest
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force -WhatIf:$false | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dest -Force -WhatIf:$false
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
    # Refuse before prompting when there is no console. Read-Host
    # -AsSecureString at EOF is worse than the plain form: it does not return an
    # empty SecureString and it does not raise a catchable error -- it stops the
    # pipeline abruptly, so a trap never fires, a try/catch never catches, and
    # the script simply ends. Publishing from CI or any wrapper with stdin
    # detached therefore looked like a silent success: no key, no publish, no
    # error, exit as if done.
    #
    # Inlined rather than calling the module's Test-InteractiveConsole: this is
    # a standalone maintainer script that deliberately does not load
    # TerminalStyles (it stages and publishes the module, so importing the
    # thing under test would be circular). Keep the expression identical to
    # Test-InteractiveConsole in tstyles.ps1.
    $hasConsole = [Environment]::UserInteractive -and
                  -not [Console]::IsInputRedirected -and
                  -not [Console]::IsOutputRedirected
    if (-not $hasConsole) {
        throw "No console to prompt for the PSGallery API key. Pass -ApiKey explicitly when running non-interactively."
    }
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
