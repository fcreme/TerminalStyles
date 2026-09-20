@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.37'
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
            ReleaseNotes = 'v0.8.37: tstyles list now says what each style is. The listing printed a name, a colour swatch and whether the style was yours -- everything except the one thing a reader scanning it is choosing between. The descriptions already lived in each style''s own meta.json and the picker had been reading them for some time; the listing simply never asked. Each row now carries one, trimmed to what is left of the line and cut at a sentence boundary rather than mid-word, so a narrow window reads "Warm sepia autumn." instead of a fragment, and a row with no room for a whole clause prints nothing rather than four cut-off words. The swatch is measured in columns rather than bytes: five colour cells are about 130 characters of escape sequence and 25 columns wide, and the difference between those two numbers is every description silently disappearing. The sentence cutter is the one already used for release notes, moved rather than copied, because two implementations of one rule drift. Also: a comment in the WezTerm writer credited the wiring line to a wezterm-init subcommand that has never existed in any version. A comment is a claim like any other line of output, and the reader it misleads is the next person who goes looking for that command.'
        }
    }
}
