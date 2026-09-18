@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.30'
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
            ReleaseNotes = 'v0.8.30: the picker previews the WHOLE style on WezTerm, not just its palette. WezTerm adds the files it requires to its config reload watch list, so rewriting the generated module restyles a running window -- which makes it the one terminal off Windows where arrowing through the list shows the background, font, padding, cursor shape and opacity as you move, instead of only the colours the escape-sequence retint carries. Two things hold that up. The preview runs on the thread reading your keystrokes, so it resolves backgrounds through a new -NoFetch switch that stops at the cache rather than making four serial ten-second attempts at the network mid-arrow; it is a switch rather than a gate on an existing predicate because a gate holds only while two implementations agree about an expired marker, and that rule has drifted once already. And Esc restores the module byte-exactly, including restoring it to ABSENT -- a first-ever picker run on a machine that had no module must not leave one behind. Measured at 3.1 ms per preview with zero network calls.'
        }
    }
}
