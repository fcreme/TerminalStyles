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
    # where a writer exists: Windows Terminal's settings.json and Terminal.app's
    # .terminal profile. Not to be confused with a style surviving a new tab,
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
        # Ghostty / WezTerm / kitty / Alacritty all keep their settings in a
        # config file this module has never learned to write -- ghostty's
        # `config`, `wezterm.lua`, `kitty.conf`, `alacritty.toml`. Each of them
        # can do fonts and opacity, and WezTerm does animated background
        # images, but none of that reaches the user through TerminalStyles
        # today. What genuinely works on all four is the OSC retint, which is
        # the whole live-preview path, so that is what is claimed.
        #
        # Adding a writer for any of these is the moment to turn its flags back
        # on -- one terminal at a time, next to the code that delivers it.
        'Ghostty' {
            $caps.OscPalette = $true
        }
        'WezTerm' {
            $caps.OscPalette = $true
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

function Sync-ShellRuntime {
    # Refresh the staged runtime from the module. Runs on every apply so an
    # upgraded module's runtime replaces the staged copy without the user having
    # to re-run shell-init.
    $src = Join-Path (Join-Path $script:TStylesModuleRoot 'shell') 'tstyles.sh'
    if (-not (Test-Path -LiteralPath $src)) { return $false }
    try {
        Copy-Item -LiteralPath $src -Destination (Get-ShellRuntimePath) -Force

        # Entry point for the `tstyles` shell function. Generated rather than
        # shipped so the module root is baked in at stage time: a zsh user has
        # no PSModulePath set up, and `Import-Module TerminalStyles` by name
        # would fail for a bootstrap install. Regenerated on every apply, so an
        # upgrade to a new versioned directory refreshes the path.
        $moduleManifest = Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1'
        $cli = @"
# Generated by TerminalStyles -- do not edit; rewritten on every style apply.
# Entry point for the ``tstyles`` shell function in tstyles.sh.
`$ErrorActionPreference = 'Stop'
Import-Module '$moduleManifest' -DisableNameChecking
Invoke-TerminalStyle @args
"@
        [System.IO.File]::WriteAllText((Get-ShellCliPath), $cli, [System.Text.UTF8Encoding]::new($false))
        return $true
    } catch {
        return $false
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
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)]$Scheme,
        [switch]$KeepPrompt
    )
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

        [void](Sync-ShellRuntime)
    } catch { }
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
    # without running uninstall, the block becomes a no-op instead of printing
    # "no such file" on every shell start.
    $runtime = Get-ShellRuntimePath
    return @"
# ===== TerminalStyles BEGIN =====
[ -r "$runtime" ] && . "$runtime"
# ===== TerminalStyles END =====
"@
}

function Get-ShellRcCandidate {
    # The rc files worth registering in, with the shell each belongs to.
    # ~/.bash_profile is included because macOS Terminal.app starts bash as a
    # LOGIN shell, which reads .bash_profile and never .bashrc.
    param([string]$HomeDir = $HOME)
    @(
        [pscustomobject]@{ Shell = 'zsh';  Path = (Join-Path $HomeDir '.zshrc') }
        [pscustomobject]@{ Shell = 'bash'; Path = (Join-Path $HomeDir '.bashrc') }
        [pscustomobject]@{ Shell = 'bash'; Path = (Join-Path $HomeDir '.bash_profile') }
    )
}

function Register-ShellLoader {
    # Add (or refresh) the loader block in one rc file. Returns the action taken
    # so the caller can report it: 'added', 'updated', 'unchanged', or 'skipped'.
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
    $enc   = [System.Text.UTF8Encoding]::new($false)

    $exists = Test-Path -LiteralPath $Path
    if (-not $exists -and -not $Create) { return 'skipped' }

    $content = if ($exists) { [System.IO.File]::ReadAllText($Path, $enc) } else { '' }

    if ($content -match [regex]::Escape($begin)) {
        if (-not $Force) {
            # Already registered. Compare the body so an upgraded data root or
            # runtime path is picked up without -Force.
            $pattern = [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
            $existing = [regex]::Match($content, $pattern, 'Singleline').Value
            if ($existing.Trim() -eq $block.Trim()) { return 'unchanged' }
        }
        $pattern = [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
        $updated = [regex]::Replace($content, $pattern, $block.Trim(), 'Singleline')
        [System.IO.File]::WriteAllText($Path, $updated, $enc)
        return 'updated'
    }

    # Append. A newline guard keeps the block from landing on the same line as
    # whatever the user's rc file ended with.
    $sep = if ($content -and -not $content.EndsWith("`n")) { "`n" } else { '' }
    [System.IO.File]::WriteAllText($Path, $content + $sep + "`n" + $block.Trim() + "`n", $enc)
    return 'added'
}

function Unregister-ShellLoader {
    # Strip the block from one rc file. Returns $true if something was removed.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $begin = '# ===== TerminalStyles BEGIN ====='
    $end   = '# ===== TerminalStyles END ====='
    $enc   = [System.Text.UTF8Encoding]::new($false)
    $content = [System.IO.File]::ReadAllText($Path, $enc)
    if ($content -notmatch [regex]::Escape($begin)) { return $false }

    $pattern = '\r?\n?' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end) + '\r?\n?'
    $stripped = [regex]::Replace($content, $pattern, "`n", 'Singleline')
    [System.IO.File]::WriteAllText($Path, $stripped, $enc)
    return $true
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
        [string]$HomeDir = $HOME
    )

    $candidates = Get-ShellRcCandidate -HomeDir $HomeDir

    if ($Remove) {
        $removed = 0
        foreach ($c in $candidates) {
            if (Unregister-ShellLoader -Path $c.Path) {
                Write-Host ("  removed from {0}" -f $c.Path) -ForegroundColor Yellow
                $removed++
            }
        }
        Clear-ShellStyleState
        if ($removed -eq 0) {
            Write-Host "  No shell loader was registered." -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "  Open a new tab to get your original prompt back."
        }
        return
    }

    if (-not (Sync-ShellRuntime)) {
        Write-Error "Could not stage the shell runtime (shell/tstyles.sh missing from the module)."
        return
    }

    # Register in every rc file the user actually has. Registering only the
    # login shell's would miss the common case of someone who uses zsh
    # interactively but keeps a bash rc for scripts -- and costs nothing.
    $touched = @()
    foreach ($c in $candidates) {
        $action = Register-ShellLoader -Path $c.Path -Force:$Force
        if ($action -ne 'skipped') {
            $touched += [pscustomobject]@{ Path = $c.Path; Action = $action }
        }
    }

    # Nothing existed to register in. Create the rc file for the login shell
    # rather than doing nothing and leaving the user to guess.
    if (-not $touched) {
        $loginShell = if ($env:SHELL -and $env:SHELL -match 'zsh') { 'zsh' } else { 'bash' }
        $target = $candidates | Where-Object Shell -eq $loginShell | Select-Object -First 1
        $action = Register-ShellLoader -Path $target.Path -Create
        $touched += [pscustomobject]@{ Path = $target.Path; Action = $action }
    }

    Write-Host ""
    foreach ($t in $touched) {
        $color = switch ($t.Action) {
            'added'     { 'Green' }
            'updated'   { 'Cyan' }
            default     { 'Gray' }
        }
        Write-Host ("  {0,-9} {1}" -f $t.Action, $t.Path) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "  Open a new tab, or run:  source ~/.zshrc" -ForegroundColor DarkGray
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
