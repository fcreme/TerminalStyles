## Scriptable / non-interactive

For dotfiles managers, CI, or anything that needs a one-shot apply (no
menu), there's a direct script:

```powershell
# apply.ps1 ships inside the module, whose location differs by install
# method (and changes with every update on a PSGallery install), so ask
# the module where it is rather than hard-coding a path. Ask the LOADED
# module first: a bootstrap install is not on PSModulePath, so
# Get-Module -ListAvailable cannot see it.
$ts = Get-Module TerminalStyles | Select-Object -First 1
if (-not $ts) {
    $ts = Get-Module -ListAvailable TerminalStyles | Sort-Object Version -Descending | Select-Object -First 1
}
# The last fallback is a Windows bootstrap install, in a session without the loader.
$base = if ($ts) { $ts.ModuleBase } else { Join-Path $env:LOCALAPPDATA 'TerminalStyles' }
pwsh -File (Join-Path $base 'apply.ps1') -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
```

`apply.ps1` is the flag-driven way to apply a style to Windows Terminal.
Like `tstyles <name>` there, it puts the style's scheme and theme into
`settings.json`, and, for a PowerShell profile or `defaults`, its prompt
into `current-style.ps1` (none with `-KeepPrompt`); it records the style
for `tstyles current`. It never edits `$PROFILE`: a new tab shows the
prompt when its `$PROFILE` imports TerminalStyles (the line in
[Install](Install.md#install), which `tstyles register` adds). Where `tstyles` rolls
one `settings.json.bak`, it takes a timestamped
`settings.json.bak-<timestamp>` before each change, keeping a full audit
trail of every run. See `apply.ps1 -?` for the full parameter list.

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
they take it (`Backed up settings to: ...`). If the write itself then
fails — a read-only `settings.json`, or one another program has locked — the
command stops at `Could not write <path>: <reason>`. It prints no success line
and leaves the style record and your prompt as they were; the `.bak` it has
just taken is a copy of the file as it still is.

`tstyles reset` is not a substitute: it removes the fields a style
added, but it cannot put back what the style overwrote — your own
`colorScheme`, your `font.face`, or the JSONC comments a successful
apply drops when it re-serializes the file. The `.bak` is the only
route back to those.

The picker and the tuner do not need this file to undo a preview: Esc puts
back the exact bytes they found — unless `settings.json` cannot be written
at that moment, when it says so instead of "Reverted." and prints the
`Copy-Item` that puts this `.bak` back. If one ends without Enter or Esc —
the tab is closed, or the process is killed — the copy it keeps of the file
it found is still in the data root, and the next tstyles command that writes
`settings.json` puts that file back before it reads it or rolls this backup,
and says so. If `settings.json` has changed since, it is left as it is, and
the file the picker found is moved beside it as
`settings.json.preview-<timestamp>`.

If `settings.json` changes while the picker or the tuner is open — Windows
Terminal's Settings UI saves it, or another tstyles command writes it — no
further preview is written into it. Esc then takes the preview back out of
the file as it is now instead of putting the old file back, and Enter merges
the chosen style into it as `tstyles <name>` would; the tuner's save takes
its preview out before it applies. The change stays, except where the style
you chose sets the same key; a value the preview set that was changed again
is left as it is, and named. If you want a full history of changes rather than just "undo
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
