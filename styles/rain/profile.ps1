# RAIN profile -- pwsh 7 and Windows PowerShell 5.1.
# Contemplative highland-storm aesthetic, pulled from the castle GIF.
# Dot-sourced by tstyles.ps1 at shell startup and live on style switch.
# `function global:prompt` so the binding sticks when reloaded from
# inside Invoke-TerminalStyle's function scope; inline colors so
# $script: resolution doesn't depend on the calling script.

$Host.UI.RawUI.WindowTitle = 'RAIN // HIGHLAND'

# Palette (24-bit ANSI), pulled from the castle stills.
$Esc   = [char]27
$Slate = "$Esc[38;2;156;160;204m"   # rain blue (borders, prompt scaffolding)
$Mist  = "$Esc[38;2;200;197;220m"   # pale lavender (default text)
$Moss  = "$Esc[38;2;200;184;80m"    # moss yellow (accent values)
$X     = "$Esc[0m"                  # reset

# Startup banner -- field journal, quiet
Write-Host ""
Write-Host "${Slate}+--------------------------------------------+${X}"
Write-Host "${Slate}|  ${Mist}FIELD JOURNAL // ${Moss}DAY 47${Mist}                   ${Slate}|${X}"
Write-Host "${Slate}|  ${Mist}WEATHER: ${Moss}STEADY RAIN${Mist}  ::  CEILING: ${Moss}40m${Mist}    ${Slate}|${X}"
Write-Host "${Slate}|  ${Mist}STILL NO SIGN OF THE OTHERS.              ${Slate}|${X}"
Write-Host "${Slate}+--------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc   = [char]27
    $Slate = "$Esc[38;2;156;160;204m"
    $Mist  = "$Esc[38;2;200;197;220m"
    $Moss  = "$Esc[38;2;200;184;80m"
    $X     = "$Esc[0m"
    $cwd = $PWD.Path
    "${Slate}[TRAVELER${Moss} // RAIN${Slate}]${X} ${Slate}[LOC: ${Mist}${cwd}${Slate}]${X}`n${Slate}>${X} "
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
        Command   = '#C8C5DC'
        Parameter = '#9CA0CC'
        String    = '#C8B850'
        Number    = '#7AA868'
        Comment   = '#3C4060'
        Operator  = '#A8C5D8'
        Variable  = '#A89AC8'
        Type      = '#8AA8C8'
        Keyword   = '#9CA0CC'
        Member    = '#C8C5DC'
        Default   = '#C8C5DC'
        Error     = '#A85850'
        Selection = "$Esc[48;2;60;64;96m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#3C4060' } -ErrorAction Stop
    } catch { }
}
