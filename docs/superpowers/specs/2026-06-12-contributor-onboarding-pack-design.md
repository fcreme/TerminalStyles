# Contributor Onboarding Pack — Design

**Date:** 2026-06-12
**Status:** Approved (pending user review of this written spec)
**Goal:** Turn TerminalStyles from a well-built solo project into one that visitors can
contribute to without asking questions first.

## Background

The repo already has the hard parts of an open-source project: PSGallery publishing,
40 Pester test files, CI on both pwsh 7 and Windows PowerShell 5.1, a strong README,
MIT license, and two merged community PRs. What it lacks is the contributor-facing
layer: there is no `CONTRIBUTING.md`, no issue/PR templates, no `CODE_OF_CONDUCT.md`,
no `CHANGELOG.md`, no seeded issues, and `.github/` contains only the test workflow.

Key facts mined from the repo (verified during research, 2026-06-12):

- CI runs the identical Pester invocation on two matrix legs (pwsh 7 + WinPS 5.1);
  Pester is the only CI check. Local equivalent: `Invoke-Pester -Path .\tests`.
- Dev import: `Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking`
  (`-DisableNameChecking` needed because of the unapproved verb in `Apply-StyleDirect`).
- Hard constraint: Windows PowerShell 5.1 compatibility (`#Requires -Version 5.1`) —
  no `?:`, `??`, `?.`, `&&`/`||` pipeline chains, no .NET-Core-only APIs.
- Exports are locked in `TerminalStyles.psd1` (`FunctionsToExport`, `AliasesToExport`);
  shipped files are controlled by the `$allowlist` in `scripts/publish.ps1`.
- CI already enforces two theme rules nobody documents: a >3.0:1 contrast floor on
  every chromatic ANSI color vs. the scheme background (`tests/Scheme-Contrast.Tests.ps1`,
  exceptions via its `$allow` table), and no `background.*` binaries on `main`
  (`tests/No-Committed-Backgrounds.Tests.ps1`).
- Theme contribution is a two-branch flow: code-only folder under `styles/<name>/` on
  `main`; background image flat-named `<name>.<ext>` at the root of the `gifs` branch.
- Releases are maintainer-only (`docs/RELEASING.md`); contributors never publish.

## Decisions (made with the user)

1. **Scope:** files committed to the repo **plus** live GitHub changes (seeded issues,
   repo description/topics, labels, private vulnerability reporting) — user previews
   every live change before it executes.
2. **Contact channel:** Code of Conduct lists `felipecremerius1@gmail.com` (public);
   SECURITY.md points at GitHub private vulnerability reporting with email fallback.
3. **Out of scope (deliberate):** GitHub Discussions (issues suffice at this scale),
   PSScriptAnalyzer CI lint (separate change — it will flag existing code), the
   monolith restructure and theme-pipeline automation (tracked as seeded issues instead).

## Deliverables

### 1. CONTRIBUTING.md (repo root)

Organized around the two contributor tracks, in this order (themes first — the most
likely contribution):

- **Welcome + quick links** — where to file bugs, propose themes, find good first issues.
- **Contributing a theme** — folder layout (`scheme.json` required; `theme.json`,
  `profile.ps1`, `README.md` optional); `scheme.json` rules (unique `name`, full
  Windows Terminal key set, 6-digit `#rrggbb` hex only); the `"{{BACKGROUND_IMAGE}}"`
  placeholder in `theme.json`; the two-branch submission flow; image rules (~2 MB cap,
  redistribution rights, priority `.gif > .png > .jpg > .jpeg`); **the CI checks that
  will run on the PR** (contrast floor, no-binaries-on-main) and how to test locally;
  screenshot regeneration via `scripts/capture-screenshots.ps1` (noting the maintainer
  can do this step for contributors without Windows Terminal access).
- **Contributing code** — dev setup (clone, import from checkout, Pester 5 install
  per engine, `Invoke-Pester -Path .\tests`); the PS 5.1 compatibility rules; test
  conventions (one concern per file, `<FunctionName>.Tests.ps1` naming with
  `-<Scenario>` suffix, `InModuleScope` for internal functions, `$TestDrive` for
  scratch files, BOM-less fixture writes); repo gotchas (locked exports in the
  manifest, `publish.ps1` allowlist, shared `$script:TStyles*Fields` constants,
  apply.ps1/tstyles.ps1 "keep in sync" duplicates until the dedup issue lands).
- **Pull request expectations** — CI must pass on both engines; tests for behavior
  changes; small focused PRs.
- **Releases** — maintainer-driven, link to `docs/RELEASING.md`.

