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
    param(
        [Parameter(Mandatory)][bool]$IsPwshTarget,
        [Parameter(Mandatory)][bool]$ProfilePresent
    )
    return $IsPwshTarget -and $ProfilePresent
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
