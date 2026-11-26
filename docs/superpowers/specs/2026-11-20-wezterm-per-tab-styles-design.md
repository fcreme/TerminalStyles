# WezTerm: a style per tab — design

**Date:** 2026-11-20
**Status:** Written up from a conversation with the maintainer; builder-checked; pending
the maintainer's review
**Component:** the WezTerm writer (`lib/wezterm.ps1`), its apply/reset/uninstall callers
(`lib/applystyle.ps1`), the picker and tuner previews (`tstyles.ps1`), the shell
loaders (`shell/tstyles.sh`, the pwsh startup), `terminals.ps1` capabilities,
`lib/fonts.ps1` advice, docs

## Why

In WezTerm, `tstyles <name>` restyles **every** window and tab at once. The
maintainer: "now all have the same, when I change one tab the others change also."
They want each tab (and so each window) to keep its own style, so that running
`tstyles` in one tab changes that tab and leaves the rest alone.

The cause is structural. Every WezTerm window loads the one generated module,
`~/.config/wezterm/terminalstyles.lua`. Each apply rewrites it, and WezTerm reloads
every window from it. The OSC colour packet already goes to one tab only, but the
background GIF, opacity, blur, font, padding, cursor and tab-bar colour all come from
that shared file.

## What it is, from the user's side

- `tstyles <name>` in a tab restyles **that tab**: colours, background GIF, opacity,
  blur, cursor, tab colour. Other tabs and other windows keep what they have.
- WezTerm draws one background per **window**. A window shows the style of its
  **active tab**, and switching tabs switches the window's look. The maintainer tried
  this in a throwaway test and found it fine (see Evidence).
- **Font, size and padding are no longer set by TerminalStyles in WezTerm.** They come
  from the user's own `wezterm.lua`, in every tab. *(The maintainer's choice, option C
  of three: per-tab layout reflows the text on every switch between styles that
  differ, and a shared "last applied" layout would still change every tab on each
  apply. Every bundled style is Cascadia Code 11; they differ only in weight — normal
  or semi-bold — and padding, 10 to 16, so little is lost.)* `tstyles` names font and
  padding in its "can't show" notice in WezTerm, as it does for other terminals.
- A **new** tab or window gets the **last style applied** anywhere, as today. A new
  **split pane** gets the style of the tab it opens in.
- Applying a style in one tab does **not** restyle other tabs that already exist, even
  ones that were never styled. They keep the look they had when they opened.
