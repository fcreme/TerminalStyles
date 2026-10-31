# CLAUDE.md

Working notes for AI agents in this repo. `CONTRIBUTING.md` covers layout, exports,
publishing and test style — read it, and don't duplicate it here. This file is only
the things that are non-obvious and have actually cost this project a release.

## Sandboxing: overriding the data root is NOT enough

The most important rule in this file. This codebase edits files the user owns and
that predate it — `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.bash_login`, the
PowerShell `$PROFILE`, Windows Terminal's `settings.json`, and a VS Code-family
editor's `settings.json`.

VS Code's path comes from `Resolve-VSCodeTarget`, which takes `-HomeDir` /
`-AppData` / `-XdgConfigHome`; a bound `-HomeDir` suppresses the ambient `APPDATA`
and `XDG_CONFIG_HOME`. Writer tests mock `Resolve-VSCodeTarget` to a `$TestDrive`
path AND sandbox the data root, which holds the consent and undo records in
`vscode-state.json`. `tstyles uninstall` and `tstyles vscode off` do not go
through that seam: they edit the absolute `settings.json` paths recorded in
`vscode-state.json`. So a test that takes uninstall past its consent prompt
must point the data root at `$TestDrive` as well as bind `-HomeDir`, and a
test that runs `vscode off` at all must point it there too — `off` has no
`Confirm-Action` to refuse, and edits the recorded paths directly — or the
real records, and the real editors' files they name, are in reach. The
real-state guard fingerprints the keys TerminalStyles writes in every VS
Code-family `settings.json` rather than watching mtimes, because VS Code
rewrites that file itself.

**Several code paths resolve rc paths from the live `$HOME` independently of the data
root**, so pointing `$script:TStylesDataRoot` at `$TestDrive` does not contain them.
A test that only overrides the data root will edit the machine's real dotfiles.

Use the seams. `Get-ShellRcCandidate`, `Get-ShellRcRemovalCandidate`,
`Invoke-TerminalStylesShellInit` and `Invoke-TerminalStylesUninstall` all take
`-HomeDir` / `-ZDotDir`, forwarded by what the caller **bound** (not by value) so a
bound `-HomeDir` also suppresses the ambient `$env:ZDOTDIR`. `Invoke-TerminalStylesRegister`
takes `-Targets`. `Sync-ShellRuntime` has no seam and writes to the data root, so
anything reaching it needs the data root sandboxed **as well as** `-HomeDir`.

**Splatting an undefined variable fails UNSAFE here.** `Probe @neverDefined` does not pass
"no arguments": it binds the FIRST POSITIONAL parameter to an empty string and makes
`$PSBoundParameters.ContainsKey('HomeDir')` return `$true`. That is the exact guard used
everywhere above to tell "the caller asked for a sandbox" from "use the live `$HOME`" — so
losing a `$xSplat = @{}` line does not disable the seam, it announces a sandbox at the empty
path. It has happened once already, to `$wezSplat`, dropped resolving a merge while both uses
survived. `tests/Splat-Variables-Defined.Tests.ps1` walks the AST of every source file and
fails if anything splats a variable its own scope never assigns; keep it passing.

Never run `uninstall`, `delete`, `reset`, `register`, `shell-init` or `vscode off`
against the real environment to check something. Drive the underlying function in
a sandbox instead, and mock `Confirm-Action` to refuse rather than relying on
console detection.

## Capabilities are promises, not possibilities

`Get-TerminalCapability` says what **TerminalStyles delivers**, not what the terminal
could do. iTerm2 can do background images and tab titles through Dynamic Profiles;
nothing here writes one, so it claims `OscPalette` and nothing else. Claiming a
capability no code delivers makes a style report success, paint nothing, and *suppress
the notice that would have explained why*. If you add a writer, turn the flag on next to
the code that delivers it.

