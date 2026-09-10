# FOREST profile -- pwsh 7 and Windows PowerShell 5.1.
# Quiet alpine theme. No banner -- the background GIF carries the mood.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'FOREST'

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
        Command   = '#D8E4EC'
        Parameter = '#D49680'
        String    = '#98B86A'
        Number    = '#E0A088'
        Comment   = '#2A3A30'
        Operator  = '#D8E4EC'
        Variable  = '#88C0E0'
        Type      = '#A8B0C8'
        Keyword   = '#3A8EE0'
        Member    = '#D8E4EC'
        Default   = '#D8E4EC'
        Error     = '#E0A088'
        Selection = "$([char]27)[48;2;26;53;72m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#2A3A30' } -ErrorAction Stop
    } catch { }
}
