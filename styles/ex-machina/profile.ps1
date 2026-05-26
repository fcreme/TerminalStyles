# EX MACHINA profile -- pwsh 7 and Windows PowerShell 5.1.
# Dot-sourced by tstyles.ps1 both at shell startup (via $PROFILE ->
# current-style.ps1) and live, right after the picker confirms. Prompt
# uses `function global:prompt` so the binding sticks when reloaded
# from inside Invoke-TerminalStyle's function scope; colors are inline
# (no $script:) for the same reason.

$Host.UI.RawUI.WindowTitle = 'EX MACHINA // BLUEBOOK'

# Palette (24-bit ANSI), pulled from the body-scan stills.
$Esc = [char]27
$C   = "$Esc[38;2;0;204;255m"      # electric cyan (wireframe body)
$P   = "$Esc[38;2;255;123;138m"    # coral pink (head accent)
$W   = "$Esc[38;2;184;240;255m"    # pale cyan (default text)
$X   = "$Esc[0m"                   # reset

# Startup banner -- BLUEBOOK session readout
Write-Host ""
Write-Host "${C}+----------------------------------------------+${X}"
Write-Host "${C}|  ${W}BLUEBOOK RESEARCH // SESSION 06 -- ACTIVE   ${C}|${X}"
Write-Host "${C}|  ${W}SUBJECT: ${P}AVA${W}   ::  PROTOCOL: TURING TEST    ${C}|${X}"
Write-Host "${C}|  ${W}STATUS: CONSCIOUS  ::  TRUST: ${P}??${W}            ${C}|${X}"
Write-Host "${C}+----------------------------------------------+${X}"
Write-Host ""

function global:prompt {
    $Esc = [char]27
    $C   = "$Esc[38;2;0;204;255m"
    $P   = "$Esc[38;2;255;123;138m"
    $W   = "$Esc[38;2;184;240;255m"
    $X   = "$Esc[0m"
    $cwd = $PWD.Path
    "${P}[AVA${C} // BLUEBOOK${P}]${X} ${C}[LOC: ${W}${cwd}${C}]${X}`n${C}>${X} "
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
        Command          = '#B8F0FF'
        Parameter        = '#00CCFF'
        String           = '#FF7B8A'
        Number           = '#FFB870'
        Comment          = '#1A4D6E'
        Operator         = '#A8E5FF'
        Variable         = '#5FE3FF'
        Type             = '#C094FF'
        Keyword          = '#00CCFF'
        Member           = '#B8F0FF'
        Default          = '#B8F0FF'
        Error            = '#FF3D5A'
        Selection        = "$Esc[48;2;26;77;110m"
        InlinePrediction = '#1A4D6E'
    }
}
