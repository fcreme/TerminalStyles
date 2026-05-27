# Installer UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current flat installer output with a branded banner + checked step list + bordered "Ready" panel, and drop the "open a new tab" caveat by dot-sourcing `tstyles.ps1` at the end so `tstyles` works immediately in the same tab.

**Architecture:** Three new output helper functions (`Write-InstallBanner`, `Write-InstallStep`, `Write-InstallPanel`) added near the top of `install.ps1`. The existing install flow swaps its bare `Write-Host` calls for these helpers. One new line at the end dot-sources the freshly-installed `tstyles.ps1` into the current scope. One short README paragraph updated. No code outside `install.ps1` and `README.md` changes.

**Tech Stack:** PowerShell 5.1+ (single-source, both pwsh 7 and Windows PowerShell 5.1). Box-drawing chars (┌─┐│└┘, ✓, →) — Cascadia Mono / Consolas / Windows Terminal default font handle them. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-install-ux-design.md`

---

## File Structure

Two files modified. Helpers and call sites live in the same file (`install.ps1`) because they change together and the script is small enough to read top-to-bottom.

- **Modify:** `install.ps1` — add 3 helper functions near the top, rewrite the bare `Write-Host` call sites to use them, add the dot-source at the end. Net change: ~80 lines added, ~10 lines removed.
- **Modify:** `README.md:55` — one-paragraph update to the post-install instructions.
- **No change:** `tstyles.ps1`, `apply.ps1`, the picker (`Invoke-TerminalStyle`), any test file, the workflow file. The picker is invoked by `tstyles` after install — its own UX isn't in scope.

---

## Task 1: Add the three output helper functions to `install.ps1`

**Files:**
- Modify: `install.ps1` (insert near the top, after the `$loaderBody` heredoc at line 36, before `Write-Host ""` at line 38)

Add three pure-output functions that the rewritten install flow (Task 2) will call. After this task, `install.ps1` still runs identically to today — the new functions are defined but uncalled.

- [ ] **Step 1: Insert the helpers**

Open `install.ps1`. Find the existing block (currently lines 30-37):

```powershell
$loaderBegin = '# ===== TerminalStyles BEGIN ====='
$loaderEnd   = '# ===== TerminalStyles END ====='
$loaderBody  = @"
$loaderBegin
. "`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"
$loaderEnd
"@

Write-Host ""
```

Insert these three functions between the closing `"@` of `$loaderBody` and the `Write-Host ""` line:

