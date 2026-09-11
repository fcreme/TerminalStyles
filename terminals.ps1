# terminals.ps1 -- terminal backend detection and capability model.
#
# TerminalStyles began as a Windows Terminal tool: a style was applied by
# merging theme.json into WT's settings.json. Every other terminal describes
# itself differently (iTerm2 has Dynamic Profile JSON, Terminal.app has
# NSKeyedArchiver plists, the rest have plain-text configs), and none of them
# support the full WT field set. This file is the seam between "what a style
# asks for" and "what the host terminal can actually do".
#
# Two orthogonal axes:
#
#   Detection   -- which terminal is hosting THIS session (Get-TerminalKind).
#   Capability  -- which style fields that terminal can honour
#                  (Get-TerminalCapability), so callers degrade gracefully
#                  instead of writing settings nothing will read.
#
# Dot-sourced by tstyles.ps1. Kept separate because the WT-specific merge logic
# in tstyles.ps1 is already long, and because the adapters are the part most
# likely to grow (one block per terminal).

# Every capability a style can ask for. A terminal's capability record is a
# hashtable over exactly these keys, so a typo surfaces as a missing key rather
# than a silently-false feature test.
$script:TStylesCapabilityNames = @(
    'OscPalette',      # OSC 4/10/11/12 dynamic colors -- live retint, no config write
    # Can THIS MODULE write a config the terminal reads on startup? True only
    # where a writer exists: Windows Terminal's settings.json, Terminal.app's
    # .terminal profile, and WezTerm's generated Lua module. Not to be confused with a style surviving a new tab,
    # which works on every terminal and owes nothing to this flag -- that is
    # current-style.json plus the OSC re-emit in the startup block, and it
    # carries colors only. Reading Persist as "styles stick here" is what led
    # to five terminals claiming fonts and background images that no code ever
    # delivered.
    'Persist',
    'Font',            # font family + size
    'Opacity',         # window transparency
    'CursorShape',     # block / bar / underscore / filled
    'BackgroundImage', # a wallpaper behind the text
    'TabTitle',        # per-profile tab title
    'TabColor',        # per-profile tab accent color
    'Padding'          # interior window padding
)

function Get-TerminalKind {
    # Identify the terminal emulator hosting this session.
    #
    # Detection is env-var based and ordered most-specific first, because the
    # generic markers overlap: WezTerm and iTerm2 both set TERM_PROGRAM, and a
    # multiplexer or SSH session can inherit a stale value from wherever it was
    # launched. Returns 'Unknown' rather than guessing -- callers fall back to
    # the OSC path, which is the one thing that works nearly everywhere.
    #
    # -EnvTable is a test seam: a hashtable standing in for $env:. Real callers
    # omit it and the live environment is read.
    param([hashtable]$EnvTable)

    $get = {
        param([string]$Name)
        if ($null -ne $EnvTable) { return $EnvTable[$Name] }
        return [System.Environment]::GetEnvironmentVariable($Name)
    }

    # Windows Terminal sets WT_SESSION on every tab it hosts. Checked first
    # because WT also runs on the same machine as VS Code's terminal, which
    # would otherwise match on TERM_PROGRAM below.
    if (& $get 'WT_SESSION') { return 'WindowsTerminal' }

    # kitty and Alacritty set no TERM_PROGRAM, only their own markers.
    if (& $get 'KITTY_WINDOW_ID')    { return 'Kitty' }
    if (& $get 'ALACRITTY_WINDOW_ID'){ return 'Alacritty' }
    if (& $get 'GHOSTTY_RESOURCES_DIR') { return 'Ghostty' }

    # ITERM_SESSION_ID is set even when TERM_PROGRAM has been clobbered by a
    # multiplexer, so it is the more reliable iTerm2 signal of the two.
    if (& $get 'ITERM_SESSION_ID')   { return 'ITerm2' }

    switch ((& $get 'TERM_PROGRAM')) {
        'Apple_Terminal' { return 'AppleTerminal' }
        'iTerm.app'      { return 'ITerm2' }
        'WezTerm'        { return 'WezTerm' }
        'ghostty'        { return 'Ghostty' }
        'vscode'         { return 'VSCode' }
    }

    return 'Unknown'
}

function Get-TerminalCapability {
    # The capability record for a terminal kind: a hashtable keyed by
    # $script:TStylesCapabilityNames, every value a [bool].
    #
    # These are deliberately conservative. A capability marked $false means
    # "TerminalStyles will not try", which degrades to a plainer theme; marking
    # something $true that the terminal ignores is worse, because the user is
    # told a setting was applied and sees nothing change.
    param([string]$Kind = (Get-TerminalKind))

    # Baseline: nothing. Each block below turns on only what it can prove.
    $caps = @{}
    foreach ($n in $script:TStylesCapabilityNames) { $caps[$n] = $false }

    switch ($Kind) {
        'WindowsTerminal' {
            # The original target, and still the only one that honours the whole
            # theme.json field set.
            foreach ($n in $script:TStylesCapabilityNames) { $caps[$n] = $true }
        }
        'ITerm2' {
            # iTerm2 can do every one of these, through a Dynamic Profile
            # dropped in ~/Library/Application Support/iTerm2/DynamicProfiles/,
            # which it picks up live with no restart. Nothing in this module
            # writes one yet, and a capability is a promise about what
            # TerminalStyles will deliver -- not about what the terminal could
            # do in principle.
            #
            # Claiming them cost more than leaving them off: BackgroundImage in
            # particular meant a style that ships a GIF reported success,
            # painted nothing (the apply path only builds a profile when the
            # kind is AppleTerminal), skipped the "can't show: background image"
            # notice that explains a plain result, and still had the picker
            # prefetch megabytes of GIFs that could never be drawn.
            $caps.OscPalette = $true
            $caps.TabTitle   = $true
        }
        'AppleTerminal' {
            # Persistence goes through a .terminal profile plist. No per-profile
            # tab accent color.
            #
            # BackgroundImage is $true, but it is the one capability here that
            # cannot be delivered to the CURRENT window: there is no escape
            # sequence for an image, so it can only arrive as part of a profile,
            # which means a new window. New-AppleTerminalProfile builds that
            # profile; Apply-StyleNonWT stages it and tells the user how to open
            # it rather than seizing the screen on every apply.
            #
            # OscPalette is $true on the strength of a round-trip probe against
            # Terminal.app 470 (macOS 26): OSC 4/10/11/12 all answered their
            # query form, setting OSC 11 to #ff00ff read back as ff00/0000/ff00,
            # and OSC 111 / OSC 104 restored the profile defaults exactly. So the
            # picker's live preview and its Esc revert both work here with the
            # same escape packets Windows Terminal uses -- no AppleScript needed
            # on the hot path.
            # Font / Opacity / CursorShape are deliberately NOT claimed. The
            # profile this module builds carries colors and a background image
            # and nothing else (see Get-AppleTerminalProfileData), so a style's
            # font and opacity are dropped on the way through. Terminal.app
            # would honour them in a profile; until the profile carries them,
            # saying so here would suppress the "can't show" notice and leave
            # the user comparing an unchanged font against the screenshot.
            $caps.OscPalette      = $true
            $caps.Persist         = $true
            $caps.TabTitle        = $true
            $caps.BackgroundImage = $true
        }
        # Ghostty / kitty / Alacritty keep their settings in a config file this
        # module has never learned to write -- ghostty's `config`, `kitty.conf`,
        # `alacritty.toml`. Each can do fonts and opacity, but none of it reaches
        # the user through TerminalStyles. What genuinely works on all three is
        # the OSC retint, which is the whole live-preview path, so that is what
        # is claimed.
        #
        # Adding a writer for any of these is the moment to turn its flags on --
        # one terminal at a time, next to the code that delivers it, which is
        # what the WezTerm arm below now does.
        'Ghostty' {
            $caps.OscPalette = $true
        }
        'WezTerm' {
            # lib/wezterm.ps1 generates a Lua module that the user loads from
            # their own wezterm.lua with one pcall-guarded require. Everything
            # claimed here is written by Get-WezTermStyleLua and nothing else is.
            #
            # BackgroundImage is the reason this writer exists: WezTerm is the
            # only terminal off Windows that ANIMATES a GIF, and every bundled
            # style ships one. Terminal.app gets a still first frame at best.
            #
            # Font and Padding are `config.font`/`font_size` and
            # `window_padding`. Persist is the module itself, which WezTerm reads
            # on startup -- and, because required files are on its config reload
            # watch list, rewriting it also restyles a RUNNING window.
            #
            # Opacity is deliberately NOT claimed even though WezTerm has
            # window_background_opacity. Once a `background` layer list exists
            # WezTerm skips the pane's solid rect, and the code paths that
            # multiply by that setting are guarded off -- so its effect
            # alongside the layers this writer emits is not something this
            # project has verified. Claiming it would suppress the "can't show"
            # notice and leave the user comparing an unchanged window against a
            # screenshot, which is the exact failure the capability table exists
            # to prevent. CursorShape, TabTitle and TabColor are not written at
            # all.
            $caps.OscPalette      = $true
            $caps.Persist         = $true
            $caps.Font            = $true
            $caps.Padding         = $true
            $caps.BackgroundImage = $true
        }
        'Kitty' {
            $caps.OscPalette = $true
        }
        'Alacritty' {
            $caps.OscPalette = $true
        }
        'VSCode' {
            # The integrated terminal honours OSC colors for the session but its
            # settings live in VS Code's own settings.json, which is not ours to
            # rewrite. Live-only.
            $caps.OscPalette = $true
        }
        default {
            # Unknown terminal: assume only the lowest common denominator. Nearly
            # every emulator written in the last two decades handles OSC 4/10/11,
            # and getting it wrong costs one stray escape sequence, not a
            # corrupted config file.
            $caps.OscPalette = $true
        }
    }

    return $caps
}

