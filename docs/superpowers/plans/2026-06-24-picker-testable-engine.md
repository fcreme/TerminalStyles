# Picker Testable Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the `tstyles` picker's interactive loop into a testable, seam-injected engine (`Invoke-StylePickerLoop`) and lock its three correctness invariants (byte-exact Esc revert, Enter persists the chosen style, key-mash collapses to one write) with automated tests — with zero behavior change.

**Architecture:** Move the `while (-not $confirmed)` loop out of `Invoke-TerminalStyle` into a new internal function whose I/O, rendering, and input are injected as script-block seams. `Invoke-TerminalStyle` keeps all setup/teardown and wires the real seams; tests drive the engine with scripted keys and recording/real seams.

**Tech Stack:** PowerShell (Windows PowerShell 5.1 + PowerShell 7), Pester 5.

## Global Constraints

- Must pass on **both** Windows PowerShell 5.1 and PowerShell 7 (the CI matrix runs both).
- New function is **internal** (NOT added to `FunctionsToExport` in `TerminalStyles.psd1`); tests reach it via `InModuleScope TerminalStyles`, like the existing internal-function specs.
- All `settings.json` reads/writes use **UTF-8 no BOM** (`[System.Text.UTF8Encoding]::new($false)`); never use `Get-Content -Raw` for settings (ANSI-codepage corruption on 5.1).
- This is **behavior-preserving**: the existing **406** tests must stay green.
- Test fixtures live under `$TestDrive`; written with `[System.IO.File]::WriteAllText(..., [System.Text.UTF8Encoding]::new($false))`.
- Spec: `docs/superpowers/specs/2026-06-24-picker-testable-engine-design.md`.

---

## File Structure

- **Modify** `tstyles.ps1`:
  - **Add** `Invoke-StylePickerLoop` (new internal function) immediately above `function Invoke-TerminalStyle` (currently line ~2033).
  - **Refactor** the picker loop inside `Invoke-TerminalStyle` (currently lines ~2340–2491) to delegate to `Invoke-StylePickerLoop`.
- **Create** `tests/Invoke-StylePickerLoop.Tests.ps1` — engine unit + integration tests.

---

### Task 1: Create `Invoke-StylePickerLoop` + engine unit tests

**Files:**
- Modify: `tstyles.ps1` (add new function above `Invoke-TerminalStyle`, ~line 2033)
- Test: `tests/Invoke-StylePickerLoop.Tests.ps1` (create)

**Interfaces:**
- Produces: `Invoke-StylePickerLoop -StyleCount <int> [-StartIndex <int>] -ReadKey <scriptblock> -OnPreview <scriptblock> -OnRevert <scriptblock> [-OnDraw <scriptblock>] [-OnRetint <scriptblock>] [-OnIdle <scriptblock>]` → returns a hashtable `@{ Outcome = 'confirmed'|'cancelled'; Index = <int> }`.
  - `ReadKey` returns an object with a `.Key` property (a `[ConsoleKey]`), or `$null` when no key is currently available.
  - `OnPreview`, `OnRetint` are invoked as `& $cb $index`. `OnDraw` is invoked as `& $cb $index`. `OnRevert`, `OnIdle` take no args.

- [ ] **Step 1: Write the failing test file**

Create `tests/Invoke-StylePickerLoop.Tests.ps1`:

```powershell
# Pester 5 tests for Invoke-StylePickerLoop -- the seam-injected picker engine.
# Unit tests drive the loop with scripted keys + recording seams (no real I/O);
# integration tests (Task 2) wire the real settings writers.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Invoke-StylePickerLoop' {
    InModuleScope TerminalStyles {

        # Build a ReadKey stub from an array. Yields one element per call in
        # order; an element of $null models a momentarily-empty queue (drives
        # the debounce tail). After the array is consumed, returns Escape on
        # every further call so the loop can never hang.
        function New-KeyStub {
            param([object[]]$Keys)
            $state = @{ i = 0 }
            return {
                if ($state.i -lt $Keys.Count) {
                    $k = $Keys[$state.i]; $state.i++
                    if ($null -eq $k) { return $null }
                    return [pscustomobject]@{ Key = $k }
                }
                return [pscustomobject]@{ Key = [ConsoleKey]::Escape }
            }.GetNewClosure()
        }

        Context 'engine unit behavior' {

            It 'Up clamps at index 0 and applies nothing' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $keys = New-KeyStub @([ConsoleKey]::UpArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 0
                $applied.Count | Should -Be 0
            }

            It 'Down clamps at the last index' {
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 2 `
                    -ReadKey $keys -OnPreview { param($i) } -OnRevert { }
                $r.Index | Should -Be 2
            }

            It 'collapses a key-mash to a single apply at the final index' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow,
                                      [ConsoleKey]::DownArrow, $null, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 5 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 3
                $applied.Count | Should -Be 1
                $applied[0]    | Should -Be 3
            }

            It 'confirms at the start index with no apply when Enter is pressed first' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $keys = New-KeyStub @([ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 1 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 1
                $applied.Count | Should -Be 0
            }

            It 'Esc cancels: reverts once and applies nothing' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $reverts = @{ n = 0 }
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Escape)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { $reverts.n++ }
                $r.Outcome     | Should -Be 'cancelled'
                $reverts.n     | Should -Be 1
                $applied.Count | Should -Be 0
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Invoke-StylePickerLoop.Tests.ps1"`
Expected: FAIL — `Invoke-StylePickerLoop` is not recognized (CommandNotFoundException) in every `It`.

