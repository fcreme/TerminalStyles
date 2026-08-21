@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.2'
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
            ReleaseNotes = 'v0.8.2: background images now work on macOS Terminal.app. "tstyles <name> -NewWindow" opens a window carrying the style''s background image along with its palette and prompt. 0.8.0 and 0.8.1 claimed Terminal.app had no background-image support at all, which was wrong -- it does, through a .terminal profile, though only a new window can pick one up (no escape sequence carries an image). Also fixes "tstyles <name>" reporting "Style applied" when it had painted nothing, which happened whenever stdout was redirected. --- v0.8.1: fixes the interactive picker crashing on open outside Windows Terminal. --- v0.8.0: TerminalStyles runs on macOS and Linux; colors apply as OSC escape sequences, and "tstyles shell-init" styles zsh and bash as well as PowerShell.'
        }
    }
}
