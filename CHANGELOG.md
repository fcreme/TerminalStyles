# Changelog

All notable changes to TerminalStyles are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- choosing a style in the interactive picker applied its colors but not its prompt or banner, on every terminal except Windows Terminal. The style's `profile.ps1` was copied into place and then not dot-sourced, so the prompt only appeared in the next tab you opened -- while `tstyles <name>` on the very same terminal painted it immediately. The live-reload was gated on a Windows Terminal check left over from before there was any non-Windows-Terminal path for it to be wrong about
- the capability table promised things no code delivered. iTerm2 was marked as supporting background images, fonts, opacity and cursor shapes on the strength of Dynamic Profiles, and Ghostty / WezTerm / kitty / Alacritty on the strength of their own config files -- but nothing in this module has ever written a config for any of them. Only Windows Terminal's `settings.json` and Terminal.app's `.terminal` profile have writers. On iTerm2 the effect was the failure the table exists to prevent: applying a style with a background reported success, painted no image, said nothing about why, and still had the picker prefetch megabytes of GIFs that could never be drawn. It now reports "can't show: background image" and skips the download. The live OSC retint -- the whole picker preview -- is unchanged on every terminal
- Terminal.app was likewise marked as supporting fonts, opacity and cursor shapes. The profile this module builds carries colors and a background image and nothing else, so a style's font was dropped in transit with no notice. Terminal.app would honour a font in a profile; this is a gap in the writer, not in the terminal

### Added

- `scripts/demo.ps1` and `docs/DEMO.md`: a harness for recording a short demo of live theme switching. It snapshots style state, parks personal tuned styles so the picker lists only the bundled ones, and either prints a cue card or drives the real picker through a pty with fixed timings so takes are comparable. `-Restore` puts everything back

## [0.8.4] - 2026-08-21

### Fixed

- background images did not appear on Terminal.app at all, which made 0.8.2's headline feature look like it did nothing. Terminal.app renders a still image but not an animated GIF, and every bundled background is a GIF -- a profile pointing at one gets a blank background with no error logged anywhere. The first frame is now extracted to a PNG (via `sips`) and cached beside the original, so Windows Terminal animates and Terminal.app shows a still
- a style saved by `tstyles tune` carried no `prompt.sh`, so tuning anything left a zsh or bash user with the style's colors and none of its prompt or banner. Shell prompts arrived in 0.8.2 and `Save-TunedStyle` was never taught to copy one

### Added

- `tstyles tune` now runs outside Windows Terminal. It previously refused, on the grounds that opacity and font need a config file the terminal does not expose -- true when that message was written, and no longer true once 0.8.2 started generating `.terminal` profiles. Brightness and saturation preview live over OSC exactly as on Windows Terminal; opacity and font are saved with the style and take effect when it is applied to a new window. The tuner says which knobs will not move before it takes over the screen, so the stillness is not read as a bug

## [0.8.3] - 2026-08-21

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

[Unreleased]: https://github.com/fcreme/TerminalStyles/compare/v0.8.4...HEAD
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
