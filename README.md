# TerminalStyles

[![Tests](https://github.com/fcreme/TerminalStyles/actions/workflows/test.yml/badge.svg)](https://github.com/fcreme/TerminalStyles/actions/workflows/test.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/TerminalStyles?logo=powershell&label=PSGallery)](https://www.powershellgallery.com/packages/TerminalStyles)

**Switch terminal themes live.** Run `tstyles`, arrow through 16 themes
previewing each one *in your current tab* — **Enter** keeps it, **Esc** reverts to
exactly how it looked before. Color scheme, cursor, font, opacity, and animated
background, all in one command, all non-destructive.

Works on **Windows Terminal**, **macOS Terminal.app**, **iTerm2**, and any
terminal that speaks OSC color sequences — and in **zsh** and **bash**, not just
PowerShell. Runs on PowerShell 7 and Windows PowerShell 5.1. Keep your own prompt
(Oh My Posh / Starship) with `tstyles <name> -KeepPrompt`.

<table>
  <tr>
    <td align="center"><b>umbrella</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/umbrella.gif" width="210" alt="umbrella"></td>
    <td align="center"><b>eva</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/eva.gif" width="210" alt="eva"></td>
    <td align="center"><b>ex-machina</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/ex-machina.gif" width="210" alt="ex-machina"></td>
    <td align="center"><b>forest</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/forest.gif" width="210" alt="forest"></td>
  </tr>
  <tr>
    <td align="center"><b>garden-rain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/garden-rain.gif" width="210" alt="garden-rain"></td>
    <td align="center"><b>gitbash</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/gitbash.png" width="210" alt="gitbash"></td>
    <td align="center"><b>golden-forest</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/golden-forest.gif" width="210" alt="golden-forest"></td>
    <td align="center"><b>halo</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/halo.gif" width="210" alt="halo"></td>
  </tr>
  <tr>
    <td align="center"><b>kitty</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/kitty.gif" width="210" alt="kitty"></td>
    <td align="center"><b>lain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/lain.gif" width="210" alt="lain"></td>
    <td align="center"><b>marquee</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/marquee.gif" width="210" alt="marquee"></td>
    <td align="center"><b>neon-rain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/neon-rain.gif" width="210" alt="neon-rain"></td>
  </tr>
  <tr>
    <td align="center"><b>rain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/rain.gif" width="210" alt="rain"></td>
    <td align="center"><b>snowday</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/snowday.gif" width="210" alt="snowday"></td>
    <td align="center"><b>sober</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/sober.png" width="210" alt="sober"></td>
    <td align="center"><b>tombraider</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/tombraider.gif" width="210" alt="tombraider"></td>
  </tr>
</table>

## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

Add the `Import-Module` line to your `$PROFILE` so it loads on every
new shell tab — or run `tstyles register` once and it does that for
you (both pwsh 7 and Windows PowerShell 5.1 `$PROFILE` files, with a
confirm prompt first). Then:

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

## Use

### Interactive picker

```powershell
PS C:\> tstyles
```

Arrow-key menu, with a 5-color swatch next to each style so you can see
the palette before previewing:

```
  Choose a style for 'PowerShell'
  Up/Down to preview, Enter to keep, Esc to cancel

   > umbrella         ██████████
     eva              ██████████
     ex-machina       ██████████
     ...
```

As you arrow up/down, the terminal actually changes in real time — color
scheme, cursor, font, background GIF, opacity. Press **Enter** to keep
the highlighted style, **Esc** to revert to how things looked before
you ran `tstyles`.

### Subcommands

```powershell
tstyles umbrella                  # Apply a specific style directly (no picker)
tstyles list                      # List all themes; '*' marks the active one
tstyles current                   # Print just the active style name
tstyles random                    # Pick a random style and apply it
tstyles reset                     # Revert the active profile to its unstyled default
tstyles tune [name]               # Live-tune brightness/saturation/opacity/font; save as a style
tstyles font [name]               # List coding fonts, or install one and apply it
tstyles register                  # Auto-add `Import-Module TerminalStyles ...` to both $PROFILE files
tstyles update                    # PSGallery: Update-PSResource. Bootstrap: re-run installer.
tstyles uninstall                 # Remove module + strip $PROFILE loader. Preserves user state.
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
tstyles help [command]            # Show all commands, or details for one
```

Tab completion works on the subcommand and style names:
`tstyles u<TAB>` cycles `umbrella`, `uninstall`, `update`.

### Tuning a theme

```powershell
tstyles tune            # tune the active style
tstyles tune eva        # tune a specific style
```

Opens a live editor with arrow-key sliders for **brightness**,
**saturation**, **opacity**, **font face**, and **font size**. Up/Down
selects a knob, Left/Right adjusts it, **R** resets colors, **Enter** saves,
**Esc** reverts. Colors retint instantly; opacity/font follow a beat
later (one Windows Terminal reload).

The **font face** knob cycles every monospace font installed on your machine
(curated favorites first), so your own coding fonts show up automatically.

On save you choose **Overwrite** (shadows the theme you tuned) or **Save
as** a new name. The result lands in your user-styles dir as a full style
— so it shows up in `tstyles list`, the picker, and tab-completion, and
survives updates. It inherits the base theme's background, and a small
`tune.json` remembers your adjustments so `tstyles tune <name>` resumes
where you left off.

### Installing a coding font

```powershell
tstyles font                      # list the catalog, with installed/installable markers
tstyles font 'JetBrains Mono'     # install it (if needed) and apply it to the active profile
```

Six curated fonts are available — **JetBrains Mono**, **Fira Code**,
**Cascadia Code**, **Hack**, **Source Code Pro**, and **IBM Plex Mono**.
Each is downloaded from its official GitHub release, checked against a
**pinned SHA-256** before anything is unpacked, and installed **per-user**
into `%LOCALAPPDATA%\Microsoft\Windows\Fonts` — no administrator rights
needed, and nothing is written outside your profile.

Already-installed fonts are detected and skipped, so re-running the
command is cheap. Once a font is installed it also shows up in the
`tstyles tune` font-face knob and in the picker, alongside the monospace
fonts you already had.

The first time you run `tstyles`, a one-time prompt offers to install the
whole set. Decline it and you're never asked again — `tstyles font` is
always there if you change your mind.

### Keeping your own prompt (Oh My Posh / Starship)

Applying a style normally also sets that style's prompt and banner. If you run
a prompt engine like **Oh My Posh** or **Starship**, add `-KeepPrompt` to get
the style's colors, cursor, font, and background **without** touching your
prompt:

```powershell
tstyles eva -KeepPrompt        # eva's look; your prompt stays
```

The scriptable `apply.ps1` accepts the same flag (`apply.ps1 -KeepPrompt`,
with `-NoProfile` kept as an alias). Note: a `-KeepPrompt` apply isn't reported
by `tstyles current` / the `*` in `tstyles list`, because active-style detection
is prompt-based.

### Resetting a profile

To undo theming and return a profile to Windows Terminal's plain default:

```powershell
tstyles reset                  # the active profile
tstyles reset -Target 'Ubuntu' # a specific profile
```

This strips the colors, cursor, font, opacity, and background a style added,
removes the now-unused color scheme, and restores your own prompt (open a new
tab to see it). It's the inverse of applying a style, and writes a
`settings.json.bak` first. Fields you set on the profile by hand are left alone.

## Styles

Sixteen themes ship out of the box. Click any name to jump to that style's
folder for full palette / prompt / theme.json details.

### [umbrella](styles/umbrella)

![umbrella](docs/screenshots/umbrella.png)

**Resident-Evil / survival-horror.** Blood-red brackets, bone-white text,
three-line classified-doc prompt with a startup banner.
*"Welcome to Umbrella Corporation. Status: FINE."*

### [eva](styles/eva)

![eva](docs/screenshots/eva.png)

**Evangelion / Asuka body-scan.** Coral-red CRT palette with mustard
yellow status overlay. NERV operations banner.
*"Anta baka?"*

### [ex-machina](styles/ex-machina)

![ex-machina](docs/screenshots/ex-machina.png)

**Ava body-scan / Bluebook research.** Cold electric cyan wireframe
with a coral pink accent.
*"You've been programmed and fed by another. Are you bothered?"*

### [forest](styles/forest)

![forest](docs/screenshots/forest.png)

**Quiet alpine wilderness.** Pixel-art mountain vista — snow-tipped
peaks at golden hour, deep evergreen forest, mirror lake. Cool
blue-green base, peach accents. No banner — gentle for long sessions.

### [garden-rain](styles/garden-rain)

![garden-rain](docs/screenshots/garden-rain.png)

**Ghibli-style garden rainfall.** Wet stone steps, a metal bucket
and a blue plastic one catching rainwater, leafy plants with blue
flowers. Cool slate-blue base, plant-green cursor, no banner.

### [gitbash](styles/gitbash)

![gitbash](docs/screenshots/gitbash.png)

**Git Bash / MinTTY recreation.** White background, near-black text,
bar cursor, the classic multi-color prompt with live git-branch
detection. The only light-mode theme in the catalog.

### [golden-forest](styles/golden-forest)

![golden-forest](docs/screenshots/golden-forest.png)

**Warm sepia autumn.** Amber and moss palette over deep dark green.
Quiet — no banner, gentle for long sessions.

### [halo](styles/halo)

![halo](docs/screenshots/halo.png)

**EXT3-series LED halo portrait.** Third in the EXT3 dot-matrix
series alongside tombraider and marquee. Psychedelic multi-color
portrait inside a circular halo ring — coral primary, gold EXT3
label, blue and lavender accents. Right-aligned on pure black,
vintage CRT cursor. *"Look up. Look closer."*

### [kitty](styles/kitty)

![kitty](docs/screenshots/kitty.png)

**Soft pastel CRT.** Pink, lavender, mint pastels. Retro / vintage
cursor, acrylic. The most playful theme in the set.

### [lain](styles/lain)

![lain](docs/screenshots/lain.png)

**Serial Experiments Lain.** Lain at her Navi — tangled cables,
faint red status lights, the teddy bear. Deep blackish base,
lavender-pink monitor glow, vintage CRT cursor.
*"Present day, present time. Hahaha."*

### [marquee](styles/marquee)

![marquee](docs/screenshots/marquee.png)

**EXT3-series LED marquee.** Hot magenta dot-matrix portrait,
blue arm accents, gold EXT3 label. Pure black canvas, right-aligned
image so text sits on the left half. Sister piece to tombraider.
*"Through the glass, after hours."*

### [neon-rain](styles/neon-rain)

![neon-rain](docs/screenshots/neon-rain.png)

**Cyberpunk rainy night.** District-05 corporate tower, neon yellow
sign, matrix-green displays, lone delivery truck under steady rain.
Deep blue base, neon yellow cursor, matrix-green status accents.
*"The neon never sleeps."*

### [rain](styles/rain)

![rain](docs/screenshots/rain.png)

**Contemplative highland-storm.** Slate-purple stormy sky, moss-yellow
accents, rust for the lone cloaked traveler. Field-journal banner.
*"Still no sign of the others."*

### [snowday](styles/snowday)

![snowday](docs/screenshots/snowday.png)

**Quiet winter sunset.** Pixel-art creek through a snow-dusted birch
grove, peach-coral light through bare branches, soft dusty mountain
in the distance. Deep dusk-blue base, sunset peach cursor, no banner.

### [sober](styles/sober)

![sober](docs/screenshots/sober.png)

**Minimalist monochrome.** Grayscale with one subtle teal accent, no
banner, single-line prompt. The opposite of umbrella's drama.

### [tombraider](styles/tombraider)

![tombraider](docs/screenshots/tombraider.png)

**90s arcade marquee.** LED-pixel TOMB RAIDER sign in hot neon
magenta with Lara's silhouette, gold EXT3 label, cyan highlights.
Pure black base, neon magenta cursor, vintage CRT cursor.
*"Press start."*

---

Screenshots are generated by `scripts/capture-screenshots.ps1` (see
*Adding your own style* below). If they're missing or out of date, run
that script from inside Windows Terminal and commit the output.

## macOS, Linux, and non-PowerShell shells

TerminalStyles works outside Windows Terminal. Colors are applied as OSC escape
sequences, which every current terminal understands, so `tstyles eva` retints
the window you are sitting in immediately — and, because the choice is recorded,
every tab you open afterwards too.

```powershell
brew install powershell                  # if you don't have pwsh yet
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

The loader reads only files that were precomputed when you applied the style, so
it never starts PowerShell on shell startup, and it produces **no output at all**
in a non-interactive shell — `ssh host command`, `scp`, and `rsync` are
unaffected.

> The PowerShell profiles also set PSReadLine syntax-highlighting colors. zsh and
> bash have no equivalent, so `prompt.sh` ports the title, banner, and prompt only.

### What your terminal can show

| | Colors | Cursor | Font | Opacity | Background image | Tab color |
|---|---|---|---|---|---|---|
| Windows Terminal | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| iTerm2 | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| Terminal.app | ✅ | ✅ | ✅ | ✅ | ✅ (new window) | — |
| Ghostty / WezTerm / kitty / Alacritty | ✅ | ✅ | ✅ | ✅ | WezTerm only | — |
| VS Code terminal | ✅ | — | — | — | — | — |

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
it from Finder or set it as your Terminal.app default.

## Background image

Each bundled style has its own animated background, hosted on the
[`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) of
this repo. `tstyles` lazy-fetches each one on first use of the style and
caches it under `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`, so the
install ZIP stays small (~100 KB instead of ~10 MB). Picking a style
auto-applies the image — arrow keys cycle the background live alongside
the colors / cursor / font.

To override the bundled image with your own:

```powershell
tstyles -BackgroundImage "C:\Users\me\Pictures\moody.gif"
```

To disable backgrounds for this style:

```powershell
tstyles -BackgroundImage ""
```

Switching to a style that has no bundled image clears the previous
style's background rather than leaving it showing through. A background
**you** set — your own image, or Windows Terminal's `desktopWallpaper` —
is never touched: only images TerminalStyles itself installed are cleared.

## Requirements

- **Windows** 10 / 11, or **macOS**, or **Linux**
- A terminal that can render a style:
  - **Windows Terminal** — the full feature set, including background images
  - **Terminal.app**, **iTerm2**, **Ghostty**, **WezTerm**, **kitty**,
    **Alacritty**, and anything else that speaks OSC 4/10/11/12 — colors,
    cursor, and prompt. Run `tstyles` and it reports what your terminal can and
    cannot show.
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

## Scriptable / non-interactive

For dotfiles managers, CI, or anything that needs a one-shot apply (no
menu), there's a direct script:

```powershell
pwsh -File "$env:LOCALAPPDATA\TerminalStyles\apply.ps1" -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
```

`apply.ps1` is the same logic as the interactive picker but driven
entirely by flags. It writes a timestamped `settings.json.bak-<timestamp>`
(and a `$PROFILE.bak-<timestamp>` when overwriting one) before applying,
keeping a full audit trail of every run. See `apply.ps1 -?` for the
full parameter list.

### Recovering from a bad direct apply

`tstyles <name>` and `tstyles random` write a rolling backup to
`settings.json.bak` (no timestamp — overwritten on each direct apply)
in the same directory as `settings.json` before each change. To restore
the last-known-good state:

```powershell
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Copy-Item "$wt.bak" $wt -Force
```

The picker (`tstyles` with no arg) doesn't write a `.bak` — pressing
Esc reverts in-memory to the exact prior bytes. If you need a full
history of changes (rather than just "undo the most recent direct
apply"), use `apply.ps1` instead — it keeps timestamped backups per run.

## Updating

```powershell
tstyles update
```

`tstyles update` detects how the module was installed and delegates:

- **PSGallery (`Install-PSResource`)** → runs `Update-PSResource -Name TerminalStyles`.
- **Bootstrap (`iwr | iex`)** → re-runs the bootstrap one-liner.

After update, open a new tab (or run `Import-Module TerminalStyles -Force -DisableNameChecking`) for the new version to take effect.

### How the update check works

For **bootstrap** installs only, `tstyles` issues at most one
unauthenticated HTTP GET per 24 hours per machine to
`api.github.com/repos/fcreme/TerminalStyles/commits/main` (capped at
2 seconds), comparing the returned commit SHA against the one
recorded at install time in
`%LOCALAPPDATA%\TerminalStyles\.installed-sha`. The 24h throttle is
tracked in `%LOCALAPPDATA%\TerminalStyles\.last-update-check` and
applies even on failure. No authentication, no payload sent, no
analytics.

PSGallery-installed copies skip this check entirely — `Update-PSResource`
handles version comparison internally when you run `tstyles update`.

## Uninstalling

```powershell
tstyles uninstall
```

`tstyles uninstall` detects how the module was installed and delegates:

- **PSGallery** → runs `Uninstall-PSResource -Name TerminalStyles` +
  strips the `Import-Module` loader from your `$PROFILE`.
- **Bootstrap** → removes the install-managed files from
  `%LOCALAPPDATA%\TerminalStyles\` (script files, bundled styles) and
  strips the loader.

**Either path preserves your user state by default** — your active
style (`current-style.ps1`), update-check throttle, and cached
background images stay at `%LOCALAPPDATA%\TerminalStyles\`. You can
reinstall (either path) and pick up where you left off.

To also remove the user state, pass `-DeleteData`:

```powershell
tstyles uninstall -DeleteData
```

Neither path modifies Windows Terminal's `settings.json` — your
current color scheme / cursor / background stays whatever it was
last set to.

If you want a clean default look back, either restore a
`settings.json.bak-<timestamp>` file from
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`,
or open WT Settings → "Open JSON file" and edit by hand.

## Adding your own style

Drop a folder into `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`
with:

```
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── background.gif     # default background image (optional, .png/.jpg also accepted)
└── README.md          # description (optional)
```

`tstyles` picks it up automatically on next module load — no
registration needed. The dir is the same regardless of install path
(bootstrap or PSGallery), and folders here **survive updates**: both
`tstyles update` (bootstrap re-install) and `Update-PSResource`
leave `%LOCALAPPDATA%\TerminalStyles\` untouched.

If you drop in a folder with the same name as a bundled theme (e.g.
`eva/`), your version wins — useful for tweaking a bundled theme's
prompt or palette without forking the repo.

To contribute your theme back to the bundled catalog, see
[CONTRIBUTING.md](CONTRIBUTING.md) — short version: code-only folder
under `styles/<name>/` on `main`, background image (if any) flat-named
on the `gifs` branch, and the maintainer curates what gets bundled.

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

After adding a new style, regenerate the screenshot gallery so your
theme shows up in the README:

```powershell
# Must be run from inside a Windows Terminal tab
pwsh -File .\scripts\capture-screenshots.ps1
git add docs/screenshots/
git commit -m "Refresh theme screenshots"
```

`capture-screenshots.ps1` iterates every installed theme, applies it,
takes one PNG of the WT window, then restores your original theme.

## Known limitations

- **One `$PROFILE` per host.** Confirming a style with a custom prompt
  replaces `current-style.ps1`. Switching styles changes the prompt
  globally — there's no per-tab prompt configuration.
- **Repo size grows with styles.** Bundled GIFs are committed binaries;
  contributors should keep each under ~2 MB and only submit images they
  have the right to redistribute.
- **Not every terminal can show every part of a style.** Windows Terminal reads
  the whole `theme.json` field set from its `settings.json`. Everywhere else the
  colors are applied as OSC escape sequences, and no escape sequence carries a
  background image or a tab accent color. On Terminal.app the image is instead
  delivered through a generated `.terminal` profile, which means a new window
  (`tstyles <name> -NewWindow`); tab accent color has no equivalent anywhere but
  Windows Terminal. An apply says which parts the current terminal cannot show
  rather than dropping them silently. Hosts that render nothing (VS Code's
  integrated terminal, conhost) stay plain by design.
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

## Contributing

Bug reports, feature ideas, and new themes are all welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Themes are the easiest way in:
pitch one with a [theme idea issue](https://github.com/fcreme/TerminalStyles/issues/new/choose),
or grab a [`good first issue`](https://github.com/fcreme/TerminalStyles/labels/good%20first%20issue).

## License

MIT — see [LICENSE](LICENSE).
