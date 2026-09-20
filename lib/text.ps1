# Text measuring and trimming, shared by more than one subsystem.
#
# Both functions here started life inside the one command that needed them --
# the sentence cutter in update.ps1, the width measurer in applystyle.ps1 --
# and a second caller is exactly the moment to move them. A copy in the second
# place is the failure this repo keeps paying for: two implementations of one
# rule drift, and the drift shows up as two different answers to the same
# question in two parts of the same output.

function Get-VisibleLength {
    # Printable width of a string that carries SGR escapes. The swatch and the
    # badges are mostly escape bytes, and measuring them with .Length overstates
    # their width by a factor of ten -- which would leave no room for anything
    # else and silently drop the description on every terminal.
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if (-not $Text) { return 0 }
    ($Text -replace "$([char]27)\[[0-9;]*[A-Za-z]", '').Length
}

function Get-SentenceSummary {
    <#
    .SYNOPSIS
    The opening of a piece of prose, cut short enough to fit somewhere.

    .DESCRIPTION
    Two callers, one rule. Release notes in this project run to a thousand
    characters -- they are the PSGallery listing, written to be read on a web
    page -- and printing the whole thing after an update buries the one line
    that matters (that it worked). A style's description is two short
    sentences, and `tstyles list` has only what is left of the row after the
    swatch and the badge.

    Cut at a SENTENCE boundary rather than mid-word, and only if there is more
    than one sentence to cut. A summary that ends mid-clause reads like the
    output was truncated by accident.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Notes, [int]$MaxLength = 220)

    $t = "$Notes".Trim() -replace '\s+', ' '
    if (-not $t) { return '' }
    if ($t.Length -le $MaxLength) { return $t }

    # Find where sentences END and slice there, rather than gluing matches back
    # together. Two traps, both hit on the way here:
    #
    #   * the terminator must be FOLLOWED by a space or end-of-string, or
    #     "v0.8.32" is three sentences and the summary opens "v0. 8. 32:";
    #   * matches are not contiguous from the start, so concatenating their
    #     values silently drops whatever the engine skipped -- that version
    #     prefix came out as "32: two WezTerm compositions restored".
    #
    # Slicing the ORIGINAL string at an index cannot do either.
    $end = 0
    foreach ($m in [regex]::Matches($t, '[.!?](?=\s|$)')) {
        $idx = $m.Index + 1
        if ($idx -gt $MaxLength) { break }
        $end = $idx
    }
    if ($end -gt 0) { return $t.Substring(0, $end).Trim() }
    # One very long opening sentence: fall back to a hard cut, marked as one.
    return $t.Substring(0, [Math]::Max(1, $MaxLength - 1)).TrimEnd() + [char]0x2026
}
