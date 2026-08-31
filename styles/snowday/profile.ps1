# SNOWDAY profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet winter-sunset theme. No banner -- the background GIF carries
# the mood, same vein as forest / golden-forest. function global:prompt
# is required so the binding sticks when this script is dot-sourced
# from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SNOWDAY'

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
        Command   = '#E8D4B8'
        Parameter = '#E09870'
        String    = '#D8B878'
        Number    = '#FFD8A0'
        Comment   = '#3A3028'
        Operator  = '#E8D4B8'
        Variable  = '#88A8B8'
        Type      = '#A08098'
        Keyword   = '#44739B'
        Member    = '#E8D4B8'
        Default   = '#E8D4B8'
        Error     = '#C46850'
        Selection = "$([char]27)[48;2;42;58;88m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#3A3028' } -ErrorAction Stop
    } catch { }
}
