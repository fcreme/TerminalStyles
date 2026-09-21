# KOHOLINT profile -- pwsh 7 and Windows PowerShell 5.1.
#
# Two-line prompt: a horizon rule in the sky blue, then the path and a
# hat-yellow marker. function global:prompt so the binding sticks when
# dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'KOHOLINT'

function global:prompt {
    $Esc    = [char]27
    $Sky    = "$Esc[38;2;136;152;248m"   # cloud edge -- 4.65 on the sea blue
    $Sea    = "$Esc[38;2;120;208;240m"   # the shallow water
    $Hat    = "$Esc[38;2;240;248;72m"    # the one yellow in the whole frame
    $Dim    = "$Esc[38;2;168;168;208m"
    $X      = "$Esc[0m"

    # The zsh/bash half is {LEAF}; ts_prompt_expand maps it to zsh's %1~ and,
    # in bash, to ts_leaf. Matching %1~ takes two steps: abbreviate $HOME to ~
    # FIRST, then keep the last component -- except where that leaves only one,
    # which zsh prints whole ('~', '/tmp', '/').
    $abbr = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    $leaf = if ($abbr -eq '~' -or ($abbr -replace '^[\\/]', '') -notmatch '[\\/]') {
        $abbr
    } else {
        Split-Path -Leaf $abbr
    }

    # A waterline, not a box: the source image is all horizon.
    "$($Dim)~~~~$($X) $($Sea)$leaf$($X)`n$($Sky)>$($X)$($Hat)>$($X) "
}

# PSReadLine in the island palette. Strings take the cloud white, because
# they are the thing most often read back; errors take the log red rather
# than a pure red, which would be the only colour in the scheme that is not
# in the picture.
if (Get-Module -ListAvailable PSReadLine) {
    try {
        Set-PSReadLineOption -Colors @{
            Command   = "#8898f8"
            Parameter = "#78d0f0"
            String    = "#f8f8f8"
            Operator  = "#a8a8d0"
            Variable  = "#f0f848"
            Number    = "#58b878"
            Member    = "#b894f8"
            Type      = "#58b0d8"
            Comment   = "#a8a8d0"
            Error     = "#f87858"
            # The SAME blue the scheme paints, as a background escape rather
            # than a hex colour -- PSReadLine highlights the input line and the
            # terminal highlights the scrollback, and two highlights that
            # disagree fill one drag with two colours. #4058f8 is rgb(64,88,248).
            Selection = "$([char]27)[48;2;64;88;248m"
        } -ErrorAction Stop
    } catch { }
}
