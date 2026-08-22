<#
.SYNOPSIS
    Prepare, drive, and unwind a TerminalStyles demo recording.

.DESCRIPTION
    A recording harness, not a feature. Nothing here reimplements or fakes any
    part of TerminalStyles: the picker that appears on camera is the real
    picker, the colors are the real OSC packets it emits, and in -Mode Auto the
    arrow keys are real key events delivered through a real pty. What this
    script actually does is remove the variables that make one take differ from
    the next -- leftover style state, personal tuned styles in the list, a
    starting index that depends on whatever was applied yesterday.

    Three things run here:

      -Prep      Snapshot the current style state, park any personal styles,
                 and reset the terminal so every take starts from the same
                 clean window. Leaves `tstyles` loaded in your session.

      -Mode      Guided (default) hands the keyboard back to you with a cue
                 card; Auto drives the whole sequence through expect with
                 fixed timings so takes are frame-comparable.

      -Restore   Put everything back: personal styles returned, the style you
                 had before re-applied live (colors and prompt), snapshot
                 removed.

    Restore is also safe to run on its own after a crash or a Ctrl-C -- the
    snapshot is on disk, not in this process.

.PARAMETER Mode
    Guided: prep, show the cue card, then get out of the way so you type
    `tstyles` yourself. Human arrow rhythm reads better on camera than a
    metronome, and nothing can desync.

    Auto: prep, then drive an interactive pwsh through expect -- types the
    command, opens the picker, sweeps the list, confirms, runs a real command.
    Identical every take. Requires expect (preinstalled on macOS).

