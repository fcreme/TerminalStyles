# Live style creator — design

**Date:** 2026-11-06
**Status:** Written up from a conversation with the maintainer; pending their review
**Component:** a new `tstyles create` command and the code behind it; the
existing tuner (`tstyles tune`) is unchanged

## Why

Making a new style today means running `tstyles tune <style>`. You pick an existing
style and move five sliders: brightness and saturation of the whole palette, opacity,
font face and font size. Then you Save As a new name. That is a tuner, not a creator:

- You can only nudge someone else's style. You cannot pick a single colour, choose a
  background colour, or start from your own image.
- The parts that give a style its character are out of reach. The background image,
  the prompt and its symbol, the cursor, and the tab title and colour live in
  `theme.json`, `profile.ps1` and `prompt.sh`, which you would edit by hand.
- What you see while tuning is a small swatch under a menu, not your terminal as it
  will look.

The maintainer called it "a little weird". The idea is an **RPG character creator for
the terminal**: you build the style step by step, and your real terminal window
changes as you go, so you always see the finished look.

## What it is

`tstyles create` opens a **step-by-step creator** in the Windows Terminal window you
run it from. There is one page per step, with Enter for the next step and a key to go
back. The window itself is the preview the whole time. Each page shows a short sample
session (a prompt, some coloured command output, the cursor) below the controls, so
every colour has something to land on. The layout follows mockup B from the
conversation: a panel of controls at the top, the sample session below, and the
chosen image behind everything. The sample session is fixed, made-up content: a
`git status` with a modified and a deleted file, an `ls`, and the prompt. It does not
read the user's real folder or git branch.

### The steps

