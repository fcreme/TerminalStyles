# TerminalStyles as a PowerShell Module — Design (Sub-project A)

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Part of:** PowerShell Gallery migration (sub-project A of A/B/C — see "Sub-project context" below)

## Problem

The current installation model is the `iwr -useb …/install.ps1 | iex` curl-pipe-shell pattern. It works, but the user explicitly wants a more "professional" entry point — specifically, the PowerShell Gallery (PSGallery) idiom:

```powershell
Install-PSResource -Name TerminalStyles
```

That requires `TerminalStyles` to be a published PowerShell module — which in turn requires the code to be structured as a module (`.psd1` manifest + `.psm1` entry) rather than a single `tstyles.ps1` script that gets dot-sourced from `$PROFILE`.

The migration was decomposed into three sub-projects during brainstorming. This spec covers **Sub-project A** only: restructure the code as a module locally, without any PSGallery publishing. Sub-projects B (publish) and C (migration UX) have separate specs.

## Goals

- Provide `TerminalStyles.psd1` (manifest) and `TerminalStyles.psm1` (module entry) at the repo root, alongside the existing `tstyles.ps1`.
- After install, users can `Import-Module TerminalStyles` (from any tab) to get the `tstyles` command.
- Existing `iwr | iex` install flow keeps working; `install.ps1` switches its `$PROFILE` loader from dot-source to `Import-Module`.
- Existing same-tab handoff keeps working; `install.ps1` switches from `.` dot-source to `Import-Module ... -Force -Global`.
- Existing Pester suite (43 tests) still passes; test files switch from dot-source to `Import-Module` + `InModuleScope` where they exercise internal functions.
- `tstyles update`, `tstyles uninstall`, the picker, `apply.ps1`, and every other user-facing behavior stays byte-identical.
- Tab completion for `tstyles <TAB>` continues to work.
- The module's public surface is small and intentional: `Invoke-TerminalStyle` + `Invoke-TerminalStylesUpdate` + alias `tstyles`.

## Non-goals

- PSGallery account creation, API key, publishing workflow. (Sub-project B.)
- `tstyles update` switching to `Update-PSResource`. (Sub-project C.)
- README install command changes — still documents `iwr | iex`. (Sub-project C.)
- State-file relocation. Today, `.installed-sha`, `.last-update-check`, `current-style.ps1`, and cached `background.<ext>` files all live at `%LOCALAPPDATA%\TerminalStyles\`. Once we publish to PSGallery (Sub-project B), the module directory becomes version-managed and read-only-ish; state files will need to move to a separate per-user data dir. For Sub-project A, the install dir is still writable, so state stays where it is.
- Splitting `tstyles.ps1` into Public/Private folders (the PowerShell module convention with one function per file). The all-in-one `.psm1` dot-source approach is simpler and the script is small enough to read top-to-bottom.
- Renaming `Apply-StyleDirect` → `Set-TerminalStyleDirect` to satisfy PowerShell's approved-verb convention. Suppress the warning via `-DisableNameChecking` for now; defer renames until exports become user-facing concerns in B/C.
- Module signing.
- Pester tests for the new `.psm1` / `.psd1` structure itself. (Existing tests catch regressions in `tstyles.ps1`; adding tests for manifest loading is YAGNI.)
- Changes to `apply.ps1`. It stays a standalone script for non-interactive scripted use.

## Sub-project context

The user picked "All three sub-projects, sequentially" during brainstorming. The full path:

| Sub-project | Scope | Why deferred until later |
|---|---|---|
| **A** (this spec) | Module restructure, local-only | Foundation for B; can stand alone if we never publish. |
| B | Publish to PSGallery | Needs A done first; involves account setup, signing, CI publish workflow. |
| C | Migration UX | Needs B done first; updates `tstyles update`/`uninstall` to delegate to PSResourceGet, rewrites README install section. |

Each sub-project gets its own spec → plan → implementation cycle.

## Architecture

Three new files (`.psd1`, `.psm1`, no source code split) plus surgical edits in `install.ps1` and the three test files. The existing `tstyles.ps1` is unchanged in behavior — it's dot-sourced into module scope by `.psm1`, so all its functions become module-scoped, and the `.psd1` manifest controls what's exported to consumers.

### Module entry-point pattern

```
TerminalStyles.psd1       (manifest: version, exports, metadata)
        │
        └─ RootModule = 'TerminalStyles.psm1'
                          │
                          └─ . tstyles.ps1   (existing library, unchanged)
