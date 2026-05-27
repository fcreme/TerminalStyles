# Update-Check Throttle (delta from 2026-05-26 update-check design) — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Builds on:** [update-check + `tstyles update`](2026-05-26-update-check-design.md)

## Problem

The 2026-05-26 update-check design promised "≤ 1 HTTP request per user per
day" via a `.last-update-check` timestamp file. The shipping implementation
in `tstyles.ps1` skipped that file entirely: `Test-UpdateAvailable`
(`tstyles.ps1:100-131`) hits `api.github.com` on **every** `tstyles`
invocation, with a 2-second worst-case timeout, and `Show-UpdateNoticeIfAvailable`
is wired into five entry points (`list`, `current`, `random`, direct apply,
picker — see `tstyles.ps1:372, 398, 420, 452, 600`).

User-visible consequences:

| Scenario | Today |
|---|---|
| 20 `tstyles` invocations in a day, no update | 20 API calls, up to ~2s each |
| 20 invocations, update available | 20 identical yellow "Update available" notices |
| Offline machine | 20 silent 2s timeouts per day |

The spec said `≤ 1 HTTP request per user per day`. The code does `N requests
per day where N = invocations`. This is a straightforward code/spec drift
to close.

## Goals

- Honor the 2026-05-26 spec's `≤ 1 HTTP request per user per day` throttle.
- As a side effect of the throttle, the yellow notice fires at most once per
  day (rather than once per invocation).
- Offline machines stop paying the 2-second timeout on every invocation.
- Zero behavioral change for: `.installed-sha` location and format, the API
  endpoint, the notice text, the 5 callers, `tstyles update`.

## Non-goals

- Notice-level throttling beyond what falls out of the API-call throttle
  (e.g. "remind every 4 hours within a day"). The once-per-day cadence is
  sufficient ambient awareness without nag.
- A separate `.last-remote-sha` cache so the notice can fire on every
  invocation while the API call stays 1/day. Considered and rejected during
  brainstorming — adds a file and a freshness-mismatch edge case for marginal
  UX gain.
