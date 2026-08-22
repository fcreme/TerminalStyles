# Recording the demo

A 10–15 second screen recording of TerminalStyles switching themes live.
`scripts/demo.ps1` removes everything that makes one take differ from the next;
you bring the screen recorder.

Nothing here simulates the product. The picker on camera is the real picker, the
colors are the OSC packets it really emits, and in `-Mode Auto` the arrow keys
are real key events delivered through a real pty.

---

## What actually changes on camera

Read this before planning a shot. It is not the same on every platform.

| | Windows Terminal | macOS Terminal.app |
|---|---|---|
| 16-color palette, foreground, background | live, instantly | live, instantly |
| Cursor **color** | live | live |
| Prompt + ASCII banner | on confirm | on confirm |
| Background image | live, **animated GIF** | new window only, **still frame** |
| Font, opacity, cursor **shape** | live | new window only |

On macOS the recordable demo is **color**, and it is genuinely striking — every
arrow keypress repaints the whole window in under 5 ms. But animated backgrounds
do not exist there: Terminal.app renders a still image and never animates a GIF,
which is why a `.terminal` profile ships an extracted first frame. If the video
needs animated backgrounds, record it on Windows Terminal.

Also worth knowing: all 16 bundled styles use Cascadia Code 11 and differ only in
weight, so "watch the font change" is not a shot this repo can honestly sell.
Font switching lives in `tstyles font` / `tstyles tune`, which is a different
demo.

---

## 1. Window preparation

- Close other tabs and split panes. One window, nothing else on screen.
- Terminal → Settings → Profiles → **Basic** (or any plain profile). The demo
  resets colors anyway; starting from something already themed muddies the
  opening frame.
- Hide the tab bar (`View → Hide Tab Bar`) and the scroll bar if you can. Chrome
  around the window reads as clutter at 600 px wide.
- Turn off notifications (Focus / Do Not Disturb). A banner sliding in ruins a
  take at second 9.

## 2. Dimensions

**100 columns × 34 rows.**

The picker draws 5 header lines + one row per style + a trailing blank — 22 lines
for 16 styles. 34 rows leaves room for the typed command and the banner without
scrolling. 100 columns keeps each name and its 5-block swatch on one line while
staying dense enough to crop to 16:9.

`demo.ps1` warns if the window is too small before you start recording.

## 3. Font size

**16–18 pt.** Larger than you would use for work. Assume the viewer is on a
phone, in a feed, at a third of native size.

Any monospace face is fine — the styles do not change the font on macOS.

## 4. Start the demo

```bash
cd ~/TerminalStyles
pwsh -File scripts/demo.ps1              # Guided: you drive
pwsh -File scripts/demo.ps1 -Mode Auto   # Auto: expect drives, identical takes
```

> On a machine where PowerShell came from the preview formula the binary is
> `pwsh-preview`; substitute it in every command below.

Either mode first: snapshots your current style state, parks personal tuned
styles so the list is exactly the 16 bundled ones, and resets the terminal so the
picker always opens on the first entry.

Use `-Mode Auto` for the take you ship. Use Guided when you want to explore or
when a human arrow rhythm looks better than a metronome.

### Recording it for you

```bash
pwsh -File scripts/demo.ps1 -Mode Auto -Record
```

Records the take to a `.mov` with macOS's own `screencapture`, cropped to this
terminal window, and lands it on your Desktop. No screen recorder to start, no
head or tail to trim: the script knows exactly how long the take runs, so it
gives the recorder a fixed duration and holds the final frame past the end.

`-RecordPath <file>` puts it somewhere else. It refuses to overwrite an existing
file rather than silently replacing a good take.

**Grant Screen Recording first**, to the app you are running this from —
Terminal.app, not PowerShell — in **System Settings › Privacy & Security ›
Screen Recording**, then restart that app. Without it `screencapture` writes
nothing and exits silently; the script notices the missing file and says so
rather than leaving you with a 0-byte `.mov`.

Two things about the crop: don't move or resize the window mid-take, and don't
click to another app — the rectangle is measured once, at the start. If the
window bounds can't be read the whole display is recorded instead, and it says
so before starting.

`-Record` needs `-Mode Auto`. In Guided mode the take lasts as long as you take,
so there is no duration to hand the recorder.

