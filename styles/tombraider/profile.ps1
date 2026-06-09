# TOMB RAIDER profile -- pwsh 7 and Windows PowerShell 5.1.
# 90s arcade marquee aesthetic. Pure black background, hot neon
# magenta primary, gold EXT3 label, cyan/blue highlights, vintage
# CRT cursor. Dot-sourced by tstyles.ps1 at shell startup and live
# on style switch. function global:prompt is required so the binding
# sticks when this script is dot-sourced from inside Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'TOMB RAIDER // EXT3'

# Palette (24-bit ANSI), pulled from the LED marquee.
$Esc = [char]27
$M   = "$Esc[38;2;255;48;136m"    # hot neon magenta (TOMB RAIDER letters)
$Y   = "$Esc[38;2;240;208;64m"    # arcade gold (EXT3 label)
$C   = "$Esc[38;2;64;224;224m"    # arcade cyan (highlights)
$W   = "$Esc[38;2;240;200;216m"   # pale pink-white (default text)
$D   = "$Esc[38;2;90;40;72m"      # dim dark magenta (border)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host "${D}|  ${M}>>> TOMB RAIDER // EXT3 <<<${W}                 ${D}|${X}"
Write-Host "${D}|  ${Y}CROFT INDUSTRIES${W}  ::  ${C}POWER: ONLINE${W}            ${D}|${X}"
Write-Host "${D}|  ${M}`"Press start.`"${W}                              ${D}|${X}"
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $M   = "$Esc[38;2;255;48;136m"
    $Y   = "$Esc[38;2;240;208;64m"
    $C   = "$Esc[38;2;64;224;224m"
    $W   = "$Esc[38;2;240;200;216m"
    $X   = "$Esc[0m"
    $cwd = $PWD.Path
    "${M}[CROFT${Y} // EXT3${M}]${X} ${M}[${C}${cwd}${M}]${X}`n${M}>${X} "
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
        Command   = '#F0C8D8'
        Parameter = '#FF3088'
        String    = '#F0D040'
        Number    = '#FF60D0'
        Comment   = '#2A1820'
        Operator  = '#F0C8D8'
        Variable  = '#40E0E0'
        Type      = '#A040D0'
        Keyword   = '#FF5090'
        Member    = '#F0C8D8'
        Default   = '#F0C8D8'
        Error     = '#D83078'
        Selection = "$Esc[48;2;58;16;40m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A1820' } -ErrorAction Stop
    } catch { }
}
