# VS Code settings writer — design

**Date:** 2026-10-02
**Status:** Approved in conversation (pending spec review)
**Component:** `lib/vscode.ps1` (unchanged), new `lib/vscodewriter.ps1`, and the
apply / picker / reset / uninstall paths that call it

## Context

PRs #101, #105, #106, #108, #110 and #112 built `lib/vscode.ps1`: a pure,
text-in/text-out engine that merges a style into VS Code's `settings.json`
(`Invoke-VSCodeStyleApply`), undoes it from a **record** of what it wrote
(`Invoke-VSCodeStyleReset`), switches style-to-style without leaving residue,
identifies which VS Code-family editor a terminal belongs to
(`Get-VSCodeVariant`), and finds theme-scoped blocks that would hide the
written colours (`Get-VSCodeColorOverride`).

**Nothing outside the tests calls any of it.** `Get-TerminalCapability`'s
`VSCode` arm (`terminals.ps1:280`) still claims `OscPalette` only, with a comment
calling the file "not ours to rewrite". A style applied in VS Code's integrated
terminal dies with the tab, and none of that work reaches a user.

## Goal

When `tstyles` runs in a VS Code-family integrated terminal (Code, Code -
Insiders, VSCodium, Cursor, Windsurf), the style **persists**: new terminals and
restarts keep its colours, font and cursor. Every way of taking a style off —
Esc in the picker, switching styles, `reset`, `delete`, `uninstall`,
`tstyles vscode off` — puts `settings.json` back exactly as it was, except for
keys the user changed after we wrote them, which are kept and reported.

## Decisions (made with the maintainer, 2026-10-01/02)

| Question | Decision |
|---|---|
| Write automatically, or opt in? | **Ask once per editor, remember the answer.** Not asked when nobody can answer; nothing written then. |
| Picker preview | **Full preview** (font and cursor too), written per settled style, like Windows Terminal. |
| Does `uninstall` undo it? | **Yes**, record-based, every editor, listed in the consent prompt. |
| Structure | **Approach A**: a VS Code publisher beside WezTerm's. Rejected: B (route VS Code through the WT `$useSettingsFile` path — WT-specific profiles, schemes and a backup that throws without a WT target); C (one writer interface for all four writers first — rewrites two working writers in the same change). |
| Way to change your mind | **`tstyles vscode [on\|off]`**. |

## Non-goals

- Background images, opacity, padding, tab colour/title: VS Code has no setting
  for any of them. Those flags stay `$false` and keep being named in the
  "can't show" notice.
- Live font preview in `tstyles tune` (stays colours-only in VS Code; its final
  save does go through the new writer, because it ends in `Apply-StyleDirect`).
- Workspace `.vscode/settings.json` overriding user settings: not detected;
  the README says so.
- The existing gap where `Reset-StyleNonWT` never undoes WezTerm's module
  (`lib/applystyle.ps1:1018-1074`). Out of scope here, and **not to be copied**:
  VS Code reset is wired in this change.

## Components

### `lib/vscode.ps1` — unchanged

Stays pure. Everything below calls it; nothing below is added to it.

### `lib/vscodewriter.ps1` — new, the only file I/O for VS Code

