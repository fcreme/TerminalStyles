# SOBER profile -- pwsh 7 and Windows PowerShell 5.1.
# Minimalist: title only, no banner, single-line prompt with the leaf
# folder name + a teal '$'. function global:prompt so the binding sticks
# when dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SOBER'

function global:prompt {
    $Esc  = [char]27
    $Teal = "$Esc[38;2;122;153;153m"
    $X    = "$Esc[0m"
    # The zsh/bash half is {LEAF}, which ts_prompt_expand maps to %1~ / \W.
    # Matching %1~ takes two steps, and this had neither: abbreviate $HOME to
    # ~ FIRST, then keep the last component -- except where that leaves only
    # one, which zsh prints whole ('~', '/tmp', '/'). Before: sitting in $HOME
    # printed the home folder's name where zsh printed '~', and /tmp printed
    # 'tmp' where zsh printed '/tmp'.
    $abbr = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    $leaf = if ($abbr -eq '~' -or ($abbr -replace '^[\\/]', '') -notmatch '[\\/]') {
        $abbr
    } else {
        Split-Path -Leaf $abbr
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
    # Windows only. It is already the default there, and on macOS/Linux --
    # where PSReadLine defaults to Emacs -- EditMode Windows UNBINDS Ctrl+E,
    # Ctrl+K, Ctrl+U and Ctrl+D, and turns Ctrl+A into SelectAll. Applying a
    # colour theme silently took away Ctrl+D (end session) and Ctrl+U (clear
    # line); no style README mentions edit mode and nothing on screen explains
    # it. 5.1 predates $IsWindows and is Windows by definition, hence the
    # version test first -- the same order as Get-TStylesPlatform.
    if (($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows) {
        Set-PSReadLineOption -EditMode Windows
    }
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
