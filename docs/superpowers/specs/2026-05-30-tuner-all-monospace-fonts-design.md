# Tuner Offers All Installed Monospace Fonts (Design)

**Date:** 2026-05-30
**Status:** Approved (brainstorming)
**Target version:** TerminalStyles 0.6.1

## Goal

`tstyles tune`'s font picker only cycles a curated 10-font allowlist intersected
with installed fonts (`Get-MonospaceFontList`, `tstyles.ps1:1056`). If a user has
a coding font installed that isn't on the list (Maple Mono, MonoLisa, IBM Plex
Mono, Iosevka, a Nerd Font variant, ...), they can't pick it in the tuner.

Widen the picker to offer **every installed monospace font**, with the curated
favorites floated to the top, so users see their own fonts automatically — no
allowlist to maintain.

## Non-goals (YAGNI)

- Not proportional fonts (Arial, Times) — they render badly in a terminal and
  would clutter the list. Monospace only.
- Not a font installer/downloader — only fonts already installed.
- Only `tstyles tune`'s font picker changes. Apply/reset/picker/etc. untouched.
- No font *preview* rendering in the tuner — out of scope.

## Behavior

The tuner's font cycler list becomes, in order:

1. **The current font** — first, always (even if unusual or not detected as
   monospace), so re-tuning never loses the user's font. (Unchanged from today.)
2. **Installed curated favorites** — the existing 10, in their current order,
   floated to the top. Always trusted as monospace (never measured).
3. **All other installed monospace fonts** — alphabetical. The new part.
4. De-duplicated; falls back to `@('Consolas')` if the result is somehow empty.

So with MonoLisa + Maple Mono installed, both appear in the cycle after the
favorites, even though neither is on the allowlist.

## Architecture

### New helper `Test-MonospaceFont`

`System.Drawing` exposes no "is monospace" property, so detect it by glyph-width
measurement: a font is monospace when a narrow glyph and a wide glyph have the
same advance width.

```powershell
function Test-MonospaceFont {
    # True when $FamilyName renders as monospace (fixed advance width), detected
    # by measuring a narrow vs wide glyph. $Graphics is an optional reusable
    # System.Drawing.Graphics (the caller creates one and passes it for speed).
    # Any measurement error -> $false (treat unmeasurable fonts as non-monospace;
    # curated favorites bypass this check entirely).
    param(
        [Parameter(Mandatory)][string]$FamilyName,
        $Graphics
    )
    try {
        $font = [System.Drawing.Font]::new($FamilyName, 12.0)
        try {
            # StringFormat.GenericTypographic avoids padding so the widths reflect
            # the glyph advance, not layout padding.
            $fmt = [System.Drawing.StringFormat]::GenericTypographic
            $wi = $Graphics.MeasureString('i', $font, [int]::MaxValue, $fmt).Width
            $ww = $Graphics.MeasureString('W', $font, [int]::MaxValue, $fmt).Width
            # Monospace: equal advance within a small tolerance.
            return [Math]::Abs($wi - $ww) -lt 0.5
        } finally { $font.Dispose() }
    } catch {
        return $false
    }
}
```

Notes:
- The caller creates ONE `System.Drawing.Graphics` (off a 1x1 bitmap) and reuses
  it across all measurements, then disposes it — measuring a few hundred families
  is sub-second.
- A font whose construction or measurement throws is treated as non-monospace
  (skipped). The curated favorites never reach this function, so a flaky
  measurement subsystem can never hide them.

### `Get-MonospaceFontList` — widened

Current signature: `param([string]$Current, [string[]]$Installed)`. Add a second
test seam mirroring `-Installed`:

```powershell
param(
    [string]$Current,
    [string[]]$Installed,        # test seam: real callers omit -> enumerate
    [string[]]$MonospaceNames    # test seam: real callers omit -> measure
)
```

New body logic:
1. If `-Installed` not provided, enumerate via
   `[System.Drawing.Text.InstalledFontCollection]::new().Families.Name` (as today).
