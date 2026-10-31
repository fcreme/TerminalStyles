## macOS, Linux, and non-PowerShell shells

TerminalStyles works outside Windows Terminal. Colors are applied as OSC escape
sequences, which every current terminal understands, so `tstyles eva` retints
the window you are sitting in immediately — and, because the choice is recorded,
every tab you open afterwards too.

```powershell
brew install powershell                  # macOS; on Linux, your package manager or https://aka.ms/powershell
pwsh
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
tstyles                                  # the picker, live-previewing as you arrow
```

### Styling zsh and bash

Colors belong to the terminal, not to any one shell, so a zsh tab already picks
up the palette. The prompt and banner need one extra step:

```powershell
tstyles shell-init
```

That adds a small loader to `~/.zshrc`, `~/.bashrc` and `~/.bash_profile`. New
zsh/bash tabs then come up in the full style — palette, window title, banner,
and the style's prompt — and those shells get a `tstyles` command of their own:

```zsh
% tstyles umbrella
% tstyles list
```

`tstyles shell-remove` takes the loader back out.

> **macOS and Linux only.** On Windows this command writes the loader into rc
> files under `C:\Users\<you>` and the tab still comes up unstyled: the runtime
> resolves its data root to `$HOME/.local/share/TerminalStyles` under an
> MSYS/Cygwin bash (Git Bash), while the PowerShell side stages the applied
> style to `%LOCALAPPDATA%\TerminalStyles`. `tstyles shell-init` says so before
> it writes anything. A WSL shell is unaffected either way — it has its own
> `$HOME`, and a pwsh installed inside WSL is an ordinary Linux install where
> both halves agree.

The loader reads only files that were precomputed when you applied the style, so
it never starts PowerShell on shell startup, and it produces **no output at all**
in a non-interactive shell — `ssh host command`, `scp`, and `rsync` are
unaffected.

> The PowerShell profiles also set PSReadLine syntax-highlighting colors. zsh and
> bash have no equivalent, so `prompt.sh` ports the title, banner, and prompt only.

### What your terminal can show

| | Colors | Cursor | Font | Opacity | Background image | Tab color |
|---|---|---|---|---|---|---|
| Windows Terminal ² | ✅ | ✅ shape + color | ✅ | ✅ | ✅ animated | ✅ |
| WezTerm | ✅ | ✅ shape + color | ✅ | ✅ | ✅ animated | ✅ |
| Terminal.app | ✅ | color only | — | — | ✅ still, new window | — |
| iTerm2 | ✅ | color only | — | — | — | — |
| Ghostty / kitty / Alacritty | ✅ | color only | — | — | — | — |
| VS Code terminal ¹ | ✅ | ✅ shape + color | ✅ | — | — | — |

Colors, including the cursor color, arrive as escape sequences and retint the
window you are already in. Everything else has to be written into a config the
terminal reads at startup, and TerminalStyles knows how to write four of
those: Windows Terminal's `settings.json`, Terminal.app's `.terminal` profile,
WezTerm's generated Lua module, and a VS Code-family editor's `settings.json`.