1. **`Resolve-VSCodeTarget`** → `@{ Status; Variant; Path }`.
   `Status` is `ok`, `unknownvariant` (`Get-VSCodeVariant` returned `$null` —
   zero or several candidates; **never** defaulted to `Code`), or `nodir` (the
   editor's `User` folder does not exist; nothing is created). A missing
   `settings.json` inside an existing `User` folder is `ok`: VS Code creates the
   file lazily, so we may too. Forwards `-HomeDir` / `-AppData` /
   `-XdgConfigHome` to `Get-VSCodeSettingsPath` **by what the caller bound**
   (CLAUDE.md's splat rule; every splat variable assigned in its own scope).

2. **State store**, `<DataRoot>/vscode-state.json`, keyed by the exact variant
   names `Get-VSCodeVariant` returns:

   ```json
   {
     "Cursor": {
       "consent": "yes",
       "settingsPath": "/Users/u/Library/Application Support/Cursor/User/settings.json",
       "record": { "Style": "koholint", "Wrote": [ { "Path": ["..."], "Literal": "...", "Had": null } ], "CreatedParents": [] }
     }
   }
   ```

   - Per editor because each has its own file; Cursor's record must never be
     replayed against Code's.
   - `consent` absent = undecided. `record` `null` = nothing of ours is in the file.
   - Reset and uninstall use the **recorded** `settingsPath`, not a re-resolved
     one, so they work from any terminal.
   - **Not best-effort** (unlike `current-style.json`): see *Write order*.
   - Serialised with an explicit `-Depth` (5.1 defaults to 2) and read back so
     that one-element and empty arrays keep their shape.

3. **Consent**, `Request-VSCodeWriterConsent -Variant`. Returns the stored
   answer if there is one. Otherwise asks through `Confirm-Action` (which
   refuses when nobody can answer) and **stores the answer only if the user
   actually answered**. A refusal-for-no-console stores nothing, so the next
   interactive run asks. Prompt (ASCII only):

   ```
   Save styles to Cursor's settings.json, so new terminals keep them?
   This sets the terminal's colors, font and cursor there; `tstyles reset`
   puts back whatever was there before. Change this any time with
   `tstyles vscode on` or `tstyles vscode off`. [y/N]
   ```

4. **`Test-VSCodeWriterActive`** — the single decider: target resolves `ok`
   **and** consent is `yes`. `Get-TerminalCapability` and the publisher both
   read it, so they cannot disagree (CLAUDE.md: two implementations of one rule
   diverge).

5. **`Publish-StyleVSCodeConfig`** — the writer (see *Flows*). Returns a status;
   prints its own message. It never asks: callers request consent first, and it
   reads `Test-VSCodeWriterActive` (`declined` / `unknownvariant` / `nodir` come
   from that answer).

6. **`Reset-StyleVSCodeConfig -Variant`** — record-based undo for one editor.

### Capabilities (`terminals.ps1`)

The `VSCode` arm claims `OscPalette` always, and `Persist`, `Font`,
`CursorShape` **only when `Test-VSCodeWriterActive`**. Off (declined,
unknown editor, no folder), `Get-UnsupportedStyleField` names font and cursor
shape, which is the honest notice. A cursor shape `Get-VSCodeCursorStyle`
cannot map (writes nothing) is named too, so the claim stays true per field.

## Flows

### Write order (every write to `settings.json`)

1. Read the file (`[File]::ReadAllText`; missing → `''`).
2. Compute with `Invoke-VSCodeStyleApply` / `-Reset`. A non-`applied` status
   (`rootnotobject`, `unterminated`, …) → outcome **wontparse**, nothing written.
3. First write of this command or picker session: rolling byte copy to
   `settings.json.tstyles.bak` beside it (`Copy-Item`, keeps a BOM).
4. **Save the new record to the state file.**
5. `Write-SettingsAtomic` (keeps the file's BOM, writes through a symlink,
   temp + replace).
6. If 5 throws: put the previous record back, outcome **writefailed**.

Record before file means a crash can leave a record that names keys not yet
written (reset then reports them as kept — harmless), and never a key in the
file that no record can name.

### Direct apply — `tstyles <name>`, `random`, `tune` save, `delete` revealing another style

`Apply-StyleNonWT` calls `Publish-StyleVSCodeConfig` right after
`Publish-StyleWezTermConfig` (`lib/applystyle.ps1:~799`). When the kind is
`VSCode`, `Apply-StyleNonWT` calls `Request-VSCodeWriterConsent` near its top,
**before** `Show-UnsupportedStyleField` runs, so the notice reflects the answer.
The publisher applies to the current file with
`-PreviousRecord <stored record>`.

### Picker

- **Open** (`$termKind -eq 'VSCode'`): request consent before the picker draws.
  If active: keep `$originalVSCodeText` (exact), `$startRecord` (stored), and
  `$onDiskRecord = $startRecord`.
- **Each settled preview `i`** (beside `$previewWezTerm`, called from
  `$applyTheme`): `Invoke-VSCodeStyleApply -Text $originalVSCodeText
  -PreviousRecord $startRecord` — always from the original, never chained.
  Cache text **and** record per index. Write the text; set `$lastWrittenText`
  and `$onDiskRecord` to the preview's. The state file is **not** touched.
- **Enter** (beside the picker's `Publish-StyleWezTermConfig`,
  `tstyles.ps1:~1923`): `Publish-StyleVSCodeConfig -OnDiskRecord $onDiskRecord`
  — apply the chosen style **to the file as it is on disk**, undoing what is on
  disk by the record that describes it. With no edits this is byte-identical to
  a direct apply from the starting point (undo is an exact inverse — pinned by
  existing tests); with a mid-picker edit to a key we wrote, that edit is kept
  and reported instead of overwritten.
- **Esc / Ctrl+C / exception** (`$restoreOriginalLook`, and the `finally` at
  `tstyles.ps1:~2053`): if a preview was written **and** the file still equals
  `$lastWrittenText`, write `$originalVSCodeText` back (byte-exact). If the
  file changed under us: undo the preview by `$onDiskRecord` from the current
  file, re-apply the starting style (`$startRecord.Style`) if there was one and
  it still exists, save that record, and say the file was edited during the
  picker so it was merged rather than restored.

### Reset — `tstyles reset` in a VS Code terminal

`Reset-StyleNonWT` calls `Reset-StyleVSCodeConfig -Variant <this editor>`:
undo from the record, write, clear the record, list kept keys. From any other
terminal, reset leaves VS Code alone (reset is per terminal today).

### Delete

No new code. `delete` already applies or resets when the deleted style was
active (`lib/deletestyle.ps1:1008-1014`), and the record does not need the
style to exist.

### Uninstall (`lib/update.ps1`)

For **every** editor in the state file with a non-null record: the consent
listing gains `- Take the TerminalStyles style back out of <settingsPath>`,
and the line `Will NOT modify Windows Terminal's settings.json` stays true as
written. After confirmation, each is undone via `Reset-StyleVSCodeConfig` and
kept keys are reported. Then the state file is removed with the rest of the
data root only under `-DeleteData`, as today.

### `tstyles vscode [on|off]`

- no argument: this editor's variant, settings path, consent, applied style
  (or the reason the target does not resolve); outside a VS Code terminal,
  every editor in the state file.
- `on`: consent `yes`; says it takes effect from the next apply (applies
  nothing itself).
- `off`: undo as reset does, then consent `no`.
- `on`/`off` outside an identifiable VS Code terminal: refuse and say why.

## Outcomes and messages

Statuses, never collapsed to a boolean (CLAUDE.md: every message is a claim).

| Status | Message | State |
|---|---|---|
| `written` | `Saved to Cursor's settings.json -- new terminals keep it.` plus each kept key: `Left <key> as you set it (changed since the last style wrote it).` | record updated |
| `declined` | none extra; the can't-show notice names font and cursor and mentions `tstyles vscode on` | unchanged |
| `unknownvariant` | `Couldn't tell which editor this terminal belongs to, so nothing was saved -- the colors apply to this terminal only.` | unchanged |
| `nodir` | names the expected folder; nothing created | unchanged |
| `wontparse` | names the file (the #107 wording); nothing written | unchanged |
| `writefailed` | `Could not write <path>. This terminal keeps the colors; new terminals won't.` | record rolled back |

After `written`, `Get-VSCodeColorOverride` runs on the new text; each hit
prints which theme block (`"[Monokai]"`) sets which IDs and that it wins while
that theme is active.

All new source strings are **ASCII** (`--`, not em dashes): Windows PowerShell
5.1 reads BOM-less `.ps1` in the system codepage and fails on non-ASCII string
literals.

## Documentation, same change

- `CLAUDE.md` and `terminals.ps1:26-28`: "three config writers" → four.
- README: VS Code in the supported-terminals list (persists colours, font,
  cursor; no background), the opt-in, workspace-settings caveat, the `.bak` in
  the recovery recipe (required by `tests/Contributing-MatchesCI.Tests.ps1`),
  and the uninstall section.
- `lib/help.ps1`: `tstyles help vscode`, and `reset` / `uninstall` help.
- `CHANGELOG.md` `[Unreleased]`: this, plus the unrecorded #105–#112.

## Testing

**`tests/VSCode-Writer.Tests.ps1` (unit)**
- `Resolve-VSCodeTarget`: all five variants; `unknownvariant`; `nodir`;
  missing file in existing folder is `ok`.
- **State round trip**: apply → save record → read back → reset ⇒ the original
  text, byte-identical. Includes one-element `Path`, empty `CreatedParents`,
  `Had = $null`. Must pass on both Windows CI engines.
- Consent: asked once; stored only when answered; not stored when
  `Confirm-Action` (mocked) refuses for no console; `on`/`off` change it.
- Every outcome row above, its message, and its state effect; record rollback
  when `Write-SettingsAtomic` throws; BOM preserved.

**Wiring**
- The "both paths reach every publisher" assertion
  (`tests/WezTerm-Writer.Tests.ps1:639-664`) covers `Publish-StyleVSCodeConfig`.
- Picker, mirroring `WezTerm-LivePreview`: previews computed from the original;
  Esc and Ctrl+C restore exact bytes; Esc after a mid-picker edit keeps the
  edit and restores the starting style; Enter's record equals a direct apply's
  from the same start.
- Reset touches only this editor; uninstall undoes every editor and its prompt
  names each path; delete-then-reset undoes cleanly.
- `Get-TerminalCapability` VSCode arm with the writer on and off; update
  `tests/Get-TerminalCapability.Tests.ps1` writer list (`:130`) and map
  (`:144-148`).

**Sandboxing**
- Every test points home / AppData / XDG at `$TestDrive` and sandboxes the data
  root; the splat lint stays green.
- `tests/Aa-RealStateBaseline.Tests.ps1` watch list gains the real
  `settings.json` of all five editors on macOS, Linux and Windows, so a leak
  fails CI.

## Definition of done

- Both Windows CI jobs (pwsh 7 and Windows PowerShell 5.1) green. A local macOS
  pass alone does not count.
- End-to-end run with VS Code's environment faked (`TERM_PROGRAM=vscode`, an
  askpass path) against a temporary home: apply, switch, picker Esc and Enter,
  reset, `vscode off`, uninstall — `settings.json` byte-compared at each step.
- A visual check in a real VS Code terminal by the maintainer, after their
  `settings.json` has been copied aside.

## Revisions during planning (2026-10-02)

Found while writing the implementation plan against the code. Where these
disagree with a section above, these win.

1. **Backup is first-touch, not rolling.** `Save-FirstTouchBackup` writes
   `settings.json.bak-<timestamp>` only while none of our keys are in the file
   (no record for that editor). CLAUDE.md requires it for user-owned files: a
   copy taken before a later write captures a file that already carries a
   style. The CI lint cited above (`Contributing-MatchesCI`) covers only
   Windows Terminal's rolling `.bak`, so it does not apply here; the README
   recovery section still documents the VS Code copy.
2. **The real-state guard fingerprints, it does not stat.** VS Code rewrites
   `settings.json` itself (settings UI, Settings Sync), which is exactly why
   `Zz-RealStateUntouched` leaves Windows Terminal's file unwatched. The guard
   instead records, per editor file, the source text of the top-level keys the
   style plans write (`workbench.colorCustomizations` and the four
   `terminal.integrated.*` keys), derived from the plans and the variant list
   rather than typed out.
3. **Consent checks the console itself.** `Confirm-Action` returns `$false`
   both for "no" and for "nobody could be asked", so
   `Request-VSCodeWriterConsent` asks `Test-InteractiveConsole` first and
   returns `undecided` without calling it. An answer that cannot be stored is
   reported and leaves the editor `undecided`.
4. **Blank or missing files start from `{}`.** `Invoke-VSCodeStyleApply`
   refuses empty text (`rootnotobject`). A reset then leaves `{}`, which VS
   Code reads the same as an empty file; picker Esc deletes a file the picker
   created.
5. **Statuses.** The writer adds `undecided` (distinct from `declined`) and
   `statecorrupt`; `wontparse` carries a `Detail`. Switching styles splits the
   apply's `Kept` into **left** (the new style does not set the key) and
   **replaced** (it does, so the hand edit is overwritten and kept as the value
   reset restores). Measured: koholint, hand-edit fontFamily, apply eva →
   Kept names it and the file holds eva's font; reset restores the hand edit.
6. **Both directions check readability first** (`Test-VSCodeSettingsReadable`:
   a root object that closes). Measured: `Invoke-VSCodeStyleReset` on a
   truncated file reports `reset`, removes 24 keys and keeps one, splicing
   against offsets that no longer mean what the record says.
7. **Picker logic is a testable session** in `lib/vscodewriter.ps1`
   (`New-VSCodePreviewSession`, `Invoke-VSCodePreview`,
   `Restore-VSCodePreview`); the picker only wires it. Its result is computed
   before the confirm `Clear-Host` and shown after it.
8. **`tstyles font`** says "the applied style sets the font" on VS Code once
   the writer is on (`Get-FontOwner` → `style`), and names WezTerm's
   `config.font` route only on WezTerm.
9. **Measured cost.** One apply takes ~0.2-1.3 s depending on file size (388 B
   → 166 ms, 4.7 KB → 1.3 s, macOS, pwsh 7.7), so picker previews are cached
   per style and the font and cursor land a moment after the OSC colours.

10. **Two more refinements found in review.** Both I/O helpers throw their own
    message ("Could not write/read <path>: ..."), because a .NET exception is
    only statement-terminating without a caller's try. A file that exists but
    cannot be read is `wontparse` with Detail "it could not be read" (publisher,
    reset) and gets no picker session. When the settings write fails AND the
    record cannot be put back, `writefailed` carries Detail "its undo record
    could not be restored either" and says a reset may leave some of the
    previous style's settings in place.

11. **Found in the final review.**
    - **Previews keep a record.** Each preview's record is saved to the state
      file before the preview is written, and put back if the write fails; a
      record that cannot be saved writes no preview. Esc saves the starting
      record back before it writes the original text back (or removes a file
      the picker created). This replaces "The state file is **not** touched"
      under *Picker*. The reason for that sentence still holds: a preview is
      not an apply, and after Esc the stored record is the one the picker
      found — put back now, rather than never moved. What it missed is a
      picker that never reaches Esc or its `finally`: closing the terminal
      tab, Kill Terminal and quitting VS Code all end pwsh on SIGHUP, and the
      preview left behind was named by no record. `reset` then said
      `norecord`, or, with a style on before, stranded the preview's keys
      behind false "Left ... as you set it" lines. A failed Esc puts the
      preview's record back only if it had moved it, so its message promises
      a reset only while a record that can do it is on file.
    - **`lib/vscode.ps1` changed after all**, in `Get-VSCodeVariant` only, and
      is still pure. A trailing `.exe` is stripped as `.app` is, and
      `Microsoft VS Code` and `Microsoft VS Code Insiders`, the Windows
      install folders, name Code and Code - Insiders. No Windows install of
      either was identified before.
    - **`unknownvariant` says** "Couldn't tell which editor this terminal
      belongs to, so nothing was saved to its settings.json." The Outcomes
      table's "-- the colors apply to this terminal only" is false wherever
      the shell loader is registered.
    - **`Request-VSCodeWriterConsent` takes no parameters.** §Components.3
      showed `-Variant` and the stored answer coming back; the shipped
      function resolves the editor itself and returns the writer status,
      read from `Get-VSCodeWriterState`.

Found, not fixed here (pre-existing, reported separately): the picker's
confirm on non-Windows-Terminal terminals prints the "can't show" notice
twice, and `Publish-StyleWezTermConfig`'s notices in the picker are printed
above a `Clear-Host` that wipes them.
