<#
.SYNOPSIS
Drive the real style picker through a scripted tour, for recording a demo.

.DESCRIPTION
The README shows fifteen animated GIFs of what the styles LOOK like. What it
has never shown is what the tool DOES: the terminal repainting live as you
arrow down the list. That is the one thing a screenshot cannot convey, and it
is the reason someone installs this.

Recording it by hand means typing at the right speed while a capture runs, and
getting a dozen takes with a hesitation in them. This drives the picker
instead, so the recording is a single clean take.

HOW IT DRIVES IT
    Through `wezterm cli send-text --no-paste`, which writes to the pane's
    input as though it were typed. Not AppleScript / System Events: that needs
    an Accessibility grant, and this needs no permission at all.

    It waits for the picker to actually be on screen -- polling
    `wezterm cli get-text` for the header -- rather than sleeping and hoping.
    A fixed sleep is how a demo ends up recording the shell prompt.

WHY WEZTERM
    It is the only terminal on macOS that animates a style's background. The
    same tour recorded in Terminal.app shows a still first frame and undersells
    the thing being demonstrated.

WHAT IT TOUCHES
    The picker previews by applying, so this changes the active style while it
    runs -- that IS the demo. The style that was active beforehand is restored
    at the end unless -NoRestore is given. It never writes a shell rc file, a
    profile, or a setting; it presses arrow keys in a window it spawned.

.EXAMPLE
    ./scripts/demo-picker.ps1 -DryRun
    Print the tour -- every key and every pause -- without opening anything.

.EXAMPLE
    ./scripts/demo-picker.ps1 -Tour eva,lain,umbrella -Countdown 5
    Start recording, run this, and it lands on umbrella.
