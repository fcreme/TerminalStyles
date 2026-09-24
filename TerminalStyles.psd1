@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.47'
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
            ReleaseNotes = 'v0.8.47: tstyles show <name> looks at a style without applying it. Until now the only ways to see one were to APPLY it, or to open the picker and arrow to it -- both change what is applied until you back out, and neither answers "what is lain like" from a prompt. show writes nothing: no settings file, no profile, no current-style record, no shell staging. A command whose whole promise is "look without committing" must not be the one that leaves something behind, so it repaints the palette, waits for a keypress, and restores in a finally -- a preview that fails halfway through still puts the terminal back, and with no style applied it hands colour control back to the terminal rather than re-emitting one you were never looking at. The cost of writing nothing is that a background, font and cursor shape are not part of what you see, and on Windows Terminal those are most of a style; the command says so on screen rather than letting you assume you have seen the whole thing. Two pictures were also corrected. eva''s screenshot was captured in May under uniformToFill -- a 480x480 source enlarged 2.08x, cut off at the chin with the EXT3 label gone -- which is the exact crop 0.8.44 removed, so the picture advertising the style was the last place still showing the defect. Redrawing it made it the fifth rendered screenshot while only two of the five said they were renders, and a reader cannot tell a render from a photograph of a real terminal by looking; eva, neon-rain and phosphor now carry that note, and a test decides which is which from the canvas size it reads out of the generator. The banner moved into the repo and the build now fails if the image and what it claims disagree.'
        }
    }
}