function Test-TerminalCapability {
    # Convenience predicate: does $Kind support $Capability?
    # Throws on an unknown capability name so a typo fails loudly at the call
    # site instead of quietly reading as "unsupported".
    param(
        [Parameter(Mandatory)][string]$Capability,
        [string]$Kind = (Get-TerminalKind)
    )
    if ($script:TStylesCapabilityNames -notcontains $Capability) {
        throw "Unknown terminal capability '$Capability'. Known: $($script:TStylesCapabilityNames -join ', ')"
    }
    return [bool](Get-TerminalCapability -Kind $Kind)[$Capability]
}

function Get-TerminalDisplayName {
    # Human-readable name for messages ("Ghostty", not "Ghostty" == kind by
    # accident). Kept as an explicit map so renaming a kind doesn't silently
    # change user-facing output.
    param([string]$Kind = (Get-TerminalKind))
    switch ($Kind) {
        'WindowsTerminal' { 'Windows Terminal' }
        'AppleTerminal'   { 'Terminal.app' }
        'ITerm2'          { 'iTerm2' }
        'Ghostty'         { 'Ghostty' }
        'WezTerm'         { 'WezTerm' }
        'Kitty'           { 'kitty' }
        'Alacritty'       { 'Alacritty' }
        'VSCode'          { 'VS Code terminal' }
        default           { 'this terminal' }
    }
}

function Test-HostOutputVisible {
    # True when this session's stdout is a terminal a human is looking at.
    #
    # Guards everything the module prints at load time -- the OSC palette and
    # the style's banner. `pwsh -c '...' > out.txt` from a $PROFILE that imports
    # TerminalStyles would otherwise prepend a banner and ~280 bytes of escape
    # sequences to out.txt, quietly corrupting the output of any script that
    # captures it. Redirected output has no terminal listening, so suppressing
    # is free.
    try {
        return -not [Console]::IsOutputRedirected
    } catch {
        # No console object at all (hosted runspace, some CI harnesses).
        return $false
    }
}

function Test-StyledHost {
    # True when the host terminal can actually render a style, and therefore
    # when it makes sense to load the style's prompt/banner at startup.
    #
    # Replaces the old Test-InWindowsTerminal gate. The original reasoning was
    # "only WT renders the colors, so only load the themed prompt there" -- that
    # reasoning is right, but WT is no longer the only terminal that qualifies.
    # Any terminal that can take an OSC palette, or that we can write a config
    # for, will render the style; a bare pipe or a dumb host will not.
    param([string]$Kind = (Get-TerminalKind))
    $caps = Get-TerminalCapability -Kind $Kind
    return [bool]($caps.OscPalette -or $caps.Persist)
}

function Get-CurrentStyleRecordPath {
    # Where the "which style is applied" record lives off Windows.
    #
    # On Windows Terminal the applied style is recoverable by reading the
    # colorScheme name back out of settings.json, so no separate record is kept.
    # Terminals driven by OSC have no such readback -- the escape sequences are
    # fire-and-forget -- so the choice is recorded here instead. This is also
    # what the startup re-emit reads to restore colors in a new tab.
    Join-Path $script:TStylesDataRoot 'current-style.json'
}

function Set-CurrentStyleRecord {
    # Record the applied style. Best-effort: a failure to write the record makes
    # `tstyles current` and the startup re-emit forget the choice, but it must
    # never take down an apply that already succeeded.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Kind = (Get-TerminalKind)
    )
    try {
        $record = [pscustomobject]@{
            name      = $StyleName
            terminal  = $Kind
            appliedAt = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        $json = $record | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Get-CurrentStyleRecordPath), $json, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Get-CurrentStyleRecord {
    # The recorded style, or $null when there is none / the file is unreadable
    # or corrupt. Corruption self-heals: the next apply overwrites it.
    $path = Get-CurrentStyleRecordPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $json = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
        if (-not $json.Trim()) { return $null }
        $record = $json | ConvertFrom-Json
        if (-not $record.name) { return $null }
        return $record
    } catch {
        return $null
    }
}

