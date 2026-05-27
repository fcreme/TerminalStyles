# PSGallery First Publish Implementation Plan (Sub-project B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a manual `scripts/publish.ps1` script that stages an allowlist of files and publishes the TerminalStyles module to PSGallery. Execute the first publish of version `0.1.0`. Verify install from a clean shell.

**Architecture:** Stage-and-publish via a small PowerShell script. Allowlist-based file copy into `out/TerminalStyles/`, then `Publish-PSResource` against the staged dir. API key prompted at runtime via `Read-Host -AsSecureString` (never written to env, history, or disk). Maintainer-facing `docs/RELEASING.md` documents the procedure.

**Tech Stack:** PowerShell 5.1+ for the script body (`Read-Host`, `Copy-Item`, `Test-ModuleManifest`). PowerShell 7+ for the publish itself (`Publish-PSResource` from `Microsoft.PowerShell.PSResourceGet`, preinstalled on pwsh 7.4+). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-psgallery-first-publish-design.md`

---

## File Structure

Three new files; one existing file modified. No production code changes.

- **Create:** `scripts/publish.ps1` — stages files into `out/TerminalStyles/`, runs `Test-ModuleManifest`, runs `Publish-PSResource`. Supports `-WhatIf` for dry-run.
- **Create:** `docs/RELEASING.md` — maintainer-facing one-page release procedure.
- **Modify:** `.gitignore` — append `out/` so the staging dir is never committed.
- **No change:** `TerminalStyles.psd1`, `TerminalStyles.psm1`, `tstyles.ps1`, `install.ps1`, `apply.ps1`, `README.md`, `styles/`, `tests/`, `.github/workflows/test.yml`.

**Task ordering:**

1. **Task 1** creates the publish script + `.gitignore` update. Subagent-friendly: writes code, runs `-WhatIf` (no key needed), commits.
2. **Task 2** creates `docs/RELEASING.md`. Subagent-friendly.
3. **Task 3** pushes the two commits to `origin/main` so they're durable BEFORE the irreversible publish action. Controller-handled (`git push`).
4. **Task 4** executes the first publish (`pwsh -File .\scripts\publish.ps1 -ApiKey '<key>'`). Requires the API key — controller-handled (subagent can't drive an interactive prompt and shouldn't carry the key).
5. **Task 5** verifies the published module installs cleanly from a fresh shell, then tags + pushes the tag. Controller-handled.

---

## Task 1: Create `scripts/publish.ps1` and update `.gitignore`

**Files:**
- Create: `scripts/publish.ps1`
- Modify: `.gitignore` (append `out/`)

After this task, `pwsh -File .\scripts\publish.ps1 -WhatIf` runs end-to-end (stages files, runs `Test-ModuleManifest`) without uploading anything. The staging dir is `.gitignore`'d.

- [ ] **Step 1: Create `scripts/publish.ps1`**

Create `C:\Users\felip\dotfiles\scripts\publish.ps1` with this exact content:

```powershell
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
```

Implementation notes (deviation from spec sketch, intentional improvement):

- **The spec sketched** prompt-first → stage → check → publish. **This refines that** to stage → check → ShouldProcess gate → prompt (only if not WhatIf) → publish. The refinement makes `-WhatIf` runs not require an API key, which is what you actually want when dry-running (you want to verify the stage without typing your secret).
- `SupportsShouldProcess` automatically gives the script `-WhatIf` and `-Confirm` parameters.
- `ShouldProcess` returns `$true` for a real run and `$false` (after printing the WhatIf message) for a dry run.

- [ ] **Step 2: Update `.gitignore` (append `out/`)**

Read the current `.gitignore` to see its existing patterns:

```powershell
pwsh -NoProfile -Command "Get-Content .gitignore"
```

Then append `out/` so the staging dir isn't accidentally committed. If `.gitignore` doesn't end with a blank line, prepend one. Use the Edit tool with `replace_all: false` and an anchor like the file's last existing pattern line.

If `.gitignore` doesn't exist (unlikely — there's already a long one based on past commits), create it with just:

```
out/
```

Verify after edit:

```powershell
pwsh -NoProfile -Command "Get-Content .gitignore | Select-String -Pattern '^out/$'"
```

Expected: one match.

- [ ] **Step 3: Dry-run the publish script**

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf
```

Expected output (approximate):

```

Staged TerminalStyles 0.1.0 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

What if: Performing the operation "Publish-PSResource to PSGallery" on target "C:\Users\felip\dotfiles\out\TerminalStyles".
```

