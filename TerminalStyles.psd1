@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.48'
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
            ReleaseNotes = 'v0.8.48: eva and skyline fill the window again. Both declared a native-size background, so Windows Terminal drew eva as a 480px square in the middle of the window and skyline as a 270px strip along the bottom with the top half flat indigo. eva now scales to the window''s height, whole -- covering would still cut her off at the chin and lose the EXT3 label, and the GIF''s near-black edges blend into the bars either side. skyline now covers, anchored bottom-right: its 1052x270 source is short, so a centred cover kept the mirrored city and lost the girl, and anchored right it keeps her, the pole and the moon. The screenshot renderer centre-cropped anything that covered its canvas and ignored left and right alignment, so it would have drawn skyline without her; it now follows the style''s alignment, and both screenshots are redrawn.'
        }
    }
}
