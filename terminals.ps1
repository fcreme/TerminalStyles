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
    'Persist',         # can we write a config that survives a new tab/window?
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
            # Dynamic Profiles: a JSON file dropped in DynamicProfiles/ is picked
            # up live, no restart. Covers everything except WT's tab styling.
            $caps.OscPalette      = $true
            $caps.Persist         = $true
            $caps.Font            = $true
            $caps.Opacity         = $true
            $caps.CursorShape     = $true
            $caps.BackgroundImage = $true
            $caps.TabTitle        = $true
            $caps.Padding         = $true
        }
        'AppleTerminal' {
            # Persistence goes through a .terminal profile plist. Terminal.app
            # has no background-image support at all, and no per-profile tab
            # accent color.
            #
            # OscPalette is $true on the strength of a round-trip probe against
            # Terminal.app 470 (macOS 26): OSC 4/10/11/12 all answered their
            # query form, setting OSC 11 to #ff00ff read back as ff00/0000/ff00,
            # and OSC 111 / OSC 104 restored the profile defaults exactly. So the
            # picker's live preview and its Esc revert both work here with the
            # same escape packets Windows Terminal uses -- no AppleScript needed
            # on the hot path.
            $caps.OscPalette  = $true
            $caps.Persist     = $true
            $caps.Font        = $true
            $caps.Opacity     = $true
            $caps.CursorShape = $true
            $caps.TabTitle    = $true
        }
        'Ghostty' {
            $caps.OscPalette  = $true
            $caps.Persist     = $true
            $caps.Font        = $true
            $caps.Opacity     = $true
            $caps.CursorShape = $true
            $caps.Padding     = $true
        }
        'WezTerm' {
            $caps.OscPalette      = $true
            $caps.Persist         = $true
            $caps.Font            = $true
            $caps.Opacity         = $true
            $caps.CursorShape     = $true
            $caps.BackgroundImage = $true
            $caps.Padding         = $true
        }
        'Kitty' {
            $caps.OscPalette  = $true
            $caps.Persist     = $true
            $caps.Font        = $true
            $caps.Opacity     = $true
            $caps.CursorShape = $true
            $caps.Padding     = $true
        }
        'Alacritty' {
            $caps.OscPalette  = $true
            $caps.Persist     = $true
            $caps.Font        = $true
            $caps.Opacity     = $true
            $caps.CursorShape = $true
            $caps.Padding     = $true
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
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Packet)
    if (-not $Packet) { return }
    try {
        [Console]::Out.Write($Packet)
        [Console]::Out.Flush()
    } catch {
        # A redirected/absent console (CI, a job runspace) has nothing to paint.
        # Silent by design: colors are cosmetic, and throwing here would abort an
        # otherwise-successful apply.
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
    Write-HostOscPacket -Packet (Get-SchemeOscPacket -Scheme $Scheme)
    return $true
}

function Invoke-TerminalStyleOscReset {
    # Hand color control back to the terminal's own configured scheme.
    param([string]$Kind = (Get-TerminalKind))
    if (-not (Get-TerminalCapability -Kind $Kind).OscPalette) { return $false }
    Write-HostOscPacket -Packet (Get-OscResetPacket)
    return $true
}
