# PHOSPHOR profile -- pwsh 7 and Windows PowerShell 5.1.
#
# Austere on purpose. A real phosphor terminal had no decoration: one hue, one
# line, a block cursor. The only colour that is not green is the amber chevron,
# and it is amber for the same reason the scheme's alarm slots are -- a
# monochrome tube could not paint a warning in red, so the machines that needed
# two states used two phosphors.
#
# function global:prompt so the binding sticks when dot-sourced from inside
# tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'PHOSPHOR'

function global:prompt {
    $Esc   = [char]27
    $Dim   = "$Esc[38;2;47;107;58m"
    $Glow  = "$Esc[38;2;51;255;94m"
    $Amber = "$Esc[38;2;255;176;0m"
    $X     = "$Esc[0m"

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

    "$($Dim)[$($X)$($Glow)$leaf$($X)$($Dim)]$($X)$($Amber)>$($X) "
}

# PSReadLine in one hue at several brightnesses, which is what a phosphor tube
# actually gave you: emphasis was intensity, not colour. Errors take the amber,
# the only other thing the tube could do.
if (Get-Module -ListAvailable PSReadLine) {
    try {
        Set-PSReadLineOption -Colors @{
            Command   = "#33ff5e"
            Parameter = "#8fdc9b"
            String    = "#4ce6a0"
            Operator  = "#2f6b3a"
            Variable  = "#72e0a2"
            Number    = "#5fd98f"
            Member    = "#1faa3f"
            Type      = "#24b06a"
            Comment   = "#2f6b3a"
            Error     = "#ffb000"
            # The SAME dark green the scheme paints, as a background escape:
            # PSReadLine highlights the input line and the terminal highlights
            # the scrollback, and two highlights that disagree fill one drag
            # with two colours. #14401f is rgb(20,64,31).
            Selection = "$([char]27)[48;2;20;64;31m"
        } -ErrorAction Stop
    } catch { }
}
