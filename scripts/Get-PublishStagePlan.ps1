# scripts/Get-PublishStagePlan.ps1
#
# Pure planning helper for scripts/publish.ps1: turns the publish allowlist
# into the exact list of repo-relative files to stage.
#
# Why this exists: a normal checkout carries gitignored runtime cache inside
# allowlisted directories -- styles/*/background.* (lazy-fetched from the gifs
# branch, ~MBs each) and styles/*/.no-background markers. Copying the styles/
# tree wholesale swept those into the PSGallery package, so the published
# artifact depended on which themes the release machine had previewed. Driving
# the copy from `git ls-files` makes the package exactly the committed tree,
# and identical on every machine.
#
# Dot-sourced by publish.ps1 and by tests/Get-PublishStagePlan.Tests.ps1.

function Get-PublishStagePlan {
    <#
    .SYNOPSIS
    Resolve an allowlist to the git-tracked files it covers.

    .OUTPUTS
    Repo-relative paths, forward-slashed (git's own form), in allowlist order
    and de-duplicated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Allowlist
    )

    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        throw "Not a git checkout: $RepoRoot -- publish stages from git-tracked files only."
    }

    $plan = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $Allowlist) {
        # git pathspecs are forward-slashed; the allowlist uses Windows separators.
        $pathspec = $item -replace '\\', '/'

        # stderr -> $null, then judge by exit code: on Windows PowerShell 5.1 any
        # stderr text from a native command becomes a terminating error under
        # $ErrorActionPreference = 'Stop' (which publish.ps1 sets), and git is
        # happy to warn on stderr while succeeding.
        $tracked = @(& git -C $RepoRoot ls-files --full-name -- $pathspec 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "git ls-files failed for allowlist item: $item"
        }
        # Drop the empty trailing element git can emit, and normalise.
        $tracked = @($tracked | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })

        if ($tracked.Count -eq 0) {
            $onDisk = Test-Path -LiteralPath (Join-Path $RepoRoot $item)
            if ($onDisk) {
                throw "Allowlist item is not tracked by git (commit it before publishing): $item"
            }
            throw "Allowlist item missing from repo: $item"
        }

        # A directory entry that resolves to SOMETHING passes the check above even
        # when a file inside it is uncommitted -- git ls-files simply cannot see
        # it, so it left the package silently. That is the exact failure the
        # directory entries exist to prevent: lib/*.ps1 is dot-sourced by
        # enumeration, so a forgotten `git add` ships a module that imports fine
        # and then fails at first use with "Show-StyleList is not recognized".
        #
        # --others --exclude-standard is untracked-and-NOT-ignored, which is the
        # distinction that matters: gitignored runtime cache inside styles/
        # (background.*, .no-background) must still be skipped in silence -- that
        # is what this helper is for.
        $stray = @(& git -C $RepoRoot ls-files --others --exclude-standard -- $pathspec 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "git ls-files --others failed for allowlist item: $item"
        }
        $stray = @($stray | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
        if ($stray.Count -gt 0) {
            throw ("Untracked file(s) under allowlist item '$item' would be dropped from the " +
                   "package (commit them, or add them to .gitignore): " + ($stray -join ', '))
        }

        foreach ($path in $tracked) {
            if ($seen.Add($path)) { $plan.Add($path) }
        }
    }

    # Unary comma: keep a one-file plan an array instead of letting PowerShell
    # unwrap it to a bare string (symmetric return, as elsewhere in this repo).
    return ,$plan.ToArray()
}
