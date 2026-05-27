# Pester Coverage for Throttle + Backup — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Builds on:** [update-check throttle](2026-05-27-update-check-throttle-design.md),
[direct-apply backup](2026-05-27-direct-apply-backup-design.md)

## Problem

Both recently-shipped safety features explicitly deferred Pester
coverage:

- `2026-05-27-update-check-throttle-design.md` non-goals: *"Pester test
  for the throttle. Deferred — manual testing per the 2026-05-26 spec's
  test list is sufficient to ship."*
- `2026-05-27-direct-apply-backup-design.md` non-goals: *"Pester test
  coverage. Defer with the throttle test."*

The deferral was reasonable — manual smoke tests covered each at ship
time. But neither feature now has a regression test, and both have
non-obvious invariants worth locking in:

- **Throttle:** the timestamp write must happen on API failure (not just
  success), or offline machines retry the 2s timeout on every invocation.
- **Backup:** the `Copy-Item` must happen before `Merge-StyleIntoSettings`,
  not after (or the bak captures the mutated state, defeating the point).
  The `try/catch` around it must allow the function to continue on
  failure.

The CI Pester install was broken until `ddaeac3` (now using
`Install-PSResource`); that fix is also untested end-to-end because the
existing `Get-SchemeSwatch.Tests.ps1` doesn't exercise the new install
path differently from the old one. Adding test files validates the CI
fix while also locking in the throttle + backup invariants.

## Goals

- One Pester test file per function-under-test, mirroring the existing
  `tests/Get-SchemeSwatch.Tests.ps1` pattern.
- Throttle test covers: fresh stamp short-circuits the API call, stale
  stamp triggers the API call, missing stamp triggers it, corrupt stamp
  self-heals, API failure still writes the stamp, update-available
  returns the abbreviated SHA pair.
- Backup test covers: bak captures the pre-mutation state, bak rolls
  on the second invocation, Copy-Item failure prints yellow + lets the
  function continue, bak is written next to settings.json with the
  correct `.bak` suffix.
- Tests are hermetic: no network, no real `%LOCALAPPDATA%` writes, no
  real `settings.json` mutation. Heavy use of Pester 5's `Mock` cmdlet
  and `$TestDrive`.
- Both new test files run as part of `Invoke-Pester -Path tests`, which
  the CI workflow at `.github/workflows/test.yml` already runs on every
  push and PR.

## Non-goals

- Tests for `Merge-StyleIntoSettings` (the bg state machine). Bigger
  scope; deserves its own design pass given the three-action state
  machine (skip / remove / apply) and the bundled-bg resolution
  three-tier (local → negative-cache → lazy-fetch).
- Tests for `Get-CurrentStyleName` (byte-compare detection). Tied to
  the separate "persist active style as metadata" improvement
  candidate; better to add tests when we replace the detection rather
  than locking in the brittle current behavior.
- Integration tests that invoke real `tstyles <name>` against a real
  WT install. Out of scope; would need a runner with Windows Terminal
  installed.
- A shared `tests/TestHelpers.psm1`. The two new test files have
  ~5 lines of mock-setup duplication; the existing
  `Get-SchemeSwatch.Tests.ps1` is also self-contained. Sticking with
  one-file-reads-top-to-bottom matches the project's pattern.
- Code-coverage measurement (`Invoke-Pester -CodeCoverage`). Useful
  later, but adds noise to CI output now.
- Changes to `tstyles.ps1`. The functions are testable as-is via
  `Mock`.

## Architecture

Two self-contained Pester 5 test files under `tests/`, each:

1. `BeforeAll { . tstyles.ps1 *> $null }` — dot-source the library
   into the test scope, suppressing load-time output (matches the
   existing test).
2. `BeforeEach { $script:TStylesRoot = $TestDrive }` — redirect file
   I/O to Pester's auto-cleaned temp dir.
