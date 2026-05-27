# Update-Check Throttle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Throttle `Test-UpdateAvailable` so `api.github.com` is hit at most once per 24 hours per machine, via a new `.last-update-check` timestamp file. Closes the code/spec drift from `docs/superpowers/specs/2026-05-26-update-check-design.md`.

**Architecture:** Add a throttle gate at the top of `Test-UpdateAvailable` that reads `$TStylesRoot\.last-update-check`, an ISO-8601-`o` timestamp file. If parsed timestamp is < 24h old, return `$null` immediately (no API call, no notice). After every API attempt (success **or** failure), rewrite the timestamp so failure paths don't retry on every invocation. Update README wording so it stops claiming "every invocation." Flip both 2026-05-26 specs whose work has actually shipped from `Approved (pending implementation)` → `Implemented` status.

**Tech Stack:** PowerShell 5.1+ (single-source, both engines). No new dependencies. Pester 5 already in CI but not used by this plan (test deferred per spec).

**Spec:** `docs/superpowers/specs/2026-05-27-update-check-throttle-design.md`

---

## File Structure

Only one production code file is modified; the rest is repo hygiene.

- **Modify:** `tstyles.ps1` — replace the body of `Test-UpdateAvailable` (lines 100-131). The function signature, name, return shape, and all five call sites are unchanged.
- **Modify:** `README.md` — two one-line wording updates (lines 303-304 and 330-332).
- **Modify:** `docs/superpowers/specs/2026-05-26-update-check-design.md` — bump `**Status:**` line from `Approved (pending implementation)` to `Implemented 2026-05-27` once this plan ships.
- **Verify (probable status bump):** `docs/superpowers/specs/2026-05-26-bundled-style-backgrounds-design.md` and `docs/superpowers/specs/2026-05-26-dual-shell-support-design.md` — both still say `Approved (pending implementation)`. Audit each against the current code; flip whichever has shipped. This is bundled into the same PR because it's the same class of fix (status hygiene on the 2026-05-26 cohort).
- **No change:** `install.ps1` (already writes `.installed-sha` at line 115). The 5 callers of `Show-UpdateNoticeIfAvailable` (`tstyles.ps1:372, 398, 420, 452, 600`). `apply.ps1`. The `tests/` directory.

---

## Task 1: Add the throttle gate to `Test-UpdateAvailable`

**Files:**
- Modify: `tstyles.ps1:100-131`

The throttle is one self-contained block at the top of the function plus one self-contained block right before the final `if` statement. The current API-call block stays byte-identical (same URL, same `User-Agent`, same `-TimeoutSec 2`, same `try/catch`).

- [ ] **Step 1: Replace the function body**

Open `tstyles.ps1`. Find the existing `function Test-UpdateAvailable {` block (currently lines 100-131). Replace **the entire function** (from `function Test-UpdateAvailable {` through the matching closing `}`) with this exact block:

```powershell
function Test-UpdateAvailable {
    # Returns a pscustomobject with short SHAs if a newer commit is available
    # on origin/main, or $null if local already matches / no .installed-sha /
    # we're inside the 24h throttle window / the API call fails.
    #
    # Throttled to <= 1 HTTP request per 24 hours per machine via
    # .last-update-check. The timestamp is rewritten on every attempt
    # (success or failure), so an offline machine doesn't retry the
    # 2s timeout on every single tstyles invocation.
    $shaFile   = Join-Path $script:TStylesRoot '.installed-sha'
    $stampFile = Join-Path $script:TStylesRoot '.last-update-check'

    # --- Throttle gate ---
    # If the stamp file is present and parses as a datetime less than 24h old,
    # skip everything below. Unparseable / missing -> fall through and the
    # timestamp write at the end will overwrite with a valid value (self-heal).
    if (Test-Path -LiteralPath $stampFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false)).Trim()
            $stamp = [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (((Get-Date) - $stamp).TotalHours -lt 24) { return $null }
        } catch { }
    }

    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        $resp = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
            -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
            -TimeoutSec 2 -ErrorAction Stop
        $remote = $resp.sha
    } catch { }

    # --- Throttle write ---
    # Always write the timestamp, even on API failure. Without this, an
    # offline machine would retry the 2s timeout on every invocation.
    try {
        $now = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $now, [System.Text.UTF8Encoding]::new($false))
    } catch { }

    if ($remote -and $remote -ne $installed) {
        return [pscustomobject]@{
            Installed = $installed.Substring(0, [Math]::Min(7, $installed.Length))
            Remote    = $remote.Substring(0, [Math]::Min(7, $remote.Length))
        }
    }
    return $null
}
```