```powershell
# --- Output helpers ---
# Branded banner + step list + bordered "Ready" panel. Pure string
# composition with ANSI colors; safe on both pwsh 7 and WinPS 5.1, and
# uses box-drawing characters supported by Cascadia Mono / Consolas
# (Windows Terminal's default fonts).

function Write-InstallBanner {
    # Cyan rule + wordmark + tagline + cyan rule.
    $rule = '─' * 52
    Write-Host ''
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host '   tstyles' -ForegroundColor White -NoNewline
    Write-Host '  ·  Windows Terminal themes for pwsh' -ForegroundColor DarkGray
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host ''
}

function Write-InstallStep {
    # Single-line step indicator. -Check appends a green checkmark to
    # signal completion of an action whose "in progress" version printed
    # on the previous line.
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Check
    )
    Write-Host '  → ' -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -NoNewline
    if ($Check) {
        Write-Host ' ✓' -ForegroundColor Green
    } else {
        Write-Host ''
    }
}

function Write-InstallPanel {
    # Bordered "Ready" panel listing the count, the one command to run,
    # and all theme names wrapped to fit.
    param(
        [Parameter(Mandatory)][string[]]$ThemeNames,
        [Parameter(Mandatory)][string[]]$RegisteredEngines
    )
    $width = 56   # interior width, between │ chars (not counting them)

    # Borders -- both 58 visible chars (1 corner + 56 interior + 1 corner)
    $labelPart = '─ Ready '                                  # 8 chars
    $top    = '┌' + $labelPart + ('─' * ($width - $labelPart.Length)) + '┐'
    $bottom = '└' + ('─' * $width) + '┘'

    # Row writer: writes one panel row with the leading '  ' indent,
    # green borders, and middle content padded to exactly $width chars.
    # The middle content is rendered as up to three colored segments.
    function WriteRow {
        param(
            [Parameter(Mandatory)][int]$Width,
            [Parameter(Mandatory)][string[]]$Segments,
            [string[]]$Colors
        )
        Write-Host '  │' -ForegroundColor Green -NoNewline
        $printed = 0
        for ($i = 0; $i -lt $Segments.Count; $i++) {
            $seg = $Segments[$i]
            $color = if ($Colors -and $i -lt $Colors.Count -and $Colors[$i]) { $Colors[$i] } else { $null }
            if ($color) {
                Write-Host $seg -ForegroundColor $color -NoNewline
            } else {
                Write-Host $seg -NoNewline
            }
            $printed += $seg.Length
        }
        if ($printed -lt $Width) {
            Write-Host (' ' * ($Width - $printed)) -NoNewline
        }
        Write-Host '│' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "  $top" -ForegroundColor Green

    # Row: "  N themes installed."
    WriteRow -Width $width -Segments @('  ', "$($ThemeNames.Count) themes installed.")

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Row: "      tstyles" with the command in cyan
    WriteRow -Width $width -Segments @('      ', 'tstyles') -Colors @($null, 'Cyan')

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Theme-name rows: wrap at $width chars
    $line = '  '
    foreach ($name in $ThemeNames) {
        $candidate = if ($line.Trim().Length -eq 0) { "$line$name" } else { "$line · $name" }
        if ($candidate.Length -gt $width) {
            WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
            $line = "  $name"
        } else {
            $line = $candidate
        }
    }
    if ($line.Trim().Length -gt 0) {
        WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
    }

    Write-Host "  $bottom" -ForegroundColor Green
    Write-Host ''

    # If both engines were registered, mention the one the user isn't
    # currently in -- they need a new tab for that side.
    if ($RegisteredEngines.Count -gt 1) {
        $current    = $PSVersionTable.PSEdition  # 'Core' for pwsh 7, 'Desktop' for WinPS 5.1
        $otherLabel = if ($current -eq 'Core') { 'Windows PowerShell 5.1' } else { 'PowerShell 7' }
        Write-Host "  Also wired up for $otherLabel — available in any new tab there." -ForegroundColor DarkGray
        Write-Host ''
    }
}

```

Use `Edit` with the exact anchor `$loaderEnd"@` (the closing of the heredoc plus the next `Write-Host ""` line) to insert the block before it. The new functions live in the script scope and are visible to the rest of `install.ps1`.

- [ ] **Step 2: Verify the helpers render without errors**

```powershell
pwsh -NoProfile -Command @'
. .\install.ps1 2>&1 | Out-Null  # this will fail mid-way (install runs), don't worry
'@
```

The above will actually try to run the installer (because `install.ps1` is not function-only). That's not what we want for verification. Instead, do this minimal test that loads only the helpers without triggering the install flow:

```powershell
pwsh -NoProfile -Command @'
# Extract the helper definitions and define them in isolation
$content = Get-Content .\install.ps1 -Raw
$helpersStart = $content.IndexOf('# --- Output helpers ---')
$helpersEnd   = $content.IndexOf('# --- Download ---')
$helpersBlock = $content.Substring($helpersStart, $helpersEnd - $helpersStart)
Invoke-Expression $helpersBlock

# Render each helper
Write-InstallBanner
Write-InstallStep "Downloading"
Write-InstallStep "Downloading" -Check
Write-InstallStep "Extracting" -Check
Write-InstallPanel -ThemeNames @('umbrella','eva','ex-machina','forest','garden-rain','gitbash','golden-forest','halo','kitty','lain','marquee','neon-rain','rain','snowday','sober','tombraider') -RegisteredEngines @('PowerShell 7','Windows PowerShell 5.1')
'@
```

Expected output (rendered in the terminal):

