@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.26'
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
            ReleaseNotes = 'v0.8.26: eight more defects from the same audit, and the pattern in most of them is a claim the code then did not honour. `tstyles delete` itemised a reset of the active profile and then refused to perform it, telling you the style you had just deleted was ''not a style this tool wrote'' while leaving the profile styled; its confirmation also described the exact opposite of what happens to a tuned child, and a delete that FAILED still erased the expired trash while reporting only that the style could not be deleted. Five places on the shell and loader paths reported success for something that had not happened -- `Register-ShellLoader` said ''updated'' about a file it wrote back byte-for-byte, `uninstall` could leave an rc file carrying the block it had promised to strip, `register` left the second $PROFILE unwritten under a promise that every new tab would auto-load, and the whole zsh/bash half of an apply was swallowed by one empty catch. Every write to settings.json dropped a byte-order mark your file already had, on a path the picker documents as byte-exact. A background written to profiles.defaults was never cleared, so the previous style''s image bled through the next one. Styles whose names begin with a dot -- which the tuner itself creates -- were invisible to every listing, including the one the delete prompt prints before erasing them. And the shell-variable leak check whitelisted the very prefix 0.8.22 declared a leak, so one style went on overwriting names in your shell for four releases while the guard reported green.'
        }
    }
}
