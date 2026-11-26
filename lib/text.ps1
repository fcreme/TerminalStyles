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

function ConvertTo-VisibleText {
    # Text somebody else wrote, safe to print: every control character but
    # newline and tab is shown as \xNN, so an escape sequence in it is read,
    # not obeyed by the terminal; and every invisible format character
    # (\p{Cf}: bidi overrides, zero-width characters) as \uNNNN, so text cannot
    # display as something other than what it is.
    #
    # The maintainer's review script had this for submitted files; the module
    # needed it for a style's description, quote and tab title (audit #89),
    # which reached the terminal as written whenever styles were listed or
    # browsed. One copy, here: scripts/review-submission.ps1 dot-sources this
    # file. -SingleLine first turns each run of CR, LF and tab into one space,
    # for fields that are one line by contract.
    param([AllowEmptyString()][string]$Text, [switch]$SingleLine)
    if ($SingleLine) { $Text = $Text -replace '[\r\n\t]+', ' ' }
    [regex]::Replace($Text, '[\x00-\x08\x0B-\x1F\x7F\u0080-\u009F]|\p{Cf}', {
        param($m)
        $c = [int][char]$m.Value
        if ($c -le 0xFF) { '\x{0:x2}' -f $c } else { '\u{0:x4}' -f $c }
    })
}
