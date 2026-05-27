# TerminalStyles -- gifs branch

This branch holds the background images for each style. They live here
instead of on main so the install ZIP stays small (~100 KB instead of
~10 MB). TerminalStyles' `tstyles.ps1` lazy-fetches each file on first
use via `raw.githubusercontent.com`.

Filename convention: `<style-name>.<ext>` (e.g., `umbrella.gif`,
`sober.png`). Extension priority is `gif > png > jpg > jpeg`.

To add a new style's background:

1. Switch to this branch: `git checkout gifs`
2. Drop your file at the root: `cp my-bg.gif <style-name>.gif`
3. Commit + push.

Adding a new style itself (`scheme.json` / `theme.json` / `profile.ps1`)
is done on main; only the binary asset belongs here.