#>
[CmdletBinding()]
param(
    # An explicit sequence to arrow through, last one being where Enter lands.
    # Left empty, the tour is a single downward sweep of the whole list, which
    # is what a demo wants: every style previewed once, no backtracking. A
    # named tour zig-zags, and on screen that reads as indecision -- it also
    # tripled the length of the recording in the first version of this.
    [string[]]$Tour,

    # Applied BEFORE the window opens, so the picker is already sitting at the
    # top of the list when the recording starts and the sweep is downward only.
    # Defaults to the first style the picker will show.
    [string]$StartAt,

    # How long to sit on each style. The preview repaints instantly; this is
    # how long a viewer gets to look at it. ~650ms across fifteen styles is a
    # ten second GIF, which is about as long as a README animation earns.
    [int]$DwellMs = 650,

    # A longer beat on the final style before Enter, so the last frame is not
    # a blur of the key press.
    [int]$SettleMs = 1600,

    # Seconds to wait before spawning, so you can start the capture and let go
    # of the keyboard.
    [int]$Countdown = 5,

    # End on Esc instead of Enter. Esc reverts, so nothing is applied at all --
    # useful for a rehearsal.
    [switch]$Cancel,

    # Leave the active style as whatever the tour landed on.
    [switch]$NoRestore,

    # Leave the spawned window open when the tour finishes.
    [switch]$KeepOpen,

    # Print the plan and exit. Opens nothing, presses nothing, changes nothing.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# The pure half, so the tour arithmetic can be tested without spawning a window.
. (Join-Path $PSScriptRoot 'demo-lib.ps1')

# --- keys -------------------------------------------------------------------
# What the picker's ReadKey sees. CSI A / CSI B are what a real arrow key
# sends, so nothing here is a special case in the code being demonstrated.
$KeyDown  = "$([char]27)[B"
$KeyUp    = "$([char]27)[A"
$KeyEnter = "`r"
$KeyEsc   = "$([char]27)"

function Test-WezTermMux {
    # `wezterm cli` talks to a running GUI. With none up, spawn fails with a
    # message about the mux that reads like a bug in this script.
    try {
        & wezterm cli list 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Wait-ForPicker {
    <#
    .SYNOPSIS
    Block until the picker is actually drawn in $PaneId, or give up.

    .DESCRIPTION
    Polls the pane's text for the picker's header. A fixed sleep is how a demo
    ends up recording a shell prompt, or sending its first arrow into a module
    that is still loading -- which the picker reads as a keystroke on the wrong
    screen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PaneId, [int]$TimeoutMs = 20000)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $text = ''
        try { $text = (& wezterm cli get-text --pane-id $PaneId 2>$null) -join "`n" } catch { }
        if ($text -match 'Choose a style for') { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Send-Key {
    param([Parameter(Mandatory)][string]$PaneId, [Parameter(Mandatory)][string]$Text)
    & wezterm cli send-text --no-paste --pane-id $PaneId $Text
}

# --- the styles the picker will show, from the picker's own reader ----------
$env:TSTYLES_NO_AUTOLOAD = '1'
$TStylesNoAutoLoad = $true
. (Join-Path $repoRoot 'tstyles.ps1')

# Through Get-PickerStyleSet, not Get-AvailableStyles: the picker drops any
# style whose scheme.json will not parse, so a list built the other way would
# be off by one for every arrow after the broken folder -- and the tour would
# land somewhere other than where it said it would.
$styles = @((Get-PickerStyleSet -Styles @(Get-AvailableStyles)).Styles | ForEach-Object { $_.Name })
if (-not $styles) { throw 'No styles the picker can show.' }
$startStyle = ''
try { $startStyle = "$(Get-CurrentStyleName)" } catch { }

if (-not $StartAt) { $StartAt = $styles[0] }
if ($styles -notcontains $StartAt) {
    throw "No style named '$StartAt'. Available: $($styles -join ', ')"
}
# No -Tour: sweep the whole list downward from where it opens. Every style is
# previewed exactly once and the highlight only ever moves one way.
$effectiveTour = if ($Tour) { $Tour } else { @($styles[-1]) }

$plan = Get-TourPlan -Styles $styles -StartStyle $StartAt -Tour $effectiveTour `
            -DwellMs $DwellMs -SettleMs $SettleMs
$endKeyName = if ($Cancel) { 'Esc (reverts)' } else { 'Enter (keeps)' }

Write-Host ""
Write-Host "  Picker demo" -ForegroundColor Cyan
Write-Host "  active   : $(if ($startStyle) { $startStyle } else { '(none)' })  (restored afterwards)"
Write-Host "  opens at : $StartAt"
Write-Host "  tour     : $(if ($Tour) { $Tour -join ' -> ' } else { "sweep all $($styles.Count) styles, downward" })"
Write-Host "  keys     : $($plan.Count) presses, then $endKeyName"
$total = ($plan | Measure-Object -Property PauseMs -Sum).Sum
Write-Host ("  runtime  : ~{0}s of tour, after a {1}s countdown" -f [int][Math]::Round($total / 1000), $Countdown)
Write-Host ""

if ($DryRun) {
    foreach ($s in $plan) {
        Write-Host ("    {0,-5} -> {1,-16} {2,5}ms" -f $s.Key, $s.Label, $s.PauseMs) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Dry run: nothing was opened, pressed or changed." -ForegroundColor DarkGray
    return
}

if (-not (Test-WezTermMux)) {
    Write-Host "  No running WezTerm to drive. Open WezTerm first -- it is the only" -ForegroundColor Yellow
    Write-Host "  terminal on macOS that animates a style's background, which is the" -ForegroundColor Yellow
    Write-Host "  half of this demo a still frame cannot show." -ForegroundColor Yellow
    return
}

if ($StartAt -ne $startStyle) {
    Write-Host "  Setting up: applying '$StartAt' so the sweep starts at the top." -ForegroundColor DarkGray
    Invoke-TerminalStyle $StartAt | Out-Null
}

for ($i = $Countdown; $i -gt 0; $i--) {
    Write-Host "`r  Recording window opens in $i... " -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host "`r  Opening.                        " -ForegroundColor Green

$paneId = (& wezterm cli spawn --new-window -- pwsh-preview -NoProfile -Command tstyles).Trim()
if (-not $paneId) { throw 'WezTerm did not report a pane id for the spawned window.' }

try {
    if (-not (Wait-ForPicker -PaneId $paneId)) {
        throw "The picker never drew in pane $paneId. Nothing was sent."
    }
    # A beat on the opening frame: the first thing the recording shows should be
    # the menu at rest, not a list already moving.
    Start-Sleep -Milliseconds 900

    foreach ($step in $plan) {
        Send-Key -PaneId $paneId -Text $(if ($step.Key -eq 'Down') { $KeyDown } else { $KeyUp })
        Start-Sleep -Milliseconds $step.PauseMs
    }
    Send-Key -PaneId $paneId -Text $(if ($Cancel) { $KeyEsc } else { $KeyEnter })
    Start-Sleep -Milliseconds 1800
}
finally {
    if (-not $KeepOpen) {
        & wezterm cli kill-pane --pane-id $paneId 2>$null | Out-Null
    }
    # Esc already reverted, so there is nothing to put back on that path.
    if (-not $Cancel -and -not $NoRestore -and $startStyle) {
        Write-Host "  Restoring '$startStyle'." -ForegroundColor DarkGray
        try { Invoke-TerminalStyle $startStyle | Out-Null } catch {
            Write-Host "  Could not restore it: $_" -ForegroundColor Yellow
        }
    }
}
