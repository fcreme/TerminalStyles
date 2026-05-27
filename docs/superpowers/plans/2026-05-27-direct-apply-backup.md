# Direct-Apply Backup Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a rolling `settings.json.bak` written by `Apply-StyleDirect` (`tstyles <name>` and `tstyles random`) before each settings.json mutation, so the user can recover from a bad direct apply with a one-line `Copy-Item`.

**Architecture:** One `Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak" -Force` inserted into `Apply-StyleDirect` immediately after the target-profile auto-detect and before the merge. Wrapped in `try/catch` so backup failure (read-only volume, AV interference, disk full) warns but doesn't block the apply. Picker stays untouched (it has in-memory revert on Esc). `apply.ps1` stays untouched (its timestamped backup serves the audit-trail use case).

**Tech Stack:** PowerShell 5.1+ (single-source, both engines). No new dependencies. No tests added — deferred to a future Pester cohort with `Test-UpdateAvailable`.

**Spec:** `docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md`

---

## File Structure

Single-file production change plus a small README update. No new files.

- **Modify:** `tstyles.ps1` — `Apply-StyleDirect` (lines 456-529). Add an 8-line `try/catch` backup block between the target auto-detect (line 489) and the merge (line 491). Function signature, name, return paths, and all callers unchanged.
- **Modify:** `README.md` — add one short subsection under the existing `## Scriptable / non-interactive` heading documenting the rolling backup and the restore one-liner. Refresh the wording near line 297 so the "one-time backup" claim that applies to `apply.ps1` doesn't read as if it covers `tstyles <name>`.
- **No change:** `apply.ps1` (its timestamped backup serves a different use case). The picker in `Invoke-TerminalStyle` (already byte-safe via in-memory Esc revert). `install.ps1`. Anything in `tests/`.

---

## Task 1: Add the backup block to `Apply-StyleDirect`

**Files:**
- Modify: `tstyles.ps1:489-491` (insert between)

The change is one self-contained block. The existing code on either side stays byte-identical.

- [ ] **Step 1: Insert the backup block**

Open `tstyles.ps1`. Find the existing `Apply-StyleDirect` function. Locate these three consecutive non-blank lines (currently around lines 487-491):

```powershell
        Write-Error "Could not auto-detect a Windows Terminal profile. Pass -Target <name>."
        return
    }

    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
```

Replace **exactly that span** (from the `Write-Error` line through the blank line before `$settings = Merge-StyleIntoSettings`) with:

```powershell
        Write-Error "Could not auto-detect a Windows Terminal profile. Pass -Target <name>."
        return
    }

    # Rolling backup: copy the on-disk settings.json to settings.json.bak
    # before any mutation. Single file, overwritten on each direct apply --
    # gives the user a one-line undo without filling LocalState with timestamped
    # backups over time. The picker doesn't need this (Esc reverts in-memory);
    # apply.ps1 keeps its own timestamped audit trail. -ErrorAction Stop so
    # non-terminating errors (permission denied, etc.) enter the catch block
    # rather than silently logging via $Error.
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor DarkGray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
```

Use `Edit` with the exact old/new strings above. Both old and new strings should be unique in the file (the `Write-Error "Could not auto-detect..."` text appears only here).

Verify visually that the block is now inside `Apply-StyleDirect` (not accidentally injected into another function) by reading a 30-line window starting from line 482.

- [ ] **Step 2: Sanity-check the file parses**

Run:

```powershell
pwsh -NoProfile -Command "Get-Command -Syntax (Get-Command Invoke-TerminalStyle -Module $null -ErrorAction SilentlyContinue) 2>&1; if (\$LASTEXITCODE) { exit \$LASTEXITCODE }; \$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw .\tstyles.ps1), [ref]\$null); Write-Host 'tstyles.ps1 parses cleanly'"
```

Expected: prints `tstyles.ps1 parses cleanly` with no errors. If you get parser errors, your `Edit` introduced a syntax problem — revert and try again.

Simpler alternative if the above is fiddly: just `pwsh -NoProfile -Command ". .\tstyles.ps1; Write-Host 'sourced OK'"` from the repo root.

- [ ] **Step 3: Smoke-test against a real install**

```powershell
# Copy the modified library into LOCALAPPDATA so the installed tstyles uses it
Copy-Item .\tstyles.ps1 "$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1" -Force

# Note the current settings.json state
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$preHash = (Get-FileHash $wt).Hash
$preMod  = (Get-Item $wt).LastWriteTime

# Remove any prior .bak so we know this run created it
Remove-Item "$wt.bak" -ErrorAction SilentlyContinue

# Pick a style you're NOT currently using; if you're on umbrella, switch to eva
. $PROFILE
tstyles eva
```