The script should NOT prompt for the API key (because `-WhatIf` short-circuits before the prompt). The script should NOT upload anything to PSGallery.

- [ ] **Step 4: Eyeball the staging dir contents**

```powershell
pwsh -NoProfile -Command "Get-ChildItem -Recurse .\out\TerminalStyles | Select-Object FullName | Format-Table -AutoSize -Wrap"
```

Expected: at the top level of `out\TerminalStyles\`, exactly these items:

```
TerminalStyles.psd1
TerminalStyles.psm1
tstyles.ps1
apply.ps1
README.md
LICENSE
styles\           (folder, recursive)
scripts\          (folder containing only capture-screenshots.ps1)
```

Should NOT see: `docs/`, `tests/`, `.github/`, `install.ps1`, `current-style.ps1`, `.installed-sha`, `.last-update-check`, `.gitignore`, `publish.ps1`.

Under `styles\`, you should see 16 theme folders (eva, ex-machina, forest, garden-rain, gitbash, golden-forest, halo, kitty, lain, marquee, neon-rain, rain, snowday, sober, tombraider, umbrella), each containing at least `scheme.json`.

- [ ] **Step 5: Verify `git status` is clean (staging dir not tracked)**

```bash
git status
```

Expected output mentions `scripts/publish.ps1` as untracked (or modified `.gitignore`) — and **does NOT mention `out/`** (the .gitignore entry takes effect).

- [ ] **Step 6: Commit**

```bash
git add scripts/publish.ps1 .gitignore
git commit -m "$(cat <<'EOF'
Add scripts/publish.ps1 + .gitignore out/

scripts/publish.ps1 stages an allowlist of files into out/TerminalStyles/,
runs Test-ModuleManifest against the staged copy, then runs
Publish-PSResource. Prompts for the API key via Read-Host -AsSecureString
so it never enters env vars, PSReadLine history, or files on disk.
Supports -WhatIf for dry runs that skip both the prompt and the upload.

.gitignore now ignores out/ so the staging dir is never committed.

Spec: docs/superpowers/specs/2026-05-27-psgallery-first-publish-design.md
EOF
)"
```

---

## Task 2: Create `docs/RELEASING.md`

**Files:**
- Create: `docs/RELEASING.md`

Maintainer-facing one-page release procedure with troubleshooting.

- [ ] **Step 1: Create `docs/RELEASING.md`**

Create `C:\Users\felip\dotfiles\docs\RELEASING.md` with this exact content:

````markdown
# Releasing TerminalStyles to the PowerShell Gallery

How to publish a new version of TerminalStyles.

## Preflight

1. Make sure `main` is clean and pushed:

   ```powershell
   git status   # should be clean
   git log --oneline origin/main..HEAD   # should be empty
   ```

2. Run the local Pester suite — should be all green:

   ```powershell
   Invoke-Pester -Path .\tests
   ```

3. Make sure you have your PSGallery API key handy. Generate at
   https://www.powershellgallery.com/account/apikeys with scope
   "Push new packages and package versions" + glob `TerminalStyles`.

## Release

1. **Bump `ModuleVersion`** in `TerminalStyles.psd1`. SemVer; bump patch
   for fixes (`0.1.0` → `0.1.1`), minor for new themes/features
   (`0.1.0` → `0.2.0`), major for breaking changes (`0.x` → `1.0`).

2. **Update `PrivateData.PSData.ReleaseNotes`** in `TerminalStyles.psd1`
   with a 1-3 line summary of what's in this release. PSGallery shows
   this on the version's page.

3. **Commit the version bump** and push:

   ```powershell
   git add TerminalStyles.psd1
   git commit -m "Bump version to <new-version>"
   git push origin main
   ```

4. **Dry-run the publish script** first (stages files + runs
   `Test-ModuleManifest`, no upload):

   ```powershell
   pwsh -File .\scripts\publish.ps1 -WhatIf
   ```

   Eyeball the printed stage dir — `Get-ChildItem -Recurse .\out\TerminalStyles`
   should show exactly the allowlist contents.

5. **Run the real publish.** The script prompts for your API key
   (input hidden, never written to disk):

   ```powershell
   pwsh -File .\scripts\publish.ps1
   ```

6. **Tag the release** for traceability:

   ```powershell
   git tag v<new-version>
   git push --tags
   ```

7. **Verify** within ~1 minute at
   https://www.powershellgallery.com/packages/TerminalStyles/

8. **Smoke-test the install** in a clean shell (no module already
   loaded):

   ```powershell
   pwsh -NoProfile -Command "Install-PSResource -Name TerminalStyles -Scope CurrentUser; Import-Module TerminalStyles -DisableNameChecking; Get-Command -Module TerminalStyles | Format-Table"
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
| `Publish-PSResource` not recognized | PSResourceGet (the package containing it) not preinstalled. Stock pwsh 7.4+ has it. | `Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope CurrentUser` and retry. |

