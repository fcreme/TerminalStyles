# MARQUEE profile -- pwsh 7 and Windows PowerShell 5.1.
# EXT3-series LED marquee aesthetic, sister theme to tombraider.
# Hot magenta portrait, gold EXT3 label, blue cool accents, pure
# black canvas. Vintage CRT cursor for the dot-matrix feel.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'MARQUEE // EXT3'

# Palette (24-bit ANSI), pulled from the LED portrait.
$Esc = [char]27
$M   = "$Esc[38;2;255;64;144m"    # hot magenta-pink (primary)
$Y   = "$Esc[38;2;240;208;64m"    # arcade gold (EXT3 label)
$B   = "$Esc[38;2;64;144;240m"    # arcade blue (cool accents)
$W   = "$Esc[38;2;240;200;216m"   # pale pink-white (default text)
$D   = "$Esc[38;2;90;40;72m"      # dim dark magenta (border)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host "${D}|  ${M}>>> MARQUEE // EXT3 <<<${W}                     ${D}|${X}"
Write-Host "${D}|  ${Y}NIGHT GALLERY${W}  ::  ${B}SIGNAL: STRONG${W}           ${D}|${X}"
Write-Host "${D}|  ${M}`"Through the glass, after hours.`"${W}           ${D}|${X}"
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $M   = "$Esc[38;2;255;64;144m"
    $Y   = "$Esc[38;2;240;208;64m"
    $B   = "$Esc[38;2;64;144;240m"
    $W   = "$Esc[38;2;240;200;216m"
    $X   = "$Esc[0m"
    $cwd = $PWD.Path
    "${M}[MARQUEE${Y} // EXT3${M}]${X} ${M}[${B}${cwd}${M}]${X}`n${M}>${X} "
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
        Parameter = '#FF4090'
        String    = '#F0D040'
        Number    = '#FF80D8'
        Comment   = '#2A1820'
        Operator  = '#F0C8D8'
        Variable  = '#4090F0'
        Type      = '#40E0E0'
        Keyword   = '#FF6098'
        Member    = '#F0C8D8'
        Default   = '#F0C8D8'
        Error     = '#D83080'
        Selection = "$Esc[48;2;58;16;40m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A1820' } -ErrorAction Stop
    } catch { }
}