Expected output includes:

```
Backed up settings to: C:\Users\felip\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.bak
...
  Style applied: eva
```

Verify:

```powershell
Test-Path "$wt.bak"                                          # True
(Get-FileHash "$wt.bak").Hash -eq $preHash                   # True (.bak holds prior content)
(Get-FileHash $wt).Hash -ne $preHash                         # True (settings.json was changed by the apply)
```

If any of those assertions are False, stop and diagnose. The backup must hold the *prior* state and `settings.json` must hold the new state.

- [ ] **Step 4: Smoke-test the rolling overwrite**

Immediately after Step 3:

```powershell
$bakHashAfterEva = (Get-FileHash "$wt.bak").Hash    # snapshot the eva-pre-state
tstyles golden-forest
(Get-FileHash "$wt.bak").Hash -ne $bakHashAfterEva  # True -- bak was rewritten
```

Expected: `True`. The `.bak` should now hold the post-eva state (which became the pre-golden-forest state), proving rolling semantics.

- [ ] **Step 5: Smoke-test the read-only fallback**

```powershell
# Make .bak read-only so Copy-Item -Force fails (it can't overwrite read-only by default)
attrib +R "$wt.bak"
tstyles eva   # should print the yellow warning, still apply
attrib -R "$wt.bak"
```

Expected output includes:

```
Warning: could not write backup (Access to the path '...settings.json.bak' is denied. ...); proceeding anyway.
...
  Style applied: eva
```

And `settings.json` should still hold the new eva state (verify with another `Get-FileHash` comparison if you want). If the warning didn't fire, `-ErrorAction Stop` is missing from the `Copy-Item` call — re-check Step 1.

- [ ] **Step 6: Smoke-test that the picker is unaffected**

```powershell
Remove-Item "$wt.bak" -ErrorAction SilentlyContinue
tstyles      # opens the picker; pick a theme with arrow keys, hit Enter to confirm
Test-Path "$wt.bak"     # should be False (picker doesn't create .bak)
```

Expected: `False`. If the picker ever started writing `.bak`, you've put the backup block in the wrong function.

- [ ] **Step 7: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Add rolling settings.json.bak to Apply-StyleDirect

tstyles <name> and tstyles random previously overwrote settings.json
with no backup. Now write a single rolling settings.json.bak alongside
it before each merge so the user can recover with a one-line Copy-Item.

The picker stays as-is (in-memory revert on Esc covers it). apply.ps1
stays as-is (its timestamped backup serves the audit-trail use case).
Backup failure (read-only volume, AV, disk full) warns yellow and
proceeds rather than blocking the apply.

Spec: docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md
EOF
)"
```

---

## Task 2: README — document the rolling backup and restore one-liner

**Files:**
- Modify: `README.md:287-299` (the existing `## Scriptable / non-interactive` section)

The existing section discusses `apply.ps1`'s backup behavior. Two small additions: refine the wording so it's clear the "one-time backup" claim refers only to `apply.ps1`, and add a short paragraph documenting the `tstyles <name>` rolling backup with the restore command.

- [ ] **Step 1: Refine the existing `apply.ps1` mention**

Find this paragraph in `README.md` (currently lines 296-299):

```
`apply.ps1` is the same logic as the interactive picker but driven
entirely by flags, with a one-time backup of `settings.json` and
`$PROFILE` before applying. See `apply.ps1 -?` for the full parameter
list.
```

Replace with:

```
`apply.ps1` is the same logic as the interactive picker but driven
entirely by flags. It writes a timestamped `settings.json.bak-<timestamp>`
(and a `$PROFILE.bak-<timestamp>` when overwriting one) before applying,
keeping a full audit trail of every run. See `apply.ps1 -?` for the
full parameter list.
```

The wording change: "one-time backup" → "timestamped `settings.json.bak-<timestamp>` ... keeping a full audit trail of every run." This disambiguates from the rolling backup added in the next paragraph and is more accurate ("one-time" was misleading — `apply.ps1` actually writes a new timestamped file per run).

- [ ] **Step 2: Add the new subsection**

Immediately after the paragraph from Step 1 (still inside `## Scriptable / non-interactive`, before the next `## Updating` heading), insert:

