# picker.ps1 -- the interactive picker's testable pieces.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# The picker itself is a keyboard UI and lives in Invoke-TerminalStyle, where it
# cannot be driven by a test. What CAN be tested was carved out here: the
# selection loop with its I/O injected as scriptblocks, and the viewport
# arithmetic that keeps the frame inside the window. Both exist in this shape
# for that reason and no other.

function Get-StyleMeta {
    <#
    .SYNOPSIS
    A style's one-line description and its quote, from its own meta.json.

    .DESCRIPTION
    Lives IN the style, not in a catalog, and that is the point. A central list
    of descriptions is a second list of styles, and this project has already
    paid for one: docs/index.html carries a hand-written description per style,
    and when `halo` was removed its entry had to be found and deleted by hand.
    A file inside the folder cannot drift from the folder.

    It is also why the descriptions here are SHORT. The long-form prose belongs
    in the style's README, which is written for a reader with a whole screen;
    this one has to fit a picker row on a narrow terminal, so it is capped and
    a test holds the cap.

    Returns @{ Description = <string>; Quote = <string> }, both empty when the
    style ships no meta.json -- which a hand-dropped user style will not, and
    which must degrade to the name alone rather than to an error.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

    $empty = @{ Description = ''; Quote = '' }
    $path = Join-Path $StyleDir 'meta.json'
    if (-not (Test-Path -LiteralPath $path)) { return $empty }
    try {
        $m = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return $empty }
    if (-not $m) { return $empty }
    @{
        Description = "$($m.description)".Trim()
        Quote       = "$($m.quote)".Trim()
    }
}

function Get-PickerFramePlan {
    # The whole frame budget in one place: how many rows the chrome costs, how
    # many styles fit, and how tall the frame will be.
    #
    # It exists because the caller used to do this arithmetic inline and got it
    # off by one. Get-PickerViewport's contract is about $Available, and the
    # picker computed $Available as `$wh - $chrome` -- at which point the frame
    # paints exactly $wh rows and the newline ending the last one scrolls the
    # buffer. The saved home row then no longer points at the top of the menu,
    # which is the garbling this function's sibling docstring describes. Reported
    # from a real WezTerm window with 17 styles: the header repeating down the
    # screen, and short rows wearing the tails of longer ones --
    #   "Choose a style for WezTermto keep, Esc to cancel"
    #
    # ChromeRows is what the frame spends on things that are not styles: the
    # leading blank, the header, the two hint lines, the blank under them, the
    # two always-present scroll indicators and the trailing blank -- plus one row
    # per optional note. Both indicators are always emitted, blank when there is
    # nothing to report, so the height is identical on every redraw.
    #
    # A non-positive WindowHeight means "I don't know", not "no room". It reads
    # as 0 under a pty whose size was never set -- some CI runners, some SSH
    # sessions before the first SIGWINCH -- and budgeting from that would
    # collapse the menu to one row, far worse than the unbounded frame this
    # exists to prevent; so it falls back to drawing everything.
    #
    # Returns @{ ChromeRows; Available; First; Count; More; FrameRows; Fits }.
    # Pure, so the arithmetic is testable without a terminal.
    param(
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$WindowHeight,
        [int]$NoteCount = 0,
        [bool]$TipRow = $true
    )

    # 9, not 7: the two rows under the list that describe the highlighted
    # style -- its one-liner and its quote. BOTH are always painted, blank when
    # the style has no meta.json or no quote, for the same reason the scroll
    # indicators are: the frame is overwritten in place, so a row that comes and
    # goes strands the taller frame's last line on screen. A style with no quote
    # must cost exactly what a style with one costs.
    #
    # The tip row is the tenth, and the only one the picker can give back. It
    # says "run tstyles help for all commands" -- useful the first few times
    # and then a permanent tax: one fewer style visible in every window, for
    # the life of the tool. The controls line above it is not the same thing;
    # that one has to be there every time, because it is what the keys do.
    $chrome = 9 + [Math]::Max(0, $NoteCount)
    if ($TipRow) { $chrome++ }
    # -1: reserve a row the frame will not paint, so ending the last line cannot
    # scroll the buffer.
    $available = if ($WindowHeight -gt 0) { $WindowHeight - $chrome - 1 } else { $Total }
    $vp = Get-PickerViewport -Total $Total -Selected $Selected -Available $available
    $rows = $chrome + $vp.Count
    @{
        ChromeRows = $chrome
        Available  = $available
        First      = $vp.First
        Count      = $vp.Count
        More       = $vp.More
        FrameRows  = $rows
        # False only when the window cannot hold the chrome at all -- the menu
        # still draws (one row beats none), and the caller reclaims the screen
        # rather than painting at an origin the scroll has invalidated.
        Fits       = ($WindowHeight -le 0) -or ($rows -lt $WindowHeight)
    }
}

function Get-PickerViewport {
    # Which slice of the style list to draw, so the menu always fits the window.
    #
    # The picker redraws by parking the cursor at a fixed row and overwriting in
    # place. That only works while the whole frame fits below that row: draw more
    # rows than the terminal has and it scrolls, the saved home row no longer
    # points at the top of the menu, and every later redraw lands in the wrong
    # place and garbles. With 17 styles the frame is already 23 rows in a 24-row
    # window -- two more user styles and it breaks.
    #
    # Returns @{ First = <index>; Count = <how many>; More = <bool> }, keeping the
    # selection visible and the window stable while arrowing through the middle.
    # Pure, so the arithmetic is testable without a terminal.
    param(
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$Available
    )

    if ($Total -le 0) { return @{ First = 0; Count = 0; More = $false } }

    # At least one row, even in an absurdly short window: a picker showing
    # nothing is worse than one showing a single entry.
    $visible = [Math]::Max(1, [Math]::Min($Total, $Available))
    if ($visible -ge $Total) { return @{ First = 0; Count = $Total; More = $false } }

    # Centre the selection, then clamp so the window never runs off either end.
    $first = $Selected - [int][Math]::Floor($visible / 2)
    if ($first -lt 0) { $first = 0 }
    if ($first + $visible -gt $Total) { $first = $Total - $visible }

    return @{ First = $first; Count = $visible; More = $true }
}


