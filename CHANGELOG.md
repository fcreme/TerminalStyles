# Changelog

All notable changes to TerminalStyles are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **a redirected run spent the one-time font offer without anyone seeing it.** `Invoke-FontFirstRunPrompt` gated on `[Environment]::UserInteractive`, which is `$true` whenever the process has a console -- redirected stdin included -- so a bare `tstyles` from a pipe, a file, a script or a CI step reached the `Read-Host`. It returns empty at EOF rather than throwing, so the prompt went into the redirect, the answer was nobody's, and the marker was written anyway. The offer is one-time by design, so it was gone: no interactive session was ever asked again. The same shape as the update notice the tuner printed and instantly wiped while still burning its 24-hour throttle. It checks `IsInputRedirected` and `IsOutputRedirected` now, as the picker and the tuner already did -- this was the third `Read-Host`/keyboard path in the project and the only one that did not. Both directions matter: a redirected stdin means the answer is not the user's, and a redirected stdout means `Read-Host` blocks a real console on a question nobody can read
- the four `Get-MonospaceFontList` cases added for the known-names union passed `-MonospaceNames $null`, which is what asks the function to work the list out itself -- and on Windows that branch measures glyph widths through GDI+ rather than consulting the canonical table. Synthetic `-Installed` names are not installed fonts, so every one failed measurement, the list fell through to its Consolas fallback, and all four failed on both Windows jobs while passing on macOS and Linux. They mock the platform seam now, so the branch they are about is the branch they exercise on every runner
- **the case-sensitivity probe answered backwards on Windows PowerShell 5.1.** `Test-PathCaseInsensitive` compared `(Get-Item ...).FullName` for the two spellings, which is canonical only on .NET Core: on .NET Framework the provider echoes the caller's own casing straight back, so two spellings of one NTFS directory compared unequal and the probe reported a case-SENSITIVE volume on the most case-insensitive one there is. The engine decided the answer, which is the same class of mistake as inferring it from the platform name -- the thing this function was written to stop. Green on pwsh 7 and red on 5.1, same machine, same directory. It rebuilds each path from the names the parent directory actually lists now, preferring an exact match so a genuinely case-sensitive volume still reports two directories. Caught by CI, which runs both Windows engines; the local run that preceded the commit was macOS-only
- `tstyles font` walked every font directory on the machine once per catalogue entry. `Show-FontList` called `Test-FontInstalled` without the `-Installed` list, and that function enumerates for itself when the list is absent, so a six-entry catalogue produced six full enumerations. Off Windows each one is a recursive scan of `~/Library/Fonts`, `/Library/Fonts` and both `/System/Library/Fonts` trees -- 672 files on the machine this was measured on, walked six times over: 378ms against 113ms for a single shared pass. On Windows each is a fresh `InstalledFontCollection`. The cost is linear in the catalogue, so every font added made the listing slower for everyone -- and the `-Installed` seam existed for exactly this while the one real caller was not using it
- a font published as a bare `.ttf` behind a URL carrying `?raw=1` installed under a name nothing could find again. `Resolve-FontPackage`'s direct-download branch stripped the query string when it tested the extension -- so the branch fired -- and then built the destination name from the raw URL, writing `Font.ttf?raw=1` to disk. `Get-InstalledFontFamily` counts only files whose extension is `ttf`/`otf`/`ttc`/`otc`, so the font was invisible to the tool from that moment on: `tstyles font <name>` reported the install as successful and the font as still missing, then downloaded and installed it again on every subsequent run. On Windows it never got that far -- `?` is not a legal filename character, so the copy threw. A `#fragment` failed the other way round: it stayed in the extension, so the branch did not fire at all and a bare `.ttf` was handed to `ZipFile::OpenRead`. One query-stripped URL path now backs both the extension test and the name. Latent today, since all six catalogue entries are zips -- the same standing this branch's previous defect had

## [0.8.18] - 2026-08-29

### Fixed

