# Style submission: `tstyles submit` and the maintainer's review

Status: design. Follows `2026-11-06-live-style-creator-design.md`, which
named this as the next project ("creator first then submitting").

## Intent

A user who made a style with `tstyles create` (or `tune`, or by hand) can
offer it for the bundled catalogue without knowing git. The maintainer
decides; nothing reaches other users until the maintainer merges.

Today the only route is CONTRIBUTING's two-branch flow: fork, add the
code-only folder on `main`, put the image flat on the `gifs` branch, open
two PRs, pass CI. That is fine for developers and a wall for everyone the
creator was built for.

## Goals

- One command on the user's side: `tstyles submit <name>`.
- The user finds out locally, before submitting, about anything that would
  certainly get the style refused (broken scheme, contrast floor, image too
  big, name already bundled).
- The maintainer gets one place to look (a GitHub issue), and one command
  that checks the submission and, on approval, opens the PRs that add it.
- Approval is merging. Rejection is closing the issue with a reason.

## Non-goals

- No server, no bot, no GitHub token on the user's machine, no `gh`
  requirement for users.
- No automatic CI workflow reacting to submission issues. A workflow that
  downloads and unpacks strangers' zips with a write token is attack
  surface the project does not need; the maintainer runs the review
  locally, where nothing in the zip is executed.
- Not a gallery website, voting, or a way to install unapproved styles from
  other users.

## Anti-goals

- Executing anything from a submission on the maintainer's machine. The
  review script parses JSON and copies files as bytes; it never dot-sources
  `profile.ps1` or runs `prompt.sh`.
- Telling the user "submitted" when nothing was sent. The command cannot
  attach a file to an issue; it says exactly what the user still has to do.
- A second copy of the catalogue's rules that drifts from the tests (see
  "One rule").

## The user's side: `tstyles submit <name>`

1. Resolves `<name>` to a USER style (`$DataRoot\styles\<name>`). A bundled
   style is refused: "'eva' is already in the catalogue." Unknown name:
   the usual "no such style".
2. Runs `Get-StyleSubmissionProblems` (below). Any problem: list them, one
   line each, and stop. Nothing is written.
3. If the style ships a background, asks two questions: where the image
   comes from (free text, may be empty) and "Do you have the right to let
   everyone use this image? [y/N]". Anything but y stops: "Not submitted:
   the catalogue can only ship images that may be shared."
4. Writes `$DataRoot\submissions\<name>.zip`: the style's allowed files
   plus `submission.json` (name, module version, image source, rights
   answer, UTC timestamp). Overwrites an older zip for the same name.
5. Prints the zip's path and the issue URL, and opens the URL in the
   browser (`Start-Process`; failure to open is not an error, the URL is
   on screen). The URL is the "Style submission" issue form, prefilled
   with the name, description and image source via query parameters.
6. Final line says what is left: "Drag <zip> into the issue and press
   Submit. The maintainer decides whether it joins the catalogue."

Works on every platform; it does not touch any terminal's settings.

## What gets checked: `Get-StyleSubmissionProblems -StyleDir`

Returns an array of plain sentences, empty when submittable. Rules:

- `scheme.json` parses and has the full Windows Terminal key set, every
  colour 6-digit `#rrggbb`.
- Contrast: every chromatic ANSI slot >3.0:1 on `background`; `foreground`
  >4.5:1 on `selectionBackground`. These are the catalogue's CI floors.
- `prompt.sh` present when `profile.ps1` is.
- `meta.json` has a one-line description of at most 90 characters (the
  picker's cap); a quote, if any, at most 70.
- Only these files: `scheme.json`, `theme.json`, `profile.ps1`,
  `prompt.sh`, `README.md`, `meta.json`, and at most one `background.<ext>`
  of a supported type. Anything else is named as a problem.
- Background at most 2 MB (CONTRIBUTING's rule).
- The folder name is not a bundled style's name, and passes
  `Test-StyleNameValid`.

### One rule

The contrast floors move out of `tests/Scheme-Contrast.Tests.ps1` into a
library function (`Get-SchemeCatalogueContrastProblems`), and the test
calls it for every bundled scheme, keeping its `$allow` table. The meta
caps likewise come from one place read by `Style-Meta.Tests.ps1`. A
new test asserts every bundled style returns no submission problems
except the ones it is documented as exempt from (umbrella/red), so the
submit check can never be stricter than the catalogue it feeds.

The check is a pre-flight, not the gate: the PR the maintainer opens runs
the whole suite, which stays the final word.

## Telling generated prompts from hand-written ones

`Save-CreatedStyle` adds a `created` block to `meta.json`: the prompt
shape, symbol, path colour and symbol colour it generated from. The review
regenerates `New-StylePromptText` from that block (title = upper-cased
name) and compares bytes with the submitted `profile.ps1` / `prompt.sh`
(LF-normalised). Match: "Prompt is generated by tstyles create; no
hand-written code." Anything else (no block, mismatch, tuner or hand-made
style): "profile.ps1 / prompt.sh are hand-written; read them before
accepting", and the review prints both files.

## The issue form

`.github/ISSUE_TEMPLATE/style_submission.yml`, label `style-submission`.
Fields: style name, description, image source, a required rights checkbox,
and a note telling the user to attach the zip. `config.yml` and
CONTRIBUTING link it.

## The maintainer's side: `scripts/review-submission.ps1`

`-Issue <n>` (report only), `-Accept`, or `-Reject -Reason <text>`. Uses
`gh`, run by the maintainer in a clone of the repo.

- Reads the issue, finds exactly one `.zip` attachment link
  (`github.com/user-attachments/...`), downloads it to a temp folder.
- Unpacks safely: entry count and total size capped, every entry must be a
  flat file name on the allow-list (no folders, no `..`, no absolute
  paths); otherwise refuse and say why.
- Runs `Get-StyleSubmissionProblems` on the unpacked folder (from the
  clone's module, not the user's) plus the generated-prompt check, and
  prints a report: problems, prompt verdict, image size and type,
  `submission.json` contents, and the name-collision check against the
  clone's `styles/`.
- `-Accept` (refused if there are problems): creates branch
  `style/<name>` from `origin/main` with `styles/<name>/` (no image) and a
  generated `README.md` whose `## Includes` matches the folder and credits
  the issue author by profile link; and branch `style/<name>-image` from
  `origin/gifs` with `<name>.<ext>` at the root. Pushes both, opens both
  PRs (each referencing the issue), comments on the issue with the links,
  and prints the remaining manual checklist (README theme count, wiki
  Styles.md entry, screenshot). Merging both PRs is the approval.
- `-Reject -Reason` comments the reason and closes the issue as not
  planned.

Every remote write is printed before it happens; the script refuses to run
outside a clean clone of `fcreme/TerminalStyles`.

## Wiring

- `submit` joins `$script:TStylesSubcommands`, dispatch beside `create`,
  tab completion of user style names, help topic, wiki commands list,
  CHANGELOG `[Unreleased]`.
- After `tstyles create` saves, its last line mentions `tstyles submit
  <name>`.

## Left to the builder

File layout inside `lib/` (a `lib/submit.ps1` is expected), exact message
wording within the rules above, zip caps (suggested: 16 entries, 4 MB).
