@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.36'
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
            ReleaseNotes = 'v0.8.36: the first run now offers, once, to install WezTerm. Every bundled style ships an animated background and off Windows exactly one terminal renders it as one -- Terminal.app shows a still first frame and the rest show no image at all -- so there is a real gap between what a style IS and what you can see of it. The offer defaults to no, names the exact command before running it, and is recorded whether you accept or refuse, because an offer that comes back every run is a nag rather than an offer. It never appears to someone already running WezTerm, or where it is already installed, or without Homebrew to install it with, or in a session whose output is redirected. The welcome''s keypress is now conditional on the same reasoning: two real questions follow it on a first run and each holds the screen, so the Press Enter in front of them was ceremony -- but for anyone already using this the font prompt has been answered in an earlier version and nothing follows, so the keypress stays exactly where it is still doing work.'
        }
    }
}