function Clear-CurrentStyleRecord {
    # Forget the applied style (used by `tstyles reset`). -Force so the write
    # survives a read-only attribute; missing file is not an error.
    $path = Get-CurrentStyleRecordPath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Write-HostOscPacket {
    # Emit raw escape bytes to the terminal.
    #
    # [Console]::Out.Write, NOT Write-Host: Write-Host routes through the
    # PowerShell host's formatting layer, which can swallow or re-encode control
    # characters (and in a transcript or a redirected stream would write the
    # escapes as visible text). Console.Out goes straight at stdout, which is
    # where the terminal is listening. Flush so the repaint happens now rather
    # than whenever the buffer next drains -- the picker depends on that
    # immediacy for per-keystroke preview.
    # Returns $true when the bytes actually reached a terminal, $false when
    # there was none to reach. Callers MUST NOT assume success: an apply that
    # silently painted nothing and still reported "Style applied" is exactly the
    # confusion this return value exists to prevent.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Packet)
    if (-not $Packet) { return $false }

    # Never write escape bytes into a redirected stream. The module re-emits the
    # applied style's palette when it loads, and a $PROFILE that imports it turns
    # every `pwsh -c ... > out.txt` and every piped invocation into a file with
    # ~280 bytes of OSC glued to the front of the real output. Redirected stdout
    # means nothing is listening for escape sequences, so there is nothing to
    # lose by staying quiet. (The shell loader makes the same check via $-.)
    try {
        if ([Console]::IsOutputRedirected) { return $false }
    } catch {
        # No console at all (a runspace, a hosted app): also nothing to paint.
        return $false
    }

    try {
        [Console]::Out.Write($Packet)
        [Console]::Out.Flush()
        return $true
    } catch {
        # A redirected/absent console (CI, a job runspace) has nothing to paint.
        # Silent by design: colors are cosmetic, and throwing here would abort an
        # otherwise-successful apply.
        return $false
    }
}

function Invoke-TerminalStyleOscApply {
    # Retint the live terminal to $Scheme via OSC. Returns $true when the packet
    # was emitted, $false when the terminal cannot take one.
    param(
        [Parameter(Mandatory)]$Scheme,
        [string]$Kind = (Get-TerminalKind)
    )
    if (-not (Get-TerminalCapability -Kind $Kind).OscPalette) { return $false }
    # Return what actually happened, not what the terminal is capable of. The
    # two differ whenever stdout is redirected -- a pipe, a file, an agent shell
    # -- and reporting capability there made `tstyles <name>` claim success
    # while changing nothing on screen.
    return (Write-HostOscPacket -Packet (Get-SchemeOscPacket -Scheme $Scheme))
}

function Invoke-TerminalStyleOscReset {
    # Hand color control back to the terminal's own configured scheme.
    param([string]$Kind = (Get-TerminalKind))
    if (-not (Get-TerminalCapability -Kind $Kind).OscPalette) { return $false }
    return (Write-HostOscPacket -Packet (Get-OscResetPacket))
}

# === zsh / bash support ====================================================
#
# TerminalStyles is a PowerShell module, but a Mac user's login shell is
# usually zsh. The colors are a property of the terminal, not the shell, so
# they apply either way -- but the prompt and banner would not, and a zsh user
# would get a half-applied style.
#
# The shell side therefore reads only precomputed files. It never starts
# pwsh: the loader runs on every interactive shell start, and paying
# PowerShell's startup cost there would be felt on every new tab.

function Get-ShellRuntimePath {
    # Staged copy of shell/tstyles.sh under the data root.
    #
    # The loader block in ~/.zshrc points here rather than at the module
    # directory, because a PSResourceGet upgrade installs to a NEW versioned
    # directory -- a path baked into ~/.zshrc at install time would dangle after
    # the first update. The data root is stable across versions.
    Join-Path $script:TStylesDataRoot 'tstyles.sh'
}

function Get-ShellPromptPath { Join-Path $script:TStylesDataRoot 'current-prompt.sh' }
function Get-ShellOscPath    { Join-Path $script:TStylesDataRoot 'current-style.osc' }

function Get-ShellCliPath { Join-Path $script:TStylesDataRoot 'tstyles-cli.ps1' }

# WHY the last staging step failed, in the OS's own words.
#
# A status names the CATEGORY of failure, which is what the caller branches on,
# and it cannot also carry the reason -- but the reason is the actionable half:
# "access is denied" and "no space left on the device" send the user to two
# different places. Set by the function that returns the non-'ok' status, and
# valid only for the caller that just received one.
$script:TStylesShellStagingError = $null

function Sync-ShellRuntime {
    # Refresh the staged runtime from the module. Runs on every apply so an
    # upgraded module's runtime replaces the staged copy without the user having
    # to re-run shell-init.
    #
    # Returns a STATUS, not a boolean:
    #   'ok'       -- tstyles.sh and the generated shim are staged and current
    #   'nosource' -- shell/tstyles.sh is not in the module: a broken install
    #   'failed'   -- the data root would not take the write; the reason is in
    #                 $script:TStylesShellStagingError
    #
    # The last two are two unrelated things that used to be one $false, and the
    # caller printed the FIRST cause for both. So a user whose data root was
    # read-only, root-owned after a sudo install, or simply full was told
    # "shell/tstyles.sh missing from the module" -- which sends them to reinstall
    # the module, the one action that cannot help -- while the directory really
    # at fault was never named. Same rule as Unregister-ShellLoader's four
    # statuses, and the same reason.
    $script:TStylesShellStagingError = $null
    $src = Join-Path (Join-Path $script:TStylesModuleRoot 'shell') 'tstyles.sh'
    if (-not (Test-Path -LiteralPath $src)) { return 'nosource' }
    try {
        # -ErrorAction Stop because Copy-Item ALSO writes the failure to the
        # error stream: without it a red "Access to the path ... is denied"
        # printed immediately above the message that contradicted it.
        Copy-Item -LiteralPath $src -Destination (Get-ShellRuntimePath) -Force -ErrorAction Stop

        # Entry point for the `tstyles` shell function. Generated rather than
        # shipped because a BOOTSTRAP install is not on $env:PSModulePath, so
        # `Import-Module TerminalStyles` by name would find nothing there and
        # the absolute path has to be baked in. That is the same rule
        # Invoke-TerminalStylesRegister applies to the $PROFILE loader.
        #
        # A PSGallery install is the other case and needs the opposite. Its
        # module root is a VERSION-stamped directory, and Update-PSResource
        # installs alongside rather than in place -- three versions are a normal
        # sight under ~/.local/share/powershell/Modules/TerminalStyles. Baking
        # that path in pinned the shell's `tstyles` to whichever version was
        # current when shell-init last ran, permanently: `tstyles update` from
        # zsh ran Update-PSResource, printed "Update complete", and the next
        # `tstyles` still executed the old code, so the user silently kept every
        # bug the release had fixed.
        #
        # "Regenerated on every apply, so an upgrade refreshes the path" -- the
        # note that used to stand here -- cannot be true of it. The regeneration
        # runs INSIDE the module the shim just loaded, so $script:TStylesModuleRoot
        # is the stale root and it rewrites the same stale path. A fixed point.
        # Nothing reachable from the shell could break out of it.
        #
        # By name, PowerShell's own autoload picks the highest version, which is
        # what an update is for. The user module directory is on the default
        # PSModulePath in any pwsh, whatever shell started it.
        $moduleManifest = Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1'
        # Doubled for the single-quoted string it is interpolated into. An
        # apostrophe in the path -- ~/Documents/O'Brien/... is an ordinary macOS
        # home -- otherwise closed the quote early and produced a shim that
        # could not parse, so every `tstyles` call from zsh died on a syntax
        # error while Sync-ShellRuntime reported success.
        $manifestLiteral = $moduleManifest.Replace("'", "''")
        $importLine = if ((Get-TerminalStylesInstallKind) -eq 'Bootstrap') {
            "Import-Module '$manifestLiteral' -DisableNameChecking"
        } else {
            'Import-Module TerminalStyles -DisableNameChecking'
        }
        $cli = @"
# Generated by TerminalStyles -- do not edit; rewritten on every style apply.
# Entry point for the ``tstyles`` shell function in tstyles.sh.
`$ErrorActionPreference = 'Stop'
# Load the library WITHOUT its shell-startup behaviour. A normal import
# re-emits the CURRENTLY applied style's palette and dot-sources its
# profile.ps1 -- so ``tstyles list`` from zsh repainted the terminal and printed
# the old style's banner before it listed anything.
`$global:TStylesNoAutoLoad = `$true
$importLine
Invoke-TerminalStyle @args
"@
        [System.IO.File]::WriteAllText((Get-ShellCliPath), $cli, [System.Text.UTF8Encoding]::new($false))
        return 'ok'
    } catch {
        $script:TStylesShellStagingError = $_.Exception.Message
        return 'failed'
    }
}

function Set-ShellStyleState {
    # Stage everything the zsh/bash loader needs for $StyleName:
    #   current-style.osc  -- the exact escape packet, so a new tab restores the
    #                         palette with one `cat` and no computation
    #   current-prompt.sh  -- the style's prompt/banner, if it ships one
    #
    # Best-effort throughout: a PowerShell user with no shell integration set up
    # should never see an apply fail because these could not be written.
    #
    # Best effort still has to REPORT, so it returns 'ok' or 'failed' (with the
    # reason in $script:TStylesShellStagingError) rather than nothing. The catch
    # below used to be `} catch { }`, and these two files are what every FUTURE
    # zsh/bash tab reads: one failed write left them on the PREVIOUS style while
    # the apply printed its ordinary green success block and told the user the
    # style was saved for the next tab. The half that repaints THIS tab has
    # always reported its own failure precisely; this is the half that decides
    # every tab after it.
    #
    # Both call sites must CONSUME the status -- a bare statement would emit it
    # into `tstyles`' own output. tests/Picker-ShellStateStaging.Tests.ps1 walks
    # the AST for that.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)]$Scheme,
        [switch]$KeepPrompt
    )
    $script:TStylesShellStagingError = $null
    try {
        $enc = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Get-ShellOscPath),
            (Get-SchemeOscPacket -Scheme $Scheme), $enc)

        $promptSrc = Join-Path $StyleDir 'prompt.sh'
        $promptDst = Get-ShellPromptPath
        if (-not $KeepPrompt -and (Test-Path -LiteralPath $promptSrc)) {
            Copy-Item -LiteralPath $promptSrc -Destination $promptDst -Force
        } elseif (Test-Path -LiteralPath $promptDst) {
            # -KeepPrompt, or a style with no shell prompt: drop the previous
            # style's, or the old prompt would outlive the style that installed it.
            Remove-Item -LiteralPath $promptDst -Force -ErrorAction SilentlyContinue
        }

        # Deliberately NOT folded into the status above. A stale or unwritten
        # tstyles.sh does not change what the next tab looks like: the rc block
        # sources whatever is there, and the palette and prompt staged above are
        # the new style's. shell-init is the command that promises the runtime,
        # and it reports this failure with the path and the reason.
        [void](Sync-ShellRuntime)
        return 'ok'
    } catch {
        $script:TStylesShellStagingError = $_.Exception.Message
        return 'failed'
    }
}

function Show-ShellStagingFailure {
    # The notice both apply doors print when Set-ShellStyleState could not
    # stage. Written once on purpose: `tstyles <name>` and the picker stage the
    # same two files, they have already drifted apart over exactly this -- the
    # picker did not stage them at all for several releases -- and a notice that
    # exists on one door and not the other is the defect this whole file is
    # being edited for.
    #
    # Leading blank line, no trailing one: the callers own their own spacing.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Status)
    if ($Status -eq 'ok') { return }
    Write-Host ""
    Write-Host ("  Could not stage the shell files under {0}: {1}" -f
                $script:TStylesDataRoot, $script:TStylesShellStagingError) -ForegroundColor Yellow
    Write-Host "  New zsh/bash tabs will keep the PREVIOUS style until that is fixed." -ForegroundColor Yellow
}

function Clear-ShellStyleState {
    # Inverse of Set-ShellStyleState. The staged runtime (tstyles.sh) stays --
    # it is the loader's target, and removing it would break the block in
    # ~/.zshrc rather than just unstyling the shell.
    foreach ($p in @((Get-ShellOscPath), (Get-ShellPromptPath))) {
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ShellLoaderBlock {
    # The block written into ~/.zshrc / ~/.bashrc. Marker comments match the
    # PowerShell loader's so uninstall can strip both with one pattern.
    #
    # Guarded on the runtime existing: if the user removes TerminalStyles
    # without running uninstall, the block does nothing instead of printing
    # "no such file" on every shell start.
    #
    # An `if` rather than `[ -r ... ] && . ...`. The && form is silent but it is
    # NOT a no-op: when the runtime is gone the compound command is false, and
    # since this block is the last thing in the rc file, the whole file exits 1.
    # `set -e; source ~/.bashrc` then aborts before doing any work,
    # `source ~/.bashrc && next-step` skips next-step, and every new terminal
    # opens with a failed-status indicator and no failing command to explain it.
    # Verified: healthy 0, orphaned 1, both shells. The `if` form exits 0 either
    # way.
    # SINGLE-quoted, not double. Double quotes protect spaces and apostrophes
    # but not $, ` or \ -- and a home directory containing a '$' is perfectly
    # legal. With `"..."` the shell expanded it, the path came out wrong, and
    # the runtime silently never loaded: no colours, no prompt, no error, on
    # every shell forever. Single quotes make every byte literal; an embedded
    # apostrophe is closed, escaped and reopened, which is the only character
    # single quotes cannot carry.
    $runtime = (Get-ShellRuntimePath).Replace("'", "'\''")
    return @"
# ===== TerminalStyles BEGIN =====
if [ -r '$runtime' ]; then . '$runtime'; fi
# ===== TerminalStyles END =====
"@
}

function Get-ShellRcCandidate {
    # The rc files worth registering in, with the shell each belongs to.
    # ~/.bash_profile is included because macOS Terminal.app starts bash as a
    # LOGIN shell, which reads .bash_profile and never .bashrc.
    param(
        # Test seam: real callers omit it and the live $HOME is used.
        [string]$HomeDir = $HOME,
        # The zsh config directory, normally $env:ZDOTDIR. Its own seam,
        # because -HomeDir alone could not sandbox it -- see below.
        [string]$ZDotDir
    )

    # -HomeDir means a SANDBOX, and the ambient $env:ZDOTDIR is not part of it.
    #
    # This read used to be $env:ZDOTDIR directly, which made -HomeDir a seam
    # that leaked: three of the four candidates honoured it and the fourth
    # reached straight past it into the caller's real environment. The test
    # suite paid for that. tests/Uninstall-ReversesShellInit.Tests.ps1 calls
    # shell-init with -HomeDir pointed at a TestDrive, and on any machine with
    # ZDOTDIR set -- the standard XDG zsh layout, and every dotfile framework
    # that relocates zsh config, which is exactly the setup this candidate was
    # ADDED for -- running the suite appended a loader block to the developer's
    # own zsh config, pointing at a Pester temp path that is deleted when the
    # run ends. Nothing removed it; the run reported PASS=27 FAIL=0.
    #
    # So a caller that sandboxes the home and says nothing about the zsh config
    # dir gets no ZDOTDIR candidate at all. A caller that wants one names it.
    # Callers that sandbox neither -- `tstyles shell-init`, and uninstall's
    # bare call -- still get the live environment, so the feature is unchanged
    # for every real user.
    if (-not $PSBoundParameters.ContainsKey('ZDotDir')) {
        $ZDotDir = if ($PSBoundParameters.ContainsKey('HomeDir')) { $null } else { $env:ZDOTDIR }
    }

    # $ZDOTDIR first when it is set: zsh reads $ZDOTDIR/.zshrc and does NOT read
    # ~/.zshrc, so for anyone with a relocated config (the standard XDG layout,
    # and every dotfile framework that uses one) the block went into a file zsh
    # never opens. shell-init reported success and no shell ever loaded it.
    $zdot = @()
    if ($ZDotDir -and (Test-Path -LiteralPath $ZDotDir)) {
        $zdotRc = Join-Path $ZDotDir '.zshrc'
        if ($zdotRc -ne (Join-Path $HomeDir '.zshrc')) {
            $zdot = @([pscustomobject]@{ Shell = 'zsh'; Path = $zdotRc })
        }
    }
    $zdot
    @(
        [pscustomobject]@{ Shell = 'zsh';  Path = (Join-Path $HomeDir '.zshrc') }
        [pscustomobject]@{ Shell = 'bash'; Path = (Join-Path $HomeDir '.bashrc') }
        [pscustomobject]@{ Shell = 'bash'; Path = (Join-Path $HomeDir '.bash_profile') }
    )
}


function Get-ShellRcRemovalCandidate {
    <#
    .SYNOPSIS
    Every rc file the loader could be IN -- a superset of the files it is
    written to.

    .DESCRIPTION
    Registration and removal are not the same list, and treating them as one
    left a block that nothing could ever take out.

    `Get-ShellRcCandidate` is the REGISTRATION list, and ~/.profile is
    deliberately not on it: it is sh's file rather than bash's, and writing to
    it unasked would reach past the shells this tool claims. But shell-init
    registers there anyway in the one case where it is the only file the login
    shell will read -- a home with a ~/.profile and no .bash_profile, where
    creating a .bash_profile would shadow a file already in use. Two branches
    do this (the .bashrc-exists branch and the nothing-existed fallback).

    Removal iterated the REGISTRATION list, so it never looked at ~/.profile.
    `tstyles shell-remove` reported "removed from ~/.bashrc" and "Open a new tab
    to get your original prompt back" while the block sat in ~/.profile, which
    is precisely the file the login shell reads. After `tstyles uninstall` it
    pointed at a deleted data root, on every login shell, with nothing left on
    the machine to remove it and no message that it was there.

    So: write to the narrow list, sweep the wide one. A file with no block
    returns 'none' from Unregister-ShellLoader and a file that does not exist is
    never created, so the extra entry costs nothing when it was never used.
    #>
    param(
        # Same seams as Get-ShellRcCandidate, forwarded exactly -- binding
        # -HomeDir there means a sandbox and suppresses the ambient $env:ZDOTDIR,
        # and that rule has to survive the hop through here.
        [string]$HomeDir = $HOME,
        [string]$ZDotDir
    )
    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('ZDotDir')) { $splat.ZDotDir = $ZDotDir }

    @(Get-ShellRcCandidate @splat) +
    @([pscustomobject]@{ Shell = 'sh'; Path = (Join-Path $HomeDir '.profile') })
}

