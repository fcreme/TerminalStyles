@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.35'
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
            ReleaseNotes = 'v0.8.35: the hints, badges and descriptions this tool prints are now readable on every style, instead of on the dark ones it happened to be developed against. Ten places printed the same hardcoded grey -- the picker''s hints and style descriptions, tstyles list''s parentheticals and its ''yours'' badges, the tuner''s hints while it previews live, and the notes that stand in for an unreadable swatch -- and every one of them renders against whatever background the applied style painted. On gitbash, the one light theme, that grey sits at 2.61 against the 4.5 contrast threshold for body text, and the picker previews by repainting the terminal, so the text went faint the moment you arrowed onto it. The colour is now taken from the highlighted style''s own foreground and blended toward its background, so it still reads as secondary text; every bundled style lands between 4.60 and 5.99. Anything that cannot be read -- a scheme.json that will not parse, no active style at all -- keeps the old grey, which is what everything had before.'
        }
    }
}