- `tstyles reset` in a tab puts **that tab** back to the user's own WezTerm look, and
  makes new tabs open unstyled (today's meaning of reset for "what comes next"). Other
  existing tabs keep their styles. *(My call: it mirrors apply — this tab plus new
  tabs — so the two commands keep one rule.)*
- Commands that ask "which style is active" answer **for this tab** in WezTerm:
  `tstyles current`, the active marker in `tstyles list`, `tune` with no name,
  `random`'s "pick another", `delete` of the active style, and the picker's starting
  row. With no record for this tab they fall back to the last applied style.
  *(My call: it is what "each tab has its own style" means to someone typing in that
  tab.)*
- The picker (`tstyles` with no argument) previews in **its own tab only**. Esc puts
  that tab back; confirm is an apply in that tab. The tuner's Esc does the same.
- The prompt and banner stay per **shell**, as today: the shell you apply in swaps
  them live, and a new shell loads the last applied style's prompt. A new split in a
  tab wearing another style therefore shows that tab's look with the last applied
  prompt. *(Non-goal, stated so it is not mistaken for a bug.)*
- When WezTerm quits, tabs forget their individual styles. After a restart everything
  opens in the last-applied style. *(Stated to the maintainer; not objected to.)*
- **Windows**: WezTerm on Windows keeps today's behaviour (every tab restyled) until
  someone checks on a real Windows machine that the tab tag gets through. *(My call:
  if the tag is lost there, an apply would change only the default and leave the tab
  you ran it in on its old background — a regression from today. Nobody on this
  project can check it from macOS or a CI runner.)*

## Goals

1. Apply, reset and picker/tuner preview affect only the tab they run in, plus the
   default for new tabs.
2. Switching tabs switches the window to that tab's style with no visible lag, and
   no text reflow.
3. The user's one wiring line in `wezterm.lua` stays exactly as it is. Existing users
   upgrade by updating the module; they edit nothing.
4. A broken or missing module still costs the user only the style, never their config
   (the `pcall` contract in `lib/wezterm.ps1`'s header). Windows already open may keep
   their last look until closed (see Uninstall).

## Non-goals

- Two tabs side by side in one window showing different backgrounds at the same time.
  WezTerm cannot draw that.
- Remembering per-tab styles across a WezTerm restart.
- Different styles in two panes of one tab. A new split takes its tab's style; nothing
  more is built for panes.
- Per-tab prompts and banners (see above).
- A "reset every tab" command.
- tmux inside WezTerm. Best effort only (see Left to the builder).
- Per-tab behaviour on Windows (see above).

## Anti-goals

- Never write to the user's `wezterm.lua`. The header of `lib/wezterm.ps1` explains why.
- Never take over the user's own `update-status` / status bar. TerminalStyles' handler
  must not call `set_right_status`/`set_left_status` and must not return `false`.
- No network from the picker or the tuner's preview, and no fetch of every style's GIF
  at apply time (see Backgrounds).
- No lag or flicker storms: `set_config_overrides` is called only when a window's
  wanted style actually changes.
- No text reflow on a tab switch (why option C).

## Constraints learned in the test

WezTerm 20260917-114457-b09b56c2, macOS 26.4, a separate instance launched with
`wezterm-gui --config-file <spike.lua> start --always-new-process` (the user's real
config untouched).

- `window:set_config_overrides(t)` gives one window its own config; another window is
  unaffected. Overrides **replace** the previous override table wholesale; `{}` means
  "the base config". An override cannot say "unset this key".
- **`update-status` fires on a tab switch**, not only on its 1 s interval. Logged
  mouse-click switches: the background swapped 0–5 ms after the new tab was first
  drawn (13:06:31–13:06:35). No key rebinding is needed.
- There is **no tab-activated event** in this build (`strings wezterm-gui`: only
  `update-status`, `user-var-changed`, `window-focus-changed`,
  `window-config-reloaded`, `format-window-title` among the candidates).
- **`format-window-title` cannot reach a window object.** Calling
  `wezterm.mux.get_window()` there fails with "attempt to yield from outside a
  coroutine", and the hook runs several times a second while a GIF animates. Do no
  window work in format callbacks.
- `OSC 1337 ; SetUserVar=NAME=<base64 value> BEL` sets a per-pane user var and fires
  `user-var-changed`; `pane:get_user_vars()` reads it back. PowerShell cannot read it
  back: no escape sequence queries it.
- A per-pane OSC palette (what `tstyles` sends today) sits **on top of** the window's
  `color_scheme`. Left in place, it would mask the window's scheme whenever the tab's
  style changes by tag (a preview, a retag).
- The zsh/bash loader (`shell/tstyles.sh`) replays `current-style.osc` — the
  last-applied palette — into every new shell, including new splits, `exec zsh` and
  nested shells. The spike used `zsh -f` to keep that out of the measurement.
- The three styles in the test all had padding 12 and the same font, so the test said
  nothing about layout switches. Option C removes the question.

**Not exercised by the test** (the builder checks each, in a sandbox instance like the
spike, never the user's config): a new untagged tab showing the default; a split
taking its tab's style; retagging a live tab; whether overrides **survive a config
reload** (every apply rewrites the module, which reloads all windows); a GIF that
appears on disk after the module was written; tmux.

## Approaches

1. **Per window.** Each window keeps the style applied in it; its tabs share it. Solid
   and simple, directly supported. Rejected: two tabs in one window could not differ,
   and that is what the maintainer described.
2. **Per tab — chosen.** Each tab carries a tag naming its style; the window shows its
   active tab's style and swaps on tab switch. Includes per-window (a one-tab window).
   The risk was lag or flicker on switch; the test showed 0–5 ms and the maintainer
   found it fine.
3. Dropped early: a separate WezTerm config per window (WezTerm loads one config for
   the whole app); Lua-side keyboard rebinding for instant switches (unneeded once
   `update-status` proved to fire on switch, and it missed mouse clicks anyway).

Font and padding, a sub-decision of 2: per tab (reflow on switches), shared and
following the last apply (every apply still changes every tab), or **left to the
user's own config — chosen** (see What it is).

## How it works (decided)

### Where the colours come from

In WezTerm with the module wired, a tab's colours come **only** from its window's
`color_scheme`, which is the tab's style. So, in that case only:

- Apply, reset, and every preview/tuner Esc send the OSC **reset** packet
  (`Get-OscResetPacket`) to their tab instead of a palette, clearing any per-pane
  palette left from before, so the window's scheme shows through.
- The loaders (`shell/tstyles.sh` and the pwsh startup) do **not** replay
  `current-style.osc` in WezTerm when the module is wired. A new shell anywhere then
  shows its tab's scheme: the last applied style in a new tab, the tab's style in a
  split. *(My call; it changes the loaders, which the first draft avoided, because
  otherwise every new split and `exec zsh` paints the last applied colours over its
  tab's background.)*
- The tuner's live retint still uses an OSC palette while it runs (it is tuning
  colours no scheme holds yet); its Esc sends the reset; its save is an apply.

When the module is **not** wired, today's OSC behaviour is unchanged.

### The tag

`tstyles` tags the tab it runs in by writing
`ESC ] 1337 ; SetUserVar=TERMINALSTYLES_STYLE=<base64(value)> BEL` to the terminal,
in WezTerm only and not on Windows. The value is a style name, a reserved "unstyled"
value for reset, or a reserved preview form. The tag is written by the pwsh process,
so it works the same from zsh, bash and pwsh.

### The per-tab record (PowerShell side)

Because PowerShell cannot read the tag back, `tstyles` keeps its own record of each
tab's style, written on every apply and reset in WezTerm: keyed by the WezTerm
instance (from `$env:WEZTERM_UNIX_SOCKET`, which names the running GUI) and
`$env:WEZTERM_PANE`. The "which style is active" readers listed above read this tab's
entry first and fall back to the last applied style. Entries for instances that are
no longer running are pruned, so a pane id reused after a restart cannot inherit a
dead session's style. The last applied style (`current-style.json`) stays the record
of what new tabs get.

### The module

`terminalstyles.lua` keeps its entry point, `M.apply_to_config(config)`, so the wiring
line is unchanged. It now carries:

- **Every installed style's look**, keyed by style name (bundled and user styles), so
  any tag and any preview resolves without a file write. All `color_schemes` go into
  the base config under their existing `TerminalStyles <name>` names.
- **No font, font size or padding** for any style (option C).
- **The default** — the last-applied style, or none after a reset. `apply_to_config`
  applies it to `config`, as today's module does, so a new window and an untagged tab
  look like today with no unstyled first frame.
- **The user's own values**, recorded by `apply_to_config` before it applies the
  default, for every key TerminalStyles sets: `color_scheme`, `background`,
  `window_background_opacity`, `macos_window_background_blur`,
  `default_cursor_style`, and `colors` (a deep copy).
- **Complete override tables.** Because an override replaces only the keys it carries
  and the base holds the default style, every style's override — and the "unstyled"
  one — carries the **whole** key set above. A key the style does not set is filled
  with the user's own recorded value; a key the user did not set either is filled with
  WezTerm's built-in default, from a short hard-coded list. `colors` is always the
  user's own table with the style's tab-bar change merged in, never the style's alone,
  since overriding `colors` replaces the user's whole table. *(My call, over the
  alternative of making the user's own look the base and the default an override: that
  draws every new window's first frame unstyled.)*
- **Event handlers**, registered from `apply_to_config`:
  - `update-status(window, pane)`: work out the wanted style for `window` from its
    active pane (tag, else pin), and call `set_config_overrides` only if it differs
    from what that window has. This is the whole tab-switch path.
  - `user-var-changed(window, pane, name, value)`: for `TERMINALSTYLES_STYLE`, run the
    same sync for `window` at once, so an apply or preview shows immediately.
- **Pinning untagged panes.** An untagged pane in a tab where another pane is tagged
  (a new split) takes that tab's style. An untagged pane in an untagged tab is pinned
  to the default it opened under, so a later apply in another tab does not restyle it.
  Pins live in `wezterm.GLOBAL`, keyed by pane id, set at the first sync that sees the
  pane; a new tab is active when it opens, so it is seen at once.

Window-to-style state also lives in `wezterm.GLOBAL`, keyed by window id, because
module-level Lua locals reset on every config reload.

### Apply

`Publish-StyleWezTermConfig` writes the module with the applied style as the new
default, then tags this tab, writes this tab's record, and sends the OSC reset. The
other tabs keep their tags or pins.

### Reset

`Reset-StyleNonWT`'s WezTerm half tags this tab "unstyled", writes this tab's record,
and rewrites the module with no default (new tabs unstyled). `Clear-WezTermStyleModule`
stops being reset's tool; the header's reasons about rewrite-vs-delete and the reload
watch list still hold for what reset writes.

### Picker and tuner

The preview stops rewriting the module on every arrow key. Each arrow sends the
**preview tag** for the highlighted style; Esc sends this tab's own tag back (from the
per-tab record) plus the OSC reset; confirm is an apply. No layout pinning is needed
any more, since no style carries layout; the `-LayoutTheme` machinery goes for
WezTerm. `Restore-AbandonedFilePreview` has nothing to restore for WezTerm, since no
file is written mid-preview; the builder removes or narrows it for WezTerm. The
picker opens by rewriting the module once if the installed set of styles changed since
it was written (a user style created after the last apply).

### Backgrounds

Each style's look names the path where its GIF is cached, whether or not the file is
there yet. The Lua checks that the file exists **when it builds a window's override**,
and uses the colour layer alone if it does not. So the picker's background download job
keeps working as today: a GIF that lands mid-session shows on the next preview of that
style, with no module rewrite. Only the style being applied may fetch at apply time.
*(My call: it keeps the picker's progressive download and needs no reloads.)*

### Capabilities and messages

`Get-TerminalCapability`'s WezTerm arm turns `Font` and `Padding` off, next to the
generator change that stops emitting them (CLAUDE.md: capabilities are promises), so
`Get-UnsupportedStyleField` names them. `lib/fonts.ps1`'s WezTerm advice changes in the
same commit: the applied style no longer sets the font, so it says to set
`config.font` in `wezterm.lua` (anywhere), and drops the "tune it into the style"
route for WezTerm. README's WezTerm section and `tstyles help` describe per-tab,
new-tab, split, restart and Windows rules, and that a style's keys in a styled tab win
over the user's own lines for those keys (opacity, cursor, colours).

### Uninstall

Uninstall deletes the module as today. If the builder finds that overrides survive a
reload, open windows keep their last look after that, and uninstall says so plainly
("WezTerm windows already open keep their look until you close them or restart
WezTerm"). *(My call: a module that clears every window before it is deleted depends on
timing the uninstall cannot see.)*

## Left to the builder

- **Overrides across a reload.** Verify whether a window's `set_config_overrides`
  survives the module rewrite. If it does not, re-apply on the next sync without
  looping: `set_config_overrides` itself causes a reload, so a naive "clear the cache
  on `window-config-reloaded`" handler loops. The uninstall message depends on the
  answer.
- **WezTerm's built-in defaults** for the override key set, pinned against WezTerm's
  source, and the "no background" case: verify in a sandbox instance what override
  value draws the plain scheme background for a user who set no `background`.
- **The reserved tag forms** ("unstyled", preview). Style names are user-controlled;
  pick forms that cannot collide with a style name.
- **The per-tab record's file and pruning**, under the data root.
- **tmux.** Wrap the tag in tmux passthrough when `$TMUX` is set; if it does not reach
  WezTerm, the tab follows its pin. Say so in the README; do not build more.
- **Module size.** Roughly 40 lines per style for twenty styles; keep the generator's
  per-style output a function so tests can assert on one style.
- **Tests.** Extend `tests/WezTerm-Writer.Tests.ps1`, `WezTerm-LivePreview.Tests.ps1`
  and `Reset-StyleNonWT-WezTerm.Tests.ps1`, plus the font advice and capability tests.
  Nothing there can run a real WezTerm, so pin the generated Lua's shape, the tag bytes
  and the record; record the sandbox-instance checks in the PR. Follow CLAUDE.md's
  sandboxing rules — the module path resolves from `$HOME` via `-HomeDir`.
- **Windows.** The Windows path keeps generating today's single-style module; CI covers
  that the generator branches correctly. Open a follow-up issue for the real-machine
  check.

## Evidence

The test, its log and the generated per-style Lua lived in the session scratchpad
(`wezterm-spike/`: `spike.lua`, `ts-tag`, `gen.ps1`, `swap.log`) and are throwaway.
The per-style tables were made by the real `Get-WezTermStyleLua`, called on an empty
table, so the override shape the module will use is the shape that test applied.
