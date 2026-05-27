# GARDEN RAIN profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet Ghibli-style garden-rainfall theme. No banner -- the GIF
# carries the mood, same vein as forest / golden-forest / snowday.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'GARDEN RAIN'

function global:prompt { "PS $($PWD.Path)> " }

if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -Colors @{
        Command   = '#C8D4DC'
        Parameter = '#5EC47A'
        String    = '#88C0D8'
        Number    = '#88C890'
        Comment   = '#38424A'
        Operator  = '#C8D4DC'
        Variable  = '#5A98D8'
        Type      = '#9088B8'
        Keyword   = '#3A78B8'
        Member    = '#C8D4DC'
        Default   = '#C8D4DC'
        Error     = '#C87080'
        Selection = "$([char]27)[48;2;26;48;64m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#38424A' } -ErrorAction Stop
    } catch { }
}
