# Changelog

All notable changes to TerminalStyles are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tstyles font` — install curated coding fonts (JetBrains Mono, Fira Code, Cascadia Code, Hack, Source Code Pro, IBM Plex Mono) from their official sources (SHA-256 verified) and apply them to the active profile. A one-time opt-in prompt offers to install the set on first run. Installed fonts appear automatically in `tstyles tune`.

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

[Unreleased]: https://github.com/fcreme/TerminalStyles/compare/v0.6.3...HEAD
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
