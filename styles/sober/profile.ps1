# SOBER profile -- pwsh 7 and Windows PowerShell 5.1.
# Minimalist: title only, no banner, single-line prompt with the leaf
# folder name + a teal '$'. function global:prompt so the binding sticks
# when dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SOBER'

function global:prompt {
    $Esc  = [char]27
    $Teal = "$Esc[38;2;122;153;153m"
    $X    = "$Esc[0m"
    $leaf = if ($PWD.Path -eq $HOME) {
        Split-Path -Leaf $HOME
    } else {
        Split-Path -Leaf $PWD.Path
    }
    "$leaf $($Teal)`$$($X) "
}

# Minimal PSReadLine styling: grayscale + the same teal accent for keywords.
# Errors stay muted (no screaming red).
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -Colors @{
        Command   = '#D5D5D5'
        Parameter = '#7A9999'
        String    = '#A89878'
        Number    = '#D5D5D5'
        Comment   = '#6E6E6E'
        Operator  = '#D5D5D5'
        Variable  = '#D5D5D5'
        Type      = '#7A9999'
        Keyword   = '#7A9999'
        Member    = '#D5D5D5'
        Default   = '#D5D5D5'
        Error     = '#A85050'
        Selection = "$([char]27)[48;2;46;46;46m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#6E6E6E' } -ErrorAction Stop
    } catch { }
}
