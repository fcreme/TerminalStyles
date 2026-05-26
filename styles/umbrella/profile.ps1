# UMBRELLA TERMINAL profile -- pwsh 7
# Applies only to PowerShell 7+ (Microsoft.PowerShell_profile.ps1 in the
# `PowerShell` folder, not the `WindowsPowerShell` folder).

$Host.UI.RawUI.WindowTitle = 'UMBRELLA TERMINAL'

# Palette (24-bit ANSI)
$script:UmbR = "`e[38;2;180;30;30m"    # muted blood red
$script:UmbW = "`e[38;2;232;220;200m"  # bone white
$script:UmbX = "`e[0m"                 # reset

# Startup banner
function Show-UmbrellaBanner {
    $r = $script:UmbR; $w = $script:UmbW; $x = $script:UmbX
    Write-Host ""
    Write-Host "${r}+------------------------------------------+${x}"
    Write-Host "${r}|  ${w}UMBRELLA CORP. // OPERATOR TERMINAL     ${r}|${x}"
    Write-Host "${r}|  ${w}CLEARANCE: PERSONAL  ::  STATUS: FINE   ${r}|${x}"
    Write-Host "${r}+------------------------------------------+${x}"
    Write-Host ""
}
Show-UmbrellaBanner

# Prompt
function prompt {
    $r = $script:UmbR; $w = $script:UmbW; $x = $script:UmbX
    $op  = $env:USERNAME
    $cwd = $PWD.Path
    "${r}[UMBRELLA // OPERATOR: ${w}${op}${r}]${x}`n${r}[CWD: ${w}${cwd}${r}]${x}`n${r}>${x} "
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
        Selection        = "`e[48;2;90;15;15m"
        InlinePrediction = '#6E6862'
    }
}