## What gets published

The `scripts/publish.ps1` allowlist controls what ships. Currently:

- `TerminalStyles.psd1`, `TerminalStyles.psm1`
- `tstyles.ps1`, `apply.ps1`
- `styles/` (all 16 themes)
- `README.md`, `LICENSE`
- `scripts/capture-screenshots.ps1`

Intentionally excluded: `docs/`, `tests/`, `.github/`, `install.ps1`,
runtime state files (`current-style.ps1`, `.installed-sha`,
`.last-update-check`, cached `background.<ext>` files), the publish
script itself.

## Quick reference

```powershell
# Dry run
pwsh -File .\scripts\publish.ps1 -WhatIf

# Publish
pwsh -File .\scripts\publish.ps1

# Verify after publish
Find-PSResource -Name TerminalStyles -Repository PSGallery
```
````

- [ ] **Step 2: Verify the markdown renders correctly**

```powershell
pwsh -NoProfile -Command "Get-Content .\docs\RELEASING.md | Select-String -Pattern '^# Releasing|^## Preflight|^## Release|^## Troubleshooting'"
```

Expected: 4 matches (one per top-level/H2 heading).

- [ ] **Step 3: Commit**

```bash
git add docs/RELEASING.md
git commit -m "$(cat <<'EOF'
Add docs/RELEASING.md (maintainer release procedure)

One-page maintainer-facing procedure for releasing new TerminalStyles
versions to PSGallery. Covers preflight (clean main, green Pester),
release steps (version bump, ReleaseNotes update, dry-run, publish,
tag), and troubleshooting (version-conflict, manifest fail,
DisableNameChecking, state-file caveat, PSResourceGet missing).
EOF
)"
```

---

## Task 3: Push commits to `origin/main`

**Files:** None modified. Push only.

Get the two new commits durable on `origin` before the irreversible publish action.

- [ ] **Step 1: Confirm pending commits**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Two commits ahead:

1. `Add docs/RELEASING.md (maintainer release procedure)` (Task 2)
2. `Add scripts/publish.ps1 + .gitignore out/` (Task 1)

- [ ] **Step 2: Push**

```bash
git push origin main
```

Expected: `<prior-sha>..<HEAD-sha>  main -> main`.

---

## Task 4: Execute the first publish

**Files:** None modified locally. PSGallery state changes.

This task requires the maintainer's PowerShell Gallery API key. The
key is already in the maintainer's possession (created during
brainstorming).

- [ ] **Step 1: Final pre-publish sanity check**

Local Pester pass:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests"
```

Expected: 43 tests passed.

Final dry-run of the publish:

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf
```

Expected: stages successfully, prints "What if: Performing the operation..." for the publish, does NOT prompt for the key.

- [ ] **Step 2: Run the real publish**

```powershell
pwsh -NoProfile -File .\scripts\publish.ps1 -ApiKey '<paste-key-here>'
```

(`-ApiKey` is passed inline to avoid the interactive prompt during automated execution. For maintainer hands-on use later, just `pwsh -File .\scripts\publish.ps1` and the prompt fires.)

Expected output:

```
Staged TerminalStyles 0.1.0 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

Published TerminalStyles 0.1.0 to PSGallery.
Verify at: https://www.powershellgallery.com/packages/TerminalStyles/0.1.0
```

If `Publish-PSResource` errors:
- "A package with this version already exists" → version `0.1.0` already on PSGallery. Bump to `0.1.1` in the manifest, commit, push, retry.
- "401 Unauthorized" → API key invalid or revoked. Generate a new one on PSGallery and retry.
- "Network failure" → retry. PSGallery occasionally hiccups.

- [ ] **Step 3: Verify on PSGallery**

