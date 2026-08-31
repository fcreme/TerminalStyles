# HALO profile -- pwsh 7 and Windows PowerShell 5.1.
# Third in the EXT3 LED-marquee series, sister theme to tombraider
# and marquee. Multi-color psychedelic portrait inside a circular
# halo / ring. Coral-orange primary, gold EXT3 label, vivid blue and
# lavender accents, vintage CRT cursor.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'HALO // EXT3'

# Palette (24-bit ANSI), pulled from the LED portrait.
$Esc = [char]27
$O   = "$Esc[38;2;255;104;80m"    # coral-orange (primary)
$Y   = "$Esc[38;2;240;208;64m"    # arcade gold (EXT3 label)
$B   = "$Esc[38;2;72;104;216m"    # vivid clothing blue
$L   = "$Esc[38;2;192;160;240m"   # lavender accent
$W   = "$Esc[38;2;240;216;192m"   # pale warm cream (default text)
$D   = "$Esc[38;2;90;48;72m"      # dim dark warm purple (border)
$X   = "$Esc[0m"                  # reset

# Startup banner
Write-Host ""
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host "${D}|  ${O}>>> HALO // EXT3 <<<${W}                        ${D}|${X}"
Write-Host "${D}|  ${Y}NIGHT CHAPEL${W}  ::  ${L}RADIANCE: HIGH${W}            ${D}|${X}"
Write-Host "${D}|  ${O}`"Look up. Look closer.`"${W}                     ${D}|${X}"
Write-Host "${D}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $O   = "$Esc[38;2;255;104;80m"
    $Y   = "$Esc[38;2;240;208;64m"
    $B   = "$Esc[38;2;72;104;216m"
    $W   = "$Esc[38;2;240;216;192m"
    $X   = "$Esc[0m"
    # ~-abbreviated, as the zsh/bash half already is: ts_prompt_expand maps
    # {CWD} to %~ in zsh and \w in bash, both of which shorten $HOME. Left
    # absolute here, the two halves of one style printed different paths
    # everywhere under the home directory.
    $cwd = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    "${O}[HALO${Y} // EXT3${O}]${X} ${O}[${B}${cwd}${O}]${X}`n${O}>${X} "
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
        Command   = '#F0D8C0'
        Parameter = '#FF6850'
        String    = '#F0D040'
        Number    = '#C0A0F0'
        Comment   = '#2A1820'
        Operator  = '#F0D8C0'
        Variable  = '#4868D8'
        Type      = '#50C8E0'
        Keyword   = '#FF8068'
        Member    = '#F0D8C0'
        Default   = '#F0D8C0'
        Error     = '#D8504A'
        Selection = "$Esc[48;2;42;26;48m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A1820' } -ErrorAction Stop
    } catch { }
}
