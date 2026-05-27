# PSGallery First Publish — Design (Sub-project B)

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Part of:** PowerShell Gallery migration (sub-project B of A/B/C)
**Builds on:** [Sub-project A: TerminalStyles as a PowerShell module](2026-05-27-module-restructure-design.md)

## Problem

Sub-project A turned the repo into a valid PowerShell module (`TerminalStyles.psd1` + `.psm1`, both shipped on `origin/main`). The next step toward `Install-PSResource -Name TerminalStyles` is actually publishing version `0.1.0` to the PowerShell Gallery.

The user explicitly opted out of GitHub Actions auto-publish in favor of **manual local publish**. So Sub-project B is:

1. A small staging-and-publish script (`scripts/publish.ps1`) that copies a controlled allowlist of files into `out/TerminalStyles/` and runs `Publish-PSResource`.
2. A one-page maintainer-facing release procedure (`docs/RELEASING.md`).
3. The first manual publish of `TerminalStyles 0.1.0`, executed by the maintainer (user) after this spec ships.
4. Verification from a clean shell that the published module installs and the `tstyles` command works.

## Goals

- A single `scripts/publish.ps1` invocation publishes the module to PSGallery.
- The published package contains only the files end-users need (manifest, entry, library, themes, README, LICENSE, etc.) — NOT the dev artifacts (`docs/`, `tests/`, `.github/`, `install.ps1`).
- The API key is never written to disk in plaintext (no env var, no PSReadLine history, no committed file).
- The publish script is repeatable: every future release follows the same procedure.
- A maintainer-facing `RELEASING.md` documents the procedure so future-you doesn't have to reverse-engineer it.

## Non-goals

- **GitHub Actions auto-publish.** Explicitly out per user choice; could be a future Sub-project D if manual publishing becomes annoying.
- **State-file relocation** (`.installed-sha`, `.last-update-check`, `current-style.ps1`, cached `background.<ext>` → per-user data dir instead of `$PSScriptRoot`). Deferred to Sub-project C, where it travels with the user-facing migration UX. The published `0.1.0` will technically lose state files on version upgrade — acceptable because we don't tell any user to install via PSGallery yet (the README still says `iwr | iex`).
- **README install-command rewrite.** The user-facing install instructions still say `iwr | iex` until Sub-project C lands. The PSGallery listing exists but isn't the documented install path.
- **`tstyles update` switching to `Update-PSResource`.** Sub-project C.
- **Module signing.** Not required by PSGallery for `Publish-PSResource`. Could be added later if desired; out of scope.
- **Versioning automation.** The maintainer manually bumps `ModuleVersion` in `TerminalStyles.psd1` before each release. No auto-versioning from git tags, no `semantic-release`-style tooling.
- **Pre-publish smoke tests in CI.** The existing Pester suite already runs on every push (43 tests against the module structure). Sub-project B does not add anything beyond what CI does.

## Architecture

Three files added at the repo root and under `scripts/` and `docs/`. No production code changes (nothing in `tstyles.ps1`, the manifest, `.psm1`, `install.ps1`, the picker, or any test).

```
scripts/publish.ps1   (NEW) — stage allowlist → run Publish-PSResource
docs/RELEASING.md     (NEW) — 1-page maintainer procedure
.gitignore            (MODIFIED) — append `out/` so the stage dir isn't committed
```

### Publish flow

```
   maintainer runs: pwsh -File .\scripts\publish.ps1
            │
            ▼
   prompt for API key (Read-Host -AsSecureString; input hidden, no history)
            │
            ▼
   stage allowlist into out/TerminalStyles/ (clean rebuild on every run)
            │
            ▼
   Test-ModuleManifest against the staged copy (catches manifest issues
   before they hit PSGallery's stricter validation)
            │
            ▼
   Publish-PSResource -Path out/TerminalStyles -ApiKey <key> -Repository PSGallery
            │
            ▼
   PSGallery processes upload (~30s)
            │
            ▼
   maintainer verifies: Find-PSResource -Name TerminalStyles → version 0.1.0
   maintainer verifies: Install-PSResource (from a clean shell) → picker works
```

## File-by-file changes

### `scripts/publish.ps1` (NEW)

