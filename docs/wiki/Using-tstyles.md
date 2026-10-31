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

As you arrow up/down, the terminal actually changes in real time: the
palette, the foreground and the cursor color, on every terminal that
speaks OSC. On Windows Terminal the font, opacity and background GIF
follow a beat later, once the keypresses stop. Press **Enter** to keep
the highlighted style, **Esc** to revert to how things looked before
you ran `tstyles`.

### Subcommands

```powershell
tstyles umbrella                  # Apply a specific style directly (no picker)
tstyles list                      # List all themes; '*' marks the active one, 'yours' marks yours
tstyles current                   # Print just the active style name
tstyles show <name>               # Preview a style's colours, then put the terminal back. Applies nothing.
tstyles random                    # Pick a random style and apply it
tstyles reset                     # Revert the active profile to its unstyled default
tstyles tune [name]               # Live-tune brightness/saturation/opacity/font; save as a style
tstyles delete [name]             # Delete a style you made (bundled styles are refused)
tstyles trash                     # List deleted styles, and how long each one has left
tstyles restore [name]            # Put a deleted style back; never overwrites a live one
tstyles font [name]               # List coding fonts, or install one and apply it
tstyles register                  # Auto-add `Import-Module TerminalStyles ...` to each engine's $PROFILE
tstyles shell-init                # Style zsh/bash too: add the loader to ~/.zshrc, ~/.bashrc, ~/.bash_profile
tstyles shell-remove              # Remove that zsh/bash loader again
tstyles profiles [-Clean]         # macOS: Terminal.app profiles this tool left behind; -Clean removes duplicates
tstyles vscode [on|off]           # VS Code: show, allow (on) or undo and stop (off) saving styles to settings.json
tstyles update                    # PSGallery: Update-PSResource (Update-Module without it). Bootstrap: re-run installer.
tstyles uninstall                 # Remove module + strip $PROFILE loader. Preserves user state.
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
tstyles help [command]            # Show all commands, or details for one
```

Tab completion works on the subcommand and style names:
`tstyles u<TAB>` cycles `umbrella`, `uninstall`, `update`. `tstyles delete
<TAB>` offers only the styles you may delete, and `tstyles restore <TAB>`
only the names sitting in the trash.

### Deleting a style, and changing your mind

`tstyles delete <name>` never erases: it **moves** the folder to
`.deleted/<name>-<timestamp>` in your data dir and keeps it for **7
days**. `tstyles trash` lists what is in there, when each one went and
how many of its days are left; `tstyles restore <name>` moves the newest
copy back under the plain name — the timestamp does not come with it.

A restore refuses rather than overwriting: if you have since made a new
style under that name, it says so and leaves the trashed copy where it
is. Nothing in the trash is erased until the **next** `tstyles delete`,
which lists every expired folder in red on the screen you confirm.

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

On save you choose **Overwrite** or **Save as** a new name. What Overwrite
means depends on where the style lives, and the prompt says which: for a
**bundled** theme it shadows the original, which stays in the module and
comes back if you delete your copy; for a theme that exists only in your
user-styles dir it *replaces* that theme, so it asks first.

Either way the result lands in your user-styles dir as a full style — so it
shows up in `tstyles list`, the picker, and tab-completion, and survives
`tstyles update` and `tstyles uninstall` even when it carries a bundled
theme's name. It inherits the base theme's background, and a small
`tune.json` records what you chose.

After a **Save as**, `tstyles tune <new-name>` resumes where you left off:
the brightness and saturation you set come back on the sliders. After an
**Overwrite** they do not, and this is deliberate — the colors are already
baked into the style itself, so re-applying the same adjustments on top
would darken or saturate it twice over. Re-tuning an overwritten theme
starts from neutral against its current colors; the opacity and font you
saved still come back. For the same reason, if the theme you tuned *from*
has itself changed since, the tuner says so and starts from its current
colors rather than stacking one set of adjustments on another.

### Installing a coding font