Why these specific choices, against the spec snippet that used `Set-Content`:

- `[System.IO.File]::WriteAllText` + explicit UTF-8 without BOM matches the convention used everywhere else in this file (see the `.installed-sha` read at the current line 112 and the `settings.json` writes). Avoids the WinPS 5.1 `Set-Content` ANSI-codepage gotcha that's already called out in `tstyles.ps1:618-622`.
- `[datetime]::Parse(..., InvariantCulture, RoundtripKind)` is the matching parser for the `'o'` format. Using bare `[datetime]::Parse($raw)` is locale-sensitive on WinPS 5.1 and would misparse on Spanish/German locales — exactly the kind of bug `tstyles.ps1:618-622` complains about for `Get-Content -Raw`.
- The `try`/`catch` for the timestamp write swallows disk-full / read-only / AV failures. Spec-mandated.

- [ ] **Step 2: Smoke-test the function in a scratch shell**

Open a new pwsh tab. Run:

```powershell
. "$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"   # or the local repo path during dev
Remove-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" -ErrorAction SilentlyContinue
Test-UpdateAvailable                                # first call: should hit API
Test-UpdateAvailable                                # second call: should return null instantly
Get-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" | Select-Object Name, LastWriteTime
```

Expected output:
- First call: returns either `$null` (SHA matches) or a `[pscustomobject]@{Installed=...; Remote=...}` (SHA differs). Takes ~100-2000ms.
- Second call: returns `$null` **instantly** (no perceptible delay).
- `Get-Item` shows the file exists with `LastWriteTime` within the last few seconds.

If you're not yet running tstyles from a real install (only in the local repo), substitute `$script:TStylesRoot` for `$env:LOCALAPPDATA\TerminalStyles` in the paths above. The script computes `$script:TStylesRoot = $PSScriptRoot` so it'll write the stamp next to the script itself during dev.

- [ ] **Step 3: Throttle-window expiry test**

In the same shell:

```powershell
$stampFile = Join-Path $script:TStylesRoot '.last-update-check'
$pastIso = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
[System.IO.File]::WriteAllText($stampFile, $pastIso, [System.Text.UTF8Encoding]::new($false))
Measure-Command { Test-UpdateAvailable }            # should hit API (slow-ish)
Measure-Command { Test-UpdateAvailable }            # should be instant (throttle re-engaged)
```

Expected: first `Measure-Command` shows TotalMilliseconds ~100-2000; second shows TotalMilliseconds < 50.

- [ ] **Step 4: Corrupt-stamp self-heal test**

```powershell
[System.IO.File]::WriteAllText($stampFile, "garbage not a date", [System.Text.UTF8Encoding]::new($false))
Test-UpdateAvailable                                # should not throw; should hit API
(Get-Content $stampFile)                            # should now be a valid ISO timestamp
```

Expected: no exception. Final `Get-Content` shows a parseable ISO-8601 timestamp (the self-heal worked).

- [ ] **Step 5: Offline path test**

Easiest way: temporarily flip the URL inside the function to a guaranteed-404 (e.g. `https://api.github.com/repos/fcreme/TerminalStyles/commits/no-such-branch-XYZ`) and re-source:

```powershell
. "$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"   # re-source with the bad URL
Remove-Item $stampFile -ErrorAction SilentlyContinue
Test-UpdateAvailable                                # returns null (no throw)
Test-Path $stampFile                                # True -- stamp written even on failure
Measure-Command { Test-UpdateAvailable }            # < 50ms because the throttle kicked in
```

Then revert the URL change. (Alternatively: pull the Ethernet cable / disable Wi-Fi for a real offline test.)

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1
git commit -m "Throttle update check to 1/day via .last-update-check"
```

Commit body (use heredoc):

```
Throttle update check to 1/day via .last-update-check

Test-UpdateAvailable previously hit api.github.com on every tstyles
invocation, with no throttling. Adds a .last-update-check timestamp file
read at the top of the function and rewritten after each attempt
(success or failure), capping API calls at 1 per 24h per machine.

