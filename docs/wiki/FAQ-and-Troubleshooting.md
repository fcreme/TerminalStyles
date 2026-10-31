## FAQ and Troubleshooting

Each answer is short and links to the page that covers it in full.

### `tstyles` is not found in a new tab

The module is loaded by your `$PROFILE`. Run `tstyles register` once: it adds
the `Import-Module` line to the `$PROFILE` of each PowerShell engine on your
PATH, after a confirm prompt. See [Install](Install.md#install).

### A new shell prints `UnauthorizedAccess` on startup

Your `CurrentUser` execution policy is `Restricted`. Run
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. See
[Execution policy](Install.md#execution-policy).

### I applied a style and only the colors changed

Colors reach every terminal that speaks OSC. The font, opacity, cursor shape
and background image have to be written into a config file the terminal reads,
and TerminalStyles writes four of those: Windows Terminal, Terminal.app,
WezTerm and VS Code-family editors. Applying a style names every part this
terminal cannot show. See
[What your terminal can show](Terminals-and-Shells.md#what-your-terminal-can-show).

### The background does not move on Terminal.app

Terminal.app shows a still first frame, and only in a new window:
`tstyles <name> -NewWindow`. See
[Background images on Terminal.app](Terminals-and-Shells.md#background-images-on-terminalapp).

### WezTerm shows no background

It needs one line in your own `wezterm.lua`, added by hand above
`return config`. `tstyles` prints that line until it can see it in your config.
See [Animated backgrounds on WezTerm](Terminals-and-Shells.md#animated-backgrounds-on-wezterm).

### My Oh My Posh or Starship prompt was replaced

Apply with `-KeepPrompt`: you get the style's colors, cursor, font and
background, and your prompt stays. See
[Keeping your own prompt](Using-tstyles.md#keeping-your-own-prompt-oh-my-posh--starship).

### zsh or bash tabs get the colors but not the prompt

Run `tstyles shell-init` to add the loader to your rc files; `tstyles
shell-remove` takes it out. This is a macOS and Linux feature: it does not work
in Git Bash on Windows. See
[Styling zsh and bash](Terminals-and-Shells.md#styling-zsh-and-bash).

### VS Code did not keep the style after a restart

TerminalStyles asks once per editor before it writes that editor's
`settings.json`; `tstyles vscode` shows the answer on record and `tstyles
vscode on` changes it. It also refuses when it cannot tell which editor it is
in: with `git.terminalAuthentication` turned off, or in a remote terminal. See
[VS Code, Cursor, VSCodium and Windsurf](Terminals-and-Shells.md#vs-code-cursor-vscodium-and-windsurf).

### The style went to the wrong Windows Terminal profile or build

`-Target` names the profile. With more than one Windows Terminal build
installed, open a tab in the one you want, or set `$env:TSTYLES_WT_SETTINGS`
for the session. See
[Which profile a style lands on](Using-tstyles.md#which-profile-a-style-lands-on--target).

### Windows Terminal's `settings.json` is broken

Restore the rolling `settings.json.bak` beside it. It holds the file from
before the most recent command that wrote it. See
[Recovering from a bad write to `settings.json`](Scripting-and-Recovery.md#recovering-from-a-bad-write-to-settingsjson).

### I deleted a style by mistake

Deleted styles stay in the trash for 7 days. `tstyles trash` lists them and
`tstyles restore <name>` puts one back. See
[Deleting a style, and changing your mind](Using-tstyles.md#deleting-a-style-and-changing-your-mind).

### I installed both from PSGallery and with the bootstrap script

Whichever your `$PROFILE` loads wins. Run `tstyles uninstall` twice, switching
shells between runs if needed, to remove both. See
[Known Limitations](Known-Limitations.md).
