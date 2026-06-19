# Install Hardening — Design

**Date:** 2026-06-18
**Status:** Approved (pending implementation)
**Author:** Felipe

## Problem

`install.ps1` is the public bootstrap entry point, run via
`iwr -useb …/install.ps1 | iex`. A code audit surfaced four
reliability/robustness gaps in it, plus a structural blocker that makes
all of them hard to test:

1. **No download validation (highest stakes).** The ZIP is fetched
   (`install.ps1:174`) and immediately `Expand-Archive`'d
   (`install.ps1:180`) with no check that it is non-empty or even a
   valid archive. A truncated download or a GitHub 404-with-HTML-body
   surfaces only as a cryptic `Expand-Archive` error, or worse extracts
   into a broken install.

2. **Move-Item can silently nest a broken install.** The install step
   does `Remove-Item $installDir -Recurse -Force` then
   `Move-Item $extractedRoot -Destination $installDir`
   (`install.ps1:213-216`). If `Remove-Item` partially fails (a locked
   GIF, OneDrive/AV lock — the exact locks the script's own comments
   worry about) without throwing, `$installDir` still exists and
   `Move-Item` drops the extracted folder *inside* it as
   `$installDir\TerminalStyles-main\…`. The final
   `Import-Module $installDir\TerminalStyles.psd1` guard
   (`install.ps1:408`) then silently skips, leaving a broken install
   reported as success.

3. **`$PROFILE` rewrite is non-atomic and usually unbacked.**
   `Register-LoaderInProfile` writes the profile with a direct
   truncate-then-write `[System.IO.File]::WriteAllText`
   (`install.ps1:331`). A crash mid-write corrupts the user's
   `$PROFILE`. A `.bak` is taken only on the bundled-style *migration*
   path (`install.ps1:311-312`), not on the normal re-register path —
   so re-running the installer rewrites a user's hand-maintained
   profile in place with no backup and no atomicity.

4. **Execution-policy fix reports success without verifying.**
   `Resolve-ExecutionPolicy` runs `Set-ExecutionPolicy … -Force` in a
   child shell (`install.ps1:361`) and unconditionally prints "Done."
   in green. If a machine-wide (LocalMachine/GPO) policy overrides the
   `CurrentUser` scope, the set silently has no effect but the user is
   told it worked. The interactive `Read-Host` prompt
   (`install.ps1:353`) also blocks if the installer is ever run in a
   non-interactive context.

**Structural blocker:** `install.ps1` interleaves top-level imperative
code (download/extract/install at `:170-251`, loader registration at
`:371-410`) with its function definitions (`:257-369`). There is no
load-without-run seam, so none of its functions can be dot-sourced for
unit testing the way `apply.ps1` allows via `$TStylesApplyNoRun`
(`apply.ps1:289`). The existing register tests cover the *module's*
`Invoke-TerminalStylesRegister`, not `install.ps1`'s own
`Register-LoaderInProfile`.

## Goals

- Validate the downloaded archive before extracting: non-empty, a valid
  ZIP, and actually containing `TerminalStyles.psd1`. Fail with a clear
  "re-run the installer" message instead of a cryptic error.
- Assert the module actually landed at `$installDir` after the
  `Move-Item`, turning a silent nested/broken install into a loud,
  actionable failure.
