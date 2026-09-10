# SNOWDAY profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet winter-sunset theme. No banner -- the background GIF carries
# the mood, same vein as forest / golden-forest. function global:prompt
# is required so the binding sticks when this script is dot-sourced
# from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'SNOWDAY'

function global:prompt {
    # ~-abbreviated to match the zsh/bash half, where {CWD} maps to %~ / \w.
    $cwd = $PWD.Path -replace ('^' + [regex]::Escape($HOME) + '(?=$|[\\/])'), '~'
    "PS $cwd> "
}

if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    # No edit mode is set here, on any platform. Supplying -EditMode at all
    # makes PSReadLine throw away its dispatch tables and rebuild them from
    # that mode's defaults, even when the mode does not change -- so every key
    # the user had bound in this session is deleted. On Windows, where Windows
    # mode is already the default, that erasure was the statement's only
    # effect. This file is dot-sourced from the END of $PROFILE, after the
    # user's own bindings, so they always lost. A style is a colour theme; the
    # line editor belongs to the user.
    Set-PSReadLineOption -Colors @{
        Command   = '#E8D4B8'
        Parameter = '#E09870'
        String    = '#D8B878'
        Number    = '#FFD8A0'
        Comment   = '#3A3028'
        Operator  = '#E8D4B8'
        Variable  = '#88A8B8'
        Type      = '#A08098'
        Keyword   = '#44739B'
        Member    = '#E8D4B8'
        Default   = '#E8D4B8'
        Error     = '#C46850'
        Selection = "$([char]27)[48;2;42;58;88m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#3A3028' } -ErrorAction Stop
    } catch { }
}