function Get-RcFileEncoding {
    <#
    .SYNOPSIS
    The encoding to read and write a user's rc file with.

    .DESCRIPTION
    ISO-8859-1, which maps every byte 0-255 to exactly one character and back.
    Reading and writing an rc file through it is byte-preserving whatever the
    file really is, and the markers and loader block this module cares about are
    pure ASCII either way.

    It used to be UTF-8. Both halves read the WHOLE file and write the WHOLE
    file back, so a single byte that is not valid UTF-8 -- a latin-1 comment, a
    stray byte from an old editor -- was decoded to U+FFFD on the first
    shell-init and written back as the replacement character. The user's own
    content, silently and permanently corrupted, by a tool that was only asked
    to append three lines.
    #>
    return [System.Text.Encoding]::GetEncoding(28591)
}

function Save-FirstTouchBackup {
    <#
    .SYNOPSIS
    Back up a user's own config file the FIRST time TerminalStyles edits it.

    .DESCRIPTION
    Every rc file and $PROFILE this project writes is a file the USER owns and
    that predates us. install.ps1 has backed one up since it was written --
    `<path>.bak-<timestamp>`, once, skipped when the loader block is already
    there, pinned by tests/Install-Hardening.Tests.ps1 -- and the module half
    never did. So `tstyles shell-init` and `tstyles register` rewrote a
    hand-maintained .zshrc or profile.ps1 with no copy kept anywhere, and
    `shell-remove` rewrote it again on the way out.

    FIRST TOUCH is the whole rule, and the reason is that a backup taken later
    is worth less: once our block is in the file, a fresh copy would capture a
    file that already carries it. The pristine version -- the one the user
    would actually want back -- exists only before we first write. That is also
    why the block being present means SKIP rather than "back up again".

    Returns the backup path when one was written, else $null. Never throws: a
    failed backup must not stop the operation, which is itself recoverable.

    NOTE the guard order. `$Content -match ''` is TRUE for every string, so a
    bare `-match $BlockPattern` with an empty pattern would report "already
    ours" and silently skip the backup on every call -- the exact opposite of
    the intent. The `$BlockPattern -and` is load-bearing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        # Matches when the file already carries our block. Empty/absent means
        # "cannot tell", which errs toward taking the backup.
        [AllowEmptyString()][string]$BlockPattern
    )

    if ($BlockPattern -and $Content -match $BlockPattern) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        $bak = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $bak -Force -ErrorAction Stop
        return $bak
    } catch { return $null }
}

