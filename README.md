# TerminalStyles

Themed styles for **PowerShell** (5.1 and 7+) in **Windows Terminal**.
Install once, then run `tstyles` to switch — arrow keys preview each style
live in your current tab, Enter keeps it, Esc cancels.

![demo placeholder](docs/screenshots/demo.gif)

## Install

Open a **PowerShell** tab in Windows Terminal (either Windows PowerShell
5.1 or PowerShell 7+ works) and run:

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

That's it. You don't need to clone anything. The installer:

1. Downloads the styles to `%LOCALAPPDATA%\TerminalStyles\`.
2. Registers a loader line in your `$PROFILE` for **every** PowerShell
   engine it finds on PATH (`pwsh.exe` and `powershell.exe`), so one run
   sets up both shells.
3. Detects if either engine's execution policy is `Restricted` /
   `AllSigned` and offers to set `CurrentUser` to `RemoteSigned` for you
   (it asks first — never silent).

Then open a new pwsh or powershell tab (or run `. $PROFILE` to reload).

## Use

```powershell
PS C:\> tstyles
```

You'll get an arrow-key menu like:

```
  Choose a style for 'PowerShell'
  Up/Down to preview, Enter to keep, Esc to cancel

   > umbrella
     kitty
     golden-forest
```

As you arrow up/down, the terminal actually changes in real time — color
scheme, cursor, font, opacity. Press **Enter** to keep the highlighted
style, **Esc** to revert to how things looked before you ran `tstyles`.

## Styles

| Style | Vibe | Includes |
|---|---|---|
| [**umbrella**](styles/umbrella) | Resident-Evil / survival-horror | scheme + theme + custom prompt (`[UMBRELLA // OPERATOR]` 3-line classified-doc prompt, startup banner) |
| [**kitty**](styles/kitty) | Soft pastel CRT | scheme + theme (retro effect, acrylic, vintage cursor, corner GIF) |
| [**golden-forest**](styles/golden-forest) | Warm sepia / autumn | scheme + theme (filledBox cursor, fullscreen GIF) |

Each style folder has its own README with full details.

## Background image

Each bundled style ships with its own `background.gif` (or `.png` / `.jpg`)
under `styles/<name>/`. Picking a style auto-applies that image — arrow
keys cycle the GIF live alongside the colors / cursor / font.

To override the bundled image with your own:

```powershell
tstyles -BackgroundImage "C:\Users\me\Pictures\moody.gif"
```

To disable backgrounds for this style:

```powershell
tstyles -BackgroundImage ""
```

Styles without a bundled image leave your existing background untouched
unless you pass `-BackgroundImage`.

## Requirements

- Windows 10 / 11
- [Windows Terminal](https://aka.ms/terminal) (live preview only shows up
  here — VS Code's integrated terminal etc. won't reflect the changes)
- **Either** Windows PowerShell 5.1 (ships with Windows) **or**
  [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`).
  Both engines work; if both are installed, the one-liner sets up both.

### Execution policy

If you see `UnauthorizedAccess` / "ejecución de scripts deshabilitada"
on shell startup, your `CurrentUser` execution policy is `Restricted`.
The installer asks to fix this for you. To do it manually:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

(GPO-locked machine policy can override `CurrentUser`. If the install
shows that, ask your admin or run an elevated `Set-ExecutionPolicy` at
`LocalMachine` scope.)

## Scriptable / non-interactive

For dotfiles managers, CI, or anything that needs a one-shot apply (no
menu), there's a direct script:

```powershell
pwsh -File "$env:LOCALAPPDATA\TerminalStyles\apply.ps1" -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
```

`apply.ps1` is the same logic as the interactive picker but driven
entirely by flags, with a one-time backup of `settings.json` and
`$PROFILE` before applying. See `apply.ps1 -?` for the full parameter
list.

## Updating

Re-run the install one-liner to pull the latest styles. Your currently
selected style (the `current-style.ps1` file) is preserved across
reinstalls.

## Uninstalling

```powershell
# Remove the installed files
Remove-Item "$env:LOCALAPPDATA\TerminalStyles" -Recurse -Force

# Remove the loader block from your $PROFILE (between the BEGIN/END markers)
# You can do this by hand, or:
$content = Get-Content $PROFILE -Raw
$content = [regex]::Replace($content, '(?ms)# ===== TerminalStyles BEGIN =====.*?# ===== TerminalStyles END =====\r?\n?', '')
[System.IO.File]::WriteAllText($PROFILE, $content, [System.Text.UTF8Encoding]::new($false))
```

The original `settings.json` is restored automatically if you press Esc
in the menu before confirming. If you've already confirmed a style,
restore the appropriate `.bak-<timestamp>` file in your Windows Terminal
`LocalState` folder.

## Adding your own style

Once installed, you can drop a new style folder into
`%LOCALAPPDATA%\TerminalStyles\styles\<name>\` with:

```
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── background.gif     # default background image (optional, .png/.jpg also accepted)
└── README.md          # description (optional)
```

`tstyles` will pick it up automatically — no registration needed.

For contributing back, fork the repo, add the folder under `styles/`,
and open a PR.

- **scheme.json** must contain a unique `name`. See
  [Microsoft's docs](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes).
- **theme.json** uses the literal string `"{{BACKGROUND_IMAGE}}"` for
  the background image field; `tstyles` substitutes the bundled
  `background.*` (or the user's `-BackgroundImage` flag if passed) and
  strips the field if neither is available.
- **profile.ps1** is copied to `current-style.ps1` on apply and
  dot-sourced from `$PROFILE` on shell startup.
- **background.gif / .png / .jpg / .jpeg** is auto-applied when the style
  is selected. Priority order if multiple exist: `.gif > .png > .jpg >
  .jpeg`. Only contribute images you have the right to redistribute.

## Known limitations

- **One `$PROFILE` per host.** Confirming a style with a custom prompt
  replaces `current-style.ps1`. Switching styles changes the prompt
  globally — there's no per-tab prompt configuration.
- **Preview carryover for bundle-less styles.** Arrow-keying from a style
  with a bundled `background.*` onto a style without one leaves the
  previous GIF visible (the bundle-less path doesn't touch background
  fields). Pass `-BackgroundImage ""` to clear, or just confirm the
  selection.
- **Repo size grows with styles.** Bundled GIFs are committed binaries;
  contributors should keep each under ~2 MB and only submit images they
  have the right to redistribute.
- **Live preview is Windows-Terminal-only.** Other hosts (VS Code,
  conhost) don't read `settings.json`, so the menu won't show theme
  changes there — `tstyles` warns when this is the case.
- **JSON reformatting.** Each apply reformats `settings.json` cosmetically
  (PowerShell's `ConvertTo-Json` style). Functionally identical;
  Windows Terminal rewrites the file on its next save anyway.

## License

MIT — see [LICENSE](LICENSE).
