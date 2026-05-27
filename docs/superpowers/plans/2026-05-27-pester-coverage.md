# Pester Coverage for Throttle + Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two self-contained Pester 5 test files locking in the throttle and backup invariants — `tests/Test-UpdateAvailable.Tests.ps1` (six tests) and `tests/Apply-StyleDirect-Backup.Tests.ps1` (four tests). No production code changes; CI workflow already runs `Invoke-Pester -Path tests` and auto-discovers new files.

**Architecture:** Mirror the existing `tests/Get-SchemeSwatch.Tests.ps1` pattern: `BeforeAll { . tstyles.ps1 *> $null }`, `BeforeEach` to set `$script:TStylesRoot = $TestDrive`, heavy use of Pester 5's `Mock` cmdlet for network (`Invoke-RestMethod`) and filesystem (`Copy-Item`, `Find-WTSettingsPath`, etc.). Each test file is self-contained — no shared helper module.

**Tech Stack:** Pester 5.x (installed by CI via `Install-PSResource`, locally via `Install-PSResource -Name Pester -Version '[5.0.0,)' -TrustRepository`). PowerShell 5.1+. No new modules.

**Spec:** `docs/superpowers/specs/2026-05-27-pester-coverage-design.md`

---

## File Structure

Two new files under `tests/`. No production code changes. Both files run alongside `tests/Get-SchemeSwatch.Tests.ps1` via the existing CI workflow.

- **Create:** `tests/Test-UpdateAvailable.Tests.ps1` — six tests covering throttle behavior (fresh stamp, stale stamp, missing stamp, corrupt stamp self-heal, API-failure-still-writes-stamp, update-available SHA pair).
- **Create:** `tests/Apply-StyleDirect-Backup.Tests.ps1` — four tests covering backup behavior (bak captures prior state, rolling overwrite, Copy-Item failure path, correct destination path).
- **No change:** `tests/Get-SchemeSwatch.Tests.ps1`, `tstyles.ps1`, `apply.ps1`, `.github/workflows/test.yml`, `README.md`.

---

## Task 1: Create `tests/Test-UpdateAvailable.Tests.ps1`

**Files:**
- Create: `tests/Test-UpdateAvailable.Tests.ps1`

The throttle test file. Six `It` blocks inside one `Describe`. Mocks `Invoke-RestMethod` per test so no real network calls fire. Uses `$TestDrive` for the stamp file and SHA file so cleanup is automatic.

- [ ] **Step 1: Create the test file**

Create `tests/Test-UpdateAvailable.Tests.ps1` with this exact content:

```powershell
# Pester 5 tests for Test-UpdateAvailable (the 24h-throttled update check).
#
# Locks in the throttle invariants from
# docs/superpowers/specs/2026-05-27-update-check-throttle-design.md:
#   - Fresh stamp short-circuits the API call entirely (no IRM invocation).
#   - Stale / missing stamp triggers the API call and writes a fresh stamp.
#   - Corrupt stamp falls through and self-heals (overwritten with valid value).
#   - API failure still writes the stamp -- the bug that motivated the spec
#     was an offline machine retrying the 2s timeout on every invocation.
#   - Update-available returns abbreviated 7-char SHA pair.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # Dot-source tstyles.ps1 to bring Test-UpdateAvailable into scope.
    # Suppress its load-time output so the test runner stays clean.
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Test-UpdateAvailable' {
    BeforeEach {
        # Redirect file I/O to a per-test temp dir so we never touch the
        # user's real .last-update-check or .installed-sha files.
        $script:TStylesRoot = $TestDrive
        $stampFile = Join-Path $TestDrive '.last-update-check'
        $shaFile   = Join-Path $TestDrive '.installed-sha'
        Remove-Item $stampFile -ErrorAction SilentlyContinue
        Remove-Item $shaFile   -ErrorAction SilentlyContinue
    }

    It 'returns $null and skips the API when the stamp is fresh (< 24h)' {
        $fresh = (Get-Date).AddMinutes(-30).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $fresh, [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { throw 'API should NOT be called inside the throttle window' }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'fires the API call when the stamp is stale (> 24h)' {
        $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }   # matches installed SHA

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty                    # SHA matches, no update
        Should -Invoke Invoke-RestMethod -Times 1
        Test-Path $stampFile | Should -BeTrue              # stamp rewritten
    }

    It 'fires the API call when no stamp file exists' {
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 1
        Test-Path $stampFile | Should -BeTrue
    }

    It 'self-heals on corrupt stamp (unparseable contents)' {
        [System.IO.File]::WriteAllText($stampFile, 'garbage not a date', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

        { Test-UpdateAvailable } | Should -Not -Throw

        Should -Invoke Invoke-RestMethod -Times 1
        # Stamp was overwritten with a valid timestamp
        $written = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false))
        { [datetime]::Parse($written, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } | Should -Not -Throw
    }

    It 'still writes the stamp when the API call fails' {
        # THE key invariant: without write-on-failure, an offline machine
        # would retry the 2s timeout on every single tstyles invocation.
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { throw 'simulated network failure' }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Test-Path $stampFile | Should -BeTrue
    }

    It 'returns the abbreviated SHA pair when remote SHA differs from installed' {
        $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, '0000000000000000000000000000000000000000', [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = 'abc123def4567aaaaaaaaaaaaaaaaaaaaaaaaaaa' } }

        $result = Test-UpdateAvailable

        $result | Should -Not -BeNullOrEmpty
        $result.Installed | Should -Be '0000000'
        $result.Remote    | Should -Be 'abc123d'
    }
}
```