function Register-ShellLoader {
    # Add (or refresh) the loader block in one rc file. Returns the action taken
    # so the caller can report it: 'added', 'updated', 'unchanged', 'skipped',
    # 'malformed', or 'failed' when the file could not be written.
    #
    # 'malformed' is the same state Unregister-ShellLoader names, on the same
    # bytes: a BEGIN marker with no matching END. It was missing here, and the
    # refresh branch below then matched nothing, wrote the file back
    # byte-for-byte and returned 'updated' -- so shell-init printed the file in
    # cyan as registered and told the user to `source` it, having written
    # nothing, and said the same on every run afterwards. In the shape this
    # state usually arrives in -- a block deleted by hand down to its first line
    # -- there is no loader in that file at all. The status vocabulary exists so
    # the two halves of the pair cannot disagree about what a file is.
    #
    # 'failed' rather than an exception: shell-init registers into several rc
    # files in a loop, and one unwritable file (read-only, owned by root, on a
    # full disk) used to abort the whole command with a raw .NET
    # MethodInvocationException -- after some files had already been written and
    # before anything was reported, so the user saw a stack trace and had no
    # idea which of their rc files had been touched.
    #
    # Only touches a file that already exists, unless -Create is passed: silently
    # creating ~/.bashrc on a machine that only uses zsh would be a surprise.
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Create,
        [switch]$Force
    )
    $begin = '# ===== TerminalStyles BEGIN ====='
    $end   = '# ===== TerminalStyles END ====='
    $block = Get-ShellLoaderBlock
    $enc   = Get-RcFileEncoding

    $exists = Test-Path -LiteralPath $Path
    if (-not $exists -and -not $Create) { return 'skipped' }

    $content = if ($exists) { [System.IO.File]::ReadAllText($Path, $enc) } else { '' }

    if ($content -match [regex]::Escape($begin)) {
        # The span is TEMPERED -- it may not cross a second BEGIN -- and that is
        # the whole of what keeps this path from eating the user's own lines.
        # `BEGIN .*? END` under Singleline is lazy in the END, not in the BEGIN:
        # the match still starts at the FIRST BEGIN in the file and runs to the
        # first END anywhere after it. So an rc file carrying a stray or
        # duplicated BEGIN -- a hand edit, a merged dotfile, an interrupted
        # write, the inputs Unregister-ShellLoader's docstring already names --
        # had every line between that marker and the real block's END replaced
        # by this three-line block. With no way back: the first-touch rule below
        # skips a file that already carries a BEGIN, so the one path that can
        # destroy content the user wrote was the one path that never took a
        # copy. Refusing to cross a BEGIN makes the match fail at the stray
        # marker and start again at the real one, which is the block we own.
        $pattern = [regex]::Escape($begin) + '(?:(?!' + [regex]::Escape($begin) + ')[\s\S])*?' + [regex]::Escape($end)
        # A BEGIN with no END to close it. Everything below assumes the span
        # exists: the Replace would match nothing, write the identical bytes
        # back and report 'updated'. Checked before the -Force branch, because
        # -Force skips the comparison and went straight to that Replace.
        #
        # [regex]::IsMatch with the Singleline option rather than -notmatch:
        # PowerShell's operator has no Singleline, so `.` would not cross the
        # newlines between the markers and every ordinary multi-line block would
        # be called malformed.
        if (-not [regex]::IsMatch($content, $pattern, 'Singleline')) { return 'malformed' }
        if (-not $Force) {
            # Already registered. Compare the body so an upgraded data root or
            # runtime path is picked up without -Force.
            $existing = [regex]::Match($content, $pattern, 'Singleline').Value
            if ($existing.Trim() -eq $block.Trim()) { return 'unchanged' }
        }
        $updated = [regex]::Replace($content, $pattern, $block.Trim(), 'Singleline')
        try { [System.IO.File]::WriteAllText($Path, $updated, $enc) } catch { return 'failed' }
        return 'updated'
    }

    # Append. A newline guard keeps the block from landing on the same line as
    # whatever the user's rc file ended with.
    # One newline before the block, and Unregister-ShellLoader substitutes
    # exactly one back. It used to append a blank line as well and give only one
    # back, so every init/remove cycle grew the file by a line -- shell-remove
    # was not the byte-exact reversal it is documented to be.
    $sep = if ($content -and -not $content.EndsWith("`n")) { "`n" } else { '' }
    # First touch: this is the one moment the user's pristine file still exists.
    # The refresh path above does not back up, and should not -- the block is
    # already there, so a copy would capture a file that carries it.
    $bak = Save-FirstTouchBackup -Path $Path -Content $content -BlockPattern ([regex]::Escape($begin))
    try {
        [System.IO.File]::WriteAllText($Path, $content + $sep + $block.Trim() + "`n", $enc)
    } catch { return 'failed' }
    if ($bak) { Write-Host "    backed up your original to: $bak" -ForegroundColor DarkGray }
    return 'added'
}

function Test-ShellLoaderPresent {
    <#
    .SYNOPSIS
    Is the loader block in this rc file? Reads; never writes.

    .DESCRIPTION
    Unregister-ShellLoader answers the same question, but only by stripping the
    block. The uninstall consent listing has to name the files it is about to
    change BEFORE the user has agreed to change anything, so it needs the
    question asked on its own.

    Same encoding as the rest of the rc handling, and an Ordinal Contains rather
    than -match: the marker is a fixed string, and -match would write to the
    automatic $Matches for a caller that never asked it to.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $content = [System.IO.File]::ReadAllText($Path, (Get-RcFileEncoding))
    } catch { return $false }
    return $content.Contains('# ===== TerminalStyles BEGIN =====')
}

function Get-UninstallShellRcTarget {
    <#
    .SYNOPSIS
    The rc files an uninstall will actually strip the loader from.

    .DESCRIPTION
    The removal superset filtered down to the files that really carry a block,
    so the consent listing names what will change and nothing else. Pure: it
    reads the files and writes none of them.

    Seams forwarded by what the caller BOUND, the same rule Get-ShellRcCandidate
    documents -- binding -HomeDir means a sandbox and suppresses the ambient
    $env:ZDOTDIR, and that has to survive every hop.
    #>
    [CmdletBinding()]
    param([string]$HomeDir, [string]$ZDotDir)

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('ZDotDir')) { $splat.ZDotDir = $ZDotDir }

    @(Get-ShellRcRemovalCandidate @splat | Where-Object { Test-ShellLoaderPresent -Path $_.Path })
}

