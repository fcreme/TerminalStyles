# Style Content Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any style folder can be browsed without acting on the terminal, applied without leaving keys reset cannot take back, and refused cleanly when its JSON is broken; CONTRIBUTING says what CI requires of a new theme.

**Architecture:** A new `lib/stylefiles.ps1` holds the one reader of a style's JSON and the one "is it readable" question; every apply, preview, random pick, list row and tune entry asks it. `Select-StyleThemeFields` (in `lib/wtsettings.ps1`, beside the merge) decides which `theme.json` fields may reach a Windows Terminal profile, from the same `$script:TStylesThemeFields` reset uses. `ConvertTo-VisibleText` moves into `lib/text.ps1` and every display of style text goes through it.

**Tech Stack:** PowerShell 7 and Windows PowerShell 5.1, Pester 5/6. Run tests with `~/TerminalStyles/.claude/tools/run-pester.sh . <test files>` from the worktree root (sandboxed; mirrors CI).

**Spec:** `docs/superpowers/specs/2026-11-26-style-content-trust-design.md`

## Global Constraints

- Every user-facing message is a claim: it must be true on every path that prints it (CLAUDE.md).
- No second implementation of a rule: the field list is `$script:TStylesThemeFields`; the unsafe-text rule is `ConvertTo-VisibleText`; the readability rule is `Read-StyleJson`.
- Windows PowerShell 5.1: no 3-argument `Join-Path`, ASCII-only string literals in `.ps1`, `-ErrorVariable` rather than `2>&1` for captured errors (CI runs with `$ErrorActionPreference = 'Stop'`).
- Tests sandbox the data root and bind `-HomeDir` wherever a path reaches user files (CLAUDE.md, "Sandboxing").
- Commits: plain messages, no trailers.

## Review Focus

