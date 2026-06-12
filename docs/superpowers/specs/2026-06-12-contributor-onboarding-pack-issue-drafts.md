# Contributor Onboarding Pack — mined data (companion to the design spec)

Companion to `2026-06-12-contributor-onboarding-pack-design.md`. Contains the full
CHANGELOG bullets mined from git history and the full drafted bodies for the 11
seeded issues. Code pointers were verified against commit `a06d157` (2026-06-12).

## CHANGELOG data

### Unreleased (post-v0.6.1: 35cbcc7..a06d157)

- Fixed: crash on Windows PowerShell 5.1 when settings.json contains JSONC comments or trailing commas
- Fixed: background images never appeared on PowerShell Gallery installs — the prefetcher wrote to the module directory while readers looked in the local cache, leaving styles stuck on "fetching"
- Fixed: cancelling the picker or tuner (Esc) no longer leaves live preview colors applied on top of your reverted settings
- Fixed: applying a style to a mistyped profile name no longer leaves an orphaned color scheme in settings.json
- Fixed: re-tuning a style whose base style was deleted now keeps its saved opacity and font instead of resetting them to defaults
- Fixed: re-tuning a style saved with Overwrite no longer re-applies its adjustments on top of the already-baked colors (color drift on every re-tune)
- Fixed: deeply nested settings.json structures are no longer silently corrupted on save
- Changed: settings.json writes are now atomic (temp file + replace), and the picker/tuner roll a settings.json.bak before previewing so a hard kill is recoverable
- Changed: when both Windows Terminal Stable and Preview are installed, TerminalStyles now edits the settings file of the build hosting the current session instead of always preferring Stable
- Changed: six themes' muddy accent colors (neon-rain, umbrella, gitbash, rain, snowday, golden-forest) were lifted to a 3:1 contrast floor for legible syntax and prompt tokens, preserving each theme's hue identity
- Changed: background image binaries (~9.9 MB) removed from the main branch — clones are lighter and backgrounds are fetched on demand

### 0.6.1 — 2026-05-30

- Changed: the `tstyles tune` font picker now cycles through every installed monospace font (curated favorites first) instead of a fixed allowlist, so your own coding fonts show up automatically

### 0.6.0 — 2026-05-30

- Added: `tstyles reset` to revert a Windows Terminal profile to its unstyled state

### 0.5.0 — 2026-05-30

- Added: `-KeepPrompt` flag (`tstyles <name> -KeepPrompt`) applies a style's colors, font, and background while keeping your existing prompt
- Changed: apply.ps1's `-NoProfile` switch renamed to `-KeepPrompt` (the old name still works as an alias)

### 0.4.2 — 2026-05-29

- Changed: a style's themed prompt and banner now load only inside Windows Terminal — other hosts (VS Code terminal, plain consoles) keep their own prompt

### 0.4.1 — 2026-05-29

- Fixed: user-registered and tuned styles now appear in the interactive picker, not just via direct apply

### 0.4.0 — 2026-05-29

- Added: `tstyles help` with a command overview and per-command detail
- Added: a `tstyles help` hint in the picker header
- Changed: an unknown argument now shows help instead of silently opening the picker

### 0.3.0 — 2026-05-29

- Added: `tstyles tune` — interactive live theme tuning (brightness/saturation color adjustments, font cycling from a curated monospace list, opacity) with instant preview
- Added: tuned styles can be saved as new styles and inherit their base style's background
- Fixed: styles saved via the tuner's Save-As are now correctly recognized in active-style detection

### 0.2.2 — 2026-05-27

- Added: `tstyles register` to install a custom style folder into the user styles directory, with tab completion

### 0.2.1 — 2026-05-27

- Added: a user styles directory in the data root that survives module updates; user styles with the same name win over bundled ones
- Fixed: installer output rendered as `?` on some consoles — output is now ASCII-only with UTF-8 console handling for Windows PowerShell 5.1
- Fixed: install failures from temp ZIP file lock collisions (download path is now uniquely named)

### 0.2.0 — 2026-05-27

- Added: PowerShell Gallery is now the primary install channel (`Install-PSResource TerminalStyles`)
- Added: `tstyles uninstall -DeleteData` to also remove local TerminalStyles data
- Changed: `tstyles update` and `tstyles uninstall` delegate to PSResourceGet for Gallery installs
- Changed: user state moved to a data root separate from the module install, so module updates never touch your data
- Changed: the GitHub update check is skipped for Gallery installs (PSResourceGet handles updates)

