# FOREST profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet alpine theme. No banner -- the background GIF carries the mood.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'FOREST'

function global:prompt {
    # ~-abbreviated to match the zsh/bash half, where {CWD} maps to %~ / \w.
    $cwd = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    "PS $cwd> "
}

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
        Command   = '#D8E4EC'
        Parameter = '#D49680'
        String    = '#98B86A'
        Number    = '#E0A088'
        Comment   = '#2A3A30'
        Operator  = '#D8E4EC'
        Variable  = '#88C0E0'
        Type      = '#A8B0C8'
        Keyword   = '#3A8EE0'
        Member    = '#D8E4EC'
        Default   = '#D8E4EC'
        Error     = '#E0A088'
        Selection = "$([char]27)[48;2;26;53;72m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A3A30' } -ErrorAction Stop
    } catch { }
}