Use the `Write` tool with the absolute path `C:\Users\felip\dotfiles\tests\Test-UpdateAvailable.Tests.ps1`. The `tests/` directory already exists (from `Get-SchemeSwatch.Tests.ps1`).

- [ ] **Step 2: Run the new test file to confirm it passes**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-UpdateAvailable.Tests.ps1 -Output Detailed"
```

Expected: 6 tests, 6 passed, 0 failed. Output looks like:

```
Describing Test-UpdateAvailable
  [+] returns $null and skips the API when the stamp is fresh (< 24h)  XXms
  [+] fires the API call when the stamp is stale (> 24h)               XXms
  [+] fires the API call when no stamp file exists                     XXms
  [+] self-heals on corrupt stamp (unparseable contents)               XXms
  [+] still writes the stamp when the API call fails                   XXms
  [+] returns the abbreviated SHA pair when remote SHA differs from installed  XXms
Tests completed in XXms
Tests Passed: 6, Failed: 0, Skipped: 0 NotRun: 0
```

If any test fails, the most likely cause is a mismatch between the
mock signature and the real `Invoke-RestMethod` call shape inside
`Test-UpdateAvailable`. Cross-reference with `tstyles.ps1:100-152` —
the real call is:

```powershell
Invoke-RestMethod -Uri '...' -Headers @{ 'User-Agent' = '...' } -TimeoutSec 2 -ErrorAction Stop
```

A bare `Mock Invoke-RestMethod { @{ sha = ... } }` handles all those
parameters because Pester mocks accept any parameter set the real
function would accept. If the mock isn't being invoked, check that
`$script:TStylesRoot` is actually pointing at `$TestDrive` (write a
quick `Write-Host $script:TStylesRoot` inside one test to diagnose).

- [ ] **Step 3: Deliberately break the throttle invariant to verify the test catches it**

This is the "test the test" step. Open `tstyles.ps1` and temporarily
comment out the timestamp-write block (lines roughly 142-146):

```powershell
    # try {
    #     $now = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    #     [System.IO.File]::WriteAllText($stampFile, $now, [System.Text.UTF8Encoding]::new($false))
    # } catch { }
```

Re-run:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-UpdateAvailable.Tests.ps1 -Output Detailed"
```

Expected: at least the "still writes the stamp when the API call fails"
test fails (and probably "fires the API call when no stamp file exists"
and "fires the API call when the stamp is stale" too). This proves
the test is wired to the right invariant.

**Critical: revert your comment-out before committing.** Run:

```powershell
git diff tstyles.ps1
```

Expected: **no changes**. If you see your comment-outs, restore the
original via `git checkout tstyles.ps1`.

- [ ] **Step 4: Commit**

```bash
git add tests/Test-UpdateAvailable.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Pester tests for Test-UpdateAvailable throttle

Six tests covering the 24h throttle invariants from
docs/superpowers/specs/2026-05-27-update-check-throttle-design.md:

- Fresh stamp short-circuits (no API call).
- Stale / missing stamp triggers the API call and rewrites the stamp.
- Corrupt stamp self-heals.
- API failure still writes the stamp (the key correctness bit -- the
  bug that motivated the spec was offline machines retrying the 2s
  timeout on every invocation).
- Update-available returns the abbreviated 7-char SHA pair.

Mocks Invoke-RestMethod per test; no real network calls. Uses
$TestDrive for stamp file and .installed-sha so cleanup is automatic.
EOF
)"
```

