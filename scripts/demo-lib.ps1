# demo-lib.ps1 -- the pure half of the picker demo driver.
#
# Defines functions and runs nothing, so a test can dot-source it without
# opening a window or pressing a key. demo-picker.ps1 is the other half: it
# spawns, waits and sends, none of which a test should do.
#
# Same split the module itself uses, and for the same reason -- the arithmetic
# that decides where the tour goes is worth pinning, and it cannot be pinned
# while reading it also starts a demo.

function Get-TourPlan {
    <#
    .SYNOPSIS
    The key sequence that walks from the active style through $Tour, pure.

    .DESCRIPTION
    Takes the picker's own style list rather than a list of its own, because
    two orderings of the same thing drift and the picker's is the one on
    screen. Returns a list of @{ Key; Label; PauseMs } so the whole tour can be
    read -- and tested -- without a terminal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Styles,
        # AllowEmptyString because the docstring below promises to handle an
        # unset start -- a machine with no active style -- and a Mandatory
        # [string] rejects '' before the function is ever entered. The comment
        # and the parameter disagreed, and the comment was the one worth keeping.
        [Parameter(Mandatory)][AllowEmptyString()][string]$StartStyle,
        [Parameter(Mandatory)][string[]]$Tour,
        [int]$DwellMs = 1100,
        [int]$SettleMs = 1600
    )

    $plan = [System.Collections.Generic.List[hashtable]]::new()
    $idx = [Array]::IndexOf($Styles, $StartStyle)
    # An unknown or unset start means the picker opens at 0 -- Get-PickerStyleSet
    # orders the list and the picker highlights the active style, or the first
    # when none is active.
    if ($idx -lt 0) { $idx = 0 }

    foreach ($want in $Tour) {
        $to = [Array]::IndexOf($Styles, $want)
        if ($to -lt 0) {
            throw "No style named '$want'. Available: $($Styles -join ', ')"
        }
        $step = if ($to -gt $idx) { 1 } else { -1 }
        while ($idx -ne $to) {
            $idx += $step
            # Every intermediate style is previewed too -- that is the point of
            # the demo -- so each press gets a beat rather than racing past.
            # Every style on the way gets the SAME beat. Racing past the
            # intermediate ones to reach a named destination is what makes a
            # tour look hurried, and those styles are previewing too -- that is
            # the whole thing being demonstrated.
            $plan.Add(@{
                Key     = if ($step -gt 0) { 'Down' } else { 'Up' }
                Label   = $Styles[$idx]
                PauseMs = $DwellMs
            })
        }
    }
    if ($plan.Count -gt 0) { $plan[$plan.Count - 1].PauseMs = $SettleMs }
    return $plan
}
