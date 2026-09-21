@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.42'
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
            ReleaseNotes = 'v0.8.42: koholint, a sixteenth theme, built from the opening of Link''s Awakening -- Link face-down on driftwood off the island, four fifths water and sky. Its palette is sampled from the source frames rather than chosen: the sea is 39.9% of every pixel in the GIF and becomes the background, and the band on his hat is 0.3% of the picture and the only yellow in it, so it is the cursor and nothing else. Cloud white on sea blue measures 11.6 to 1. Adding it turned up a crop that had been there all along. uniformToFill scales to COVER, so a square source on an ordinary window is enlarged twice over and loses two thirds of its height -- koholint showed sea and the top of a hat, and eva was cut off at the chin and lost its EXT3 label. Both ask for native size now. Four other styles are flagged by the same arithmetic and deliberately left alone: they are landscape or abstract, a centre crop keeps the subject, and containing them would leave most of the window flat. The defect was never scaled up, it was the subject cropped out. Also: the docs site no longer carries an inline second copy of every scheme and description, its banner quotes no longer render with visible backslashes, and the README stops denying that WezTerm shows a background image while devoting a section to explaining how.'
        }
    }
}
