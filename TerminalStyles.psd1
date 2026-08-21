@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.0'
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
            ReleaseNotes = 'v0.8.0: TerminalStyles now runs on macOS and Linux, not just Windows Terminal. Colors are applied as OSC escape sequences, which Terminal.app, iTerm2, Ghostty, WezTerm, kitty and Alacritty all understand, so a style applies to the window you are in and to every tab you open afterwards. Applying a style reports what the host terminal cannot show rather than dropping it silently. "tstyles shell-init" styles zsh and bash too -- palette, window title, banner and prompt -- and gives those shells a "tstyles" command of their own; each style ships a prompt.sh ported from its profile.ps1. Fixes: the module could not be imported at all off Windows (the data dir was built from $env:LOCALAPPDATA, which is null there); font detection reported every font as missing on macOS/Linux (System.Drawing is Windows-only from .NET 6 on); and importing the module wrote the style''s escape sequences and banner into REDIRECTED output, corrupting anything that captured it. Windows behaviour is unchanged.'
        }
    }
}