### 0.1.0 — 2026-05-27

- Added: 16 bundled themes — umbrella, kitty, golden-forest, ex-machina, sober, eva, rain, gitbash, forest, neon-rain, lain, snowday, tombraider, garden-rain, marquee, and halo
- Added: interactive `tstyles` picker with live preview — instant color preview via OSC escapes, per-theme swatches, flicker-free in-place redraw, live tab title/color preview, and the cursor lands on the currently active style
- Added: `tstyles` subcommands — list, current (with inline swatch), random, direct apply (`tstyles <name>`), and uninstall — all with tab completion
- Added: per-style background images that apply automatically with a style, lazily fetched from a dedicated `gifs` branch with prefetching and a loading indicator
- Added: support for both PowerShell 7 and Windows PowerShell 5.1
- Added: one-line installer with a polished banner/step/ready-panel flow and same-tab handoff (no new tab needed after install)
- Added: update check (throttled to once per day) and a `tstyles update` command
- Added: rolling settings.json.bak backup before any direct (non-picker) style apply, with a documented one-liner restore
- Added: packaged as a proper PowerShell module (TerminalStyles.psd1 manifest + TerminalStyles.psm1)
- Changed: themes live-reload on confirm — colors and tab title update without opening a new tab

### Mining notes

Version boundaries were taken from tag targets, not bump-commit messages. Two
quirks are baked in: v0.3.0 is tagged one commit after the "bump to 0.3.0" commit
(includes the Save-As active-style fix), and the three installer fixes committed
after the 0.2.0 bump shipped in v0.2.1 per its tag. All 90+ pre-publish commits
were collapsed into 0.1.0. Pure CI/docs/plan commits were ignored.

## Issue drafts

### Issue 1 — Add more light-mode themes (only 1 of 16 themes is light)

**Labels:** `theme`, `good first issue`, `help wanted`

```markdown
## Context

Of the 16 bundled themes, **gitbash is the only light-mode theme** — the README calls it out explicitly ("The only light-mode theme in the catalog"). Users who work in bright environments or simply prefer light terminals have exactly one option, and it is a Git Bash recreation rather than an original design.

This is a great first contribution: a theme is just a folder of 2–4 small files, no PowerShell internals knowledge needed.

## What a theme looks like

See CONTRIBUTING.md and any bundled theme, e.g. `styles/gitbash/`:

    styles/<name>/
    ├── scheme.json    # Windows Terminal color scheme (required, unique "name")
    ├── theme.json     # profile-level overrides (optional)
    ├── profile.ps1    # custom prompt/banner (optional)
    └── README.md      # description (optional)

`styles/gitbash/scheme.json` is the reference for a light palette (white `background`, near-black `foreground`).

## Acceptance criteria

- [ ] At least one new original light theme under `styles/<name>/` (ideas: paper/sepia, solarized-light-adjacent, pastel morning, high-contrast light)
- [ ] `scheme.json` has a unique `name` and all standard Windows Terminal keys (see `styles/gitbash/scheme.json` for the full key list)
- [ ] Passes the existing contrast guard: every chromatic ANSI color ≥ 3:1 against the scheme background (`tests/Scheme-Contrast.Tests.ps1` — note light backgrounds make this harder; saturated yellows/cyans usually need darkening)
- [ ] `Invoke-Pester -Path tests` green (the swatch tests in `tests/Get-SchemeSwatch.Tests.ps1` also pick the theme up automatically)
- [ ] If the theme ships a background image, it goes on the `gifs` branch as `<name>.<ext>` (flat naming), not on `main` — keep it under ~2 MB and only submit images you may redistribute
- [ ] Theme section added to the README catalog + screenshot regenerated via `scripts/capture-screenshots.ps1` (maintainer can help with this step)

## Pointers

- CONTRIBUTING.md — contribution workflow
- `styles/gitbash/scheme.json` — the existing light palette to compare against
- `tests/Scheme-Contrast.Tests.ps1` — the 3:1 legibility floor your palette must clear
```

### Issue 2 — Picker: support Home/End/PageUp/PageDown and wrap-around navigation

**Labels:** `enhancement`, `good first issue`

