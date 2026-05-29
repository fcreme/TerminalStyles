# Load the Themed Prompt/Banner Only in Windows Terminal (Design)

**Date:** 2026-05-29
**Status:** Approved (brainstorming)
**Target version:** TerminalStyles 0.4.2 (patch)

## Goal

A style's color scheme, cursor, font, opacity, and background image are all
applied through Windows Terminal's `settings.json`. Other terminal hosts —
VS Code's integrated terminal, Visual Studio's terminal, conhost — do not read
that file, so none of that styling renders there. But the style's
`profile.ps1` (the prompt + startup banner) is plain PowerShell that
dot-sources from the user's `$PROFILE` on **every** shell, regardless of host.
The result in a non-Windows-Terminal host is a "half" look: the themed
prompt/banner appears with none of the colors or background that are supposed
to go with it.

The user prefers a non-WT terminal stay **plain** over showing this half-themed
result. So: load the active style's `profile.ps1` (prompt/banner) **only when
the current session is Windows Terminal**; skip it everywhere else.

## Non-goals (YAGNI)

- No VS Code / Visual Studio palette writing (writing those hosts' own theme
  files is a large, out-of-character platform expansion — a stated non-goal).
- No opt-out flag. The user explicitly wants it blocked. An escape hatch
  (`$env:TSTYLES_FORCE_PROFILE`) is trivial to add later if a real need
  surfaces; deliberately omitted now.
- No per-host (VS Code vs Visual Studio vs conhost) detection. The single
  trusted signal is "are we in Windows Terminal" (`$env:WT_SESSION`); everything
  else is treated uniformly as "not WT → stay plain."
- The module's **functions** still import in every host. Only the auto-applied
  prompt/banner is gated. `tstyles`, `list`, `help`, `tune`, etc. all still work
  in VS Code; they just don't theme the current session's prompt.

## Behavior

| Host | Module functions | Style colors/bg (via WT settings.json) | Themed prompt/banner |
|---|---|---|---|
| Windows Terminal | available | applied | **loaded** |
| VS Code / Visual Studio / conhost | available | n/a (host ignores settings.json) | **skipped** (plain prompt) |

"Current session is Windows Terminal" is detected via the `$env:WT_SESSION`
environment variable, which Windows Terminal sets in every shell it hosts (both
pwsh 7 and Windows PowerShell 5.1).

## Architecture

### New helper: `Test-InWindowsTerminal`

A one-line, side-effect-free predicate — the single source of truth for the
gate, and the testable seam:

```powershell
function Test-InWindowsTerminal {
    # True when the current session is hosted by Windows Terminal (which sets
    # WT_SESSION). The only host that renders a style's colors/background, so
    # the themed prompt/banner is loaded only here.
    return [bool]$env:WT_SESSION
}
```

Placed with the other internal helpers in `tstyles.ps1` (before the
`# === Public command ===` marker).

### Gate the three `profile.ps1` dot-source sites

The active style's profile is dot-sourced into the current session in three
places (all already guard on file-existence and/or `$isPwshTarget`). Each gets
an added `Test-InWindowsTerminal` check. **The dot-source itself stays inline at
each site** — it must not be wrapped in a function, because dot-sourcing inside
a function would scope the `prompt` function (and anything else the profile
defines) to that function instead of where it currently lands. Only the guarding
`if` condition changes.

1. **Startup auto-load** — `tstyles.ps1:2066-2069` (top-level, runs on every
   module import):
   ```powershell
   # === Auto-load the currently selected style's profile.ps1 (Windows Terminal only) ===
   if ((Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
       . $script:TStylesCurrent
   }
   ```

2. **After `tstyles <name>`** — inside `Apply-StyleDirect`, `tstyles.ps1:~698-700`:
   ```powershell
   if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
       . $script:TStylesCurrent
   }
   ```

3. **After picker-confirm** — `tstyles.ps1:~2021-2023`:
   ```powershell
   if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
       . $script:TStylesCurrent
   }
   ```

This yields the invariant: **the style's prompt/banner loads into the current
session only when that session is Windows Terminal** — whether triggered by
shell startup or an explicit apply.

### Reuse for the existing picker warning (DRY)

The picker already prints `if (-not $env:WT_SESSION) { ... "live preview is only
visible inside Windows Terminal" }` (`tstyles.ps1:~1697`). Switch it to
`if (-not (Test-InWindowsTerminal))` for a single detection path, and sharpen the
message to name what's affected, e.g.: `Note: color scheme + background only
render in Windows Terminal; this host shows a plain prompt.` (Wording finalized
in the plan.)

## Edge cases / error handling

- **`$env:WT_SESSION` set but not actually WT** (extremely rare spoofing): the
  prompt would load — acceptable, no opt-out needed.
- **WT but `WT_SESSION` somehow unset** (rare): prompt skipped in WT — a benign
  false negative; the user can reopen the tab. No mitigation in scope.
- **No active style** (`current-style.ps1` absent): unchanged — the `Test-Path`
  guard already short-circuits.
- The change only *adds* a condition to existing `if`s; it removes no behavior
  inside Windows Terminal. WT users see no change.

## Testing

- **Unit-test `Test-InWindowsTerminal`** (`tests/Test-InWindowsTerminal.Tests.ps1`):
  returns `$true` when `$env:WT_SESSION` is set, `$false` when unset/empty.
  Save and restore `$env:WT_SESSION` around the cases.
- **The three inline dot-sources** stay inline (correct scope) and are
  verified by code review — these are interactive/startup load paths with side
  effects (set the prompt, print a banner), the same testing model already used
  for the picker and tuner key loops.
- **Optional (plan's call):** a child-process integration test that imports the
  module in a fresh `pwsh` with `WT_SESSION` unset and a sentinel
  `current-style.ps1`, asserting the sentinel did **not** fire (startup gate
  honored). Nice-to-have; the helper unit test + review are the baseline.

## Documentation & version

- **README "Known limitations":** update the WT-only note to state that the
  themed prompt/banner now loads only in Windows Terminal — non-WT hosts stay
  plain by design (so this is expected, not a bug).
- **TerminalStyles.psd1:** `ModuleVersion` 0.4.1 → 0.4.2; ReleaseNotes describing
  the gate. (Patch — a small, additive behavior refinement. Final
  release/version timing is the user's call; may batch with other work.)

## Decisions / judgment calls

- **Gate all three load sites, not just startup.** Consistency: the goal is "no
  half look in a non-WT host," and running `tstyles <name>` *inside* a non-WT
  terminal would otherwise re-introduce it via the apply-time load.
- **`$env:WT_SESSION` as the sole signal.** One trusted, future-proof check
  (covers VS Code, Visual Studio, conhost, and any future host) beats a fragile
  denylist — Visual Studio in particular has no clean detection env var.
- **No opt-out** (YAGNI), as above.
- **Helper extraction over inline checks.** A named, unit-tested predicate is
  the testable seam and the one place detection can evolve later.
