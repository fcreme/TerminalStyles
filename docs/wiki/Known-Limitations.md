## Known limitations

- **One `$PROFILE` per host.** Confirming a style with a custom prompt
  replaces `current-style.ps1`. Switching styles changes the prompt
  globally — there's no per-tab prompt configuration.
- **Background images live on a separate branch.** They are deliberately
  not committed to `main` — `.gitignore` blocks them and a test fails the
  build if one becomes tracked — so the install stays ~900 KB instead of
  ~10 MB. They sit flat-named on the [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs)
  and are fetched on first use. Contributors should keep each under ~2 MB
  and only submit images they have the right to redistribute.
- **Not every terminal can show every part of a style.** Windows Terminal reads
  the whole `theme.json` field set from its `settings.json`. Everywhere else the
  colors are applied as OSC escape sequences, and no escape sequence carries a
  background image or a tab accent color. On Terminal.app the image is instead
  delivered through a generated `.terminal` profile, which means a new window
  (`tstyles <name> -NewWindow`). Tab accent color, font, cursor shape, window
  transparency and interior padding are the same story: they live in a config
  file. Off Windows Terminal, WezTerm's generated Lua module carries all five,
  so a WezTerm window gets everything the eighteen bundled styles declare
  except the tab title (the style's prompt sets that anyway) and the
  experimental CRT effect, which WezTerm has no equivalent for. A VS
  Code-family editor's `settings.json` carries the font and the cursor shape
  once you have said yes to it being written, and has no setting for the other
  three. Both doors — `tstyles <name>` and the picker — name every field the
  style declares that this terminal cannot show, read off the same capability
  table as the grid on [Terminals and Shells](Terminals-and-Shells.md#what-your-terminal-can-show), rather than dropping them silently. Hosts that
  render nothing (conhost) stay plain by design.
- **The zsh/bash loader is a macOS/Linux feature.** `tstyles shell-init` on
  Windows writes the block into your rc files, but nothing there can read the
  applied style: `shell/tstyles.sh` has no MSYS/MinGW/Cygwin branch, so a Git
  Bash tab looks under `$HOME/.local/share/TerminalStyles` while the apply
  stages to `%LOCALAPPDATA%\TerminalStyles`, and the shell's own `tstyles`
  command answers "not initialised". The command says this before it writes.
- **zsh/bash styling covers the prompt, not the syntax highlighting.** The
  PowerShell profiles carry a PSReadLine color block; zsh and bash have no
  equivalent, so `prompt.sh` ports the title, banner, and prompt only.
- **JSON reformatting.** Each apply reformats `settings.json` cosmetically
  (PowerShell's `ConvertTo-Json` style). Functionally identical;
  Windows Terminal rewrites the file on its next save anyway.
- **User state lives outside the install** regardless of install method:
  `%LOCALAPPDATA%\TerminalStyles\` on Windows,
  `~/Library/Application Support/TerminalStyles/` on macOS,
  `$XDG_DATA_HOME/TerminalStyles/` (default `~/.local/share/`) on Linux. This
  dir holds your active style, cached background images, the staged zsh/bash
  runtime, and the update-check throttle. It survives uninstall (unless you pass
  `-DeleteData`) and version upgrades.
- **Bootstrap + PSGallery installs can coexist.** If you've run both,
  whichever your `$PROFILE` loads first wins; the other is orphaned
  silently. To clean up: `tstyles uninstall` removes whichever is
  currently loaded; run it twice (switching shells between runs if
  needed) to clean both.
