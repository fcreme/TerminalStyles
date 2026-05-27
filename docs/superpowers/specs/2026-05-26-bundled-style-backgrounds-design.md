# Bundled Per-Style Backgrounds — Design

**Date:** 2026-05-26
**Status:** Implemented 2026-05-27
**Author:** Felipe
**Builds on:** [dual-shell support](2026-05-26-dual-shell-support-design.md)

## Problem

Today TerminalStyles ships only color schemes / profile overrides; background
images are explicitly NOT shipped (`.gitignore` blocks all `*.gif/.png/.jpg`,
and `tstyles` deliberately leaves the user's existing background untouched
unless they pass `-BackgroundImage <path>`). This means out-of-the-box the
"full themed look" requires manual work for every user: they have to source
their own GIF, place it somewhere, and remember to pass the flag.

Goal: ship a default background image with each style so picking a style
applies the matching imagery automatically, while still allowing users to
override or disable.

## Goals

- A bundled `background.{gif,png,jpg}` per style is auto-applied when the
  user picks that style (interactive `tstyles` or non-interactive
  `apply.ps1`).
- `-BackgroundImage <path>` still overrides the bundled default.
- `-BackgroundImage ""` (empty string) still strips the background entirely.
- Styles without a bundled background fall back to today's behavior (leave
  user's existing background alone).
- The path written into `settings.json` resolves to
  `%LOCALAPPDATA%\TerminalStyles\styles\<name>\background.<ext>` — portable
  across users, no hardcoded `C:\Users\…`.

## Non-goals

- Shipping multiple background variants per style (one canonical per style).
- Animated GIF rendering quality tweaks (uses Windows Terminal's native
  rendering, no extra processing).
- Resizing / optimization of GIFs at install time.

## Folder layout

```
styles/
├── umbrella/
│   ├── README.md
│   ├── profile.ps1
│   ├── scheme.json
│   ├── theme.json
│   └── background.gif   <-- NEW (optional)
├── kitty/
│   ├── README.md
│   ├── scheme.json
│   ├── theme.json
│   └── background.gif   <-- NEW (optional)
└── golden-forest/
    ├── README.md
    ├── scheme.json
    ├── theme.json
    └── background.gif   <-- NEW (optional)
```

GIFs are committed to the repo and ride along when `install.ps1` copies the
extracted ZIP to `%LOCALAPPDATA%\TerminalStyles\`.

## File-by-file changes

### `.gitignore`

Add exceptions for per-style backgrounds, after the existing
`!docs/**/*.png` / `!docs/**/*.jpg` exceptions:

```
!styles/**/background.gif
!styles/**/background.png
!styles/**/background.jpg
```

### `tstyles.ps1`

Add a helper function:

```powershell
function Get-StyleBundledBackground {
    param([Parameter(Mandatory)][string]$StyleDir)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}
