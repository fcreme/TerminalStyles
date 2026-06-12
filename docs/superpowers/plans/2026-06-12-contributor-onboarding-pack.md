# Contributor Onboarding Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the contributor-facing layer (CONTRIBUTING, issue/PR templates, CoC, SECURITY, CHANGELOG, README links) and seed the live GitHub repo (description, topics, `theme` label, private vulnerability reporting, 11 issues) so visitors can contribute without asking questions first.

**Architecture:** Pure docs + GitHub-metadata change — no PowerShell code paths are touched. Six file-creation tasks commit to `main` one logical unit at a time; the final two tasks are live `gh` changes that REQUIRE showing the user the exact commands and getting confirmation first. Spec: `docs/superpowers/specs/2026-06-12-contributor-onboarding-pack-design.md`; issue bodies live verbatim in `docs/superpowers/specs/2026-06-12-contributor-onboarding-pack-issue-drafts.md` (the "companion file").

**Tech Stack:** Markdown, GitHub issue-forms YAML, `gh` CLI, Pester (verification only).

---

### Task 1: CHANGELOG.md + changelog step in RELEASING.md

**Files:**
- Create: `CHANGELOG.md`
- Modify: `docs/RELEASING.md:26-40` (Release steps) and the six step numbers after it

- [ ] **Step 1: Create `CHANGELOG.md`** with exactly this content:

````markdown
# Changelog

All notable changes to TerminalStyles are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/fcreme/TerminalStyles/compare/v0.6.1...HEAD
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
````

- [ ] **Step 2: Add the CHANGELOG step to `docs/RELEASING.md`.** Edit (exact match):

Old:
```markdown
2. **Update `PrivateData.PSData.ReleaseNotes`** in `TerminalStyles.psd1`
   with a 1-3 line summary of what's in this release. PSGallery shows
   this on the version's page.
```

New:
```markdown
2. **Update `PrivateData.PSData.ReleaseNotes`** in `TerminalStyles.psd1`
   with a 1-3 line summary of what's in this release. PSGallery shows
   this on the version's page.

3. **Update `CHANGELOG.md`**: retitle `## [Unreleased]` to
   `## [<new-version>] - <YYYY-MM-DD>`, start a fresh empty
   `## [Unreleased]` above it, and update the reference links at the
   bottom (point `[Unreleased]` at `v<new-version>...HEAD`, add a
   compare link for the new version).
```

- [ ] **Step 3: Renumber the six following steps in `docs/RELEASING.md`** with six exact-match edits (each old string is unique because it includes the step title):
  - `3. **Commit the version bump**` → `4. **Commit the version bump**`
  - `4. **Dry-run the publish script**` → `5. **Dry-run the publish script**`
  - `5. **Run the real publish.**` → `6. **Run the real publish.**`
  - `6. **Tag the release**` → `7. **Tag the release**`
  - `7. **Verify** within` → `8. **Verify** within`
  - `8. **Smoke-test the install**` → `9. **Smoke-test the install**`

- [ ] **Step 4: Verify** the renumbering is sequential 1–9 with no duplicates:

Run: `Select-String -Path docs\RELEASING.md -Pattern '^\d+\. \*\*'`
Expected: nine lines numbered 1. through 9. in order.

- [ ] **Step 5: Commit**

```powershell
git add CHANGELOG.md docs/RELEASING.md
git commit -m "docs: add retroactive CHANGELOG + changelog step in release flow"
```

---

### Task 2: CODE_OF_CONDUCT.md + SECURITY.md

**Files:**
- Create: `CODE_OF_CONDUCT.md`
- Create: `SECURITY.md`

- [ ] **Step 1: Download the canonical Contributor Covenant 2.1 text:**

Run:
```powershell
iwr -useb https://www.contributor-covenant.org/version/2/1/code_of_conduct/code_of_conduct.md -OutFile CODE_OF_CONDUCT.md
```
Expected: file created, starts with `# Contributor Covenant Code of Conduct`. (Fallback if the URL is down: `https://raw.githubusercontent.com/EthicalSource/contributor_covenant/release/content/version/2/1/code_of_conduct.md` — strip the YAML/Hugo front matter between the leading `---` lines if present.)

- [ ] **Step 2: Fill in the enforcement contact.** Edit `CODE_OF_CONDUCT.md` (exact match): `[INSERT CONTACT METHOD]` → `felipecremerius1@gmail.com`.

