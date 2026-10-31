## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

On macOS and Linux this needs PowerShell first — `brew install powershell`,
or see [Requirements](#requirements). On Windows it is already there.

Add the `Import-Module` line to your `$PROFILE` so it loads on every
new shell tab — or run `tstyles register` once and it does that for
you, with a confirm prompt first. It writes to the `$PROFILE` of each
PowerShell engine it finds on your PATH — on Windows that is pwsh 7 and
Windows PowerShell 5.1; on macOS and Linux, `pwsh` and `pwsh-preview` —
skips one that isn't installed, and writes once where two of them share
one file. The prompt names each file first. Then:

```powershell
tstyles
```

Arrow keys preview each style live, Enter keeps it, Esc cancels.

### Alternate: bootstrap installer

For setups without [PSResourceGet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/)
(rare on modern Windows; ships natively in pwsh 7.4+), use the
bootstrap one-liner installer instead. It also auto-registers the
loader in your `$PROFILE`:

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

This downloads to `%LOCALAPPDATA%\TerminalStyles\`, registers a
loader for every PowerShell engine it finds, and offers to fix
restrictive execution policies if needed. Once it finishes, run
`tstyles` immediately in the same tab.

The bootstrap install and the PSGallery install can coexist —
whichever your `$PROFILE` loads wins; the other is orphaned silently.

## Requirements

- **Windows** 10 / 11, or **macOS**, or **Linux**
- A terminal that can render a style:
  - **Windows Terminal** — the full feature set, including background images,
    when tstyles runs on Windows; in a WSL distro, colors, cursor color and
    prompt (see ² under [What your terminal can show](Terminals-and-Shells.md#what-your-terminal-can-show))
  - **Terminal.app** — colors, cursor color, and prompt in the current window,
    plus a background image in a new one (`tstyles <name> -NewWindow`)
  - **WezTerm** — colors, cursor color and shape, prompt, font, padding,
    window transparency (with the macOS blur for an acrylic style), the tab
    accent color, and an **animated** background image, live in the running
    window, after one line of setup (see [Animated backgrounds on WezTerm](Terminals-and-Shells.md#animated-backgrounds-on-wezterm))
  - **VS Code**, Insiders, VSCodium, Cursor and Windsurf — colors, cursor
    color and shape, prompt, and font. The colors, font and cursor are
    written into the editor's own `settings.json` once you have said yes to
    that (see [VS Code, Cursor, VSCodium and Windsurf](Terminals-and-Shells.md#vs-code-cursor-vscodium-and-windsurf)); until then, only
    what the next line lists
  - **iTerm2**, **Ghostty**, **kitty**, **Alacritty**, and anything else that
    speaks OSC 4/10/11/12 — colors, cursor color, and prompt. Run `tstyles`
    and it reports what your terminal can and cannot show.
- **Either** Windows PowerShell 5.1 (ships with Windows) **or**
  [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`).
  Both engines work. On macOS: `brew install powershell`.
- For the PSGallery install path (`Install-PSResource`), PowerShell
  7.4+ ships [PSResourceGet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/)
  natively. Older shells can use the bootstrap `iwr | iex` one-liner
  instead — it auto-registers a loader in every PowerShell engine
  it finds.

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
