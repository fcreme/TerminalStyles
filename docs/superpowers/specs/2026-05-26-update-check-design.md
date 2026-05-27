# Update-Check + `tstyles update` — Design

**Date:** 2026-05-26
**Status:** Implemented 2026-05-27
**Author:** Felipe

## Problem

The README currently tells users to "re-run the install one-liner to pull the
latest styles," but it's passive — users have no way of knowing when a new
theme or feature has actually shipped. As the repo gains themes
(ex-machina just landed, with nostromo/matrix/cyberpunk likely next), this
becomes a real gap: a user who installed last week won't know there are
three new themes available unless they read the README again.

## Goals

- Users learn about updates without manually re-reading the README.
- One explicit, discoverable command (`tstyles update`) re-runs the install
  flow.
- Zero startup overhead on shell launch (the check runs only when the user
  actively invokes `tstyles`).
- Throttled to ≤ 1 HTTP request per user per day. Never blocks `tstyles`
  invocation. Never spams stderr on network errors.
- Works on PCs with no internet (silent skip) and on locked-down PCs where
  api.github.com is unreachable (silent skip).

## Non-goals

- Auto-update on shell startup (rejected: surprise behavior, mandatory
  network on every tab).
- Automatic background daemon / scheduled task (rejected: scope creep,
  Windows policy surface).
- Authenticated GitHub API access (rejected: 60 unauthenticated requests
  per hour is plenty for our ~1/day per user).
- Telemetry / analytics. The check sends nothing about the user to
  GitHub; it's a plain unauthenticated HTTP GET of a public branch.

## Architecture

Two files in `%LOCALAPPDATA%\TerminalStyles\` track state:

| File | Written by | Read by | Purpose |
|---|---|---|---|
| `.installed-sha` | `install.ps1` after extract | `tstyles.ps1` update check | The git SHA at install time (40-char hex). |
| `.last-update-check` | `tstyles.ps1` update check | `tstyles.ps1` update check | ISO-8601 timestamp of last check (success or failure). Used to throttle. |

The HTTP endpoint used is
`https://api.github.com/repos/fcreme/TerminalStyles/commits/main`. Response
is JSON with a top-level `sha` field. No auth headers.

## File-by-file changes

### `install.ps1`

After the extract step copies files to `$installDir`, add:

```powershell
# --- Record install SHA for the update checker ---
try {
    $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" `
                                    -TimeoutSec 5 -ErrorAction Stop
    if ($commitInfo.sha) {
        [System.IO.File]::WriteAllText(
            (Join-Path $installDir '.installed-sha'),
            $commitInfo.sha,
            [System.Text.UTF8Encoding]::new($false))
    }
} catch {
    # Non-fatal: install proceeds, update check will just skip until next reinstall.
    Write-Host "Note: couldn't record install SHA (network?); update checker will be disabled." -ForegroundColor DarkGray
}
```

Place it right after the existing `Move-Item ... -Destination $installDir`
block, before the loader registration loop.

### `tstyles.ps1`

Add two new helpers and one hook in `Invoke-TerminalStyle`.

**`Test-UpdateAvailable`** — returns a `pscustomobject` if newer SHA is
available, or `$null` if not / can't tell:

```powershell
function Test-UpdateAvailable {
    $shaFile   = Join-Path $script:TStylesRoot '.installed-sha'
    $stampFile = Join-Path $script:TStylesRoot '.last-update-check'

    # Throttle: only check once per 24h. Write the timestamp on EVERY
    # attempt (success or failure) so a network outage doesn't trigger
    # one retry per tstyles invocation.
    if (Test-Path -LiteralPath $stampFile) {
        try {
            $stamp = [datetime]::Parse((Get-Content -LiteralPath $stampFile -Raw).Trim())
            if (((Get-Date) - $stamp).TotalHours -lt 24) { return $null }
        } catch { }
    }

    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = (Get-Content -LiteralPath $shaFile -Raw).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        $resp = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
            -TimeoutSec 3 -ErrorAction Stop
        $remote = $resp.sha
    } catch { }

    # Always update the throttle timestamp -- even on failure.
    try {
        Set-Content -LiteralPath $stampFile -Value (Get-Date -Format 'o') `
                    -Encoding UTF8 -NoNewline -ErrorAction Stop
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

**`Invoke-TerminalStylesUpdate`** — re-runs the install one-liner:

```powershell
function Invoke-TerminalStylesUpdate {
    Write-Host ""
    Write-Host "Updating TerminalStyles from GitHub..." -ForegroundColor Cyan
    try {
        Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1' -UseBasicParsing).Content
    } catch {
        Write-Host "Update failed: $_" -ForegroundColor Red
        Write-Host "You can retry manually:" -ForegroundColor Yellow
        Write-Host "  iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex" -ForegroundColor Cyan
    }
}
```

**Hook in `Invoke-TerminalStyle`** — at the top of the function, before
locating settings.json:

```powershell
# Subcommand routing
if ($Update -or $Target -eq 'update') {
    Invoke-TerminalStylesUpdate
    return
}

# One-time-per-day update notice
$pending = Test-UpdateAvailable
if ($pending) {
    Write-Host ("Update available ({0} -> {1}). Run: tstyles update" -f $pending.Installed, $pending.Remote) -ForegroundColor Yellow
    Write-Host ""
}
```

Add a parameter to the function signature:

```powershell
param(
    [string]$Target,
    [string]$BackgroundImage,
    [switch]$Update
)
```

Both `tstyles update` (positional) and `tstyles -Update` (switch) are
accepted. The positional form is more discoverable; the switch is the
PowerShell-idiomatic form.

### `README.md`

Replace the existing "Updating" section with:

```markdown
## Updating

`tstyles` checks once per day for new commits on `main` and prints a one-line
notice if a newer version is available. To actually pull the update, run:

\`\`\`powershell
tstyles update
\`\`\`

This re-runs the install one-liner against the latest `main`. Your currently
selected style (`current-style.ps1`) is preserved.

If `tstyles update` fails (no internet, GitHub down, corporate proxy), you
can always run the original install one-liner instead:

\`\`\`powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
\`\`\`

### How the update check works

When you run `tstyles`, it makes at most one HTTP GET per day to
`api.github.com` to compare your installed commit SHA against `main`. No
authentication, no payload sent, no analytics. If your machine is offline or
the API is unreachable, the check fails silently — `tstyles` works
normally.
```

(Backticks around the powershell blocks are intentional in this spec; the
actual README uses real fences.)

## Data flow

1. **Install:** user runs the one-liner → `install.ps1` downloads ZIP →
   extracts → hits GitHub API for current commit SHA → writes
   `%LOCALAPPDATA%\TerminalStyles\.installed-sha`.
2. **First `tstyles` invocation after install:** no `.last-update-check`
   file → `Test-UpdateAvailable` runs the API call → SHA matches → returns
   `$null` → no notice → timestamp written.
3. **Same day, second `tstyles` invocation:** timestamp < 24h old → skip
   check entirely → no notice.
4. **Day later, a new commit has shipped on main:** stamp >= 24h →
   `Test-UpdateAvailable` runs the API call → remote SHA differs → returns
   abbreviated SHAs → notice printed in yellow → user can run `tstyles
   update` whenever they want.
5. **User runs `tstyles update`:** subcommand routing fires →
   `Invoke-TerminalStylesUpdate` re-runs the install one-liner → fresh ZIP,
   fresh SHA, fresh `.installed-sha`. Next-day check will be quiet again.

## Edge cases

- **Pre-feature installs:** users who installed before this change won't
  have `.installed-sha`. Update check silently no-ops for them; they get
  the notice flow only after their next reinstall. Acceptable graceful
  degradation.
- **Clock skew:** if the system clock is wildly wrong, the 24h throttle
  could either over-check or under-check. Worst case: a few extra API
  calls. Acceptable.
- **GitHub rate limit:** 60 unauthenticated requests per hour per IP. Even
  in households with multiple users behind one NAT, this is fine.
- **User on a metered connection:** the request is ~1 KB. Negligible.
- **User pipes `iwr | iex` again instead of `tstyles update`:** install.ps1
  rewrites `.installed-sha` on every install, so this still works correctly.

## Testing

Manual:

- **Install records SHA:** delete `%LOCALAPPDATA%\TerminalStyles\` and
  re-run installer. Confirm `.installed-sha` exists and contains a 40-char
  hex string.
- **Same-SHA path:** `tstyles` should print no notice on day-1 of a fresh
  install (since installed SHA == remote SHA).
- **Different-SHA path:** manually edit `.installed-sha` to a fake older
  SHA (e.g. `0000000000000000000000000000000000000000`), delete
  `.last-update-check`, run `tstyles`. Confirm yellow notice prints.
- **Throttle:** immediately re-run `tstyles`. Confirm NO notice (because
  `.last-update-check` was just written).
- **Network failure:** disconnect, delete `.last-update-check`, run
  `tstyles`. Confirm no error, no notice, and `.last-update-check` was
  still written (to throttle retries).
- **`tstyles update`:** run it. Confirm the install one-liner runs through
  to completion and `.installed-sha` is rewritten to current `main`.
- **`-Update` switch form:** `tstyles -Update`. Same behavior as
  positional `tstyles update`.

## Known limitations

- **Check fires only when the user runs `tstyles`.** Users who install
  once and never run `tstyles` will never see update notices. Acceptable —
  if they're not using the picker, they don't need new themes.
- **No CHANGELOG link in the notice.** The notice says "Update available"
  but doesn't say what's new. Follow-up work could fetch the commit
  message of the newer SHA and show its first line.
