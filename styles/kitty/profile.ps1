# KITTY profile -- pwsh 7 and Windows PowerShell 5.1.
# Sets tab title, a clean default prompt, and explicit PSReadLine colors
# matching the kitty scheme so syntax colors from the previously-active
# theme don't bleed through after a live `tstyles` switch.
# function global:prompt is required so the binding sticks when this
# script is dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'KITTY TERMINAL'

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
        Command   = '#F4E1E8'
        Parameter = '#FF8FA3'
        String    = '#FFD6A5'
        Number    = '#A5B4FC'
        Comment   = '#5A5468'
        Operator  = '#FCE4EC'
        Variable  = '#BAE6FD'
        Type      = '#C4B5FD'
        Keyword   = '#A8E6CF'
        Member    = '#F4E1E8'
        Default   = '#F4E1E8'
        Error     = '#FF8FA3'
        Selection = "$([char]27)[48;2;88;72;104m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#5A5468' } -ErrorAction Stop
    } catch { }
}