```
  ────────────────────────────────────────────────────
   tstyles  ·  Windows Terminal themes for pwsh
  ────────────────────────────────────────────────────

  → Downloading
  → Downloading ✓
  → Extracting ✓

  ┌─ Ready ────────────────────────────────────────────────┐
  │  16 themes installed.                                  │
  │                                                        │
  │      tstyles                                           │
  │                                                        │
  │  umbrella · eva · ex-machina · forest · garden-rain    │
  │  · gitbash · golden-forest · halo · kitty · lain ·     │
  │  marquee · neon-rain · rain · snowday · sober ·        │
  │  tombraider                                            │
  └────────────────────────────────────────────────────────┘

  Also wired up for Windows PowerShell 5.1 — available in any new tab there.
```

Sanity checks:
- Top and bottom borders are the same visible length.
- All `│` characters in middle rows align vertically with each other and with the corners.
- The cyan `tstyles` in the middle stands out from the rest.
- The "Also wired up for..." line prints once at the end.

If borders don't align: check the `$width` math and the `WriteRow`'s `($printed -lt $Width)` padding calculation. The most common failure mode is counting box-drawing chars as multi-byte and miscounting `.Length` — but in PowerShell, `.Length` on a `[string]` counts UTF-16 code units, and the box-drawing chars used (┌ ┐ └ ┘ ─ │) are all in the BMP, so each counts as 1.

If only one engine is in `-RegisteredEngines`, the "Also wired up for..." line should NOT print. Re-test with `-RegisteredEngines @('PowerShell 7')`.

- [ ] **Step 3: Commit**

```bash
git add install.ps1
git commit -m "$(cat <<'EOF'
Add output helpers to install.ps1 (banner, step, panel)

Three new functions (Write-InstallBanner, Write-InstallStep,
Write-InstallPanel) added near the top of install.ps1, ready to be
called by the install flow in the next commit. Pure-output -- no
behavior change yet.
EOF
)"
```

---

## Task 2: Wire the helpers into the install flow

**Files:**
- Modify: `install.ps1` (replace bare `Write-Host` call sites throughout)

Swap the existing `Write-Host` calls for the helpers added in Task 1. After this task, the installer renders the new output. The dot-source for same-tab handoff comes in Task 3.

- [ ] **Step 1: Replace the top banner**

Find this block in `install.ps1` (currently around lines 38-40):

```powershell
Write-Host ""
Write-Host "TerminalStyles installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
```

Replace with:

```powershell
Write-InstallBanner
```

- [ ] **Step 2: Replace the download/extract steps**

Find this block (currently around lines 42-49):

```powershell
# --- Download ---
Write-Host "Downloading from $zipUrl ..."
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

# --- Extract ---
Write-Host "Extracting ..."
if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
```

Replace with:

```powershell
# --- Download ---
Write-InstallStep "Downloading"
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
Write-InstallStep "Downloading" -Check

# --- Extract ---
Write-InstallStep "Extracting"
if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
Write-InstallStep "Extracting" -Check
```

- [ ] **Step 3: Replace the "Preserved" lines**

Find these two lines (currently around lines 88 and 98):

```powershell
    Write-Host "Preserved your existing style selection."
...
    Write-Host ("Preserved {0} cached background image(s)." -f $preservedBackgrounds.Count)
```

Replace them respectively with:

```powershell
    Write-InstallStep "Preserved your active style" -Check
```

and

```powershell
    Write-InstallStep ("Preserved {0} cached background(s)" -f $preservedBackgrounds.Count) -Check
```

- [ ] **Step 4: Remove the "Files installed at:" line**

Find this line (currently around line 105):

```powershell
Write-Host "Files installed at: $installDir" -ForegroundColor Green
```

**Delete it entirely.** The "Ready" panel at the end conveys success more visibly.

- [ ] **Step 5: Replace the per-shell bracket header + "Loader registered in:" line**

Find this block (currently around lines 250-258):