1. **Background (the maintainer's first decision).** You choose an image file from
   your computer: a PNG, JPEG or GIF, typed or pasted as a path. It appears behind the
   text at once. On the same page you adjust how strongly it shows (the opacity that
   WT calls `backgroundImageOpacity`), how it fits (`backgroundImageStretchMode`) and
   where it sits (`backgroundImageAlignment`), each live. The image is **copied into
   the new style's folder** as `background.<ext>`, so the style keeps working if the
   original file moves or is deleted.
2. **Colours (the maintainer's decision: pull a palette first).** TerminalStyles
   builds a full scheme from the image: background, foreground, cursor, selection and
   the 16 terminal colours. It applies the scheme at once. You then pick any single
   colour and change it, and the window updates as you go. Changing colours in a
   single step must stay responsive. A colour you set by hand that falls below the
   readability bar is **allowed, with a visible warning** on the page and again
   before save, never blocked or silently changed. **Re-pulling** the palette from
   the image replaces only the colours you have not changed by hand.
3. **Font and cursor.** The font face and size, and the cursor shape, each live.
4. **Prompt (the maintainer's decision: colours and symbol).** You choose one of a few
   ready-made **prompt shapes**:
   - minimal: `projects $`
   - full path: `~/code/projects $`
   - two lines: the path on one line, the symbol on the next
   - with git branch: `projects (main) $`

   Then you choose the prompt's colours and its **symbol** (`$`, `>`, `❯`, `λ`, and so
   on). TerminalStyles generates both halves of the prompt, `profile.ps1` for
   PowerShell and `prompt.sh` for bash/zsh. They must render **byte-identically**,
   the promise every style makes. The **sample session** on this page shows the
   chosen prompt. The user's real shell prompt is not swapped during creation; it
   changes only when the saved style is applied.
5. **Name and save.** You give the style a name, validated with the tuner's rule
   (`Test-StyleNameValid`). **A name that is already taken is refused**, whether
   it's one of the user's own styles or a built-in one like `eva`. The page says the
   name is taken and asks for another, so the creator never overwrites or shadows a
   style (the maintainer's decision). It is saved to the user styles directory as a normal style
   (`scheme.json`, `theme.json`, `profile.ps1`, `prompt.sh`, `meta.json`, the
   background file) and applied. Afterwards `tstyles <name>`, `tstyles tune <name>`,
   `tstyles list` and the picker treat it like any other style.

**Esc, at any step, cancels.** The terminal and every file the preview touched go back
exactly as they were before `tstyles create` started.

## Goals

- Every change is visible in the running Windows Terminal window as you make it:
  image, image settings, every colour, font and cursor, with the prompt shown in the
  sample session.
- The result is an ordinary style, indistinguishable from a hand-made one to every
  other command.
- Cancelling, or a crash or closed tab mid-creation, never costs the user their
  `settings.json` or their current look. The picker and the tuner already meet this
  bar through `lib/previewsession.ps1`.

## Non-goals (first version)

- **A free-form prompt builder.** The maintainer agreed to a fixed set of shapes. More
  shapes can be added later without changing how the step works.
- **Live preview outside Windows Terminal.** On WezTerm the background could also be
  live; on Terminal.app, iTerm2 and others only the colours can be. In the first
  version `tstyles create` on another terminal either refuses with a clear message,
  or runs with colours-only preview and says so up front, like the tuner does today.
  The builder chooses; see "Left to the builder".
- **Changing an existing style with the creator.** `tstyles tune` stays as it is.
- **Images from the internet.** A file on this computer only.
- **Submitting a style to ship with TerminalStyles.** The maintainer wants users to be
  able to submit a style they made, for the maintainer to approve or reject as a
  built-in style for everyone. That is the **next project**, designed separately
  after the creator. The creator's job is to save a complete, normal style folder,
  which is what a submission would contain.
- **Startup banners, the `meta.json` quote, and other per-style extras.**

## Anti-goals

The maintainer said nothing specific would make it a failure and that rough edges
will be worked out together. These follow from the project's rules (CLAUDE.md) and
would make it a failure even if it worked:

- Leaving the user's Windows Terminal `settings.json` or current style changed after
  Esc, a crash or a closed tab.
- A saved style whose PowerShell and bash/zsh prompts look different.
- A message that claims more than happened, such as "Saved" when a file failed to
  write.

## Constraints

- **Windows PowerShell 5.1 and pwsh 7**, as everywhere in this repo: ASCII-only string
  literals in `.ps1`, and none of `?:`, `??` or `&&`. CI runs both engines, plus macOS
  and Ubuntu.
- **Live preview of the image, font, cursor and opacity goes through Windows
  Terminal's `settings.json`** (the same debounced merge the tuner and picker use), and
  colours through OSC. Reuse `lib/previewsession.ps1` for recording and restoring the
  preview, including recovery after a closed tab. Don't write a second mechanism.
- **Reading an image's pixels** to pull a palette. `System.Drawing` is already used in
  `lib/fonts.ps1` on Windows. For a GIF the first frame is enough. Large images should
  be downscaled before analysis so the step stays responsive.
- **The palette must be readable.** Foreground on background, and the ANSI colours on
  the background, need enough contrast. `lib/color.ps1` already has
  `Get-ContrastRatio` and `Get-SchemeUnreadableSlots`. Slots map to their usual roles
  (red reads red, green reads green, and so on) closely enough that `git status`,
  `ls` and errors keep their meaning.
- **Style files** follow the existing layout: `scheme.json` (21 colours, see
  `styles/sober/scheme.json`), `theme.json` (see `styles/eva/theme.json`, including
  `{{BACKGROUND_IMAGE}}` as the image placeholder), `profile.ps1`, `prompt.sh`,
  `meta.json`. Shell-side names in `prompt.sh` are `_ts_`-prefixed on every column.
- **Interactive guards**, like the tuner's: refuse cleanly when input or output is
  redirected, before touching the terminal.
- **Every new code path that writes a file the user owns** follows CLAUDE.md:
  first-touch backups, encodings, and sandboxed tests that never reach the real
  `$HOME`.

## Decided in conversation

| Question | Decision |
|---|---|
| What do you decide first? | The background image. |
| Where does the image come from? | A file on your computer. |
| Which terminal? | Windows Terminal. |
| Colours | Pull a palette from the image first, then change any single colour. |
| Layout | **B: one step at a time**, one page per step, with a way to go back (chosen over A, everything on one screen). |
| Prompt | Pick a shape from a few presets, then its colours and its symbol. Recommended by Claude, agreed by the maintainer. |
| A name already taken | Refused, and the page asks for another, for the user's own styles and built-in ones alike. Recommended by Claude, agreed by the maintainer. |
| Submitting styles for everyone | Wanted, as a separate project after the creator. |

## Calls made by Claude (not discussed; open to change)

- The command is `tstyles create`, a new subcommand. `tune` stays unchanged.
- The image is copied into the new style's folder.
- The steps after colours are font and cursor, then prompt, then name and save.
- The tab title defaults to the style's name in upper case, and the tab colour to the
  palette's accent. Neither gets its own step in the first version.
- Saving also applies the new style.
- Banners are left out of the first version.
- The prompt is previewed in the sample session only, not by swapping the user's real
  prompt. That would need restoring a live `global:prompt`, and couldn't work at all
  when `tstyles create` runs from bash or zsh.
- A hand-picked colour that is hard to read is allowed with a warning, not blocked.
  Re-pulling the palette keeps the colours you changed by hand.
- The sample session is fixed, made-up content.

## Left to the builder

- How the palette is extracted (for example k-means or median cut on a downscaled
  image) and how colours are assigned to the 16 ANSI slots, within the readability
  constraint above.
- How a single colour is edited on the colours page: hue, saturation and lightness
  sliders, hex entry, nudging, or a mix. Keyboard only.
- How the file path is entered on the background page. Typing or pasting is enough;
  a file dialog is optional.
- Exactly which prompt symbols are offered, and the colour roles inside a prompt
  shape (for example path colour and symbol colour).
- On a terminal other than Windows Terminal, whether to refuse or to offer
  colours-only preview, and the wording.
- How the pages are drawn and which keys they use, consistent with the tuner and
  picker (arrows, Enter, Esc).
- File layout inside `lib/`, and how the generated `profile.ps1` / `prompt.sh` are
  templated.
