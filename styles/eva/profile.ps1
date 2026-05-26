# EVA profile -- pwsh 7 and Windows PowerShell 5.1.
# Themed around Asuka Langley / Unit-02 (red CRT palette).
# Dot-sourced by tstyles.ps1 at shell startup and live on style switch.
# `function global:prompt` so the binding sticks when reloaded from
# inside Invoke-TerminalStyle's function scope; inline colors so
# $script: resolution doesn't depend on the calling script.

$Host.UI.RawUI.WindowTitle = 'EVA // NERV'

# Palette (24-bit ANSI), pulled from the body-scan stills.
$Esc = [char]27
$R   = "$Esc[38;2;255;61;90m"     # coral-red (primary)
$Y   = "$Esc[38;2;232;197;71m"    # mustard yellow (EXT-3 overlay)
$W   = "$Esc[38;2;255;232;232m"   # pale pink-white (default text)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${R}+----------------------------------------------+${X}"
Write-Host "${R}|  ${W}NERV // EVA-02 PILOT INTERFACE              ${R}|${X}"
Write-Host "${R}|  ${W}SOHRYU, ASUKA LANGLEY :: SYNC: ${Y}89%${W}          ${R}|${X}"
Write-Host "${R}|  ${Y}ANTA BAKA?${W}                                  ${R}|${X}"
Write-Host "${R}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $R   = "$Esc[38;2;255;61;90m"
    $Y   = "$Esc[38;2;232;197;71m"
    $W   = "$Esc[38;2;255;232;232m"
    $X   = "$Esc[0m"
    $cwd = $PWD.Path
    "${R}[PILOT${Y} // EVA-02${R}]${X} ${R}[LOC: ${W}${cwd}${R}]${X}`n${R}>${X} "
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
        Command   = '#FFE8E8'
        Parameter = '#FF3D5A'
        String    = '#E8C547'
        Number    = '#FF85B8'
        Comment   = '#4A1A20'
        Operator  = '#FFE8E8'
        Variable  = '#FF85B8'
        Type      = '#E8C547'
        Keyword   = '#FF3D5A'
        Member    = '#FFE8E8'
        Default   = '#FFE8E8'
        Error     = '#FF3D5A'
        Selection = "$Esc[48;2;74;10;20m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#4A1A20' } -ErrorAction Stop
    } catch { }
}