Wait ~30-60 seconds, then:

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery"
```

Expected:

```
Name              Version          Prerelease   Repository      Description
----              -------          ----------   ----------      -----------
TerminalStyles    0.1.0                         PSGallery       Windows Terminal themes for PowerShell...
```

If `Find-PSResource` returns nothing, wait another minute (PSGallery indexing lag) and retry. If still nothing, check https://www.powershellgallery.com/packages/TerminalStyles/0.1.0 directly in a browser — the page should exist.

---

## Task 5: Smoke-test install + tag + push tag

**Files:** Local repo unchanged; `git tag v0.1.0` added.

Verify the published module installs and works from a clean shell, then tag the commit for traceability.

- [ ] **Step 1: Install from a clean shell and verify the module loads**

```powershell
pwsh -NoProfile -Command "Install-PSResource -Name TerminalStyles -Scope CurrentUser -TrustRepository; Import-Module TerminalStyles -DisableNameChecking; Get-Command -Module TerminalStyles -CommandType All | Format-Table Name, CommandType, ModuleName -AutoSize"
```

Expected:

```
Name                         CommandType ModuleName
----                         ----------- ----------
Invoke-TerminalStyle            Function TerminalStyles
Invoke-TerminalStylesUpdate     Function TerminalStyles
tstyles                            Alias TerminalStyles
```

- [ ] **Step 2: Smoke-test the picker (one non-destructive subcommand)**

```powershell
pwsh -NoProfile -Command "Install-PSResource -Name TerminalStyles -Scope CurrentUser -TrustRepository; Import-Module TerminalStyles -DisableNameChecking; tstyles list"
```

Expected: a list of 16 themes printed with color swatches and a `(* = currently active)` line (or `(no bundled style currently active)` if the user has no current-style.ps1 from a PSGallery install — they'd have one only if they'd already used `tstyles <name>` against the PSGallery install).

Note: this test installs the published version of TerminalStyles to the maintainer's local `~/Documents/PowerShell/Modules/TerminalStyles/0.1.0/`. That's parallel to their existing `%LOCALAPPDATA%\TerminalStyles\` install (which is what they actually use). The PSGallery install can be uninstalled later via `Uninstall-PSResource -Name TerminalStyles`.

- [ ] **Step 3: Tag the release commit**

```bash
git tag v0.1.0
git push --tags
```

Expected: `* [new tag]         v0.1.0 -> v0.1.0`.

- [ ] **Step 4: Verify the tag points at the right commit**

```bash
git show v0.1.0 --stat
```

Expected: shows the most recent commit on `main` (which should be the `Add docs/RELEASING.md` commit from Task 2, or potentially `Add scripts/publish.ps1` from Task 1 if Task 2's commit is on top). The exact commit doesn't matter much — the tag is for human traceability.

---

## Self-Review Notes

Spec coverage:

- `scripts/publish.ps1` with allowlist + Read-Host -AsSecureString + Test-ModuleManifest + Publish-PSResource → Task 1.
- `.gitignore` append → Task 1.
- `docs/RELEASING.md` with preflight + release steps + troubleshooting → Task 2.
- First publish executed and verified → Task 4 + Task 5.
- No README rewrite (sub-project C territory) → not in plan, correctly absent.
- No state-file relocation (sub-project C territory) → not in plan, correctly absent.

Spec items deliberately deferred (matches plan):
- GitHub Actions auto-publish → user opted for manual.
- State-file relocation → Sub-project C.
- README install instructions rewrite → Sub-project C.
- `tstyles update` → `Update-PSResource` → Sub-project C.
- Module signing → out of scope.

Type / signature consistency:

- `scripts/publish.ps1` filename is consistent across the plan, the spec, and RELEASING.md.
- `out/TerminalStyles/` staging path is consistent.
- Allowlist contents match exactly between the spec, the script body in Task 1 Step 1, and the docs/RELEASING.md "What gets published" section.
- `-ApiKey` parameter name is consistent.
- `Publish-PSResource` cmdlet name is consistent (NOT `Publish-Module`, which is the legacy v2 command).

No placeholders. All code blocks contain the actual content to paste. All commands have expected output.

Three judgment calls worth flagging:

- **The spec sketched prompt-first; the plan refines to stage-first → check-first → ShouldProcess gate → prompt-if-needed → publish.** This makes `-WhatIf` not require a key, which is what dry-run users actually want. The refinement preserves the spec's "key never written to disk" goal.
- **Tasks 4-5 are controller-handled (run by the main thread, not a subagent)**, because they require the API key and a subagent can't drive an interactive prompt. The subagent-driven-development controller should recognize this and execute Tasks 4-5 inline.
- **Task 4 Step 2 says `-ApiKey '<paste-key-here>'` inline.** This is intentional for the automated first-publish flow; the alternative (interactive prompt) doesn't work when the controller invokes pwsh via the Bash tool. The leak risk is the same as keeping the key in the existing chat. Future releases (per RELEASING.md) use the interactive prompt, which is safer.
