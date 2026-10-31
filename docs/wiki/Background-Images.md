## Background image

Each bundled style has its own animated background, hosted on the
[`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) of
this repo. `tstyles` lazy-fetches each one on first use of the style and
caches it under `%LOCALAPPDATA%\TerminalStyles\cache\<name>\`, so the
install stays small (~900 KB instead of ~10 MB). On Windows Terminal,
picking a style auto-applies the image and the arrow keys cycle the
background live alongside the colors / cursor / font. Terminal.app takes
one through a generated profile, which means a new window and a still
frame (see [Background images on Terminal.app](Terminals-and-Shells.md#background-images-on-terminalapp)). **WezTerm** shows one live in the running window and is the
only terminal off Windows that animates it — see [Animated backgrounds on
WezTerm](Terminals-and-Shells.md#animated-backgrounds-on-wezterm). Every other terminal gets the colors and the prompt, but no image.

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
