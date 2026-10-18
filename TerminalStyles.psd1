@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.9.2'
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
            ReleaseNotes = 'v0.9.2: tstyles uninstall now tells you what it could not remove. It used to close on "TerminalStyles uninstalled." even with the module still installed or files left behind. That line now prints only when nothing is left; otherwise the end of the output names each module copy, install file, WezTerm style module or part of the data folder still in place, with what finishes the job. On Windows PowerShell 5.1 without PSResourceGet it now removes a Gallery copy, with Uninstall-Module -AllVersions; before, it called Uninstall-PSResource, which is not there, and left the module installed. On Windows it also looks in the other PowerShell engine''s per-user module folder, since PowerShell 7 and Windows PowerShell 5.1 keep separate ones, and names the command to run there. For a Gallery install, the confirmation screen names the command it will run.'
        }
    }
}