Closes the code/spec drift from
docs/superpowers/specs/2026-05-26-update-check-design.md.

Spec: docs/superpowers/specs/2026-05-27-update-check-throttle-design.md
```

---

## Task 2: README wording update

**Files:**
- Modify: `README.md:303-304`
- Modify: `README.md:330-332`

The README currently says the check fires "on every invocation." That's no longer true post-Task-1. Two one-line edits.

- [ ] **Step 1: Update the `## Updating` opener**

Find this paragraph in `README.md` (currently lines 303-304):

```
Every `tstyles` invocation checks `api.github.com` for new commits on
`main` and prints a one-line yellow notice if your install is behind:
```

Replace with:

```
`tstyles` checks `api.github.com` for new commits on `main` at most once
per day per machine and prints a one-line yellow notice if your install
is behind:
```

- [ ] **Step 2: Update the `### How the update check works` block**

Find this paragraph in `README.md` (currently lines 330-336):

```
`tstyles` issues a single unauthenticated HTTP GET to
`api.github.com/repos/fcreme/TerminalStyles/commits/main` on every
invocation (capped at 2 seconds), comparing the returned commit SHA
against the one recorded at install time in `%LOCALAPPDATA%\TerminalStyles\.installed-sha`.
No authentication, no payload sent, no analytics. Offline / API
unreachable / rate-limited → check fails silently and `tstyles` works
normally.
```

Replace with:

```
`tstyles` issues at most one unauthenticated HTTP GET per 24 hours per
machine to `api.github.com/repos/fcreme/TerminalStyles/commits/main`
(capped at 2 seconds), comparing the returned commit SHA against the
one recorded at install time in
`%LOCALAPPDATA%\TerminalStyles\.installed-sha`. The 24h throttle is
tracked in `%LOCALAPPDATA%\TerminalStyles\.last-update-check` and
applies even on failure (so an offline machine doesn't retry the
2s timeout on every invocation). No authentication, no payload sent,
no analytics. Offline / API unreachable / rate-limited → check fails
silently and `tstyles` works normally.
```

- [ ] **Step 3: Verify both edits**

Run:

```powershell
Select-String -Path .\README.md -Pattern 'on every invocation','Every `tstyles` invocation'
```