```markdown
## Context

The interactive picker (`tstyles` with no args) only handles four keys: `UpArrow`, `DownArrow`, `Enter`, `Escape` — see the `switch ($key.Key)` block at `tstyles.ps1:2362-2393`. With 16 bundled themes (plus any user/tuned styles) reaching the bottom of the list from the top is 15 keypresses, and the cursor pins at the edges:

- `tstyles.ps1:2364` — `if ($idx -gt 0)` (no wrap from first → last)
- `tstyles.ps1:2370` — `if ($idx -lt $styles.Count - 1)` (no wrap from last → first)

## Proposal

Add to the existing `switch`:

- **Home** → jump to index 0
- **End** → jump to `$styles.Count - 1`
- **PageUp / PageDown** → move by ~5 entries, clamped
- **Wrap-around** on Up at index 0 / Down at the last index (matches most TUI pickers)

Each new case should follow the exact pattern of the existing arrow cases: update `$idx`, set `$needsRedraw = $true`, set `$pendingApply = $idx`, and emit the instant color retint with `[Console]::Out.Write($oscPackets[$idx])` (`tstyles.ps1:2363-2374`). The debounce machinery below the switch (`tstyles.ps1:2397-2406`) already collapses rapid moves into one settings.json write — no changes needed there.

Also update the key hint line in `$drawMenu` (`tstyles.ps1:2318`) if it gets too long, and the `tstyles help` overview if you mention keys (`tstyles.ps1:1799` `Get-TerminalStyleHelpData`).

## Acceptance criteria

- [ ] Home/End/PageUp/PageDown work in the picker and trigger the same instant OSC retint + debounced apply as arrows
- [ ] Up on the first entry wraps to the last; Down on the last wraps to the first
- [ ] Esc still reverts byte-exact; Enter still confirms
- [ ] Existing Pester suite stays green (`Invoke-Pester -Path tests`)

## Pointers

- `tstyles.ps1:2354-2427` — the render/input loop
- `tstyles.ps1:2362-2393` — the key `switch` to extend
- `tstyles.ps1:2313-2334` — `$drawMenu` (hint text lives here)
```

### Issue 3 — Add a `tstyles version` subcommand

**Labels:** `enhancement`, `good first issue`

```markdown
## Context

There is no way to ask `tstyles` what version is installed or which install path (PSGallery vs bootstrap) is active. Users filing bug reports have to know `Get-Module TerminalStyles` incantations. The building blocks already exist:

- `Get-TerminalStylesInstallKind` (`tstyles.ps1:200`) already distinguishes PSGallery vs bootstrap installs
- The help renderer already reads the module version best-effort: `$ver = $ExecutionContext.SessionState.Module.Version` (`tstyles.ps1:1908`)

## Proposal

`tstyles version` prints something like:

    TerminalStyles 0.6.1 (PSGallery install)
    Module root: C:\Users\me\Documents\PowerShell\Modules\TerminalStyles\0.6.1
    Data root:   C:\Users\me\AppData\Local\TerminalStyles

(`$script:TStylesModuleRoot` and `$script:TStylesDataRoot` are set at `tstyles.ps1:12-20`.)

## Where to wire it in (all four places — there is a drift-guard test)

1. **Dispatch:** add a line to the subcommand dispatch block at `tstyles.ps1:2058-2066`
2. **Help data:** add an entry to `Get-TerminalStyleHelpData` (`tstyles.ps1:1799-1868`) — a drift-guard test asserts every dispatched subcommand has a help entry (see `tests/Get-TerminalStyleHelpData.Tests.ps1` and the comment at `tstyles.ps1:1803-1804`)
3. **Tab completion:** add `'version'` to the `$subcommands` array in the argument completer (`tstyles.ps1:2496`)
4. **README:** add a row to the subcommand table

## Acceptance criteria

- [ ] `tstyles version` prints version + install kind, works on both pwsh 7 and Windows PowerShell 5.1
- [ ] Degrades gracefully when the module version is unavailable (dot-sourced dev checkout — `$ExecutionContext.SessionState.Module` is `$null` there, same guard as `tstyles.ps1:1908-1910`)
- [ ] `tstyles help version` shows a detail page
- [ ] Tab completion includes `version`
- [ ] New Pester test for the dispatch (pattern: `tests/Invoke-TerminalStyle-HelpDispatch.Tests.ps1`)
- [ ] Full suite green
```

### Issue 4 — Add a scheme.json completeness + format validation test

**Labels:** `enhancement`, `good first issue`