.PARAMETER Finale
    Style to land on and confirm. Default tombraider: pure black with hot pink
    (#ff3088), which holds up at small sizes and in a compressed social feed
    better than the low-luminance themes around it.

.PARAMETER FinalCommand
    Real command run after the style is confirmed, to show a working terminal
    rather than a still. Must be something harmless and colorful.

.PARAMETER HoldOn
    Style names the sweep pauses on. Defaults pick the three biggest jumps in
    the alphabetical run rather than the three prettiest themes -- contrast
    against the *previous* frame is what registers at speed.

.EXAMPLE
    ./scripts/demo.ps1
    Prep + cue card, then you drive.

.EXAMPLE
    ./scripts/demo.ps1 -Mode Auto
    Full automated take.

.EXAMPLE
    ./scripts/demo.ps1 -Restore
    Put my terminal back.
#>
[CmdletBinding()]
param(
    [ValidateSet('Guided', 'Auto')]
    [string]$Mode = 'Guided',

    [string]$Finale = 'tombraider',

    [string]$FinalCommand = 'git log --oneline -6',

    [string[]]$HoldOn = @('gitbash', 'lain', 'neon-rain'),

    # Milliseconds per arrow press during the sweep, and on a hold row.
    # 300/620 puts the full 16-style sweep at ~6.4s and the whole take at
    # ~14.4s. The sweep is the one section that wants to be as long as it can
    # be -- it is the actual product -- so these are tuned to spend everything
    # left over after the opening, the confirm, and the closing command.
    [int]$StepMs = 300,
    [int]$HoldMs = 620,

    # Keep personal (tuned) styles visible in the picker. Off by default: a
    # name like "felitest" in a launch video is a blemish, and the picker
    # opens on whatever style is current, which would move the start index.
    [switch]$KeepUserStyles,

    [switch]$Prep,
    [switch]$Restore,

    # Write the generated expect script and print its path instead of running
    # it. Use this to hand-tune a timing without editing this file.
    [switch]$DryRun,

    # Record the take to a .mov with macOS's own screencapture, cropped to the
    # terminal window, so a take needs no screen recorder and no trimming.
    # -Mode Auto only: it works by knowing exactly how long the take runs,
    # which is only true when the script is driving the keys.
    #
    # Needs Screen Recording permission for the app running this (System
    # Settings > Privacy & Security > Screen Recording). Without it
    # screencapture writes nothing and says so, which this reports rather than
    # leaving you with a 0-byte file.
    [switch]$Record,

    [string]$RecordPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent

# --- data root -------------------------------------------------------------
# Deliberately duplicated from the module's Get-TStylesDataRoot rather than
# called through it: that function is not exported, and a recording harness
# reaching into module internals is exactly the kind of coupling that breaks
# the day someone refactors. Five lines, one comment, no dependency.
function Get-DemoDataRoot {
    if ($IsWindows) {
        $base = $env:LOCALAPPDATA
        if (-not $base) { $base = Join-Path $HOME 'AppData\Local' }
        return Join-Path $base 'TerminalStyles'
    }
    if ($IsMacOS) { return Join-Path $HOME 'Library/Application Support/TerminalStyles' }
    $base = $env:XDG_DATA_HOME
    if (-not $base) { $base = Join-Path $HOME '.local/share' }
    return Join-Path $base 'TerminalStyles'
}

$DataRoot   = Get-DemoDataRoot
$BackupDir  = Join-Path $DataRoot '.demo-backup'
$UserStyles = Join-Path $DataRoot 'styles'
$ParkedDir  = Join-Path $DataRoot 'styles.demo-parked'

# The live-state files a confirm writes. Everything the demo can dirty is in
# this list; anything not here is either regenerated on demand or untouched.
$StateFiles = @(
    'current-style.json',
    'current-style.ps1',
    'current-style.osc',
    'current-prompt.sh'
)

function Write-Step   { param($m) Write-Host "  $m" -ForegroundColor DarkGray }
function Write-Good   { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  $m" -ForegroundColor Yellow }

function Import-TerminalStyles {
    # -Global so `tstyles` is still there after this script returns, which is
    # the whole point in Guided mode.
    Import-Module (Join-Path $RepoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking -Global
}

function Get-DemoStyleNames {
    # The picker's list, in the picker's order, via the module itself -- so a
    # style added or renamed upstream cannot silently desync the key plan.
    & (Get-Module TerminalStyles) { @(Get-AvailableStyles) } | ForEach-Object { $_.Name }
}

# --- snapshot / restore ----------------------------------------------------

function Save-DemoState {
    if (Test-Path -LiteralPath $BackupDir) {
        Write-Warn "A snapshot already exists -- keeping it (it is from before the first take)."
        return
    }
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

    # Record which files were absent, so Restore can delete rather than
    # resurrect them. Without this, a user who had no style applied ends up
    # with the demo's style stuck on after restore.
    $present = @()
    foreach ($f in $StateFiles) {
        $src = Join-Path $DataRoot $f
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $BackupDir $f) -Force
            $present += $f
        }
    }
    $present | Set-Content -LiteralPath (Join-Path $BackupDir 'present.txt') -Encoding utf8
    Write-Step "Snapshot saved ($($present.Count) state file(s))."
}

function Restore-DemoState {
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        Write-Warn "No snapshot found -- nothing to restore."
    } else {
        $presentPath = Join-Path $BackupDir 'present.txt'
        $present = if (Test-Path -LiteralPath $presentPath) {
            @(Get-Content -LiteralPath $presentPath | Where-Object { $_ })
        } else { @() }

        foreach ($f in $StateFiles) {
            $dst = Join-Path $DataRoot $f
            $bak = Join-Path $BackupDir $f
            if ($present -contains $f -and (Test-Path -LiteralPath $bak)) {
                Copy-Item -LiteralPath $bak -Destination $dst -Force
            } elseif (Test-Path -LiteralPath $dst) {
                Remove-Item -LiteralPath $dst -Force
            }
        }
        Remove-Item -LiteralPath $BackupDir -Recurse -Force
        Write-Good "Style state restored."
    }

    Restore-UserStyles

    # Repaint this window to match what was just restored, so the terminal you
    # are sitting in agrees with the state on disk without opening a new tab.
    $osc = Join-Path $DataRoot 'current-style.osc'
    if (Test-Path -LiteralPath $osc) {
        [Console]::Out.Write([System.IO.File]::ReadAllText($osc))
        Write-Step "Previous colors re-applied to this window."
    } else {
        Import-TerminalStyles
        tstyles reset | Out-Null
        Write-Step "No previous style -- terminal reset to its own defaults."
    }
    $prompt = Join-Path $DataRoot 'current-style.ps1'
    if (Test-Path -LiteralPath $prompt) { . $prompt }
}

function Hide-UserStyles {
    if ($KeepUserStyles) { return }
    if (-not (Test-Path -LiteralPath $UserStyles)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $UserStyles -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { return }
    if (Test-Path -LiteralPath $ParkedDir) {
        Write-Warn "Styles already parked from an earlier run -- leaving them."
        return
    }
    # A move inside the same parent: reversible, atomic, and it never touches
    # the style's contents.
    Move-Item -LiteralPath $UserStyles -Destination $ParkedDir -Force
    New-Item -ItemType Directory -Path $UserStyles -Force | Out-Null
    Write-Step "Parked $($dirs.Count) personal style(s): $($dirs.Name -join ', ')"
}

function Restore-UserStyles {
    if (-not (Test-Path -LiteralPath $ParkedDir)) { return }
    if (Test-Path -LiteralPath $UserStyles) {
        $left = @(Get-ChildItem -LiteralPath $UserStyles -Directory -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) {
            Remove-Item -LiteralPath $UserStyles -Recurse -Force
        } else {
            # Someone tuned a new style mid-session. Merge rather than clobber.
            foreach ($d in @(Get-ChildItem -LiteralPath $ParkedDir -Directory)) {
                $dst = Join-Path $UserStyles $d.Name
                if (-not (Test-Path -LiteralPath $dst)) { Move-Item -LiteralPath $d.FullName -Destination $dst }
            }
            Remove-Item -LiteralPath $ParkedDir -Recurse -Force
            Write-Good "Personal styles restored (merged)."
            return
        }
    }
    Move-Item -LiteralPath $ParkedDir -Destination $UserStyles -Force
    Write-Good "Personal styles restored."
}

# --- prep ------------------------------------------------------------------

function Invoke-Prep {
    Write-Host ""
    Write-Host "  TerminalStyles -- demo prep" -ForegroundColor Cyan
    Write-Host ""

    Import-TerminalStyles
    Save-DemoState
    Hide-UserStyles

    # Clearing the style record is what makes the picker open on the first
    # entry every time instead of on whatever was applied last -- and it is
    # also what gives the "plain terminal" opening frame.
    tstyles reset *> $null
    Write-Step "Terminal reset -- picker will open on the first style."

    $names = @(Get-DemoStyleNames)
    Write-Step "Picker will list $($names.Count) styles."

    # The picker draws 5 header lines, one row per style, and a trailing
    # blank, and repaints in place from a fixed home row. If the window is
    # shorter than that the frame scrolls mid-sweep and the take is unusable
    # -- worth catching before the recorder is rolling, not after.
    $needRows = $names.Count + 8
    try {
        $haveRows = [Console]::WindowHeight
        $haveCols = [Console]::WindowWidth
        if ($haveRows -lt $needRows) {
            Write-Warn "Window is $haveRows rows; the picker needs at least $needRows."
            Write-Step "Make the window taller or the font smaller, then re-run."
        }
        if ($haveCols -lt 80) {
            Write-Warn "Window is $haveCols columns; 90-110 keeps the swatches on one line."
        }
    } catch {
        # No console attached (piped, CI). Nothing to check.
    }

    if ($IsMacOS) {
        Write-Host ""
        Write-Warn "macOS: only colors change in the window you are recording."
        Write-Step "Background images need a new window and render as a still frame;"
        Write-Step "font/opacity/cursor-shape are profile-only. See docs/DEMO.md."
    }
    return $names
}

# --- the key plan ----------------------------------------------------------

function Get-KeyPlan {
    # Returns an ordered list of @{ Key; Ms; Label } describing the sweep.
    # Built from the live style list so it cannot drift from what is on screen.
    param([string[]]$Names)

    $finaleIdx = [Array]::IndexOf($Names, $Finale)
    if ($finaleIdx -lt 0) {
        throw "Finale style '$Finale' is not in the picker list: $($Names -join ', ')"
    }

    $plan = @()
    # Sweep to the bottom of the list, then settle back up onto the finale.
    # The overshoot-and-return reads as a deliberate choice on camera; walking
    # straight to the finale and stopping reads as the list simply ending.
    $last = $Names.Count - 1
    for ($i = 1; $i -le $last; $i++) {
        $ms = if ($HoldOn -contains $Names[$i]) { $HoldMs } else { $StepMs }
        $plan += @{ Key = 'Down'; Ms = $ms; Label = $Names[$i] }
    }
    for ($i = $last - 1; $i -ge $finaleIdx; $i--) {
        $plan += @{ Key = 'Up'; Ms = $StepMs; Label = $Names[$i] }
    }
    if ($plan.Count -gt 0) { $plan[-1].Ms = 900 }   # settle on the finale
    return $plan
}

function Show-Timeline {
    param($Plan)
    $total = ($Plan | Measure-Object -Property Ms -Sum).Sum
    Write-Host ""
    Write-Host "  Sweep: $($Plan.Count) keypresses, $([math]::Round($total/1000,1))s" -ForegroundColor Cyan
    $line = ($Plan | ForEach-Object {
        if ($_.Ms -ge $HoldMs) { "[$($_.Label)]" } else { $_.Label }
    }) -join ' > '
    Write-Host "  $line" -ForegroundColor DarkGray
    Write-Host "  ( [name] = deliberate hold )" -ForegroundColor DarkGray
}

# --- guided ----------------------------------------------------------------

function Invoke-Guided {
    param([string[]]$Names)
    $plan = Get-KeyPlan -Names $Names
    Show-Timeline -Plan $plan

    $downs = @($plan | Where-Object { $_.Key -eq 'Down' }).Count
    $ups   = @($plan | Where-Object { $_.Key -eq 'Up' }).Count

    Write-Host ""
    Write-Host "  Ready. Start your screen recorder, then:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1.  type   " -NoNewline -ForegroundColor DarkGray
    Write-Host "tstyles" -NoNewline -ForegroundColor White
    Write-Host "   and press Enter" -ForegroundColor DarkGray
    Write-Host "    2.  hold   " -NoNewline -ForegroundColor DarkGray
    Write-Host "Down x$downs" -NoNewline -ForegroundColor White
    Write-Host "   -- steady, ~3 per second, all the way to the bottom" -ForegroundColor DarkGray
    Write-Host "    3.  tap    " -NoNewline -ForegroundColor DarkGray
    Write-Host "Up x$ups" -NoNewline -ForegroundColor White
    Write-Host "     -- settles on " -NoNewline -ForegroundColor DarkGray
    Write-Host $Finale -ForegroundColor White
    Write-Host "    4.  press  " -NoNewline -ForegroundColor DarkGray
    Write-Host "Enter" -NoNewline -ForegroundColor White
    Write-Host "     -- banner and themed prompt paint" -ForegroundColor DarkGray
    Write-Host "    5.  run    " -NoNewline -ForegroundColor DarkGray
    Write-Host $FinalCommand -ForegroundColor White
    Write-Host "    6.  stop recording on the last frame" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Afterwards:  " -NoNewline -ForegroundColor DarkGray
    Write-Host "./scripts/demo.ps1 -Restore" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Press Enter to clear the screen and begin." -ForegroundColor DarkGray
    [void](Read-Host)
    Clear-Host
}

# --- auto ------------------------------------------------------------------

function Get-RecordRect {
    # "x,y,w,h" for the terminal window, in screen points, for screencapture
    # -R. Returns $null to mean "record the whole display" -- a full-screen
    # take is worth having; a failed one is not.
    #
    # Terminal.app is asked directly because it answers with window bounds and
    # cannot be confused about which window is which. Anything else goes
    # through System Events, which reports position and size for the frontmost
    # app's front window whatever that app is.
    if (-not $IsMacOS) { return $null }
    try {
        if ($env:TERM_PROGRAM -eq 'Apple_Terminal') {
            $raw = & osascript -e 'tell application "Terminal" to get bounds of front window' 2>$null
            if ($raw) {
                $n = @($raw -split ',' | ForEach-Object { [int]($_.Trim()) })
                # bounds are {left, top, right, bottom}; -R wants width/height.
                if ($n.Count -eq 4) { return '{0},{1},{2},{3}' -f $n[0], $n[1], ($n[2] - $n[0]), ($n[3] - $n[1]) }
            }
        }
        $raw = & osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get {position, size} of front window' 2>$null
        if ($raw) {
            $n = @($raw -split ',' | ForEach-Object { [int]($_.Trim()) })
            if ($n.Count -eq 4) { return '{0},{1},{2},{3}' -f $n[0], $n[1], $n[2], $n[3] }
        }
    } catch { }
    return $null
}

function Start-TakeRecording {
    # screencapture -V records for a fixed number of seconds and exits on its
    # own, which is what makes this unattended: there is no stop signal to get
    # wrong, and the file is finalised whether or not the take behaved.
    #
    # Deliberately no -C: that would burn the mouse pointer into the frame.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$Seconds, [string]$Rect)

    $args = @('-v', '-V', "$Seconds")
    if ($Rect) { $args += @('-R', $Rect) }
    $args += $Path

    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) "tstyles-rec-$PID.err"
    $proc = Start-Process -FilePath 'screencapture' -ArgumentList $args -PassThru -NoNewWindow `
                          -RedirectStandardError $errFile
    return [pscustomobject]@{ Process = $proc; ErrFile = $errFile }
}

function Stop-TakeRecording {
    param([Parameter(Mandatory)]$Rec, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$Seconds)

    # Give it the recording window plus a little, then stop waiting. A hung
    # screencapture should not hold the session open.
    if (-not $Rec.Process.WaitForExit(($Seconds + 15) * 1000)) {
        try { $Rec.Process.Kill() } catch { }
    }
    $err = ''
    if (Test-Path -LiteralPath $Rec.ErrFile) {
        $err = (Get-Content -LiteralPath $Rec.ErrFile -Raw -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $Rec.ErrFile -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($file -and $file.Length -gt 0) {
        Write-Good ("Recorded {0:N1} MB -> {1}" -f ($file.Length / 1MB), $Path)
        return
    }

    # No file, or an empty one. Overwhelmingly this is the permission, so say
    # that first instead of printing a bare failure.
    Write-Warn "No recording was produced."
    if ($err.Trim()) { Write-Step ($err.Trim() -split "`n")[0] }
    Write-Step "Most likely Screen Recording permission. Grant it to the app running"
    Write-Step "this (Terminal, iTerm2, ...) in System Settings > Privacy & Security >"
    Write-Step "Screen Recording, then restart that app and run the take again."
}

function ConvertTo-ExpectLiteral {
    # Escape a string for interpolation into an expect (Tcl) double-quoted
    # word. Tcl expands backslashes, [command substitution], and $variables
    # inside "" -- an unescaped repo path containing any of them would be
    # executed rather than sent. String.Replace, not -replace: the regex
    # replacement operator treats backslash and $ specially in the
    # REPLACEMENT too, which turns one backslash into four.
    param([string]$Text)
    $Text = $Text.Replace('\', '\\')
    $Text = $Text.Replace('"', '\"')
    $Text = $Text.Replace('[', '\[')
    $Text = $Text.Replace(']', '\]')
    $Text = $Text.Replace('$', '\$')
    return $Text
}

function Invoke-Auto {
    param([string[]]$Names)

    $expectBin = (Get-Command expect -ErrorAction SilentlyContinue)
    if (-not $expectBin) {
        Write-Warn "expect not found -- falling back to Guided."
        Invoke-Guided -Names $Names
        return
    }

    $plan = Get-KeyPlan -Names $Names
    Show-Timeline -Plan $plan

    # Drive a real interactive pwsh through a pty. Every keypress below is a
    # genuine key event arriving at [Console]::ReadKey -- the picker cannot
    # tell it apart from a finger, which is the point.
    $sb = [System.Text.StringBuilder]::new()

    $rows = [Console]::WindowHeight
    $cols = [Console]::WindowWidth
    $pwshExe = (Get-Process -Id $PID).Path
    if (-not $pwshExe) { $pwshExe = 'pwsh' }

    [void]$sb.AppendLine('set timeout 60')
    [void]$sb.AppendLine("set stty_init `"rows $rows cols $cols`"")
    # -NoProfile so the user's own prompt/aliases never appear on camera.
    $initCmd = "Import-Module '$RepoRoot/TerminalStyles.psd1' -Force -DisableNameChecking; Set-Location '$RepoRoot'; function global:prompt { `"PS `" + (Split-Path -Leaf `$PWD) + `"> `" }; Clear-Host"
    [void]$sb.AppendLine("spawn -noecho `"$pwshExe`" -NoProfile -NoLogo -NoExit -Command `"$(ConvertTo-ExpectLiteral $initCmd)`"")
    [void]$sb.AppendLine('expect { "> " {} timeout { exit 2 } }')
    [void]$sb.AppendLine('sleep 1.0')

    # Type the command a character at a time. A pasted line appearing all at
    # once looks scripted; ~55ms/char looks like a person.
    [void]$sb.AppendLine('foreach ch [split "tstyles" ""] { send -- $ch; sleep 0.055 }')
    [void]$sb.AppendLine('sleep 0.35')
    [void]$sb.AppendLine('send -- "\r"')
    [void]$sb.AppendLine('expect { "Up/Down to preview" {} timeout { exit 3 } }')
    # Let the picker land before moving -- the viewer needs one clean beat to
    # read what this thing is.
    [void]$sb.AppendLine('sleep 0.9')

    foreach ($step in $plan) {
        $seq = if ($step.Key -eq 'Down') { '\033\[B' } else { '\033\[A' }
        [void]$sb.AppendLine("send -- `"$seq`"")
        [void]$sb.AppendLine("sleep $([math]::Round($step.Ms / 1000.0, 3))")
    }

    [void]$sb.AppendLine('send -- "\r"')          # confirm
    [void]$sb.AppendLine('sleep 1.4')             # banner + prompt land
    [void]$sb.AppendLine("foreach ch [split `"$(ConvertTo-ExpectLiteral $FinalCommand)`" `"`"] { send -- `$ch; sleep 0.04 }")
    [void]$sb.AppendLine('sleep 0.3')
    [void]$sb.AppendLine('send -- "\r"')

    # How long the visible take runs, from the first keystroke to the end of
    # the closing hold. Every number here is a sleep emitted above, so the two
    # cannot drift: the typing rates, the picker beat, the sweep, and the pause
    # after the confirm.
    $takeSeconds = 1.0 + ('tstyles'.Length * 0.055) + 0.35 + 0.9 +
                   (($plan | Measure-Object -Property Ms -Sum).Sum / 1000.0) +
                   1.4 + ($FinalCommand.Length * 0.04) + 0.3

    if ($Record) {
        # Hold the last frame well past the point the recorder stops, so the
        # take never ends on the shell prompt reappearing. Nothing waits on
        # this -- screencapture -V decides when the file closes.
        [void]$sb.AppendLine('sleep 8')
        $takeSeconds += 2.6
    } else {
        [void]$sb.AppendLine('sleep 2.6')         # final frame holds for the end card
        $takeSeconds += 2.6
        # Hand the session back rather than killing it, so the last frame stays
        # up while you stop the recorder. Ctrl-D closes it.
        [void]$sb.AppendLine('interact')
    }

    $expectFile = Join-Path ([System.IO.Path]::GetTempPath()) "tstyles-demo-$PID.exp"
    [System.IO.File]::WriteAllText($expectFile, $sb.ToString())

    if ($DryRun) {
        Write-Host ""
        Write-Good "Expect script written (not run):"
        Write-Host "  $expectFile" -ForegroundColor Cyan
        Write-Host ("  Take runs {0:N1}s." -f $takeSeconds) -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    if (-not $Record) {
        Write-Host ""
        Write-Host ("  Start your recorder now. The take begins in 3 seconds and runs ~{0:N0}s." -f $takeSeconds) -ForegroundColor Cyan
        Write-Host "  Ctrl-D at the end to close the demo shell." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 3000
        Clear-Host

        try   { & $expectBin.Source -f $expectFile }
        finally { Remove-Item -LiteralPath $expectFile -Force -ErrorAction SilentlyContinue }
        return
    }

    # --- recorded take -----------------------------------------------------
    $rect = Get-RecordRect
    # Allowance for pwsh starting inside the pty before the first keystroke.
    # The screen is already cleared by then, so those frames open on an empty
    # terminal, which is the shot the take wants to start on anyway.
    $seconds = [int][math]::Ceiling($takeSeconds + 3)

    Write-Host ""
    Write-Host ("  Recording {0}s to:" -f $seconds) -ForegroundColor Cyan
    Write-Host "  $RecordPath" -ForegroundColor White
    if ($rect) {
        Write-Step "Cropped to this window ($rect)."
    } else {
        Write-Warn "Could not read the window bounds -- recording the whole display."
    }
    Write-Step "Starting in 3 seconds. Do not click away: the crop follows this window."
    Start-Sleep -Milliseconds 3000

    # Clear before the recorder starts so the opening frames are an empty
    # terminal rather than this message.
    Clear-Host
    $rec = Start-TakeRecording -Path $RecordPath -Seconds $seconds -Rect $rect

    try   { & $expectBin.Source -f $expectFile }
    finally {
        Remove-Item -LiteralPath $expectFile -Force -ErrorAction SilentlyContinue
        Stop-TakeRecording -Rec $rec -Path $RecordPath -Seconds $seconds
    }
}

# --- entry -----------------------------------------------------------------

if ($Restore) { Restore-DemoState; return }

if ($Record) {
    # Refused rather than half-honoured: the recorder is given a fixed
    # duration, and there is no way to know how long a take lasts when a
    # person is driving the keys.
    if ($Mode -ne 'Auto') {
        Write-Warn "-Record needs -Mode Auto (the recorder is given a fixed duration)."
        Write-Step "Use: -Mode Auto -Record, or record Guided takes yourself."
        return
    }
    if (-not $IsMacOS) {
        Write-Warn "-Record uses macOS screencapture and only runs there."
        return
    }
    if (-not $RecordPath) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $RecordPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "TerminalStyles-demo-$stamp.mov"
    }
    # screencapture refuses to overwrite, and fails late if the directory is
    # missing -- both are better caught before the terminal is cleared.
    $dir = Split-Path -Parent $RecordPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $RecordPath) {
        Write-Warn "$RecordPath already exists. Pass a different -RecordPath."
        return
    }
}

$names = Invoke-Prep
if ($Prep) {
    Write-Host ""
    Write-Good "Prepped. Run the picker yourself, or re-run with -Mode Auto."
    Write-Host ""
    return
}

if ($Mode -eq 'Auto') { Invoke-Auto -Names $names } else { Invoke-Guided -Names $names }
