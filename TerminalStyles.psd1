@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.17'
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
            ReleaseNotes = 'v0.8.17: "tstyles uninstall" deleted the styles you wrote. It printed "PRESERVE user state -- pass -DeleteData to wipe" and then removed the styles directory outright, and your own styles live there beside the bundled ones, because that is how the documented override works. Every style you had authored or tuned was gone, silently. The installer now records what it placed and uninstall removes exactly that, style folder by style folder; installs predating that manifest leave the styles directory alone entirely. The same list also left CHANGELOG.md, CONTRIBUTING.md, docs/ and tests/ behind in the data root. Also: the documented iwr|iex install opened with a red "chcp is not recognized" error on macOS and Linux and then told those users they were "Also wired up for Windows PowerShell 5.1"; "tstyles list" threw on a style whose scheme.json holds a colour that is not 6-digit hex (thanks @cnovakdev); and one of the three functions install.ps1 duplicates from the module had drifted from its copy, which matters because "tstyles update" runs the installer inside the module''s own scope, so those copies replace the module''s for the rest of the session.'
        }
    }
}
