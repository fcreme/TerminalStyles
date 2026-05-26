# TerminalStyles

A pack of themed styles for **PowerShell 7** in **Windows Terminal**. Pick a
mood, run `apply.ps1`, and your terminal switches over — scheme, cursor,
font, optional GIF background, and (for styles that include one) a
custom prompt.

## Styles

| Style | Vibe | Includes |
|---|---|---|
| [**umbrella**](styles/umbrella) | Resident-Evil / survival-horror | scheme + theme + custom prompt (`[UMBRELLA // OPERATOR]` 3-line classified-doc prompt, startup banner, tuned PSReadLine colors) |
| [**kitty**](styles/kitty) | Soft pastel CRT | scheme + theme (retro effect, acrylic, vintage cursor, corner GIF) |
| [**golden-forest**](styles/golden-forest) | Warm sepia / autumn | scheme + theme (filledBox cursor, no acrylic, fullscreen GIF) |

Each style lives in `styles/<name>/` with its own README and preview.

## Requirements

- Windows 10 / 11
- [Windows Terminal](https://aka.ms/terminal)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`) —
  **not** Windows PowerShell 5.1, which has a separate `$PROFILE`

## Quick start

```powershell
git clone https://github.com/fcreme/TerminalStyles.git
cd TerminalStyles
pwsh -File .\apply.ps1
```

You'll be prompted interactively for:

1. Which style to apply
2. Which Windows Terminal profile to apply it to (e.g. `PowerShell`,
   `Windows PowerShell`, `Command Prompt`, or `defaults` to apply globally)
3. An optional background image path

`apply.ps1` always backs up `settings.json` (and `$PROFILE` if it
overwrites one) before making changes.

## Non-interactive

```powershell
pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -BackgroundImage "C:\path\to\your.gif"

# Apply a style globally (defaults block — affects all WT profiles):
pwsh -File .\apply.ps1 -Style kitty -Target defaults

# Skip installing the style's profile.ps1 even if it has one:
pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -NoProfile

# Point at a non-standard settings.json:
pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -SettingsPath "D:\custom\settings.json"
```

## What the script does

For your chosen style:

1. **Backs up** `settings.json` to `settings.json.bak-<timestamp>`.
2. **Adds the color scheme** to the `schemes` array (replacing any existing
   scheme with the same name).
3. **Applies the theme** (cursor shape, font, opacity, GIF settings,
   `colorScheme`, etc.) to the target profile entry.
4. If the style includes a `profile.ps1` and the target is a PowerShell
   profile, **backs up** any existing `$PROFILE` and **installs** the
   style's profile.

Background image handling:

- If you provide an image path, the script substitutes it into
  `theme.json`'s `{{BACKGROUND_IMAGE}}` placeholder.
- If you provide nothing, the `backgroundImage*` fields are removed from
  the target profile entirely (the terminal will use whatever it
  inherits from `defaults`, or no background at all).

## Reverting

Each apply creates a timestamped backup next to the file it modified.
To roll back the most recent apply:

```powershell
# Restore Windows Terminal settings
Move-Item "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.bak-<timestamp>" `
          "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force

# Restore PowerShell profile
Move-Item "$PROFILE.bak-<timestamp>" $PROFILE -Force
```

## Adding your own style

Create a new directory under `styles/`:

```
styles/<your-style>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional but recommended)
├── profile.ps1        # custom $PROFILE (optional)
└── README.md          # description + preview (optional)
```

- **scheme.json** — a single Windows Terminal scheme object (with `name`,
  `background`, `foreground`, ANSI colors, etc.). The `name` field must be
  unique across styles. See
  [Microsoft's scheme docs](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes).
- **theme.json** — fields to merge onto the target Windows Terminal profile
  entry. Use the literal string `"{{BACKGROUND_IMAGE}}"` as the
  `backgroundImage` value — `apply.ps1` substitutes the user's chosen
  path, or removes all `backgroundImage*` fields if none provided.
- **profile.ps1** — PowerShell 7 profile script. Will be copied to
  `$PROFILE` when the user targets a PowerShell profile.

The script will automatically detect new styles — no registration needed.

## Known limitations

- **One `$PROFILE` per host.** Applying a style with a custom prompt
  overwrites your existing profile (backed up). Switching styles changes
  the prompt globally.
- **GIFs aren't bundled.** Each style describes the mood it wants from a
  background, but you bring your own image. (Repo would balloon and
  raise copyright headaches if we shipped them.)
- **JSON reformatting.** `apply.ps1` reformats `settings.json` cosmetically
  on save (PowerShell's `ConvertTo-Json` differs slightly from Windows
  Terminal's default). Functionally identical; Windows Terminal rewrites
  the file on its next save anyway.

## License

MIT — see [LICENSE](LICENSE).
