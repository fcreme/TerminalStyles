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
    # Windows-only variable, empty on macOS/Linux -- the segment rendered with
    # nothing in it. The zsh/bash half uses {USER} and was always correct.
    $op  = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
    # ~-abbreviated, as the zsh/bash half already is: ts_prompt_expand maps
    # {CWD} to %~ in zsh and \w in bash, both of which shorten $HOME. Left
    # absolute here, the two halves of one style printed different paths
    # everywhere under the home directory.
    $cwd = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    "${R}[UMBRELLA // OPERATOR: ${W}${op}${R}]${X}`n${R}[CWD: ${W}${cwd}${R}]${X}`n${R}>${X} "
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
        Command   = '#E8DCC8'
        Parameter = '#B41E1E'
        String    = '#C9A66B'
        Number    = '#E04848'
        Comment   = '#6E6862'
        Operator  = '#E8DCC8'
        Variable  = '#E8DCC8'
        Type      = '#C9A66B'
        Keyword   = '#B41E1E'
        Member    = '#E8DCC8'
        Default   = '#E8DCC8'
        Error     = '#FF4444'
        Selection = "$Esc[48;2;90;15;15m"
    }
    # InlinePrediction was added in PSReadLine 2.1; the version shipped
    # with stock Windows PowerShell 5.1 rejects it and -- crucially --
    # rejects the WHOLE -Colors call if it's included, dropping every
    # other color too. Set it separately so it can fail in isolation.
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#6E6862' } -ErrorAction Stop
    } catch { }
}