```powershell
tstyles font                      # list the catalog, with installed/installable markers
tstyles font 'JetBrains Mono'     # install it (if needed); on Windows Terminal, apply it too
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

Applying the font to a profile is a **Windows Terminal** thing —
`settings.json` is the only config file `tstyles font` writes. On every
other terminal the install is the whole job, and the command says so. The
font is then chosen in your terminal's own settings — or, on WezTerm and on
VS Code with saving on, by the applied style: `tstyles tune` saves a font
into a style.

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
with `-NoProfile` kept as an alias). A `-KeepPrompt` apply is still reported by
`tstyles current` and the `*` in `tstyles list`: detection normally byte-compares
the installed prompt, which this flag deliberately leaves alone, so it falls back
to the style record that every apply writes.

### Which profile a style lands on (`-Target`)

On Windows Terminal a style is written to one profile — by default the one the
tab you are sitting in uses. `-Target` names a different one:

```powershell
tstyles eva -Target 'Ubuntu'   # style that profile instead of this tab's
tstyles eva -Target defaults   # style profiles.defaults: everything inherits it
```

That profile lives in the `settings.json` of the Windows Terminal the tab
belongs to — Stable, Preview, Canary, or an unpackaged or portable copy.
Windows Terminal does not tell the shell which build it is, so tstyles reads it
off the process the session runs under. When that process does not lead back to
a running Windows Terminal (a program in between has exited, say) and more than
one build has a `settings.json`, it lists them and edits none: open a new tab
in the one you want and run it there, or set `$env:TSTYLES_WT_SETTINGS` to that
build's `settings.json` for the session. That variable wins over the detection
wherever it is set, so with more than one build installed keep it out of
`$PROFILE`, which every build's tabs run.

**`defaults` is a target name, not a placeholder.** It is Windows Terminal's
`profiles.defaults` block, which every profile that does not set a field itself
inherits — so a style applied there reaches all of them at once. That is also
why it is the one target that can change a profile you did not name: applying a
later style with no background image of its own clears the image from
`defaults`, and every profile that was inheriting it loses that image too.
The tool offers the name — it is first in the list a mistyped `-Target` prints,
and first in the menu `apply.ps1` shows when you do not pass one — so it is
documented here rather than only in that error message.

`tstyles reset` takes the same `-Target`, including `defaults`.

### Resetting a profile

To undo theming and return a profile to Windows Terminal's plain default:

```powershell
tstyles reset                  # the active profile
tstyles reset -Target 'Ubuntu' # a specific profile
tstyles reset -Target defaults # the block every profile inherits from
```

This strips the colors, cursor, font, opacity, and background a style added,
removes the now-unused color scheme, and restores your own prompt (open a new
tab to see it). It's the inverse of applying a style, and writes a
`settings.json.bak` first — that last part is Windows Terminal only. In a VS
Code-family terminal whose editor you let TerminalStyles save styles to, the
reset also takes the style back out of that editor's `settings.json`, from its
record: earlier values come back, and a key you changed by hand since is left
alone and named. No `.bak` is written for that. Elsewhere there is no
`settings.json` to strip: the reset is an escape sequence handing color control
back to the terminal's own profile, so there is nothing to back up and no
`.bak` is written. In WezTerm that profile includes the module TerminalStyles
generated, `~/.config/wezterm/terminalstyles.lua`, so the reset also rewrites
it to one that applies nothing. The tab you reset in and every new tab come up
in your own `wezterm.lua`, and other open tabs lose what the module set: the
font, padding, cursor shape, opacity, tab color, background and color scheme.
WezTerm keeps colors an escape sequence set as that tab's own, though, so the
tab you applied a style in can keep its colors until you close it or run
`tstyles reset` there. A reset run in another terminal leaves the module alone,
as it leaves VS Code's `settings.json`. Fields you set on the profile by hand
are left alone.

If you styled `profiles.defaults` (`tstyles eva -Target defaults`), a reset of
one profile also has to deal with what that profile *inherits* — Windows
Terminal resolves every profile against `profiles.defaults`, so stripping the
entry alone hands the window straight back to the inherited copy. A background
image on `profiles.defaults` that TerminalStyles put there is cleared with the
profile, and the command says so, because that clears it for every profile
inheriting it. An inherited **color scheme** is not: removing it would restyle
every other profile on a command that named one. Reset says which scheme is
still coming from `profiles.defaults` and how to clear it
(`tstyles reset -Target defaults`) rather than reporting an unstyled default you
would not see.
