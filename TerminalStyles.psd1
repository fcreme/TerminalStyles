@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.22'
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
            ReleaseNotes = 'v0.8.22: three fixes on the paths that touch files the user owns. tstyles reset deleted profile settings you had set by hand -- acrylic, opacity, padding, cursor shape, font, wallpaper, tab title -- on any profile TerminalStyles had never styled, then printed that it had reset the style; it also rolled your only settings.json.bak over and dropped every JSONC comment in the file while doing it. Reset now requires the profile to carry a colorScheme this tool knows, which an apply always writes, and leaves anything else completely alone. The loader block written into ~/.profile could never be removed, by anything: shell-remove and uninstall walked the registration list, which ~/.profile is deliberately not on, so both reported success while the block sat in the one file the login shell reads -- pointing at a data root uninstall had just deleted. Removal now walks a wider candidate set than registration writes to. And the shell runtime itself defined TS_LOADED and TS_SHELL as bare names in your shell, the one file outside the leak check that 0.8.21 added for the sixteen styles; they are now namespaced, and the check covers the runtime by sourcing it in a real zsh and diffing the variable table.'
        }
    }
}
