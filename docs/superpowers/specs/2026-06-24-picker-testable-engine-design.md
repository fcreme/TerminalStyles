# Picker testable engine — design

**Date:** 2026-06-24
**Status:** Approved (pending spec review)
**Component:** `tstyles.ps1` — the interactive `tstyles` picker

## Context

`Invoke-TerminalStyle`'s no-argument path is the interactive picker: arrow keys
preview each style live in the current Windows Terminal tab, **Enter** keeps the
highlighted style, **Esc** reverts to exactly how `settings.json` looked before.

The picker's core correctness promise — *"Esc restores the byte-exact original
`settings.json`"* — is currently **untested**. The whole selection loop
(`while (-not $confirmed)`, currently ~lines 2358–2431) is welded to
`[Console]::KeyAvailable` / `[Console]::ReadKey($true)` and writes directly to
the host, so no automated test can drive it. This is the project's riskiest code
(a crash or logic slip here can mangle a user's real `settings.json`) and its
least-covered path.

## Goal

Make the picker's selection logic testable without changing its behavior, then
lock the three load-bearing invariants with automated tests:

1. **Byte-exact revert** — Esc restores the original `settings.json` bytes exactly.
2. **Enter persists the chosen style** — confirming writes the merged settings for
   the highlighted style.
3. **Mash-collapse** — a burst of arrow keys results in a single settings write at
   the final position (Windows Terminal does one reload, not N).

## Scope / non-goals

- **In scope:** the picker loop in `Invoke-TerminalStyle`.
- **Out of scope (follow-up):** the tuner loop (`Invoke-TerminalStyleTune`) has a
  similar console loop; not touched here, to keep this change focused.
- **No behavior change.** This is a refactor + tests only. No new commands, no
  user-visible difference.

## Current behavior to preserve

Within `Invoke-TerminalStyle`, after setup (find settings, enumerate styles,
snapshot `$originalJson` as UTF-8/no-BOM, resolve `$Target`, preload
swatches/schemes/titles/OSC packets, start the background prefetch job, write the
rolling `settings.json.bak`, hide the cursor, save the window title, write the
first preview), the loop:

- **Up/Down:** clamp the index to `[0, count-1]`; on a real move, immediately
  write the style's OSC color packet (instant retint) and set `$pendingApply = $idx`
  (deferred settings write); request a redraw.
- **Enter:** if a preview is pending, apply it first (so the confirmed theme is on
  disk before profile.ps1 is copied), then mark confirmed.
- **Esc:** write `$originalJson` back via `Write-SettingsAtomic`, emit the OSC
  reset packet, print "Reverted.", and return.
- **Queue-empty (debounce tail):** if a preview is pending, apply it once — this is
  what collapses a key-mash to a single write.
- **Truly idle:** prebuild the next uncached resolved style's merged JSON, else
  `Start-Sleep 50ms`.

After the loop, on confirm: install the selected style's `profile.ps1` to
`current-style.ps1` (for pwsh targets), print "Style applied", and dot-source the
profile for live reload. The `finally` restores cursor visibility, restores the
window title if not confirmed, and tears down the prefetch job.

## Architecture: `Invoke-StylePickerLoop`

Extract the selection loop into a new internal function that owns **only** index
state, the `pendingApply` debounce, and key dispatch. All I/O, rendering, and
side effects are injected as script-block **seams** so the loop is driveable.

### Signature (conceptual)

```
Invoke-StylePickerLoop
    -StyleCount [int]
    -StartIndex [int]
    -ReadKey    [scriptblock]            # -> a key object with .Key, or $null when none available
    -OnPreview  [scriptblock]  param($i) # debounced settings write for index $i
    -OnRevert   [scriptblock]            # Esc: restore original settings + OSC reset
    -OnDraw     [scriptblock]  param($i) # render the menu at index $i
    -OnRetint   [scriptblock]  param($i) # instant OSC color packet for index $i
    -OnIdle     [scriptblock]            # idle prebuild / sleep
-> returns @{ Outcome = 'confirmed' | 'cancelled'; Index = <int> }
```

### Seam defaults (wired in `Invoke-TerminalStyle`) vs. test doubles

| Seam | Real default | In tests |
|---|---|---|
| `ReadKey` | `{ if ([Console]::KeyAvailable) { [Console]::ReadKey($true) } else { $null } }` | scripted queue; returns `[ConsoleKey]::Escape` when exhausted (hang-guard) |
| `OnPreview $i` | existing `$applyTheme` (cache-aware settings write + title) | recorder (unit) / real (integration) |
| `OnRevert` | `Write-SettingsAtomic $originalJson` + `Get-OscResetPacket` write | recorder (unit) / real (integration) |
| `OnDraw $i` | existing `$drawMenu` | no-op |
| `OnRetint $i` | `[Console]::Out.Write($oscPackets[$i])` | no-op |
| `OnIdle` | idle prebuild loop / `Start-Sleep 50` | no-op |

### Loop contract

- The loop is the **only** owner of `$idx` and `$pendingApply`.
- A single `ReadKey` seam models both "is a key available?" and "read it": it
  returns a key object while keys are queued, and `$null` the moment the queue is
  empty. `$null` is the trigger for the debounce tail (apply the pending preview)
  and then the idle path — preserving mash-collapse exactly.
- Enter drains a pending preview before returning `confirmed`.
- Esc invokes `OnRevert` and returns `cancelled`.
- `Invoke-TerminalStyle` keeps the first-preview write, setup, the post-confirm
  profile install, the "Reverted."/"Style applied" messaging, and the `finally`
  cleanup; it branches on the returned `Outcome`/`Index`.

## Behavior-preservation strategy

This is an **extract-method** refactor: the loop body, bounds checks, debounce,
and key→action mapping move verbatim into `Invoke-StylePickerLoop`; the existing
inline scriptblocks (`$drawMenu`, `$applyTheme`, the Esc block, the idle prebuild,
the OSC write) become the default seam callbacks, retaining their closure over
`$styles`, `$settingsPath`, `$originalJson`, `$Target`, `$mergedCache`, `$titles`,
`$oscPackets`. No control-flow or logic changes.

Verified by: (a) the existing **406** tests stay green; (b) the new tests below.

## Tests (the deliverable)

New file: `tests/Invoke-StylePickerLoop.Tests.ps1`, dot-sourcing `tstyles.ps1`
the same way the other internal-function specs do (e.g.
`Merge-StyleIntoSettings.Tests.ps1`).

A test helper builds a `ReadKey` stub from an array, yielding one element per
call **in order**. An element may be `$null` to simulate a momentary empty queue
(the signal that drives the debounce tail / mash-collapse). Once the array is
fully consumed the stub returns `[ConsoleKey]::Escape` on every further call, so
a test can never hang the loop.

Integration tests (6–7) wire the **real** `OnPreview` and `OnRevert` against a
temp `settings.json`, but stub `OnDraw` / `OnRetint` / `OnIdle` to no-ops — those
are cosmetic and console-dependent, and asserting them is out of scope.

### Engine unit tests (recording seams, no real I/O)

1. **Up clamps at 0** — `Up` at start index 0 leaves index 0; `OnPreview` not called.
2. **Down clamps at last** — `Down` at the last index does not overflow.
3. **Mash-collapse** — keys `Down, Down, Down, <null>, Enter` ⇒ `OnPreview` called
   exactly once, with the final index; `Outcome = 'confirmed'`, `Index = final`.
4. **Bare Enter** — `Enter` with no prior arrow ⇒ `OnPreview` not called;
   `Outcome = 'confirmed'`, `Index = StartIndex`.
5. **Esc cancels** — `Down, Esc` ⇒ `OnRevert` called once; `Outcome = 'cancelled'`.

### Integration tests (real seams, temp `settings.json` + 1–2 fake styles)

6. **Byte-exact revert (headline)** — drive `Down → Esc` against a temp
   `settings.json`; assert the file is **byte-identical** to the original snapshot.
   Include a fixture whose target profile name contains non-ASCII (e.g.
   `Símbolo del sistema`) to lock the UTF-8/no-BOM round-trip the code comment at
   ~2110–2114 warns about.
7. **Enter persists chosen** — drive `Down → Enter`; assert the resulting
   `settings.json` equals `Merge-StyleIntoSettings` output for the highlighted style.

## Risks & mitigations

- **Refactoring the riskiest code.** Mitigated by keeping it a verbatim
  extract-method, gating on the existing 406 tests, and TDD on the new invariants.
- **Closure/scope drift** when moving inline scriptblocks to seam defaults.
  Mitigated by passing them from within `Invoke-TerminalStyle` (closures keep their
  defining scope) and asserting end-to-end via the integration tests.
- **Test hangs** if a scripted key queue never terminates. Mitigated by the
  `ReadKey` stub returning `Escape` when exhausted.

## Out of scope / future

- Tuner loop (`Invoke-TerminalStyleTune`) testability via the same pattern.
- Driving `OnRetint`/OSC assertions (cosmetic; not a correctness invariant).