```

Modify `Merge-StyleIntoSettings` so that when `-BackgroundImageProvided` is
`$false` but the style has a bundled background, the function treats it as
if `-BackgroundImage <bundled-path>` had been passed. Concretely:

- Before the per-property loop, resolve the bundled background path.
- If a bundled path exists, set `$effectiveBg = $bundled` and treat
  `$BackgroundImageProvided` as `$true` for the rest of the function.
- The existing `bgFields` loop and `{{BACKGROUND_IMAGE}}` substitution
  handle the rest unchanged.

Net effect: during live preview AND on confirm, arrow-keying onto a style
with a bundled background updates `settings.json` with that background.
Arrow-keying onto a style WITHOUT a bundled background falls back to the
current behavior (don't touch the existing background).

### `apply.ps1`

Add the same `Get-StyleBundledBackground` helper at top.

Modify the interactive prompt around current line 134:

```
Background image path (blank = use bundled <style>/background.<ext> if
available, 'none' = no background):
```

After parameter resolution but before the merge call, compute the
effective background:

```powershell
if (-not $PSBoundParameters.ContainsKey('BackgroundImage') -and
    -not $userTypedBlank) {
    $bundled = Get-StyleBundledBackground -StyleDir $styleDir
    if ($bundled) { $BackgroundImage = $bundled }
}
```

If user types `'none'` interactively, treat as explicit empty (`-BackgroundImage ""`).

### `install.ps1`

**No code changes required.** The extract step already copies the entire
repo (including any `background.gif` files) into `%LOCALAPPDATA%\TerminalStyles\`.

### `README.md`

- Update "Optional: background image" section: explain that each style now
  ships with a default GIF, and `-BackgroundImage <path>` overrides while
  `-BackgroundImage ""` disables.
- Update "Adding your own style" folder template to include
  `background.gif` (or `.png`/`.jpg`) as an optional file.
- Remove the "Background images aren't shipped" bullet from "Known
  limitations" (and add a new note: "Bundled GIFs are committed binaries —
  the repo will grow over time as styles are added").

## Data flow

1. User runs `tstyles`.
2. Arrow key highlights a style; `Merge-StyleIntoSettings` runs for preview.
3. `Merge-StyleIntoSettings` calls `Get-StyleBundledBackground $styles[$idx].FullName`:
   - If returns a path → substitute `{{BACKGROUND_IMAGE}}` with that path,
     apply `backgroundImageOpacity` / `StretchMode` / `Alignment` from
     `theme.json`.
   - If returns `$null` and `-BackgroundImage` not passed → skip background
     fields (current behavior).
4. `settings.json` is written; Windows Terminal re-renders with the bundled
   GIF visible.
5. Enter → confirmed; settings stays as previewed.

## Edge cases

- **Style has no bundled background, no `-BackgroundImage` passed:** behave
  as today (don't touch user's existing background).
- **User passes `-BackgroundImage <path>`:** override bundled with the
  user-provided path.
- **User passes `-BackgroundImage ""`:** strip background entirely (no
  image), overriding any bundled GIF.
- **Multiple `background.*` files in same style folder:** priority `.gif >
  .png > .jpg > .jpeg`. `Get-StyleBundledBackground` returns the first
  match.
- **Image path contains spaces / non-ASCII:** Windows Terminal accepts
  these natively; we just write the string into JSON. JSON encoding
  handles escaping via `ConvertTo-Json`.

## Testing

Manual (no test framework in this repo):

- **Bundled GIF present, no flag:** drop `background.gif` into
  `styles/umbrella/`, run `tstyles`, arrow to umbrella, confirm
  `settings.json` now references
  `%LOCALAPPDATA%\TerminalStyles\styles\umbrella\background.gif` in the
  target profile's `backgroundImage` field.
- **Bundled GIF present, `-BackgroundImage <other-path>`:** confirm the
  user-supplied path wins over the bundled one.
- **Bundled GIF present, `-BackgroundImage ""`:** confirm no background is
  applied.
- **No bundled GIF, no flag:** confirm existing user background is
  preserved (regression check on current behavior).
- **Live preview cycling:** arrow between three styles, two of which have
  bundled GIFs and one of which doesn't — confirm the WT window cycles
  through the GIFs and the third style preserves whatever was last shown.
  *(Caveat: the existing "don't touch user's bg unless provided" behavior
  needs care here — preview-cycling onto a no-bundle style should ideally
  strip the previously-applied bundle, otherwise you get visual carryover.
  See "Known limitation" below.)*

## Known limitations

- **Repo size:** Bundled GIFs are committed binaries; repo will grow as
  styles are added. Mitigation: keep each GIF small (target < 2 MB) and
  encourage contributors to optimize before submitting.
- **Preview carryover:** When arrow-keying from a style WITH a bundle to a
  style WITHOUT one, the previously-applied GIF persists visually because
  the no-bundle code path doesn't touch background fields. Acceptable for
  v1 — both bundled styles produce a clear theme, and falling back to
  user's bg on a bundle-less style is honest about "this style has no
  default imagery." If this becomes confusing, follow-up work can clear
  bg fields when transitioning bundled → unbundled.
- **Copyright / attribution:** Bundled GIFs must be content the project
  owner has the right to redistribute. README should mention this for
  contributors.