- **a scheme value could smuggle an arbitrary escape sequence into every new shell.** `Get-SchemeOscPacket` interpolated slot values into OSC sequences with no validation, and README documents dropping a third-party style folder into the styles dir. A `background` of `#000000<BEL><ESC>]52;c;...` closed OSC 11 early and made the remainder a second, attacker-chosen sequence -- and this packet is not written once: `Set-ShellStyleState` persists it to `current-style.osc`, which every new zsh/bash shell replays, so it re-executed on every shell start indefinitely. Every value is normalised to `#rrggbb` before it reaches the string now, so nothing can escape the sequence
- **the tuner froze shorthand and 8-digit hex while adjusting everything around it.** Three notions of "a colour" lived in one file: `Get-AdjustedScheme` accepted only 6-digit hex, so a style written with `background: '#013'` (valid, and what Microsoft's own colour-scheme docs allow) kept its background fixed while the foreground and the whole palette brightened -- and `#RGB` is valid XParseColor, so the terminal genuinely applied the frozen value. `Get-SchemeSwatch` used a *third*, stricter test and dropped the slot from the preview row entirely, silently promoting another colour into its place, so the tuner's only in-menu feedback never showed it. A save then baked the frozen value in for good. One `ConvertTo-NormalHex` now backs all three
- **`tstyles current` reported no active style right after applying one, on Windows Terminal.** `Get-CurrentStyleName` byte-compares `current-style.ps1` against each style's `profile.ps1` and falls back to a recorded name when there is nothing to compare -- but `Apply-StyleDirect`'s Windows Terminal branch never wrote that record, and for a style with no `profile.ps1` it *deletes* `current-style.ps1` one line earlier. Tuned styles hit this routinely, since `Save-TunedStyle` only writes a `profile.ps1` when the base has one. So `tstyles current` printed "(no bundled style currently active)", `tstyles list` showed no `*`, the picker opened at index 0 and a bare `tstyles tune` errored "No active style detected" -- while settings.json plainly carried the style's `colorScheme`. Both halves fixed: the WT apply records, and the WT reset clears
- **a Save-As over an existing style was a merge, not the replace it promised.** "'<name>' already exists and will be REPLACED. Continue?" -- and then anything the new base did not itself ship survived from the old style. `profile.ps1` and `prompt.sh` are both optional (README says so), so tuning a style that has neither, saved over a name that was previously tuned from one that has both, left the old theme's profile and prompt in place: the replaced style printed the wrong banner and set the wrong prompt. The two artefacts Save-TunedStyle owns are now copied *or removed*, and an Overwrite re-tune (where base and destination are one directory) is untouched
- **the tuner's own menu could dye itself invisible.** `$drawMenu` passed `-ForegroundColor Cyan/DarkGray/Yellow/Gray`, and PowerShell maps those onto SGR 96/90/93/37 -- brightCyan, brightBlack, brightYellow and white, which are exactly the palette slots the tuner has just retinted over OSC 4. On the bundled light theme gitbash the background is `#ffffff` and lightness clamps at 1.0, so the background cannot move while the text climbs into it: measured 1.482:1 at brightness +20 and exactly **1.000:1 at +55**, where the menu is gone and the slider that caused it cannot be read or reversed. The chrome is derived from the adjusted background as truecolor now, holding 14.7:1 across the whole range -- the hint line had always done this; the other four elements now do too
- **a `tune.json` carrying only `base` seeded opacity 0 and font size 0.** That is a shape this project itself writes and treats as valid, and `[int]$null` is 0 -- so the tuner opened showing "Opacity 0%" and "Font size 0", discarding what the style declared, and a straight Enter save wrote opacity 0 (a fully transparent window) and font size 0 onto the profile. Recovery was asymmetric too: Left clamps font size at 6, Right walked a seeded 0 up through 1..6. Each field is now read only when `tune.json` actually carries it -- a key written as `null` counts as absent -- falling back to what the style declares for itself
- `tstyles tune` printed the once-a-day update notice and then wiped it with `Clear-Host`, which pwsh emits including `ESC[3J` -- so it took the scrollback too and the notice was unrecoverable. Worse, printing it burned the throttle: the check stamps `.last-update-check` on every attempt, so having flashed the notice unreadably the tool then stayed silent for 24 hours and no other command showed it either. Held and printed after the tuner gives the screen back, on every exit path, exactly as the picker already does -- and the check now happens after the console guards, so a non-interactive run pays neither the HTTP timeout nor the throttle write
- **`tstyles tune <name> > out.txt` drove a screen nobody could see.** The redirected-*input* guard added above does not fire when stdin is a real console, so the tuner took over: the menu, the swatch and every OSC repaint went into the file (151 escape sequences measured on a pty run), the terminal showed nothing, and keystrokes were read and acted on blind. It checks `IsOutputRedirected` too now, matching what the shell half already does before emitting a palette
- the tuner would happily save a style named after a subcommand. `reset`, `list`, `tune`, `uninstall` and the rest all passed the name check, and the resulting style listed, tab-completed and appeared in the picker -- but could never be applied, because `Invoke-TerminalStyle` dispatches every subcommand before it considers a style name. `tstyles reset` ran the *reset*: OSC reset, style record and shell state cleared, `current-style.ps1` deleted, "Reset <terminal> to its unstyled default." One list now backs both the completer and the name check, so they cannot drift
- the three one-hop self-reference guards compared style paths with `-eq`/`-ne`, which are case-insensitive everywhere, while `Test-SameStyleDirectory` -- written precisely because "-eq is wrong here" -- was called from `Save-TunedStyle` alone. On a case-sensitive volume `styles/eva` and `styles/Eva` are two directories that `-ne` collapses into one, so the guard fired on a style legitimately based on a name differing only in case and dropped its deltas. All three use the helper now
- `Test-SameStyleDirectory` itself inferred case sensitivity from the platform NAME -- Ordinal on Linux, OrdinalIgnoreCase everywhere else -- but case sensitivity is a property of the VOLUME. On case-sensitive APFS (chosen at format time), a Windows directory flagged with `fsutil file setCaseSensitiveInfo`, or a case-sensitive network mount, a Save-As differing from its base only in case looked like the same directory, skipped the `prompt.sh` copy, and produced a brand-new style with no zsh/bash prompt at all -- while the collision prompt stayed silent, because the destination genuinely did not exist. It asks the filesystem now, falling back to the platform guess only when there is nothing to probe. The function's docstring had claimed since it was written that it was carved out to be directly testable; it now is
- the font knob promised "every monospace font installed on your machine" and offered only the curated favourites plus families whose name matches `mono`/`code`. Iosevka, Cousine, Inconsolata, Terminus, Hasklig, Anonymous Pro, PragmataPro and MonoLisa were dropped silently -- and three of those are in the module's own canonical font table, which `Get-InstalledFontFamily` uses to resolve installed filenames, so the module went out of its way to name them and then the knob discarded them. Anything the table already knows is offered
- README claimed a tuned style's `tune.json` "remembers your adjustments so `tstyles tune <name>` resumes where you left off", immediately below the paragraph introducing Overwrite -- for which it is false in both flavours, and deliberately so: the colours are already baked into the style, and re-applying the same deltas would darken it twice. The paragraph now says which save resumes what, and why
- **`tstyles tune ../styles/eva` deleted `styles/eva`**, printed "Reverted." and exited 0. The tuner's scratch directory was `<DataRoot>/.tune-preview/<name>` and its `finally` block removes it whole and recursive on every exit path. `.tune-preview` and `styles` are both single-segment children of the data root, so any name reaching up one level made the two paths the same directory -- the scratch dir *was* the style dir. Three ways in, all of them reproduced: typing the name; a tuned style whose `tune.json` `base` carried the traversal, which needed nothing unusual typed at all; and Enter -> `[1] Overwrite`, which skipped even the Save-As name check, so the style was written, applied, reported as saved, and then deleted. Style names are now validated at the one choke point every path is built from -- `Get-StyleDir` refuses anything that is not a single directory segment, which is the honest answer since `../styles/eva` is not a style. It rejects paths, not names: a hand-authored style is whatever folder the user dropped in and README puts no constraint on what it is called, so spaces and non-ASCII still resolve. The tuner's scratch directory now sits in a per-process session directory (with the base's name still on the leaf, which is what the background cache is keyed on), and the recursive delete proves its target is inside `.tune-preview` instead of trusting it
- **two `tstyles tune` sessions open at once destroyed each other's work.** The scratch directory was keyed on the base style name, so two sessions tuning the same base shared one -- and whichever exited first deleted it, recursively, out from under the other. The survivor's next preview write then threw from inside the Enter path, unwinding past the Save/Save-As prompt and past `Save-TunedStyle`: no prompt, nothing written, every adjustment gone. Off Windows Terminal those writes were doing nothing in the first place. The comment above them said "the scratch style above is written either way -- Save-TunedStyle reads it on Enter", which was never true; `Save-TunedStyle` is called with `-BaseStyleDir $baseDir`, never with the scratch dir. The scratch style is Windows-Terminal-only now, as its one real consumer (`Merge-StyleIntoSettings`) always was, and the preview on the Enter path can no longer take the save down with it
- **`[1] Overwrite` said "(shadows the bundled style)" while destroying a style that had no bundled original.** For a theme you hand-authored per the README, or saved here earlier with Save As, there is nothing in the module to fall back to -- so the option rewrote it in place, no confirmation, no `.bak`, no undo, one line after the label had asserted the original was safe. The Save-As branch twenty lines below has drawn exactly this distinction since 0.8.x, and even carries the comment explaining it; option [1] never did. The label is now decided by where the style actually lives, and the destructive case asks the same y/N Save-As asks
- **`tstyles uninstall` deleted a style you had tuned with `[1] Overwrite`**, one line after printing "PRESERVE user state ... pass `-DeleteData` to wipe". Overwrite saves under a *bundled* name -- that is the option's purpose -- and a bundled name is exactly what `.installed-files` always contains, so the manifest that 0.8.17 added to stop uninstall deleting user styles named this one. A Save-As tune under a fresh name survived, which made the loss silent and inconsistent. A style carrying `tune.json` is the user's now, and the uninstall plan leaves it alone
- **`tstyles update` reverted an Overwrite-tuned style to stock and left its `tune.json` lying about it.** `Sync-InstallTree` copied the shipped tree over the install dir, so `styles/<name>/scheme.json`, `theme.json` and `profile.ps1` went back to the version's originals -- while `tune.json`, which ships with nothing, survived and went on claiming brightness -35 against colours that no longer had it. Re-tuning could not recover it either: `Resolve-TuneSeed` hits its self-reference guard on such a style and comes up neutral. `styles/` is merged one style at a time now, and a style carrying `tune.json` is left where it is; everything else still updates
- **re-tuning a style silently doubled its adjustments when the style it was tuned from had changed.** A tuned style stores *deltas*, not colours, so they only mean anything while the base still holds what they were measured against. Tune `eva` by -35 and save it as `eva-night`; Overwrite-save `eva` itself at -20; re-open `eva-night` and it seeds -35 against a base already carrying -20 and previews at -55. Saving from there bakes the drift in, and it compounds every round. `tune.json` now records a fingerprint of the base scheme it was measured against, and the tuner starts from the base's current colours -- saying so on screen -- rather than stacking. A `tune.json` written before this field keeps seeding as it always did: missing means unknown, not changed
- **Esc put the wrong style back on screen.** Off Windows Terminal the revert re-emitted `$baseScheme` -- the *working base*, which for a tuned style is a different file from the style being tuned. Opening the tuner on `eva-night` resolves its base `eva`, because that is what the deltas are measured from, so Esc repainted the terminal as eva, printed "Reverted.", and left the user on a style they had never chosen and had not been using a moment earlier. It restores the style the tuner was opened on now. Same bug the picker's Esc had, one level further in
- a base `theme.json` that was empty, truncated, or held a bare JSON scalar or array parsed to something `Add-Member` cannot extend. Those failures are non-terminating, so `New-TunedThemeObject` sailed on and returned `$null`, which `ConvertTo-Json` writes out as the four characters `null` -- a saved style with no `colorScheme`, no `opacity` and no font, while the tuner reported "Style applied". On Windows Terminal that is a profile pointing at nothing with an orphaned scheme beside it. It falls back to an empty object, so everything the tuner sets is written
- `Resolve-TuneSeed` wrote `BaseName` and `BaseDir` into the seed *before* the `[int]` casts that can throw. A `tune.json` whose brightness was not a number -- hand-edited, shared, truncated by a full disk -- threw on the cast with the base already swapped in and the "seeded from tune" flag still false, so the fallback then seeded from the *base's* `theme.json`: the tuner opened on the base style with neutral knobs, and saving re-baked the tuned style as a copy of it. The conversions happen into locals first and are committed only once all of them succeed
- the tuner's Save-As prompt accepted `.` and `..` -- both match `^[A-Za-z0-9._-]+$`, and neither is a name -- writing the style's four files into the styles directory itself or its parent, producing something `tstyles list` could never show. It also accepted a name long enough to abort the save with a raw .NET path-too-long exception, after the user had already committed to it. Two rules now, and the distinction is the point: `Test-StyleNameIsSingleSegment` gates every name-to-path conversion and rejects only what stops a name being one directory segment, while the stricter `Test-StyleNameValid` applies where the tool INVENTS a directory rather than resolving one -- today just the Save-As prompt, which has enforced `^[A-Za-z0-9._-]+$` since it was written
- **the tuner's "Font face" knob was completely dead, and the first press on it killed the session.** One of the five knobs, on every platform, for every style. `Get-MonospaceFontList` ends with `return ,@(...)` -- the leading comma is deliberate, so that a machine with one monospace font hands back a list rather than a bare string the knob would then index per character. The tuner wrapped that call in `@()` as "belt and braces". The two do not compose, they cancel: `@()` does not re-enumerate a single array object, it nests it, so `$fontList.Count` was 1 with the whole list as element 0. `($fontIdx +/- 1) % 1` is always 0, so Left and Right moved nothing -- and the assignment behind them handed an `Object[]` to a `[string]$FontFace` parameter, which refuses it outright. The tuner died on a raw parameter-binding error inside the key loop and every adjustment made up to that point was lost. `tests/Get-MonospaceFontList.Tests.ps1` was green throughout because all four of its array-contract cases call the function bare, the one form where the comma holds; a fifth test pinned the broken call site by source text, so the actual fix turned it red. It now asserts the behaviour -- that the knob yields a `[string]` and that it moves
- **`tstyles tune <name>` with stdin redirected repainted your terminal and wiped your scrollback before failing, then reported success.** A pipe, a redirect, a CI step or any tool running commands with stdin detached. `[Console]::KeyAvailable` throws when stdin is not a console, but it is polled at the top of the key loop -- so everything before it had already happened: the notice, a 900ms sleep, the first preview write, the OSC packet that repaints the live terminal, and the `Clear-Host` that emits `ESC[3J` and takes the scrollback with it. Only then came the raw .NET text, "Cannot see if a key has been pressed ... Try Console.In.Peek". The process exited 0, so the zsh/bash shim's `if [ $_ts_rc -eq 0 ]` read the crash as a successful run. Measured on this fix: before, one `ESC[3J`, two OSC background repaints and the .NET error; after, none of the three. The picker was given exactly this guard in 0.8.0 and the tuner never got it -- it now checks `[Console]::IsInputRedirected` before it touches the screen and says what it needs. The three tests covering the off-Windows-Terminal notice were reaching it only by riding this crash and swallowing it in `catch { }`; they are AST assertions now, the same trade `tests/Picker-NonWT.Tests.ps1` already documents
- **style prompts overwrote your own shell variables.** The staged `prompt.sh` is sourced straight into your interactive shell, and 11 of the 16 styles assigned bare single-letter names at top level -- `X`, `W`, `D`, `M`, `P`, `R`, `Y`, `C`, `B`, `G`, `L`, `O` and `Mist`/`Moss`/`Slate` -- so opening a terminal silently clobbered anything you had by those names. All namespaced under `_ts_` now; every style renders byte-identically after the rename
- the banner box was misaligned in 5 of the 9 boxed styles -- halo, lain, marquee, neon-rain and tombraider -- by 1 to 3 columns, always on the line with a colour code embedded mid-string, which is where hand-counted padding goes wrong. It was wrong identically in both halves (`prompt.sh` for zsh/bash and `profile.ps1` for pwsh), since the two are hand-maintained copies of the same art. A test now measures the rendered output with the escape sequences stripped, and checks the two halves agree
- **a `$` anywhere in your home directory path stopped the runtime loading entirely** -- no colours, no prompt, no error, on every shell. The generated rc block put the path inside double quotes, which protect spaces and apostrophes but not `$`, so the shell expanded it and the path came out wrong. Single-quoted now
- **`shell-init` ignored `$ZDOTDIR`.** zsh reads `$ZDOTDIR/.zshrc` and does *not* read `~/.zshrc`, so anyone with a relocated zsh config -- the standard XDG layout, and most dotfile frameworks -- got a success message and a block in a file zsh never opens
- **one byte that was not valid UTF-8 in your own rc file was silently replaced.** Both halves read the whole file and write it back, so a latin-1 comment became a replacement character on the first `shell-init` and was gone for good. rc files are now read and written byte-preservingly
- `shell-remove` was not the byte-exact reversal it is documented to be: each init/remove cycle left one extra blank line behind
- `shell-init`'s closing hint always said `source ~/.zshrc`, even when it had only registered bash files. It now names a file it actually wrote
- **a bash user on macOS got no style at all.** Terminal.app starts bash as a LOGIN shell, which reads `~/.bash_profile` and never `~/.bashrc` -- and `shell-init` only registered files that already existed, so someone with a `.bashrc` and no `.bash_profile` saw a green "added ~/.bashrc", opened a new window, and got their default prompt with no hint anything was missing. `shell-init` now creates `~/.bash_profile` (sourcing their `~/.bashrc`, the conventional shape, so their own config keeps working in login shells), or registers in `~/.profile` where one already exists rather than shadowing it
- **`tstyles shell-remove` could report success while leaving the loader in place.** A `BEGIN` marker with no matching `END` made the strip match nothing, and an unwritable rc file (read-only dotfiles, a symlink into a nix or chezmoi store) was reported as *"No shell loader was registered"* -- the opposite of the truth, sending you looking for a block the tool had just denied existed. The three outcomes are now distinguished and each is reported for what it is
- an orphaned loader block left the rc file exiting 1. The block is the last thing in the file, so with the runtime gone `[ -r x ] && . x` made the whole file fail: `set -e; source ~/.bashrc` aborted before doing any work, and every new terminal opened showing a failed status with no failing command behind it
- **an interactive shell with a redirected stdout still emitted the palette and the style's banner**, so anything capturing output from your login shell got them glued to the front of the value. `zsh -ic 'cmd'` is how editors and IDEs learn your real `PATH`; measured on a clean sandbox, a `PATH` probe came back as 854 bytes of escape sequences instead of 14 bytes of path, and was unusable. The guard tested `$-`, which says the shell is interactive and nothing about where fd 1 goes. The PowerShell half of the project has always checked `[Console]::IsOutputRedirected`; the shell half now checks `[ -t 1 ]` to match. `ssh host command`, scp and rsync were never affected -- those are non-interactive and were already covered
- **`tstyles <style>` from zsh or bash printed the style's banner twice**, every time. The shim runs a one-shot pwsh process that exits immediately, so dot-sourcing the style's `profile.ps1` to "live reload the prompt in this shell" reloaded nothing and printed the banner; the shell function then re-sourced the staged `prompt.sh` to swap the prompt for real, printing it again. The pwsh-side reload is now skipped when the shim's own `$TStylesNoAutoLoad` signal is set, and still happens for `tstyles <style>` run from a real pwsh session

## [0.8.17] - 2026-08-27

### Fixed

- `tstyles update` on a bootstrap install runs the installer inside the module's own scope, so the three functions `install.ps1` duplicates from the module (`Get-TStylesPlatform`, `Get-TStylesDataRoot`, `Get-PowerShellEngineCandidate`) do not sit beside the module's copies -- they REPLACE them for the rest of that session. One had drifted: the module returned `[pscustomobject]`, the installer raw hashtables, and uninstall enumerates `.Exe` over the result. So `tstyles update` followed by `tstyles uninstall` in the same tab ran a different function than the same command in a fresh one. All three carried a "keep in sync" note already; nothing enforced it, and now a test does
- **`tstyles uninstall` deleted the styles you wrote.** It printed "PRESERVE user state ... pass `-DeleteData` to wipe" and then removed `styles/` wholesale -- and your own styles live in that directory, beside the bundled ones, because that is how the documented override works. Every style you had authored or tuned was gone, silently, one line after being told it would be kept. `install.ps1` now records what it placed in `.installed-files` and uninstall removes exactly that, style folder by style folder
- an uninstall left `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/`, `tests/`, `.github/` and `.gitignore` behind in the data root. The bootstrap extracts the whole repo; the removal list named 13 of the 21 entries it unpacks
- **the documented `iwr | iex` install opened with a red error on macOS and Linux.** `chcp` is a Windows console command, and `$null = & chcp ... 2>&1` does not swallow its absence -- a missing native command is a PowerShell error, not stderr -- so "The term 'chcp' is not recognized" was the first thing anyone following the README saw. The install itself worked; it just looked like it had failed before it started
- the install's closing line told macOS and Linux users they were "Also wired up for Windows PowerShell 5.1", which does not exist there. It named the other engine by inverting `$PSVersionTable.PSEdition`, which assumed the only two engines are pwsh 7 and Windows PowerShell 5.1 -- true while the probe looked for `pwsh.exe`/`powershell.exe`, and false once it became platform-aware and started finding `pwsh` alongside `pwsh-preview`
- `tstyles list` threw on a style whose `scheme.json` holds a colour that is not 6-digit hex. `Get-SchemeSwatch` checked only the length before `[Convert]::ToInt32`, so `not-a-color` or `#zzzzzz` reached the conversion. The bad value is now skipped in the dedup pass rather than the render pass, so it does not consume one of the five swatch slots either -- the remaining valid colours still fill it. Thanks to [@cnovakdev](https://github.com/cnovakdev) for the fix ([#11](https://github.com/fcreme/TerminalStyles/pull/11))
- `docs/RELEASING.md`'s post-publish smoke test told the maintainer to run `Get-Command -Module TerminalStyles` and expect `tstyles` in the output. Bare `Get-Command -Module` lists functions only, so the alias never appeared -- every release since it existed looked like a failed publish at the final verification step. `-CommandType Function,Alias` is what shows it

### Internal

- `tstyles font` was exercised end-to-end for the first time -- list, install, re-install, unknown names, and a deliberately tampered SHA-256 -- against a sandboxed font directory. No defects found. Two properties it was relying on without checking are now pinned: a hash mismatch leaves nothing on disk (not even the directory it would have unpacked into), and a hostile archive entry cannot write outside the extract directory


## [0.8.16] - 2026-08-27

### Fixed

- **the interactive picker could never deliver a background image on Terminal.app.** `tstyles` + arrow + Enter applied colors and prompt, said "Style applied", and stopped -- no profile written, no mention that the style ships a background, no hint about how to see it -- while `tstyles <name>` on the same terminal did all three. That is the primary macOS flow. `tstyles -NewWindow` was worse: accepted without error, and did nothing at all
- **`tstyles random -BackgroundImage <path>` silently dropped the flag** and reported success, while `tstyles <name> -BackgroundImage <path>` honoured it. `-BackgroundImage ""`, the documented way to apply a style with no background, was dropped the same way
- **kitty's selection highlight made selected text unreadable.** `selectionBackground` was a byte-identical copy of `cursorColor` (a near-white pink), so selecting a line filled the cells with it while the text kept its own colour: foreground at 1.34:1, `brightRed` at 1.00:1 -- invisible. Now the dark plum the style always meant, which its own PSReadLine highlight has been using all along
- `tstyles help LIST` failed under Turkish and Azerbaijani locales, printing "No help topic 'LIST'." directly above a topics line containing `list` -- while `tstyles LIST` worked in the same session. The lookup lowercased with the current culture, where an uppercase `I` becomes a dotless `i`
- `scripts/demo.ps1 -Restore` destroyed a personal style when its name collided with one created during the demo. Prep *moves* your styles aside, so the parked copy is the only copy, and the merge branch deleted it. Both copies are now kept, and it says where
- three false claims in the docs: `docs/DEMO.md` said the demo never writes Windows Terminal's `settings.json` (on WT every stage of it does); kitty and golden-forest both said "No `profile.ps1` -- purely visual" while shipping one that replaces your prompt; gitbash documented a yellow that is in no slot of its scheme. Six more style READMEs listed what they ship without mentioning `prompt.sh`

### Changed

- `scripts/` is no longer shipped to the PowerShell Gallery. `capture-screenshots.ps1` was included as "useful for theme authors", but it requires `$env:WT_SESSION`, the bootstrap layout at `%LOCALAPPDATA%\TerminalStyles\`, and a repo checkout to write `docs/screenshots` into -- a Gallery consumer has none of the three, so it could only ever fail for the people receiving it. Theme authors work from a clone, which is what the README and CONTRIBUTING both tell them to do

### Fixed

- `scripts/setup-gifs-branch.ps1` described itself as "idempotent: safe to re-run" and was neither. It snapshots `styles/<name>/background.*` as its first step and those are blocked from `main`, so every re-run ended in a "nothing to migrate" throw. The migration completed before 0.2.0; the script now says so and exits cleanly, and is kept as the record of how the `gifs` branch came to be

### Internal

- an audit of the test suite itself found seven assertions that could not fail, each proved by restoring the regression it named and watching it stay green. The worst pair were the guards written to protect the `lib/` split: they iterated a list that Pester leaves empty at run time, so an uncommitted `lib/` file passed both. `Get-PublishStagePlan` now refuses one outright, which is what those guards always claimed it did
- `scripts/demo.ps1` had no tests, because dot-sourcing it ran the demo. It has a `$TStylesDemoNoRun` seam now, matching `install.ps1` and `apply.ps1`

## [0.8.15] - 2026-08-27

### Fixed

- **`tstyles reset <profile>` reset the wrong profile.** The name landed in the second positional slot and the dispatcher read only `-Target`, so it was silently ignored and the auto-detected profile was reset instead -- with a success message. `-Target` still wins when both are given
- `tstyles ls` worked but was offered nowhere: it is an accepted alias for `list` and was missing from tab-completion, so you only found it if you already knew it existed
- the coding-font download had no timeout, unlike every other fetch in the project, so a stalled connection hung `tstyles font` with nothing to distinguish it from a slow link
- adding a font published as a bare `.ttf` rather than a zip would not have worked. The direct-file branch took its extension from the local download name, which is always `download.bin`, so it could never fire for anything actually fetched. All six catalogue entries are zips, so nothing was broken today -- it was waiting for the first person to add one

- the README told you the picker writes no `settings.json.bak`. It writes one before its first preview, so a crash mid-pick is recoverable -- the README would have talked you out of a recovery path that exists
- the README pointed at `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` for cached background images. That is the pre-0.2.0 location; they have been under `cache\<name>\` since. Anyone looking for their cache, or trying to clear it, was looking in the wrong place
- the README described bundled GIFs as "committed binaries". They are deliberately not committed -- `.gitignore` blocks them and a test fails the build if one becomes tracked -- and live on the `gifs` branch, which the README says correctly three hundred lines earlier
- five style READMEs listed `background.gif` among the folder's files, where a reader will not find it. Each now says where the image actually lives
- `CHANGELOG.md` dated 0.8.3 and 0.8.4 to 2026-08-21; both tags are 2026-08-22

## [0.8.14] - 2026-08-27

### Fixed

- the bootstrap installer did not raise the TLS floor to 1.2, so on stock Windows PowerShell 5.1 -- which is exactly who runs the `iwr | iex` one-liner -- the download could fail outright. On .NET Framework the default `SecurityProtocol` can still omit TLS 1.2 and GitHub refuses anything older, and the failure surfaces as "the underlying connection was closed", which reads like a network fault rather than a protocol one. This project already forced TLS 1.2 in its own CI to bootstrap Pester on the 5.1 leg; it was missing from the one place a user actually runs
- the installer's main download had no timeout, while the far less important update-check call did. A stalled connection left it sitting on "Downloading" indefinitely with no way to tell that apart from a slow link
- the installer left `$ErrorActionPreference` set to `Stop` in your session after it finished. `iwr | iex` runs the whole script body in the *caller's* scope, so every preference it set outlived the install -- and that one turns every later non-terminating error in that session into a terminating one. The preferences it changes, and the TLS floor it raises, are now restored on the way out, including on the failure paths

## [0.8.13] - 2026-08-27

### Fixed

- cancelling `tstyles tune` did not put your colours back on any terminal except Windows Terminal -- the same bug the picker's Esc had before 0.8.9, in the one place it had not been fixed. Esc emitted the OSC reset, which hands colour control to the *terminal's own* defaults; correct on Windows Terminal, where settings.json has just been restored and WT repaints from it, and wrong everywhere else, where the style being tuned was itself only escape sequences. All three exit paths -- Esc, an aborted save, and the safety net -- now re-emit the style you opened the tuner on

### Changed

- the library was split out of `tstyles.ps1` into `lib/`, one file per subsystem: background resolution, the Windows Terminal merge, colour maths, fonts, apply/reset, the tuner, the picker's testable pieces, help, and install/update. `tstyles.ps1` went from 4,105 lines to 1,148 and keeps platform/paths/discovery plus the `tstyles` dispatcher. No behaviour change -- everything is dot-sourced into the same scope it always shared. `CONTRIBUTING.md` now carries a map of where things live

## [0.8.12] - 2026-08-26

### Fixed

- **the picker garbled itself once the style list outgrew the window.** It redraws by parking the cursor at a fixed row and overwriting in place, which only works while the whole frame fits below that row -- draw more rows than the terminal has and it scrolls, the saved home row stops pointing at the top of the menu, and every later redraw lands in the wrong place. With 17 styles the frame is already 23 rows and a stock Terminal.app window is 24, so two more tuned styles was enough to break it. The list now scrolls within the window, keeping the selection visible and showing how many entries are hidden above and below

- the synchronous background fetch could also strand a truncated image in the cache, the same way the picker's prefetch could before 0.8.11. Its `catch` cleans up after a network error, but a Ctrl+C or a killed process never reaches it -- and a file sitting at the cache path is treated as a complete entry by every reader, with nothing to revalidate it. Both paths now download to a `.part` and rename only once the transfer finished

## [0.8.11] - 2026-08-26

### Fixed

- **the picker could cache a truncated background image permanently.** The prefetch job downloads each style's image in the background and is killed with `Stop-Job` the moment you pick -- but it wrote straight to the final cache path, so a half-finished transfer left a partial file exactly where every reader treats it as a valid cache hit. Nothing revalidates a file that exists, so that style kept a corrupt background for good. Downloads now land in a `.part` and are renamed only once complete, which is what the code's own comment already claimed happened
- the picker burned roughly 176 ms of work per second doing nothing, on every terminal except Windows Terminal. Its idle slice runs about 20 times a second and probed the filesystem once per style before checking whether the result would be used at all -- measured at 8.8 ms per full scan over 17 styles. The check now comes first
- the update notice was printed and then immediately wiped. It went to the screen just before the picker's first `Clear-Host`, so it was never readable, while still costing the HTTP check that produced it. It is now held and shown after the picker hands the screen back
- the background prefetch wrote an undated `.no-background` marker, which has read as expired since 0.8.6 -- so its negative caching silently did nothing

- a login bash window printed the style's banner twice and re-emitted its palette twice. `tstyles shell-init` registers the same loader into both `~/.bashrc` and `~/.bash_profile` -- the latter because macOS Terminal.app starts bash as a *login* shell and never reads `.bashrc` -- but the widespread convention is for `.bash_profile` to source `.bashrc`, so both fired. The loader now runs once per shell, with the guard set after the non-interactive check so `ssh host command`, `scp` and `rsync` stay silent as before

## [0.8.10] - 2026-08-26

### Fixed

- the README's "Adding your own style" folder listing never mentioned `prompt.sh`, so a style created from it gives a zsh or bash tab the colors and none of the prompt or banner -- `profile.ps1` is PowerShell-only. (`CONTRIBUTING.md` had the same gap, fixed in 0.8.8.)

- **`tstyles tune` could destroy a style you had already saved.** Choosing "Save as a new name" and typing the name of an existing user style replaced it with no warning at all -- while the *harmless* collision, a name matching a bundled style, did warn. That is backwards: a bundled style is only shadowed and comes back if the user style is deleted, whereas a user style of the same name is overwritten in place. Both cases are now checked, and the destructive one says so
- the font-face knob in `tstyles tune` cycled through the *letters* of a font name on a machine with exactly one monospace font installed, and saved a one-character font face. `return @(...)` does not stop PowerShell unrolling an array on the way to the output stream, so a single-element list arrived at the caller as a string and was indexed per character: the knob read `M`, then `e`, then `n`

- `tstyles random` accepted `-Target`, `-KeepPrompt` and `-NewWindow` and forwarded none of them. `tstyles random -KeepPrompt` replaced the prompt it had just promised to keep, `-Target` applied to the auto-detected Windows Terminal profile rather than the one you named, and `-NewWindow` did nothing at all
- one malformed style stopped `tstyles list` dead. Every style's `scheme.json` was read and parsed with no guard, so a user-authored folder with broken JSON threw mid-loop: a raw .NET exception printed between the rows and every style after it was hidden. A bad folder now costs its own row, marked `(unreadable scheme.json)`, and the rest of the listing prints
- a `current-style.ps1` that will not parse -- a style profile with a syntax error, or a copy interrupted mid-write -- printed a full `ParserError` with a caret diagram into **every new shell tab**. It is now one warning naming the way out (`tstyles reset`). The module import always succeeded either way; this was never the "bricked `tstyles`" it was first reported as

## [0.8.9] - 2026-08-26

### Fixed

- **Esc in the picker did not put your colors back on any terminal except Windows Terminal.** It emitted the OSC reset, which hands color control to the *terminal's own* defaults -- correct on Windows Terminal, where settings.json has just been restored byte-exactly and WT repaints from it, but wrong everywhere else, where the style you arrived with was itself only escape sequences. Cancelling dropped you to a stock palette rather than back to your style. It now re-emits the style you started with, and still resets when there genuinely was no active style
- Ctrl+C, or any error inside the picker, left the last previewed style applied. The cleanup restored the cursor and the window title and nothing else, so on Windows Terminal settings.json kept the preview and elsewhere the preview palette stayed painted. Cancelling by any route now reverts
- `tstyles list`, `tstyles current` and every other read-only subcommand reprinted the whole style banner when run from zsh or bash. The shell wrapper re-sourced the staged prompt after any command that exited 0; the comment above it claimed the exit code prevented exactly that, which it never did. It now re-sources only when the staged prompt actually changed
- every `tstyles` command run from zsh or bash first repainted the terminal with the *currently applied* style and printed its banner, because the generated `tstyles-cli.ps1` imported the module normally and that import re-emits the active style. The shim now suppresses the shell-startup path
- a `%` in a git branch name corrupted the zsh prompt: zsh re-scans command-substitution output for prompt escapes, so a branch called `100%done` rendered as `100`, then the **current directory** (`%d`), then `one` -- and a branch containing `%(` swallowed the rest of the prompt as an unterminated ternary
- the git-branch segment printed its own color escapes as literal `\[\033[38;2;...m\]` text in bash. bash decodes PS1 backslash escapes once, when it parses the prompt, and only then performs command substitution -- so colors produced inside `$(...)` arrive too late to be decoded. There is now a substitution-safe colour helper that emits the bytes bash would have decoded to
- an apostrophe anywhere in the module path produced a `tstyles-cli.ps1` that could not parse -- the path was interpolated into a single-quoted string with no escaping -- so every `tstyles` call from zsh died on a syntax error while the staging step reported success
- **`tstyles uninstall` never undid `tstyles shell-init`.** It stripped only the PowerShell `$PROFILE` loader, so afterwards every new zsh/bash tab still repainted the palette, set the window title, printed the banner and took over the prompt. The documented way back was already dead by then: uninstall deletes `TerminalStyles.psd1`, which is the exact path baked into the generated shim, so the shell's own `tstyles` could no longer load the module and hand-editing `~/.zshrc` was the only recovery. Uninstall now strips the shell loader and clears the staged state, and counts `terminals.ps1` and the shell runtime as install-managed -- leaving those behind kept an "uninstalled" copy fully working
- one unwritable rc file took down the whole of `shell-init` / `shell-remove` with a raw .NET exception, after some files had already been written and before anything was reported. Each file now fails on its own and is reported as `failed`

## [0.8.8] - 2026-08-25

### Fixed

- **`tstyles register` did nothing on macOS and Linux.** It probed only `pwsh.exe` and `powershell.exe`; off Windows the binary is `pwsh`, with no extension, and Windows PowerShell does not exist at all. So it printed "Neither pwsh.exe nor powershell.exe was found on PATH. Nothing to do." and did exactly that -- while the README tells macOS users to run it. `tstyles uninstall` shared the probe and so could not strip the loader either. Both on the platforms 0.8.0 added support for
- the bootstrap installer downloaded, installed, and *then* failed on macOS and Linux, throwing "Neither pwsh.exe nor powershell.exe was found on PATH" after the files were already in place -- leaving you installed with no loader and a stack trace. It now finds `pwsh`, and if it genuinely finds no engine it prints the one line you need to add to your profile instead of throwing
- `shell/appleterminal.js` had two guards that guarded nothing, each producing the one shape the file's own header warns Terminal rejects as a corrupt profile while naming no key. A malformed hex reached `parseInt`, which yields `NaN`; `NSColor` accepts NaN components without complaint, so the archive carried `NSRGB = "nan nan nan"` and the caller's "skip a bad color" catch never fired because nothing threw. And the missing-image check read `!bookmark`, but a nil ObjC return arrives in JXA as a *truthy* wrapper -- so a missing background produced a `BackgroundImageBookmark` archiving nothing. Colors are now validated before parsing, and the nil check uses `isNil()`
- `CONTRIBUTING.md` described a theme folder as four files and never mentioned `prompt.sh` -- which `tests/Shell-Prompt.Tests.ps1` requires of every folder under `styles/`, rendering it in real zsh and bash and checking each escape sequence is marked non-printing. All sixteen bundled themes ship one, so the gap was invisible to the maintainer and hit only newcomers: following the contributing guide exactly turned the Linux and macOS CI legs red on a first PR. The folder layout, the submission checklist and a pointer to the smallest existing example are now all in the guide
- `SECURITY.md` listed `0.6.x` as the supported version, ten releases out of date, and named GitHub private vulnerability reporting as the *preferred* channel while the repository has it disabled -- so it sent reporters to a Security tab with no "Report a vulnerability" button. It now tracks the shipped minor series and gives the channel that actually exists

### Added

- `tests/Contributing-MatchesCI.Tests.ps1`: docs drift silently because nothing executes them, so the suite now asserts that `CONTRIBUTING.md` documents the files CI enforces, that the examples it points at exist, and that `SECURITY.md`'s supported-version table matches the manifest

## [0.8.7] - 2026-08-25

### Fixed

- **`apply.ps1` deleted a background image you had set yourself.** The scriptable entry point carried copy-pasted forks of five library functions, each with a "keep in sync" note, and two had drifted. Its merge stripped `backgroundImage` and friends whenever the style resolved no background of its own -- with no check of whose background it was -- so applying a style to a profile carrying your own image, or Windows Terminal's `desktopWallpaper`, silently removed it. The module has always decided by ownership and left yours alone; `tests/Background-Carryover.Tests.ps1` pins exactly that, and only ever covered the module
- `apply.ps1` wrote its background cache into the **style** directory rather than the data root, in the pre-0.2.0 layout, and swallowed the failure. That directory belongs to the installed module on a PSGallery install. It also wrote the old undated `.no-background` marker, which 0.8.6 reads as expired -- so the script and the module had diverged on both where the cache lives and what a marker means
- `apply.ps1` wrote `current-style.ps1` beside itself instead of into the data root, which only coincide for bootstrap installs; on a PSGallery install the module then looked for it somewhere else entirely

### Changed

- `apply.ps1` now dot-sources the library instead of duplicating it, dropping from 446 lines to 221 with only its own interactive prompt left. Parity tests could only ever catch drift in functions someone had written one for, and neither function that actually drifted had one; there is now a single implementation, and the module's own tests cover it. As a side effect `apply.ps1` sees the same styles `tstyles list` does, including tuned and user-authored ones, rather than only those in its own folder

## [0.8.6] - 2026-08-25

### Fixed

- **the bootstrap installer destroyed your data on every update.** `install.ps1` removed the install directory outright -- and that directory *is* the module's writable data root -- then copied a hand-listed subset back. Everything off the list died: the cached background images (tens of megabytes, re-fetched from the `gifs` branch one 10-second request at a time), every style saved by `tstyles tune`, the active-style record, the staged zsh/bash runtime, the font cache and the generated Terminal.app profiles. The one thing it *tried* to save it looked for at `styles/<name>/background.*`, the pre-0.2.0 cache location, so on any install since 0.2.0 it preserved nothing at all; its restore path also hardcoded a backslash separator and so could not have run off Windows. The installer now removes only the entries the downloaded release actually ships and leaves everything else alone. `styles/` is merged rather than replaced, because the README documents dropping a folder named after a bundled theme to override it, and on a bootstrap install that override lives in the same directory as the theme. This affects `tstyles update` for bootstrap installs; PSGallery installs were never touched by it
- `tstyles uninstall -DeleteData` could not be run at all. The switch existed on the uninstall function and was documented in `tstyles help` and three places in the README, but the `tstyles` dispatcher had no such parameter, so PowerShell rejected the command outright. It was also the only documented way to clear a stuck background cache
- **a mistyped `-Target` reported success and silently deleted your settings.json comments.** Applying to a Windows Terminal profile that does not exist left the settings untouched by design, but the apply wrote the file and printed "Style applied" in green regardless. The write was not a no-op: it re-serializes the parsed object, and parsing strips every `//` comment on the way in. A typo in a profile name irreversibly erased hand-written comments while claiming to have worked. The profile name is now checked before anything is written -- before even the rolling backup -- and an unknown one lists the profiles that do exist
- a style's background could be lost permanently by one apply made while offline. Any fetch failure -- a real 404, a DNS failure, four 10-second timeouts -- wrote the same undated `.no-background` marker, and nothing ever deleted it. The two are now told apart: a 404 from the server means the asset is genuinely absent and is remembered for 30 days (the `gifs` branch is updated independently of releases, so a style can gain one later), while an unreachable network is remembered for an hour -- long enough that repeated applies do not each pay four timeouts, short enough to heal itself on reconnect. Markers written by earlier versions are treated as expired, so an already-stuck cache recovers on the next apply
- applying a style that ships no `theme.json` left an unreferenced color scheme in `settings.json`. A scheme is only reachable through a profile's `colorScheme` key, and that key lives in `theme.json` -- so writing the scheme first and only then discovering there was no theme to write left a scheme nothing points at. `tstyles reset` removes the scheme named by the profile it is resetting, so an unreferenced one could never be cleaned up and a fresh one accumulated on every apply. `theme.json` is optional by contract, and the README documents it that way for user-authored styles. This was the same failure an existing guard already prevented for a mistyped `-Target`, reachable through the door beside it
- switching to a style whose `theme.json` does not mention background fields left the previous style's image showing behind the new palette. Clearing a background TerminalStyles itself installed was driven by the incoming theme's own properties, so it only happened for styles that named those fields. All sixteen bundled themes declare the placeholder, which is why this never showed up with them -- but a style that ships no background has no reason to name background fields at all. The clear now depends on what is on the profile, not on what the incoming theme happens to mention

## [0.8.5] - 2026-08-25

### Fixed

- choosing a style in the interactive picker applied its colors but not its prompt or banner, on every terminal except Windows Terminal. The style's `profile.ps1` was copied into place and then not dot-sourced, so the prompt only appeared in the next tab you opened -- while `tstyles <name>` on the very same terminal painted it immediately. The live-reload was gated on a Windows Terminal check left over from before there was any non-Windows-Terminal path for it to be wrong about
- the capability table promised things no code delivered. iTerm2 was marked as supporting background images, fonts, opacity and cursor shapes on the strength of Dynamic Profiles, and Ghostty / WezTerm / kitty / Alacritty on the strength of their own config files -- but nothing in this module has ever written a config for any of them. Only Windows Terminal's `settings.json` and Terminal.app's `.terminal` profile have writers. On iTerm2 the effect was the failure the table exists to prevent: applying a style with a background reported success, painted no image, said nothing about why, and still had the picker prefetch megabytes of GIFs that could never be drawn. It now reports "can't show: background image" and skips the download. The live OSC retint -- the whole picker preview -- is unchanged on every terminal
- Terminal.app was likewise marked as supporting fonts, opacity and cursor shapes. The profile this module builds carries colors and a background image and nothing else, so a style's font was dropped in transit with no notice. Terminal.app would honour a font in a profile; this is a gap in the writer, not in the terminal
- the interactive picker never staged the zsh/bash side of the style you chose. It recorded the name, so `tstyles current` and the `*` in `tstyles list` were right, and it retinted the window you were sitting in -- but `current-style.osc` and `current-prompt.sh` stayed on the PREVIOUS style, so every zsh or bash tab you opened afterwards came up in the old palette and the old banner. Nothing errored; the next tab was just quietly wrong. `tstyles <name>` staged correctly all along, which is what made it hard to spot
- the picker ignored `-KeepPrompt`. It accepted the flag and then copied the style's `profile.ps1` over `current-style.ps1` regardless, which is exactly what installs the style's prompt -- so `tstyles -KeepPrompt` replaced the Oh My Posh / Starship prompt it had just promised to leave alone. The direct-apply path always honoured it
- `tstyles font <name>` installed the font and then reported failure, on every terminal except Windows Terminal. It went looking for a `settings.json` that cannot exist off Windows Terminal and printed "Could not locate Windows Terminal settings.json." in red -- after an install that had actually succeeded. Applying a font means writing it into a profile and no escape sequence carries one, so off Windows Terminal the install IS the whole job; it now says so, and names the terminal whose preferences will list the new font. 0.8.4 fixed this same class of message for `tstyles tune` and left `font` behind
- an apply outside Windows Terminal resolved the style's background image twice, on the hot path, after "Style applied" had already printed. One of the two calls was the left operand of an `-and` whose right side would have short-circuited it away. Resolving a background can make four serial 10-second HTTP attempts against the `gifs` branch, so a style with nothing cached could sit on the network for up to 80 seconds for a result that was then discarded. It now resolves at most once, and not at all for a style that ships no `theme.json`
- re-tuning a style you had already saved with **Overwrite** made `tstyles tune` copy files onto themselves, because the base and the destination were the same directory. `prompt.sh` produced a red "Cannot overwrite the item with itself" at save time -- after you had committed to the save -- and `profile.ps1` grew another `# tstyles-tuned:` line on every repeat
- the tuner told you something untrue outside Windows Terminal: that opacity and font were "saved with the style, but only a new window shows them". No terminal there can show either. The `.terminal` profile carries colors and a background image and nothing else, and no escape sequence carries a font or an opacity, so the advice sent you to open a window and compare an unchanged font against the screenshot. Both the tuner and `tstyles help tune` now say they are recorded and not shown
- a failed apply at the end of `tstyles tune` skipped the tuner's own cleanup. `Apply-StyleDirect` reports every one of its give-up paths with `Write-Error`, which does not throw, so the "we applied it" flag was set whether or not anything had been applied -- and the `finally` block then skipped the OSC reset, leaving the tuner's preview colors painted over a settings.json that had already been restored

### Added

- `scripts/demo.ps1` and `docs/DEMO.md`: a harness for recording a short demo of live theme switching. It snapshots style state, parks personal tuned styles so the picker lists only the bundled ones, and either prints a cue card or drives the real picker through a pty with fixed timings so takes are comparable. `-Restore` puts everything back

## [0.8.4] - 2026-08-22

### Fixed

- background images did not appear on Terminal.app at all, which made 0.8.2's headline feature look like it did nothing. Terminal.app renders a still image but not an animated GIF, and every bundled background is a GIF -- a profile pointing at one gets a blank background with no error logged anywhere. The first frame is now extracted to a PNG (via `sips`) and cached beside the original, so Windows Terminal animates and Terminal.app shows a still
- a style saved by `tstyles tune` carried no `prompt.sh`, so tuning anything left a zsh or bash user with the style's colors and none of its prompt or banner. Shell prompts arrived in 0.8.2 and `Save-TunedStyle` was never taught to copy one

### Added

- `tstyles tune` now runs outside Windows Terminal. It previously refused, on the grounds that opacity and font need a config file the terminal does not expose -- true when that message was written, and no longer true once 0.8.2 started generating `.terminal` profiles. Brightness and saturation preview live over OSC exactly as on Windows Terminal; opacity and font are saved with the style and take effect when it is applied to a new window. The tuner says which knobs will not move before it takes over the screen, so the stillness is not read as a bug

## [0.8.3] - 2026-08-22

### Fixed

- the macOS install instructions named a Homebrew cask that no longer exists. `brew install --cask powershell` fails outright with "No Cask with this name exists" -- PowerShell moved to a Homebrew *formula*, so the command is `brew install powershell`. It was the first step a new macOS user followed, in the README and in the "PowerShell not found" message the zsh/bash wrapper prints

## [0.8.2] - 2026-08-21

### Added

- **background images on Terminal.app.** `tstyles <name> -NewWindow` opens a window carrying the style's background image along with its palette and prompt. Terminal.app does support background images -- 0.8.0 and 0.8.1 said it did not, which was simply wrong -- but only through a profile, and a profile only takes effect on a new window, so there is no way to push an image into the window you are already sitting in. The generated profile is kept under `~/Library/Application Support/TerminalStyles/profiles/` and can be opened from Finder or set as your Terminal.app default
- `shell/appleterminal.js`, a JXA helper that builds the Cocoa objects a `.terminal` profile needs. Terminal stores each color as an `NSKeyedArchiver` archive of an `NSColor`, and the background image as an archive of an `NSMutableData` holding a security-scoped bookmark. Hand Terminal a bare bookmark, or a color that is not archived, and it rejects the whole profile as "corrupt" without naming the offending key

### Fixed

- the capability table claimed Terminal.app could not show a background image, so styles that ship one reported it as unsupported. It can; that entry, the runtime message, and the README table were all wrong
- `tstyles <name>` reported "Style applied" even when it had painted nothing. The emit function returned no value and the caller reported the terminal's *capability* rather than the actual outcome, so anything running tstyles through a pipe or with stdout redirected saw a success message and an unchanged window. It now says the colors could not be applied and why

## [0.8.1] - 2026-08-21

### Fixed

- the interactive picker crashed the moment it opened on any terminal that is not Windows Terminal: `Cannot index into a null array` at the first paint. The initial preview indexed the per-keystroke OSC cache, which is built about fifty lines further down and was still `$null`. The starting style's packet is now built directly from the loaded scheme. This shipped in 0.8.0 with all four CI legs green -- the picker is a keyboard UI, so its non-Windows branch had no automated coverage at all
- the picker downloaded a background image for every style even on terminals that cannot display one, showing `...fetching background` beside each entry while pulling megabytes from the `gifs` branch for images that would never be drawn. Prefetch is now skipped entirely when the host terminal has no background-image capability
- the picker header read `Choose a style for ''` off Windows Terminal, where there is no profile to name. It now names the terminal being styled -- `Choose a style for Terminal.app`
- running `tstyles` with stdin redirected (a pipe, a shell that detaches stdin, a CI step) drew the whole menu and then died on `[Console]::KeyAvailable` with "Cannot see if a key has been pressed ... Try Console.In.Peek". It now detects that up front, explains that the picker needs an interactive terminal, points at `tstyles <name>`, and returns without clearing the screen
- `terminals.ps1` and `shell/` were missing from the publish allowlist. Both are new in 0.8.0 and both are load-bearing -- `tstyles.ps1` dot-sources `terminals.ps1` -- so this was caught during 0.8.0's preflight, but the allowlist is now verified by importing the staged package standalone rather than by eye

## [0.8.0] - 2026-08-21

### Added

- **macOS and Linux support.** A style now applies outside Windows Terminal. Colors go out as OSC escape sequences — which Terminal.app, iTerm2, Ghostty, WezTerm, kitty and Alacritty all understand — so `tstyles <name>` retints the window immediately, and the choice is recorded so later tabs come up styled too. Applying a style reports what the host terminal cannot show (Terminal.app has no background images, nothing but Windows Terminal has tab accent colors) rather than dropping those fields silently
- **zsh and bash styling.** `tstyles shell-init` registers a loader in `~/.zshrc`, `~/.bashrc` and `~/.bash_profile`, so a non-PowerShell shell comes up with the style's palette, window title, banner and prompt — and gets a `tstyles` command of its own. Each style ships a `prompt.sh` ported from its `profile.ps1`. The loader reads only precomputed files, so it never starts PowerShell at shell startup, and it emits nothing in a non-interactive shell (`ssh host command`, `scp` and `rsync` are unaffected). `tstyles shell-remove` reverses it. PSReadLine's syntax-highlighting colors have no zsh/bash equivalent and are not ported
- `terminals.ps1`: terminal detection and a capability model. `Get-TerminalKind` identifies the host from its environment markers; `Get-TerminalCapability` reports which style fields it can honour, so callers degrade against a capability record instead of writing settings nothing will read
- CI now runs the suite on macOS and Ubuntu alongside the two Windows legs

### Fixed

- the module could not be imported at all off Windows: the per-user data dir was built with `Join-Path $env:LOCALAPPDATA`, and that variable is null on macOS/Linux, so loading threw before defining a single function. State now resolves per platform — `%LOCALAPPDATA%` on Windows (unchanged, so existing installs are untouched), `~/Library/Application Support` on macOS, `$XDG_DATA_HOME` on Linux
- five path joins embedded a literal `\` separator (`"cache\$name"`). A backslash is an ordinary filename character off Windows, so these produced single files with backslashes in their names instead of the intended subdirectories
- font detection reported every font as missing on macOS/Linux. Both the installed-font check and the tuner's font list enumerated through `System.Drawing`, which is Windows-only from .NET 6 onward -- constructing an `InstalledFontCollection` throws there, and the error was caught into an empty list. `tstyles font` therefore listed the whole catalogue as installable even straight after installing one, and the tuner had no fonts to cycle. Off Windows the font directories are scanned instead, and families are matched on a normalized key so a family recovered from `JetBrainsMono-Regular.ttf` matches "JetBrains Mono"
- `tstyles tune` failed off Windows Terminal with "Could not locate Windows Terminal settings.json" -- an error about a file the user was never going to have. Tuning adjusts opacity and font as well as color, none of which can be sent as an escape sequence, so it now says plainly that it needs Windows Terminal and points at `tstyles <name>` instead
- importing the module wrote the applied style's OSC palette, and its banner, into **redirected** output. A `$PROFILE` that imports TerminalStyles would prepend ~280 bytes of escape sequences plus a banner to the output of any `pwsh -c '...' > file.txt`, quietly corrupting it. Both are now suppressed when stdout is not a terminal

## [0.7.1] - 2026-08-07

### Fixed

- switching to a style that ships no background image no longer leaves the previous style's background showing through it. Every `theme.json` declares the background fields, but a style with nothing to put there used to skip them entirely — so applying `sober` after `forest` kept forest's GIF behind sober's colors, in the picker and on a direct apply alike. A background TerminalStyles installed is now cleared when the next style has none; one you set yourself (your own image, or Windows Terminal's `desktopWallpaper`) is still left alone

## [0.7.0] - 2026-08-07

### Added

- `tstyles font` — install curated coding fonts (JetBrains Mono, Fira Code, Cascadia Code, Hack, Source Code Pro, IBM Plex Mono) from their official sources (SHA-256 verified) and apply them to the active profile. A one-time opt-in prompt offers to install the set on first run. Installed fonts appear automatically in `tstyles tune`.

### Fixed

- the published PowerShell Gallery package no longer carries background-image binaries. The publish script copied the whole `styles/` tree from the working directory, so any background GIF the release machine had lazily fetched got swept into the package — making the upload both bloated and dependent on which themes that machine happened to have previewed. Staging is now driven by `git ls-files`, so the package is exactly the committed tree and byte-identical from any checkout (this release: 252 KB instead of 3.0 MB)

## [0.6.3] - 2026-06-24

### Changed

- PowerShell Gallery listing metadata refreshed for discoverability: a clearer, keyword-rich description and an expanded tag set (adds `Terminal`, `ColorScheme`, `Cursor`, `Background`, `Customization`, `Console`, `Dotfiles`, plus the `PSEdition_Core` / `PSEdition_Desktop` / `Windows` platform tags so the package shows up in the Gallery's search filters)

### Fixed

- on PowerShell 7, a direct style apply (`tstyles <name>`) or the picker/tuner could leave a half-written or empty Windows Terminal settings.json if interrupted mid-write — the atomic temp-file replace silently degraded to a non-atomic in-place write because `File.Replace`'s backup argument was a bare `$null` (which PS7 coerces to an empty string and rejects). Both settings writers now pass `[NullString]::Value`, so the atomic same-volume rename runs as intended

## [0.6.2] - 2026-06-13

### Changed

- settings.json writes are now atomic (temp file + replace), and the picker/tuner roll a settings.json.bak before previewing so a hard kill is recoverable
- when both Windows Terminal Stable and Preview are installed, TerminalStyles now edits the settings file of the build hosting the current session instead of always preferring Stable
- six themes' muddy accent colors (neon-rain, umbrella, gitbash, rain, snowday, golden-forest) were lifted to a 3:1 contrast floor for legible syntax and prompt tokens, preserving each theme's hue identity
- background image binaries (~9.9 MB) removed from the main branch — clones are lighter and backgrounds are fetched on demand

### Fixed

- crash on Windows PowerShell 5.1 when settings.json contains JSONC comments or trailing commas
- background images never appeared on PowerShell Gallery installs — the prefetcher wrote to the module directory while readers looked in the local cache, leaving styles stuck on "fetching"
- cancelling the picker or tuner (Esc) no longer leaves live preview colors applied on top of your reverted settings
- applying a style to a mistyped profile name no longer leaves an orphaned color scheme in settings.json
- re-tuning a style whose base style was deleted now keeps its saved opacity and font instead of resetting them to defaults
- re-tuning a style saved with Overwrite no longer re-applies its adjustments on top of the already-baked colors (color drift on every re-tune)
- deeply nested settings.json structures are no longer silently corrupted on save

## [0.6.1] - 2026-05-30

### Changed

- the `tstyles tune` font picker now cycles through every installed monospace font (curated favorites first) instead of a fixed allowlist, so your own coding fonts show up automatically

## [0.6.0] - 2026-05-30

### Added

- `tstyles reset` to revert a Windows Terminal profile to its unstyled state

## [0.5.0] - 2026-05-30

### Added

- `-KeepPrompt` flag (`tstyles <name> -KeepPrompt`) applies a style's colors, font, and background while keeping your existing prompt

### Changed

- apply.ps1's `-NoProfile` switch renamed to `-KeepPrompt` (the old name still works as an alias)

## [0.4.2] - 2026-05-29

### Changed

- a style's themed prompt and banner now load only inside Windows Terminal — other hosts (VS Code terminal, plain consoles) keep their own prompt

## [0.4.1] - 2026-05-29

### Fixed

- user-registered and tuned styles now appear in the interactive picker, not just via direct apply

## [0.4.0] - 2026-05-29

### Added

- `tstyles help` with a command overview and per-command detail
- a `tstyles help` hint in the picker header

### Changed

- an unknown argument now shows help instead of silently opening the picker

## [0.3.0] - 2026-05-29

### Added

- `tstyles tune` — interactive live theme tuning (brightness/saturation color adjustments, font cycling from a curated monospace list, opacity) with instant preview
- tuned styles can be saved as new styles and inherit their base style's background

### Fixed

- styles saved via the tuner's Save-As are now correctly recognized in active-style detection

## [0.2.2] - 2026-05-27

### Added

- `tstyles register` to install a custom style folder into the user styles directory, with tab completion

## [0.2.1] - 2026-05-27

### Added

- a user styles directory in the data root that survives module updates; user styles with the same name win over bundled ones

### Fixed

- installer output rendered as `?` on some consoles — output is now ASCII-only with UTF-8 console handling for Windows PowerShell 5.1
- install failures from temp ZIP file lock collisions (download path is now uniquely named)

## [0.2.0] - 2026-05-27

### Added

- PowerShell Gallery is now the primary install channel (`Install-PSResource TerminalStyles`)
- `tstyles uninstall -DeleteData` to also remove local TerminalStyles data

### Changed

- `tstyles update` and `tstyles uninstall` delegate to PSResourceGet for Gallery installs
- user state moved to a data root separate from the module install, so module updates never touch your data
- the GitHub update check is skipped for Gallery installs (PSResourceGet handles updates)

## [0.1.0] - 2026-05-27

### Added

- 16 bundled themes — umbrella, kitty, golden-forest, ex-machina, sober, eva, rain, gitbash, forest, neon-rain, lain, snowday, tombraider, garden-rain, marquee, and halo
- interactive `tstyles` picker with live preview — instant color preview via OSC escapes, per-theme swatches, flicker-free in-place redraw, live tab title/color preview, and the cursor lands on the currently active style
- `tstyles` subcommands — list, current (with inline swatch), random, direct apply (`tstyles <name>`), and uninstall — all with tab completion
- per-style background images that apply automatically with a style, lazily fetched from a dedicated `gifs` branch with prefetching and a loading indicator
- support for both PowerShell 7 and Windows PowerShell 5.1
- one-line installer with a polished banner/step/ready-panel flow and same-tab handoff (no new tab needed after install)
- update check (throttled to once per day) and a `tstyles update` command
- rolling settings.json.bak backup before any direct (non-picker) style apply, with a documented one-liner restore
- packaged as a proper PowerShell module (TerminalStyles.psd1 manifest + TerminalStyles.psm1)

### Changed

- themes live-reload on confirm — colors and tab title update without opening a new tab

[Unreleased]: https://github.com/fcreme/TerminalStyles/compare/v0.8.18...HEAD
[0.8.18]: https://github.com/fcreme/TerminalStyles/compare/v0.8.17...v0.8.18
[0.8.17]: https://github.com/fcreme/TerminalStyles/compare/v0.8.16...v0.8.17
[0.8.16]: https://github.com/fcreme/TerminalStyles/compare/v0.8.15...v0.8.16
[0.8.15]: https://github.com/fcreme/TerminalStyles/compare/v0.8.14...v0.8.15
[0.8.14]: https://github.com/fcreme/TerminalStyles/compare/v0.8.13...v0.8.14
[0.8.13]: https://github.com/fcreme/TerminalStyles/compare/v0.8.12...v0.8.13
[0.8.12]: https://github.com/fcreme/TerminalStyles/compare/v0.8.11...v0.8.12
[0.8.11]: https://github.com/fcreme/TerminalStyles/compare/v0.8.10...v0.8.11
[0.8.10]: https://github.com/fcreme/TerminalStyles/compare/v0.8.9...v0.8.10
[0.8.9]: https://github.com/fcreme/TerminalStyles/compare/v0.8.8...v0.8.9
[0.8.8]: https://github.com/fcreme/TerminalStyles/compare/v0.8.7...v0.8.8
[0.8.7]: https://github.com/fcreme/TerminalStyles/compare/v0.8.6...v0.8.7
[0.8.6]: https://github.com/fcreme/TerminalStyles/compare/v0.8.5...v0.8.6
[0.8.5]: https://github.com/fcreme/TerminalStyles/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/fcreme/TerminalStyles/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/fcreme/TerminalStyles/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/fcreme/TerminalStyles/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/fcreme/TerminalStyles/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/fcreme/TerminalStyles/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/fcreme/TerminalStyles/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/fcreme/TerminalStyles/compare/v0.6.3...v0.7.0
[0.6.3]: https://github.com/fcreme/TerminalStyles/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/fcreme/TerminalStyles/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/fcreme/TerminalStyles/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/fcreme/TerminalStyles/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/fcreme/TerminalStyles/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/fcreme/TerminalStyles/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/fcreme/TerminalStyles/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/fcreme/TerminalStyles/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/fcreme/TerminalStyles/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/fcreme/TerminalStyles/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/fcreme/TerminalStyles/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/fcreme/TerminalStyles/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fcreme/TerminalStyles/releases/tag/v0.1.0
