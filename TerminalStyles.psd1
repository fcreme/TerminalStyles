@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.12'
    GUID              = '50bee3d1-bbcc-479d-852a-df363b207ef5'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Theme your terminal from PowerShell: 16 bundled color schemes with an arrow-key picker that previews each theme live in your current tab (Enter keeps, Esc reverts). Switch color scheme, cursor, font, opacity, and background image in one command, and install curated coding fonts (JetBrains Mono, Fira Code, Cascadia Code and more) straight from their official sources. Works on Windows Terminal, macOS Terminal.app, iTerm2, and any terminal that supports OSC color sequences -- and can style zsh and bash as well as PowerShell. Runs on PowerShell 7 and Windows PowerShell 5.1, on Windows, macOS, and Linux.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Terminal', 'Theme', 'ColorScheme', 'Prompt', 'Cursor', 'Background', 'Font', 'Customization', 'Console', 'Dotfiles', 'pwsh', 'iTerm2', 'zsh', 'bash', 'ANSI', 'PSEdition_Core', 'PSEdition_Desktop', 'Windows', 'MacOS', 'Linux')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'v0.8.12: the picker garbled itself once the style list outgrew the terminal window. It redraws by parking the cursor at a fixed row and overwriting in place, which only works while the whole frame fits below that row -- draw more rows than the terminal has and it scrolls, the saved home row stops pointing at the top of the menu, and every later redraw lands in the wrong place. With 17 styles the frame is already 23 rows and a stock Terminal.app window is 24, so a couple of tuned styles was enough to break it. The list now scrolls within the window, keeping the selection visible and showing how many entries are hidden above and below. Also: the synchronous background fetch could strand a truncated image in the cache, the same way the picker''s prefetch could before 0.8.11 -- its error handling cleans up after a failed request, but a Ctrl+C or a killed process never reaches it, and a file sitting at the cache path is treated as a complete entry by every reader. Both paths now download to a temporary name and rename only once the transfer finished.'
        }
    }
}