3. `Mock` for `Invoke-RestMethod` / `Copy-Item` / `Find-WTSettingsPath`
   / `Show-UpdateNoticeIfAvailable` as needed per test.
4. Tests as straight `It` blocks (parameterize only when it materially
   reduces duplication).

The CI workflow (`.github/workflows/test.yml`) already runs
`Invoke-Pester -Path tests`, so adding files under `tests/` picks them
up automatically.

## File-by-file changes

### `tests/Test-UpdateAvailable.Tests.ps1` (new)

Header matches the existing test:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
```

Structure:

```
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Test-UpdateAvailable' {
    BeforeEach {
        # Redirect file I/O to a per-test temp dir
        $script:TStylesRoot = $TestDrive
        $stampFile = Join-Path $TestDrive '.last-update-check'
        $shaFile   = Join-Path $TestDrive '.installed-sha'
    }

    It 'returns $null and skips the API when the stamp is fresh (< 24h)' { ... }
    It 'fires the API call when the stamp is stale (> 24h)' { ... }
    It 'fires the API call when no stamp file exists' { ... }
    It 'self-heals on corrupt stamp (unparseable contents)' { ... }
    It 'still writes the stamp when the API call fails' { ... }
    It 'returns the abbreviated SHA pair when remote != installed' { ... }
}
```

Test body sketches:

- **Fresh stamp:**
  ```
  $now = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
  [IO.File]::WriteAllText($stampFile, $now, [Text.UTF8Encoding]::new($false))
  Mock Invoke-RestMethod { throw "API should NOT be called" }
  $result = Test-UpdateAvailable
  $result | Should -BeNullOrEmpty
  Should -Invoke Invoke-RestMethod -Times 0
  ```

- **Stale stamp:**
  ```
  $stale = (Get-Date).AddHours(-25).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
  [IO.File]::WriteAllText($stampFile, $stale, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($shaFile, ('a' * 40), [Text.UTF8Encoding]::new($false))
  Mock Invoke-RestMethod { @{ sha = 'a' * 40 } }
  $result = Test-UpdateAvailable
  $result | Should -BeNullOrEmpty                # SHA matches, no notice
  Should -Invoke Invoke-RestMethod -Times 1
  (Test-Path $stampFile) | Should -BeTrue        # stamp was rewritten
  ```

- **API failure leaves stamp written** (the key correctness bit):
  ```
  Remove-Item $stampFile -ErrorAction SilentlyContinue
  [IO.File]::WriteAllText($shaFile, ('a' * 40), [Text.UTF8Encoding]::new($false))
  Mock Invoke-RestMethod { throw 'simulated DNS failure' }
  $result = Test-UpdateAvailable
  $result | Should -BeNullOrEmpty
  (Test-Path $stampFile) | Should -BeTrue        # THE invariant: stamp written even on failure
  ```

- **Update available:**
  ```
  $stale = (Get-Date).AddHours(-25).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
  [IO.File]::WriteAllText($stampFile, $stale, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($shaFile, '0000000000000000000000000000000000000000', [Text.UTF8Encoding]::new($false))
  Mock Invoke-RestMethod { @{ sha = 'abc123def4567aaaaaaaaaaaaaaaaaaaaaaaaaaa' } }
  $result = Test-UpdateAvailable
  $result.Installed | Should -Be '0000000'
  $result.Remote    | Should -Be 'abc123d'
  ```

Variable naming convention: `$stampFile`, `$shaFile`, `$result` (matches
the function's internal naming).

### `tests/Apply-StyleDirect-Backup.Tests.ps1` (new)

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Apply-StyleDirect backup behavior' {
    BeforeEach {
        # Heavy mocking: no real settings.json mutation, no real merge,
        # no real network. We're testing the backup block in isolation.
        $script:TStylesRoot = $TestDrive

        $fakeSettings = Join-Path $TestDrive 'fake-settings.json'
        '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}' |
            Set-Content -LiteralPath $fakeSettings -Encoding UTF8 -NoNewline

        # Fake style on disk so the StyleName check passes
        $styleDir = Join-Path $TestDrive 'styles\fakeStyle'
        New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
        '{"name":"fake"}' | Set-Content -LiteralPath (Join-Path $styleDir 'scheme.json') -Encoding UTF8 -NoNewline

        Mock Find-WTSettingsPath { $fakeSettings }
        Mock Show-UpdateNoticeIfAvailable {}   # skip the throttle path
        Mock Get-CurrentWTProfileName { 'PowerShell' }
        Mock Merge-StyleIntoSettings { $Settings }   # passthrough, no real merge
        Mock Write-SettingsFile {}                   # no real write
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:TStylesCurrent }  # skip dot-source
    }

    It 'writes settings.json.bak with the prior contents before merging' { ... }
    It 'rolls the .bak file on a second invocation' { ... }
    It 'prints yellow warning and continues when Copy-Item throws' { ... }
    It 'writes the backup as <settingsPath>.bak (not anywhere else)' { ... }
}
```

Test body sketches:

- **Bak captures prior state:**
  ```
  Apply-StyleDirect -StyleName fakeStyle
  $bak = "$fakeSettings.bak"
  (Test-Path $bak) | Should -BeTrue
  (Get-Content $bak -Raw) | Should -Be (Get-Content $fakeSettings -Raw)
  ```

- **Rolling overwrite:**
  ```
  Apply-StyleDirect -StyleName fakeStyle
  $firstBakHash = (Get-FileHash $bak).Hash

  # Mutate the fake settings.json between runs (simulates the prior apply
  # actually changing the file -- normally Merge+Write would, but we
  # mocked both, so do it manually).
  'second-run contents' | Set-Content -LiteralPath $fakeSettings -Encoding UTF8 -NoNewline

  Apply-StyleDirect -StyleName fakeStyle
  $secondBakHash = (Get-FileHash $bak).Hash
  $secondBakHash | Should -Not -Be $firstBakHash
  ```

- **Copy-Item failure path:**
  ```
  Mock Copy-Item { throw 'simulated permission denied' } -ParameterFilter { $Destination -like '*.bak' }
  Mock Write-Host {}    # capture the calls

  { Apply-StyleDirect -StyleName fakeStyle } | Should -Not -Throw
  Should -Invoke Write-Host -ParameterFilter {
      $ForegroundColor -eq 'Yellow' -and $Object -match 'could not write backup'
  } -Times 1
  Should -Invoke Write-SettingsFile -Times 1   # function continued past the failure
  ```

- **Backup destination is correct:**
  ```
  Mock Copy-Item {} -ParameterFilter { $Destination -eq "$fakeSettings.bak" }
  Apply-StyleDirect -StyleName fakeStyle
  Should -Invoke Copy-Item -ParameterFilter { $Destination -eq "$fakeSettings.bak" } -Times 1
  ```

Naming convention: `$fakeSettings`, `$bak`, `$styleDir` (concise, no
prefixes).

### `tests/Get-SchemeSwatch.Tests.ps1`

No change. Continues to run alongside the new files.

### `.github/workflows/test.yml`

No change. The `Invoke-Pester -Configuration $config` invocation at
line 30 picks up any `*.Tests.ps1` under `tests/` automatically.

### `tstyles.ps1`

No change. All target functions are testable via Mock as-is.

### `README.md`

No change. The "Adding your own style" section mentions tests
peripherally but doesn't promise specific test coverage; nothing to
update.

## Data flow

CI side:

1. Push to `main` (or a PR) triggers `.github/workflows/test.yml`.
2. The `Install Pester 5` step runs `Install-PSResource -Name Pester ...`
   (from `ddaeac3`).
3. The `Run Pester tests` step runs `Invoke-Pester` with
   `$config.Run.Path = 'tests'` and `$config.Run.Exit = $true`.
4. Pester discovers all three `*.Tests.ps1` files under `tests/` and
   runs them. Any failure exits non-zero, marking the run red.

Local-developer side:

1. `Invoke-Pester -Path tests` from the repo root runs the same three
   files.
2. Each file's `BeforeAll` dot-sources `tstyles.ps1` once.
3. Each `It` block's `BeforeEach` sets up mocks and temp files.
4. Pester auto-cleans `$TestDrive` after each test.

## Error handling

| Failure | Behavior |
|---|---|
| `Invoke-RestMethod` mock not set in a throttle test | Pester throws `Cannot find an overload...`; test fails closed. Acceptable — forces every test to be explicit about network behavior. |
| `Copy-Item` mock not set in a backup test | The real `Copy-Item` runs against `$TestDrive` paths; no real damage, but the test may falsely pass. Mitigation: always set the `Copy-Item` mock explicitly per test that exercises the backup path. |
| Test pollution between tests (e.g. one test's `Mock` leaks into the next) | Pester scopes mocks to the `Describe`/`It` they're declared in; this is a Pester-builtin guarantee. No mitigation needed beyond following the pattern. |
| `$script:TStylesRoot` set in `BeforeEach` leaks into other test files | Each `*.Tests.ps1` has its own `BeforeAll` dot-source; the script variable is scoped to that file's runspace. Pester runs each Describe in isolation. No leakage in practice. |
| Pester 5 missing on the local developer's machine | `#Requires -Modules @{...}` at the top of each test file produces a clear error. The CI runner installs Pester 5 explicitly. |
| Reading the stamp file fails (e.g. encoding mismatch) | The throttle test "self-heals on corrupt stamp" exercises this — function falls through to API path. No additional mitigation needed. |

## Testing

Manual (before declaring done):

- Run `pwsh -NoProfile -Command 'Invoke-Pester -Path tests'` from the
  repo root. All three test files run; all tests pass.
- Run with the `Detailed` verbosity that CI uses:
  `Invoke-Pester -Configuration (New-PesterConfiguration |
   ForEach-Object { $_.Run.Path = 'tests'; $_.Output.Verbosity =
   'Detailed'; $_ })`. Confirm each test prints its name and `Passed`
  status.
- Deliberately break one assertion (e.g. change `Should -Be 5` to
  `Should -Be 99` in the existing test) and confirm the test fails red.
  Revert.
- Deliberately break the throttle invariant (remove the
  `Set-Content $stampFile ...` line in `Test-UpdateAvailable`'s catch
  path) and confirm the "still writes the stamp when the API call fails"
  test catches it. Revert.

CI-side validation:

- Push the new test files; confirm the GitHub Actions run goes green.
  This also validates that the `Install-PSResource` fix in `ddaeac3`
  actually produces a usable Pester install (not just a
  successfully-installed-but-unusable one).

## Known limitations

- **Tests run against the dot-sourced library, not the installed copy.**
  If `%LOCALAPPDATA%\TerminalStyles\tstyles.ps1` diverges from the repo
  copy (e.g. user edits in place without committing), tests still pass
  while production behaves differently. Acceptable — same limitation as
  every Pester test in this repo.
- **No PSScriptAnalyzer.** Style/lint isn't checked. Out of scope for
  this cohort.
- **Heavy mocking means tests verify wiring, not end-to-end behavior.**
  The manual smoke tests in each shipped spec remain the source of
  truth for end-to-end correctness. Pester here is a regression net,
  not a substitute.
- **Mock leakage risk on `Copy-Item` and `Invoke-RestMethod`.** These
  are .NET-cmdlet mocks; if a test forgets to mock them, the real
  cmdlets run. Tests should always set explicit mocks for these two.
  A future "test helper" extraction could enforce this, but that
  contradicts the self-contained-files pattern; defer.
