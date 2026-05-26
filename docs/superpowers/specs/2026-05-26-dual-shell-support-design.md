# Dual-Shell Support (pwsh 7 + Windows PowerShell 5.1) — Design

**Date:** 2026-05-26
**Status:** Approved (pending implementation)
**Author:** Felipe

## Problem

TerminalStyles currently targets PowerShell 7 only (`#Requires -Version 7` in
`install.ps1`, `tstyles.ps1`, `apply.ps1`). When installed on a fresh PC the
user reported a `PSSecurityException` / "ejecución de scripts está
deshabilitada" error on shell startup, triggered from
`Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` — i.e. from a
**Windows PowerShell 5.1** session, not pwsh 7. Diagnosis:

1. The error is from execution policy (`Restricted`) blocking the user's
   preexisting WinPS 5.1 profile. Our installer never touched that file,
   because `$PROFILE` in pwsh 7 resolves to `Documents\PowerShell\…` — a
   different path.
2. The user wants TerminalStyles to work in both engines with a single install
   one-liner, and wants the execution-policy roadblock handled cleanly during
   install.

This spec covers (a) porting the scripts to be portable across pwsh 7 and
WinPS 5.1, (b) extending the installer to register the loader in both
engines' profiles in one run, and (c) detecting + interactively offering to
fix `Restricted` execution policy per engine.

## Goals

- One install one-liner (`iwr | iex`) works from either pwsh 7 or WinPS 5.1.
- After install, `tstyles` works identically in both engines with full prompt
  parity (umbrella ANSI banner + prompt renders in 5.1).
- Execution policy blockage is detected during install and the user is
  prompted to fix it (never silent).
- Single source of truth: one set of scripts, no duplicated per-engine
  variants.

## Non-goals

- Bypassing or weakening execution policy without user consent.
- Supporting older PowerShell (≤ 5.0) or PowerShell on macOS/Linux.
- Working around enterprise GPO-locked execution policy (we report and
  instruct, but cannot override).

## Architecture