```powershell
$registered = @()
foreach ($s in $shells) {
    Write-Host ""
    Write-Host "[$($s.Label)]" -ForegroundColor Cyan
    $info = Get-ShellInfo -Exe $s.Exe -Label $s.Label
    if (-not $info) { continue }
    Register-LoaderInProfile -ProfilePath $info.ProfilePath -Label $s.Label -InstallDir $installDir `
        -LoaderBegin $loaderBegin -LoaderEnd $loaderEnd -LoaderBody $loaderBody
    Resolve-ExecutionPolicy -Exe $s.Exe -Label $s.Label -EffectivePolicy $info.Policy
    $registered += $s.Label
}
```

Replace with:

```powershell
$registered = @()
foreach ($s in $shells) {
    $info = Get-ShellInfo -Exe $s.Exe -Label $s.Label
    if (-not $info) { continue }
    Register-LoaderInProfile -ProfilePath $info.ProfilePath -Label $s.Label -InstallDir $installDir `
        -LoaderBegin $loaderBegin -LoaderEnd $loaderEnd -LoaderBody $loaderBody
    Resolve-ExecutionPolicy -Exe $s.Exe -Label $s.Label -EffectivePolicy $info.Policy
    Write-InstallStep "Registered loader: $($s.Label)" -Check
    $registered += $s.Label
}
```

Also find and **delete** this line inside `Register-LoaderInProfile` (currently around line 203):

```powershell
    Write-Host "  Loader registered in: $ProfilePath" -ForegroundColor Green
```

(The `Write-InstallStep "Registered loader: $($s.Label)" -Check` line we just added in the caller replaces it. The full path was only useful for debugging and is omitted from the polished output by design.)

- [ ] **Step 6: Replace the final "Done!" block with the panel**

Find this block at the end of the script (currently around lines 261-271):

```powershell
if (-not $registered) {
    throw "Neither pwsh.exe nor powershell.exe was found on PATH. Cannot register TerminalStyles loader."
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  Registered for: $($registered -join ', ')"
Write-Host "  1. Open a new tab in one of those shells (or run: . `$PROFILE)"
Write-Host "  2. Run:  tstyles"
Write-Host "     -> Arrow keys to preview each style live, Enter to keep, Esc to cancel."
Write-Host ""
```

Replace with:

```powershell
if (-not $registered) {
    throw "Neither pwsh.exe nor powershell.exe was found on PATH. Cannot register TerminalStyles loader."
}

# Gather the bundled theme names for the "Ready" panel
$themeNames = @(
    Get-ChildItem -LiteralPath (Join-Path $installDir 'styles') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
        Sort-Object Name |
        ForEach-Object Name
)

Write-InstallPanel -ThemeNames $themeNames -RegisteredEngines $registered
```

- [ ] **Step 7: Smoke-test the full installer**

Run the entire installer locally and inspect the output:

```powershell
pwsh -NoProfile -File .\install.ps1
```

Expected output (in order):

1. The banner (cyan rule, "tstyles  ·  Windows Terminal themes for pwsh", cyan rule).
2. `→ Downloading` followed by `→ Downloading ✓`.
3. `→ Extracting` followed by `→ Extracting ✓`.
4. `→ Preserved your active style ✓` (if a `current-style.ps1` was present from before).
5. `→ Preserved 16 cached background(s) ✓` (if any backgrounds were cached).
6. Possibly a dim "Note: couldn't record install SHA..." line if offline (acceptable).
7. `→ Registered loader: PowerShell 7 ✓`.
8. `→ Registered loader: Windows PowerShell 5.1 ✓`.
9. The bordered "Ready" panel with 16 themes.
10. The dim "Also wired up for ..." line.

What should be **gone** from the output: the long `Downloading from <URL> ...` line, the `Files installed at: <path>` line, the `[PowerShell 7]` bracket headers, the `Loader registered in: <full path>` lines, the numbered `1./2.` next-steps block.

If the panel borders don't align, double-check Task 1 Step 2's `WriteRow` math. If you see literal `→` or `✓` chars rendered as `?`, your font lacks the glyphs — try Cascadia Mono.

After this smoke test, `%LOCALAPPDATA%\TerminalStyles\` is freshly reinstalled. Your existing style is preserved.

- [ ] **Step 8: Commit**

```bash
git add install.ps1
git commit -m "$(cat <<'EOF'
Wire the install flow to use the new output helpers

Replaces the bare Write-Host calls in install.ps1 with the helpers
added in the previous commit:

- Top banner now uses Write-InstallBanner.
- Each install phase uses Write-InstallStep (with -Check on completion).
- Per-shell [Label] brackets removed; "Registered loader: <Label> ✓"
  step lines used instead.
- "Files installed at: <path>" and "Loader registered in: <path>" lines
  removed -- the panel makes them redundant.
- Final "Done!" + numbered list replaced with Write-InstallPanel
  showing 16 themes and the one command (tstyles).

Spec: docs/superpowers/specs/2026-05-27-install-ux-design.md
EOF
)"
```

---

## Task 3: Add the same-tab handoff

**Files:**
- Modify: `install.ps1` (append at the very end of the script)

Dot-source the freshly-installed `tstyles.ps1` so the user can run `tstyles` immediately in the same tab where they ran `iwr | iex`.

- [ ] **Step 1: Append the dot-source block**

At the very end of `install.ps1` (after `Write-InstallPanel ...` from Task 2), append:

```powershell

# --- Same-tab handoff ---
# Dot-source the freshly-installed tstyles.ps1 into the current scope
# so the user can type `tstyles` immediately without opening a new tab.
# `iwr | iex` runs this whole installer in the caller's scope, so a
# dot-source from here exposes Invoke-TerminalStyle (the function
# behind the `tstyles` command) to that scope too.
$installedLib = Join-Path $installDir 'tstyles.ps1'
if (Test-Path -LiteralPath $installedLib) {
    . $installedLib *> $null
}
```

The `*> $null` suppresses any startup output `tstyles.ps1` might print (currently none, but defensive against future load-time banners).

- [ ] **Step 2: Smoke-test the same-tab handoff**

Run the installer in a fresh pwsh tab the way a real user would (via the one-liner mechanism — but locally from the file, not from GitHub):

```powershell
pwsh -NoProfile -Command "& { . .\install.ps1; Get-Command tstyles | Format-List Name, CommandType }"
```

Expected: the installer prints all of its UI, then at the end (after the panel) the `Get-Command tstyles` shows:

```
Name        : tstyles
CommandType : Alias
```

(or `Function` for `Invoke-TerminalStyle`, depending on what `Get-Command tstyles` resolves to in `tstyles.ps1`).

Crucially: it should NOT print `Get-Command : The term 'tstyles' is not recognized`. If it does, the dot-source didn't expose the function — check that the file path resolves correctly with `Write-Host "DEBUG: $installedLib"` before the `if (Test-Path...)`.

- [ ] **Step 3: Commit**

```bash
git add install.ps1
git commit -m "$(cat <<'EOF'
install.ps1: dot-source tstyles.ps1 at end for same-tab handoff

After install, the freshly-installed tstyles.ps1 is dot-sourced into
the caller's scope. Because `iwr | iex` runs the whole installer in
the user's current shell scope, this exposes the `tstyles` command
immediately -- no need to open a new tab or run `. $PROFILE` first.

The same-tab handoff only works for the engine that ran the
installer; the other engine (if both are installed) still requires a
new tab (the "Also wired up for ..." panel note covers this).

Spec: docs/superpowers/specs/2026-05-27-install-ux-design.md
EOF
)"
```

---

## Task 4: README — update the post-install instructions

**Files:**
- Modify: `README.md` (around line 55)

The README currently tells users to open a new tab after installing. With the same-tab handoff in place, that's outdated.

- [ ] **Step 1: Find and replace the post-install paragraph**

Find this line in `README.md` (currently around line 55, immediately after the numbered installer steps list):

```
Then open a new pwsh or powershell tab (or run `. $PROFILE` to reload).
```

Replace with:

```
Once the installer finishes, you can run `tstyles` immediately in the
same tab. Any other tabs already open (and the other PowerShell engine
if both are installed) will pick it up the next time they start.
```

- [ ] **Step 2: Verify the edit**

```powershell
Select-String -Path .\README.md -Pattern 'open a new pwsh or powershell tab'
```

Expected: **no matches** (old wording is gone).

```powershell
Select-String -Path .\README.md -Pattern 'run `tstyles` immediately in the','same tab'
```

Expected: at least one hit per pattern.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
README: update post-install instructions for same-tab handoff

The installer now dot-sources tstyles.ps1 at the end (see
docs/superpowers/specs/2026-05-27-install-ux-design.md), so the
"open a new pwsh tab" step is no longer required for the engine the
user installed from. README updated to match.
EOF
)"
```

