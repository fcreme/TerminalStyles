@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.31'
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
            ReleaseNotes = 'v0.8.31: a background image was tiled across a wide WezTerm window instead of being drawn once. WezTerm repeats a background layer by default, and the Contain size deliberately leaves room -- it fits the image inside the pane without cropping -- so a wide window had bare strips at the sides and WezTerm filled them with copies. Reported on tombraider, whose uniform stretch mode maps to Contain. Repeating is now off on both axes for every style, unconditionally: these styles are authored against Windows Terminal, and none of its four backgroundImageStretchMode values tile -- none draws one copy at natural size, fill stretches one, uniform and uniformToFill scale one -- so a style asking for any of them is asking for exactly one image. Verified against the real wezterm binary, with all sixteen bundled styles regenerated and loaded with config validation on.'
        }
    }
}