There are exactly four config writers in the repo: `Merge-StyleIntoSettings` (Windows
Terminal `settings.json`), `New-AppleTerminalProfile` (Terminal.app `.terminal` plist),
`Get-WezTermStyleLua` (WezTerm's generated Lua module) and `Invoke-VSCodeStyleApply`
(a VS Code-family editor's `settings.json`, written from `lib/vscodewriter.ps1` —
`Publish-StyleVSCodeConfig` and the picker's preview session — only after the user has
said yes for that editor, so its capability flags are conditional too, on
`Test-VSCodeWriterActive`). Everything else is escape sequences.

Corollary the table cost a release: a flag nothing reads is not a promise, it is a
rumour. `Get-UnsupportedStyleField` is the reader — it walks theme.json field by field
against the record and is the whole of the "can't show" notice, so turning a flag off is
what puts the field on screen. `TabTitle` is the documented exception and says why in
its own comment: the title arrives from the style's prompt on every terminal, so naming
it there would be a false claim in the other direction.

## Every user-facing message is a claim

This is the project's most-shipped defect class: a consent prompt listing two of the
three things it changes, help text describing a narrower command than the one that runs,
a success line printed on a path that silently no-opped. When you change what a command
does, change what it says in the same commit. When a listing bounds itself ("will NOT
modify X"), a reader is entitled to treat it as complete.

Corollary: don't collapse a status into a boolean. `Unregister-ShellLoader` returns
`removed` / `none` / `malformed` / `failed` precisely because "it failed" and "there was
nothing to do" became the same answer once, and the user was told the opposite of the truth.

## Two implementations of one rule will diverge

Most defects in `CHANGELOG.md` are this shape: a lint and the thing it lints, a listing
and the sweep it describes, a registration list and a removal list, an rc-file path and
a `$PROFILE` path. Before adding a second place that decides something, make the first
one answer the question and read it. If a fix applies to one half of a symmetry, check
the other half in the same change.

## Encoding and culture, on files the user owns

- `Get-RcFileEncoding` is **ISO-8859-1 (28591)**, not UTF-8, and it is load-bearing:
  these paths read the whole file and write the whole file back, so a byte that is not
  valid UTF-8 decodes to U+FFFD and is written back as the replacement character —
  silently corrupting the user's own content. ISO-8859-1 round-trips every byte 0-255,
  but only when the file's RAW BYTES are decoded through it. Read with `Read-RcFileText`
  (install.ps1: `Read-ProfileFileText`) and write back with the `Encoding` it returns.
  Never use `[System.IO.File]::ReadAllText(path, (Get-RcFileEncoding))`: it looks for a
  byte-order mark first and decodes by it whatever encoding it is handed. A UTF-16 or
  UTF-32 file is decoded and written back in its own encoding, BOM first.
- Any timestamp that is **parsed back** must be culture-pinned on **both** sides.
  `Get-Date -Format` uses the current culture's *calendar*; under `ar-SA` or `fa-IR`
  that is not Gregorian, and a reader pinned to `InvariantCulture` misreads it by
  centuries. Write with `(Get-Date).ToString(fmt, [cultureinfo]::InvariantCulture)`.
- Take a first-touch backup before the first write to a user-owned file
  (`Save-FirstTouchBackup`). It is FIRST touch on purpose: once our block is in the file,
  a fresh copy captures a file that already carries it.

## Tests that pass while measuring nothing

Each of these has hidden a real bug in this repo. Check for them in anything you write:

- **`-Skip:` is evaluated at DISCOVERY.** A flag set in `BeforeAll` is `$null` there, so
  the test never runs and still reports green.
- **`Get-Item` without `-Force` returns nothing for a dotfile on Unix.** Both sides of the
  assertion come back `$null` and it passes while comparing nothing. Use `[System.IO.File]`.
- **Asserting on a function's source text** (`ScriptBlock.ToString()` matching a helper
  name) proves nothing about behaviour and breaks on refactors that change nothing.
- **`-match` is case-insensitive** and matches substrings — `'ERASE'` also matches
  `is erased`.
- **Member access on an empty array yields one `$null`**, so `@((Get-Thing).Prop).Count`
  is 1 when `Get-Thing` returned nothing. Project with `ForEach-Object`.
- A mock that is never invoked, and an assertion inside a loop that never iterates, both
  report green.

## Style parity

Every style promises that its `profile.ps1` and `prompt.sh` halves render **byte-identically**
— it is written at the top of every `prompt.sh`. Shell-side names must be `_ts_`-prefixed,
on **every** column of a line, not just the first. `shell/tstyles.sh` is sourced on every
interactive shell, so it is held to the same rule (`TSTYLES_DATA` is a deliberate exception).

## Workflow

- Branch → PR → CI green on all four legs → merge. CI runs Pester on pwsh 7, **Windows
  PowerShell 5.1** (.NET Framework, not Core), macos-latest and ubuntu-latest. A green
  local macOS run proves little; 5.1 is where the surprises are.
- Locally: `Invoke-Pester -Path tests`. On a Mac with no `pwsh`, the binary may be
  `pwsh-preview` — Homebrew's stable cask is gone.
- Releases: bump `ModuleVersion` and `ReleaseNotes` in `TerminalStyles.psd1`, stamp the
  `[Unreleased]` heading in `CHANGELOG.md` and add the compare link, tag `vX.Y.Z`.
- CHANGELOG entries name the **mechanism** and the user-visible consequence, not just the
  fix. Match the surrounding prose; it is the project's main design record.