```powershell
# scripts/publish.ps1
#
# Stages the TerminalStyles module from the repo + publishes to PSGallery.
# Run from any pwsh; prompts for the API key (input hidden, never written
# to history or env). See docs/RELEASING.md for the full release procedure.

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ApiKey,                       # optional; prompts if not supplied
    [string]$Repository = 'PSGallery'
)
$ErrorActionPreference = 'Stop'

# --- 1. Resolve the API key ---
if (-not $ApiKey) {
    $secure = Read-Host "PSGallery API key (input hidden)" -AsSecureString
    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if (-not $ApiKey) { throw "No API key provided." }
}

# --- 2. Stage the allowlist into out/TerminalStyles/ ---
$repoRoot  = Split-Path $PSScriptRoot -Parent
$stageRoot = Join-Path $repoRoot 'out\TerminalStyles'

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

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
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
}

# --- 3. Sanity-check the staged manifest before uploading ---
# Test-ModuleManifest validates the .psd1 syntax + that RootModule resolves.
# Better to fail here than have PSGallery reject after upload.
$null = Test-ModuleManifest (Join-Path $stageRoot 'TerminalStyles.psd1')

# --- 4. Publish ---
$manifest = Test-ModuleManifest (Join-Path $stageRoot 'TerminalStyles.psd1')
Write-Host ""
Write-Host "Staged TerminalStyles $($manifest.Version) at:" -ForegroundColor Cyan
Write-Host "  $stageRoot" -ForegroundColor Gray
Write-Host ""

if ($PSCmdlet.ShouldProcess($stageRoot, "Publish-PSResource to $Repository")) {
    Publish-PSResource -Path $stageRoot -ApiKey $ApiKey -Repository $Repository
    Write-Host ""
    Write-Host "Published TerminalStyles $($manifest.Version) to $Repository." -ForegroundColor Green
    Write-Host "Verify at: https://www.powershellgallery.com/packages/TerminalStyles/$($manifest.Version)" -ForegroundColor Gray
}
```

Implementation notes:

- **`SupportsShouldProcess` + `-WhatIf`.** Standard PowerShell pattern for "show me what would happen without doing it." Run `pwsh -File .\scripts\publish.ps1 -WhatIf` to stage + manifest-check without uploading.
- **Allowlist over denylist.** Explicit list of files that ship is safer than "exclude these" — a new top-level dev file added later won't accidentally leak into the package.
- **`Copy-Item -Recurse`** handles the `styles/` directory tree.
- **`scripts\capture-screenshots.ps1`** is shipped because users authoring custom themes (per the README's "Adding your own style" section) need it. `scripts\publish.ps1` itself is NOT shipped (it's only useful to the maintainer).
- **`Test-ModuleManifest` runs on the staged copy** specifically, not the repo root. Catches problems where the stage dir has a missing file the manifest references.
- **Hidden-input prompt** uses `Read-Host -AsSecureString` then immediate marshal to plaintext. The key only exists in the script's local scope; goes out of scope on script exit.

### `docs/RELEASING.md` (NEW)