Expected: **no matches**. (If either string still appears, the edit didn't take.)

Then verify the new wording is present:

```powershell
Select-String -Path .\README.md -Pattern 'at most one','\.last-update-check'
```

Expected: at least two hits (one in each updated paragraph for "at most one", one in the second paragraph for `.last-update-check`).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "README: describe update-check throttle"
```

Commit body:

```
README: describe update-check throttle

Updates two paragraphs in the Updating section that claimed the check
fires "on every invocation" to reflect the actual 1/day throttle and
document the .last-update-check state file.
```

---

## Task 3: Status-bump shipped 2026-05-26 specs

**Files:**
- Modify: `docs/superpowers/specs/2026-05-26-update-check-design.md` (Status line in header)
- Verify, then probably modify: `docs/superpowers/specs/2026-05-26-bundled-style-backgrounds-design.md`
- Verify, then probably modify: `docs/superpowers/specs/2026-05-26-dual-shell-support-design.md`

All three 2026-05-26 specs say `Status: Approved (pending implementation)`. The update-check one definitively flips to "Implemented" once Tasks 1-2 ship. The other two need a quick audit; per the brainstorming analysis they appear shipped, but verify before bumping.

- [ ] **Step 1: Bump the update-check spec**

Edit `docs/superpowers/specs/2026-05-26-update-check-design.md`. Find:

```
**Status:** Approved (pending implementation)
```

Replace with:

```
**Status:** Implemented 2026-05-27
```

(There's exactly one occurrence in the file.)

- [ ] **Step 2: Audit the bundled-backgrounds spec**

Open `docs/superpowers/specs/2026-05-26-bundled-style-backgrounds-design.md` and skim its "File-by-file changes" section. Then verify against the current code:

```powershell
# 1. Does Get-StyleBundledBackground exist in tstyles.ps1?
Select-String -Path .\tstyles.ps1 -Pattern '^function Get-StyleBundledBackground'
# 2. Does the lazy-fetch from gifs branch exist?
Select-String -Path .\tstyles.ps1 -Pattern 'raw.githubusercontent.com.*?/gifs/'
# 3. Does the negative-cache marker exist?
Select-String -Path .\tstyles.ps1 -Pattern '\.no-background'
```

Expected: all three queries hit. If all three hit, the spec is shipped — edit its `**Status:**` line to `Implemented 2026-05-27` (using today's date as the "verified shipped on" date is fine; the actual implementation predates this plan). If any query misses, leave the status line alone and add a one-line note in the spec under the Status line: `**Audit 2026-05-27:** still partially implemented; <which piece is missing>.`

- [ ] **Step 3: Audit the dual-shell-support spec**

Same drill for `docs/superpowers/specs/2026-05-26-dual-shell-support-design.md`:

```powershell
# 1. Has #Requires been lowered to 5.1?
Select-String -Path .\install.ps1, .\tstyles.ps1, .\apply.ps1 -Pattern '#Requires -Version'
# 2. Does install.ps1 detect both engines via Get-Command?
Select-String -Path .\install.ps1 -Pattern "Get-Command -Name 'pwsh.exe'", "Get-Command -Name 'powershell.exe'"
# 3. Has the umbrella profile been ported off `e?
Select-String -Path .\styles\umbrella\profile.ps1 -Pattern '\$script:Esc|\[char\]27'
```

Expected: query 1 should show `5.1` (not `7`) on all three files. Queries 2 and 3 should hit. If all green, flip `**Status:**` to `Implemented 2026-05-27`. Otherwise add the same audit note as Step 2.

- [ ] **Step 4: Commit**

If all three specs flipped to Implemented:

```bash
git add docs/superpowers/specs/2026-05-26-update-check-design.md docs/superpowers/specs/2026-05-26-bundled-style-backgrounds-design.md docs/superpowers/specs/2026-05-26-dual-shell-support-design.md
git commit -m "Mark 2026-05-26 spec cohort as Implemented"
```

Commit body:

```
Mark 2026-05-26 spec cohort as Implemented

All three 2026-05-26 specs (update-check, bundled-backgrounds,
dual-shell-support) say "Approved (pending implementation)" but their
code has shipped. update-check is finalized by this branch; the other
two were verified by code audit (Get-StyleBundledBackground exists +
lazy-fetches from gifs branch; #Requires lowered to 5.1; install.ps1
detects both engines; umbrella profile uses [char]27).
```

If only the update-check spec flipped (other two had audit findings), stage just that one file instead.

---

## Task 4: Full manual test pass against an installed copy

This is the spec's "Testing" section run end-to-end, against a real `%LOCALAPPDATA%\TerminalStyles\` install. Catches integration issues the unit-level smoke tests in Task 1 won't.

**Files:** None modified. This is verification only.

- [ ] **Step 1: Push your branch and re-install from it**

You can't easily test the throttle in the dev repo because the `.last-update-check` path is `$PSScriptRoot`-relative — the production behavior is in `%LOCALAPPDATA%\TerminalStyles\`. Either:

(a) Merge to `main` and re-run `iwr -useb …/install.ps1 | iex`, **or**
(b) Manually copy your edited `tstyles.ps1` over the installed one:

```powershell
Copy-Item .\tstyles.ps1 "$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1" -Force
. $PROFILE   # re-source so the new function is loaded
```

Option (b) is faster for the test pass; option (a) is more representative of what a user gets.

- [ ] **Step 2: Same-SHA path**

```powershell
Remove-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" -ErrorAction SilentlyContinue
tstyles list
Get-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" | Select Name, LastWriteTime
```

Expected: `tstyles list` runs with no yellow "Update available" banner (because installed SHA matches `main`). `.last-update-check` exists with a fresh `LastWriteTime`.

- [ ] **Step 3: Different-SHA path**

```powershell
[System.IO.File]::WriteAllText("$env:LOCALAPPDATA\TerminalStyles\.installed-sha", "0000000000000000000000000000000000000000", [System.Text.UTF8Encoding]::new($false))
Remove-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" -ErrorAction SilentlyContinue
tstyles list
```

Expected: yellow `Update available (0000000 -> <real-sha>). Run: tstyles update` banner prints. `.last-update-check` is rewritten.

- [ ] **Step 4: In-window throttle**

Immediately after Step 3 (same minute):

```powershell
tstyles list
```

Expected: **no banner this time** (throttle window blocks the check). Run `tstyles current` and `tstyles random` for good measure — none should print the banner either.

- [ ] **Step 5: Window expiry**

```powershell
$past = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
[System.IO.File]::WriteAllText("$env:LOCALAPPDATA\TerminalStyles\.last-update-check", $past, [System.Text.UTF8Encoding]::new($false))
tstyles list
```

Expected: banner prints again (window expired → check fires → SHA still mismatched).

- [ ] **Step 6: Restore the real SHA and finish clean**

```powershell
tstyles update   # re-runs the installer, rewrites .installed-sha to current main
```

Expected: install one-liner runs to completion, `.installed-sha` is reset to a real 40-char hex value, no banner on subsequent `tstyles` invocations.

- [ ] **Step 7: Offline / network-failure path (optional but worth it)**

Disconnect from the internet (turn off Wi-Fi / pull the cable). Then:

```powershell
Remove-Item "$env:LOCALAPPDATA\TerminalStyles\.last-update-check" -ErrorAction SilentlyContinue
Measure-Command { tstyles current } | Select-Object TotalSeconds
Test-Path "$env:LOCALAPPDATA\TerminalStyles\.last-update-check"
Measure-Command { tstyles current } | Select-Object TotalSeconds
```

Expected: first `Measure-Command` shows TotalSeconds ~2 (the API timeout). `Test-Path` is True (stamp was written even though API failed). Second `Measure-Command` shows TotalSeconds well under 1 (throttle skipped the API call entirely). Reconnect when done.

If any step fails, do **not** mark this task complete — diagnose and either fix or update the spec.

---

## Task 5: Push and open the PR

**Files:** None modified.

- [ ] **Step 1: Verify the branch is clean and pushed**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Commits in order:

1. `Spec: throttle update check to 1/day via .last-update-check` (already on the branch from brainstorming)
2. `Throttle update check to 1/day via .last-update-check` (Task 1)
3. `README: describe update-check throttle` (Task 2)
4. `Mark 2026-05-26 spec cohort as Implemented` (Task 3)

- [ ] **Step 2: Push**

```bash
git push -u origin HEAD
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "Throttle update check to 1/day via .last-update-check" --body "$(cat <<'EOF'
## Summary
- Adds `.last-update-check` timestamp gate to `Test-UpdateAvailable` so `api.github.com` is hit at most once per 24 hours per machine, closing the code/spec drift from the 2026-05-26 update-check design.
- Writes the stamp on every attempt (success or failure) so offline machines don't retry the 2s timeout on every invocation.
- Updates the README's `## Updating` section to match the actual throttled behavior, and marks the 2026-05-26 spec cohort `Implemented`.

## Test plan
- [ ] `tstyles list` on a fresh install: no banner, `.last-update-check` written.
- [ ] Edit `.installed-sha` to `0000000…`, delete `.last-update-check`: banner prints, stamp rewritten.
- [ ] Immediately re-run `tstyles list`: no banner (throttle engaged).
- [ ] Backdate stamp to -25h: banner prints again.
- [ ] Offline + delete stamp: first call ~2s (timeout), stamp still written, second call < 1s.
- [ ] CI Pester suite still green (no test changes, just verifying no regression).

Spec: `docs/superpowers/specs/2026-05-27-update-check-throttle-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: `gh` prints a PR URL. Open it in a browser, double-check the rendered diff matches your local commits, and you're done.

---

## Self-Review Notes

Spec coverage:

- Goal: throttle API to ≤ 1/day → Task 1.
- Side effect: notice ≤ 1/day → falls out of Task 1 automatically (no separate work).
- Offline machine no longer pays 2s/invocation → Task 1 throttle-write-on-failure + Task 4 Step 7.
- README accuracy → Task 2.
- 2026-05-26 spec status bump (in scope per design) → Task 3.
- Manual test list from spec → Task 4 covers all 7 cases listed.
- Pester test (explicitly deferred in spec) → not in plan, as specified.

Type/signature consistency:

- `Test-UpdateAvailable` return shape (`$null | [pscustomobject]@{Installed,Remote}`) unchanged.
- `Show-UpdateNoticeIfAvailable` callers unchanged.
- File paths (`.installed-sha`, `.last-update-check`) consistent across all tasks.

No placeholders. All commands have expected output. All code blocks are complete.