- Make the `$PROFILE` rewrite atomic (temp file + replace, so a crash
  can't corrupt the profile), and back it up the first time we add our
  loader to a profile that has pre-existing user content — without
  littering a new `.bak` on every re-register.
- Verify the execution-policy change actually took effect before
  reporting success; print the GPO/LocalMachine caveat otherwise. Skip
  the prompt gracefully when non-interactive.
- Add a `$TStylesInstallNoRun` test seam (mirroring `apply.ps1`) so the
  new logic can be dot-sourced and unit-tested with Pester, matching
  the project's existing test culture and CI.
- All code changes are confined to `install.ps1` plus one new test file
  `tests/Install-Hardening.Tests.ps1`.

## Non-goals

- **SHA-pinned download.** Fetching the commit SHA first and downloading
  `/archive/<sha>.zip` was considered and rejected for this pass: it
  adds a pre-download API round-trip (rate-limitable) for reproducibility
  that HTTPS-plus-validation does not need. The installer intentionally
  tracks `main`.
- **Checksum / signature manifest.** True cryptographic integrity would
  require a self-maintained per-release hash the project doesn't publish
  (it installs straight from the `main` branch archive). Out of scope.
- **The other three audit packages** — settings-write safety in
  `apply.ps1`/`tstyles.ps1`, picker performance, and docs/catalog fixes.
  Separate specs if pursued.
- **Re-styling installer output.** The banner/step/panel UX
  (`Write-InstallBanner`/`Write-InstallStep`/`Write-InstallPanel`) is
  untouched except for the new validation step lines.
- **Sharing helpers with `apply.ps1`/`tstyles.ps1`.** Impossible at
  bootstrap — only `install.ps1` is piped into `iex`; nothing else is
  on disk yet. All new helpers live inside `install.ps1`.

## Architecture

One file changes structurally; one test file is added.

1. **Test seam (reorder).** `install.ps1` is reordered to:
   header + pure variable definitions → *all* functions (existing +
   new) → `if (-not $TStylesInstallNoRun) { <entire main flow> }`. The
   `chcp`/console-encoding setup and the `$ErrorActionPreference` /
   `$ProgressPreference` assignments move *inside* the guard so that
   dot-sourcing for tests has no side effects (no external `chcp`
   process, no preference mutation in the test scope). Tests set
   `$TStylesInstallNoRun = $true` and dot-source the script to reach
   its functions, exactly as `apply.ps1`'s tests do.

2. **Four hardening units**, each a small self-contained function inside
   `install.ps1`:
   - `Assert-ValidArchive` — pure, fully unit-testable.
   - `Assert-InstallLanded` — pure, fully unit-testable.
   - `Write-TextFileAtomic` — pure, fully unit-testable; consumed by
     `Register-LoaderInProfile`.
   - `Resolve-ExecutionPolicy` — modified in place; the policy-decision
     logic is unit-testable, the actual `Set-ExecutionPolicy` shell-out
     is integration-only.

## File-by-file changes

### `install.ps1` — reorder + test seam

Move the three output helpers (`Write-InstallBanner`,
`Write-InstallStep`, `Write-InstallPanel`), the three flow helpers
(`Get-ShellInfo`, `Register-LoaderInProfile`, `Resolve-ExecutionPolicy`),
and the new functions below so they are all defined before any
imperative code. Then wrap the imperative flow (currently the banner
call through the same-tab handoff, `:170-251` and `:371-410`) in:

```powershell
# Main flow. Guarded so tests can dot-source this script for its
# functions (set $TStylesInstallNoRun = $true) without running the
# installer. A normal `iwr | iex` run never sets the var, so main runs.
if (-not $TStylesInstallNoRun) {
    $null = & chcp 65001 2>&1
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference     = 'SilentlyContinue'

    Write-InstallBanner
    # … download, validate, extract, install, register, handoff …
}
```

The `$repo`/`$branch`/`$installDir`/`$zipUrl`/`$runId`/`$tempZip`/
`$tempDir`/loader-string definitions stay at top level (pure, cheap,
side-effect-free) so functions and tests can reference them.

### `install.ps1` — `Assert-ValidArchive` (new)

Called immediately after the download, before `Expand-Archive`.

```powershell
function Assert-ValidArchive {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "Download was empty or missing. This is usually a network blip -- re-run the installer."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem  # WinPS 5.1 needs this explicitly
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $hasManifest = $zip.Entries | Where-Object { $_.FullName -match 'TerminalStyles\.psd1$' }
            if (-not $hasManifest) {
                throw "Downloaded file is not a TerminalStyles archive (no module manifest found). Re-run the installer."
            }
        } finally { $zip.Dispose() }
    } catch [System.IO.InvalidDataException] {
        throw "Downloaded file is not a valid ZIP (partial download or network error). Re-run the installer."
    }
}
```

Flow change at the download site (`:173-181`):

```powershell
Write-InstallStep "Downloading"
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
Assert-ValidArchive -Path $tempZip
Write-InstallStep "Downloading" -Check

Write-InstallStep "Extracting"
…
```

### `install.ps1` — `Assert-InstallLanded` (new)

Called right after the `Move-Item` (`:216`).

```powershell
function Assert-InstallLanded {
    param([Parameter(Mandatory)][string]$InstallDir)
    $manifest = Join-Path $InstallDir 'TerminalStyles.psd1'
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw ("Install did not complete: $manifest is missing. A leftover lock on " +
               "'$InstallDir' may have blocked the update. Close other PowerShell tabs " +
               "and re-run the installer.")
    }
}
```

Also add a pre-move sanity check: after `Remove-Item $installDir`
(`:213-215`), if `$installDir` still exists, throw rather than letting
`Move-Item` nest the source inside it.

### `install.ps1` — `Write-TextFileAtomic` (new) + `Register-LoaderInProfile` (modified)

`Write-TextFileAtomic` writes UTF-8 (no BOM) to a temp sibling, then
atomically replaces the target (`[System.IO.File]::Replace` when the
target exists, else `Move`); on a replace failure it falls back to a
direct write but surfaces a one-time warning. It mirrors the atomic
pattern already proven in `apply.ps1`'s `Write-WTSettingsFile` and
`tstyles.ps1`'s `Write-SettingsAtomic`, kept as a private copy because
the bootstrap can't share code.

`Register-LoaderInProfile` changes:

- The final write (`:331`,
  `[System.IO.File]::WriteAllText($ProfilePath, $final, …)`) becomes
  `Write-TextFileAtomic -Path $ProfilePath -Content $final`.
- **Backup rule (litter-free):** before the first time we add our loader
  to a profile that (a) already exists with non-whitespace content and
  (b) does *not* already contain a TerminalStyles BEGIN/END block, copy
  it to `$ProfilePath.bak-<yyyyMMdd-HHmmss>`. When the block is already
  present (a re-register), skip the backup — we're only swapping our own
  block, so no user content is at risk. The existing migration backup
  (`:311-312`) is unchanged and remains the backup for that path.

### `install.ps1` — `Resolve-ExecutionPolicy` (modified) + `Test-PolicyResolved` (new)

- Combine set + verify into one child launch:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force;
  Get-ExecutionPolicy -Scope CurrentUser`. Capture the trailing policy
  value the child prints.
- Extract the pure decision into a tiny testable helper so the shell-out
  itself stays a thin wrapper (the `& $cmd.Source` call operator can't be
  mocked cleanly, so the logic must live outside it):

  ```powershell
  function Test-PolicyResolved {
      # Returns $true if the (re-queried) effective policy now permits
      # the loader to run -- i.e. it is no longer Restricted/AllSigned.
      param([string]$Policy)
      return -not ([string]::IsNullOrWhiteSpace($Policy)) -and
             ($Policy.Trim() -notin @('Restricted', 'AllSigned'))
  }
  ```

- Print "Done. CurrentUser policy is now RemoteSigned" **only** when
  `Test-PolicyResolved` returns `$true` for the re-queried value.
  Otherwise print the existing LocalMachine/GPO caveat and manual-fix
  instructions (so a GPO-overridden machine no longer gets a false
  "Done.").
- Guard the `Read-Host` prompt: if `[Environment]::UserInteractive` is
  `$false`, skip the prompt and print the manual `Set-ExecutionPolicy`
  instructions instead of blocking.

### `tests/Install-Hardening.Tests.ps1` (new)

Pester 5, mirroring `tests/Apply-WriteWTSettings.Tests.ps1`: set
`$TStylesInstallNoRun = $true`, then `. install.ps1` for functions only.

## Data flow (install order, with new checks)

1. `iwr … | iex` runs `install.ps1`; main flow begins (guard false).
2. Banner renders.
3. **Download** → `Assert-ValidArchive` (non-empty + valid ZIP +
   contains manifest) → step checked.
4. **Extract** to `$tempDir`; locate `$extractedRoot`.
5. Preserve `current-style.ps1` + cached backgrounds (unchanged).
6. `Remove-Item $installDir`; **assert it's gone**; `Move-Item`
   extracted root → `$installDir`; **`Assert-InstallLanded`**.
7. Restore preserved bytes; clean up temp; record install SHA
   (unchanged).
8. For each detected shell: `Register-LoaderInProfile` (atomic write +
   first-touch backup) → `Resolve-ExecutionPolicy` (set + verify).
9. "Ready" panel; same-tab handoff (unchanged).

## Error handling

| Failure | Behavior |
|---|---|
| Empty/missing downloaded file | `Assert-ValidArchive` throws a clear "re-run" message before any extract. |
| Corrupt/truncated ZIP | `OpenRead` throws `InvalidDataException` → caught → "not a valid ZIP, re-run." |
| 404 HTML body saved as the zip | Opens but has no `TerminalStyles.psd1` entry → "not a TerminalStyles archive, re-run." |
| `Remove-Item $installDir` partially fails, dir remains | Pre-move check throws before `Move-Item` can nest the source. |
| Extract/move otherwise produces no manifest | `Assert-InstallLanded` throws with a lock-hint message. |
| Crash mid `$PROFILE` write | Atomic temp+replace leaves the original profile intact. |
| `File.Replace` unsupported on the volume | Falls back to direct write with a one-time warning (no worse than today). |
| Execution-policy set blocked by GPO/LocalMachine | Re-query shows it unchanged → caveat + manual instructions printed (no false "Done."). |
| Non-interactive host | `Read-Host` prompt skipped; manual instructions printed instead of blocking. |
| Temp zip/dir left after a validation throw | Cleaned up via `-ErrorAction SilentlyContinue` removal in the failure path. |

## Testing

**Pester (`tests/Install-Hardening.Tests.ps1`):**

- `Assert-ValidArchive`:
  - a real ZIP (built in `$TestDrive`) containing `…/TerminalStyles.psd1`
    → passes;
  - a zero-byte file → throws "empty";
  - a plain text file renamed `.zip` → throws "not a valid ZIP";
  - a valid ZIP without the manifest → throws "not a TerminalStyles
    archive".
- `Assert-InstallLanded`: dir containing `TerminalStyles.psd1` → passes;
  dir without it → throws.
- `Write-TextFileAtomic`: writes exact content; UTF-8 with no BOM;
  overwrites an existing file; leaves no stray temp file.
- `Register-LoaderInProfile` backup rule (call with `-InstallDir`
  pointing at a `$TestDrive` fixture containing an empty `styles/`):
  - fresh empty profile → loader written, **no** `.bak`;
  - profile with pre-existing user content and no loader block →
    loader written, **exactly one** `.bak` created;
  - re-run with the loader block already present → idempotent, **no new**
    `.bak`.
- `Test-PolicyResolved`: `RemoteSigned`/`Bypass`/`Unrestricted` → `$true`;
  `Restricted`/`AllSigned`/empty → `$false`. (This is the unit-testable
  core of the policy decision; the actual `Set-ExecutionPolicy`
  shell-out in `Resolve-ExecutionPolicy` is integration-only.)

**Manual (one-shot, hard to fully automate):**

- Fresh install (pwsh 7 and WinPS 5.1): one-liner completes, steps show
  `✓`, `tstyles` works in-tab.
- Reinstall over an existing install: preserve steps fire; no spurious
  new profile `.bak`.
- Simulated corrupt download: point `$zipUrl` at a small non-zip URL;
  confirm the clear validation message.

## Known limitations

- **Branch-archive trust model unchanged.** Validation confirms the
  download is a well-formed TerminalStyles archive, not that it is a
  specific signed release. HTTPS remains the transport-integrity
  guarantee; SHA-pinning and signatures are explicit non-goals here.
- **`Resolve-ExecutionPolicy` verification is best-effort.** It re-reads
  the effective `CurrentUser` policy after setting; an exotic
  policy-resolution edge case could still mislead, but the common
  GPO-override case is now reported honestly.
- **`Write-TextFileAtomic` fallback is non-atomic.** On a volume where
  `File.Replace` is unsupported it degrades to a direct write (warned),
  which is no worse than the current behavior.
- **Installer helpers are duplicated, by necessity.** The atomic-write
  logic now exists in three places (`install.ps1`, `apply.ps1`,
  `tstyles.ps1`) because the bootstrap can't source shared code. This is
  an accepted, documented trade-off, not drift to fix here.
