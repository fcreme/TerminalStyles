@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.33'
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
            ReleaseNotes = 'v0.8.33: the picker now tells you what a style IS. It listed fifteen names and five colour blocks, while the thing that actually distinguishes them -- that eva is an Evangelion body-scan and sober is minimalist monochrome -- lived only in each style''s README and on the docs site, neither of which you are reading when you choose. Every style carries its own meta.json now, and the picker shows the description and quote for the highlighted row, plus a * marking the style that is actually applied so it stays visible once the cursor moves away. Two commands also stopped saying things that were not true. tstyles update printed ''Update complete'' whether it had updated anything or not -- Update-PSResource is a no-op when you are already current and reports nothing either way -- so it now names the version you came from and went to, shows what is new, or says plainly that nothing needed doing. And tstyles font told WezTerm users to choose a font in WezTerm''s own settings, where the next style apply overrides it; it now names the two routes that actually stick.'
        }
    }
}