- [ ] **Step 3: Verify no placeholders remain:**

Run: `Select-String -Path CODE_OF_CONDUCT.md -Pattern 'INSERT'`
Expected: no output. Also confirm the attribution footer ("adapted from the Contributor Covenant, version 2.1") survived the download.

- [ ] **Step 4: Create `SECURITY.md`** with exactly this content:

````markdown
# Security Policy

## Supported versions

| Version                | Supported                              |
| ---------------------- | -------------------------------------- |
| 0.6.x (latest release) | ✅                                      |
| older                  | ❌ — update first (`tstyles update`)    |

## Reporting a vulnerability

Please report vulnerabilities privately — do not open a public issue.

- **Preferred:** GitHub private vulnerability reporting — open the
  [Security tab](https://github.com/fcreme/TerminalStyles/security) and click
  "Report a vulnerability".
- **Fallback:** email felipecremerius1@gmail.com.

This is a maintainer-run hobby project: responses are best-effort, usually
within a few days. There is no bug bounty.

## Scope

TerminalStyles writes to your PowerShell `$PROFILE` and Windows Terminal's
`settings.json`, fetches background images over HTTPS, and (on bootstrap
installs only) runs an unauthenticated daily update check against the GitHub
API. Reports about those write/fetch paths — profile injection, settings
corruption, update-check tampering — are explicitly welcome.
````

- [ ] **Step 5: Commit**

```powershell
git add CODE_OF_CONDUCT.md SECURITY.md
git commit -m "docs: add code of conduct (Contributor Covenant 2.1) + security policy"
```

---

### Task 3: GitHub issue forms + PR template

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/theme_idea.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Create `.github/ISSUE_TEMPLATE/bug_report.yml`:**

````yaml
name: Bug report
description: Something broke — wrong colors, a crash, a mangled settings.json
labels: [bug]
body:
  - type: textarea
    id: what-happened
    attributes:
      label: What happened, and what did you expect instead?
      description: Include the exact error text if there was any.
      placeholder: Ran `tstyles eva`, expected eva's colors — got a parse error instead.
    validations:
      required: true
  - type: textarea
    id: repro-steps
    attributes:
      label: Steps to reproduce
      description: The shortest sequence of commands that triggers it.
      placeholder: |
        1. Open a fresh Windows Terminal tab
        2. tstyles eva
        3. ...
    validations:
      required: true
  - type: input
    id: wt-version
    attributes:
      label: Windows Terminal version
      description: Windows Terminal → Settings → About. Say so if you're on Preview.
      placeholder: 1.22.10731.0
  - type: input
    id: ps-version
    attributes:
      label: PowerShell engine and version
      description: Paste the output of `$PSVersionTable.PSVersion`, and say whether it's pwsh 7 or Windows PowerShell 5.1 — bugs are often engine-specific.
      placeholder: 7.4.6 (pwsh) / 5.1.26100.2161 (Windows PowerShell)
    validations:
      required: true
  - type: dropdown
    id: install-kind
    attributes:
      label: How did you install TerminalStyles?
      description: Whichever your $PROFILE loads is the one that's active.
      options:
        - PSGallery (Install-PSResource)
        - Bootstrap one-liner (iwr | iex)
        - Not sure
    validations:
      required: true
  - type: input
    id: module-version
    attributes:
      label: Module version
      description: "`Get-Module TerminalStyles` shows it after import."
      placeholder: 0.6.1
  - type: textarea
    id: settings-snippet
    attributes:
      label: Relevant settings.json snippet
      description: Optional. The profile entry or `schemes` block involved, from `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`. Strip anything personal.
      render: json
````

- [ ] **Step 2: Create `.github/ISSUE_TEMPLATE/feature_request.yml`:**

````yaml
name: Feature request
description: Propose an improvement — picker, tuner, subcommands, anything
labels: [enhancement]
body:
  - type: textarea
    id: problem
    attributes:
      label: What problem does this solve?
      description: Describe the situation that's annoying or impossible today — the problem is often more useful than the feature.
      placeholder: With 30 saved styles, finding one in the picker means arrow-keying through the whole list.
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed solution
      description: What you'd like to happen. Rough is fine — a command sketch or example output helps.
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives considered
      description: Optional. Other approaches you thought about, or workarounds you use today.
````

- [ ] **Step 3: Create `.github/ISSUE_TEMPLATE/theme_idea.yml`:**

````yaml
name: Theme idea
description: Pitch a theme before building it — get a yes/no on bundling first
labels: [theme]
body:
  - type: markdown
    attributes:
      value: |
        Anyone can submit a theme, and pitching here first is encouraged — bundling is at
        the maintainer's discretion, so a quick yes/no on the idea saves you building
        something that won't land. Themes that aren't bundled still work as local user
        styles. The full rules live in the theme checklist in
        [CONTRIBUTING.md](https://github.com/fcreme/TerminalStyles/blob/main/CONTRIBUTING.md).
  - type: input
    id: theme-name
    attributes:
      label: Theme name
      description: Lowercase, hyphens for spaces, unique against the bundled catalog (see the README).
      placeholder: paper-morning
    validations:
      required: true
  - type: textarea
    id: mood
    attributes:
      label: Mood / inspiration
      description: What's the vibe? A film, a place, a time of day — whatever the theme is channeling.
      placeholder: Early-morning workshop — warm paper tones, pencil-graphite text, one teal accent.
    validations:
      required: true
  - type: textarea
    id: palette
    attributes:
      label: Palette sketch
      description: Rough 6-digit hex values are enough — this is a sketch, not the final scheme.json.
      placeholder: |
        background: #f4ecd8
        foreground: #3b3228
        cursor:     #00736f
        accents:    #a5222f, #4d6b2f, #0f4d8c
  - type: dropdown
    id: light-or-dark
    attributes:
      label: Light or dark?
      description: Light themes are especially wanted — only 1 of the 16 bundled themes is light.
      options:
        - Dark
        - Light
    validations:
      required: true
  - type: dropdown
    id: ships-background
    attributes:
      label: Ships a background image?
      description: Images go flat-named on the `gifs` branch, never on `main`. Keep it under ~2 MB, and only use images you have the right to redistribute.
      options:
        - "Yes"
        - "No"
    validations:
      required: true
  - type: checkboxes
    id: read-checklist
    attributes:
      label: Before you build
      options:
        - label: I've read the theme checklist in [CONTRIBUTING.md](https://github.com/fcreme/TerminalStyles/blob/main/CONTRIBUTING.md)
````

- [ ] **Step 4: Create `.github/ISSUE_TEMPLATE/config.yml`:**

````yaml
# Blank issues stay enabled — the forms cover the common cases without blocking anything else.
blank_issues_enabled: true
````

- [ ] **Step 5: Create `.github/pull_request_template.md`:**

````markdown
## What and why

<!-- What does this change, and what problem does it solve?
     Link the issue if there is one: Fixes #12 -->

## Checklist

- [ ] `Invoke-Pester -Path tests` is green locally on at least one engine — CI runs both pwsh 7 and Windows PowerShell 5.1
- [ ] New behavior has tests
- [ ] The diff stays focused on one change

## Theme PRs

<details>
<summary>Extra checklist if this PR adds or changes a theme (skip otherwise)</summary>

- [ ] `scheme.json` has a `name` that is unique across every bundled theme
- [ ] `scheme.json` has the full Windows Terminal key set (`styles/gitbash/scheme.json` shows it)
- [ ] Every color is 6-digit `#rrggbb` hex — no `#fff` shorthand
- [ ] Contrast floor passes locally: `Invoke-Pester -Path tests/Scheme-Contrast.Tests.ps1` (every chromatic ANSI color above 3:1 against the scheme background)
- [ ] No background binary on `main` — `tests/No-Committed-Backgrounds.Tests.ps1` fails CI if one sneaks in
- [ ] If the theme ships a background: the image sits flat at the root of the `gifs` branch as `<name>.<ext>`, under ~2 MB
- [ ] I have the right to redistribute any image in this PR
- [ ] README catalog entry added and screenshot regenerated via `scripts/capture-screenshots.ps1` (the maintainer can capture it if you can't run Windows Terminal)

</details>
````

- [ ] **Step 6: Verify the YAML parses.** Run:

```powershell
pwsh -Command "Install-PSResource -Name powershell-yaml -TrustRepository -ErrorAction SilentlyContinue; Get-ChildItem .github/ISSUE_TEMPLATE/*.yml | ForEach-Object { ConvertFrom-Yaml (Get-Content $_ -Raw) | Out-Null; \"OK $($_.Name)\" }"
```
Expected: `OK bug_report.yml`, `OK config.yml`, `OK feature_request.yml`, `OK theme_idea.yml`. (If powershell-yaml is unavailable, skip — GitHub validates on push and Task 6 checks rendering.)

- [ ] **Step 7: Commit**

```powershell
git add .github/ISSUE_TEMPLATE/ .github/pull_request_template.md
git commit -m "docs: add issue forms (bug/feature/theme idea) + PR template"
```

---

### Task 4: CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Create `CONTRIBUTING.md`** with exactly the content below (verified against the repo at commit `a06d157`; the contrast threshold is "above 3.0:1" because the test asserts `BeGreaterThan 3.0`):

````markdown
# Contributing to TerminalStyles

Thanks for helping out. There are two ways to contribute: a **theme**
(a small folder of JSON + an optional prompt script — no PowerShell
internals needed) or **code** (the picker, tuner, apply logic, tests).
This page covers both.

Quick links:

- **Found a bug? Want a feature?** [Open an issue](https://github.com/fcreme/TerminalStyles/issues/new/choose) —
  there are templates for bug reports, feature requests, and theme ideas.
- **Want to start somewhere easy?** Look for the
  [`good first issue`](https://github.com/fcreme/TerminalStyles/labels/good%20first%20issue) label.
- **Have a theme in mind?** Open a
  [theme idea issue](https://github.com/fcreme/TerminalStyles/issues/new/choose) first
  to get a quick yes/no before doing the work (see [Curation model](#curation-model)).

## Contributing a theme

A theme is a folder under `styles/<name>/`:

```
styles/<name>/
├── scheme.json    # Windows Terminal color scheme (required)
├── theme.json     # profile-level overrides (optional)
├── profile.ps1    # custom prompt/banner (optional)
└── README.md      # description (optional)
```

To develop one, iterate locally first: drop the folder into
`%LOCALAPPDATA%\TerminalStyles\styles\<name>\` and `tstyles` picks it
up on next module load (see "Adding your own style" in the README).

### scheme.json rules

- `name` must be **unique** across all bundled themes — schemes are
  deduplicated by name, so a duplicate would shadow another theme.
- Include the **full Windows Terminal key set**: `name`, `background`,
  `foreground`, `cursorColor`, `selectionBackground`, plus the 16 ANSI
  slots (`black`, `red`, `green`, `yellow`, `blue`, `purple`, `cyan`,
  `white` and their `bright*` variants). `styles/gitbash/scheme.json`
  shows the complete set.
- Colors must be **6-digit hex** (`#rrggbb`). Shorthand like `#fff`
  silently breaks the picker's swatch rendering.

### theme.json and the background placeholder

`theme.json` holds profile-level overrides (color scheme name, font,
opacity, cursor, padding, background fields). For the background image
field, use the literal string `"{{BACKGROUND_IMAGE}}"`:

```json
"backgroundImage": "{{BACKGROUND_IMAGE}}"
```

`tstyles` substitutes the fetched background (or the user's
`-BackgroundImage` flag) and strips the field if neither is available.
See `styles/umbrella/theme.json` for a full example.

### The two-branch submission flow

Code and images live on different branches — `main` stays binary-free:

1. **Code on `main`:** fork the repo, add the code-only folder
   (`scheme.json` / `theme.json` / `profile.ps1` / `README.md` — **no
   background image**) under `styles/<name>/`, and open a PR against `main`.
2. **Image on `gifs`:** if your theme ships a background, put the file
   at the **root** of the [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs)
   named `<name>.<ext>` (flat naming, no subfolder). `tstyles`
   lazy-fetches it on first use of your style.

Image rules:

- Keep it under **~2 MB**.
- Only submit images you have the **right to redistribute**.
- If multiple formats exist, the priority order is
  `.gif > .png > .jpg > .jpeg`.

### CI checks on theme PRs

Every PR runs the full Pester suite on both pwsh 7 and Windows
PowerShell 5.1. Two checks exist specifically to guard themes:

- **Contrast floor** (`tests/Scheme-Contrast.Tests.ps1`): every
  chromatic ANSI color (`red`, `green`, `yellow`, `blue`, `purple`,
  `cyan` and their `bright*` variants) must be **above 3.0:1 contrast**
  against your scheme's `background`. Black/white are exempt by design.
  If a color is intentionally below the floor and you can argue why,
  add a documented entry to the `$allow` table inside that test file —
  the only current exception is `umbrella/red`, the theme's signature
  blood red at 2.99:1. Tip: light backgrounds make this harder;
  saturated yellows and cyans usually need darkening.
- **No backgrounds on `main`** (`tests/No-Committed-Backgrounds.Tests.ps1`):
  fails if git tracks any `styles/*/background.*` file. Background
  images belong on the `gifs` branch.

Run everything locally before pushing:

```powershell
Invoke-Pester -Path .\tests                            # full suite
Invoke-Pester -Path .\tests\Scheme-Contrast.Tests.ps1  # just the contrast guard
```

### Screenshots

After adding a theme, regenerate the README screenshot gallery:

```powershell
# Must be run from inside a Windows Terminal tab
pwsh -File .\scripts\capture-screenshots.ps1
git add docs/screenshots/
git commit -m "Refresh theme screenshots"
```

The script applies each theme, captures one PNG of the WT window to
`docs/screenshots/<name>.png`, then restores your original theme. If
you can't run it (no Windows Terminal access), say so in the PR — the
maintainer can do this step for you.

### Curation model

Anyone may submit a theme — including one you made with `tstyles tune`
(the tuner's saved folder in `%LOCALAPPDATA%\TerminalStyles\styles\<name>\`
is exactly the submittable format). **Inclusion in the bundled catalog
is at the maintainer's discretion.** A theme is accepted when:

- it passes the CI checks above,
- it's visually distinct from the existing bundled themes,
- redistribution rights for any image are confirmed, and
- the maintainer likes it.

That last point is subjective by design — the catalog is curated, not
exhaustive. Opening a **theme idea** issue first is encouraged: you get
a yes/no before doing the work. A theme that isn't accepted for
bundling still works perfectly as a local user style and can be shared
from your own fork.

## Contributing code

### Dev setup

```powershell
git clone https://github.com/fcreme/TerminalStyles.git
cd TerminalStyles
Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking
```

`-DisableNameChecking` is required — the module ships an unapproved
verb (`Apply-StyleDirect`). Tests need Pester 5:

```powershell
# pwsh 7
Install-PSResource -Name Pester -Version '[5.0.0,)' -TrustRepository

# Windows PowerShell 5.1 (ships Pester 3 in-box, which won't work)
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

Then run the suite:

```powershell
Invoke-Pester -Path .\tests
```

CI (`.github/workflows/test.yml`) runs this exact suite on **both**
pwsh 7 and Windows PowerShell 5.1; Pester is the only CI check.

### PowerShell 5.1 compatibility

The whole codebase targets `#Requires -Version 5.1` and must run on
both engines. That means **no**:

- ternary `?:`
- null-coalescing `??` / null-conditional `?.`
- `&&` / `||` pipeline chain operators
- .NET-Core-only APIs

If you only develop in pwsh 7, the 5.1 CI leg will catch slips — but
testing locally in `powershell.exe` saves a round trip.

### Test conventions

- One concern per file, named `<FunctionName>.Tests.ps1`, with a
  `-<Scenario>` suffix for variants (e.g.
  `Apply-StyleDirect-KeepPrompt.Tests.ps1`).
- Use `InModuleScope TerminalStyles { ... }` to reach internal
  (non-exported) functions — see
  `tests/Invoke-TerminalStyle-TuneDispatch.Tests.ps1` for the
  dispatch/mock pattern.
- Use `$TestDrive` for scratch files; never touch the real
  `settings.json` or `%LOCALAPPDATA%` state.
- Write JSON fixtures BOM-less:
  `[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))`
  — see `tests/Find-WTSettingsPath.Tests.ps1`.

### Repo gotchas

- **Exports are locked** in `TerminalStyles.psd1`: only
  `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`, and the
  `tstyles` alias are exported. New public surface means editing
  `FunctionsToExport` / `AliasesToExport` deliberately.
- **Shipped files are allowlisted** in `scripts/publish.ps1`
  (`$allowlist`). A new file that must ship in the PSGallery package
  has to be added there, or it silently won't be published.
- **Shared field constants:** `$script:TStylesBgFields` and
  `$script:TStylesThemeFields` near the top of `tstyles.ps1` define
  which profile fields a style owns. Merge and reset both consume
  them — touch the constants, not the call sites.
- **`apply.ps1` duplicates six functions from `tstyles.ps1`**, each
  marked with a `keep in sync` comment. Until the open deduplication
  issue lands, a fix to one copy must be applied to both.

## Pull request expectations

- CI must pass on **both** engines (pwsh 7 and Windows PowerShell 5.1).
  Running the suite locally on at least one engine before pushing is
  expected.
- Behavior changes come with tests.
- Keep PRs small and focused — one theme or one fix per PR. Small PRs
  get reviewed fast; sprawling ones stall.

## Releases

Releases are maintainer-driven — contributors never publish to the
PowerShell Gallery. Version bumps, tagging, and publishing follow
[docs/RELEASING.md](docs/RELEASING.md). Your merged change ships with
the next release.
````

- [ ] **Step 2: Verify internal references resolve.** Run:

```powershell
Test-Path tests\Scheme-Contrast.Tests.ps1, tests\No-Committed-Backgrounds.Tests.ps1, tests\Invoke-TerminalStyle-TuneDispatch.Tests.ps1, tests\Find-WTSettingsPath.Tests.ps1, styles\gitbash\scheme.json, styles\umbrella\theme.json, scripts\capture-screenshots.ps1, docs\RELEASING.md
```
Expected: eight `True` lines.

- [ ] **Step 3: Commit**

```powershell
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING with theme + code tracks and curation model"
```

---

### Task 5: README slimming + Contributing section

**Files:**
- Modify: `README.md` (two exact-match edits)

- [ ] **Step 1: Slim the "For contributing back" steps to a pointer.** Edit `README.md` (exact match — mind the em-dashes):

Old:
```markdown
For contributing back:

1. Fork the repo, add the code-only folder (scheme.json / theme.json /
   profile.ps1 / README.md — no background) under `styles/<name>/` on
   `main`, and open a PR.
2. If your theme ships a background, also switch to the `gifs` branch
   and drop the file at the root as `<name>.<ext>` (flat naming, no
   subfolder). `main` stays code-only; `tstyles` lazy-fetches the
   background on first use of your style.
```

New:
```markdown
To contribute your theme back to the bundled catalog, see
[CONTRIBUTING.md](CONTRIBUTING.md) — short version: code-only folder
under `styles/<name>/` on `main`, background image (if any) flat-named
on the `gifs` branch, and the maintainer curates what gets bundled.
```

- [ ] **Step 2: Add the Contributing section.** Edit `README.md` (exact match):

Old:
```markdown
## License

MIT — see [LICENSE](LICENSE).
```

New:
```markdown
## Contributing

Bug reports, feature ideas, and new themes are all welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Themes are the easiest way in:
pitch one with a [theme idea issue](https://github.com/fcreme/TerminalStyles/issues/new/choose),
or grab a [`good first issue`](https://github.com/fcreme/TerminalStyles/labels/good%20first%20issue).

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 3: Run the full test suite** (docs-only change; this proves nothing broke):

Run: `Invoke-Pester -Path .\tests`
Expected: all tests pass, 0 failures.

- [ ] **Step 4: Commit**

```powershell
git add README.md
git commit -m "docs: link CONTRIBUTING from README, slim duplicated PR-flow steps"
```

---

### Task 6: Push and verify on GitHub

**Files:** none (remote verification)

- [ ] **Step 1: Push:**

```powershell
git push origin main
```

- [ ] **Step 2: Watch CI:**

```powershell
gh run list --branch main --limit 1
gh run watch <run-id-from-previous-command> --exit-status
```
Expected: both matrix legs (`Pester (pwsh 7)`, `Pester (Windows PowerShell 5.1)`) green.

- [ ] **Step 3: Verify the issue templates render.** Run:

```powershell
gh api repos/fcreme/TerminalStyles/contents/.github/ISSUE_TEMPLATE --jq '.[].name'
```
Expected: `bug_report.yml`, `config.yml`, `feature_request.yml`, `theme_idea.yml`. Then tell the user to spot-check https://github.com/fcreme/TerminalStyles/issues/new/choose — the three forms should appear (broken YAML shows as a missing/blank form).

---

### Task 7: Live repo metadata — ⚠️ USER PREVIEW GATE

**Files:** none (live `gh` changes)

- [ ] **Step 1: Check auth:**

Run: `gh auth status`
Expected: logged in with access to `fcreme/TerminalStyles`. If not, STOP and ask the user to run `gh auth login`.

- [ ] **Step 2: ⚠️ Show the user these exact commands and get explicit confirmation before running any of them:**

```powershell
gh repo edit fcreme/TerminalStyles --description "Themed styles for PowerShell in Windows Terminal - live-preview picker, tuner, 16 bundled themes" --add-topic powershell --add-topic windows-terminal --add-topic terminal-theme --add-topic color-scheme --add-topic windows --add-topic customization --add-topic pester
gh label create theme --repo fcreme/TerminalStyles --color 8250df --description "Theme submission or theme-related work"
gh api -X PUT repos/fcreme/TerminalStyles/private-vulnerability-reporting
```

(Note: `gh repo edit --description` takes ASCII text here — the em-dash is replaced with `-` to avoid shell encoding surprises.)

- [ ] **Step 3: After confirmation, run the three commands** (one at a time; `gh api -X PUT .../private-vulnerability-reporting` returns HTTP 204 with no body on success).

- [ ] **Step 4: Read back and verify:**

```powershell
gh repo view fcreme/TerminalStyles --json description,repositoryTopics
gh label list --repo fcreme/TerminalStyles
```
Expected: description + 7 topics set; `theme` label present alongside the default labels.

---

### Task 8: Seed the 11 issues — ⚠️ USER PREVIEW GATE

**Files:** read-only source: `docs/superpowers/specs/2026-06-12-contributor-onboarding-pack-issue-drafts.md` (§ "Issue drafts")

The full issue bodies live verbatim in the companion file — each `### Issue N` section has the title, labels, and the body inside a fenced ```markdown block. Do NOT rewrite the bodies; copy them exactly (the `file:line` pointers were verified at commit `a06d157`).

- [ ] **Step 1: ⚠️ Show the user the list of 11 issues (titles + labels below) and get explicit confirmation before creating any.**

| # | Title | Labels |
|---|-------|--------|
| 1 | Add more light-mode themes (only 1 of 16 themes is light) | `theme`, `good first issue`, `help wanted` |
| 2 | Picker: support Home/End/PageUp/PageDown and wrap-around navigation | `enhancement`, `good first issue` |
| 3 | Add a `tstyles version` subcommand | `enhancement`, `good first issue` |
| 4 | Add a scheme.json completeness + format validation test | `enhancement`, `good first issue` |
| 5 | Picker: type-to-filter style search | `enhancement`, `help wanted` |
| 6 | Previewing a style without a bundled background leaves a stale background image | `bug`, `help wanted` |
| 7 | Track the active style in a state file | `enhancement` |
| 8 | Deduplicate the six library functions copy-pasted into apply.ps1 | `enhancement`, `bug` |
| 9 | Picker breaks/overflows when the style list is taller than the terminal window | `bug`, `enhancement` |
| 10 | Restructure: split the 2,517-line tstyles.ps1 monolith into a conventional module layout | `enhancement`, `help wanted` |
| 11 | User comments in settings.json are silently deleted on first apply | `bug`, `help wanted` |

- [ ] **Step 2: After confirmation, create each issue in order 1→11.** For each: copy the body from the companion file's fenced block into `$env:TEMP\tstyles-issue-N.md` (Write tool, exact copy), then:

```powershell
gh issue create --repo fcreme/TerminalStyles --title "<title from table>" --label "<comma-joined labels from table>" --body-file "$env:TEMP\tstyles-issue-N.md"
```

Example for issue 1:

```powershell
gh issue create --repo fcreme/TerminalStyles --title "Add more light-mode themes (only 1 of 16 themes is light)" --label "theme,good first issue,help wanted" --body-file "$env:TEMP\tstyles-issue-1.md"
```

- [ ] **Step 3: Verify:**

```powershell
gh issue list --repo fcreme/TerminalStyles --limit 20
```
Expected: 11 open issues matching the table. Spot-check one on GitHub for body formatting (code fences render, checkboxes render).

- [ ] **Step 4: Clean up temp files:**

```powershell
Remove-Item "$env:TEMP\tstyles-issue-*.md"
```

---

## Out of scope (tracked elsewhere)

- GitHub Discussions, PSScriptAnalyzer lint step — deliberately excluded (spec § Decisions).
- The monolith restructure and theme-pipeline automation — seeded as issues 10 and 4/1 instead of built now.
