# WezTerm per-tab styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In WezTerm off Windows, `tstyles` restyles only the tab it runs in (plus the default for new tabs); a window shows its active tab's style.

**Architecture:** `tstyles` tags its pane with an OSC 1337 user var naming the style. The generated `terminalstyles.lua` carries every installed style's look and registers `update-status` / `user-var-changed` handlers that give each window `set_config_overrides` for its active tab's style. PowerShell keeps its own per-tab record, because it cannot read the tag back. Font, size and padding are no longer set in WezTerm off Windows.

**Tech Stack:** PowerShell 7 + Windows PowerShell 5.1, Pester 5, WezTerm Lua config API.

**Spec:** `docs/superpowers/specs/2026-11-20-wezterm-per-tab-styles-design.md` (read it first; this plan argues from it).

## Global Constraints

- Branch `feat/wezterm-per-tab`. Branch → PR → CI green on all four legs (pwsh 7, Windows PowerShell 5.1, macOS, Ubuntu) → merge. `Invoke-Pester -Path tests` locally; the binary may be `pwsh-preview`.
- Per-tab mode = **all** of: terminal kind `WezTerm`, `Get-TStylesPlatform` ≠ `Windows`, `Test-WezTermStyleWired`. Everywhere else, today's behaviour byte for byte.
- Never write to the user's `wezterm.lua`. The wiring line (`Get-WezTermWiringLine`) is unchanged.
- The handlers never call `set_right_status`/`set_left_status`, never return `false`, and do no window work in `format-*` callbacks.
- `set_config_overrides` only when a window's wanted style actually changed.
- No network from the picker; the module build never fetches (`-NoFetch` everywhere except the style being applied, which `Publish-StyleWezTermConfig` already resolves).
- Every value in generated Lua goes through `ConvertTo-WezTermLuaString`.
- CLAUDE.md sandboxing: every test that reaches the module path binds `-HomeDir` to `$TestDrive` and points `$script:TStylesDataRoot` at `$TestDrive`.
- Tests that measure nothing (CLAUDE.md list): no `-Skip:` from `BeforeAll`, no `Get-Item` on dotfiles, no source-text assertions.
- Every changed behaviour changes its message in the same commit (CLAUDE.md "Every user-facing message is a claim").
- Commit messages: plain sentences in the repo's style, no `feat:` prefix, no Claude attribution trailer.
- **Deviation from the spec, deliberate:** apply keeps sending the style's OSC palette (it equals the tab's style, so it is harmless, and it keeps the `painted`/`noterminal` statuses and the colours if the tag is lost). Reset and every Esc send the OSC reset, as the spec says.

## Review Focus

1. A style name with a quote, backslash or non-ASCII letter (hand-made user style) → the module still loads and the tag still round-trips. Tests in Task 2 and Task 3.
2. `tstyles kitty > log` in WezTerm → no tag bytes in the file and no per-tab record written (the record would lie). Test in Task 4.
3. WezTerm restarted, pane ids reused → a dead session's record is not read as this tab's style. Test in Task 2.
4. A tab tagged with a style that has since been deleted → `tstyles current` falls back, the Lua treats the tag as untagged. Test in Task 6; the Lua half is checked by hand in Task 3 Step 5.
5. The module is written but the user never added the wiring line, or later removed it → everything behaves as today, the zsh/bash palette replay included. Tests in Task 2, Task 4 (marker removed) and Task 5.

---

### Task 1: Measure the four unknowns in a sandbox WezTerm

