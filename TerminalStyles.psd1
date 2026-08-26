@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.10'
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
            ReleaseNotes = 'v0.8.10: "tstyles tune" could destroy a style you had already saved. Choosing "Save as a new name" and typing the name of an existing user style replaced it with no warning, while the harmless collision -- a name matching a BUNDLED style, which is only shadowed and comes back when the shadow is deleted -- did warn. Both are checked now and the destructive one says so. The tuner''s font-face knob also cycled through the LETTERS of a font name on a machine with exactly one monospace font installed, and saved a one-character font face: PowerShell unrolls an array on the way to the output stream, so a single-element list reached the caller as a string and was indexed per character. Also: "tstyles random" accepted -Target, -KeepPrompt and -NewWindow and forwarded none of them, so "tstyles random -KeepPrompt" replaced the prompt it had just promised to keep; one malformed style stopped "tstyles list" dead, hiding every style after it, and now costs only its own row; and a current-style.ps1 that will not parse printed a full ParserError into every new shell tab instead of one warning naming "tstyles reset". Documentation: the README''s style-folder listing now mentions prompt.sh, without which a zsh or bash tab gets the colors and none of the prompt or banner.'
        }
    }
}