2. Curated favorites (the existing 10-name `$allow`) ∩ installed → `$favorites`,
   preserving `$allow` order. (This is today's behavior, kept as the priority
   tier.)
3. If `-MonospaceNames` not provided, compute it: create one reusable `Graphics`,
   then `$MonospaceNames = @($Installed | Where-Object { Test-MonospaceFont -FamilyName $_ -Graphics $g })`;
   dispose the Graphics. If `System.Drawing` is unavailable (Add-Type failed),
   `$MonospaceNames = @()` (degrade to favorites-only).
4. `$others = @($MonospaceNames | Where-Object { $_ -notin $favorites } | Sort-Object)`.
5. `$list = @($favorites) + @($others)`; if empty, `$list = @('Consolas')`.
6. Prepend `$Current` (de-duped) if set: `$list = @($Current) + @($list | Where-Object { $_ -ne $Current })`.
7. `return @($list | Select-Object -Unique)`.

This preserves every existing guarantee (current-first, favorites present,
Consolas fallback, dedup) and adds the monospace tier. The `-Installed` and
`-MonospaceNames` seams let tests drive the ordering/filtering logic with zero
font-subsystem dependence.

## Error handling / edge cases

- **System.Drawing unavailable** (constrained host): enumeration already
  try/catches to `@()`; measurement degrades to `$MonospaceNames = @()` →
  favorites-only list (today's behavior). No crash.
- **A font that errors on measurement:** skipped (Test-MonospaceFont → `$false`).
- **Current font not installed / not monospace:** still first in the list
  (unchanged guarantee).
- **No monospace fonts at all** (favorites not installed either): `@('Consolas')`
  fallback.
- Performance: one-time enumeration on tuner entry; favorites skip measurement;
  reused Graphics. Sub-second on a typical machine. Noted, not optimized further.

## Testing

`Get-MonospaceFontList` is already test-covered via the `-Installed` seam; the new
`-MonospaceNames` seam keeps tests font-subsystem-free.

Update/extend `tests/Get-MonospaceFontList.Tests.ps1`:
1. **Existing tests stay green** — favorites ∩ installed, current-first, dedup,
   Consolas fallback (with `-MonospaceNames @()` passed where needed so behavior
   matches today's favorites-only expectation).
2. **New monospace tier:** given `-Installed @('Consolas','MonoLisa','Arial')` and
   `-MonospaceNames @('Consolas','MonoLisa')`, the list contains `Consolas` and
   `MonoLisa` but NOT `Arial`.
3. **Favorites float above other monospace:** with a favorite + a non-favorite
   monospace both present, the favorite precedes the non-favorite, and non-
   favorites are alphabetical.
4. **Current-first still wins** even when the current font is a non-favorite
   monospace.

For `Test-MonospaceFont` (the System.Drawing measurement): it depends on the
real font subsystem, so it is verified by review + a light live smoke check
(`Consolas` → true, `Arial` → false) rather than a hermetic unit test — the same
testing model used for other System.Drawing-touching code. The list-ordering
logic that matters is fully covered via the `-MonospaceNames` seam.

## Documentation & version

- **README "Tuning a theme":** add a one-line note that the font knob now cycles
  all installed monospace fonts (favorites first), not just a fixed list.
- **TerminalStyles.psd1:** `ModuleVersion` 0.6.0 → 0.6.1 (enhancement to an
  existing feature, no new command → patch); ReleaseNotes.

## Decisions / judgment calls

- **Glyph-width measurement** for monospace detection (no native API), with the
  curated favorites bypassing it so they're always present even if measurement
  is flaky.
- **Favorites stay a priority tier**, not removed — the curated order is a good
  default; the new tier is additive below it.
- **`-MonospaceNames` test seam** mirrors the established `-Installed` seam so the
  ordering logic stays hermetically testable.
- **Patch bump (0.6.1)** — widens an existing knob, adds no command.