```

When a consumer does `Import-Module TerminalStyles`:

1. PowerShell loads `TerminalStyles.psd1`, reads the manifest.
2. `RootModule` points at `TerminalStyles.psm1`, which gets executed in a module scope.
3. `.psm1` dot-sources `tstyles.ps1`, bringing all its functions into module scope (`Invoke-TerminalStyle`, `Apply-StyleDirect`, `Merge-StyleIntoSettings`, etc.) plus the `Set-Alias -Name tstyles` from the bottom of `tstyles.ps1`.
4. The manifest's `FunctionsToExport` and `AliasesToExport` filter what's visible to consumers — only `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`, and `tstyles` cross the boundary.
5. The `Register-ArgumentCompleter` call at the bottom of `tstyles.ps1` registers globally (PowerShell completers are not module-scoped), so tab completion works for module consumers.

### Same-tab handoff change

Today the installer ends with `. $installedLib`. With modules, dot-source doesn't expose module exports. The fix:

```powershell
Import-Module $installedManifest -Force -Global *> $null
```

- `-Force`: reload if already imported (so `tstyles update` flows pick up the new code).
- `-Global`: load into the global scope, not the script's child scope. Without this, when `install.ps1` runs via `iwr | iex` in the user's session, the import would happen in install.ps1's nested scope and disappear when the script returns. With `-Global`, the import survives into the caller's session — `tstyles` becomes available immediately in the same tab. This is the **single most critical line** of the sub-project; verify with a smoke test.

## File-by-file changes

### `TerminalStyles.psd1` (NEW)

Module manifest. Generate the GUID once during implementation and pin it for the life of the module.

```powershell
@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '<run [guid]::NewGuid() once, paste here, never change>'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Windows Terminal themes for PowerShell — 16 bundled styles with arrow-key live-preview picker.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Themes', 'Color', 'Prompt', 'pwsh')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'Initial module structure (sub-project A of the PSGallery migration). No behavior changes from the prior dot-sourced install.'
        }
    }
}
```

Notes:
- `ModuleVersion = '0.1.0'` per design discussion — leaves headroom for breaking changes before 1.0.
- `PowerShellVersion = '5.1'` matches the existing `#Requires` on `tstyles.ps1`.
- `FunctionsToExport` is the exhaustive list — no wildcards (`*`). Wildcards prevent PowerShell from auto-loading the module by command name and slow down session startup.
- `AliasesToExport = @('tstyles')` re-exports the alias `tstyles.ps1` sets internally.
- `CmdletsToExport` / `VariablesToExport` set to `@()` (not `*`) explicitly — PSGallery rejects modules that export wildcard variables.

### `TerminalStyles.psm1` (NEW)

Minimal module entry that dot-sources the existing library.

```powershell
# TerminalStyles module entry. Dot-sources tstyles.ps1 to bring its
# functions and the `tstyles` alias into module scope. The manifest
# (TerminalStyles.psd1) controls what's exported to consumers.
#
# tstyles.ps1 stays unchanged so that:
#   - apply.ps1 (standalone script) can keep using the same library
#     directly if it ever needs to (currently it doesn't dot-source).
#   - the existing test fixtures and conventions stay familiar.

. (Join-Path $PSScriptRoot 'tstyles.ps1')
```

That's the whole file. No `Export-ModuleMember` calls — the manifest's `FunctionsToExport` / `AliasesToExport` do the filtering.

### `install.ps1`

Two changes. Both swap dot-source for `Import-Module`.

#### Change 1: `$loaderBody` heredoc (around line 32-36)

Current:

```powershell
$loaderBody  = @"
$loaderBegin
. "`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"
$loaderEnd
"@
```

New:

```powershell
$loaderBody  = @"
$loaderBegin
Import-Module "`$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking
$loaderEnd
"@
```

- `-DisableNameChecking` suppresses PowerShell's warning about `Apply-StyleDirect` not following approved-verb naming. The function isn't exported to consumers, but the warning fires anyway during dot-source. Long-term we rename (separate spec); short-term we suppress.

#### Change 2: same-tab handoff at end of file (added in Task 3 of the prior install-ux plan)

Current:

```powershell
# --- Same-tab handoff ---
$installedLib = Join-Path $installDir 'tstyles.ps1'
if (Test-Path -LiteralPath $installedLib) {
    . $installedLib *> $null
}
```

New:

```powershell
# --- Same-tab handoff ---
# Import the freshly-installed module into the GLOBAL scope (not the
# script's child scope) so the `tstyles` command is available in the
# caller's session immediately. Without -Global, the import would be
# scoped to this script and disappear when install.ps1 returns.
$installedManifest = Join-Path $installDir 'TerminalStyles.psd1'
if (Test-Path -LiteralPath $installedManifest) {
    Import-Module $installedManifest -Force -Global -DisableNameChecking *> $null
}
```

Both edits use the existing `$installDir` variable (defined at the top of `install.ps1`).

### `tests/Get-SchemeSwatch.Tests.ps1`

Change `BeforeAll` from:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
    # ... helper function definition ...
}
```

To:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    # ... helper function definition ...
}
```

`Get-SchemeSwatch` is currently a top-level function in `tstyles.ps1` that's NOT in `FunctionsToExport`. After the manifest change it's module-private. The tests call `Get-SchemeSwatch` directly — they need to wrap their function calls in `InModuleScope TerminalStyles { ... }`.

The cleanest pattern: move the existing inline helper (`Get-ThemeSwatchRGBs`) into an `InModuleScope` block and call it from the tests via a module-scoped wrapper. OR re-structure the test to import a small helper into the test scope but call the actual `Get-SchemeSwatch` inside `InModuleScope`. Implementation plan will pick the cleanest variant.

### `tests/Test-UpdateAvailable.Tests.ps1`

Same pattern: `Import-Module` instead of dot-source, wrap function calls in `InModuleScope TerminalStyles`. `Test-UpdateAvailable` is module-private (not in `FunctionsToExport`).

The existing mock setup (`Mock Invoke-RestMethod`, `$script:TStylesRoot = $TestDrive`) needs to live inside the `InModuleScope` block so the mocks apply to the module-scoped function. This is a Pester 5 convention — mocks set outside `InModuleScope` won't intercept calls made from inside the module.

### `tests/Apply-StyleDirect-Backup.Tests.ps1`

Same pattern. `Apply-StyleDirect`, `Find-WTSettingsPath`, `Show-UpdateNoticeIfAvailable`, `Get-CurrentWTProfileName`, `Merge-StyleIntoSettings`, `Write-SettingsFile` are all module-private. Wrap in `InModuleScope`.

### `tstyles.ps1`

**No functional change.** Keep the `Set-Alias` and `Register-ArgumentCompleter` at the bottom. They run when `tstyles.ps1` is dot-sourced from `.psm1`.

### `apply.ps1`

**No change.** It's a standalone script used for non-interactive applies. It doesn't dot-source `tstyles.ps1` or import the module; it has its own self-contained copies of `Find-WTSettingsPath`, `Get-AvailableStyles`, etc.

### `README.md`

**No change in sub-project A.** The install command still documents `iwr | iex`. Sub-project C handles the rewrite.

## Data flow

### Fresh install

1. User runs `iwr -useb …/install.ps1 | iex` in pwsh.
2. `install.ps1` downloads, extracts, places files at `%LOCALAPPDATA%\TerminalStyles\` (now including the new `TerminalStyles.psd1` and `TerminalStyles.psm1` alongside `tstyles.ps1`).
3. `install.ps1` writes the new loader line to `$PROFILE`: `Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking`.
4. `install.ps1` does the same-tab handoff: `Import-Module $installedManifest -Force -Global -DisableNameChecking`.
5. User types `tstyles` → picker launches. (Identical UX from here.)
6. New shell tabs import the module on startup via the new `$PROFILE` line.

### Reinstall (existing user)

1. User runs `iwr | iex` (or `tstyles update` which currently re-runs the installer).
2. `install.ps1` extracts the new tree; existing `current-style.ps1` and cached backgrounds are preserved (existing behavior, no change).
3. `install.ps1` rewrites `$PROFILE`: the regex strip `(?ms)# ===== TerminalStyles BEGIN =====.*?# ===== TerminalStyles END =====\r?\n?` removes the old dot-source block; the new `Import-Module` block replaces it. Net result: a clean swap, no duplicate lines.
4. Same-tab handoff with `-Force -Global` reloads the module in the current tab.
5. User keeps working without opening a new tab.

### Test run (local or CI)

1. `Invoke-Pester -Path tests` discovers all `*.Tests.ps1`.
2. Each file's `BeforeAll` runs `Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null`.
3. `It` blocks calling exported functions (`Invoke-TerminalStyle`) work directly.
4. `It` blocks calling module-private functions (`Test-UpdateAvailable`, `Apply-StyleDirect`, `Get-SchemeSwatch`) wrap calls in `InModuleScope TerminalStyles { ... }` so they can see the private surface.
5. Mocks (`Mock Invoke-RestMethod`, `Mock Copy-Item`) live inside `InModuleScope` so they intercept calls from the module's perspective.

