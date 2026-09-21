# SKYLINE profile -- pwsh 7 and Windows PowerShell 5.1.
#
# Two lines: the path in window-light blue with a lit-sign green marker, then a
# bar. function global:prompt so the binding sticks when dot-sourced from
# inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SKYLINE'

function global:prompt {
    $Esc  = [char]27
    $Lit  = "$Esc[38;2;0;149;255m"     # a window with the light on
    $Sign = "$Esc[38;2;66;255;142m"    # the green strip across the skyline
    $Dim  = "$Esc[38;2;95;107;176m"
    $X    = "$Esc[0m"

    # The zsh/bash half is {LEAF}; ts_prompt_expand maps it to zsh's %1~ and, in
    # bash, to ts_leaf. Matching %1~ takes two steps: abbreviate $HOME to ~
    # FIRST, then keep the last component -- except where that leaves only one,
    # which zsh prints whole ('~', '/tmp', '/').
    $abbr = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    $leaf = if ($abbr -eq '~' -or ($abbr -replace '^[\\/]', '') -notmatch '[\\/]') {
        $abbr
    } else {
        Split-Path -Leaf $abbr
    }

    "$($Dim)..$($X) $($Lit)$leaf$($X)`n$($Sign)|$($X) "
}

# PSReadLine in the city's own colours: the lit-window blue for commands, the
# sign green for variables, and the neon pink for errors -- the one warm colour
# anywhere in the frame.
if (Get-Module -ListAvailable PSReadLine) {
    try {
        Set-PSReadLineOption -Colors @{
            Command   = "#0095ff"
            Parameter = "#00bcff"
            String    = "#b8c8f8"
            Operator  = "#5f6bb0"
            Variable  = "#42ff8e"
            Number    = "#89dab5"
            Member    = "#bd57d7"
            Type      = "#0095c8"
            Comment   = "#5f6bb0"
            Error     = "#ff2e7a"
            # The SAME blue the scheme paints, as a background escape: PSReadLine
            # highlights the input line and the terminal highlights the
            # scrollback, and two highlights that disagree fill one drag with two
            # colours. #003ddf is rgb(0,61,223).
            Selection = "$([char]27)[48;2;0;61;223m"
        } -ErrorAction Stop
    } catch { }
}