## 5. Sequence

Guided mode prints this as a cue card. Auto mode performs it.

| # | Action | Why |
|---|---|---|
| 1 | type `tstyles`, Enter | viewer sees a real command, not a mockup |
| 2 | **Down × 15** — steady, ~3/sec | the sweep. every press repaints the window |
| 3 | **Up × 1** | settles onto `tombraider` — an overshoot-and-return reads as a choice, not as the list ending |
| 4 | **Enter** | banner + themed prompt paint. second reveal |
| 5 | run `git log --oneline -6` | proves the terminal still works |
| 6 | stop recording on the last frame | leaves room for an end card |

The sweep deliberately passes through **every** style rather than jumping between
five. The picker only moves one row at a time, and a continuous run of 16 repaints
sells "instant" far better than five slow steps — including `gitbash`, the one
light theme, which lands as a white flash in the middle of a dark run.

Holds are on `gitbash`, `lain`, and `neon-rain`: the three biggest jumps against
the *previous* frame, which is what registers at speed.

## 6. Timing

| Time | Beat |
|---|---|
| 0.0–1.6 s | `tstyles` typed, Enter |
| 1.6–2.5 s | picker opens, holds one beat so it can be read |
| 2.5–8.9 s | sweep: 16 keypresses, 6.4 s, three deliberate holds |
| 8.9–10.3 s | Enter → banner + themed prompt |
| 10.3–11.8 s | `git log --oneline -6` typed |
| 11.8–14.4 s | output holds on screen |

**≈14.4 s.** Tune with `-StepMs` / `-HoldMs`:

```bash
pwsh -File scripts/demo.ps1 -Mode Auto -StepMs 260 -HoldMs 550   # ~12.5s
pwsh -File scripts/demo.ps1 -Mode Auto -Finale eva               # different finale
pwsh -File scripts/demo.ps1 -Mode Auto -DryRun                   # print the expect script
```

`-DryRun` writes the generated expect script and prints its path without running
it — edit that directly for one-off timing tweaks.

## 7. Reset afterwards

```bash
pwsh -File scripts/demo.ps1 -Restore
```

Returns your personal styles, restores the style you had before, and repaints the
window you are sitting in to match — no new tab needed. Safe to run on its own
after a Ctrl-C or a crash: the snapshot is on disk, not in the process.

If you only want the terminal back and do not care about the previous style:

```bash
tstyles reset
```

---

## What the script touches

Small and fully reversible, listed so you can audit it:

- **Snapshots** `current-style.json`, `current-style.ps1`, `current-style.osc`,
  and `current-prompt.sh` into `<data-root>/.demo-backup/`, recording which were
  absent so `-Restore` deletes rather than resurrects them.
- **Moves** `<data-root>/styles/` to `styles.demo-parked/` and back. A move within
  one parent — reversible, and it never touches a style's contents. Pass
  `-KeepUserStyles` to skip it.
- **Runs `tstyles reset`**, the same command a user would.

It does not modify the module, write to Windows Terminal's `settings.json`, or
touch anything outside the data root.

## If a take goes wrong

- **Picker frame scrolls mid-sweep** — window too short. `demo.ps1` warns; make it
  34 rows.
- **A style name you do not recognise appears** — a personal style was not parked.
  Run `-Restore`, then start again.
- **Picker opens partway down the list** — a style is still applied. Prep clears
  this; if you skipped prep, run `tstyles reset`.
- **Auto mode exits immediately** — `expect` is missing (preinstalled on macOS,
  `apt install expect` on Linux). It falls back to Guided.
- **`-Record` produced no file** — Screen Recording permission, almost always.
  Grant it to the terminal app itself and restart it; the permission is per-app,
  so granting it to one terminal does nothing for another.
- **The recording is the wrong region** — the window moved after the take
  started, or focus went to another app. The crop is measured once, up front.
- **Colors look washed out in the file** — the recorder is capturing in a
  different color profile. Record in sRGB.

## Optional: the background-image shot

Not in the main take, because it opens a second window and the cut has to jump.
Worth a separate clip:

```bash
tstyles eva -NewWindow
```

A new Terminal.app window opens carrying the full style — palette, prompt, and
the background image as a still frame.