- CHANGELOG line in the notice (already listed as future work in the
  2026-05-26 spec's Known limitations).
- Reconsidering which subcommands invoke the notice. The current 5-caller
  layout stays.
- Pester test for the throttle. Deferred — manual testing per the 2026-05-26
  spec's test list is sufficient to ship. Can land as a follow-up.

## Architecture

One new state file alongside the existing `.installed-sha`:

| File | Written by | Read by | Purpose |
|---|---|---|---|
| `.installed-sha` (existing) | `install.ps1` after extract | `Test-UpdateAvailable`, `Invoke-TerminalStylesUpdate` | The git SHA at install time. |
| `.last-update-check` (**new**) | `Test-UpdateAvailable` after each attempt | `Test-UpdateAvailable` at top of next call | ISO-8601 (`o`-format) timestamp of last attempt — success **or** failure. |

The write-on-failure semantics are the key correctness bit: an offline
machine that doesn't write the timestamp would retry the 2-second timeout
on every single `tstyles` invocation, exactly the bug we're fixing.

## File-by-file changes

### `tstyles.ps1` — `Test-UpdateAvailable` (lines 100-131)

Add a throttle check at the top of the function and a timestamp write after
the API attempt. Pseudocode:

```
function Test-UpdateAvailable:
    shaFile   = $TStylesRoot\.installed-sha
    stampFile = $TStylesRoot\.last-update-check

    # NEW: throttle gate
    if stampFile exists:
        try:
            stamp = [datetime]::Parse(file contents)
            if (now - stamp) < 24h: return $null
        catch:
            # unparseable -- fall through, will overwrite below

    if shaFile missing or empty: return $null
    installed = file contents

    remote = $null
    try:
        resp = Invoke-RestMethod -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' \
                                 -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } \
                                 -TimeoutSec 2 -ErrorAction Stop
        remote = resp.sha
    catch: # swallowed, intentional

    # NEW: always write timestamp, even on API failure
    try:
        Set-Content -LiteralPath stampFile -Value (Get-Date -Format 'o') \
                    -Encoding UTF8 -NoNewline -ErrorAction Stop
    catch: # disk full / read-only volume / AV -- ignore

    if remote and remote != installed:
        # Abbreviation form unchanged from current code:
        # installed.Substring(0, [Math]::Min(7, installed.Length))
        return [pscustomobject]@{ Installed = <7-char prefix of installed>; Remote = <7-char prefix of remote> }
    return $null
```

Notes on small deltas from the 2026-05-26 spec:

- **Timeout stays at 2 seconds** (current code). The 2026-05-26 spec wrote
  `-TimeoutSec 3`; keeping 2s minimizes the diff and the worst-case latency
  on the one-call-per-day path is small either way. No correctness impact.
- **User-Agent header preserved.** The current code passes
  `'User-Agent' = 'TerminalStyles-UpdateCheck'`; the 2026-05-26 spec
  snippet omitted it. Keep it — GitHub's API requires a User-Agent on
  unauthenticated requests and the current header is descriptive.
- **`Set-Content -Encoding UTF8 -NoNewline`** for the timestamp write, as
  the 2026-05-26 spec wrote. This is one of the few places we don't use
  `[System.IO.File]::WriteAllText` because the timestamp is trivially short
  and `Set-Content` keeps the code closer to the original spec snippet
  reviewers will recognize.

### `install.ps1`

No change. `.installed-sha` is already written at `install.ps1:115`.

### `docs/superpowers/specs/2026-05-26-update-check-design.md`

Flip the header from `**Status:** Approved (pending implementation)` to
`**Status:** Implemented 2026-05-27`. The spec body is accurate as a
historical record; this is purely a status bump so future readers don't
think the work is still pending.

### `README.md`

Two small text fixes — the README currently documents the *un-throttled*
behavior verbatim, so it'll become inaccurate the moment the throttle
ships. Both edits are one-line wording changes.

- **Line 303-304** (`## Updating` opener): "Every `tstyles` invocation
  checks `api.github.com` ..." → "`tstyles` checks `api.github.com`
  at most once per day ...".
- **Lines 330-332** (`### How the update check works`): "... HTTP GET to
  `api.github.com/...` on every invocation (capped at 2 seconds) ..." →
  "... HTTP GET to `api.github.com/...` at most once every 24 hours per
  machine (capped at 2 seconds), throttled via
  `%LOCALAPPDATA%\TerminalStyles\.last-update-check` ...".

Exact replacement text will be in the implementation plan; the design
intent is "the README must describe what the code actually does, namely
at-most-once-per-day."

## Data flow

1. **First `tstyles` invocation after install:** no `.last-update-check`
   file → fall through to API call → SHA matches → return `$null` → no
   notice → timestamp written.
2. **Same day, second invocation:** timestamp < 24h old → return `$null`
   immediately, no API call, no notice.
3. **24h later, new commit on `main`:** stamp ≥ 24h → API call fires →
   remote SHA differs → returns abbreviated SHAs → notice printed in
   yellow → timestamp written.
4. **Same day, third invocation after seeing the notice:** timestamp <
   24h old → return `$null` immediately. User saw the notice once today;
   they'll see it again tomorrow if they haven't run `tstyles update`.
5. **User runs `tstyles update`:** `Invoke-TerminalStylesUpdate` re-runs
   the install one-liner → `install.ps1` overwrites `.installed-sha` →
   next-day check is quiet again.
6. **Offline machine:** API call throws → caught → timestamp written
   anyway → next 24h of invocations skip the API call entirely → no error
   noise, no latency.

## Error handling

| Failure | Behavior |
|---|---|
| `.last-update-check` exists but isn't a parseable `datetime` | Catch, fall through to perform the check. Timestamp write at the end overwrites with a valid value — self-healing. |
| API call fails (offline, GitHub down, rate limit, timeout) | Catch silently (existing behavior). Timestamp still written so we don't retry on every invocation. |
| `Set-Content` of timestamp fails (read-only volume, AV interference) | Catch silently. Next invocation will re-attempt the check. No regression from current behavior. |
| Clock skew (system clock jumps backward by hours) | Could under-throttle for one cycle (one extra API call). Absorbed by GitHub's 60/hr unauth limit. No mitigation needed. |
| Clock skew (system clock jumps forward by hours) | Could over-throttle (notice delayed by up to the skew). Acceptable; clock skew of hours is rare. |
| `.installed-sha` deleted out from under us between throttle-write and SHA-read | The function already returns `$null` if `.installed-sha` is missing. No throw, no notice. |

## Testing

**Manual** (the 2026-05-26 spec's test list applies as-is, with two cases
that newly exercise meaningful behavior):

- **Same-SHA path:** fresh install, run `tstyles`. No notice. Confirm
  `.last-update-check` exists and contains a recent ISO-8601 timestamp.
- **Different-SHA path:** edit `.installed-sha` to `0000000…`, delete
  `.last-update-check`, run `tstyles`. Yellow notice prints. Confirm
  `.last-update-check` was written.
- **Throttle (the new behavior):** immediately re-run `tstyles`. **No
  API call should fire** and **no notice should print.** Measure with
  Fiddler / Wireshark, or temporarily add `Write-Host "[debug] API hit"`
  to the API branch and confirm it doesn't print.
- **Network failure (the new behavior):** disconnect Wi-Fi, delete
  `.last-update-check`, run `tstyles`. No error printed. `.last-update-check`
  is still written. Re-run `tstyles` — completes instantly (no 2s timeout).
- **Cross-day:** edit `.last-update-check` to 25 hours ago, run `tstyles`.
  Check fires, timestamp refreshed.
- **Corrupt stamp file:** put garbage into `.last-update-check` (e.g.
  `echo "not a date" > .last-update-check`). Run `tstyles`. Check fires
  (graceful), timestamp overwritten with valid value.
- **`tstyles update`:** unchanged from 2026-05-26; verify it still works
  end-to-end and rewrites `.installed-sha`.

**Automated:** none for this change. Defer Pester coverage to a follow-up.

## Known limitations

- **Notice fires only when the user runs `tstyles`** (inherited from
  2026-05-26). Users who never run `tstyles` never see notices. Acceptable.
- **First-of-day call still costs up to 2 seconds on a slow network**
  (the throttle covers all *other* calls). If that ever becomes annoying,
  follow-up work could background the API call via `Start-ThreadJob` and
  surface the notice on the *next* invocation. Out of scope here.
- **Throttle is per-machine, not per-user.** Two users sharing a Windows
  account share the throttle. Effectively never happens on Windows.
