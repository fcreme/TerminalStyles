# Umbrella Terminal

A Resident-Evil-themed styling for **PowerShell 7** in **Windows Terminal**.
Survival-horror classified-doc prompt, muted-blood-red + bone-white palette,
animated GIF background.

```
+------------------------------------------+
|  UMBRELLA CORP. // OPERATOR TERMINAL     |
|  CLEARANCE: PERSONAL  ::  STATUS: FINE   |
+------------------------------------------+

[UMBRELLA // OPERATOR: <you>]
[CWD: C:\Users\<you>]
> _
```

## What's included

- **`pwsh/Microsoft.PowerShell_profile.ps1`** — the PowerShell 7 profile:
  custom 3-line prompt, startup banner, tuned PSReadLine colors, history-based
  inline predictions, tab title set to `UMBRELLA TERMINAL`.
- **`windows-terminal/umbrella-scheme.json`** — a Windows Terminal color
  scheme (red / bone / tan) you paste into your `settings.json`.
- **`windows-terminal/profile-fragment.json`** — the profile overrides to
  apply this scheme + GIF background to your pwsh profile only.
- **`install.ps1`** — copies the profile script into your `$PROFILE` path.

## Requirements

- Windows 10/11
- [Windows Terminal](https://aka.ms/terminal)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)
  — **not** the built-in Windows PowerShell 5.1
- A GIF (or static image) you'd like as a background, on disk somewhere

## Install

### 1. Install the PowerShell profile

```powershell
git clone https://github.com/fcreme/dotfiles.git
cd dotfiles
pwsh -File .\install.ps1
```

`install.ps1` copies `pwsh\Microsoft.PowerShell_profile.ps1` into your
`$PROFILE` path (backing up any existing profile first).

### 2. Add the color scheme to Windows Terminal

Open Windows Terminal → **Settings** → **Open JSON file** (gear in the
bottom-left, or `Ctrl+,` then the link at the bottom).

In `settings.json`, find the `"schemes"` array and add the contents of
[`windows-terminal/umbrella-scheme.json`](windows-terminal/umbrella-scheme.json)
as a new entry.

### 3. Apply the scheme to your pwsh profile

In the same `settings.json`, find the `profiles.list` entry where
`"source": "Windows.Terminal.PowershellCore"`. Add the fields from
[`windows-terminal/profile-fragment.json`](windows-terminal/profile-fragment.json)
to it.

Replace `<YOUR_GIF_PATH>` with the absolute path to your GIF, e.g.:

```json
"backgroundImage": "C:\\Users\\<you>\\Pictures\\some-gif.gif"
```

…or remove the `backgroundImage*` fields entirely if you want no background.

### 4. Open a new pwsh tab

Windows Terminal auto-reloads settings on save. Open a fresh PowerShell tab
and you should see the new styling.

## Customizing

- **Banner text** — edit the `Show-UmbrellaBanner` function in
  `Microsoft.PowerShell_profile.ps1`.
- **Prompt** — edit the `prompt` function. The format string is the last
  line of that function.
- **Colors** — the palette is defined in the `$script:UmbR` and
  `$script:UmbW` ANSI escape variables at the top of the profile, and in the
  `umbrella-scheme.json` file for Windows Terminal output.
- **Background opacity** — tweak `backgroundImageOpacity` in your
  `settings.json` (range 0.0–1.0; 0.35 is the default here).

## Uninstall

The installer backs up your existing profile to
`$PROFILE.bak-<timestamp>` before overwriting. To restore:

```powershell
Move-Item $PROFILE.bak-<timestamp> $PROFILE -Force
```

For Windows Terminal, remove the `umbrella` scheme entry from `schemes` and
the override fields from your pwsh profile entry.

## License

MIT — see [LICENSE](LICENSE).