## Error handling

| Failure | Behavior |
|---|---|
| Malformed `TerminalStyles.psd1` | `Import-Module` throws with the manifest parser error. `install.ps1`'s `$ErrorActionPreference = 'Stop'` surfaces it as an install failure. |
| `TerminalStyles.psm1` dot-source throws (e.g. `tstyles.ps1` deleted) | `Import-Module` throws. Same handling as above. |
| `Apply-StyleDirect` non-approved-verb warning still fires despite `-DisableNameChecking` | Cosmetic; the import still succeeds. Users with strict mode might see it; tolerable. Rename in a future spec. |
| `-Global` import scope leaks unexpected state across user's other modules | The module exports only 2 functions + 1 alias, no variables, no cmdlets. Minimal pollution. The `Register-ArgumentCompleter` registration was already global pre-module. No regression. |
| `Import-Module -Force` while the module is in-use | PowerShell handles re-import cleanly; the module's internal state (`$script:TStylesRoot`, etc.) reinitializes. The picker, if currently open mid-arrow-key, would NOT be affected because reimport doesn't kill running scripts. Edge case: if the user is mid-picker and a parallel session does `tstyles update`, the running picker keeps its in-memory state until the user hits Enter/Esc. Acceptable. |
| Pester test inadvertently calls a module-private function without `InModuleScope` | Test fails with `The term '<function>' is not recognized`. Clear error, easy to fix during the test migration. |

## Testing

Manual smoke tests:

- **Local module load:** `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1; Get-Command -Module TerminalStyles"` → should show `Invoke-TerminalStyle` (Function), `Invoke-TerminalStylesUpdate` (Function), `tstyles` (Alias). Nothing else.
- **Fresh install end-to-end:** Delete `%LOCALAPPDATA%\TerminalStyles\` + strip $PROFILE. Run `iwr | iex`. Verify: panel renders (existing UX intact), `tstyles` works immediately in the same tab, new tab also has `tstyles`.
- **Reinstall over old (dot-source) install:** Don't delete LOCALAPPDATA. Don't strip $PROFILE. Run `iwr | iex`. Verify: $PROFILE now contains the new `Import-Module` line (not the old `. "$env:..."` dot-source); `tstyles` works in the same tab; opening a new tab also gives `tstyles`.
- **Tab completion:** Type `tstyles l<TAB>` in a new tab — should complete to `list`. `tstyles e<TAB>` should suggest theme names starting with 'e'.
- **`tstyles list`, `tstyles current`, `tstyles random`, `tstyles <name>`, `tstyles -BackgroundImage <path>`** — all should work as before.

Automated:
- `Invoke-Pester -Path tests` → all 43 tests pass.
- CI workflow (`.github/workflows/test.yml`) runs the same test suite; should stay green after the test-file migration.

## Known limitations / risks

- **The `Apply-StyleDirect` verb-noun warning** is a real (cosmetic) wart suppressed via `-DisableNameChecking`. A future spec can rename to `Set-TerminalStyleDirect` (or similar) — defer until the public surface really matters for PSGallery consumers.
- **`Get-SchemeSwatch` is currently used by the test suite as if it's public-ish.** It's not in `FunctionsToExport`. Tests will use `InModuleScope TerminalStyles { Get-SchemeSwatch ... }`. If we ever want to expose it for users to build their own theme tools, add it to `FunctionsToExport`. Not now.
- **`Register-ArgumentCompleter` is global.** It registers against `Invoke-TerminalStyle` regardless of which version of the module is imported. If a user has multiple versions of TerminalStyles in their PSModulePath (future scenario in sub-project B), the last-imported version's completer wins. Not a real risk in sub-project A (only one install location).
- **`-Global` flag carries import side effects.** Globally-loaded modules persist for the whole session. If a user reloads `install.ps1` multiple times in one tab (unlikely), each load is a `-Force` re-import. Idempotent in practice.
- **PowerShell 5.1 strict-mode environments** that ban dot-sourcing scripts from `$PROFILE` will still work — `Import-Module` is the canonical mechanism and is not blocked. This is actually an improvement over the prior dot-source.
- **Reverting from module-based to dot-source** would require a code change to `install.ps1` (swap the heredoc back) plus a rewrite of $PROFILE. Easy to do, low likelihood of needing it.
