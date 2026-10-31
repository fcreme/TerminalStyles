
<p align="center">
  <img src="docs/banner.png" width="600" alt="tstyles — switch terminal themes live">
</p>

<p align="center">
  <a href="https://github.com/fcreme/TerminalStyles/actions/workflows/test.yml"><img src="https://github.com/fcreme/TerminalStyles/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <a href="https://hub.xerj.org/contributors/fcreme.html"><img src="https://hub.xerj.org/contributors/fcreme/badge.svg" alt="XERJ Corpus Hub contributor"></a>
  <a href="https://www.powershellgallery.com/packages/TerminalStyles"><img src="https://img.shields.io/powershellgallery/v/TerminalStyles?logo=powershell&label=PSGallery" alt="PowerShell Gallery"></a>
</p>

**Switch terminal themes live.** Run `tstyles`, arrow through 18 themes
previewing each one *in your current tab* — **Enter** keeps it, **Esc** reverts to
exactly how it looked before. The palette, the cursor color and the prompt
repaint instantly on any terminal that speaks OSC; on **Windows Terminal** and
**WezTerm** the font, opacity and animated background come with them. All in one
command, all non-destructive.

<p align="center">
  <img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/picker-demo.gif" width="720" alt="Arrowing through the style picker, each theme previewing live in the terminal">
</p>

Works on **Windows Terminal**, **macOS Terminal.app**, **iTerm2**, and any
terminal that speaks OSC color sequences — and in **zsh** and **bash**, not just
PowerShell. Runs on PowerShell 7 and Windows PowerShell 5.1. Keep your own prompt
(Oh My Posh / Starship) with `tstyles <name> -KeepPrompt`.

## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

On macOS and Linux this needs PowerShell first — `brew install powershell`,
or see [Requirements](https://github.com/fcreme/TerminalStyles/wiki/Install#requirements). On Windows it is already there.

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

Prefer a one-line installer, or on a shell without PSResourceGet? See the
[bootstrap installer](https://github.com/fcreme/TerminalStyles/wiki/Install#alternate-bootstrap-installer).

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
    <td align="center"><b>kitty</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/kitty.gif" width="210" alt="kitty"></td>
  </tr>
  <tr>
    <td align="center"><b>lain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/lain.gif" width="210" alt="lain"></td>
    <td align="center"><b>marquee</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/marquee.gif" width="210" alt="marquee"></td>
    <td align="center"><b>neon-rain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/neon-rain.gif" width="210" alt="neon-rain"></td>
    <td align="center"><b>rain</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/rain.gif" width="210" alt="rain"></td>
  </tr>
  <tr>
    <td align="center"><b>snowday</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/snowday.gif" width="210" alt="snowday"></td>
    <td align="center"><b>sober</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/sober.png" width="210" alt="sober"></td>
    <td align="center"><b>tombraider</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/tombraider.gif" width="210" alt="tombraider"></td>
    <td align="center"><b>koholint</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/koholint.gif" width="210" alt="koholint"></td>
    <td align="center"><b>skyline</b><br><img src="https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/skyline.gif" width="210" alt="skyline"></td>
    <td align="center"><b>phosphor</b><br><img src="docs/screenshots/phosphor.png" width="210" alt="phosphor"></td>
  </tr>
</table>

## Documentation

The full guide is in the [wiki](https://github.com/fcreme/TerminalStyles/wiki):

- [Install](https://github.com/fcreme/TerminalStyles/wiki/Install): PSGallery and bootstrap installs, requirements, execution policy
- [Using tstyles](https://github.com/fcreme/TerminalStyles/wiki/Using-tstyles): the picker, every subcommand, tuning, fonts, `-KeepPrompt`, `-Target`, reset
- [Styles](https://github.com/fcreme/TerminalStyles/wiki/Styles): the bundled catalog, with screenshots
- [Terminals and Shells](https://github.com/fcreme/TerminalStyles/wiki/Terminals-and-Shells): macOS, Linux, zsh and bash, what each terminal can show, WezTerm, Terminal.app, VS Code and its forks
- [Background Images](https://github.com/fcreme/TerminalStyles/wiki/Background-Images)
- [Scripting and Recovery](https://github.com/fcreme/TerminalStyles/wiki/Scripting-and-Recovery): `apply.ps1`, and getting `settings.json` back
- [Updating and Uninstalling](https://github.com/fcreme/TerminalStyles/wiki/Updating-and-Uninstalling)
- [Creating a Style](https://github.com/fcreme/TerminalStyles/wiki/Creating-a-Style)
- [Known Limitations](https://github.com/fcreme/TerminalStyles/wiki/Known-Limitations)
- [FAQ and Troubleshooting](https://github.com/fcreme/TerminalStyles/wiki/FAQ-and-Troubleshooting)

The wiki is generated from [`docs/wiki/`](docs/wiki), so changes to it go
through a pull request like any other.

## Contributing

Bug reports, feature ideas, and new themes are all welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Themes are the easiest way in:
pitch one with a [theme idea issue](https://github.com/fcreme/TerminalStyles/issues/new/choose),
or grab a [`good first issue`](https://github.com/fcreme/TerminalStyles/labels/good%20first%20issue).

## License

MIT — see [LICENSE](LICENSE).
