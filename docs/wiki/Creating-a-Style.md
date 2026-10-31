## Adding your own style

Drop a folder into `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`
with:

```
<name>/
├── scheme.json        # Windows Terminal color scheme (required)
├── theme.json         # profile-level overrides (optional)
├── profile.ps1        # custom pwsh $PROFILE (optional)
├── prompt.sh          # the same prompt for zsh/bash (optional)
├── background.gif     # default background image (optional, .png/.jpg/.jpeg also accepted)
└── README.md          # description (optional)
```

Without a `prompt.sh`, a zsh or bash tab gets your style's colors and none
of its prompt or banner — `profile.ps1` is PowerShell-only. Copy the
closest bundled style's `prompt.sh` and adapt it; `styles/sober/prompt.sh`
is the smallest. (Contributing a theme back to the repo? There it is
**required** — see [CONTRIBUTING.md](https://github.com/fcreme/TerminalStyles/blob/main/CONTRIBUTING.md).)

`tstyles` picks it up automatically on next module load — no
registration needed. The dir is the same regardless of install path
(bootstrap or PSGallery), and folders here **survive updates**: both
`tstyles update` (bootstrap re-install) and `Update-PSResource`
leave `%LOCALAPPDATA%\TerminalStyles\` untouched.

If you drop in a folder with the same name as a bundled theme (e.g.
`eva/`), your version wins — useful for tweaking a bundled theme's
prompt or palette without forking the repo.

That holds across updates too, including the bootstrap layout where the
install tree and this folder are the *same* directory. Each install
records a fingerprint of every style it places, so a bundled style you
have edited — or added a file to — is left alone by the next `tstyles
update` (it prints the names it kept) and by `tstyles uninstall`, which
also stops listing it for deletion. `tstyles list` calls it **yours** and
`tstyles delete` will remove it, the same as a style you wrote from
scratch. Put the shipped files back exactly and the style becomes the
install's again, so updates resume.

One bound, stated because it is a one-time hole and not a rule: the
fingerprint is written *by* an install. A folder you dropped in before
the first install that records one is overwritten once by that update —
the alternative, refusing to update any style the tool cannot vouch for,
would freeze bundled themes at whatever version you happen to have.

To contribute your theme back to the bundled catalog, see
[CONTRIBUTING.md](https://github.com/fcreme/TerminalStyles/blob/main/CONTRIBUTING.md) — short version: code-only folder
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
theme shows up on the [Styles](Styles.md) page:

```powershell
# Must be run from inside a Windows Terminal tab
pwsh -File .\scripts\capture-screenshots.ps1
git add docs/screenshots/
git commit -m "Refresh theme screenshots"
```

`capture-screenshots.ps1` iterates every installed theme, applies it,
takes one PNG of the WT window, then restores your original theme — so it
overwrites the rendered screenshots too. Check `git status` before adding
`docs/screenshots/`, and redraw any render you did not mean to replace with
`python3 scripts/make-preview.py <style>`.