function Unregister-ShellLoader {
    <#
    .SYNOPSIS
    Strip the loader block from one rc file.

    .OUTPUTS
    'removed'   -- the block was there and is gone
    'none'      -- no block in this file (or the file does not exist)
    'malformed' -- a BEGIN marker with no matching END; nothing was removed
    'failed'    -- the block is there and the file could not be written

    A STATUS, not a boolean, because the three failure modes are not the same
    thing and were being reported as one. Two of them lied to the user:

      * A BEGIN with no END (hand-edited rc, interrupted write) made the
        Replace match nothing. The unchanged text was written back and $true
        returned, so shell-remove said the loader was removed and a new tab
        would restore the prompt -- while every new shell still sourced the
        runtime.
      * An unwritable rc file (read-only dotfiles, a symlink into a nix or
        chezmoi store) returned the same $false as "there was no block here",
        and the caller turned that into "No shell loader was registered." --
        telling the user the opposite of the truth and sending them looking for
        a block the tool had just denied existed.

    Callers must compare explicitly. `if (Unregister-ShellLoader ...)` is true
    for EVERY status now, including 'none'.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'none' }
    $begin = '# ===== TerminalStyles BEGIN ====='
    $end   = '# ===== TerminalStyles END ====='
    $enc   = Get-RcFileEncoding
    # The READ is guarded as well as the write. It was not, so an rc file this
    # user cannot read threw a raw MethodInvocationException straight out of
    # both callers -- past every remaining rc file, past the WezTerm cleanup and
    # past the $PROFILE strip, in the middle of an uninstall. 'failed' is the
    # right answer for the same reason it is when the write is refused: the
    # block is still in a file we could not deal with.
    try {
        $content = [System.IO.File]::ReadAllText($Path, $enc)
    } catch { return 'failed' }
    if ($content -notmatch [regex]::Escape($begin)) { return 'none' }

    # Tempered exactly as Register-ShellLoader's span is, and for the same
    # reason: `.*?` anchored at the first BEGIN swallows everything up to the
    # first END, so a stray BEGIN above a real block made shell-remove -- and
    # uninstall, which strips through this function -- delete the user's own
    # lines and report 'removed'. The 'malformed' guard below could not catch
    # it: `$stripped -eq $content` only fires when there is no END ANYWHERE, and
    # this input matched fine. Removal takes no backup either, by the same
    # first-touch rule, so the loss was silent and total.
    $pattern = '\r?\n?' + [regex]::Escape($begin) + '(?:(?!' + [regex]::Escape($begin) + ')[\s\S])*?' + [regex]::Escape($end) + '\r?\n?'
    $stripped = [regex]::Replace($content, $pattern, "`n", 'Singleline')
    if ($stripped -eq $content) { return 'malformed' }

    # Same reasoning as Register-ShellLoader: one unwritable rc file must not
    # take down a shell-remove that has already stripped others.
    try { [System.IO.File]::WriteAllText($Path, $stripped, $enc) } catch { return 'failed' }
    return 'removed'
}

function Remove-ShellLoaderBlock {
    <#
    .SYNOPSIS
    Strip the loader from a list of rc files and report what happened to each.

    .DESCRIPTION
    ONE implementation of the reporting rule, because there are two callers --
    `tstyles shell-remove` and `tstyles uninstall` -- and they diverged.
    shell-remove switched on all four of Unregister-ShellLoader's statuses;
    uninstall kept `if ((Unregister-ShellLoader -Path $c.Path) -eq 'removed')`,
    which is an explicit comparison against exactly one of them and throws the
    other three away. So an unwritable rc file (the managed-dotfile case that
    function's docstring names) and a BEGIN with no END printed nothing at all,
    were counted as nothing, and the command signed off on "TerminalStyles
    uninstalled." with the block still in files its own consent screen had just
    listed by name -- after step 1 had removed the module, so `shell-remove`
    could no longer take them out either.

    .OUTPUTS
    [pscustomobject] Removed  = how many blocks went
                     Problems = the paths still carrying one

    The caller decides what to say about those two numbers, because the two
    commands close on different sentences. Neither gets to decide whether a
    failure is mentioned at all.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Path)

    $removed = 0
    $problems = @()
    foreach ($p in $Path) {
        switch (Unregister-ShellLoader -Path $p) {
            'removed' {
                Write-Host ("  removed the loader from {0}" -f $p) -ForegroundColor Green
                $removed++
            }
            'malformed' {
                Write-Host ("  ! {0} has a TerminalStyles BEGIN marker with no matching END." -f $p) -ForegroundColor Red
                Write-Host "    Nothing was removed. Delete the block by hand -- it still loads on every shell." -ForegroundColor Red
                $problems += $p
            }
            'failed' {
                Write-Host ("  ! could not write {0}" -f $p) -ForegroundColor Red
                Write-Host "    The loader is still there. Check the file's permissions (a read-only" -ForegroundColor Red
                Write-Host "    dotfile, or a symlink into a managed store) and remove the block by hand." -ForegroundColor Red
                $problems += $p
            }
            # 'none' is the ordinary case for an rc file that never carried a
            # block, and says nothing on purpose.
        }
    }
    [pscustomobject]@{ Removed = $removed; Problems = @($problems) }
}

