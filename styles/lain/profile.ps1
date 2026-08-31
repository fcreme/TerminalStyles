# LAIN profile -- pwsh 7 and Windows PowerShell 5.1.
# Serial Experiments Lain. Deep black room, lavender monitor glow,
# faint red status indicators, ghost-pale foreground. Vintage cursor
# for the late-90s CRT aesthetic. Dot-sourced by tstyles.ps1 at shell
# startup and live on style switch. function global:prompt is required
# so the binding sticks when this script is dot-sourced from inside
# Invoke-TerminalStyle's function scope; inline colors so $script:
# resolution doesn't depend on the calling script.

$Host.UI.RawUI.WindowTitle = 'NAVI // PROTOCOL 7'

# Palette (24-bit ANSI), pulled from the room.
$Esc = [char]27
$P   = "$Esc[38;2;224;144;184m"   # lavender-pink (monitor glow, primary)
$M   = "$Esc[38;2;208;168;216m"   # bright lavender (accent)
$W   = "$Esc[38;2;216;212;224m"   # ghost-pale (default text)
$R   = "$Esc[38;2;176;64;80m"     # dim status red
$D   = "$Esc[38;2;90;88;112m"     # muted slate (border / dim)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host "${D}|  ${P}NAVI // PROTOCOL 7${W}                          ${D}|${X}"
Write-Host "${D}|  ${W}COPLAND OS  ::  WIRED CONNECTION ${R}ONLINE${W}     ${D}|${X}"
Write-Host "${D}|  ${M}`"Present day, present time. Hahaha.`"${W}        ${D}|${X}"
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $P   = "$Esc[38;2;224;144;184m"
    $M   = "$Esc[38;2;208;168;216m"
    $W   = "$Esc[38;2;216;212;224m"
    $X   = "$Esc[0m"
    # ~-abbreviated, as the zsh/bash half already is: ts_prompt_expand maps
    # {CWD} to %~ in zsh and \w in bash, both of which shorten $HOME. Left
    # absolute here, the two halves of one style printed different paths
    # everywhere under the home directory.
    $cwd = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    "${P}[LAIN${M} // WIRED${P}]${X} ${P}[${W}${cwd}${P}]${X}`n${P}>${X} "
}

# PSReadLine -- colors + history-based inline prediction
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
        Command   = '#D8D4E0'
        Parameter = '#E090B8'
        String    = '#88A8C0'
        Number    = '#D0A8D8'
        Comment   = '#2A2530'
        Operator  = '#D8D4E0'
        Variable  = '#A890C8'
        Type      = '#88C0A8'
        Keyword   = '#6AA090'
        Member    = '#D8D4E0'
        Default   = '#D8D4E0'
        Error     = '#D06070'
        Selection = "$Esc[48;2;42;31;48m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A2530' } -ErrorAction Stop
    } catch { }
}