---

## Task 2: Create `tests/Apply-StyleDirect-Backup.Tests.ps1`

**Files:**
- Create: `tests/Apply-StyleDirect-Backup.Tests.ps1`

The backup test file. Four `It` blocks inside one `Describe`. Heavy mocking (`Find-WTSettingsPath`, `Merge-StyleIntoSettings`, `Write-SettingsFile`, `Show-UpdateNoticeIfAvailable`) because we're testing only the backup block, not the real merge or write.

- [ ] **Step 1: Create the test file**

Create `tests/Apply-StyleDirect-Backup.Tests.ps1` with this exact content:

```powershell
# Pester 5 tests for Apply-StyleDirect's rolling settings.json.bak.
#
# Locks in the backup invariants from
# docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md:
#   - .bak captures the PRIOR state (not the merged state).
#   - .bak rolls (overwrites) on every direct apply.
#   - Copy-Item failure prints a yellow warning and lets the function
#     continue past the failure -- doesn't block the apply.
#   - .bak is written next to settings.json as "<settingsPath>.bak"
#     (not in a temp dir, not anywhere else).
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # Dot-source tstyles.ps1 to bring Apply-StyleDirect into scope.
    # Suppress its load-time output so the test runner stays clean.
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Apply-StyleDirect backup behavior' {
    BeforeEach {
        # Heavy mocking: no real settings.json mutation, no real merge,
        # no real network. We're testing the backup block in isolation.
        $script:TStylesRoot = $TestDrive

        # Fake settings.json with known content -- the backup should capture
        # this exact byte sequence before any mutation happens.
        $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
        $initialContent = '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}'
        [System.IO.File]::WriteAllText($script:fakeSettings, $initialContent, [System.Text.UTF8Encoding]::new($false))

        # Fake style directory so the StyleName-not-found early-exit doesn't fire
        $script:styleDir = Join-Path $TestDrive 'styles\fakeStyle'
        New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $script:styleDir 'scheme.json'),
            '{"name":"fakeScheme"}',
            [System.Text.UTF8Encoding]::new($false)
        )

        # Mock everything around the backup block so only the backup runs for real
        Mock Find-WTSettingsPath        { $script:fakeSettings }
        Mock Show-UpdateNoticeIfAvailable {}                          # skip the throttle path
        Mock Get-CurrentWTProfileName   { 'PowerShell' }
        Mock Merge-StyleIntoSettings    { param($Settings) $Settings } # passthrough, no real merge
        Mock Write-SettingsFile         {}                            # no real write
    }

    It 'writes settings.json.bak with the prior contents before merging' {
        $initial = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

        $bak = "$script:fakeSettings.bak"
        Test-Path $bak | Should -BeTrue
        [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $initial
    }

    It 'rolls the .bak file on a second invocation' {
        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
        $bak = "$script:fakeSettings.bak"
        $firstBakHash = (Get-FileHash $bak).Hash

        # Simulate the prior apply actually changing settings.json (normally
        # Merge-StyleIntoSettings + Write-SettingsFile would, but we mocked
        # them, so mutate the source manually to make a different second-run
        # pre-state).
        [System.IO.File]::WriteAllText(
            $script:fakeSettings,
            '{"profiles":{"list":[{"name":"DIFFERENT","guid":"{y}"}]}}',
            [System.Text.UTF8Encoding]::new($false)
        )

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
        $secondBakHash = (Get-FileHash $bak).Hash

        $secondBakHash | Should -Not -Be $firstBakHash
    }

    It 'prints yellow warning and continues when Copy-Item throws' {
        # Force the backup to fail. Filter by destination path so we don't
        # accidentally break other Copy-Item calls deeper in the function
        # (e.g., the profile.ps1 copy).
        Mock Copy-Item { throw 'simulated permission denied' } `
            -ParameterFilter { $Destination -like '*.bak' }
        Mock Write-Host { }   # capture color/text via Should -Invoke

        { Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell' } | Should -Not -Throw

        Should -Invoke Write-Host -ParameterFilter {
            $ForegroundColor -eq 'Yellow' -and "$Object" -match 'could not write backup'
        } -Times 1

        # Function continued past the backup failure -- the merge + write
        # mocks were still invoked.
        Should -Invoke Write-SettingsFile -Times 1
    }

    It 'writes the backup as <settingsPath>.bak (not anywhere else)' {
        $expectedBak = "$script:fakeSettings.bak"

        # Spy on Copy-Item via -ParameterFilter
        Mock Copy-Item { } -ParameterFilter {
            $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
        }

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
        }
    }
}
```

Use the `Write` tool with absolute path `C:\Users\felip\dotfiles\tests\Apply-StyleDirect-Backup.Tests.ps1`.

Notes on the test code:

- **`$script:fakeSettings`** (not `$fakeSettings`) — Pester 5's
  `BeforeEach` variables are scoped to the `It` block by default, but
  using `$script:` makes them visible inside the `-ParameterFilter`
  closures, which run in a separate scope.
- **`Mock Copy-Item { } -ParameterFilter { $Destination -like '*.bak' }`**
  — the parameter filter scopes the mock to ONLY backup writes; if
  `Apply-StyleDirect` does any other `Copy-Item` (e.g. for
  `profile.ps1`), those fall through to the real cmdlet, which is what
  we want (no test pollution).
- **The fourth test mocks Copy-Item itself to a no-op** — this is fine
  because we're verifying it's invoked with the right args, not that
  it actually copies. The first test (which DOES verify the bak file
  exists on disk) leaves Copy-Item real.

- [ ] **Step 2: Run the new test file**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Apply-StyleDirect-Backup.Tests.ps1 -Output Detailed"
```

