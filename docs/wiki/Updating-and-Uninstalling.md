## Updating

```powershell
tstyles update
```

`tstyles update` detects how the module was installed and delegates:

- **PSGallery (`Install-PSResource` or `Install-Module`)** → runs
  `Update-PSResource -Name TerminalStyles -TrustRepository`, or
  `Update-Module -Name TerminalStyles -Force` where PSResourceGet is not
  installed (Windows PowerShell 5.1 ships without it).
- **Bootstrap (`iwr | iex`)** → re-runs the bootstrap one-liner.

After update, open a new tab (or run `Import-Module TerminalStyles -Force -DisableNameChecking`) for the new version to take effect.

### How the update check works

`tstyles` issues at most one unauthenticated HTTP GET per 24 hours per
machine, with a 2-second timeout, asking for whatever `tstyles update`
would fetch:

- **PSGallery** → the PowerShell Gallery's feed
  (`www.powershellgallery.com/api/v2`) for the newest stable
  TerminalStyles, compared with the newest version installed on your
  module path. Nothing is asked when no installed copy can be found.
- **Bootstrap** → `api.github.com/repos/fcreme/TerminalStyles/commits/main`,
  comparing the returned commit SHA against the one recorded at install
  time in `%LOCALAPPDATA%\TerminalStyles\.installed-sha`.

When something newer is out, the picker, the tuner, `list`, `current`,
`random`, applying a style, `reset`, and `delete` when it removes the
active style print
`Update available (<installed> -> <latest>). Run: tstyles update`.
When the shell or program running `tstyles` captures its output —
`x=$(tstyles current)`, a pipe or redirect in zsh or bash, a script
running `pwsh -c` — it neither asks nor prints, and leaves the check to
the next command you see. Inside PowerShell the notice goes to the
screen, never into a pipe or a `>` redirect.

The 24h throttle is tracked in `.last-update-check` in your data dir
(`%LOCALAPPDATA%\TerminalStyles` on Windows) and applies even on
failure, so an offline machine pays the timeout once a day rather than
on every command. No authentication, no payload sent, no analytics; the
request identifies itself only as `TerminalStyles-UpdateCheck`.

## Uninstalling

```powershell
tstyles uninstall
```

`tstyles uninstall` detects how the module was installed and delegates:

- **PSGallery** → runs `Uninstall-PSResource -Name TerminalStyles`, or
  `Uninstall-Module -Name TerminalStyles -AllVersions` where PSResourceGet
  is not installed (Windows PowerShell 5.1 ships without it), and strips
  the `Import-Module` loader from your `$PROFILE`.
- **Bootstrap** → removes the install-managed files from
  `%LOCALAPPDATA%\TerminalStyles\` (script files, bundled styles) and
  strips the loader.

The confirmation lists every file it is about to edit by name — each
engine's `$PROFILE`, each shell rc file that actually carries a block,
each VS Code-family `settings.json` a style was saved to, and the
generated WezTerm style module, which it deletes. If it cannot strip one
(a read-only profile, or a block hand-edited down to a stray `BEGIN`), it
names that file at the end instead of closing on "TerminalStyles
uninstalled." The same goes for anything else it could not remove — a
copy of the module still installed, an install file, the WezTerm module,
or what `-DeleteData` could not delete: each is checked after the attempt
and named at the end with what finishes the job, and "TerminalStyles
uninstalled." is printed only when none of them is left. For a PSGallery
install, module copies are looked for on the module path of the PowerShell
running the uninstall and, on Windows, in the other engine's per-user module
folder too: PowerShell 7 and Windows PowerShell 5.1 each keep their own, so a
copy installed from one is out of the other's reach, and is named with the
command to run in that engine.

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

VS Code is the exception. A style saved into a VS Code-family
editor's `settings.json` is taken back out, from its record, for
every editor that has one — the confirmation names each file first,
and a key you changed by hand since is left alone. If a style cannot
be taken out, or the record of what was saved cannot be read,
uninstall says so at the end rather than reporting a clean
uninstall.

If you want a clean default look back, either restore a
`settings.json.bak-<timestamp>` file from the folder that holds your Windows
Terminal's `settings.json`
(`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`
for Stable), or open WT Settings → "Open JSON file" and edit by hand.