function Get-PickerStyleSet {
    # The picker's working set: every style whose scheme.json actually PARSES,
    # with that parsed scheme and its swatch, read once, up front.
    #
    # Get-AvailableStyles admits a folder on scheme.json EXISTING, never on it
    # parsing, so a hand-authored style with a JSON typo -- README invites them
    # in that directory -- or a `tstyles tune` save killed mid-write (Save-
    # TunedStyle writes the file with a plain, non-atomic WriteAllText) reaches
    # the picker as an ordinary entry. The pre-load loop that used to sit inline
    # in Invoke-TerminalStyle parsed it with no guard, and that cost two
    # different failures, one per $ErrorActionPreference:
    #
    #   Stop     -- the generated tstyles-cli.ps1 sets it, and shell/tstyles.sh
    #               runs that for every `tstyles` call from zsh and bash. There
    #               ConvertFrom-Json's error is fully terminating: bare
    #               `tstyles` printed a raw .NET parse error naming a line of
    #               this module, never the style, and drew no menu at all.
    #   Continue -- pwsh's default, where the same error is only statement-
    #               terminating. The loop carried on with $scheme still holding
    #               the PREVIOUS style's object, so the broken style took the
    #               previous style's swatch, the previous style's live OSC
    #               preview and, on Enter, the previous style's palette written
    #               into current-style.osc under the broken style's name --
    #               replayed by every new zsh/bash tab, with nothing on screen
    #               after the first red block to say so.
    #
    # A style that fails the parse is therefore not in the returned set at all.
    # $idx, $startIdx, $swatches, $schemes, $titles, $oscPackets and
    # $mergedCache are all keyed by position, so keeping it with a $null scheme
    # only moves the crash into the draw path. Dropping it is the picker's
    # counterpart to the row `tstyles list` marks "(unreadable scheme.json)",
    # not a disagreement with it -- and the caller has to SAY which folders it
    # dropped, or the picker becomes the one command that answers "where did my
    # style go?" with silence.
    #
    # Returns @{ Styles = @(...); Schemes = @{i->obj}; Swatches = @{i->string};
    #            Unreadable = @(names) } -- the two hashtables keyed by index
    # into Styles, which is how the picker indexes them.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Styles)

    $keep       = @()
    $schemes    = @{}
    $swatches   = @{}
    $unreadable = @()

    foreach ($s in $Styles) {
        # Cleared per iteration, deliberately: inheriting the previous style's
        # scheme is precisely what a loop-carried variable does when the
        # statement that should have replaced it did not complete.
        $scheme = $null
        $swatch = $null
        try {
            $scheme = [System.IO.File]::ReadAllText((Join-Path $s.FullName 'scheme.json'),
                          [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            # The swatch is built inside the guard for the same reason
            # Show-StyleList builds its own inside one: a file that parses is
            # not necessarily a scheme, and a row the picker cannot draw is as
            # fatal to the menu as a row it cannot parse.
            # Note-aware, like the row `tstyles list` prints: a scheme that
            # parses but carries no colour this tool can read is KEPT (it is not
            # in $unreadable, and the picker will happily apply it), so drawing
            # it as an empty column was the one row in the menu that said
            # nothing about itself.
            if ($null -ne $scheme) { $swatch = Get-SchemeSwatchOrNote -Scheme $scheme }
        } catch {
            $scheme = $null
        }
        # "It did not throw" is not the test. An empty or whitespace-only file
        # is the other half of a truncated write, and ConvertFrom-Json returns
        # $null for it on pwsh 7 rather than raising -- and $null is unusable
        # everywhere downstream, where -Scheme is Mandatory and refuses to bind.
        if ($null -eq $scheme) { $unreadable += $s.Name; continue }

        $i = $keep.Count
        $keep       += $s
        $schemes[$i]  = $scheme
        $swatches[$i] = $swatch
    }

    return @{
        Styles     = @($keep)
        Schemes    = $schemes
        Swatches   = $swatches
        Unreadable = @($unreadable)
    }
}


function Get-StylePreviewJson {
    # The settings.json the picker would write for one style -- or $null when
    # that style has nothing to put there.
    #
    # Get-StyleSettingsPayload is the function that decides whether a style
    # contributes anything to settings.json at all. Apply-StyleDirect asks it,
    # apply.ps1 asks it, and 0.8.18's CHANGELOG says "all four write paths ...
    # now check first" -- but the picker never did, because it held THREE
    # open-coded copies of ConvertFrom-WTJson -> Merge-StyleIntoSettings ->
    # ConvertTo-Json (the first preview, the per-keystroke apply, the idle
    # prebuild) and none of them asked. A style with a scheme.json and no
    # theme.json is legal -- README documents theme.json as optional and
    # Get-AvailableStyles admits the folder, so it is listed and selectable --
    # and Merge-StyleIntoSettings returns the settings object UNTOUCHED for it.
    # The picker wrote that object anyway, which re-serializes what
    # ConvertFrom-WTJson parsed and drops every // and /* */ comment the user
    # wrote, then printed "Style applied: <name>" in green and recorded the
    # style. So `tstyles current` and the `*` in `tstyles list` both named a
    # style Windows Terminal had never been told about, while `tstyles <name>`
    # on the very same style refused in as many words. The load-bearing copy was
    # the FIRST preview, which fires as the picker opens -- before the user
    # touches a key.
    #
    # One function, so there is one place that asks, and so a fourth copy cannot
    # be added without it. $null means "nothing to write", which the picker's
    # $writeSettings choke point already treats as a no-op -- the gate is the
    # return value rather than a fourth guard beside a fourth merge.
    #
    # Carved out here for the same reason Invoke-PickerLoop and
    # Get-PickerViewport are: the picker body cannot be driven by a test, and a
    # decision that only exists inside it can only ever be asserted on its
    # source text.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$OriginalJson,
        [Parameter(Mandatory)][string]$StyleDir,
        [string]$TargetName,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided
    )

    if (-not (Get-StyleSettingsPayload -StyleDir $StyleDir).Ok) { return $null }

    $preview = ConvertFrom-WTJson $OriginalJson
    $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $StyleDir `
                   -TargetName $TargetName -BackgroundImage $BackgroundImage `
                   -BackgroundImageProvided $BackgroundImageProvided
    # Depth 100 (the JSON max), matching Write-SettingsFile: a user
    # settings.json nested deeper than 32 is silently stringified by
    # ConvertTo-Json, without warning on Windows PowerShell 5.1.
    return $preview | ConvertTo-Json -Depth 100
}


function Test-ShouldRestoreWindowTitle {
    # Is there a window title worth putting back?
    #
    # The picker and the tuner both snapshot $Host.UI.RawUI.WindowTitle before
    # they take over the screen and write it back if the user cancels. That is
    # only a restore on a host that ANSWERS the getter. Terminal.app and iTerm2
    # return an empty string -- the title is the terminal's to know, not the
    # host's -- so "restoring" it assigned '' and wiped whatever the window was
    # showing: on cancel, the previous style's title (set by its own profile.ps1
    # or ts_title) vanished, which is a worse end state than not restoring at all.
    #
    # So: a title we never read is not a title we can put back. Leave the window
    # alone and let whatever set it keep it. Windows Terminal returns a real
    # title and is unaffected.
    #
    # Whitespace counts as nothing for the same reason it reads as nothing --
    # assigning it blanks the window just as surely as ''.
    #
    # Pure, so the decision is testable without a host that has a title bar.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Title)

    return -not [string]::IsNullOrWhiteSpace($Title)
}

function Get-RevertOscPacket {
    <#
    .SYNOPSIS
    The escape packet that puts the terminal back when a preview is cancelled.

    .DESCRIPTION
    The picker's Esc and the tuner's Esc ask one question, and each used to
    answer it with its own inline `if`: re-emit the style the user arrived with,
    or hand colour control back to the terminal with Get-OscResetPacket?

    Get-OscResetPacket resets to the TERMINAL's own configured colours, which is
    right on Windows Terminal -- settings.json has just been restored and WT
    repaints from it. Off Windows Terminal there is no such file: the style the
    user arrived with was itself only escape sequences, so a reset drops them to
    the stock palette instead of back to their style.

    Both copies of that rule were pinned by nothing but a `-Match` against the
    caller's own source text, which cannot see which arm is which: swapping the
    two arms -- the exact regression the rule exists to prevent -- left all 1821
    tests green. Asking one function makes the answer a value a test can compare,
    on every CI leg, with no console.

    Returns a string, never $null or empty. A cancel that emits nothing leaves
    the cancelled preview painted, so a starting scheme this tool cannot read
    falls back to the reset rather than to silence.
    #>
    [CmdletBinding()]
    param(
        # $true on Windows Terminal, where a settings.json was just restored.
        [Parameter(Mandatory)][bool]$UseSettingsFile,
        # Was a style actually active when the preview opened? NOT the same
        # question as "is $StartingScheme non-null": with nothing applied the
        # picker's cursor starts on the first style in the list, whose scheme is
        # a real one the user was never looking at. The stock palette is the
        # correct end state there.
        [bool]$HadStartingStyle,
        # The scheme to re-emit: the style the user OPENED, not the working base
        # -- on a tuned style those are different files.
        $StartingScheme
    )

    if (-not $UseSettingsFile -and $HadStartingStyle -and $null -ne $StartingScheme) {
        $packet = Get-SchemeOscPacket -Scheme $StartingScheme
        if ($packet) { return $packet }
    }
    return (Get-OscResetPacket)
}

function Invoke-PickerLoop {
    # The interactive picker's selection loop, with all I/O / rendering / input
    # injected as seams so it can be driven by tests. Owns ONLY the highlight
    # index, the pendingApply debounce, and key dispatch -- it never learns what
    # is being picked, which is why the font picker drives this loop rather than
    # growing a second one. It was Invoke-StylePickerLoop taking a -StyleCount
    # until fonts became its second caller and the name started to lie.
    #
    # Returns the outcome:
    #   @{ Outcome = 'confirmed' | 'cancelled'; Index = <int> }
    #
    # Seams:
    #   ReadKey   -> a key object with a .Key ([ConsoleKey]), or $null when the
    #                input queue is momentarily empty (drives the debounce tail).
    #   OnPreview -> & $OnPreview $index : the debounced settings.json write.
    #   OnRevert  -> & $OnRevert         : Esc -- restore original settings (+OSC reset).
    #   OnDraw    -> & $OnDraw $index    : render the menu at $index.
    #   OnRetint  -> & $OnRetint $index  : instant per-keystroke OSC color packet.
    #   OnIdle    -> & $OnIdle           : idle slice (prebuild / sleep).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ItemCount,
        [int]$StartIndex = 0,
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$OnPreview,
        [Parameter(Mandatory)][scriptblock]$OnRevert,
        [scriptblock]$OnDraw   = {},
        [scriptblock]$OnRetint = {},
        [scriptblock]$OnIdle   = {}
    )

    $idx          = $StartIndex
    $pendingApply = -1
    $needsRedraw  = $true

    while ($true) {
        if ($needsRedraw) {
            & $OnDraw $idx
            $needsRedraw = $false
        }

        $key = & $ReadKey
        if ($null -ne $key) {
            switch ($key.Key) {
                'UpArrow' {
                    if ($idx -gt 0) {
                        $idx--; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'DownArrow' {
                    if ($idx -lt $ItemCount - 1) {
                        $idx++; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'Enter' {
                    if ($pendingApply -ge 0) {
                        & $OnPreview $pendingApply
                        $pendingApply = -1
                    }
                    return @{ Outcome = 'confirmed'; Index = $idx }
                }
                'Escape' {
                    & $OnRevert
                    return @{ Outcome = 'cancelled'; Index = $idx }
                }
            }
            continue
        }

        # Queue empty -- debounce tail: apply the latest pending preview once.
        if ($pendingApply -ge 0) {
            $applyIdx = $pendingApply
            $pendingApply = -1
            & $OnPreview $applyIdx
            continue
        }

        # Truly idle.
        & $OnIdle
    }
}

function Test-ShouldLiveReloadPrompt {
    # Pure gate: after the picker confirms, should THIS session dot-source the
    # newly installed current-style.ps1?
    #
    # Yes whenever a prompt was actually installed for this shell. The gate
    # used to also require Test-InWindowsTerminal, which made the picker
    # install a style's prompt off Windows Terminal and then decline to load
    # it -- so on the same macOS terminal `tstyles eva` painted the banner and
    # themed prompt while picking eva from the picker painted neither, until
    # the user opened a new tab. Apply-StyleNonWT has always dot-sourced
    # unconditionally at the end of the direct-apply path; this is the picker
    # catching up to it. The WT check was left over from before there was any
    # non-WT path for it to be wrong about.
    #
    # ...and no when $global:TStylesNoAutoLoad is set, which is the "I am not an
    # interactive pwsh session" signal the generated tstyles-cli.ps1 sets
    # (terminals.ps1). From zsh or bash, `tstyles` runs that shim in a one-shot
    # pwsh that exits immediately: dot-sourcing the style's profile.ps1 there
    # reloads nothing and prints the style's whole ASCII banner, and the shell
    # wrapper then re-sources the staged prompt.sh and prints it a SECOND time.
    # Apply-StyleNonWT was fixed for that; the picker's confirm asked this gate
    # instead, which had no way to know the shim was running -- so choosing a
    # style in the picker from bash printed two NERV banners where `tstyles eva`
    # printed one (measured on a pty: 2 vs 1), and confirming the style already
    # staged printed one spuriously. Both doors now ask here, so the two cannot
    # drift apart again.
    param(
        [Parameter(Mandatory)][bool]$IsPwshTarget,
        [Parameter(Mandatory)][bool]$ProfilePresent,
        [Parameter(Mandatory)][bool]$AutoLoadSuppressed
    )
    return $IsPwshTarget -and $ProfilePresent -and (-not $AutoLoadSuppressed)
}

function Test-ShouldPreviewWindowTitle {
    <#
    .SYNOPSIS
    May a preview move the window title at all?

    .DESCRIPTION
    The mirror of Test-ShouldRestoreWindowTitle, and it exists because the two
    halves have to agree: the picker WRITES $Host.UI.RawUI.WindowTitle on its
    first preview and on every arrow key, and restores it on cancel only when
    the snapshot it took is a title worth putting back. On Terminal.app and
    iTerm2 the getter answers '' -- the title is the terminal's to know, not the
    host's -- so the picker was changing a thing it had already decided it could
    not change back. "Reverted." then printed under the rejected style's tab
    title, which survived for the life of the tab: all 16 styles set the title
    once at load, never from `prompt`, so nothing repaints it.

    Measured under the zsh/bash shim, which is where it always bites -- the shim
    sets $TStylesNoAutoLoad, so no style profile has ever run in that process
    and the snapshot is always empty: four OSC 0 title writes during a cancelled
    session and no restoring one after it.

    The answer is deliberately the same as the restore gate's rather than
    "restore ''": assigning an empty title blanks whatever the window was
    showing, which is the worse end state (see Test-ShouldRestoreWindowTitle).
    A confirmed apply still sets the title, through the style's own profile.ps1
    and prompt.sh, which is where that job belongs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$SnapshotTitle)

    return (Test-ShouldRestoreWindowTitle -Title $SnapshotTitle)
}

function Get-PickerCapabilityNote {
    <#
    .SYNOPSIS
    The one line the picker owes the user about what this terminal cannot show,
    or $null.

    .DESCRIPTION
    The picker printed this ABOVE its menu, and its own Clear-Host then wiped
    it: pwsh emits Clear-Host as ESC[3J ESC[H ESC[2J, and ESC[3J erases the
    SCROLLBACK, so the line was not merely scrolled off, it was unrecoverable.
    Measured on a pty: the note at byte 283, the first ESC[3J 410 bytes later,
    in one uninterrupted output burst with no input wait, and the string never
    appears again in the capture.

    tstyles.ps1 had already learned this three times -- $unreadableNote,
    $backupNote and the update notice each carry a comment saying anything
    printed above the menu is wiped unread. This is the note that was left
    outside the frame. Returning it as a value rather than printing it is what
    lets the frame paint it, and lets a test assert it without a console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][bool]$UseSettingsFile
    )

    if (-not (Test-StyledHost -Kind $Kind)) {
        return "  Note: this host doesn't render colors; you'll get the prompt but not the palette."
    }
    # Windows Terminal previews through settings.json, which carries the
    # background image, so the question does not arise there.
    if ($UseSettingsFile) { return $null }
    if (-not (Get-TerminalCapability -Kind $Kind).BackgroundImage) {
        return ("  Note: {0} renders the palette but not background images." -f
                (Get-TerminalDisplayName -Kind $Kind))
    }
    return $null
}

function Get-TStylesWordmark {
    <#
    .SYNOPSIS
    The tstyles wordmark, as lines.

    .DESCRIPTION
    The same lettering install.ps1 prints, and deliberately a SECOND copy of it:
    install.ps1 is fetched and piped to iex before this module exists, so it
    cannot read anything from here. Every other duplicate in this project is
    held in step by a test rather than by hope, and so is this one --
    tests/Install-Hardening.Tests.ps1 compares the two character for character.

    Single-quoted: the lettering is full of backslashes and pipes, and in a
    double-quoted PowerShell string a backtick escapes the next character.
    There is no backtick or $ in it today, and single quotes mean one cannot
    arrive by accident.
    #>
    [CmdletBinding()]
    param()
    ,@(
        '   _       _         _'
        '  | |_ ___| |_ _   _| | ___  ___'
        '  | __/ __| __| | | | |/ _ \/ __|'
        '  | |_\__ \ |_| |_| | |  __/\__ \'
        '   \__|___/\__|\__, |_|\___||___/'
        '                |___/'
    )
}

function Test-ShouldShowWelcome {
    # Pure gate, same shape as Test-ShouldPromptFonts and for the same reasons:
    # once ever, and only where someone can actually see it.
    #
    # The interactive half is not belt-and-braces. This marker is one-time by
    # design, so printing into a redirect would spend it on a banner nobody saw
    # -- which is precisely what happened to the font prompt, and is written up
    # at length above it.
    param(
        [Parameter(Mandatory)][bool]$MarkerPresent,
        [Parameter(Mandatory)][bool]$Interactive
    )
    return (-not $MarkerPresent) -and $Interactive
}

function Invoke-WelcomeFirstRun {
    # The wordmark, once, on the first interactive `tstyles`.
    #
    # It has to HOLD the screen. The picker Clear-Host's on the way in and
    # anything printed above the frame is wiped unread, so a banner that merely
    # printed would flash and vanish -- and would have burned its one-time
    # marker doing it. The font prompt that follows only blocks when IT has
    # something to ask, so this cannot lean on that either.
    #
    # One keypress, once, on the first run of a tool whose whole subject is what
    # the terminal looks like.
    $marker = Join-Path $script:TStylesDataRoot '.welcomed'
    if (-not (Test-ShouldShowWelcome -MarkerPresent (Test-Path -LiteralPath $marker) `
                                     -Interactive (Test-InteractiveConsole))) {
        return
    }

    Write-Host ''
    foreach ($line in (Get-TStylesWordmark)) { Write-Host $line -ForegroundColor Cyan }
    Write-Host '        themed styles for your terminal' -ForegroundColor DarkGray
    Write-Host ''
    $count = @(Get-AvailableStyles).Count
    # Short enough not to wrap. The art is held to 78 by a test, and a hint
    # that wraps under it undoes the point of having any of this.
    Write-Host "  $count styles ready. Arrow to preview, Enter to keep, Esc to cancel." -ForegroundColor Gray
    Write-Host ''

    # The keypress appears only when nothing after it will hold the screen.
    #
    # It exists because the picker Clear-Host's on the way in, so a banner that
    # merely printed would flash past unread. But two real questions follow this
    # on a first run, and each of them blocks -- so on that path the keypress is
    # ceremony in front of someone who has not seen a style yet.
    #
    # Not dropped outright, because "nothing follows" is the COMMON case for
    # people who already use this: they answered the font prompt in an earlier
    # version, so its marker is present and it will not fire, and the welcome is
    # the only new thing on their screen. Asking the two gates rather than
    # assuming is what tells those situations apart.
    $heldByNext =
        (Test-ShouldPromptFonts `
            -MarkerPresent (Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.fonts-prompted')) `
            -Interactive   $true) -or
        (Test-ShouldOfferWezTerm `
            -MarkerPresent    (Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.wezterm-offered')) `
            -Interactive      $true `
            -Platform         (Get-TStylesPlatform) `
            -Kind             (Get-TerminalKind) `
            -AlreadyInstalled (Test-WezTermInstalled) `
            -BrewPresent      ([bool](Get-Command brew -ErrorAction SilentlyContinue)))

    if (-not $heldByNext) { [void](Read-Host '  Press Enter to look') }

    # Written LAST and guarded: a marker written before the banner is shown
    # would spend the one showing on a run that then failed to draw it. A write
    # that fails is not worth taking the picker down for -- the cost is seeing
    # this once more.
    try {
        [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Test-ShouldOfferWezTerm {
    <#
    .SYNOPSIS
    Pure gate for the one-time WezTerm offer. Every condition has to hold.

    .DESCRIPTION
    Installing a GUI application is a far larger intervention than anything else
    this tool does, so the bar is correspondingly high. Each of these rules out
    a case where the offer would be noise or a nuisance:

      MarkerPresent   -- asked once, ever. Same rule as the font prompt.
      Interactive     -- a question printed into a redirect is asked of nobody,
                         and would burn the one asking. That is not theoretical:
                         the font prompt lost its single offer exactly that way.
      Platform MacOS  -- the install route below is a Homebrew cask.
      Kind not WezTerm-- offering it to someone already running it is absurd.
      AlreadyInstalled-- likewise, and it is cheap to check.
      BrewPresent     -- with no brew there is nothing to offer; saying "install
                         Homebrew first" turns a courtesy into a chore.
    #>
    param(
        [Parameter(Mandatory)][bool]$MarkerPresent,
        [Parameter(Mandatory)][bool]$Interactive,
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][bool]$AlreadyInstalled,
        [Parameter(Mandatory)][bool]$BrewPresent
    )
    return (-not $MarkerPresent) -and $Interactive -and ($Platform -eq 'MacOS') -and
           ($Kind -ne 'WezTerm') -and (-not $AlreadyInstalled) -and $BrewPresent
}

function Test-WezTermInstalled {
    # On PATH or in /Applications. Either is enough to mean "do not offer".
    [CmdletBinding()]
    param()
    if (Get-Command wezterm -ErrorAction SilentlyContinue) { return $true }
    return (Test-Path -LiteralPath '/Applications/WezTerm.app')
}

function Install-WezTermViaBrew {
    # The external call, on its own, so the failure path around it can be
    # driven. Pester cannot mock `& brew` -- an external binary is not a
    # command it can intercept -- so a test that tried would pass while
    # exercising nothing, which is exactly what the first version of it did.
    [CmdletBinding()]
    param()
    & brew install --cask wezterm 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

function Invoke-WezTermOfferFirstRun {
    <#
    .SYNOPSIS
    Offer, once, to install WezTerm -- the only terminal off Windows that
    animates a background GIF.

    .DESCRIPTION
    Every bundled style ships an animated GIF, and off Windows exactly one
    terminal renders it as one: Terminal.app can show a still first frame and
    nothing more, and the rest show no image at all. That is a real gap between
    what a style is and what the reader can see of it, and it is worth one
    question.

    ONE question. It defaults to no, it names the exact command it will run
    before running it, and a refusal is recorded the same as a yes -- the offer
    is not repeated on the next run, because an offer that keeps coming back is
    not an offer.

    A failure here is reported and swallowed. The user asked to style their
    terminal; whether Homebrew succeeded is not a reason to stop doing that.
    #>
    $marker = Join-Path $script:TStylesDataRoot '.wezterm-offered'
    $kind   = Get-TerminalKind
    if (-not (Test-ShouldOfferWezTerm `
                -MarkerPresent    (Test-Path -LiteralPath $marker) `
                -Interactive      (Test-InteractiveConsole) `
                -Platform         (Get-TStylesPlatform) `
                -Kind             $kind `
                -AlreadyInstalled (Test-WezTermInstalled) `
                -BrewPresent      ([bool](Get-Command brew -ErrorAction SilentlyContinue)))) {
        return
    }

    $hint = Get-HintEscape
    $rst  = "$([char]27)[0m"
    Write-Host ""
    Write-Host ("  Every style here ships an animated background. {0} shows a still frame at best." -f
                (Get-TerminalDisplayName -Kind $kind)) -ForegroundColor Gray
    Write-Host "  WezTerm is the only terminal off Windows that animates it." -ForegroundColor Gray
    Write-Host "$hint  Installs with: brew install --cask wezterm$rst"
    $ans = Read-Host "  Install WezTerm now? [y/N]"

    # Written whatever the answer: a no is an answer, and asking again next time
    # would make it a nag rather than an offer.
    try {
        [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
    } catch { }

    if ("$ans" -notmatch '^(?i)y') {
        Write-Host "$hint  Skipped. Install it later with: brew install --cask wezterm$rst"
        return
    }

    Write-Host "  Running brew install --cask wezterm..." -ForegroundColor Cyan
    try {
        Install-WezTermViaBrew
        if (Test-WezTermInstalled) {
            Write-Host "  WezTerm installed. Open it, then run tstyles there to see the backgrounds." -ForegroundColor Green
        } else {
            # brew can exit 0 having done nothing useful. Checking beats trusting.
            Write-Host "  brew finished but WezTerm is not on this machine. Install it by hand:" -ForegroundColor Yellow
            Write-Host "    brew install --cask wezterm" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "  Could not install WezTerm: $_" -ForegroundColor Yellow
        Write-Host "    brew install --cask wezterm" -ForegroundColor Cyan
    }
}

function Get-PickerRunCount {
    <#
    .SYNOPSIS
    How many times the picker has been opened on this machine.

    .DESCRIPTION
    Zero for anything unreadable, missing or not a number. This decides only
    whether one hint row is painted, so every failure has to mean "show it" --
    the state being unreadable is not a reason to hide the line that tells a
    newcomer where the commands are.
    #>
    [CmdletBinding()]
    param([string]$DataDir = $script:TStylesDataRoot)

    $path = Join-Path $DataDir '.picker-runs'
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    try {
        $raw = ([System.IO.File]::ReadAllText($path)).Trim()
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 0) { return $n }
        return 0
    } catch { return 0 }
}

function Add-PickerRun {
    <#
    .SYNOPSIS
    Record one more opening of the picker, and return the new count.

    .DESCRIPTION
    Best-effort on the write: a read-only or missing data directory must not
    take the picker down over a counter whose only job is to retire a hint. On
    failure it still returns the incremented count, so the session behaves as
    though it were recorded -- the next session simply counts it again, which
    costs a hint row and nothing else.
    #>
    [CmdletBinding()]
    param([string]$DataDir = $script:TStylesDataRoot)

    $next = (Get-PickerRunCount -DataDir $DataDir) + 1
    try {
        if (-not (Test-Path -LiteralPath $DataDir)) {
            New-Item -ItemType Directory -Path $DataDir -Force -ErrorAction Stop | Out-Null
        }
        [System.IO.File]::WriteAllText((Join-Path $DataDir '.picker-runs'), "$next")
    } catch { }
    return $next
}

function Test-ShouldShowPickerTip {
    <#
    .SYNOPSIS
    Is the "run tstyles help" line still worth a row of the picker?

    .DESCRIPTION
    Pure. The line is onboarding, and onboarding that never ends is a tax: it
    costs a viewport row on every redraw of every session forever, which is one
    fewer style visible in the window. The same reasoning the WezTerm offer is
    built on -- something that comes back every run stops being help.

    A few runs rather than one: a single showing of a hint is easy to miss, and
    unlike an offer nobody has to answer it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RunCount,
        [int]$Limit = 3
    )
    return ($RunCount -le $Limit)
}

function Get-StyleShowLines {
    <#
    .SYNOPSIS
    What `tstyles show` prints about one style, as lines.

    .DESCRIPTION
    Pure: it returns strings and paints nothing, so what the command SAYS can
    be tested without a terminal and without applying anything.

    The capability note is the load-bearing part. `show` repaints the palette
    and nothing else -- it deliberately writes no settings file, no profile and
    no current-style record, because a command whose whole promise is "look
    without committing" must not be the one command that leaves something
    behind. That means a style's background, font and cursor shape are NOT in
    what you see, and on Windows Terminal those are most of the style. Saying
    so is the difference between a preview and a misrepresentation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Scheme,
        $Meta,
        [AllowNull()][string]$Swatch,
        [AllowNull()][string]$CapabilityNote,
        [string]$HintEscape = '',
        [bool]$IsCurrent = $false
    )

    $reset = "$([char]27)[0m"
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('')
    $marker = if ($IsCurrent) { '  (currently applied)' } else { '' }
    $out.Add("  $Name$HintEscape$marker$reset")
    if ($Swatch) { $out.Add("  $Swatch") }
    $out.Add('')
    if ($Meta -and $Meta.Description) { $out.Add("$HintEscape  $($Meta.Description)$reset") }
    if ($Meta -and $Meta.Quote)       { $out.Add("$HintEscape  `"$($Meta.Quote)`"$reset") }
    $out.Add('')
    # Sample text in the scheme's own colours, so the palette is visible as
    # something other than a row of blocks: this is what code will look like.
    $out.Add((Get-StyleShowSample -Scheme $Scheme))
    $out.Add('')
    if ($CapabilityNote) { $out.Add("$HintEscape$CapabilityNote$reset") }
    return $out.ToArray()
}

function Get-StyleShowSample {
    <#
    .SYNOPSIS
    One line of sample text painted in a scheme's own ANSI colours.

    .DESCRIPTION
    A swatch shows five background cells. This shows the colours doing the job
    they are actually for -- foreground text at the weights a terminal uses --
    which is the difference between "these are the colours" and "this is what
    your screen will look like".

    Reads the scheme's slots by name and degrades to the plain string for any
    the scheme does not carry: a hand-authored style is only required to have
    background and foreground.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scheme)

    $esc = [char]27
    # Through ConvertTo-NormalHex, which is this project's one answer to "is
    # that a colour". Its own docstring records what a second opinion cost:
    # two slots tested different patterns, so a shorthand #013 was frozen by
    # the tuner while its neighbours moved, and the swatch silently substituted
    # a different slot than the one it was showing.
    $fg = {
        param($hex, $text)
        $norm = ConvertTo-NormalHex $hex
        if (-not $norm) { return $text }
        $r = [Convert]::ToInt32($norm.Substring(1, 2), 16)
        $g = [Convert]::ToInt32($norm.Substring(3, 2), 16)
        $b = [Convert]::ToInt32($norm.Substring(5, 2), 16)
        "$esc[38;2;$r;$g;$($b)m$text$esc[0m"
    }
    $parts = @(
        (& $fg $Scheme.brightGreen  'function'),
        (& $fg $Scheme.foreground   'Get-Thing'),
        (& $fg $Scheme.brightBlack  '{'),
        (& $fg $Scheme.brightCyan   '$path'),
        (& $fg $Scheme.brightYellow "'~/code'"),
        (& $fg $Scheme.brightRed    'throw'),
        (& $fg $Scheme.brightBlack  '}')
    )
    '  ' + ($parts -join ' ')
}

function Invoke-TerminalStyleShow {
    <#
    .SYNOPSIS
    `tstyles show <name>` -- look at a style without applying it.

    .DESCRIPTION
    The gap this fills: until now the only ways to see a style were to APPLY
    it, or to open the picker and arrow to it. Both change what is applied
    until you back out, and neither is a way to answer "what is lain like"
    from a prompt.

    It repaints the palette and puts it back, and it writes NOTHING: no
    settings file, no profile, no current-style record, no shell staging. A
    command whose whole promise is "look without committing" must not be the
    one command that leaves something behind, so the restore is in a finally
    and the preview never touches the apply path at all.

    The cost of writing nothing is that a style's background, font and cursor
    shape are not in what you see -- on Windows Terminal that is most of a
    style. Get-StyleShowLines says so on screen rather than letting the reader
    assume they have seen the whole thing.

    Non-interactive callers get the description and the palette without the
    repaint: there is no keypress coming to end it, and painting a terminal
    nobody is watching and never putting it back is worse than not painting.

    -ReadKey and -Write are test seams. Real callers omit them.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [scriptblock]$ReadKey,
        [scriptblock]$Write,
        [System.Nullable[bool]]$Interactive
    )

    if (-not $Write) { $Write = { param($line) Write-Host $line } }

    if (-not $Name) {
        & $Write "Usage: tstyles show <name>"
        & $Write "Available: $(@(Get-AvailableStyles | ForEach-Object Name) -join ', ')"
        return
    }

    $dir = Get-StyleDir -StyleName $Name
    if (-not $dir) {
        # Same shape as `tstyles font` uses for an unknown font: name what was
        # asked for, then what could have been.
        & $Write "Unknown style: '$Name'"
        & $Write "Available: $(@(Get-AvailableStyles | ForEach-Object Name) -join ', ')"
        return
    }

    $scheme = $null
    try {
        $scheme = [System.IO.File]::ReadAllText((Join-Path $dir 'scheme.json'),
                    [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { }
    if (-not $scheme) {
        # A style whose scheme.json will not parse is exactly what
        # Get-PickerStyleSet drops, and for the same reason: there is nothing
        # to show and a raw parser exception is not an answer.
        & $Write "'$Name' has no readable scheme.json, so there is nothing to show."
        return
    }

    $kind = Get-TerminalKind
    $note = Get-PickerCapabilityNote -Kind $kind -UseSettingsFile $false
    if (-not $note) {
        $note = '  Colours only: a background, font and cursor shape are not part of this preview.'
    }
    $current = ''
    try { $current = "$(Get-CurrentStyleName)" } catch { }

    $lines = Get-StyleShowLines -Name $Name -Scheme $scheme `
                -Meta (Get-StyleMeta -StyleDir $dir) `
                -Swatch (Get-SchemeSwatchOrNote -Scheme $scheme) `
                -CapabilityNote $note -HintEscape (Get-HintEscape) `
                -IsCurrent ($current -eq $Name)

    $live = if ($null -ne $Interactive) { [bool]$Interactive } else { Test-InteractiveConsole }
    if (-not $live) {
        foreach ($l in $lines) { & $Write $l }
        return
    }

    # What to put back. The style the user is ON, not this one -- and $null
    # when nothing is applied, which Get-RevertOscPacket reads as "hand colour
    # control back to the terminal" rather than "re-emit a style they were
    # never looking at".
    $startScheme = $null
    if ($current) {
        $curDir = Get-StyleDir -StyleName $current
        if ($curDir) {
            try {
                $startScheme = [System.IO.File]::ReadAllText((Join-Path $curDir 'scheme.json'),
                                 [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            } catch { }
        }
    }

    if (-not $ReadKey) {
        $ReadKey = { [void][Console]::ReadKey($true) }
    }

    try {
        & $Write (Get-SchemeOscPacket -Scheme $scheme)
        foreach ($l in $lines) { & $Write $l }
        & $Write ''
        & $Write "$(Get-HintEscape)  Press any key to put it back.$([char]27)[0m"
        & $ReadKey
    } finally {
        # In a finally because a preview that fails halfway through must still
        # put the terminal back: leaving someone in a palette they did not
        # choose, with no record of it anywhere, is the one outcome this
        # command cannot have.
        & $Write (Get-RevertOscPacket -UseSettingsFile $false `
                    -HadStartingStyle ([bool]$startScheme) -StartingScheme $startScheme)
    }
}

function Test-ShouldPromptFonts {
    # Pure gate: only prompt on an interactive session that hasn't been prompted.
    param(
        [Parameter(Mandatory)][bool]$MarkerPresent,
        [Parameter(Mandatory)][bool]$Interactive
    )
    return (-not $MarkerPresent) -and $Interactive
}

function Invoke-FontFirstRunPrompt {
    # One-time opt-in: offer to install the recommended font set. Marker-gated so
    # it never repeats; silent in non-interactive sessions.
    $marker = Join-Path $script:TStylesDataRoot '.fonts-prompted'
    $markerPresent = Test-Path -LiteralPath $marker

    # [Environment]::UserInteractive is NOT enough, and on its own it burned the
    # one thing this function owns. It reports $true whenever the process has a
    # console -- including when stdin or stdout is a pipe or a file -- so a bare
    # `tstyles` with stdin redirected reached the Read-Host below, which returns
    # empty at EOF rather than throwing, and then wrote the marker anyway. The
    # offer is one-time by design, so it was gone: the question went into the
    # redirect, nobody saw it, the answer was nobody's, and no interactive
    # session was ever asked again. Same shape as the update notice the tuner
    # printed and immediately wiped while still burning its 24-hour throttle.
    #
    # Both directions matter. Redirected stdin means the answer is not the
    # user's; redirected stdout means the question is not visible, and a
    # Read-Host then blocks a real console on a prompt nobody can read.
    #
    # This comment used to claim "the picker and the tuner already guard this
    # way". Only the tuner did: the picker checked stdin alone, so `tstyles >
    # file` drove an invisible menu and applied a style blind. Both check both
    # now -- but the claim was written from intent rather than from the code,
    # and was wrong on the day it was written.
    # One spelling, shared with every other gate in the project -- and mockable,
    # which the three .NET statics are not.
    $interactive = Test-InteractiveConsole
    if (-not (Test-ShouldPromptFonts -MarkerPresent $markerPresent -Interactive $interactive)) {
        return
    }

    $ans = Read-Host "Install a set of recommended coding fonts now? [y/N]"
    if ("$ans" -match '^(?i)y') {
        try {
            $catalog = @(Get-FontCatalog)
            foreach ($f in $catalog) {
                if (Test-FontInstalled -Family $f.family) { continue }
                Write-Host "  Installing $($f.name)..." -ForegroundColor Cyan
                try {
                    $files = Resolve-FontPackage -Font $f
                    [void](Install-Font -FontFiles $files)
                } catch {
                    Write-Host "    Skipped $($f.name): $_" -ForegroundColor DarkGray
                }
            }
            Write-Host "Done. Pick fonts anytime with 'tstyles tune' or 'tstyles font'." -ForegroundColor Green
        } catch {
            Write-Host "Font setup failed: $_" -ForegroundColor Red
        }
    }

    # Always record that we've prompted, regardless of the answer.
    try {
        if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
    } catch { }
}