¹ VS Code, Insiders, VSCodium, Cursor and Windsurf, once you have said yes to
TerminalStyles saving styles in that editor's `settings.json` — it asks the
first time. Until then, and in an editor it cannot identify, colors only. See
[VS Code, Cursor, VSCodium and Windsurf](#vs-code-cursor-vscodium-and-windsurf).

² When TerminalStyles runs on Windows. A pwsh installed inside a WSL distro is
a Linux install, and Windows Terminal's `settings.json` is on the Windows side,
out of its reach: in a WSL tab a style brings the colors, the cursor color and
the prompt, and `tstyles font` installs into the distro, where Windows Terminal
does not look for fonts. To give that profile the rest, apply the style from a
PowerShell tab of the same Windows Terminal: `tstyles <name> -Target '<profile>'`.

So the dashes above describe this tool, not the emulator. iTerm2 would honour a
Dynamic Profile; nothing here writes one yet. They are marked `—` rather than
`✅` on purpose — a claimed capability that no code delivers means a style
reports success, paints nothing, and suppresses the notice that would have
explained why.

### Animated backgrounds on WezTerm

WezTerm is the only terminal outside Windows that **animates** a background GIF,
and every bundled style ships one. Terminal.app can show a still first frame at
best, so this is the one way to see those backgrounds move on macOS or Linux.

It needs one line in your own `wezterm.lua`, added by hand, above the final
`return config`:

```lua
local ok, ts = pcall(require, 'terminalstyles')
if ok then ts.apply_to_config(config) end
```

TerminalStyles never edits `wezterm.lua` itself. That file is a Lua *program*,
not a config file: a syntax error in it does not degrade, it drops WezTerm to
its default configuration until you find and fix it — and almost every
`wezterm.lua` ends with `return config`, after which nothing may be appended.
The `pcall` above is what bounds the damage the other way too: if the generated
module is ever missing or broken, your own config still loads and you simply
lose the style.

Applying a style rewrites `~/.config/wezterm/terminalstyles.lua`, and because
WezTerm watches every file it `require`s, the running window repaints on the
spot — background animation included. No new window, no restart. `tstyles`
prints the line above until it can see it in your config. `tstyles reset`, run
in WezTerm, rewrites the same file to one that applies nothing, and the same
reload takes the style back off (the tab you applied a style in can keep its
colors; see [Resetting a profile](Using-tstyles.md#resetting-a-profile)). `tstyles uninstall` deletes the file.

The module carries the rest of the style too: the palette as a named color
scheme, the font and its size, the interior padding, the cursor shape, the tab
accent color, and — for a style that asks for transparency — the window
opacity, with `macos_window_background_blur` added only on macOS, behind a
`wezterm.target_triple` test, so the same file stays valid on Linux. The tab
accent color is merged into `config.colors` key by key rather than assigned, so
whatever you already set there survives.

Applying a style reports which parts the current terminal cannot show, so a
plainer result is never a mystery.

### Background images on Terminal.app

Colors reach your current window as escape sequences, instantly. An image
cannot — Terminal.app only takes one through a *profile*, and a profile only
applies to a new window. So a style that ships a background gives you:

```powershell
tstyles eva              # colors + prompt, right here, right now
tstyles eva -NewWindow   # a new window with the background image as well
```

The profile is written either way, under
`~/Library/Application Support/TerminalStyles/profiles/`, so you can also open
it from Finder or set it as your Terminal.app default. If you open it from
Finder before any `-NewWindow` has imported the style, the profile that creates
is yours: `-NewWindow` has no record of importing it, so it never reuses,
replaces or deletes it, and may add its own numbered copy (`eva 1`) beside it.

> Terminal.app renders a **still** background, not an animated one. The bundled
> backgrounds are animated GIFs, so the first frame is extracted to a PNG and
> used instead — Windows Terminal animates, Terminal.app shows a still. Pointing
> a profile at the GIF directly produces a blank background with no error.

### VS Code, Cursor, VSCodium and Windsurf

The integrated terminal takes the colors live like any other. To make a style
*stay* — in new terminals and after a restart, font and cursor included —
TerminalStyles writes it into that editor's own `settings.json`, and asks once
per editor before it does. `tstyles vscode` shows the answer on record;
`tstyles vscode on` and `tstyles vscode off` change it (`off` takes the saved
style back out first).

What is written: the terminal's 20 colors under `workbench.colorCustomizations`,
and `terminal.integrated.fontFamily`, `fontSize`, `fontWeight` and
`cursorStyle`. Nothing else in the file is touched, comments and formatting
included. Each apply keeps a record of what was there before, so `tstyles reset`
(in that editor's terminal), `tstyles vscode off` and `tstyles uninstall` put
your own values back; a key you change by hand afterwards is left alone and
named. The first time a style goes into a file that already has content, a
copy of it is kept beside it as `settings.json.bak-<timestamp>`; restoring
that copy also undoes anything you changed in the file since.

The picker previews the whole style as you arrow, font and cursor too, and Esc
puts the file back exactly as it was. If the picker is closed without Enter or
Esc (the terminal closed), the preview it left is recorded, so `tstyles reset`
takes it out. If `settings.json` changes while the picker is open (you edit
it, or Settings Sync does), no further preview is written into it, and Enter
and Esc both work from the file as it is now. Esc takes the preview out by its
record instead of putting the old file back. Either way your change stays,
except for a key the incoming style also sets: that key takes the incoming
style's value, and `tstyles reset` puts yours back. It is named when the
style you were previewing also wrote it.

- **No background image.** VS Code has no setting for one.
- **The editor has to be identifiable.** All five set `TERM_PROGRAM=vscode`, so
  TerminalStyles tells them apart by the install path VS Code's git integration
  exports as `VSCODE_GIT_ASKPASS_NODE`. With `git.terminalAuthentication` turned
  off VS Code does not set it, and TerminalStyles refuses to write rather than
  guess which editor's file to change. A remote terminal (SSH, WSL, a dev
  container) is refused too: the askpass path there is the server's, which
  names no editor.
- **A color theme can win.** A theme-scoped block such as
  `"[Monokai]": { "terminal.background": "#000000" }` inside
  `workbench.colorCustomizations` overrides the style while that theme is
  active; the apply names any it finds.
- **Workspace settings win over user settings.** A project's own
  `.vscode/settings.json` can set the same keys, and that is not detected.
- **Settings Sync carries it.** If you sync settings, the style goes to your
  other machines with them.
