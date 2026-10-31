## Scriptable / non-interactive

For dotfiles managers, CI, or anything that needs a one-shot apply (no
menu), there's a direct script:

```powershell
# apply.ps1 ships inside the module, whose location differs by install
# method (and changes with every update on a PSGallery install), so ask
# the module where it is rather than hard-coding a path:
$base = Split-Path (Get-Module -ListAvailable TerminalStyles |
                    Sort-Object Version -Descending |
                    Select-Object -First 1).Path -Parent
pwsh -File (Join-Path $base 'apply.ps1') -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
```

`apply.ps1` is the same logic as the interactive picker but driven
entirely by flags. It writes a timestamped `settings.json.bak-<timestamp>`
(and a `$PROFILE.bak-<timestamp>` when overwriting one) before applying,
keeping a full audit trail of every run. See `apply.ps1 -?` for the
full parameter list.

It edits the `settings.json` of the Windows Terminal it runs in, as
`tstyles` does. Run outside one — from a scheduled task, say — on a machine
where more than one build has a `settings.json`, it cannot tell which you
mean and stops: pass `-SettingsPath`.

### Recovering from a bad write to `settings.json`

There is exactly ONE rolling backup, `settings.json.bak` (no timestamp),
in the same directory as the `settings.json` tstyles edited — that of the
Windows Terminal you ran it in. Every command that writes
`settings.json` rolls it first: `tstyles <name>`, `tstyles random`,
`tstyles reset`, `tstyles font <name>`, `tstyles tune`, and opening the
picker (`tstyles` with no arg, which backs up before its first preview).
So it holds the state from immediately before the **most recent** of
those — a font change or a tune after an apply is what you will get
back, not the file from before the apply. To restore it:

```powershell
# Stable's. Preview and Canary keep theirs in their own package folders under
# Packages (Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe,
# Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe), an unpackaged build under
# "$env:LOCALAPPDATA\Microsoft\Windows Terminal", and a portable one in the
# settings folder beside WindowsTerminal.exe.
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Copy-Item "$wt.bak" $wt -Force
```

Windows Terminal's Settings → Open JSON file opens the one in use, and
`tstyles <name>`, `random`, `reset` and `font` print the backup's path as
they take it (`Backed up settings to: ...`).

`tstyles reset` is not a substitute: it removes the fields a style
added, but it cannot put back what the style overwrote — your own
`colorScheme`, your `font.face`, or the JSONC comments a successful
apply drops when it re-serializes the file. The `.bak` is the only
route back to those.

A crash mid-pick or mid-tune is recoverable from the same file. Pressing
Esc in the picker reverts in-memory to the exact prior bytes without
needing it. If you want a full history of changes rather than just "undo
the most recent write", use `apply.ps1` — it keeps a timestamped backup
per run.

**VS Code** keeps its own copy. The first write of a style into a VS
Code-family `settings.json` that already has content copies the file beside
it as `settings.json.bak-<timestamp>`, taken before any TerminalStyles key was
in it. Try `tstyles reset` from that editor's terminal first; the copy is the
way back from anything a reset cannot fix, and restoring it also undoes any
edit you made to the file since it was taken:

```powershell
# Stable VS Code on macOS. The folder follows the editor's name -- Code - Insiders,
# VSCodium, Cursor or Windsurf in place of Code -- and sits under "$env:APPDATA"
# on Windows and ~/.config on Linux.
$vs = "$HOME/Library/Application Support/Code/User/settings.json"
Copy-Item "$vs.bak-<timestamp>" $vs -Force
```