---

## Task 5: End-to-end test against a clean install + push

**Files:** None modified.

- [ ] **Step 1: Confirm the branch state**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Commits in order (most recent first):

1. `README: update post-install instructions for same-tab handoff` (Task 4)
2. `install.ps1: dot-source tstyles.ps1 at end for same-tab handoff` (Task 3)
3. `Wire the install flow to use the new output helpers` (Task 2)
4. `Add output helpers to install.ps1 (banner, step, panel)` (Task 1)
5. `Spec: installer UX polish ...` (already on main from brainstorming)

- [ ] **Step 2: Push to main**

```bash
git push origin main
```

Expected: `<prior-sha>..<HEAD-sha>  main -> main`.

- [ ] **Step 3: True end-to-end run via the one-liner mechanism**

Important: this is the most realistic test. Open a fresh Windows Terminal pwsh tab (not your dev shell) and run:

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

Expected:
1. The full new UX renders (banner, steps, panel).
2. Within ~5 seconds of the panel appearing, `tstyles` should be a valid command in that same tab — type `tstyles` (no quotes, no path) and the picker should launch.
3. Arrow up/down inside the picker previews themes live (existing behavior).
4. Press Esc to exit the picker.

If `tstyles` is NOT recognized after the installer finishes, the dot-source didn't fire. Read the installer output for any error around the same-tab handoff line.

If the panel borders look misaligned in the real Windows Terminal (vs. your earlier helper test which may have been in an editor), it may be a font issue. The default Windows Terminal font (Cascadia Mono) renders the box-drawing chars correctly; if you've configured a different font that lacks them, it's a font issue, not a code issue.

- [ ] **Step 4: Open the README on GitHub and visually confirm**

Go to https://github.com/fcreme/TerminalStyles and verify:
- The "After install you can run `tstyles` immediately in the same tab" wording is present in the README rendering.
- No broken screenshots or other regressions.

---

## Self-Review Notes

Spec coverage:

- Banner + tighter section headers + richer panel → Tasks 1 + 2.
- Dot-source `tstyles.ps1` at end → Task 3.
- README update → Task 4.
- "Also wired up for..." dim note for the other engine → Task 1 Step 1 (inside `Write-InstallPanel`).
- Theme names enumerated from `$installDir/styles/` → Task 2 Step 6.
- Mentioned but NOT in plan (correctly absent): auto-launch picker, auto-apply default theme, emoji icons, custom spinner, `apply.ps1` polish, Pester for installer.
- End-to-end real-world run validation → Task 5 Step 3.

Type / signature consistency:

- All three helper function names match between Task 1 (definitions) and Task 2 (callers).
- `-Check` is used as a switch on `Write-InstallStep` in both tasks.
- `-RegisteredEngines` and `-ThemeNames` parameter names on `Write-InstallPanel` are consistent.
- `$themeNames` variable name (Task 2 Step 6) matches `-ThemeNames` (Task 1 Step 1).
- The dot-source path `$installedLib = Join-Path $installDir 'tstyles.ps1'` (Task 3) uses `$installDir` defined at the top of the script (line 25).

No placeholders. All commands have expected output. All code blocks contain the actual content to paste.

Two judgment calls worth flagging:

- **Task 2's smoke test (Step 7) actually reinstalls TerminalStyles** on the user's machine. This is acceptable because the existing `current-style.ps1` and cached backgrounds are preserved by the installer. The user's active theme stays the same.
- **Task 5's Step 3 hits the live GitHub raw URL.** This will only work AFTER Step 2 pushes the new install.ps1 to `main`. If the user wants to test against the local repo's install.ps1 first (before pushing), they can substitute `pwsh -NoProfile -File .\install.ps1` for the `iwr | iex` line — same effect except for the URL fetch.