- [ ] **Step 3: Implement `Invoke-StylePickerLoop`**

In `tstyles.ps1`, immediately **above** `function Invoke-TerminalStyle {` (line ~2033), insert:

```powershell
function Invoke-StylePickerLoop {
    # The interactive picker's selection loop, with all I/O / rendering / input
    # injected as seams so it can be driven by tests. Owns ONLY the highlight
    # index, the pendingApply debounce, and key dispatch. Returns the outcome:
    #   @{ Outcome = 'confirmed' | 'cancelled'; Index = <int> }
    #
    # Seams:
    #   ReadKey   -> a key object with a .Key ([ConsoleKey]), or $null when the
    #                input queue is momentarily empty (drives the debounce tail).
    #   OnPreview -> & $OnPreview $index : the debounced settings.json write.
    #   OnRevert  -> & $OnRevert         : Esc -- restore original settings (+OSC reset).
    #   OnDraw    -> & $OnDraw $index    : render the menu at $index.
    #   OnRetint  -> & $OnRetint $index  : instant per-keystroke OSC color packet.
    #   OnIdle    -> & $OnIdle           : idle slice (prebuild / sleep).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$StyleCount,
        [int]$StartIndex = 0,
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$OnPreview,
        [Parameter(Mandatory)][scriptblock]$OnRevert,
        [scriptblock]$OnDraw   = {},
        [scriptblock]$OnRetint = {},
        [scriptblock]$OnIdle   = {}
    )

    $idx          = $StartIndex
    $pendingApply = -1
    $needsRedraw  = $true

    while ($true) {
        if ($needsRedraw) {
            & $OnDraw $idx
            $needsRedraw = $false
        }

        $key = & $ReadKey
        if ($null -ne $key) {
            switch ($key.Key) {
                'UpArrow' {
                    if ($idx -gt 0) {
                        $idx--; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'DownArrow' {
                    if ($idx -lt $StyleCount - 1) {
                        $idx++; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'Enter' {
                    if ($pendingApply -ge 0) {
                        & $OnPreview $pendingApply
                        $pendingApply = -1
                    }
                    return @{ Outcome = 'confirmed'; Index = $idx }
                }
                'Escape' {
                    & $OnRevert
                    return @{ Outcome = 'cancelled'; Index = $idx }
                }
            }
            continue
        }

        # Queue empty -- debounce tail: apply the latest pending preview once.
        if ($pendingApply -ge 0) {
            $applyIdx = $pendingApply
            $pendingApply = -1
            & $OnPreview $applyIdx
            continue
        }

        # Truly idle.
        & $OnIdle
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Invoke-StylePickerLoop.Tests.ps1"`
Expected: PASS — 5 tests in `engine unit behavior`.

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Invoke-StylePickerLoop.Tests.ps1
git commit -m "feat(picker): extract testable Invoke-StylePickerLoop engine + unit tests"
```

---

### Task 2: Integration tests — byte-exact revert + Enter persists

**Files:**
- Test: `tests/Invoke-StylePickerLoop.Tests.ps1` (add a Context)

**Interfaces:**
- Consumes: `Invoke-StylePickerLoop` (Task 1); `ConvertFrom-WTJson`, `Merge-StyleIntoSettings`, `Write-SettingsAtomic` (existing internal functions).

- [ ] **Step 1: Write the failing integration tests**

In `tests/Invoke-StylePickerLoop.Tests.ps1`, add this `Context` **inside** the `InModuleScope TerminalStyles { ... }` block, after the `'engine unit behavior'` context:

```powershell
        Context 'integration with real settings I/O' {

            BeforeEach {
                # Two fake styles so DownArrow can move 0 -> 1.
                $script:dirA = Join-Path $TestDrive 'styles\alpha'
                $script:dirB = Join-Path $TestDrive 'styles\beta'
                foreach ($d in @($script:dirA, $script:dirB)) {
                    New-Item -ItemType Directory -Path $d -Force | Out-Null
                }
                $enc = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText((Join-Path $script:dirA 'scheme.json'),
                    '{"name":"alpha","background":"#000000","foreground":"#ffffff"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirA 'theme.json'),
                    '{"colorScheme":"alpha"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirB 'scheme.json'),
                    '{"name":"beta","background":"#111111","foreground":"#eeeeee"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirB 'theme.json'),
                    '{"colorScheme":"beta"}', $enc)
                $script:styleDirs = @($script:dirA, $script:dirB)

                # Non-ASCII target profile name to lock the UTF-8/no-BOM round-trip.
                $script:target = 'Símbolo del sistema'
                $script:settingsPath = Join-Path $TestDrive 'settings.json'
                $original = '{"profiles":{"list":[{"name":"Símbolo del sistema","guid":"{abc}"}]}}'
                [System.IO.File]::WriteAllText($script:settingsPath, $original, $enc)
                # Read back exactly as the picker does (UTF-8, no BOM).
                $script:originalJson = [System.IO.File]::ReadAllText(
                    $script:settingsPath, [System.Text.UTF8Encoding]::new($false))

                # Real seams: a deferred merge+write preview, and a byte-exact revert.
                $script:onPreview = {
                    param($i)
                    $merged = ConvertFrom-WTJson $script:originalJson
                    $merged = Merge-StyleIntoSettings -Settings $merged -StyleDir $script:styleDirs[$i] `
                        -TargetName $script:target -BackgroundImage '' -BackgroundImageProvided $false
                    Write-SettingsAtomic -Path $script:settingsPath -Json ($merged | ConvertTo-Json -Depth 100)
                }
                $script:onRevert = {
                    Write-SettingsAtomic -Path $script:settingsPath -Json $script:originalJson
                }
            }

            It 'restores the byte-exact original settings.json on Esc (after a preview)' {
                $originalBytes = [System.IO.File]::ReadAllBytes($script:settingsPath)
                # Down -> (idle drains the preview, reformatting the file) -> Esc.
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, $null, [ConsoleKey]::Escape)
                $r = Invoke-StylePickerLoop -StyleCount 2 -StartIndex 0 `
                    -ReadKey $keys -OnPreview $script:onPreview -OnRevert $script:onRevert
                $r.Outcome | Should -Be 'cancelled'
                $afterBytes = [System.IO.File]::ReadAllBytes($script:settingsPath)
                # Byte-for-byte identical to the pre-picker state.
                (@(Compare-Object $originalBytes $afterBytes -SyncWindow 0).Count) | Should -Be 0
            }

            It 'persists the chosen style on Enter' {
                # Down -> Enter (Enter drains the pending preview for index 1 = beta).
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 2 -StartIndex 0 `
                    -ReadKey $keys -OnPreview $script:onPreview -OnRevert $script:onRevert
                $r.Outcome | Should -Be 'confirmed'
                $r.Index   | Should -Be 1
                $written = [System.IO.File]::ReadAllText(
                    $script:settingsPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                ($written.profiles.list | Where-Object name -eq $script:target).colorScheme | Should -Be 'beta'
                @($written.schemes | Where-Object { $_.name -eq 'beta' }).Count | Should -Be 1
            }
        }
```

- [ ] **Step 2: Run the integration tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Invoke-StylePickerLoop.Tests.ps1"`
Expected: PASS — all 7 tests (5 unit + 2 integration). The engine already exists from Task 1, so these pass immediately and prove the real-I/O invariants.

> Note: these tests are TDD-style "characterization" tests written against the just-built engine; they would have failed in Task 1 (no engine) and codify the byte-exact and persist invariants now.

- [ ] **Step 3: Commit**

```bash
git add tests/Invoke-StylePickerLoop.Tests.ps1
git commit -m "test(picker): byte-exact revert + Enter-persists integration tests"
```

---

### Task 3: Refactor `Invoke-TerminalStyle` to delegate to the engine

**Files:**
- Modify: `tstyles.ps1` — `Invoke-TerminalStyle` picker section (currently lines ~2317–2491)

**Interfaces:**
- Consumes: `Invoke-StylePickerLoop` (Task 1).

This task changes no logic — it replaces the inline loop with seam callbacks that call the engine, preserving exact behavior. The safety net is the full suite (406 existing + 7 new) staying green.

- [ ] **Step 1: Parameterize `$drawMenu` on the index**

The engine calls `& $OnDraw $idx`, so `$drawMenu` must take the index as a parameter instead of closing over the loop's `$idx`.

Find (line ~2317):

```powershell
        $drawMenu = {
            [Console]::SetCursorPosition(0, $renderHomeY)
```

Replace with:

```powershell
        $drawMenu = {
            param($idx)
            [Console]::SetCursorPosition(0, $renderHomeY)
```

(The rest of `$drawMenu` is unchanged — it already reads `$idx` for the highlight.)

- [ ] **Step 2: Replace the loop scaffolding + while-loop with the engine call**

Find the block that starts at `$needsRedraw = $true` (line ~2355) and runs through the end of the `while (-not $confirmed) { ... }` loop (the closing brace at line ~2431, immediately before the `# Confirmed -- maybe install profile.ps1` comment).

Replace that entire block with:

```powershell
        # Per-keystroke instant retint (OSC color packet). The deferred
        # settings.json write is $applyTheme, passed as -OnPreview.
        $onRetint = { param($i) [Console]::Out.Write($oscPackets[$i]) }

        # Esc: restore the byte-exact original settings.json and clear the live
        # OSC retint so the cancelled preview's colors don't linger.
        $onRevert = {
            Write-SettingsAtomic -Path $settingsPath -Json $originalJson
            [Console]::Out.Write((Get-OscResetPacket))
        }

        # Idle slice: prebuild the next uncached resolved theme's merged JSON,
        # else sleep briefly. (Verbatim from the old idle branch.)
        $onIdle = {
            $nextPrebuild = -1
            for ($j = 0; $j -lt $styles.Count; $j++) {
                if ($mergedCache.ContainsKey($j)) { continue }
                if (-not (Test-StyleResolved -StyleDir $styles[$j].FullName)) { continue }
                $nextPrebuild = $j
                break
            }
            if ($nextPrebuild -ge 0) {
                $pp = ConvertFrom-WTJson $originalJson
                $pp = Merge-StyleIntoSettings -Settings $pp -StyleDir $styles[$nextPrebuild].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $mergedCache[$nextPrebuild] = $pp | ConvertTo-Json -Depth 100
            } else {
                Start-Sleep -Milliseconds 50
            }
        }

        # Real input seam: read a key if one is queued, else $null.
        $readKey = { if ([Console]::KeyAvailable) { [Console]::ReadKey($true) } else { $null } }

        $result = Invoke-StylePickerLoop -StyleCount $styles.Count -StartIndex $idx `
            -ReadKey $readKey -OnPreview $applyTheme -OnRevert $onRevert `
            -OnDraw $drawMenu -OnRetint $onRetint -OnIdle $onIdle

        if ($result.Outcome -eq 'cancelled') {
            Clear-Host
            Write-Host "Reverted." -ForegroundColor Yellow
            return
        }

        $idx       = $result.Index
        $confirmed = $true
```

This preserves behavior: the `$applyTheme`, `$drawMenu`, and `$oscPackets` definitions above stay; the Esc path's settings-restore + OSC-reset moves into `$onRevert`; the "Reverted." message moves just after the engine returns `cancelled`; `$confirmed` is set so the `finally` block restores the window title only on cancel (unchanged net behavior).

- [ ] **Step 3: Run the full suite to verify no regression**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests"`
Expected: PASS — **413** tests (406 prior + 7 new), 0 failures.

- [ ] **Step 4: Cross-engine check on Windows PowerShell 5.1**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path tests"`
Expected: PASS — 413 tests, 0 failures (confirms 5.1 compatibility of the new code).

- [ ] **Step 5: Manual smoke (visual confirmation the picker still works)**

In an interactive Windows Terminal tab:
Run: `Import-Module ./TerminalStyles.psd1 -Force -DisableNameChecking; tstyles`
Expected: picker opens; Up/Down previews live; Enter keeps; Esc reverts to the prior look. (Skip if no interactive WT available; the automated suite is the gate.)

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1
git commit -m "refactor(picker): delegate Invoke-TerminalStyle loop to Invoke-StylePickerLoop"
```

---

## Self-Review

**Spec coverage:**
- Extract `Invoke-StylePickerLoop` with 6 seams + return contract → Task 1 (Step 3). ✓
- Behavior preservation (extract-method, 406 green) → Task 3 (Steps 3–4). ✓
- Unit invariants: Up-clamp, Down-clamp, mash-collapse, bare-Enter, Esc-cancels → Task 1 (Step 1), 5 tests. ✓
- Integration: byte-exact Esc revert (with non-ASCII fixture), Enter persists → Task 2. ✓
- New test file dot-sources/imports per repo convention → Task 1 (Step 1). ✓
- Internal function, not exported → not added to `FunctionsToExport`; reached via `InModuleScope`. ✓

**Placeholder scan:** No TBD/TODO; every code/test step has complete code; commands have expected output. ✓

**Type/name consistency:** `Invoke-StylePickerLoop` parameter names (`StyleCount`, `StartIndex`, `ReadKey`, `OnPreview`, `OnRevert`, `OnDraw`, `OnRetint`, `OnIdle`) and the return shape (`@{ Outcome; Index }`) match across the engine, the unit tests, the integration tests, and the `Invoke-TerminalStyle` call site. `New-KeyStub` signature consistent across all tests. ✓
