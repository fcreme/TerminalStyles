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
