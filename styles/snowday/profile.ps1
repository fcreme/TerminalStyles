# SNOWDAY profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet winter-sunset theme. No banner -- the background GIF carries
# the mood, same vein as forest / golden-forest. function global:prompt
# is required so the binding sticks when this script is dot-sourced
# from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SNOWDAY'

function global:prompt { "PS $($PWD.Path)> " }

if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -Colors @{
        Command   = '#E8D4B8'
        Parameter = '#E09870'
        String    = '#D8B878'
        Number    = '#FFD8A0'
        Comment   = '#3A3028'
        Operator  = '#E8D4B8'
        Variable  = '#88A8B8'
        Type      = '#A08098'
        Keyword   = '#3A6890'
        Member    = '#E8D4B8'
        Default   = '#E8D4B8'
        Error     = '#C46850'
        Selection = "$([char]27)[48;2;42;58;88m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#3A3028' } -ErrorAction Stop
    } catch { }
}
