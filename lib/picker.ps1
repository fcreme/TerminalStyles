# picker.ps1 -- the interactive picker's testable pieces.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# The picker itself is a keyboard UI and lives in Invoke-TerminalStyle, where it
# cannot be driven by a test. What CAN be tested was carved out here: the
# selection loop with its I/O injected as scriptblocks, and the viewport
# arithmetic that keeps the frame inside the window. Both exist in this shape
# for that reason and no other.

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
            if ($null -ne $scheme) { $swatch = Get-SchemeSwatch -Scheme $scheme }
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
    # Carved out here for the same reason Invoke-StylePickerLoop and
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

function Invoke-StylePickerLoop {
    # The interactive picker's selection loop, with all I/O / rendering / input
    # injected as seams so it can be driven by tests. Owns ONLY the highlight
    # index, the pendingApply debounce, and key dispatch. Returns the outcome:
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
        [Parameter(Mandatory)][int]$StyleCount,
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
                    if ($idx -lt $StyleCount - 1) {
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
