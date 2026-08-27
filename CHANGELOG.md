# Changelog

All notable changes to TerminalStyles are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `docs/RELEASING.md`'s post-publish smoke test told the maintainer to run `Get-Command -Module TerminalStyles` and expect `tstyles` in the output. Bare `Get-Command -Module` lists functions only, so the alias never appeared -- every release since it existed looked like a failed publish at the final verification step. `-CommandType Function,Alias` is what shows it

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

[Unreleased]: https://github.com/fcreme/TerminalStyles/compare/v0.8.16...HEAD
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
