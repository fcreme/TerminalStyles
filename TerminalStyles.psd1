@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.38'
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
            ReleaseNotes = 'v0.8.38: tstyles font is a picker now. Arrow to a font instead of typing its name back exactly, in a tool that had already taught you to arrow through styles -- and the catalogue says what each font IS, which a name and a licence never did. Those descriptions are measured rather than recalled: ligatures from the GSUB calt feature, the shape of the zero from the third contour of its glyph, x-height from OS/2 sxHeight over unitsPerEm. All six bundled fonts mark their zero, which is exactly the differentiator a guess would have got wrong. There is deliberately no live preview: there is no escape sequence for a font face, so off Windows Terminal nothing can show you a font before it is installed, and rather than imply otherwise the footer says what Enter will actually do on YOUR terminal, which is one of three different things. The style picker gives a viewport row back in the same release. The tip pointing at tstyles help retires after the first few openings, because onboarding that never ends is a permanent tax on the menu -- one fewer style visible in every window, and on a 24-row terminal with 15 styles that is 14 now rather than 13.'
        }
    }
}
