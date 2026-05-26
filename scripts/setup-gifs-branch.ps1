# One-off helper to set up the `gifs` branch for TerminalStyles.
#
# What it does:
#   1. Snapshots the current styles/<name>/background.* files
#   2. Creates an orphan `gifs` branch
#   3. Writes the GIFs at the gifs branch root with flat naming
#      (umbrella.gif, eva.gif, ex-machina.gif, sober.png, etc.)
#   4. Commits the gifs branch (does NOT push automatically)
#   5. Returns to main and removes the GIFs from there (staged but not committed)
#
# After it finishes:
#   1. Review the `gifs` branch:    git checkout gifs ; git log -1 --stat
#   2. Push it:                     git push -u origin gifs
#   3. Switch back to main:         git checkout main
#   4. Review the deletions:        git status
#   5. Commit + push main with the GIFs gone + the new lazy-fetch code:
#      git commit -am "Move bundled GIFs to the gifs branch; main is now code-only"
#      git push
#
# Idempotent: safe to re-run if it bails partway through (it'll fast-path
# the snapshot step if the gifs branch already exists).

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "Setting up the gifs branch for TerminalStyles" -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Cyan

# Sanity: are we in a clean main checkout?
Push-Location $repoRoot
try {
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($branch -ne 'main') {
        throw "This script must be run from the 'main' branch (currently on '$branch'). git checkout main first."
    }
    $status = git status --porcelain
    if ($status) {
        throw "Working tree has uncommitted changes. Commit or stash them first:`n$status"
    }

    # --- Step 1: snapshot the current background files ---
    $stylesDir = Join-Path $repoRoot 'styles'
    $snapshot = @()
    foreach ($styleFolder in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $bg = Join-Path $styleFolder.FullName "background.$ext"
            if (Test-Path -LiteralPath $bg) {
                $snapshot += [pscustomobject]@{
                    StyleName = $styleFolder.Name
                    Ext       = $ext
                    Path      = $bg
                    Bytes     = [System.IO.File]::ReadAllBytes($bg)
                }
                break
            }
        }
    }
    if (-not $snapshot) {
        throw "No background.* files found under styles/. Nothing to migrate."
    }
    Write-Host ("Snapshotted {0} background file(s):" -f $snapshot.Count) -ForegroundColor Green
    foreach ($s in $snapshot) {
        Write-Host ("  - {0,-16} background.{1}  ({2:N0} bytes)" -f $s.StyleName, $s.Ext, $s.Bytes.Length)
    }

    # --- Step 2: create / switch to orphan gifs branch ---
    $gifsExists = (git branch --list gifs).Trim()
    if (-not $gifsExists) {
        Write-Host ""
        Write-Host "Creating orphan 'gifs' branch..." -ForegroundColor Cyan
        git checkout --orphan gifs
        # Orphan branch starts with all main files staged. Clear them.
        git rm -rf --quiet . | Out-Null
    } else {
        Write-Host ""
        Write-Host "Reusing existing 'gifs' branch..." -ForegroundColor Yellow
        git checkout gifs
    }

    # --- Step 3: write GIFs at root with flat naming ---
    Write-Host ""
    Write-Host "Writing GIFs at gifs-branch root..." -ForegroundColor Cyan
    foreach ($s in $snapshot) {
        $dst = Join-Path $repoRoot "$($s.StyleName).$($s.Ext)"
        [System.IO.File]::WriteAllBytes($dst, $s.Bytes)
        git add -f -- "$($s.StyleName).$($s.Ext)" | Out-Null
        Write-Host ("  + {0}.{1}" -f $s.StyleName, $s.Ext)
    }

    # Add a tiny README on the gifs branch so anyone landing here knows why
    $gifsReadme = @"
# TerminalStyles -- gifs branch

This branch holds the background images for each style. They live here
instead of on main so the install ZIP stays small (~100 KB instead of
~10 MB). TerminalStyles' tstyles.ps1 lazy-fetches each file on first use
via raw.githubusercontent.com.

Filename convention: ``<style-name>.<ext>`` (e.g., ``umbrella.gif``,
``sober.png``). Extension priority is gif > png > jpg > jpeg.

To add a new style's background:
1. Switch to this branch: ``git checkout gifs``
2. Drop your file at the root: ``cp my-bg.gif <style-name>.gif``
3. Commit + push.

Adding a new style itself (scheme.json / theme.json / profile.ps1) is
done on main; only the binary asset belongs here.
"@
    $gifsReadmePath = Join-Path $repoRoot 'README.md'
    Set-Content -LiteralPath $gifsReadmePath -Value $gifsReadme -Encoding UTF8
    git add -f README.md | Out-Null

    # --- Step 4: commit the gifs branch (do NOT push automatically) ---
    $stagedCount = (git diff --cached --name-only | Measure-Object).Count
    if ($stagedCount -gt 0) {
        git commit -m "Set up gifs branch: bundle the per-style background images at root" | Out-Null
        Write-Host ""
        Write-Host "Committed $stagedCount file(s) to gifs branch (NOT pushed)." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Nothing new to commit on gifs branch." -ForegroundColor Yellow
    }

    # --- Step 5: back to main, remove the GIFs (stage but do not commit) ---
    Write-Host ""
    Write-Host "Returning to main and staging the GIF deletions..." -ForegroundColor Cyan
    git checkout main | Out-Null
    foreach ($s in $snapshot) {
        if (Test-Path -LiteralPath $s.Path) {
            git rm --quiet -- "styles/$($s.StyleName)/background.$($s.Ext)" | Out-Null
        }
    }
    Write-Host "Staged $(($snapshot | Measure-Object).Count) GIF deletion(s) on main (NOT committed)." -ForegroundColor Green

    Write-Host ""
    Write-Host "Done. Next steps (do these manually so you can review):" -ForegroundColor Cyan
    Write-Host "  1. git checkout gifs ; git log -1 --stat        # review the gifs branch" -ForegroundColor Gray
    Write-Host "  2. git push -u origin gifs                       # publish the gifs branch" -ForegroundColor Gray
    Write-Host "  3. git checkout main                             # back to main" -ForegroundColor Gray
    Write-Host "  4. git status                                    # confirm GIFs are staged for deletion" -ForegroundColor Gray
    Write-Host "  5. git commit -m 'Move GIFs to gifs branch; lazy-fetch from main'" -ForegroundColor Gray
    Write-Host "  6. git push                                      # publish main without GIFs" -ForegroundColor Gray
    Write-Host ""
} finally {
    Pop-Location
}
