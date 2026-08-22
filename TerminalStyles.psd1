@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.4'
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
            ReleaseNotes = 'v0.8.4: background images now actually appear on macOS Terminal.app. 0.8.2 generated correct profiles that pointed at the bundled animated GIFs -- and Terminal.app renders a still image but not an animated one, so the background came up blank with no error anywhere. The first frame is now extracted to a PNG and cached, so Windows Terminal animates and Terminal.app shows a still. "tstyles tune" also runs outside Windows Terminal now: brightness and saturation preview live over OSC, while opacity and font are saved with the style and take effect in a new window. Fixes a tuned style being saved without its zsh/bash prompt, which left shell users with the colors and none of the prompt or banner. --- v0.8.3: corrects the macOS install command to "brew install powershell". --- v0.8.2: background images on Terminal.app via "tstyles <name> -NewWindow". --- v0.8.0: TerminalStyles runs on macOS and Linux, and styles zsh and bash as well as PowerShell.'
        }
    }
}