1. A `theme.json` key in another case (`TabTitle`, `CommandLine`): matched case-SENSITIVELY, so it is skipped and named, never written (Windows Terminal's keys are case-sensitive). Test in Task 3.
2. A `scheme.json` or `theme.json` whose root is not an object (`[]`, `"x"`, `3`): unreadable, refused with the file named. Test in Task 1.
3. A `backgroundImage` that is local only until environment variables expand (`%LOGONSERVER%\share\x.png`): refused. Test in Task 3.
4. A `theme.json` left with nothing applicable (only `commandline`): nothing is written to settings.json, and the apply says so instead of stranding the scheme. Test in Task 3.
5. A bundled description or quote holding characters the visible-text rule would rewrite: none may change (a ZWJ emoji would). Test in Task 4.

---

### Task 1: One reader for a style's JSON

**Files:**
- Create: `lib/stylefiles.ps1`
- Test: `tests/Read-StyleJson.Tests.ps1`

**Interfaces:**
- Produces: `Read-StyleJson -StyleDir <string> -FileName <string>` returns the parsed object, `$null` when the file does not exist, and throws one terminating error when it exists but is not a readable JSON object: `"TerminalStyles: could not read <style>'s <file>. To fix it: fix the file, or remove the style with: tstyles delete <style>. Underlying error: <reason>"` (`<style>` is the folder's leaf name). Parses through `ConvertFrom-JsoncText -SourceName "<style>'s <file>" -Remedy "fix the file, or remove the style with: tstyles delete <style>"`. An empty file, JSON `null`, or a root that is not an object is unreadable with reason `it holds no JSON object`.
- Produces: `Get-StyleUnreadableFile -StyleDir <string>` returns `$null` when `scheme.json` and (if present) `theme.json` both read, else a `[pscustomobject]@{ File = '<scheme.json|theme.json>'; Message = '<the reader's message>' }` for the first that does not (scheme first).

- [ ] **Step 1: Write the failing tests** (`InModuleScope TerminalStyles`, styles built under `$TestDrive`):
  - `It 'returns the object for a readable file'`: `{"name":"x"}` → `.name | Should -Be 'x'`.
  - `It 'returns $null for a file that is not there'`.
  - `It 'refuses <Case>' -ForEach @(@{Case='a JSON typo';Text='{"name": }'}, @{Case='an empty file';Text=''}, @{Case='JSON null';Text='null'}, @{Case='an array';Text='[1]'}, @{Case='a string';Text='"x"'})`: `{ Read-StyleJson -StyleDir $d -FileName 'theme.json' } | Should -Throw "*could not read wavy's theme.json*tstyles delete wavy*"`.
  - `It 'reads JSONC'`: `// c` line plus trailing comma parses.
  - `Get-StyleUnreadableFile`: `$null` for a good style; `.File | Should -Be 'scheme.json'` when both are broken; `'theme.json'` when only theme is broken; `$null` when theme.json is absent and scheme is good.
- [ ] **Step 2: Run** `run-pester.sh . tests/Read-StyleJson.Tests.ps1` — expect FAIL (`Read-StyleJson` not recognized).
- [ ] **Step 3: Implement both functions in `lib/stylefiles.ps1`**, reading bytes as UTF-8 without BOM like every other style read.
- [ ] **Step 4: Run the file** — expect PASS.
- [ ] **Step 5: Commit** `Read a style's JSON in one place, and say which file is unreadable`.

### Task 2: A broken style fails before anything is touched (#20)

**Files:**
- Modify: `lib/wtsettings.ps1` (`Get-StyleSettingsPayload`; `Merge-StyleIntoSettings` reads via `Read-StyleJson`)
- Modify: `lib/applystyle.ps1` (`Apply-StyleDirect` gate before `Save-SettingsBackup`; `Apply-StyleNonWT` gate before any VS Code consent, OSC, record or staging; `Invoke-RandomStyle` skips; `Show-StyleList` marks an unreadable theme.json)
- Modify: `apply.ps1` (throws the reader's message)
- Modify: `lib/picker.ps1` (`Get-PickerStyleSet` drops an unreadable theme.json too, and reports which file) and `tstyles.ps1:1569-1571` (the note names that file)
- Modify: `lib/tune.ps1` (`Invoke-TerminalStyleTune` refuses an unreadable style up front)
- Test: `tests/Style-Unreadable.Tests.ps1` (new), `tests/Picker-BrokenStyle.Tests.ps1`

**Interfaces:**
- Consumes: `Read-StyleJson`, `Get-StyleUnreadableFile` (Task 1).
- Produces: `Get-StyleSettingsPayload` gains `Unreadable` (`$null` or the reader's message); `Ok` is `$false` when it is set. `Get-PickerStyleSet` gains `UnreadableFile` (`@{ <name> = '<file>' }`); `Unreadable` stays the list of names.

- [ ] **Step 1: Write the failing tests** in `tests/Style-Unreadable.Tests.ps1` (data root and settings path sandboxed; `Mock Get-TerminalKind`):
  - `It 'Apply-StyleDirect refuses a broken theme.json without spending the backup'`: settings.json bytes and `settings.json.bak` absent before and after; no `current-style.json`; error text matches `*could not read*theme.json*`.
  - `It 'Apply-StyleNonWT refuses a broken scheme.json before recording it'`: no record, no `current-style.osc`, output has no `Style applied`.
  - `It 'random never picks an unreadable style'`: two styles, one broken; `Mock Apply-StyleDirect`; 20 runs all call it with the good name.
  - `It 'list marks an unreadable theme.json'`: the row contains `(unreadable theme.json)`.
  - `It 'tune refuses an unreadable style'`: `Invoke-TerminalStyleTune -StyleName broken` writes the reader's message and opens nothing.
  - In `Picker-BrokenStyle.Tests.ps1`: `It 'drops a style whose theme.json will not parse, and says which file'`: `UnreadableFile['b'] | Should -Be 'theme.json'`; the note reads `! b -- unreadable theme.json, not shown`.
- [ ] **Step 2: Run both files** — expect the new cases to FAIL.
- [ ] **Step 3: Wire the gates.** Each gate calls `Get-StyleUnreadableFile` (or the payload) and returns before its first side effect, writing the reader's message once (`Write-Error` in the module, `throw` in `apply.ps1`). The picker note for several unreadable styles names the file when they share one, else says `unreadable style files`.
- [ ] **Step 4: Run both files, then the full suite** — expect PASS, no other failures.
- [ ] **Step 5: Commit** `Refuse a style whose JSON will not parse before touching anything`.

### Task 3: Apply writes only what reset takes back (#44)

**Files:**
- Modify: `lib/wtsettings.ps1` (new `Select-StyleThemeFields`, `Test-LocalImagePath`; the merge's property loop and its `$themeBgNames` use the picked fields; `Get-StyleSettingsPayload` reports a theme with nothing applicable)
- Modify: `lib/applystyle.ps1` (`Apply-StyleDirect` prints the skipped keys after a successful write), the picker's Enter path (same line), `apply.ps1` (same line)
- Modify: `docs/wiki/Creating-a-Style.md` (which `theme.json` keys apply, and what happens to the rest)
- Test: `tests/Merge-StyleIntoSettings.Tests.ps1`, `tests/Select-StyleThemeFields.Tests.ps1` (new)

**Interfaces:**
- Produces: `Select-StyleThemeFields -Theme <object>` returns `[pscustomobject]@{ Fields = [ordered]@{ name = value }; Skipped = @([pscustomobject]@{ Name; Reason }) }`. A key is kept only if `$script:TStylesThemeFields -ccontains` it. `backgroundImage` is kept only if it is `{{BACKGROUND_IMAGE}}` or `Test-LocalImagePath` passes; otherwise it is skipped with reason `not a file on this computer`. Other keys get reason `tstyles reset could not take it back`.
- Produces: `Test-LocalImagePath -Value <string>` returns `$true` unless, after `[Environment]::ExpandEnvironmentVariables`, the value starts with `\\` or `//`, or has a URI scheme of two or more characters other than `ms-appdata:`, `ms-appx:`, or `file:` followed by `///`.
- Produces: the note, printed once per apply when anything was skipped: `"  Not applied from theme.json: {0}. A style sets only what tstyles reset can take back off a profile."` where `{0}` joins `name` or `name (reason)` with `, `.

- [ ] **Step 1: Write the failing tests:**
  - `Select-StyleThemeFields`: keeps the 13 keys with their values; skips `commandline`, `elevate`, `startingDirectory`, `icon`; skips `TabTitle` (case); `backgroundImage` cases `'{{BACKGROUND_IMAGE}}'` kept, `'C:\pics\a.png'` kept, `'\\server\share\a.png'` skipped, `'//server/a.png'` skipped, `'https://x/a.png'` skipped, `'ms-appdata:///local/a.png'` kept, `'file:///C:/a.png'` kept, `'file://server/a.png'` skipped; `'%TS_TEST_NET%\a.png'` with `$env:TS_TEST_NET = '\\server\share'` skipped.
  - Merge: a theme with `commandline` and `tabTitle` writes `tabTitle` and leaves the profile's own `commandline` untouched.
  - Round trip: `It 'reset leaves the profile exactly as it was before the apply'`: apply a style whose theme.json carries `commandline`, `elevate` and the bundled keys to a profile with its own `commandline`, then `Reset-StyleDirect`; the profile entry serializes byte-identical to before.
  - `It 'names the keys it skipped, once'` for `Apply-StyleDirect` (output has the note exactly once) and none when nothing was skipped.
  - `It 'writes nothing to settings.json when theme.json has nothing applicable'`: theme `{"commandline":"x"}`; settings.json bytes unchanged; the output names `commandline` and says nothing was written to settings.json.
- [ ] **Step 2: Run the two files** — expect FAIL.
- [ ] **Step 3: Implement**, then document the rule in `docs/wiki/Creating-a-Style.md` (the 13 keys; everything else is skipped and named).
- [ ] **Step 4: Run the two files, then the full suite** — expect PASS.
- [ ] **Step 5: Commit** `Write only the theme.json keys reset can take back off a profile`.

### Task 4: Style text cannot act on the terminal (#89)

**Files:**
- Modify: `lib/text.ps1` (gains `ConvertTo-VisibleText`), `scripts/review-submission.ps1` (dot-sources `lib/text.ps1`; its own copy goes)
- Modify: `lib/picker.ps1` (`Get-StyleMeta`), `tstyles.ps1:1580-1590` (title preload through new `Get-StyleTitlePreview`)
- Modify: `lib/submit.ps1` (description, quote and `tabTitle` checks share the rule)
- Test: `tests/ConvertTo-VisibleText.Tests.ps1` (new), `tests/Style-Meta.Tests.ps1`, `tests/Style-Submit.Tests.ps1`

**Interfaces:**
- Produces: `ConvertTo-VisibleText -Text <string> [-SingleLine]` returns the text with every control character but `\n` and `\t` as `\xNN` and every `\p{Cf}` as `\uNNNN` (the script's rule, unchanged); `-SingleLine` first turns each run of `\r`, `\n`, `\t` into one space.
- Produces: `Get-StyleTitlePreview -StyleDir <string>` returns the `tabTitle` from `theme.json` through `ConvertTo-VisibleText -SingleLine`, or `$null` when there is none or the file is unreadable.

- [ ] **Step 1: Write the failing tests:**
  - `ConvertTo-VisibleText`: ``"a`e]0;x`ab"`` → `'a\x1b]0;x\x07b'`; `[char]0x9B` → `'\x9b'`; `[char]0x202E` → `'\u202e'`; `"a`nb"` unchanged; with `-SingleLine` → `'a b'`.
  - `Get-StyleMeta`: a description holding ESC and BEL comes back visible; a quote with a line break comes back on one line.
  - `It 'changes no bundled description or quote'`: for every `styles/*/meta.json`, `ConvertTo-VisibleText -SingleLine` of each value equals the value.
  - `Get-StyleTitlePreview`: ESC in `tabTitle` comes back as `\x1b`; `$null` without `tabTitle`.
  - Submit: a description with ESC, a quote with `[char]0x202E`, and a `tabTitle` with `[char]0x9B` are each refused with a problem naming the field.
  - `It 'review-submission.ps1 defines no ConvertTo-VisibleText of its own'` (AST: no `FunctionDefinitionAst` of that name in the script).
- [ ] **Step 2: Run the four files** — expect FAIL.
- [ ] **Step 3: Implement.** Move the function verbatim (it is 5.1-safe), add `-SingleLine`, and dot-source `lib/text.ps1` at the top of the review script with nested `Join-Path`.
- [ ] **Step 4: Run the four files, then the full suite** — expect PASS.
- [ ] **Step 5: Commit** `Show a style's text instead of letting it act on the terminal`.

### Task 5: CONTRIBUTING says what CI requires (#40)

**Files:**
- Modify: `CONTRIBUTING.md` (the by-hand route and "CI checks on theme PRs"; the curation paragraph's `tstyles tune` claim; the data folder on every platform)
- Test: `tests/Contributing-MatchesCI.Tests.ps1`

- [ ] **Step 1: Write the failing tests:** CONTRIBUTING names `meta.json` in the folder layout; names `scripts/make-banner.py`, `docs/index.html`, and the README's theme count; names each style-guard test file `Style-Meta`, `README-Theme-Count`, `README-Banner`, `Scheme-Contrast`, `Shell-Prompt`, `Style-PromptParity`, `Style-PSReadLine-Colours`, `Style-README-Accuracy`, `No-Committed-Backgrounds`; and does not say a `tstyles tune` folder is submittable (`Should -Not -Match 'tstyles tune[^.]*submittable'`).
- [ ] **Step 2: Run it** — expect FAIL.
- [ ] **Step 3: Rewrite the section** from the 2026-11-26 measurement: a theme added exactly as the old guide said failed meta, counts, banner, site lists, the submit-parity test, and swatch distinctness.
- [ ] **Step 4: Run it, then the full suite** — expect PASS.
- [ ] **Step 5: Commit** `Make CONTRIBUTING's by-hand theme route list what CI requires`.

### Task 6: Record and ship

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]`: one Security entry for #44 and #89, one Fixed entry for #20, one for #40), `docs/superpowers/specs/2026-11-26-style-content-trust-design.md` (the picker drops an unreadable style and names it, as it already does for a scheme)

- [ ] **Step 1: Write the CHANGELOG entries** (mechanism and user-visible consequence, in the file's prose style).
- [ ] **Step 2: Run the full suite** — expect 0 failed.
- [ ] **Step 3: Commit, push the branch, open the PR**, and request the independent review.