```markdown

### Recovering from a bad direct apply

`tstyles <name>` and `tstyles random` write a rolling backup to
`settings.json.bak` (no timestamp — overwritten on each direct apply)
in the same directory as `settings.json` before each change. To restore
the last-known-good state:

```powershell
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Copy-Item "$wt.bak" $wt -Force
```

The picker (`tstyles` with no arg) doesn't write a `.bak` — pressing
Esc reverts in-memory to the exact prior bytes. If you need a full
history of changes (rather than just "undo the most recent direct
apply"), use `apply.ps1` instead — it keeps timestamped backups per run.
```

Note: the nested ` ```powershell ` block inside the new subsection works
in GitHub-flavored Markdown. The outer fence is a heading-introduced
plain text block, not a code fence — there's no fence-nesting issue.
Use `Edit` with the exact paragraph from Step 1 as your anchor (search
for it, then append the new subsection right after).

- [ ] **Step 3: Verify both changes**

Run:

```powershell
Select-String -Path .\README.md -Pattern 'one-time backup'
```

Expected: **no matches** (the old wording is gone).

```powershell
Select-String -Path .\README.md -Pattern 'rolling backup','Recovering from a bad direct apply','timestamped audit trail|full audit trail'
```

Expected: at least three hits — one for each of the new strings.

Open `README.md` in your editor and visually scan the new subsection
renders well (headings nest correctly, the code block has matching
fences). GitHub will render it as soon as you push.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
README: document rolling settings.json.bak and restore one-liner

Adds a "Recovering from a bad direct apply" subsection to Scriptable /
non-interactive explaining the rolling backup written by Apply-StyleDirect
and how to restore from it. Also refines the apply.ps1 wording from
"one-time backup" to "timestamped settings.json.bak-<timestamp>" since
the prior phrasing implied apply.ps1 keeps only one backup (it actually
keeps one per run).
EOF
)"
```

---

## Task 3: Final verification + push

**Files:** None modified. Push only.

The user is committing straight to `main` (no feature branch, no PR), matching the prior throttle plan's workflow.

- [ ] **Step 1: Confirm branch state**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Commits in order (top to bottom):

1. `README: document rolling settings.json.bak and restore one-liner` (Task 2)
2. `Add rolling settings.json.bak to Apply-StyleDirect` (Task 1)
3. `Spec: rolling settings.json.bak for non-picker applies` (already committed during brainstorming)

- [ ] **Step 2: Push**

```bash
git push origin main
```

Expected: `c819a7b..<HEAD-sha>  main -> main` or similar (range from the prior push to the new HEAD).

- [ ] **Step 3: Verify the live install picked up the change**

If you already copied the modified `tstyles.ps1` to `%LOCALAPPDATA%` during Task 1 Step 3, it's already there. If you skipped that copy (e.g. ran the smoke tests against the dev repo only), `tstyles update` would now pull it from origin:

```powershell
tstyles update
```

Expected: install one-liner runs to completion, `.installed-sha` is rewritten to the new HEAD.

Then run one direct apply to confirm the production install behaves as
designed:

```powershell
Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.bak" -ErrorAction SilentlyContinue
tstyles random
Get-Item "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.bak" | Select-Object Name, Length, LastWriteTime
```

Expected: the gray `Backed up settings to: ...` line printed during the
apply; `.bak` exists with a fresh `LastWriteTime` and non-zero `Length`.

---

## Self-Review Notes

Spec coverage:

- Goal: rolling backup for direct applies → Task 1.
- Backup failure doesn't block → Task 1 (try/catch with yellow warning) + Task 1 Step 5 (read-only smoke test).
- One-line restore via `Copy-Item` → Task 2 (README).
- Picker unchanged → confirmed by Task 1 Step 6 (smoke test against the picker).
- `apply.ps1` unchanged → out of scope, no task.
- No new subcommand, no Pester → no tasks for those (correctly absent).

Type / signature consistency:

- Variable name `$bakPath` consistent within Task 1.
- `Copy-Item -LiteralPath ... -Destination ... -Force -ErrorAction Stop` — all four arguments in every reference.
- Backup-file path convention: `"$settingsPath.bak"` everywhere (interpolated string append, matches the project's convention).

No placeholders. All commands have expected output. All code blocks are complete and contain the actual content to paste.

One judgment call worth flagging:

- **Task 1 Step 1 instructs replacing a 5-line span rather than inserting between two lines.** This is intentional — `Edit` requires unique `old_string` matches, and the easiest unique anchor here is the `Write-Error "Could not auto-detect..."` text combined with the line immediately following the existing `}`. The replacement span is larger than the minimum needed but the old-text portion is preserved verbatim inside the new text, so the diff stays clean.