function Invoke-TerminalStylesShellInit {
    # `tstyles shell-init` -- register the loader in the user's zsh/bash rc
    # files so a non-PowerShell shell picks up the applied style too.
    # `tstyles shell-remove` (-Remove) takes it back out.
    #
    # Idempotent: re-running refreshes a stale block rather than appending a
    # second one. -Force rewrites even a block that already matches.
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$Remove,
        # Test seam: real callers omit it and the live $HOME is used.
        [string]$HomeDir = $HOME,
        # The zsh config dir. Omitted by real callers, who get $env:ZDOTDIR.
        [string]$ZDotDir
    )

    # Forwarded by what the caller actually BOUND, not by value. All three
    # cases -- bare, sandboxed, and explicitly named -- are then decided in one
    # place, Get-ShellRcCandidate, where each is directly testable. Resolving
    # here as well would duplicate the rule in a second frame, and only one of
    # the two could be covered by a test that does not write to the real $HOME.
    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('ZDotDir')) { $splat.ZDotDir = $ZDotDir }

    $candidates = Get-ShellRcCandidate @splat

    if ($Remove) {
        # The WIDE list: shell-init can register into ~/.profile, which is not a
        # registration candidate. Sweeping the narrow list left that block in
        # place while reporting the loader removed.
        $candidates = Get-ShellRcRemovalCandidate @splat

        # Each status reported for what it is, through the helper uninstall
        # sweeps with too. A failure and a malformed block both used to read as
        # "nothing was registered", so the user was told the loader was gone
        # while every new shell still sourced it.
        #
        # Projected with ForEach-Object rather than `$candidates.Path`: member
        # access on an empty collection yields one $null, and a list with one
        # empty path in it is not the same as an empty list.
        $swept = Remove-ShellLoaderBlock -Path @($candidates | ForEach-Object { $_.Path })
        $removed  = $swept.Removed
        $problems = $swept.Problems
        Clear-ShellStyleState
        if ($problems.Count -gt 0) {
            Write-Host ""
            Write-Host "  Shell loader NOT fully removed. See the file(s) above." -ForegroundColor Yellow
        } elseif ($removed -eq 0) {
            Write-Host "  No shell loader was registered." -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "  Open a new tab to get your original prompt back."
        }
        return
    }

    # Two different failures, two different sentences. One boolean here named
    # the first cause for both, so a user whose data root would not take the
    # write was told their install was missing a file.
    $sync = Sync-ShellRuntime
    if ($sync -eq 'nosource') {
        Write-Error "Could not stage the shell runtime (shell/tstyles.sh missing from the module). Reinstall TerminalStyles."
        return
    } elseif ($sync -ne 'ok') {
        Write-Error ("Could not write the shell runtime into {0}: {1} Check that directory's permissions and free space." -f
                     $script:TStylesDataRoot, $script:TStylesShellStagingError)
        return
    }

    # Register in every rc file the user actually has. Registering only the
    # login shell's would miss the common case of someone who uses zsh
    # interactively but keeps a bash rc for scripts -- and costs nothing.
    # Shell is carried alongside Path because everything below has to know
    # which shell a touched file belongs to, and asking the path ('*zshrc')
    # would be a second implementation of what Get-ShellRcCandidate already
    # decided -- one that also has no answer for ~/.profile.
    $touched = @()
    foreach ($c in $candidates) {
        $action = Register-ShellLoader -Path $c.Path -Force:$Force
        if ($action -ne 'skipped') {
            $touched += [pscustomobject]@{ Path = $c.Path; Shell = $c.Shell; Action = $action }
        }
    }

    # WHICH SHELL THE USER ACTUALLY LOGS IN TO. This lived inside the "nothing
    # existed" fallback below, which fires only when not one rc file was found
    # -- so on every other path the three decisions that follow (create a login
    # file, register in ~/.profile, name a file to source) were taken with no
    # idea which shell the user runs, and all three assumed bash.
    #
    # A zsh user with a leftover ~/.bashrc and no ~/.zshrc -- a pre-Catalina Mac,
    # or any home an nvm/pyenv/conda installer has dropped a .bashrc into; macOS
    # zsh has no newuser hook, so it never writes a ~/.zshrc for you -- therefore
    # got two green "added" lines naming bash files, a ~/.bash_profile invented
    # for them, "source ~/.bashrc", and a new zsh tab with nothing in it at all.
    #
    # $env:SHELL is unset on Windows and empty in some daemons, and 'bash' is the
    # answer both cases had before, so the default keeps them as they were.
    $loginShell = if ($env:SHELL -and $env:SHELL -match 'zsh') { 'zsh' } else { 'bash' }

    # A bash user needs the LOGIN file, and it is the one most likely absent.
    # macOS Terminal.app starts bash as a login shell, which reads
    # ~/.bash_profile and never ~/.bashrc -- that is why .bash_profile is in the
    # candidate list at all. But Register-ShellLoader skips a file that does not
    # exist, and the -Create fallback below only fired when NOTHING was
    # registered. So a bash user with a .bashrc and no .bash_profile got a green
    # "added ~/.bashrc", opened a new Terminal window, and saw nothing: default
    # prompt, default colours, no banner, and no hint that the file the style
    # needs was never written.
    #
    # Created as a source of .bashrc plus the block, which is the conventional
    # shape -- a bare .bash_profile would stop bash reading ~/.profile, and
    # would leave their own .bashrc unloaded in login shells exactly as before.
    #
    # Gated on the login shell, which it was not: it fired for a zsh user with a
    # .bashrc too, inventing a ~/.bash_profile they never had (shell-remove
    # strips the block but leaves the file), or writing into their ~/.profile --
    # which `tstyles help shell-init` says is touched only "when that is the
    # only file your login shell reads", and for a zsh login shell it is not.
    # Registering in rc files that already EXIST stays unconditional; this
    # branch is the one that creates and reaches past them.
    $bashrc       = $candidates | Where-Object { $_.Path -like '*.bashrc' }       | Select-Object -First 1
    $bashProfile  = $candidates | Where-Object { $_.Path -like '*.bash_profile' } | Select-Object -First 1
    $dotProfile   = Join-Path $HomeDir '.profile'
    if ($loginShell -eq 'bash' -and
        $bashrc -and $bashProfile -and
        (Test-Path -LiteralPath $bashrc.Path) -and
        -not (Test-Path -LiteralPath $bashProfile.Path)) {

        if (Test-Path -LiteralPath $dotProfile) {
            # They have a ~/.profile that login bash reads today. Register there
            # rather than creating a .bash_profile that would shadow it.
            $action = Register-ShellLoader -Path $dotProfile -Force:$Force
            if ($action -ne 'skipped') {
                # Recorded as the LOGIN shell's file, not as sh's. ~/.profile is
                # sh's by ownership, but the only reason it was written is that
                # it is what this login shell reads, and that is the question
                # the closing hint asks of this list.
                $touched += [pscustomobject]@{ Path = $dotProfile; Shell = $loginShell; Action = $action }
            }
        } else {
            $seed = "# Created by TerminalStyles: bash login shells read this file, never" + [Environment]::NewLine +
                    "# ~/.bashrc. Sourcing it here is the conventional way to get both." + [Environment]::NewLine +
                    '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' + [Environment]::NewLine
            try {
                [System.IO.File]::WriteAllText($bashProfile.Path, $seed, [System.Text.UTF8Encoding]::new($false))
                $action = Register-ShellLoader -Path $bashProfile.Path -Force:$Force
                $touched += [pscustomobject]@{ Path = $bashProfile.Path; Shell = 'bash'; Action = $action }
                Write-Host ""
                Write-Host ("  Created {0}, which is what bash reads for a login shell" -f $bashProfile.Path) -ForegroundColor DarkGray
                Write-Host "  (Terminal.app opens one). It sources your ~/.bashrc." -ForegroundColor DarkGray
            } catch {
                Write-Host ("  ! could not create {0}: {1}" -f $bashProfile.Path, $_.Exception.Message) -ForegroundColor Yellow
            }
        }
    }

    # The same rescue for zsh, which never got one. Bash's exists because its
    # login file is the one most likely to be absent; for zsh the ONLY file is
    # likely to be absent, and then not a single line of the loop above reached
    # the shell the user opens tabs in. It still printed a green "added" for
    # whatever bash rc happened to be lying around.
    #
    # The FIRST zsh candidate is the file zsh will actually read:
    # Get-ShellRcCandidate puts $ZDOTDIR/.zshrc ahead of ~/.zshrc, and zsh reads
    # ~/.zshrc only when ZDOTDIR is unset -- so "some .zshrc was written" is not
    # the test; "the one zsh opens was written" is.
    if ($loginShell -eq 'zsh') {
        $zshrc = $candidates | Where-Object { $_.Shell -eq 'zsh' } | Select-Object -First 1
        if ($zshrc -and -not (Test-Path -LiteralPath $zshrc.Path)) {
            $action = Register-ShellLoader -Path $zshrc.Path -Create -Force:$Force
            $touched += [pscustomobject]@{ Path = $zshrc.Path; Shell = 'zsh'; Action = $action }
            if ($action -ne 'failed') {
                Write-Host ""
                Write-Host ("  Created {0}, the file zsh reads on every new tab --" -f $zshrc.Path) -ForegroundColor DarkGray
                Write-Host "  you had no zsh rc file, and zsh is your login shell." -ForegroundColor DarkGray
            }
        }
    }

    # Nothing existed to register in. Create the rc file for the login shell
    # rather than doing nothing and leaving the user to guess.
    #
    # The zsh rescue above now always leaves an entry in $touched for a zsh
    # login shell (it registers the file or reports the failure), so in practice
    # this is the bash arm. It is left general rather than rewritten as a bash
    # branch: $loginShell still chooses the target, so if the rescue's condition
    # ever narrows, this keeps covering what it stops covering.
    if (-not $touched) {
        $target = $candidates | Where-Object Shell -eq $loginShell | Select-Object -First 1
        $action = Register-ShellLoader -Path $target.Path -Create
        $touched += [pscustomobject]@{ Path = $target.Path; Shell = $target.Shell; Action = $action }
        # A bash login shell reads .bash_profile, so creating only .bashrc would
        # have produced the same silent nothing as above.
        if ($loginShell -eq 'bash' -and $target.Path -like '*.bashrc') {
            $bp = $candidates | Where-Object { $_.Path -like '*.bash_profile' } | Select-Object -First 1
            if ($bp -and -not (Test-Path -LiteralPath $dotProfile)) {
                $seed = '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' + [Environment]::NewLine
                try {
                    [System.IO.File]::WriteAllText($bp.Path, $seed, [System.Text.UTF8Encoding]::new($false))
                    $touched += [pscustomobject]@{ Path = $bp.Path
                                                   Shell = 'bash'
                                                   Action = (Register-ShellLoader -Path $bp.Path -Force:$Force) }
                } catch { }
            } elseif (Test-Path -LiteralPath $dotProfile) {
                # ~/.profile exists, so we must not create a .bash_profile: bash
                # reads the FIRST of .bash_profile, .bash_login, .profile and
                # stops, and a new .bash_profile would shadow a file they are
                # already using. The block above declines for that reason -- but
                # declining was all it did, which left the loader in the .bashrc
                # just created and login bash reading a ~/.profile that never
                # sources it. That is the bug this whole branch exists to avoid,
                # surviving in the one layout the branch did not cover.
                #
                # ~/.profile is not a candidate (it is sh's, not bash's, and
                # registering in it unasked would reach past the shells this tool
                # claims), so nothing else in this function will have touched it.
                # Here it is the only file the login shell will read.
                $action = Register-ShellLoader -Path $dotProfile -Force:$Force
                if ($action -ne 'skipped') {
                    $touched += [pscustomobject]@{ Path = $dotProfile; Shell = $loginShell; Action = $action }
                }
            }
        }
    }

    Write-Host ""
    foreach ($t in $touched) {
        $color = switch ($t.Action) {
            'added'     { 'Green' }
            'updated'   { 'Cyan' }
            'failed'    { 'Red' }
            'malformed' { 'Red' }
            default     { 'Gray' }
        }
        Write-Host ("  {0,-9} {1}" -f $t.Action, $t.Path) -ForegroundColor $color
        if ($t.Action -eq 'failed') {
            Write-Host "            (could not write it -- check the file's permissions)" -ForegroundColor DarkGray
        }
        if ($t.Action -eq 'malformed') {
            Write-Host "            (a TerminalStyles BEGIN marker with no matching END -- nothing" -ForegroundColor DarkGray
            Write-Host "             was written. Delete that line by hand and run this again.)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    # Name the file that was actually registered. This was hardcoded to
    # ~/.zshrc and printed unconditionally, so a bash user who had just had
    # .bashrc and .bash_profile written was told to source a zsh file they may
    # not even have.
    #
    # Then it named whichever file came first, which is candidate order, not the
    # user's order: a zsh user whose ~/.bashrc was registered before their
    # ~/.zshrc existed was told "source ~/.bashrc" -- advice that does nothing in
    # the shell they are sitting in. Prefer a file the LOGIN shell reads; fall
    # back to the first only when none was touched.
    #
    # The filter is on the statuses that mean "there is no loader in this file",
    # not on 'failed' alone: 'malformed' writes nothing either, and naming it
    # here sent the user to `source` a file that has no loader line in it.
    $written  = @($touched | Where-Object { $_.Action -notin @('failed', 'malformed') })
    $hintPath = (@($written | Where-Object { $_.Shell -eq $loginShell }) + $written |
                 Select-Object -First 1).Path
    if ($hintPath) {
        $shown = if ($hintPath.StartsWith($HomeDir)) { '~' + $hintPath.Substring($HomeDir.Length) } else { $hintPath }
        Write-Host ("  Open a new tab, or run:  source {0}" -f $shown) -ForegroundColor DarkGray
    } else {
        Write-Host "  Open a new tab to pick it up." -ForegroundColor DarkGray
    }
    Write-Host ""
}

# === Terminal.app profiles (colors + background image) =====================
#
# OSC escape sequences cover colors, but there is no escape sequence for a
# background image -- an image can only reach Terminal.app through a profile.
# So a style that ships one is applied by writing a .terminal profile and
# opening it, which gives a new window carrying the whole style.
#
# The profile format is unforgiving: colors are NSKeyedArchiver archives of
# NSColor, and the image is an archive of an NSMutableData holding a
# security-scoped bookmark. Get any of that wrong and Terminal rejects the file
# wholesale as "corrupt", naming no key. shell/appleterminal.js builds those
# blobs; this half assembles them into a plist.

# scheme.json field -> Terminal.app profile key. Terminal names the magenta slot
# "Magenta" where a Windows Terminal scheme calls it "purple".
$script:TStylesAppleColorMap = [ordered]@{
    background          = 'BackgroundColor'
    foreground          = 'TextColor'
    cursorColor         = 'CursorColor'
    selectionBackground = 'SelectionColor'
    black               = 'ANSIBlackColor'
    red                 = 'ANSIRedColor'
    green               = 'ANSIGreenColor'
    yellow              = 'ANSIYellowColor'
    blue                = 'ANSIBlueColor'
    purple              = 'ANSIMagentaColor'
    cyan                = 'ANSICyanColor'
    white               = 'ANSIWhiteColor'
    brightBlack         = 'ANSIBrightBlackColor'
    brightRed           = 'ANSIBrightRedColor'
    brightGreen         = 'ANSIBrightGreenColor'
    brightYellow        = 'ANSIBrightYellowColor'
    brightBlue          = 'ANSIBrightBlueColor'
    brightPurple        = 'ANSIBrightMagentaColor'
    brightCyan          = 'ANSIBrightCyanColor'
    brightWhite         = 'ANSIBrightWhiteColor'
}

function Get-AppleTerminalProfileData {
    # Run the JXA helper over a scheme (+ optional image) and return a hashtable
    # of Terminal profile key -> base64 archive. Returns $null when the helper
    # is missing or fails; callers fall back to the OSC-only path.
    param(
        [Parameter(Mandatory)]$Scheme,
        [string]$BackgroundImage
    )
    $helper = Join-Path (Join-Path $script:TStylesModuleRoot 'shell') 'appleterminal.js'
    if (-not (Test-Path -LiteralPath $helper)) { return $null }

    $colors = [ordered]@{}
    foreach ($field in $script:TStylesAppleColorMap.Keys) {
        $hex = $Scheme.$field
        if ($hex) { $colors[$script:TStylesAppleColorMap[$field]] = [string]$hex }
    }

    $tmpRoot  = [System.IO.Path]::GetTempPath()
    $runId    = [guid]::NewGuid().Guid.Substring(0, 8)
    $specPath = Join-Path $tmpRoot "tstyles-spec-$runId.json"
    $outPath  = Join-Path $tmpRoot "tstyles-out-$runId.json"
    $enc      = [System.Text.UTF8Encoding]::new($false)

    try {
        $spec = [pscustomobject]@{
            colors = $colors
            image  = if ($BackgroundImage) { $BackgroundImage } else { '' }
        }
        [System.IO.File]::WriteAllText($specPath, ($spec | ConvertTo-Json -Depth 5), $enc)

        & osascript -l JavaScript $helper $specPath $outPath *> $null
        if (-not (Test-Path -LiteralPath $outPath)) { return $null }

        $json = [System.IO.File]::ReadAllText($outPath, $enc)
        if (-not $json.Trim()) { return $null }

        $result = @{}
        foreach ($p in ($json | ConvertFrom-Json).PSObject.Properties) {
            $result[$p.Name] = [string]$p.Value
        }
        if ($result.Count -eq 0) { return $null }
        return $result
    } catch {
        return $null
    } finally {
        foreach ($f in @($specPath, $outPath)) {
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
    }
}

function ConvertTo-AppleTerminalBackground {
    # Terminal.app renders a still image but NOT an animated GIF: a profile
    # pointing at one gets a blank background, with no error anywhere. Every
    # bundled background in this project is a GIF, so without this the feature
    # appears to do nothing at all -- which is exactly how it was first reported.
    #
    # Converts a GIF to a static PNG (sips takes the first frame) and caches the
    # result beside the original. Anything already static is returned unchanged.
    # On failure the original path is returned: a background that silently does
    # not render is no worse than the state before, and is not worth failing an
    # apply over.
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -ne '.gif') { return $Path }

    $still = [System.IO.Path]::ChangeExtension($Path, '.still.png')
    # Reuse a previous conversion unless the source has since changed.
    if (Test-Path -LiteralPath $still) {
        try {
            if ((Get-Item -LiteralPath $still).LastWriteTimeUtc -ge (Get-Item -LiteralPath $Path).LastWriteTimeUtc) {
                return $still
            }
        } catch { }
    }

    if (-not (Get-Command sips -ErrorAction SilentlyContinue)) { return $Path }
    try {
        & sips -s format png $Path --out $still *> $null
        if ((Test-Path -LiteralPath $still) -and (Get-Item -LiteralPath $still).Length -gt 0) {
            return $still
        }
    } catch { }
    return $Path
}

function New-AppleTerminalProfile {
    # Write a .terminal profile for $StyleName and return its path.
    #
    # Emitted as an XML plist rather than binary: the values that must be binary
    # are already base64 <data>, and XML keeps the file inspectable when
    # something goes wrong -- which, given how silently Terminal rejects a bad
    # profile, matters more here than the few hundred bytes it costs.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)]$Scheme,
        [string]$BackgroundImage,
        [string]$ProfileName,
        [string]$OutPath
    )
    if (-not $ProfileName) { $ProfileName = "TerminalStyles $StyleName" }
    if (-not $OutPath) {
        $dir = Join-Path $script:TStylesDataRoot 'profiles'
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $OutPath = Join-Path $dir "$StyleName.terminal"
    }

    # Animated GIFs do not render in Terminal.app; hand the profile a still.
    if ($BackgroundImage) {
        $BackgroundImage = ConvertTo-AppleTerminalBackground -Path $BackgroundImage
    }

    $data = Get-AppleTerminalProfileData -Scheme $Scheme -BackgroundImage $BackgroundImage
    if (-not $data) { return $null }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
    [void]$sb.AppendLine('<plist version="1.0">')
    [void]$sb.AppendLine('<dict>')
    # type + ProfileCurrentVersion are what mark this as an importable window
    # setting; without them Terminal opens the file as a document instead.
    [void]$sb.AppendLine('	<key>name</key>')
    [void]$sb.AppendLine("	<string>$([System.Security.SecurityElement]::Escape($ProfileName))</string>")
    [void]$sb.AppendLine('	<key>type</key>')
    [void]$sb.AppendLine('	<string>Window Settings</string>')
    [void]$sb.AppendLine('	<key>ProfileCurrentVersion</key>')
    [void]$sb.AppendLine('	<real>2.0699999999999998</real>')
    foreach ($key in ($data.Keys | Sort-Object)) {
        [void]$sb.AppendLine("	<key>$key</key>")
        [void]$sb.AppendLine("	<data>$($data[$key])</data>")
    }
    [void]$sb.AppendLine('</dict>')
    [void]$sb.AppendLine('</plist>')

    [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    return $OutPath
}
