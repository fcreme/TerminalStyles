# NEON RAIN profile -- pwsh 7 and Windows PowerShell 5.1.
# Cyberpunk rainy-night theme. Neon yellow accents, matrix-green status,
# muted dystopia blue base. Dot-sourced by tstyles.ps1 at shell startup
# and live on style switch. function global:prompt is required so the
# binding sticks when this script is dot-sourced from inside
# Invoke-TerminalStyle's function scope; inline colors so $script:
# resolution doesn't depend on the calling script.

$Host.UI.RawUI.WindowTitle = 'NEON RAIN // DISTRICT-05'

# Palette (24-bit ANSI), pulled from the wallpaper.
$Esc = [char]27
$Y   = "$Esc[38;2;240;200;80m"    # neon yellow (sign / primary)
$G   = "$Esc[38;2;94;224;144m"    # matrix green (status)
$W   = "$Esc[38;2;216;228;240m"   # pale blue-cream (default text)
$D   = "$Esc[38;2;90;104;120m"    # dim slate (border / muted)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host "${D}|  ${Y}DISTRICT-05 // NIGHT SECTOR${W}                 ${D}|${X}"
Write-Host "${D}|  ${W}RAIN PROTOCOL ACTIVE  ::  STATUS: ${G}ONLINE${W}      ${D}|${X}"
Write-Host "${D}|  ${Y}\"The neon never sleeps.\"${W}                    ${D}|${X}"
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $Y   = "$Esc[38;2;240;200;80m"
    $G   = "$Esc[38;2;94;224;144m"
    $W   = "$Esc[38;2;216;228;240m"
    $X   = "$Esc[0m"
    $op  = $env:USERNAME
    $cwd = $PWD.Path
    "${Y}[NEON-RAIN${W} // ${G}${op}${Y}]${X} ${Y}[CWD: ${W}${cwd}${Y}]${X}`n${Y}>${X} "
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
        Command   = '#D8E4F0'
        Parameter = '#F0C850'
        String    = '#5EE090'
        Number    = '#FFD848'
        Comment   = '#2A3548'
        Operator  = '#D8E4F0'
        Variable  = '#88C0E0'
        Type      = '#A890C0'
        Keyword   = '#5A90D0'
        Member    = '#D8E4F0'
        Default   = '#D8E4F0'
        Error     = '#D86850'
        Selection = "$Esc[48;2;26;40;64m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A3548' } -ErrorAction Stop
    } catch { }
}