```markdown
# Releasing TerminalStyles to the PowerShell Gallery

How to publish a new version of TerminalStyles.

## Preflight

1. Make sure `main` is clean and pushed.
2. Run the local Pester suite — should be all green:

   ```powershell
   Invoke-Pester -Path .\tests
   ```

3. Make sure you have your PSGallery API key handy. (Generate at
   https://www.powershellgallery.com/account/apikeys with scope
   "Push new packages and package versions" + glob `TerminalStyles`.)

## Release

1. **Bump `ModuleVersion`** in `TerminalStyles.psd1`. SemVer; bump patch
   for fixes (`0.1.0 → 0.1.1`), minor for new themes/features
   (`0.1.0 → 0.2.0`), major for breaking changes (`0.x → 1.0`).

2. **Update `PrivateData.PSData.ReleaseNotes`** in `TerminalStyles.psd1`
   with a 1-3 line summary of what's in this release. PSGallery shows
   this on the version's page.

3. **Commit the version bump.**

   ```powershell
   git add TerminalStyles.psd1
   git commit -m "Bump version to <new-version>"
   git push origin main
   ```

4. **Run the publish script.** It prompts for your API key
   (input hidden, never written to disk).

   ```powershell
   pwsh -File .\scripts\publish.ps1
   ```

   To dry-run first (stage + manifest-check, no upload):

   ```powershell
   pwsh -File .\scripts\publish.ps1 -WhatIf
   ```

5. **Tag the release** for traceability.

   ```powershell
   git tag v<new-version>
   git push --tags
   ```

6. **Verify** within ~1 minute at
   https://www.powershellgallery.com/packages/TerminalStyles/

7. **Smoke-test the install** in a clean shell (no module
   already loaded):

   ```powershell
   pwsh -NoProfile -Command "Install-PSResource -Name TerminalStyles -Scope CurrentUser; Import-Module TerminalStyles; Get-Command -Module TerminalStyles | Format-Table"
   ```

   Expected: `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`,
   `tstyles` all show up under `Module TerminalStyles`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Publish-PSResource` rejects with "A package with this version already exists" | You re-ran the publish for an unchanged `ModuleVersion`. PSGallery versions are immutable. | Bump the version and retry. |
| `Test-ModuleManifest` fails before publish | Manifest references a file the allowlist doesn't stage. | Add the file to `$allowlist` in `scripts/publish.ps1`, OR remove the manifest reference. |
| `Install-PSResource` works but `Import-Module` fails with "Apply-StyleDirect is not approved" | `-DisableNameChecking` is missing from the consumer's import. | Tell them to use `Import-Module TerminalStyles -DisableNameChecking`. Long-term fix: rename the function (future spec). |
| Module installs but `current-style.ps1` is missing after version upgrade | Known limitation — state files live in `$PSScriptRoot` which is per-version. | Will be fixed in Sub-project C. For now, end-users still install via `iwr \| iex` per the README. |

## What gets published

The `scripts/publish.ps1` allowlist controls what ships. Currently:

- `TerminalStyles.psd1`, `TerminalStyles.psm1`
- `tstyles.ps1`, `apply.ps1`
- `styles/` (all 16 themes)
- `README.md`, `LICENSE`
- `scripts/capture-screenshots.ps1`

Intentionally excluded: `docs/`, `tests/`, `.github/`, `install.ps1`,
runtime state files, the publish script itself.

## Quick reference