No repo code. The answers decide constants in Task 3. Use a throwaway config under a scratch directory, launched as
`/Applications/WezTerm.app/Contents/MacOS/wezterm-gui --config-file <scratch>/probe.lua start --always-new-process`
(never the user's config; `--always-new-process` keeps it off their running instance). Log from Lua to a file with `io.open(<scratch>/probe.log, 'a')`.

- [ ] **Step 1: Overrides across a reload.** Set `window:set_config_overrides({ window_background_opacity = 0.5 })` from `update-status` once, then `touch` a file the config `require`s. After the reload, log `window:get_config_overrides()` and look at the window. Record: do overrides survive a reload (yes/no)?
- [ ] **Step 2: Unsetting.** With the base config setting `color_scheme = 'Builtin Dark'` and a one-layer `background`, try overrides that should mean "none": `color_scheme = ''`, `color_scheme = '<a name not in color_schemes>'`, `background = {}`. Record for each: config error, warning, or the plain default look.
- [ ] **Step 3: Splits.** Split a tagged pane (`SplitHorizontal`); in `update-status` log `window:active_tab():panes()` with each pane's `get_user_vars().TERMINALSTYLES_STYLE`. Record: does the new pane start untagged, and is the sibling's tag readable?
- [ ] **Step 4: New window first frame.** With the base config unstyled and the style delivered only by an override from `update-status`, open a new window (Cmd+N) and watch for an unstyled frame. Record: visible flash (yes/no).
- [ ] **Step 5: Decide and record.** Write the four answers into the header comment of `lib/wezterm.ps1` under a new `PER-TAB MODE (measured <date>, wezterm <version>)` paragraph, in the file's existing measured-fact style. Decision rule:
  - Step 2 found a working "none" for **both** `color_scheme` and `background` → **base = last-applied style** (the spec's call). Use those values as the unstyled fills in Task 3.
  - Otherwise → **base = the user's own look**, and every styled window, the default included, gets its look as an override. If Step 4 showed a flash, stop and report to the maintainer before Task 3, because the spec chose against the flash.
- [ ] **Step 6: Commit** the header comment: `git commit -m "Record the WezTerm per-tab measurements in the writer's header"`.

### Task 2: Per-tab mode, the tag packet and the per-tab record

**Files:**
- Modify: `lib/wezterm.ps1` (new functions after `Test-WezTermStyleWired`)
- Test: `tests/WezTerm-PerTab.Tests.ps1` (new; same `BeforeDiscovery`/`BeforeAll` import and `InModuleScope TerminalStyles` shape as `tests/WezTerm-Writer.Tests.ps1`)

**Interfaces:**
- Produces:
  - `$script:WezTermTagVar = 'TERMINALSTYLES_STYLE'`, `$script:WezTermTagUnstyled = '/unstyled'`, `$script:WezTermTagPreviewPrefix = '/preview/'`. A `/` cannot be in any resolvable style name (`Test-StyleNameIsSingleSegment`), so these cannot collide.
  - `Test-WezTermPerTab [-Kind <string>] [-Platform <string>] [-HomeDir <string>] -> [bool]`. Defaults: `Get-TerminalKind`, `Get-TStylesPlatform`; `-HomeDir` forwarded to `Test-WezTermStyleWired` only when bound.
  - `Get-WezTermTagPacket -Value <string> [-InTmux <bool>] -> [string]`. `ESC ] 1337 ; SetUserVar=TERMINALSTYLES_STYLE=<base64 of UTF-8 Value> BEL`; with `-InTmux` (default `[bool]$env:TMUX`) wrapped as `ESC P tmux; <packet with every ESC doubled> ESC \`. `''` is a valid Value (clears the tag).
  - `Get-WezTermTabKey -> [string] or $null`. `"$env:WEZTERM_UNIX_SOCKET|$env:WEZTERM_PANE"`, or `$null` when either is empty.
  - `Set-WezTermTabRecord -Value <string> -> 'ok'|'failed'|'nokey'`. Writes `wezterm-tabs.json` (UTF-8, no BOM) under `$script:TStylesDataRoot`: an object mapping key → value (`''` = unstyled). Prunes every entry whose socket path (the part before `|`) no longer exists.
  - `Get-WezTermTabRecord -> [string] or $null`. This tab's value; `$null` when no key, no file, unreadable, or no entry.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Test-WezTermPerTab' {   # InModuleScope; Mock Test-WezTermStyleWired { $true }
  It 'is true only for WezTerm, off Windows, wired' {
    Test-WezTermPerTab -Kind WezTerm -Platform MacOS | Should -BeTrue
    Test-WezTermPerTab -Kind WezTerm -Platform Windows | Should -BeFalse
    Test-WezTermPerTab -Kind ITerm2  -Platform MacOS | Should -BeFalse
  }
  It 'is false when the wiring line is absent' {   # Mock Test-WezTermStyleWired { $false }
    Test-WezTermPerTab -Kind WezTerm -Platform Linux | Should -BeFalse
  }
}
Describe 'Get-WezTermTagPacket' {
  It 'base64-encodes the UTF-8 value' {
    $p = Get-WezTermTagPacket -Value "o'brién" -InTmux $false
    $p | Should -BeExactly ("$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=" +
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("o'brién")) + "$([char]7)")
  }
  It 'wraps for tmux with every ESC doubled' {
    $p = Get-WezTermTagPacket -Value kitty -InTmux $true
    $p.StartsWith("$([char]27)Ptmux;$([char]27)$([char]27)]1337;") | Should -BeTrue
    $p.EndsWith("$([char]27)\") | Should -BeTrue
  }
  It 'encodes an empty value as an empty user var' {
    Get-WezTermTagPacket -Value '' -InTmux $false |
      Should -BeExactly "$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=$([char]7)"
  }
}
Describe 'per-tab record' {   # $script:TStylesDataRoot = $TestDrive; env vars set per It and restored in AfterEach
  It 'round-trips this tab and keeps unstyled distinct from missing' { }   # set 'kitty' → 'kitty'; set '' → ''; other pane → $null
  It 'returns nokey and writes nothing outside WezTerm' { }               # both env vars empty → 'nokey', no file
  It 'drops entries whose socket no longer exists' { }                    # live socket = a file in $TestDrive; dead = a missing path; after any Set, the dead key is gone
  It 'reads a corrupt file as no record' { }                              # file holds 'not json' → Get returns $null, Set rewrites it
}
```

Fill each `It` with exactly the assertions in its comment.

- [ ] **Step 2: Run them to see them fail**

Run: `pwsh-preview -NoProfile -c "Invoke-Pester -Path tests/WezTerm-PerTab.Tests.ps1 -Output Detailed"`
Expected: FAIL, "The term 'Test-WezTermPerTab' is not recognized".

- [ ] **Step 3: Implement the six items above in `lib/wezterm.ps1`.** Read and write the JSON with `[System.IO.File]` and `[System.Text.UTF8Encoding]::new($false)`. Parse with `ConvertFrom-Json` into a hashtable by walking `PSObject.Properties` (5.1 has no `-AsHashtable`). Write with `ConvertTo-Json -Depth 2`. Catch every I/O error into `'failed'`/`$null`.
- [ ] **Step 4: Run them to see them pass.** Same command. Expected: PASS. Then the whole suite: `Invoke-Pester -Path tests`, all green, `tests/Splat-Variables-Defined.Tests.ps1` included.
- [ ] **Step 5: Commit:** `git commit -m "Add the WezTerm per-tab tag, record and mode predicate"`.

### Task 3: The per-tab module generator

**Files:**
- Modify: `lib/wezterm.ps1` (new functions beside `Get-WezTermStyleLua`; that function stays for Windows)
- Test: `tests/WezTerm-PerTab.Tests.ps1`

**Interfaces:**
- Consumes: the Task 2 constants; `Get-WezTermCursorStyle`, `Get-WezTermWindowOpacity`, `Get-WezTermTabForeground`, `Get-WezTermBackgroundSize`, `Get-WezTermBackgroundAlignment`, `Test-WezTermHexColor`, `ConvertTo-WezTermLuaString`, `Add-WezTermModuleHeader`, `Write-WezTermModuleText`; `Get-BackgroundImageExtensions`, `Get-BackgroundFileIn`, `Get-StyleBackgroundCacheDir` (lib/background.ps1); `Get-AvailableStyles`.
- Produces:
  - `Get-WezTermBackgroundCandidates -StyleDir <string> -> [string[]]`. The bundled file if `Get-BackgroundFileIn -Directory $StyleDir` finds one (inheriting a tuned style's base, as `Get-StyleBundledBackground` does); otherwise `<cache dir>/background.<ext>` for every extension, in `Get-BackgroundImageExtensions` order, **whether or not the file exists**.
  - `Get-WezTermStyleLook -StyleName <string> -Scheme <obj> -Theme <obj> -BackgroundCandidates <string[]> -> [string]`. One `[<name>] = { ... },` entry for the `LOOKS` table. Fields: `scheme` (the `color_schemes` body, the same keys and ansi/brights rule as `Get-WezTermStyleLua`), `cursor`, `opacity`, `blur` (20 when `useAcrylic` with an opacity, else absent), `tab_bg`, `tab_fg`, `base` (scheme background), `images` (the candidates), `image` (`width`/`height` from `Get-WezTermBackgroundSize`, `h`/`v` from `Get-WezTermBackgroundAlignment`, `opacity` from `backgroundImageOpacity`, default 1.0). Absent values are omitted, never `nil` literals. **No font, size or padding.**
  - `Get-WezTermTabModuleLua -Styles <object[]> -DefaultStyle <string or $null> -> [string]`. Each `Styles` item: `@{ Name; Scheme; Theme; BackgroundCandidates }`. Returns the whole module (below).
  - `Write-WezTermTabModule -DefaultStyle <string or $null> [-HomeDir <string>] -> 'written'|'unchanged'|'failed'`. Builds `Styles` from `Get-AvailableStyles`, skipping a style whose `scheme.json` is missing or unreadable. Writes through `Write-WezTermModuleText`. On `written` or `unchanged` it writes the marker file `wezterm-pertab` (empty) under `$script:TStylesDataRoot` for the zsh/bash loader (Task 5).

**The module's shape** (the algorithm the signatures do not determine). The Lua constants are interpolated from the Task 2 PowerShell constants, never retyped.

```lua
local wezterm = require 'wezterm'
local M = {}
local GENERATION = '<first 16 hex chars of SHA-256 over this text with the token blank>'
local DEFAULT = 'kitty'          -- or nil
local VAR, UNSTYLED, PREVIEW = 'TERMINALSTYLES_STYLE', '/unstyled', '/preview/'
local LOOKS = { ... }            -- Get-WezTermStyleLook per style
local BUILTIN = { ... }          -- WezTerm defaults + Task 1's "none" values
local USER = {}                  -- the user's own values, captured in apply_to_config
local KEYS = { 'color_scheme', 'background', 'window_background_opacity',
               'macos_window_background_blur', 'default_cursor_style', 'colors' }

-- look_of(name) -> a COMPLETE table over KEYS for that style; UNSTYLED -> USER
-- filled from BUILTIN. colors = deep copy of USER.colors (or {}) with the
-- style's tab_bar.active_tab merged in. background = { base colour layer,
-- image layer } using the FIRST existing path in images (checked here, with
-- io.open, every time), else the base colour layer alone.
-- blur only when wezterm.target_triple:find('darwin').

-- wanted(window, pane):
--   tag = pane:get_user_vars()[VAR]
--   PREVIEW..n with LOOKS[n] -> n;  UNSTYLED -> UNSTYLED;  LOOKS[tag] -> tag
--   else the first other pane of window:active_tab() whose tag resolves (not a preview)
--   else wezterm.GLOBAL['ts_pin_'..pane:pane_id()], set on first sight to DEFAULT or UNSTYLED
-- sync(window, pane):
--   stamp = wanted .. '@' .. GENERATION
--   if wezterm.GLOBAL['ts_win_'..window:window_id()] == stamp then return end
--   store stamp; window:set_config_overrides(<base-is-default and wanted == DEFAULT> and {} or look_of(wanted))

function M.apply_to_config(config)
  -- 1. USER[k] = deep copy of config[k] for k in KEYS
  -- 2. merge every LOOKS[n].scheme into config.color_schemes as 'TerminalStyles '..n
  -- 3. base = last-applied (Task 1 decision): for k, v in pairs(look_of(DEFAULT or UNSTYLED)) do config[k] = v end
  --    base = user's own: skip this step, and sync never uses {} for DEFAULT
  -- 4. wezterm.on('update-status', function(w, p) sync(w, p) end)
  --    wezterm.on('user-var-changed', function(w, p, name) if name == VAR then sync(w, w:active_pane()) end end)
  return config
end
return M
```

The GENERATION stamp is what re-syncs every window after a module rewrite (a new default changes what `{}` means) without looping on the reload that `set_config_overrides` itself causes.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Get-WezTermStyleLook' {   # fixtures: the eva scheme/theme from WezTerm-Writer.Tests.ps1
  It 'carries no layout' {
    $l = Get-WezTermStyleLook -StyleName eva -Scheme $scheme -Theme $theme -BackgroundCandidates @('/c/background.gif')
    $l | Should -Not -Match 'font'
    $l | Should -Not -Match 'padding'
  }
  It 'lists every candidate in order, quoted' {
    $l = Get-WezTermStyleLook -StyleName eva -Scheme $scheme -Theme $theme -BackgroundCandidates @('C:\a\bg.gif','/b/bg.png')
    $l | Should -Match ([regex]::Escape("images = { 'C:\\a\\bg.gif', '/b/bg.png' }"))
  }
  It 'escapes the style name' { }      # -StyleName "o'brien" → the entry opens with [ 'o\'brien' ] =
  It 'omits opacity and blur for an opaque style' { }   # theme.opacity 100 → no 'opacity =' at the look's top level, no 'blur'
}
Describe 'Get-WezTermBackgroundCandidates' {
  It 'returns the cache paths for every extension when nothing is cached' { }   # count == @(Get-BackgroundImageExtensions).Count, first ends with 'background.gif'
  It 'returns only the bundled file when the style ships one' { }
}
Describe 'Get-WezTermTabModuleLua' {
  It 'names the default, or nil' { }   # -DefaultStyle kitty → "local DEFAULT = 'kitty'"; $null → 'local DEFAULT = nil'
  It 'interpolates the reserved tag values from the PowerShell constants' {
    $m = Get-WezTermTabModuleLua -Styles @() -DefaultStyle $null
    $m | Should -Match ([regex]::Escape("'$($script:WezTermTagVar)', '$($script:WezTermTagUnstyled)', '$($script:WezTermTagPreviewPrefix)'"))
  }
  It 'has a stable generation for the same input and a new one when the default changes' { }
  It 'keeps the wiring entry point' { }     # matches 'function M.apply_to_config\(config\)' and ends with 'return M'
  It 'never touches the status bar' { }     # does not match 'set_right_status|set_left_status|return false'
}
Describe 'Write-WezTermTabModule' {   # -HomeDir $TestDrive, data root $TestDrive, Mock Get-AvailableStyles with two fixture dirs
  It 'writes, then reports unchanged, and leaves the per-tab marker' { }
  It 'skips a style whose scheme.json is unreadable' { }
}
```

- [ ] **Step 2: Run them to see them fail.** `Invoke-Pester -Path tests/WezTerm-PerTab.Tests.ps1`. Expected: FAIL, functions not recognized.
- [ ] **Step 3: Implement the four functions.** Compute GENERATION with `[System.Security.Cryptography.SHA256]::Create()` over the UTF-8 bytes (works on 5.1 and 7).
- [ ] **Step 4: Run them to see them pass,** then the whole suite.
- [ ] **Step 5: Load it for real.** Generate a module for all bundled styles into a scratch dir, wire it from a scratch `probe.lua`, and run `wezterm --config-file <scratch>/probe.lua ls-fonts 2>&1 >/dev/null`. Expected: no output, so no config error. Then launch the sandbox instance (Task 1 command) with two tabs: tag one with `printf` and the Task 2 packet bytes, switch tabs, open a split, Cmd+T. Expected: each tab keeps its look, the split takes its tab's look, the new tab is the default. Then tag a tab with a style name that is not installed. Expected: it shows its pin, and `probe.log` shows no Lua error. Note the results for the PR.
- [ ] **Step 6: Commit:** `git commit -m "Generate a per-tab WezTerm module that carries every style's look"`.

### Task 4: Apply and reset use the per-tab module; WezTerm stops claiming font and padding

**Files:**
- Modify: `lib/applystyle.ps1` (`Publish-StyleWezTermConfig`, `Reset-StyleNonWT`), `terminals.ps1` (`Get-TerminalCapability`)
- Test: `tests/WezTerm-Writer.Tests.ps1`, `tests/Reset-StyleNonWT-WezTerm.Tests.ps1`, `tests/Get-TerminalCapability.Tests.ps1`, any `tests/Font-*.Tests.ps1` that asserts `Get-FontOwner -Kind WezTerm` is `'style'`

**Interfaces:**
- Consumes: everything from Tasks 2–3.
- Produces: `Invoke-WezTermTabTag -Value <string> [-WithReset] [-OutputRedirected <bool> = [Console]::IsOutputRedirected] -> 'painted'|'noterminal'`. With `-OutputRedirected` true it writes nothing and returns `'noterminal'`. Otherwise it writes `Get-WezTermTagPacket` (with `Get-OscResetPacket` before it when `-WithReset`) through `Write-HostOscPacket`. On `painted` it calls `Set-WezTermTabRecord -Value $Value`; on `noterminal` it writes no record.
- `Get-TerminalCapability` gains `[string]$Platform = (Get-TStylesPlatform)`; the WezTerm arm sets `Font` and `Padding` to `($Platform -eq 'Windows')`, everything else unchanged.

- [ ] **Step 1: Write the failing tests**

```powershell
# Get-TerminalCapability.Tests.ps1
It 'WezTerm claims font and padding only on Windows' {
  (Get-TerminalCapability -Kind WezTerm -Platform MacOS).Font    | Should -BeFalse
  (Get-TerminalCapability -Kind WezTerm -Platform MacOS).Padding | Should -BeFalse
  (Get-TerminalCapability -Kind WezTerm -Platform Windows).Font  | Should -BeTrue
}
# WezTerm-Writer.Tests.ps1, Publish-StyleWezTermConfig, -HomeDir $TestDrive, Mock Test-WezTermPerTab { $true }
It 'per-tab: writes the per-tab module with this style as default and tags this tab' { }
#   Should -Invoke Write-WezTermTabModule -ParameterFilter { $DefaultStyle -eq 'eva' } -Times 1
#   Should -Invoke Invoke-WezTermTabTag   -ParameterFilter { $Value -eq 'eva' } -Times 1
It 'off per-tab: writes the single-style module exactly as before' { }   # Mock Test-WezTermPerTab { $false } → Write-WezTermStyleModule invoked, Write-WezTermTabModule not
It 'redirected output: no tag bytes reach the stream and no record is written' { }   # Invoke-WezTermTabTag -OutputRedirected $true → 'noterminal'; no wezterm-tabs.json in $TestDrive
# Reset-StyleNonWT-WezTerm.Tests.ps1
It 'per-tab: tags this tab unstyled, clears the default, and leaves other tabs alone' { }
#   Should -Invoke Invoke-WezTermTabTag -ParameterFilter { $Value -eq '/unstyled' -and $WithReset }
#   Should -Invoke Write-WezTermTabModule -ParameterFilter { $null -eq $DefaultStyle }
#   Should -Invoke Clear-WezTermStyleModule -Times 0
It 'per-tab: says it reset this tab' { }   # captured host output contains 'Reset this WezTerm tab to your own look.' and 'New tabs open unstyled; other open tabs keep their styles.'
```

- [ ] **Step 2: Run them to see them fail.** The four files above. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `Publish-StyleWezTermConfig`: when `Test-WezTermPerTab -Kind $Kind`, call `Write-WezTermTabModule -DefaultStyle $StyleName`, then `Invoke-WezTermTabTag -Value $StyleName`. Otherwise today's path. Both apply paths (direct and the picker's confirm at tstyles.ps1 ~2261) already call this function, so neither caller changes.
  - Its not-wired notice: replace "Then every style you apply repaints the running window, background animation included." with "Then each style you apply restyles the tab you run it in, background animation included." (It prints only when not wired, so it describes what wiring will give.)
  - `Reset-StyleNonWT`, WezTerm half: when per-tab, `Invoke-WezTermTabTag -Value $script:WezTermTagUnstyled -WithReset` and `Write-WezTermTabModule -DefaultStyle $null` replace `Clear-WezTermStyleModule`. The success lines in that mode: `"  Reset this WezTerm tab to your own look."` and `"  New tabs open unstyled; other open tabs keep their styles."`. Its failure line names the module path as today.
  - `Get-TerminalCapability`: the `-Platform` parameter and the WezTerm arm as above. Then `Get-FontOwner` answers `'terminal'` for WezTerm off Windows by itself (lib/fonts.ps1:604), so `tstyles font` prints the existing "takes its font from its own settings" line there. The "Or set config.font AFTER the terminalstyles require line" line sits inside the `'style'` arm, so it is now reached only on Windows, where it is still true. Leave it.
  - Off per-tab, `Publish-StyleWezTermConfig` also deletes the `wezterm-pertab` marker, so a user who removes the wiring line gets the zsh/bash replay back. Test: `It 'off per-tab: removes the per-tab marker'`.
- [ ] **Step 4: Run them to see them pass,** then the whole suite.
- [ ] **Step 5: Commit:** `git commit -m "Apply and reset restyle only this WezTerm tab; font and padding come from wezterm.lua"`.

### Task 5: New shells do not repaint the last style over their tab

**Files:**
- Modify: `shell/tstyles.sh` (`ts_load`, step 1), `tstyles.ps1` (startup block, ~line 2538)
- Test: `tests/Shell-Integration.Tests.ps1`, a new `Describe` in `tests/WezTerm-PerTab.Tests.ps1` for the pwsh half

**Interfaces:**
- Consumes: the `wezterm-pertab` marker (Task 3), `Test-WezTermPerTab` (Task 2).

- [ ] **Step 1: Write the failing tests.** In `Shell-Integration.Tests.ps1`, run the staged `tstyles.sh` the way that file's existing replay tests do, as an interactive shell with stdout on a pty, `TSTYLES_DATA=$TestDrive`, and `current-style.osc` holding `XYZ`:
  - `It 'skips the palette replay in a WezTerm pane once a per-tab module exists'`: `WEZTERM_PANE=3` and the marker present → output does not contain `XYZ`.
  - `It 'still replays in WezTerm without the marker'`: no marker → contains `XYZ`.
  - `It 'still replays outside WezTerm with the marker'`: marker present, `WEZTERM_PANE` unset → contains `XYZ`.
  - pwsh half: `It 'startup does not repaint in per-tab mode'`. Mock `Test-WezTermPerTab { $true }` and `Invoke-TerminalStyleOscApply`; run the startup block's colour step. `Should -Invoke Invoke-TerminalStyleOscApply -Times 0`. If the step is inline script, first lift it into `Invoke-StartupPaletteReplay` (no parameters, returns nothing) in `tstyles.ps1` and call that from the block.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.** In `tstyles.sh`, guard the `cat` with `[ -n "${WEZTERM_PANE-}" ] && [ -e "$TSTYLES_DATA/wezterm-pertab" ]` (skip when both hold). Use only `_ts_`-prefixed names if a variable is needed (CLAUDE.md "Style parity"). In pwsh, extend the existing `-ne 'WindowsTerminal'` condition with `-and -not (Test-WezTermPerTab)`. Uninstall's data-root wipe already removes the marker; confirm `tstyles reset` keeps it, since the per-tab module stays.
- [ ] **Step 4: Run them to see them pass,** then the whole suite plus `tests/Shell-Files-Are-LF.Tests.ps1`.
- [ ] **Step 5: Commit:** `git commit -m "New shells in WezTerm take their tab's colours instead of replaying the last style"`.

### Task 6: "Which style is active" answers for this tab

**Files:**
- Modify: `tstyles.ps1` (`Get-CurrentStyleName`, ~line 845)
- Test: `tests/WezTerm-PerTab.Tests.ps1`

- [ ] **Step 1: Write the failing tests** (Mock `Test-WezTermPerTab { $true }`, `Get-WezTermTabRecord`, `Get-StyleDir`, and the global record):
  - `It 'names this tab's style over the last applied one'`: record `'neon-rain'`, global `'kitty'` → `'neon-rain'`.
  - `It 'is $null for a tab reset to unstyled'`: record `''` → `$null`.
  - `It 'falls back to the last applied style when this tab has no record'`: record `$null` → `'kitty'`.
  - `It 'falls back when this tab's style was deleted'`: record `'gone'`, `Get-StyleDir` returns `$null` for it → `'kitty'`.
  - `It 'ignores the record off per-tab mode'`: Mock `Test-WezTermPerTab { $false }`, record `'neon-rain'` → `'kitty'`.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.** At the top of `Get-CurrentStyleName`: in per-tab mode, `$tab = Get-WezTermTabRecord`. If `$tab -eq ''` return `$null`; if `$tab` resolves with `Get-StyleDir`, return it; otherwise fall through to today's logic. This single change reaches `current`, the `list` marker, `tune` with no name, `random`, `delete` of the active style and the picker's start row, all of which read this function (16 call sites, `grep -n Get-CurrentStyleName`). Read each call site once to confirm none needs the global answer specifically. Default for new tabs is `Get-CurrentStyleRecord`, not this function, so `Write-WezTermTabModule` callers keep using the record.
- [ ] **Step 4: Run them to see them pass,** then the whole suite.
- [ ] **Step 5: Commit:** `git commit -m "tstyles current and friends answer for this WezTerm tab"`.

### Task 7: Picker, tuner and show preview in their own tab

**Files:**
- Modify: `tstyles.ps1` (picker WezTerm block ~1243–1315, the Esc block ~2059, the confirm ~2261), `lib/tune.ps1` (`Restore-TuneBaseLook` ~1156), `lib/picker.ps1` (`Invoke-TerminalStyleShow` ~1064)
- Test: `tests/WezTerm-LivePreview.Tests.ps1`, the tuner revert tests (`grep -ln Restore-TuneBaseLook tests`)

**Interfaces:**
- Consumes: `Get-WezTermTagPacket`, `Get-WezTermTabRecord`, `Write-WezTermTabModule`, `Test-WezTermPerTab`, `Get-CurrentStyleRecord`.
- Produces: `Get-WezTermPickerPreviewPacket -StyleName <string> -> [string]` (the preview tag) and `Get-WezTermPickerRevertPacket -> [string]` (`Get-OscResetPacket` + the tag for `Get-WezTermTabRecord`, `''` when `$null`). Both are pure, so the picker body, which no test can drive, calls one-liners.

- [ ] **Step 1: Write the failing tests**
  - `It 'previews by tag, not by rewriting the module'`: `Get-WezTermPickerPreviewPacket -StyleName rain` equals `Get-WezTermTagPacket -Value '/preview/rain'`.
  - `It 'Esc puts back this tab's own tag and hands colours to the window scheme'`: record `'kitty'` → packet starts with `Get-OscResetPacket` and ends with `Get-WezTermTagPacket -Value kitty`; record `$null` → ends with the `''` tag.
  - `It 'the revert packet is the reset in per-tab mode'`: `Get-RevertOscPacket -UseSettingsFile:$true -HadStartingStyle:$true -StartingScheme $s` equals `Get-OscResetPacket` (pins the arm callers will now select).
  - Tuner: `It 'Restore-TuneBaseLook sends the reset in per-tab mode'` with Mock `Test-WezTermPerTab { $true }` and a recorder for `Write-HostOscPacket` → the packet equals `Get-OscResetPacket`.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
  - Picker setup: `$wezPerTab = ($termKind -eq 'WezTerm') -and (Test-WezTermPerTab -Kind $termKind)`. When true: `[void](Write-WezTermTabModule -DefaultStyle (Get-CurrentStyleRecord).name)` once at open (deterministic, so `unchanged` costs no reload, and it picks up styles created since). Then no `New-FilePreviewSession`/`Restore-AbandonedFilePreview` for WezTerm and no `-LayoutTheme`. `$previewWezTerm` writes `Get-WezTermPickerPreviewPacket` through `Write-HostOscPacket`; `$restoreWezTerm` writes `Get-WezTermPickerRevertPacket`. When false: today's code untouched (Windows WezTerm).
  - Esc's palette line: `-UseSettingsFile:($useSettingsFile -or $wezPerTab)`. Leave `$useSettingsFile` itself alone; it drives other things.
  - Confirm: unchanged. `Publish-StyleWezTermConfig` already tags and records (Task 4). Skip `Complete-FilePreview` when `$wezSession` is `$null`.
  - `Restore-TuneBaseLook` and `Invoke-TerminalStyleShow`: pass `-UseSettingsFile:(<existing value> -or (Test-WezTermPerTab))` to `Get-RevertOscPacket` only. Do not route that into `Restore-TuneBaseLook`'s settings-file session branch.
- [ ] **Step 4: Run them to see them pass,** then the whole suite. Then by hand in the sandbox instance from Task 1, wired to a module from `Write-WezTermTabModule -HomeDir <scratch>`: arrow through the picker in one tab, Esc, confirm. The other tab must not change at any point.
- [ ] **Step 5: Commit:** `git commit -m "The picker, tuner and show preview only in their own WezTerm tab"`.

### Task 8: Uninstall wording, docs, changelog

**Files:**
- Modify: `lib/update.ps1` (~1549–1580, the WezTerm removal lines), `README.md` (WezTerm section), `lib/help.ps1` (WezTerm lines), `CHANGELOG.md` (`[Unreleased]`)
- Test: the uninstall tests that capture the WezTerm lines (`grep -ln 'Removed the WezTerm style module' tests`)

- [ ] **Step 1: Write the failing test.** `It 'says open WezTerm windows keep their look'`: sandboxed uninstall per CLAUDE.md (data root and `-HomeDir` at `$TestDrive`, `Confirm-Action` mocked to accept) with a per-tab module present. Output contains `"  WezTerm windows already open keep their look until you close them or restart WezTerm."`. **Only if Task 1 Step 1 found overrides survive a reload**; otherwise assert the line is absent.
- [ ] **Step 2: Run it to see it fail.**
- [ ] **Step 3: Implement** the line after "Removed the WezTerm style module (...)", when the deleted module was the per-tab form. Detect that by a fixed marker comment `-- TerminalStyles per-tab module` that `Get-WezTermTabModuleLua` writes as its second line; add that line to Task 3's 'keeps the wiring entry point' test. README and help: per tab; a window shows its active tab's style; new tabs take the last applied style; a split takes its tab's style; restart forgets per-tab styles; font, size and padding come from your own `wezterm.lua`; for the keys a style sets (colours, background, opacity, blur, cursor, tab colour) a styled tab wins over your own lines; tmux needs `set -g allow-passthrough on`; Windows keeps restyling every tab. CHANGELOG: one entry that names the mechanism (user-var tag, per-window overrides, per-tab record) and each user-visible consequence, in the surrounding prose style.
- [ ] **Step 4: Run it to see it pass,** then the whole suite.
- [ ] **Step 5: Commit:** `git commit -m "Document WezTerm's per-tab styles and what uninstall leaves on open windows"`.
- [ ] **Step 6: Push the branch and open the PR**, ending the body with this plan's manual checks (Task 1 answers, Task 3 Step 5, Task 7 Step 4). Wait for all four CI legs.
