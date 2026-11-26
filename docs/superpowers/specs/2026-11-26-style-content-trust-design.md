# Style content trust (audit batch 3)

Status: approved 2026-11-26 ("go with ur picks"). Short design: four audit items
(#44, #89, #20, #40 of the October audit, re-checked against main at 1ff0a8b).

## Intent

A style is files someone else may have written: `tstyles submit` invites
styles from strangers, and a style folder can be handed around without going
through that review. Three things should hold for any style folder, bundled
or not:

- **Browsing runs nothing.** Listing, showing and arrowing through styles
  never lets text from a style act on the terminal.
- **Apply writes only what reset takes back.** Whatever an apply puts on a
  Windows Terminal profile, `tstyles reset` removes.
- **A broken style fails before anything is touched.** No backup spent, no
  record written, no "Style applied".

Non-goals: a style's `profile.ps1` and `prompt.sh` are code, and applying a
style runs them; that is by design and unchanged. Windows Terminal validates
its own values, so the 13 keys are not shape-checked beyond `backgroundImage`.

## Approaches (for #44, what `theme.json` may put on a profile)

- **A. Only the keys reset knows (`$script:TStylesThemeFields`), picked.**
  Other keys are skipped and named once on apply. Apply and reset read one
  list and cannot drift. Costs a hand-made style any extra keys; no bundled,
  created or tuned style has one.
- B. Any appearance key, recorded per apply so reset removes exactly those,
  plus a block-list for keys that change what runs. Rejected: a block-list
  misses keys Windows Terminal adds later, and reset would depend on a record
  that can be lost.

## Decisions

1. **#44.** One function picks the `theme.json` fields an apply may write:
   the 13 keys, and `backgroundImage` only as the `{{BACKGROUND_IMAGE}}`
   placeholder or a path on this machine (no `\\server` or `//server` path,
   no URL other than `ms-appdata:`, `ms-appx:` or `file:///`). Everything
   else is returned as skipped, with a reason. The merge writes only the
   picked fields; the two applies that write settings.json (`tstyles <name>`
   and `apply.ps1`) name the skipped keys once. `-BackgroundImage` from the
   command line is the user's own choice and is not checked.
2. **#89.** `ConvertTo-VisibleText` moves from `scripts/review-submission.ps1`
   into the module (`lib/text.ps1`); the script dot-sources it, so there is
   one rule. It shows control characters as `\xNN` and invisible format
   characters as `\uNNNN`. `Get-StyleMeta` passes the description and quote
   through it (line breaks and tabs first become spaces: both are one-line
   fields), and so does the picker's live title preview for `tabTitle`.
   `submit` refuses those characters in the description and quote, and its
   `tabTitle` check uses the same character class.
3. **#20.** One reader parses a style's `scheme.json` or `theme.json`
   (through `ConvertFrom-JsoncText`; an empty file or a JSON `null` counts as
   unreadable) and throws a message naming the style, the file and how to fix
   it. A readability check built on it answers "can this style be applied?"
   - Every apply refuses an unreadable style before any backup, write, record
     or prompt.
   - The picker lists it but never previews it, and says why on its row.
   - `random` skips it.
   - `tstyles list` marks it, as it already does for an unreadable scheme.
   - `tstyles tune <name>` refuses it up front.
4. **#40.** CONTRIBUTING's by-hand route lists what CI actually requires of a
   new theme, as measured on 2026-11-26 by adding one exactly as the guide
   said (10 tests failed): `meta.json`, the README's theme counts, the banner
   (`scripts/make-banner.py`), the docs site's style and image lists, and a
   swatch distinct from every other style's. It names the real checks instead
   of "three", and stops calling a `tstyles tune` folder submittable (`submit`
   refuses one). `tests/Contributing-MatchesCI.Tests.ps1` grows to hold the
   guide to those requirements.

## Left to the builder

Function names, message wording (every message is a claim: it must be true
on every path that prints it), where each test lives, and how the picker
shows an unreadable row. CHANGELOG entries under `[Unreleased]`, and the
wiki pages that describe `theme.json` keys.