```markdown
## Context

The test suite guards contrast (`tests/Scheme-Contrast.Tests.ps1`) and swatch distinguishability (`tests/Get-SchemeSwatch.Tests.ps1`), but **nothing asserts a bundled `scheme.json` is structurally complete**. The contrast test explicitly skips absent keys:

    # tests/Scheme-Contrast.Tests.ps1:33
    if (-not $scheme.$key) { continue }

So a theme PR that forgets `brightRed`, typos `forground`, or uses `#fff` shorthand sails through CI, and the breakage only shows up at runtime in Windows Terminal (or as a confusing swatch). With the "more themes" contribution push, a structural validator becomes the contributor safety net.

## Proposal

New `tests/Scheme-Schema.Tests.ps1` that, for every `styles/*/scheme.json`:

- [ ] Parses as strict JSON
- [ ] Has a non-empty `name` that is **unique across all bundled themes** (the merge logic dedupes schemes by name — `tstyles.ps1:493` — so a duplicate name would shadow another theme)
- [ ] Contains all keys Windows Terminal expects: `background`, `foreground`, `cursorColor`, `selectionBackground`, plus the 16 ANSI slots (`black`, `red`, `green`, `yellow`, `blue`, `purple`, `cyan`, `white` and their `bright*` variants) — `styles/gitbash/scheme.json` shows the full set
- [ ] Every color value matches `^#[0-9a-fA-F]{6}$` (the swatch renderer hard-requires 6 hex digits: `if ($h.Length -lt 6) { continue }` at `tstyles.ps1:726`, so shorthand hex silently drops a swatch cell)
- [ ] No unknown extra keys (catches typos like `forground`) — warning-level is fine if strictness is controversial

Follow the existing discovery pattern (enumerate `styles/*` in `BeforeDiscovery`, one `It` per theme/key via `-ForEach`) used by `tests/Scheme-Contrast.Tests.ps1:16-38` so new themes are covered automatically.

## Acceptance criteria

- [ ] New test file passes against all 16 current themes
- [ ] Deleting a key or mangling a hex value in any scheme makes the test fail with a message naming the theme and key
- [ ] Runs in CI via the existing `Invoke-Pester -Path tests` workflow (`.github/workflows/test.yml`)
```

### Issue 5 — Picker: type-to-filter style search

**Labels:** `enhancement`, `help wanted`

```markdown
## Context

The picker renders all styles in a flat list with arrow-key navigation only (`tstyles.ps1:2313-2334` `$drawMenu`, input loop at `2354-2427`). As users accumulate tuned/custom styles (user dir styles are unioned in via `Get-AvailableStyles`, `tstyles.ps1:613-637`), finding one by name means scanning visually and arrow-keying.

## Proposal

Let the user type letters to filter the list incrementally (the common fuzzy-picker UX):

- Printable chars append to a filter buffer; `Backspace` removes one char; the filter is shown in the header area
- The list re-renders showing only styles whose names match (`-like "*$filter*"` is fine; prefix-match is acceptable for v1)
- `$idx` is clamped/reset into the filtered set; Enter confirms the highlighted filtered entry; Esc with a non-empty filter clears the filter first, Esc with an empty filter cancels as today
- The OSC retint + debounced apply must follow the *filtered* selection (the `$oscPackets`/`$mergedCache`/`$swatches` hashtables at `tstyles.ps1:2143-2150, 2237, 2308-2311` are keyed by absolute style index — a filtered view needs an index mapping layer)

## Gotchas (why this is not a one-liner)

- The in-place repaint assumes a **constant** line count: "the number of lines is constant (header + hint + blank + N styles + blank), so the overwrite covers the previous frame exactly" (`tstyles.ps1:2268-2274`). A shrinking filtered list leaves stale rows — you must either `Clear-Host` on filter change, or append `\e[K`/blank-pad lines as the comment itself suggests
- Keep `Escape` semantics unambiguous (clear-filter vs cancel)

## Acceptance criteria

- [ ] Typing filters the list live; Backspace edits the filter; filter text is visible
- [ ] Enter applies the highlighted filtered style; Esc behavior as described above
- [ ] No stale rows left on screen when the list shrinks
- [ ] Up/Down (and any keys from the Home/End issue, if merged first) operate on the filtered view
- [ ] Pester suite green

## Pointers