Single-source PowerShell scripts using lowest-common-denominator syntax that
parses and runs in both engines. `install.ps1` becomes a cross-shell
orchestrator that queries each installed engine for its `$PROFILE` path
(rather than only using the current engine's `$PROFILE`) and registers the
loader in any shell it finds. `%LOCALAPPDATA%\TerminalStyles\` remains the
single shared install directory — both engines dot-source the same
`tstyles.ps1` and `current-style.ps1`.

## File-by-file changes

### `install.ps1`

- Lower `#Requires -Version 7` to `5.1` so the installer itself runs in either
  shell.
- After extract, replace the single `$PROFILE` write with a loop over
  detected shells:
  - **pwsh 7:** query via
    `& pwsh.exe -NoProfile -NonInteractive -Command '$PROFILE'`. Skip if
    `pwsh.exe` not on PATH.
  - **WinPS 5.1:** query via
    `& powershell.exe -NoProfile -NonInteractive -Command '$PROFILE'`. Skip
    if not on PATH.
- For each detected profile path: apply the existing
  migrate-if-matches-bundled-style + write-loader logic (no behavioural
  change per profile, just applied per shell).
- After registration, for each detected shell:
  - Run `Get-ExecutionPolicy -Scope CurrentUser` via that engine.
  - If `Restricted`, or `Undefined` with a `Restricted` `LocalMachine`
    fallback, prompt:
    > "Script execution is disabled for <pwsh 7 | Windows PowerShell 5.1>.
    > Set CurrentUser policy to RemoteSigned? [Y/n]"
  - If user accepts (Y / Enter), invoke
    `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` via that
    engine. Never silent, never default-yes for destructive options.

### `tstyles.ps1`

- Drop or lower `#Requires` to `5.1`.
- Remove `-Depth 32` from every `ConvertFrom-Json` call (parameter not
  supported in 5.1; default depth handling is sufficient for Windows
  Terminal's `settings.json`).
- Keep `-Depth 32` on `ConvertTo-Json` — supported in 5.1 and matters for
  round-trip fidelity.
- No other code changes — `$PSScriptRoot`, `$env:LOCALAPPDATA`,
  `[Console]::ReadKey`, `Add-Member`, `PSCustomObject`, etc. all work in 5.1.

### `apply.ps1`

- Same as `tstyles.ps1`: `#Requires` to 5.1, drop `-Depth` from
  `ConvertFrom-Json`.

### `styles/umbrella/profile.ps1`

- Define `$script:Esc = [char]27` once at top.
- Replace every `` `e[…]m `` with `"$($script:Esc)[…]m"` (`` `e `` only exists
  in pwsh 6+).
- PSReadLine block already wraps `Set-PSReadLineOption -PredictionSource` in
  try/catch — degrades cleanly on the older PSReadLine 2.0 that ships with
  WinPS 5.1.

### `README.md`

- Requirements section: "PowerShell 5.1 **or** PowerShell 7+".
- Install instructions: "Open a PowerShell tab (5.1 or 7) in Windows Terminal".
- New short "Execution Policy" subsection: explains the
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` requirement and notes
  the installer offers to apply it interactively.

## Data flow

1. User opens any PowerShell on a fresh PC, runs
   `iwr -useb …/install.ps1 | iex`.
2. `install.ps1` downloads + extracts to `%LOCALAPPDATA%\TerminalStyles\`
   (unchanged from today).
3. Installer probes `pwsh.exe` and `powershell.exe` on PATH; for each found,
   queries that engine's `$PROFILE`.
4. For each profile path found:
   1. If existing profile content exactly matches a bundled style's
      `profile.ps1`, back it up and migrate to `current-style.ps1` (existing
      logic, applied per shell).
   2. Inject (or replace) the `# ===== TerminalStyles BEGIN/END =====`
      loader block.
   3. Query the engine's `Get-ExecutionPolicy -Scope CurrentUser`. If
      blocking, prompt user; if accepted, set to `RemoteSigned` via that
      engine.
5. User restarts shell. The profile dot-sources
   `%LOCALAPPDATA%\TerminalStyles\tstyles.ps1`, which auto-loads
   `current-style.ps1` (active style's prompt) and defines `tstyles`.
6. `tstyles` works identically in both engines — same picker, same
   `settings.json` writes, same `current-style.ps1`.

## Error handling

- `pwsh.exe` not on PATH → skip pwsh 7 registration with a one-line note
  ("pwsh 7 not detected, skipping").
- `powershell.exe` not on PATH → skip WinPS 5.1 registration (vanishingly
  rare on Windows; same one-line note).
- Neither found → `throw` with a clear message.
- `Set-ExecutionPolicy` fails because `LocalMachine`/`MachinePolicy`
  overrides `CurrentUser` (e.g. corporate GPO) → catch the error and print
  the manual elevation command (`Start-Process pwsh -Verb RunAs
  -ArgumentList …`) rather than letting the install crash.
- All existing error handling in `tstyles.ps1` / `apply.ps1` is unchanged.

## Testing

Manual (no test framework in this repo):

- **On this PC (pwsh 7 + WinPS 5.1 both installed):** re-run install
  one-liner; verify loader block appears in both
  `Documents\PowerShell\…profile.ps1` and
  `Documents\WindowsPowerShell\…profile.ps1`; open each shell; run
  `tstyles`; arrow + Enter; confirm style applies and prompt loads cleanly.
- **In WinPS 5.1 specifically:** confirm umbrella prompt renders ANSI colors
  via `[char]27` (no literal `` `e `` in output).
- **Execution policy path:** temporarily set
  `Set-ExecutionPolicy -Scope CurrentUser Restricted` in 5.1; re-run
  installer; confirm prompt fires and applies fix when accepted.
- **Smoke on MCidron's PC:** run installer once; confirm the policy prompt
  resolves the original `PSSecurityException`.

## Known limitations

- **Migration matching is exact string equality.** If a user's existing
  `$PROFILE` was the old `` `e ``-based umbrella profile, after this change
  the bundled source uses `[char]27` so the match won't trigger and we'll
  just inject the loader block alongside (rather than migrating their
  profile out). Acceptable — the loader still wins and the user can re-run
  `tstyles` to reapply.
- **`ConvertTo-Json` output formatting differs subtly between 5.1 and 7.**
  Windows Terminal rewrites `settings.json` on its next save (existing
  README caveat), so this is fine in practice.
- **GPO-locked execution policy** cannot be overridden by the installer; we
  surface a clear instruction but cannot fix it.