```powershell
# Dry run
pwsh -File .\scripts\publish.ps1 -WhatIf

# Publish
pwsh -File .\scripts\publish.ps1

# Verify after publish
Find-PSResource -Name TerminalStyles -Repository PSGallery
```
```

### `.gitignore` (MODIFIED)

Append the staging dir so accidental `git add .` doesn't commit `out/`:

```
# Append at the end of the existing .gitignore (or create if missing):
out/
```

### Production code

**No changes.** `TerminalStyles.psd1`, `TerminalStyles.psm1`, `tstyles.ps1`, `install.ps1`, `apply.ps1`, the picker, the tests — all untouched.

## Data flow (first publish, end-to-end)

1. Maintainer (user) confirms `main` is clean. Pester suite passes locally.
2. `TerminalStyles.psd1`'s `ModuleVersion` is already `0.1.0` (set in Sub-project A); no bump needed for the first release.
3. Maintainer runs `pwsh -File .\scripts\publish.ps1 -WhatIf`:
   - Script prompts for API key (input hidden).
   - Stages files into `out/TerminalStyles/`.
   - Runs `Test-ModuleManifest` on the staged copy → passes.
   - Reports the staged version + path; does NOT call `Publish-PSResource` because `-WhatIf` was passed.
   - Maintainer eyeballs the stage dir and confirms it has only the allowlist contents.
4. Maintainer runs `pwsh -File .\scripts\publish.ps1` (no `-WhatIf`):
   - Same staging, same manifest check, then `Publish-PSResource` fires.
   - PSGallery accepts the upload and processes it (~30s).
5. Maintainer waits ~1 minute, then runs verification:
   - `Find-PSResource -Name TerminalStyles -Repository PSGallery` shows `0.1.0`.
   - From a different pwsh tab (or with `-NoProfile` to bypass any local TerminalStyles install):
     ```
     Install-PSResource -Name TerminalStyles -Scope CurrentUser
     Import-Module TerminalStyles
     Get-Command -Module TerminalStyles
     tstyles list
     ```
   - All commands resolve. `tstyles list` prints the 16 themes.
6. Maintainer commits the new `scripts/publish.ps1`, `docs/RELEASING.md`, and `.gitignore` change. Pushes to `main`. Tags `v0.1.0` and pushes the tag.

## Error handling

| Failure | Behavior |
|---|---|
| API key missing (no prompt response, no `-ApiKey` arg) | Script throws `"No API key provided."` clearly. |
| Allowlist item missing from the repo | Script throws `"Allowlist item missing from repo: <name>"`. Catches typos. |
| `Test-ModuleManifest` fails on staged copy | Script throws with `Test-ModuleManifest`'s error message. Usually a `RootModule` reference issue. |
| `Publish-PSResource` rejects (version exists, API key invalid, network down) | Script propagates the exception. Maintainer reads the error, bumps the version or retries. |
| `out/` exists from a prior run | Removed and rebuilt cleanly on each invocation. |
| `out/` accidentally committed | Caught by the `.gitignore` update. If somehow committed pre-fix, remove and add to git history with `git rm -r --cached out/`. |
| Allowlist item is a symlink | `Copy-Item -Recurse` copies the link target's contents by default. Acceptable; no symlinks expected in the allowlist. |
| API key leaks via process inspection | Script's lifetime is seconds. Mitigation is limited; key already lives in the maintainer's local environment. Rotate the key via PSGallery if you suspect leakage. |

## Testing

Manual (no automated tests for the publish script — it's a one-shot tool):

- **Dry-run produces correct staging.** Run `-WhatIf`, then `Get-ChildItem -Recurse out/TerminalStyles/` should show:
  - 8 top-level items (manifest, .psm1, tstyles.ps1, apply.ps1, README.md, LICENSE, styles/, scripts/)
  - `styles/` containing 16 theme folders, each with at least `scheme.json` (plus optional `theme.json`, `profile.ps1`, `README.md`).
  - `scripts/` containing only `capture-screenshots.ps1` (NOT `publish.ps1`).
  - No `docs/`, `tests/`, `.github/`, `install.ps1`, `current-style.ps1`, `.installed-sha`, `.last-update-check`, `.gitignore`.

- **First publish.** Real `Publish-PSResource` call. Verify on PSGallery.

- **Install round-trip.** From a clean shell, install + import + tstyles list. Picker should launch.

- **Re-publish rejection.** Run the publish script again immediately (without bumping the version). Confirm `Publish-PSResource` rejects with the "version already exists" message — this verifies the safety against accidental re-publishes.

## Known limitations

- **State files break on version upgrade.** Carrying into Sub-project C. The published `0.1.0` writes `.installed-sha` / `.last-update-check` / `current-style.ps1` / cached backgrounds to `$PSScriptRoot` which is per-version. Upgrading to `0.1.1` (when it ships) loses all of those. Mitigation: don't publicize the PSGallery listing until Sub-project C ships the relocation.
- **Manual versioning.** Maintainer must remember to bump `ModuleVersion` before each release. If forgotten, the second run of `publish.ps1` produces a confusing "version already exists" rejection (rather than a clear "you forgot to bump"). Acceptable; the error message is recognizable enough.
- **No tag automation.** Maintainer must remember to `git tag` after publishing. If forgotten, the GitHub repo and the PSGallery package can drift in version. Documented in `RELEASING.md`; not auto-enforced.
- **API key handling is process-local.** The key only exists for the script's lifetime (a few seconds). Process-inspection-level attacks during those seconds are possible but vanishingly likely on a single-user dev machine.
- **`Apply-StyleDirect` non-approved-verb warning** still fires for module consumers who import without `-DisableNameChecking`. Same as Sub-project A's known limitation. Future spec renames it.
- **No PSGallery readme rendering preview.** PSGallery renders the shipped README.md on the package page. We don't render-test it locally before publish; if Markdown breaks on the PSGallery renderer, we find out after publish. Mitigation: PSGallery's renderer is generic Markdown; the existing README renders fine on GitHub.
