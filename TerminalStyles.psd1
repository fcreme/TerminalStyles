@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.14'
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
            ReleaseNotes = 'v0.8.14: bootstrap installer hardening. It did not raise the TLS floor to 1.2, so on stock Windows PowerShell 5.1 -- exactly who runs the "iwr | iex" one-liner -- the download could fail outright: on .NET Framework the default SecurityProtocol can omit TLS 1.2, GitHub refuses anything older, and the failure surfaces as "the underlying connection was closed", which reads like a network fault rather than a protocol one. The main download also had no timeout, while the far less important update-check call did, so a stalled connection sat on "Downloading" indefinitely. And because the one-liner runs the script body in your OWN session, the installer left $ErrorActionPreference set to Stop behind it -- turning every later non-terminating error in that shell into a terminating one. Preferences and the TLS floor are now restored on the way out, including on the failure paths. NOTE: these reach you by re-running the installer, and the version you run it FROM is the one being fixed.'
        }
    }
}