Expected: 4 tests, 4 passed.

If a test fails with `The term 'Apply-StyleDirect' is not recognized`,
the dot-source in `BeforeAll` didn't expose the function. Verify with:

```powershell
pwsh -NoProfile -Command ". .\tstyles.ps1 *> `$null; Get-Command Apply-StyleDirect"
```

Expected: prints `Function   Apply-StyleDirect    1.0.0.0    <unknown>`.

If a test fails because the backup is in the wrong location, double-check
the `$script:` prefix usage in `BeforeEach` — without it, the
`-ParameterFilter` closures can't see `$fakeSettings`.

If the fourth test ("writes the backup as <settingsPath>.bak") fails
with `Cannot find an overload for "Copy-Item"`, you've mocked too
narrowly; widen the parameter filter or set a catch-all `Mock Copy-Item { }`
in `BeforeEach` and override per-test.

- [ ] **Step 3: Deliberately break the backup invariant to verify the test catches it**

Open `tstyles.ps1` and temporarily reorder so the backup happens AFTER
the merge (this would defeat the entire point). Find the new block at
roughly lines 491-504 and move it to AFTER `Write-SettingsFile`
(roughly line 507 in the post-change file). The exact edit is:

```powershell
    # MOVED TO BREAK THE TEST: backup AFTER merge (incorrect)
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }
```

Re-run:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Apply-StyleDirect-Backup.Tests.ps1 -Output Detailed"
```

Expected: "writes settings.json.bak with the prior contents before
merging" fails — `.bak` would now contain the post-merge content
(which is the same as the pre because we passthrough the merge mock,
so actually this specific failure might not surface...). More reliably,
break the test by removing the `try/catch` entirely or by removing the
`-Force` flag (which makes the second invocation throw because `.bak`
already exists). Either of those breaks the third test "prints yellow
warning and continues when Copy-Item throws" because the warning path
no longer exists.

**Critical: revert your edit before committing.** Run:

```powershell
git diff tstyles.ps1
```

Expected: **no changes**. If you see your edits, run `git checkout tstyles.ps1`.

- [ ] **Step 4: Commit**

```bash
git add tests/Apply-StyleDirect-Backup.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Pester tests for Apply-StyleDirect rolling backup

Four tests covering the backup invariants from
docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md:

- .bak captures the prior settings.json contents (write-before-mutate
  invariant).
- .bak rolls (overwrites) on the second direct apply.
- Copy-Item failure prints yellow warning and lets the function
  continue past it -- doesn't block the apply.
- .bak is written next to settings.json as "<settingsPath>.bak".

Mocks Find-WTSettingsPath, Show-UpdateNoticeIfAvailable,
Get-CurrentWTProfileName, Merge-StyleIntoSettings, and Write-SettingsFile
so only the backup block runs for real. Uses $TestDrive so cleanup is
automatic.
EOF
)"
```

---

## Task 3: Run the full test suite + push

**Files:** None modified. Validation + push.

- [ ] **Step 1: Run all three test files together**

This is the same `Invoke-Pester` invocation CI uses, run locally:

