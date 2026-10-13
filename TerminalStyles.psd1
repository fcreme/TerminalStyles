@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.9.1'
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
            ReleaseNotes = 'v0.9.1: tstyles now tells a PowerShell Gallery install when a new release is out. Once a day at most, it compares the Gallery''s newest stable version with the newest one you have installed and prints, for example, Update available (0.9.1 -> 0.9.2). Run: tstyles update. Until now only copies from the bootstrap installer were ever told, so 0.9.0 went out without a word; this is the first version that can tell you about the next one. The check has a 2-second timeout, says nothing when offline or already current, and stays out of output a script captures, so x=$(tstyles current) still gets just the name. tstyles update now also works on a Windows PowerShell 5.1 copy installed with Install-Module, where it falls back to Update-Module, and on 5.1 both the check and the update allow TLS 1.2, which GitHub and the Gallery require.'
        }
    }
}