README change: the "Adding your own style" section keeps the local-use instructions
(drop a folder in `%LOCALAPPDATA%\TerminalStyles\styles\`) but its "contributing back"
sub-steps are slimmed to a link to CONTRIBUTING.md, so the PR flow has one source of
truth. A short "Contributing" section (link + one-liner) is added near the bottom.

### 2. GitHub templates (.github/)

All issue templates are YAML forms (`.yml`), not markdown — structured fields render
as form inputs and produce consistently formatted issues.

- `ISSUE_TEMPLATE/bug_report.yml` — what happened / expected, repro steps, Windows
  Terminal version, PowerShell engine + version (`$PSVersionTable.PSVersion`), install
  kind (PSGallery / bootstrap dropdown), module version (`Get-Module TerminalStyles`
  output — a seeded issue proposes `tstyles version`; the template gets updated when
  that lands), relevant `settings.json` snippet.
- `ISSUE_TEMPLATE/feature_request.yml` — problem, proposed solution, alternatives.
- `ISSUE_TEMPLATE/theme_idea.yml` — theme name, mood/inspiration, palette sketch,
  light or dark, whether it ships a background image (with the rights reminder),
  link to the theme checklist in CONTRIBUTING.md.
- `ISSUE_TEMPLATE/config.yml` — `blank_issues_enabled: true`; no contact links for now.
- `pull_request_template.md` — what/why summary; checklist: tests pass locally on at
  least one engine and CI covers both; new behavior has tests; **theme sub-checklist**
  (unique scheme name, contrast floor passes locally, no background binary on `main`,
  background on `gifs` branch if any, image rights confirmed).

### 3. CODE_OF_CONDUCT.md

Contributor Covenant 2.1, verbatim standard text, enforcement contact
`felipecremerius1@gmail.com`.

### 4. SECURITY.md

- Supported versions: latest released version only (table).
- Report privately via GitHub private vulnerability reporting (Security tab →
  "Report a vulnerability"); email fallback `felipecremerius1@gmail.com`.
- Scope note: the module edits `$PROFILE` and Windows Terminal `settings.json` —
  reports about those write paths are explicitly welcome.
- Live change: enable private vulnerability reporting via
  `gh api repos/fcreme/TerminalStyles/private-vulnerability-reporting -X PUT`.

### 5. CHANGELOG.md

Keep-a-Changelog format, newest first, reconstructed retroactively from git tags
(version boundaries taken from tag targets, not bump-commit messages). Versions:
0.1.0 / 0.2.0 / 0.2.1 / 0.2.2 (2026-05-27), 0.3.0 / 0.4.0 / 0.4.1 / 0.4.2
(2026-05-29), 0.5.0 / 0.6.0 / 0.6.1 (2026-05-30), plus an **Unreleased** section for
the six post-v0.6.1 commits (JSONC crash fixes, gallery-install background fix,
picker/tuner Esc fixes, atomic writes, contrast lift, binary removal). Full mined
bullets: see Appendix A. Future releases add a CHANGELOG entry as part of the
release flow (note added to `docs/RELEASING.md`).

### 6. Live repo changes (each previewed with the user before execution)

- **Description:** "Themed styles for PowerShell in Windows Terminal — live-preview
  picker, tuner, 16 bundled themes".
- **Topics:** `powershell`, `windows-terminal`, `terminal-theme`, `color-scheme`,
  `windows`, `customization`, `pester`.
- **Labels:** create `theme` (color suggestion: purple); reuse built-in
  `good first issue`, `help wanted`, `bug`, `enhancement`, `documentation`.
- **Seed 11 issues** from verified candidates (full drafted bodies with verified
  `file:line` pointers in the companion file, Appendix B):

  | # | Title | Labels | Difficulty |
  |---|-------|--------|------------|
  | 1 | Add more light-mode themes (only 1 of 16 is light) | theme, good first issue, help wanted | good first issue |
  | 2 | Picker: Home/End/PageUp/PageDown + wrap-around | enhancement, good first issue | good first issue |
  | 3 | Add a `tstyles version` subcommand | enhancement, good first issue | good first issue |
  | 4 | scheme.json completeness/format validation test | enhancement, good first issue | good first issue |
  | 5 | Picker: type-to-filter style search | enhancement, help wanted | intermediate |
  | 6 | Stale background carryover for bundle-less styles | bug, help wanted | intermediate |
  | 7 | Track active style in a state file (-KeepPrompt blind spot) | enhancement | intermediate |
  | 8 | Deduplicate the six copy-pasted functions in apply.ps1 | enhancement, bug | intermediate |
  | 9 | Picker breaks when style list taller than window | bug, enhancement | intermediate |
  | 10 | Restructure: split the 2,517-line tstyles.ps1 monolith | enhancement, help wanted | hard |
  | 11 | User comments in settings.json silently deleted on apply | bug, help wanted | hard |

  Note: research candidate "Add CONTRIBUTING.md and templates" is excluded — this
  project delivers it directly.

## Error handling / edge cases

- `gh` operations require auth against `fcreme/TerminalStyles`; verify with
  `gh auth status` before live changes, and stop to ask the user if unauthenticated.
- Issue bodies reference `file:line` pointers valid at commit `a06d157`; if
  implementation happens after further commits, spot-check the pointers (they are
  also recorded with evidence notes in Appendix B).
- CHANGELOG accuracy: two known tag quirks are baked into the mined data (v0.3.0
  tagged one commit after its bump; post-0.2.0 installer fixes shipped in v0.2.1).

## Testing / verification

- Issue-template YAML validated by opening the "New issue" chooser on GitHub after
  push (forms render or GitHub falls back to blank — visible immediately).
- Existing Pester suite must stay green (docs-only change to README; no code paths
  touched): `Invoke-Pester -Path .\tests`.
- Live changes verified by reading them back (`gh repo view`, `gh label list`,
  `gh issue list`).

## Appendix A — mined CHANGELOG data

The full per-version bullets (Keep-a-Changelog style, user-facing wording) as mined
from git history on 2026-06-12 live in the companion file:
`2026-06-12-contributor-onboarding-pack-issue-drafts.md` § CHANGELOG data.

## Appendix B — seeded issue drafts

Full markdown bodies for all 11 issues, with verified code pointers and evidence
notes: `2026-06-12-contributor-onboarding-pack-issue-drafts.md` § Issue drafts.