- `tstyles.ps1:2313-2334` — `$drawMenu`
- `tstyles.ps1:2354-2427` — input loop and debounce
- `tstyles.ps1:2268-2274` — the constant-line-count repaint assumption you'll be breaking
```

### Issue 6 — Previewing a style without a bundled background leaves a stale background image

**Labels:** `bug`, `help wanted`

```markdown
## Context

From the README (§ Known limitations):

> **Preview carryover for bundle-less styles.** Arrow-keying from a style with a bundled `background.*` onto a style without one leaves the previous GIF visible (the bundle-less path doesn't touch background fields).

Root cause: in `Merge-StyleIntoSettings`, when the user passed no `-BackgroundImage` and the style has no bundled background, the bg action resolves to `'skip'` and the four background fields are left exactly as they are in the settings being merged into (`tstyles.ps1:509-530`, action table at `528-530`, skip at `538`). Each picker preview merges into the **original** settings snapshot (`tstyles.ps1:2342-2343`), so if the user's pre-picker state already had a TerminalStyles background (from a previously confirmed style), every bundle-less style previews *and confirms* with that leftover image under its own colors.

The `'skip'` behavior is deliberate for one case: a user's **own** hand-set background should survive applying a bundle-less style (`tstyles.ps1:513` "leave user's existing bg alone"). The bug is that a background *previously written by TerminalStyles itself* is indistinguishable from a user's own and gets the same hands-off treatment.

## Possible approaches (design discussion welcome on the issue first)

1. **Tag our writes:** when applying a background, also record the applied image path in the state dir; on merge, if the existing `backgroundImage` equals the recorded TerminalStyles-applied path, treat bundle-less as `'remove'` instead of `'skip'` (`$script:TStylesBgFields` at `tstyles.ps1:30-31` is the field list)
2. **Picker-only fix:** within a picker session, if the *previous previewed* style applied a background and the next one is bundle-less, force `'remove'` for the preview
3. Document-only: keep behavior, improve the workaround hint (`-BackgroundImage ""`) in the picker UI

Option 1 also fixes the confirm case, not just the preview, and aligns with `Reset-StyleDirect` which already strips these fields (`tstyles.ps1:1988-1995`).

## Acceptance criteria

- [ ] Arrow-keying umbrella → sober in the picker no longer shows umbrella's GIF behind sober's colors when umbrella (or any bg style) was the pre-picker state
- [ ] A background the user set by hand (never written by TerminalStyles) still survives applying a bundle-less style
- [ ] Esc still reverts byte-exact
- [ ] Pester coverage for the new merge behavior (extend `tests/Merge-StyleIntoSettings.Tests.ps1`)
- [ ] README Known-limitations entry updated/removed

## Pointers

- `tstyles.ps1:509-558` — bg resolution + the three-action table
- `tstyles.ps1:2336-2349` — picker `$applyTheme`
- `tstyles.ps1:30-31` — `$script:TStylesBgFields`
```

### Issue 7 — Track the active style in a state file

**Labels:** `enhancement`

```markdown
## Context

Active-style detection works by **byte-comparing** `current-style.ps1` against every style's `profile.ps1` (`Get-CurrentStyleName`, `tstyles.ps1:639-652`). That makes detection prompt-based, with documented blind spots:

- A `-KeepPrompt` apply never copies `profile.ps1`, so `tstyles current` and the `*` marker in `tstyles list` don't report it — called out in the README
- A style without a `profile.ps1` is undetectable the same way (the loop skips styles lacking the file, `tstyles.ps1:646-647`)
- The picker also uses this to position the cursor on the active style (`tstyles.ps1:2129-2135`), so it falls back to index 0 in these cases

## Proposal

Write the applied style's name to a small state file (e.g. `%LOCALAPPDATA%\TerminalStyles\active-style.json` — `$script:TStylesDataRoot` is defined at `tstyles.ps1:20`) at every apply point, and make `Get-CurrentStyleName` read it first, falling back to the existing byte-compare for users upgrading mid-flight.

Apply/clear points to cover:

- `Apply-StyleDirect` (`tstyles.ps1:801`) — direct applies incl. `-KeepPrompt`
- The picker confirm path (`tstyles.ps1:2429-2453`)
- `Invoke-RandomStyle` (`tstyles.ps1:784`) — goes through Apply-StyleDirect already
- `Save-TunedStyle` / tune save flow (`tstyles.ps1:1369`)
- `Reset-StyleDirect` (`tstyles.ps1:1941`) — must **delete** the state file

Edge cases: the recorded style may since have been deleted from disk (validate with `Get-StyleDir`, `tstyles.ps1:596`); per-Target applies mean "active" is technically per-profile — recording the most recent apply is an acceptable v1, but say so in the file format (`{ "style": "eva", "target": "PowerShell", "keepPrompt": true }` leaves room).

## Acceptance criteria

- [ ] `tstyles eva -KeepPrompt; tstyles current` prints `eva`
- [ ] `tstyles list` stars the style after a `-KeepPrompt` apply
- [ ] `tstyles reset` clears it; `tstyles current` reports none
- [ ] Picker opens positioned on the recorded style
- [ ] Byte-compare fallback still works when the state file is absent (fresh upgrade)
- [ ] Tests updated: `tests/Get-CurrentStyleName-TunedDistinct.Tests.ps1`, `tests/Apply-StyleDirect-KeepPrompt.Tests.ps1`
- [ ] README note removed/updated
```

### Issue 8 — Deduplicate the six library functions copy-pasted into apply.ps1

**Labels:** `enhancement`, `bug`

```markdown
## Context

`apply.ps1` (the scriptable one-shot applier) duplicates six functions from `tstyles.ps1`, each with a manual "keep in sync" warning:

- `Remove-JsonComment` — `apply.ps1:31-33`: "NOTE: duplicated from tstyles.ps1 -- keep in sync"
- `Remove-JsonTrailingComma` — `apply.ps1:80-85`: same note
- `ConvertFrom-WTJson` — `apply.ps1:123-125`: same note
- `Get-StyleBundledBackground` — `apply.ps1:150-153`: "See tstyles.ps1 for full notes" (and this copy has **already drifted**: it writes fetched backgrounds and the `.no-background` marker into the *style dir* (`apply.ps1:160, 170, 187`), while tstyles.ps1 moved to a per-user cache dir precisely because the style dir is read-only on PSGallery installs — `tstyles.ps1:77-143`)
- `Find-SettingsPath` — `apply.ps1:192-195`: "mirrors tstyles.ps1 Find-WTSettingsPath"
- `Write-WTSettingsFile` — `apply.ps1:257-260`: "mirrors tstyles.ps1's Write-SettingsFile/Write-SettingsAtomic -- keep in sync"

History shows the sync rule fails in practice (recent fixes for trailing commas, atomic writes, and depth-100 each had to be applied twice). The drift in `Get-StyleBundledBackground` above is live evidence.

## Proposal

`apply.ps1` already has the load-without-run hook for tests: `if (-not $TStylesApplyNoRun) { ... }` (`apply.ps1:286-289`). Mirror that idea in the other direction — have `apply.ps1` dot-source the library next to it and delete the copies:

    . (Join-Path $PSScriptRoot 'tstyles.ps1')

Constraints to respect:

- `tstyles.ps1` runs side effects at load: data-root creation (`tstyles.ps1:21-23`), state migration (`tstyles.ps1:2509`), and dot-sources `current-style.ps1` inside Windows Terminal (`tstyles.ps1:2515-2517`). Either gate those behind a `$TStylesLibraryOnly` guard variable, or accept them (they are idempotent) — decide and document
- `apply.ps1` must keep working when run from a repo checkout **and** from `%LOCALAPPDATA%\TerminalStyles\` (both ship the pair side-by-side — `install.ps1` copies both)
- `apply.ps1`'s `Merge-ThemeIntoEntry` (`apply.ps1:227-255`) is a behavioral sibling of `Merge-StyleIntoSettings` (`tstyles.ps1:469`) with subtly different bg-field semantics — converging those two is a stretch goal, fine to leave for a follow-up

## Acceptance criteria

- [ ] No function bodies duplicated between the two files; "keep in sync" comments gone
- [ ] `pwsh -File apply.ps1 -Style umbrella -Target PowerShell -SettingsPath <scratch>` works from a clean checkout
- [ ] `tests/Apply-WriteWTSettings.Tests.ps1` and the rest of the suite green
- [ ] The `Get-StyleBundledBackground` cache-dir drift is fixed as a side effect (apply.ps1 path now writes to the user cache dir)
```

### Issue 9 — Picker breaks/overflows when the style list is taller than the terminal window

**Labels:** `bug`, `enhancement`

```markdown
## Context

The picker renders a fixed frame — header (4 lines + blank) plus **one line per style** plus a trailing blank — and repaints by jumping back to a saved row: `[Console]::SetCursorPosition(0, $renderHomeY)` (`tstyles.ps1:2314`), with `$renderHomeY` captured once after a single `Clear-Host` (`tstyles.ps1:2275-2276`).

With the 16 bundled themes this fits a default 30-row terminal. But the list also unions user styles and tuned styles (`Get-AvailableStyles`, `tstyles.ps1:613-637`), and `tstyles tune` actively encourages saving new ones. Once `6 + N` exceeds the window height:

- The first frame scrolls the buffer, so `$renderHomeY` (a buffer coordinate captured pre-scroll) no longer matches where the frame actually starts — subsequent repaints draw over the wrong rows / interleave garbage
- Entries below the fold are unreachable visually even though arrow keys move `$idx` onto them (selection indicator scrolls out of view)

A small terminal (e.g. a half-height pane) hits this today with just the bundled 16.

## Proposal

Give the picker a scrolling viewport:

- Compute `$visibleRows = [Console]::WindowHeight - <chrome lines>` each frame
- Maintain a `$scrollTop` so the highlighted index stays in view (classic follow-the-cursor windowing)
- Render only the visible slice; show `↑ more` / `↓ more` markers (or `x/N` in the header) when clipped
- Recompute on `WindowHeight` change between frames (cheap check per loop iteration; the loop already idles at `tstyles.ps1:2424-2426`)

Keep the existing repaint strategy (no per-frame `Clear-Host` — the in-place overwrite exists to avoid flicker, see the comment at `tstyles.ps1:2266-2274`); just make the painted region's height bounded so `$renderHomeY` stays valid.

## Acceptance criteria

- [ ] Picker is fully usable in a 15-row terminal with 16 styles: selection always visible, no garbled repaints
- [ ] 30+ styles (add scratch dirs under `%LOCALAPPDATA%\TerminalStyles\styles\` to simulate) scroll smoothly
- [ ] No regression in the flicker-free behavior at normal sizes
- [ ] Esc/Enter behavior unchanged

## Pointers

- `tstyles.ps1:2275-2276` — `Clear-Host` + `$renderHomeY` capture
- `tstyles.ps1:2313-2334` — `$drawMenu` (renders all N rows unconditionally)
- `tstyles.ps1:2354-2427` — the render loop
```

### Issue 10 — Restructure: split the 2,517-line tstyles.ps1 monolith into a conventional module layout

**Labels:** `enhancement`, `help wanted`

```markdown
## Context

All 43 functions live in one 119 KB file, `tstyles.ps1` (2,517 lines). The module wrapper plan (docs/superpowers/plans/2026-05-27-module-restructure.md) was executed as designed — but that plan's stated goal was explicitly *"without restructuring the existing code"*: `TerminalStyles.psm1` is a one-line dot-source of the monolith. The actual decomposition was deferred and never planned.

Pain points today:

- Contributors touching the picker scroll past JSON parsing, update-check throttling, font enumeration, and the tuner to find it
- `apply.ps1` can't reuse the library cleanly (see the dedup issue) partly because loading `tstyles.ps1` drags in load-time side effects (`tstyles.ps1:21-23, 2509, 2515-2517`)
- Review diffs all collide in one file

## Proposed target layout (conventional PS module shape)

    TerminalStyles/
    ├── TerminalStyles.psd1
    ├── TerminalStyles.psm1          # dot-sources Public/ + Private/, runs load-time side effects
    ├── Public/
    │   ├── Invoke-TerminalStyle.ps1
    │   └── Invoke-TerminalStylesUpdate.ps1
    └── Private/
        ├── Json/        # Remove-JsonComment, Remove-JsonTrailingComma, ConvertFrom-WTJson (tstyles.ps1:351-467)
        ├── Settings/    # Find-WTSettingsPath, Merge-StyleIntoSettings, Write-SettingsAtomic/File (tstyles.ps1:38-56, 469-594)
        ├── Styles/      # Get-StyleDir, Get-AvailableStyles, Get-StyleBundledBackground, Test-StyleResolved (tstyles.ps1:596-687)
        ├── Picker/      # swatches, OSC packets (tstyles.ps1:689-734, 1211-1244)
        ├── Tuner/       # Convert-*, Get-AdjustedScheme, Save-TunedStyle, Invoke-TerminalStyleTune (tstyles.ps1:1124-1797)
        └── Lifecycle/   # install-kind, update check, register, uninstall, migration (tstyles.ps1:145-349, 894-1122)

## Constraints (what makes this hard)

- **Both engines:** everything must keep working on Windows PowerShell 5.1 *and* pwsh 7 (`#Requires -Version 5.1`)
- **Load-time side effects** (data-root creation, `Invoke-TerminalStylesStateMigration` at `tstyles.ps1:2509`, conditional dot-source of `current-style.ps1` at `2515-2517`, `Set-Alias`/`Register-ArgumentCompleter` at `2489-2505`) must run exactly once, in the right order, from the psm1
- **`$script:` state** (`TStylesModuleRoot`, `TStylesDataRoot`, `TStylesCurrent`, `TStylesBgFields`, `TStylesThemeFields` — `tstyles.ps1:12-34`) must remain module-scoped and visible to every relocated function
- **Tests:** 37 Pester files use `InModuleScope TerminalStyles` — they should survive mostly untouched if exported surface stays identical
- **apply.ps1 + install.ps1** both reference `tstyles.ps1` by name; the bootstrap installer's file list and the PSGallery package layout (`scripts/publish.ps1`) need updating
- Backward compat: a `tstyles.ps1` shim that dot-sources the new layout could keep old `$PROFILE` loader lines working for bootstrap users who haven't re-run install

Recommend an incremental, CI-green-at-every-commit sequence (move one functional area per commit, full suite after each).

## Acceptance criteria

- [ ] No behavior change: exported surface stays `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`, alias `tstyles`
- [ ] All test files green on both engines
- [ ] Bootstrap install, PSGallery install, `tstyles update`, and `apply.ps1` all verified end-to-end
- [ ] No single file over ~500 lines
```

### Issue 11 — User comments in settings.json are silently deleted on first apply

**Labels:** `bug`, `help wanted`

```markdown
## Context

Windows Terminal allows `//` and `/* */` comments in `settings.json`, and users annotate their profiles. TerminalStyles strips them to parse on Windows PowerShell 5.1 — `Remove-JsonComment` (`tstyles.ps1:351-401`) inside `ConvertFrom-WTJson` (`tstyles.ps1:448-467`) — and then re-serializes the parsed object with `ConvertTo-Json` (picker: `tstyles.ps1:2251`, direct apply via `Write-SettingsFile`: `tstyles.ps1:587-594`). **The comments are gone from the file permanently after the first apply.**

The README's Known-limitations entry undersells this: "JSON reformatting. Each apply reformats settings.json cosmetically ... Functionally identical". Reformatting is cosmetic; deleting a user's comments is data loss of user-authored content. The picker's Esc path is safe (byte-exact revert, `tstyles.ps1:2384-2391`) and `.bak` files preserve one prior state — but a confirmed apply commits the comment-stripped version.

## Options (in increasing effort — maintainer input wanted before starting)

1. **Warn + document (small):** detect comments before the first write (`Remove-JsonComment` output differing from input is a cheap test), print a one-time yellow warning that comments will be removed and a `.bak` exists, and fix the README wording
2. **Preserve verbatim non-touched regions (hard):** a surgical writer that only patches the keys TerminalStyles owns (`$script:TStylesThemeFields`, `tstyles.ps1:32-34`, plus the `schemes` array) into the original text, leaving everything else byte-identical. This also fixes the reformatting limitation wholesale, but means hand-rolling JSONC-aware text patching on PS 5.1 — substantial and edge-case-prone
3. **Comment round-trip (middle):** map each stripped comment to its preceding/owning JSON path during `Remove-JsonComment`, and re-inject after `ConvertTo-Json`. Fragile against WT's own rewrites; probably not worth it vs option 2

Option 1 is a reasonable standalone first PR even if option 2 is the long-term goal.

## Acceptance criteria (option 1 baseline)

- [ ] First apply against a commented settings.json prints a clear warning (once, not per arrow-key) before anything is written
- [ ] README Known-limitations entry explicitly mentions comment removal, not just reformatting
- [ ] Pester test: commented input → warning emitted; uncommented input → no warning

## Pointers

- `tstyles.ps1:351-401` — `Remove-JsonComment`
- `tstyles.ps1:448-467` — `ConvertFrom-WTJson`
- `tstyles.ps1:2243` — picker writes the rolling `.bak` (recovery copy that still has the comments)
- `apply.ps1:31-78` — duplicated copy with the same behavior (see the dedup issue)
```
