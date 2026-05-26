# UMBRELLA TERMINAL profile -- works in pwsh 7 and Windows PowerShell 5.1.
# Loaded by tstyles.ps1 both at shell startup ($PROFILE -> current-style.ps1)
# and live, right after the picker confirms a new style. For the live-reload
# case to work mid-session, prompt MUST be defined as `function global:prompt`
# and colors must live inside the function (no $script: references, since
# dot-sourcing from another script's function changes what $script: points at).

$Host.UI.RawUI.WindowTitle = 'UMBRELLA TERMINAL'

# Startup banner
$Esc = [char]27
$R = "$Esc[38;2;180;30;30m"    # muted blood red
$W = "$Esc[38;2;232;220;200m"  # bone white
$X = "$Esc[0m"                 # reset

Write-Host ""
Write-Host "${R}+------------------------------------------+${X}"
Write-Host "${R}|  ${W}UMBRELLA CORP. // OPERATOR TERMINAL     ${R}|${X}"
Write-Host "${R}|  ${W}CLEARANCE: PERSONAL  ::  STATUS: FINE   ${R}|${X}"
Write-Host "${R}+------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $R = "$Esc[38;2;180;30;30m"
    $W = "$Esc[38;2;232;220;200m"
    $X = "$Esc[0m"
    $op  = $env:USERNAME
    $cwd = $PWD.Path
    "${R}[UMBRELLA // OPERATOR: ${W}${op}${R}]${X}`n${R}[CWD: ${W}${cwd}${R}]${X}`n${R}>${X} "
}

# PSReadLine -- colors + history-based inline prediction
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -Colors @{
        Command          = '#E8DCC8'
        Parameter        = '#B41E1E'
        String           = '#C9A66B'
        Number           = '#E04848'
        Comment          = '#6E6862'
        Operator         = '#E8DCC8'
        Variable         = '#E8DCC8'
        Type             = '#C9A66B'
        Keyword          = '#B41E1E'
        Member           = '#E8DCC8'
        Default          = '#E8DCC8'
        Error            = '#FF4444'
        Selection        = "$Esc[48;2;90;15;15m"
        InlinePrediction = '#6E6862'
    }
}
