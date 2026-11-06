# Live Style Creator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `tstyles create`: a step-by-step creator in Windows Terminal that builds a new style from an image file, previewing every change live in the running window, and saves it as an ordinary style.

**Architecture:** Pure pieces first, each tested on every CI leg: the palette builder, the prompt generator, the style writer, the creator's state and key engine, and the page renderer. Two thin platform pieces sit on top: pixel reading, which is Windows-only through `System.Drawing`, and the interactive loop. The live preview reuses the tuner's mechanism. It writes a scratch style, merges it into `settings.json` through `Merge-StyleIntoSettings` and `Write-FilePreview`, and repaints colours over OSC. Esc and crash recovery come from `lib/previewsession.ps1` unchanged.

**Tech Stack:** PowerShell 5.1 + pwsh 7, Pester 5, `System.Drawing` (Windows), Windows Terminal `settings.json`, OSC 4/10/11/12.

**Spec:** `docs/superpowers/specs/2026-11-06-live-style-creator-design.md`. Read it before any task.

## Global Constraints

- Windows PowerShell 5.1 and pwsh 7. ASCII-only string literals in `.ps1`, and none of `?:`, `??` or `&&`. CI runs pwsh 7, 5.1, macos-latest and ubuntu-latest.
- Read CLAUDE.md before starting. Its sandboxing, encoding, "every message is a claim" and "tests that measure nothing" rules apply to every task.
- Run tests only through `~/.claude/projects/-Users-cremerius/5aac5cbd-aa55-42a0-9085-695ad8af1088/tools/run-pester.sh <worktree> [tests...]`. Never run `tstyles create`, or any other tstyles command, against the real environment.
- **Tests first, proven red.** Each new test must fail on the code before its step, for the reason it tests. Check which assertion failed. A guard such as "the probe must differ" failing is a false red.
- Every test that writes runs in `$TestDrive`, with `$script:TStylesDataRoot` pointed there. Settings paths are under `$TestDrive`. `Confirm-Action` is mocked to refuse where it could be reached.
- Style files follow the existing layout: `scheme.json` (21 keys: `name`, `background`, `foreground`, `cursorColor`, `selectionBackground`, `black` `red` `green` `yellow` `blue` `purple` `cyan` `white`, and `brightBlack` through `brightWhite`), `theme.json` (keys as `styles/eva/theme.json`, with `backgroundImage` = `{{BACKGROUND_IMAGE}}`), `profile.ps1`, `prompt.sh` (LF only, `_ts_`-prefixed names on every column), and `meta.json`.
- A name is valid by `Test-StyleNameValid`. A name that `Get-StyleDir` already resolves (a user or bundled style) is **refused**, and nothing is written.
- Commits: plain messages, no Co-Authored-By or session trailers. One task can be one commit or several.

## Review Focus

