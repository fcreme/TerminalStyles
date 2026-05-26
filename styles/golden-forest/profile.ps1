# GOLDEN FOREST profile -- pwsh 7 and Windows PowerShell 5.1.
# Minimal: sets the tab title and a clean default prompt so the previously
# active style's prompt doesn't bleed through after a live `tstyles` switch.
# function global:prompt is required so the binding sticks when this script
# is dot-sourced from inside tstyles.ps1's Invoke-TerminalStyle.

$Host.UI.RawUI.WindowTitle = 'GOLDEN FOREST'

function global:prompt { "PS $($PWD.Path)> " }
