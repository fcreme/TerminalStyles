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

3. **Update `CHANGELOG.md`**: retitle `## [Unreleased]` to
   `## [<new-version>] - <YYYY-MM-DD>`, start a fresh empty
   `## [Unreleased]` above it, and update the reference links at the
   bottom (point `[Unreleased]` at `v<new-version>...HEAD`, add a
   compare link for the new version).

4. **Commit the version bump** and push:

   ```powershell
   git add TerminalStyles.psd1 CHANGELOG.md
   git commit -m "Bump version to <new-version> + update changelog"
   git push origin main
   ```

5. **Dry-run the publish script** first (stages files + runs
   `Test-ModuleManifest`, no upload):

   ```powershell
   pwsh -File .\scripts\publish.ps1 -WhatIf
   ```

   Eyeball the printed stage dir — `Get-ChildItem -Recurse .\out\TerminalStyles`
   should show exactly the allowlist contents.

6. **Run the real publish.** The script prompts for your API key
   (input hidden, never written to disk):

   ```powershell
   pwsh -File .\scripts\publish.ps1
   ```

7. **Tag the release** for traceability:

   ```powershell
   git tag v<new-version>
   git push --tags
   ```

8. **Verify** within ~1 minute at
   https://www.powershellgallery.com/packages/TerminalStyles/

9. **Smoke-test the install** in a clean shell (no module already
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
- `fonts.json` (coding-font catalog for `tstyles font`)
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