1. **A pasted path with quotes or spaces**, such as `"C:\My Pictures\city.png"` (Windows Explorer's "Copy as path" adds the quotes). Expected: it's accepted, and the quotes are stripped. Test in Task 6.
2. **A huge image** (8000x8000 PNG, or a 50 MB GIF). Expected: it's downscaled before analysis, and the palette arrives without the page freezing for more than about 2 s. Test in Task 1 (`-MaxSide` bounds the sample).
3. **A greyscale or single-colour image.** Expected: the palette still has a red that reads as red, a green as green, and so on, all readable on the background. Test in Task 2.
4. **The tab closed mid-creation.** Expected: the next tstyles command puts `settings.json` back. That comes from `Restore-AbandonedFilePreview`, because the creator's preview is a normal session. Test in Task 5.
5. **A file that isn't an image, or can't be read.** Expected: a one-line message on the background page, with the user still on that page; nothing written. Tests in Tasks 1 and 6.

---

### Task 1: Read an image's pixels (Windows only)

**Files:**
- Create: `lib/imagepixels.ps1`
- Test: `tests/Read-ImagePixels.Tests.ps1`

**Interfaces:**
- Produces: `Read-ImagePixels -Path <string> [-MaxSide <int> = 96]` -> `[int[]]`, each `0xRRGGBB`. It reads the first frame of a GIF, ignores alpha, and scales the longest side down to at most `-MaxSide` before sampling. It throws `"Not an image TerminalStyles can read: <path>"` for a missing file, a non-image or an unsupported format. Off Windows it throws `"Reading images needs Windows."`.
- Produces: `Test-ImagePixelReaderAvailable` -> `[bool]`, true on Windows when `System.Drawing` loads.

- [ ] **Step 1: Write the failing tests.** Gate them on `Test-ImagePixelReaderAvailable`, evaluated in **BeforeDiscovery** (CLAUDE.md: `-Skip:` is decided at discovery). Make the fixtures in the test with `System.Drawing.Bitmap`.
  - A 4x4 PNG filled with `#ff0000` returns 16 values, every one `0xFF0000`.
  - A 2000x1000 PNG with `-MaxSide 50` returns at most `50*25` values.
  - A two-frame GIF (frame 1 green, frame 2 blue) returns only green.
  - A `.png` file holding the text `hello` throws `*Not an image TerminalStyles can read*`.
  - Off Windows (a separate It, skipped on Windows), it throws `*needs Windows*`.
- [ ] **Step 2: Run them and confirm they fail** (the function is missing).
- [ ] **Step 3: Implement it.** Use `Add-Type -AssemblyName System.Drawing`, `[System.Drawing.Image]::FromFile`, `SelectActiveFrame` for frame 0, and draw onto a small `Bitmap` with `Graphics.DrawImage`. Read with `LockBits`, or `GetPixel` on the downscaled bitmap. Dispose everything in `finally`.
- [ ] **Step 4: Run them; they pass on Windows and skip cleanly elsewhere.**
- [ ] **Step 5: Commit.**

### Task 2: Build a readable scheme from pixels (pure)

**Files:**
- Create: `lib/palette.ps1`
- Test: `tests/New-PaletteFromPixels.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ContrastRatio`, `Get-SchemeUnreadableSlots`, `ConvertTo-NormalHex` from `lib/color.ps1`.
- Produces: `New-PaletteFromPixels -Pixels <int[]> -Name <string>` -> `[pscustomobject]` with the 21 scheme keys, all lower-case `#rrggbb`. It is deterministic: the same input gives the same output.
- Produces: `Get-PaletteAccent -Scheme <object>` -> `#rrggbb`, the most saturated colour found in the image, used for the tab colour and the default prompt colour.

- [ ] **Step 1: Write the failing tests.** Inputs are made-up pixel arrays, so these run on every leg.
  - Every key `-cmatch '^#[0-9a-f]{6}$'`, and `name` equals `-Name`.
  - `Get-ContrastRatio foreground background` is at least 7.
  - `Get-SchemeUnreadableSlots` on the result is empty.
  - Hue role: `red`, `green`, `yellow`, `blue`, `purple` and `cyan` each sit within 30 degrees of 0, 120, 60, 240, 300 and 180. Each `bright<X>` has the same role, and its relative luminance is at least that of `<X>`.
  - Run for three inputs: a sunset-like mix (oranges, purples, dark blue); all `0x808080` (Review Focus 3); and all `0x00ff00`.
  - Two calls with the same pixels produce identical JSON.
  - The background is the darkest dominant cluster, so a mostly-dark image gives a background with relative luminance below 0.05.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement it.** Use k-means (k = 8, fixed seed and iteration count) or median cut. Take the background from the darkest large cluster, darkened if needed, and the foreground from the lightest, raised until the contrast is at least 7. For each ANSI role, pick the cluster nearest the role's hue; if none is within 30 degrees, use the role hue at the image's mean saturation. Adjust lightness until the contrast against the background is at least 4.5. Brights are the same hue, lighter. `cursorColor` = foreground. `selectionBackground` = background lightened by 15%.
- [ ] **Step 4: Run them; they pass.**
- [ ] **Step 5: Commit.**

### Task 3: Generate the prompt halves (pure)

**Files:**
- Create: `lib/promptgen.ps1`
- Modify: `tests/Style-PromptParity.Tests.ps1`. Add a Describe that renders generated styles through the same harness and comparison (`Assert-PromptsMatch`, the three halves, the four cwds).
- Test: `tests/New-StylePromptText.Tests.ps1`

**Interfaces:**
- Produces: `Get-StylePromptShapes` -> `@('minimal','path','twoline','git')`.
- Produces: `Get-StylePromptSymbols` -> `[string[]]`, which must include `'$'`, `'>'`, `'#'`, U+276F `❯`, U+03BB `λ` and U+00BB `»`. Build them with `[char]0x276F` and so on; never write them as literals.
- Produces: `New-StylePromptText -Shape <string> -Symbol <string> -PathColor <#rrggbb> -SymbolColor <#rrggbb> [-BranchColor <#rrggbb>] -Title <string>` -> `@{ Profile = <string>; Shell = <string> }`. `Profile` is a complete `profile.ps1`; `Shell` is a complete `prompt.sh`.
  - The shapes map to the existing placeholders: minimal = `{LEAF}`; path = `{CWD}`; twoline = `{CWD}{NL}`; git = `{LEAF}{GITBRANCH}`.
  - The PowerShell half copies the matching logic from `styles/sober/profile.ps1` for `{LEAF}` and from `styles/gitbash/profile.ps1` for `{CWD}` and the branch, including saving and restoring `$LASTEXITCODE`.
  - The symbol is followed by one space.

- [ ] **Step 1: Write the failing tests.**
  - **ASCII-only:** for every shape and symbol pair, `Profile` holds only ASCII bytes, so the symbol is emitted as `[char]0x...`, since 5.1 misreads non-ASCII literals in a BOM-less file.
  - **Shell side:** `Shell` has no CR, and every variable it assigns `-cmatch '^_ts_'`.
  - **Parse:** `Profile` parses with `[Parser]::ParseInput`, with no errors.
  - **Parity:** the new Describe in `Style-PromptParity.Tests.ps1` writes each shape with `$`, and each symbol with `minimal`, into `$TestDrive` style folders. It asserts that each renders byte-identically in PowerShell, zsh and bash at the harness's four directories. Keep the existing `-Skip` gates, set in BeforeDiscovery.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement it.** Write colours as `38;2;r;g;b`, with the shell side using `ts_c`, exactly as `styles/sober/prompt.sh`. The title uses `ts_title` and `$Host.UI.RawUI.WindowTitle`, as sober does. Generate no PSReadLine block; CLAUDE.md says the line editor belongs to the user.
- [ ] **Step 4: Run them, plus the full `Style-PromptParity.Tests.ps1`; all pass on macOS locally, and the zsh and bash legs run in CI.**
- [ ] **Step 5: Commit.**

### Task 4: Write a created style to disk (refuse taken names)

**Files:**
- Create: `lib/createstyle.ps1`
- Test: `tests/Save-CreatedStyle.Tests.ps1`

**Interfaces:**
- Consumes: `New-StylePromptText` (Task 3), `Test-StyleNameValid`, `Get-StyleDir`.
- Produces: `New-CreatedThemeObject -Name -FontFace -FontSize -CursorShape -ImageOpacity <double 0..1> -StretchMode <none|fill|uniform|uniformToFill> -Alignment <string> -TabColor <#rrggbb>` -> `[pscustomobject]`. It has `theme.json`'s keys, with `colorScheme` = `-Name`, `tabTitle` = `-Name` upper-cased with `ToUpperInvariant()`, and `backgroundImage` = `'{{BACKGROUND_IMAGE}}'`.
- Produces: `Save-CreatedStyle -Name <string> -Scheme <object> -Theme <object> -BackgroundPath <string> -Prompt <hashtable> [-Description <string>]` -> `[pscustomobject]@{ Status; Path; Reason }`.
  - `Status` is one of `saved`, `taken`, `invalid` or `failed`.
  - It writes to `$script:TStylesDataRoot\styles\<Name>`.

- [ ] **Step 1: Write the failing tests** (data root in `$TestDrive`).
  - **Saved:** `saved` leaves exactly `scheme.json`, `theme.json`, `profile.ps1`, `prompt.sh`, `meta.json` and `background.<ext>`.
    - `Get-StyleDir -StyleName <Name>` resolves to the new folder.
    - `Get-AvailableStyles` lists it.
    - The background file is byte-identical to the source.
    - `scheme.json`'s `name` equals `<Name>`.
  - **Taken:**
    - A name with a user style folder already present returns `taken`, and that folder is byte-for-byte unchanged.
    - A bundled name (`sober`) returns `taken`, and no `styles\sober` appears under the data root.
  - **Invalid:** `'..'`, `'a b'` and `'create'` return `invalid` (the last only after Task 7 adds `create` to the subcommands; mark it pending until then).
  - **Failure:** when the source image is deleted between validation and copy, `failed` comes back, and no partial `styles\<Name>` folder is left behind.
  - **Theme fields:** `New-CreatedThemeObject` sets `tabTitle` `'MY-STYLE'` for `'my-style'` and keeps the `{{BACKGROUND_IMAGE}}` placeholder.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement it.** Build the style in a sibling temp folder (`styles\.creating-<guid>`), then rename it into place. On any failure, delete the temp folder and return `failed` with the reason. JSON is written UTF-8 without a BOM. `prompt.sh` is written with LF line endings.
- [ ] **Step 4: Run them; they pass.**
- [ ] **Step 5: Commit.**

### Task 5: The creator's state, and the live preview

**Files:**
- Create: `lib/creator.ps1` (state functions and preview)
- Test: `tests/Creator-State.Tests.ps1`, `tests/Creator-Preview.Tests.ps1`

**Interfaces:**
- Consumes: `New-PaletteFromPixels`, `Get-PaletteAccent` (Task 2), `New-CreatedThemeObject` (Task 4), `Merge-StyleIntoSettings`, `New-FilePreviewSession`, `Write-FilePreview`, `Restore-FilePreview`, `Get-SchemeOscPacket`.
- Produces: `New-CreatorState -Pixels <int[]> -ImagePath <string>` -> `[hashtable]` with these keys:
  - `Step` (0..4), `ImagePath`, `Pixels`, `Scheme`, `Edited` (set of slot names);
  - `ImageOpacity` (default 0.35), `StretchMode` (`uniformToFill`), `Alignment` (`center`);
  - `FontFace` (`Cascadia Code`), `FontSize` (11), `CursorShape` (`bar`);
  - `PromptShape` (`minimal`), `Symbol` (`$`), `PromptPathColor` (accent), `PromptSymbolColor` (foreground);
  - `Name` (`$null`).
- Produces: `Set-CreatorColor -State -Slot <string> -Hex <#rrggbb>`, which adds `Slot` to `Edited`.
- Produces: `Update-CreatorPalette -State`, which re-pulls from `Pixels`, replacing only the slots not in `Edited`.
- Produces: `Get-CreatorWarnings -State` -> `[string[]]`, one line per unreadable slot from `Get-SchemeUnreadableSlots`, plus foreground contrast below 7.
- Produces: `Write-CreatorPreview -State -Session -ScratchDir -Target <string> -OriginalJson <string>`, which:
  - writes `scheme.json` and `theme.json` into `ScratchDir`;
  - merges them with `-BackgroundImage $State.ImagePath -BackgroundImageProvided $true`;
  - calls `Write-FilePreview`.

- [ ] **Step 1: Write the failing state tests.**
  - Defaults are as listed above.
  - `Set-CreatorColor` changes `Scheme.red` and records `red` in `Edited`.
  - `Update-CreatorPalette` after editing `red` leaves `red` as edited and refreshes the rest.
  - Setting `red` to the background's colour produces a warning that names `red`, and the edit is kept (allowed, not blocked).
- [ ] **Step 2: Write the failing preview tests.** Use a sandboxed data root, a `settings.json` in `$TestDrive` with a `PowerShell` profile, and a session from `New-FilePreviewSession -Kind WindowsTerminal -By creator` (add `creator` to that function's `ValidateSet`).
  - **One write:** after one `Write-CreatorPreview`, the target profile's `backgroundImage` is the image path, `backgroundImageOpacity` is 0.35, and `font.face` is `Cascadia Code`.
  - **Esc:** `Restore-FilePreview -Session $s -End` puts `settings.json` back byte-identical to the original.
  - **Closed tab (Review Focus 4):** drop the session without restoring, then call `Restore-AbandonedFilePreview -Kind WindowsTerminal -Path <settings>`. Its status is `restored`, and the bytes are the original.
- [ ] **Step 3: Run them and confirm they fail.**
- [ ] **Step 4: Implement them.** In `Write-CreatorPreview`, build the theme through `New-CreatedThemeObject` with a placeholder name, so the preview and the saved style come from the same writer.
- [ ] **Step 5: Run them, plus `tests/FilePreviewSession.Tests.ps1` (the ValidateSet change); all pass.**
- [ ] **Step 6: Commit.**

### Task 6: Pages and keys (pure engine)

**Files:**
- Modify: `lib/creator.ps1`
- Test: `tests/Creator-Engine.Tests.ps1`

**Interfaces:**
- Consumes: Task 5's state functions, `Get-StylePromptShapes` / `Get-StylePromptSymbols` (Task 3), and `Test-StyleNameValid` / `Get-StyleDir`.
- Produces: `Invoke-CreatorKey -State <hashtable> -Key <ConsoleKeyInfo|string> [-Text <string>]` -> `@{ State; Action }`. `Action` is one of `none`, `preview` (state changed and needs a preview write), `next`, `back`, `cancel`, `save`, or `error:<message>`.
  - Up/Down choose a control on the current page; Left/Right change it.
  - Enter moves to the next step; Backspace returns to the previous one; Esc cancels.
  - On step 0, the path is typed in a text field.
  - On step 4, Enter with the name filled in returns `save`.
- Produces: `ConvertFrom-PastedPath -Text <string>` -> `<string>`. It trims whitespace and one pair of surrounding `"` or `'`.
- Produces: `Get-CreatorPageLines -State` -> `[string[]]`: the page's controls, then the fixed sample session. That is the prompt rendered by the chosen shape (folder `projects`, branch `main`), a `git status` with one `modified: readme.md` and one `deleted:  old.txt`, an `ls` showing `src  docs  build.ps1`, and a prompt with the cursor. It contains no live data from the user's folder.

- [ ] **Step 1: Write the failing tests.**
  - **Pasted path (Review Focus 1):** `ConvertFrom-PastedPath '"C:\My Pictures\city.png"'` returns `C:\My Pictures\city.png`.
  - **Navigation:**
    - Enter on step 1 returns `next`, with `Step` 2.
    - Backspace on step 2 returns `back`, with `Step` 1.
    - Backspace on step 0 changes nothing.
    - Esc returns `cancel` on every step.
  - **Bad image (Review Focus 5):** Enter on step 0 with a path that `Read-ImagePixels` throws for returns `error:Not an image TerminalStyles can read: ...`, and `Step` stays 0. Inject the reader as a scriptblock parameter.
  - **Taken name:** step 4 with Name `sober` and Enter returns `error:` naming `sober` as taken; with a free valid name it returns `save`.
  - **Changes need a preview:** Left/Right on a colour slot on step 1 returns `preview` and records the slot as edited.
  - **Image settings:** after a good image, on step 0, Down then Right changes `ImageOpacity` by 0.05 (clamped to 0..1) and returns `preview`. The fit and alignment controls cycle through WT's values.
  - **Font and cursor:** Right on font size on step 2 adds 1 (clamped to 6..36) and returns `preview`. The cursor shape cycles `bar`, `vintage`, `underscore`, `filledBox`, `emptyBox`, `doubleUnderscore`.
  - **Fixed sample:** `Get-CreatorPageLines` for step 3 with shape `git` and symbol U+276F contains `projects`, `(main)` and U+276F. It never contains `$PWD`'s leaf.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement them.** Colour editing on step 1: Up/Down choose the slot (21 slots); Left/Right move lightness by 3%; Shift+Left/Right move hue by 10 degrees; `H` opens hex entry; `P` re-pulls (`Update-CreatorPalette`). Show warnings from `Get-CreatorWarnings` under the controls.
- [ ] **Step 4: Run them; they pass.**
- [ ] **Step 5: Commit.**

### Task 7: The interactive command, wiring and docs

**Files:**
- Modify: `lib/creator.ps1` (add `Invoke-TerminalStyleCreate`)
- Modify: `tstyles.ps1`: add `'create'` to `$script:TStylesSubcommands`, and dispatch `if ($Arg -eq 'create') { Invoke-TerminalStyleCreate; return }` next to `tune`
- Modify: `lib/help.ps1` (a `create` topic and a line in the overview), `CHANGELOG.md` ([Unreleased], `### Added`), and `README.md` (one line in the commands list)
- Test: `tests/Invoke-TerminalStyleCreate.Tests.ps1`, plus re-enabling Task 4's pending `'create'` case

**Interfaces:**
- Consumes: everything above, plus `Find-WTSettingsPath`, `Restore-AbandonedFilePreview`, `Show-FilePreviewResult`, `Save-SettingsBackup`, `Write-HostOscPacket`, `Get-RevertOscPacket`, and the normal apply (`Invoke-TerminalStyle -Arg <name>`).
- Produces: `Invoke-TerminalStyleCreate` (no parameters). The loop:
  1. Run the guards.
  2. Recover a previous preview, then take a backup.
  3. Clear the screen and draw `Get-CreatorPageLines`, then read a key and call `Invoke-CreatorKey`.
  4. On `preview`, emit OSC and run a **debounced** `Write-CreatorPreview`, the same 50 ms poll pattern as the tuner.
  5. On `cancel`, restore through the session and the revert OSC packet, and print `Cancelled. Your terminal is back as it was.`
  6. On `save`, finish the session, call `Save-CreatedStyle`, and on `saved` apply it and print `Created '<name>' and applied it.` On `taken`, `invalid` or `failed`, print the reason and keep the user on step 4.

- [ ] **Step 1: Write the failing tests.**
  - **Redirected input:** with `[Console]::IsInputRedirected` true (test through a seam, as the tuner's guard tests do), it prints `needs an interactive terminal`, and `Write-FilePreview` is never called.
  - **Not Windows Terminal:** with `Get-TerminalKind` mocked to `iTerm2`, it prints `tstyles create needs Windows Terminal for now` and touches nothing. (Spec's builder choice: refuse, rather than colours-only.)
  - **Dispatch and help:** `'create'` is in `$script:TStylesSubcommands`. `Invoke-TerminalStyle -Arg create` calls `Invoke-TerminalStyleCreate` (mocked). `tstyles help create` prints the topic. Tab completion offers `create`, through the same `& (Get-Module TerminalStyles)` pattern as `tests/TabCompletion-Quoting.Tests.ps1`.
  - **Save path:** with `Invoke-CreatorKey` driven by a scripted key list, `Save-CreatedStyle` mocked to `saved`, and the apply mocked, the output contains `Created 'probe' and applied it.` With `taken`, it doesn't, and the loop stays on step 4.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement it.** Mirror the tuner's structure for the guards, the recovery, `Clear-Host` timing and the held update notice. Check every printed message against what happened.
- [ ] **Step 4: Run the full suite (`run-pester.sh <worktree>`); all pass.** Check that no existing test assumed the old subcommand list, for example a completion or help listing count.
- [ ] **Step 5: Write the CHANGELOG entry, naming the mechanism and the consequence, as the file's other entries do. Note that a user style already named `create` is now shadowed by the subcommand.**
- [ ] **Step 6: Commit.**

### Task 8: Try it on a real Windows Terminal (manual, by the maintainer)

- [ ] Before release, the maintainer runs `tstyles create` on Windows from the branch build:
  1. Pick a PNG and a GIF.
  2. Change a colour, then re-pull the palette.
  3. Try each prompt shape.
  4. Press Esc once and check `settings.json` is back.
  5. Run it again and save. Then apply another style and back again with `tstyles <name>`.
- [ ] Record what was checked in the PR description. CI can't drive Windows Terminal's live reload or the look.
