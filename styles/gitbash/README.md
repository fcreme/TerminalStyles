# gitbash

> *`felip@DESKTOP MINGW64 ~/dotfiles (main)`*

Authentic Git-for-Windows MinTTY look. Pure white background, near-black
text, vertical-bar cursor, and the iconic multi-color prompt with live
git-branch detection. The only light-mode theme in the catalogue --
useful for screenshots, screen-sharing, or just a break from the
cinematic dark themes.

## Includes

- **scheme.json** — Git Bash / MinTTY defaults: white background,
  near-black text, the classic 16-color ANSI palette
  (`#A31515` reds, `#008000` greens, `#A6A000` yellows, `#0000BB`
  blues, `#BB00BB` magentas, `#007777` cyans).
- **theme.json** — bar cursor, Cascadia Code regular, padding 10,
  opacity 100, full-screen solid-white bundled PNG so picking gitbash
  cleanly wipes any GIF from the previously-active style.
- **profile.ps1** — recreates the Git Bash prompt:
  - Line 1: `<user>@<host>` (green) + `MINGW64` (yellow) +
    `<~-relative path with forward slashes>` (cyan) +
    `(<branch>)` (magenta, only inside a git repo).
  - Line 2: `$ ` (dark gray).
  - PSReadLine syntax colors tuned for a light background.
  - Tab title set to `GITBASH // MINGW64`.
  - **No startup banner** — Git Bash itself is silent.
- **background.png** — 256×256 solid `#FFFFFF` so the previous theme's
  GIF doesn't bleed through.

## Notes

- **Git branch detection** shells out to `git rev-parse` on every prompt
  render. On large repos this can add a small lag (~50–100 ms). Save /
  restores `$LASTEXITCODE` so it doesn't pollute the user's error checks.
- **Font:** Cascadia Code regular looks closer to the real Git Bash than
  semi-bold would. For full authenticity, change the WT profile font
  to `Lucida Console` (Git Bash's actual default).

## Preview

```
felip@DESKTOP MINGW64 ~/dotfiles (main)
$ _
```