```powershell
pwsh -NoProfile -Command "$config = New-PesterConfiguration; $config.Run.Path = 'tests'; $config.Run.Exit = $true; $config.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration $config"
```

Expected: at least 3 files discovered (`Get-SchemeSwatch.Tests.ps1`,
`Test-UpdateAvailable.Tests.ps1`, `Apply-StyleDirect-Backup.Tests.ps1`),
all tests pass.

Approximate counts:
- `Get-SchemeSwatch.Tests.ps1`: 2 tests per theme × 16 themes + 1 cross-theme = 33 tests.
- `Test-UpdateAvailable.Tests.ps1`: 6 tests.
- `Apply-StyleDirect-Backup.Tests.ps1`: 4 tests.
- **Total: 43 tests, all passing.**

If the run hangs (rare but possible if a mock leaks and a real
`Invoke-RestMethod` fires against api.github.com), Ctrl-C and check
the mock setup in the newly-failing test.

- [ ] **Step 2: Check branch state**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Commits in order:

1. `Add Pester tests for Apply-StyleDirect rolling backup` (Task 2)
2. `Add Pester tests for Test-UpdateAvailable throttle` (Task 1)
3. `Spec: Pester coverage for throttle + backup` (already committed during brainstorming)

- [ ] **Step 3: Push**

```bash
git push origin main
```

Expected: `ddaeac3..<HEAD-sha>  main -> main` or similar.

- [ ] **Step 4: Confirm CI green**

The push triggers `.github/workflows/test.yml`. After ~30-60s the run
finishes. If `gh` is authenticated locally:

```bash
gh run list --limit 1
gh run view --log
```

If `gh` isn't authenticated, just check
`https://github.com/fcreme/TerminalStyles/actions` in a browser.

Expected: the new run is green, with all 43 tests passing. This
**also validates the `Install-PSResource` CI fix end-to-end** —
previously CI was failing on the Pester install step.

If CI is red, common causes:
- `Install-PSResource` syntax not recognized (impossible on
  `windows-latest`, but verify with `pwsh --version` in CI logs)
- A test that relies on Windows-locale-specific date parsing
  (the spec mandated `InvariantCulture`, so this should be safe)
- File-path separators (`$TestDrive` is Windows-style, no issue here)

---

## Self-Review Notes

Spec coverage:

- Spec lists 6 throttle test cases → Task 1 has 6 `It` blocks (one per case).
- Spec lists 4 backup test cases → Task 2 has 4 `It` blocks (one per case).
- "Tests are hermetic" → both tasks use `$TestDrive`, mock `Invoke-RestMethod` and `Copy-Item`, never touch real `%LOCALAPPDATA%`.
- "Both new test files run via the existing CI workflow" → Task 3 validates with `Invoke-Pester -Path tests`.
- "Validates the `Install-PSResource` CI fix end-to-end" → Task 3 Step 4.
- "No shared helper module" → both task files have inline `BeforeEach` setup.
- Spec non-goal "code-coverage measurement" → not in plan, correctly absent.
- Spec non-goal "tests for `Merge-StyleIntoSettings`" → not in plan, correctly absent.
- Spec non-goal "changes to `tstyles.ps1`" → no production-code edits in any task.

Type / signature consistency:

- Variable names: `$stampFile`, `$shaFile`, `$fakeSettings`, `$styleDir`, `$bak` — used consistently within each test file.
- `$script:` prefix on `$fakeSettings` and `$styleDir` in Task 2 (visible to `-ParameterFilter` closures).
- `[System.IO.File]::WriteAllText(..., [System.Text.UTF8Encoding]::new($false))` and `[System.Globalization.CultureInfo]::InvariantCulture` — used consistently (matches `tstyles.ps1` conventions).
- Mock signatures match the real cmdlets' parameter sets (verified mentally against `tstyles.ps1:117-122` for IRM and `tstyles.ps1:498-504` for Copy-Item).

No placeholders. All commands have expected output. All code blocks are complete and runnable.

One judgment call worth flagging:

- **Step 3 of both Task 1 and Task 2 is a "deliberately break the production code to test the test" step.** This is genuinely useful for confidence but adds friction. If the implementer is short on time, they can skip Step 3 of both tasks and rely on the green-on-first-try result as evidence (with the explicit understanding that "green on first try" doesn't prove the test catches the right regression). Recommend running Step 3 at least once on one of the two test files just to validate the methodology.
