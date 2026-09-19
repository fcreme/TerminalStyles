@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.34'
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
            ReleaseNotes = 'v0.8.34: URGENT for anyone on 0.8.32 or 0.8.33 from PSGallery. Those two packages shipped a shell runtime with Windows line endings, and a carriage return is not whitespace to zsh or bash -- it becomes part of the token, so `case $x in` read as `in^M` and the runtime died where every interactive shell sources it, taking the tstyles command with it: ''zsh: command not found: tstyles''. The repo was never wrong; the publish workflow runs on a Windows runner, where the checkout converts LF to CRLF on the way in, and nothing looked at the package afterwards. Three layers now stand between that and a release: .gitattributes pins eol=lf on every extension a shell reads, a test reads the BYTES of every tracked .sh and .js rather than its lines, and the publish script refuses to ship a staged tree carrying one. Also in this release: the installer and the first interactive tstyles now open with the tstyles wordmark, once, on a real console.'
        }
    }
}
