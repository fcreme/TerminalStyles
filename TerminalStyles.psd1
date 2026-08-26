@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.13'
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
            ReleaseNotes = 'v0.8.13: cancelling "tstyles tune" now puts your colours back. Esc emitted the OSC reset, which hands colour control to the TERMINAL''s own defaults -- correct on Windows Terminal, where settings.json has just been restored and WT repaints from it, and wrong everywhere else, where the style being tuned was itself only escape sequences. Cancelling dropped you to a stock palette instead of the style you opened the tuner on. All three exit paths -- Esc, an aborted save, and the safety net -- now restore it. This is the same bug the picker''s Esc had before 0.8.9, in the one place it had not been fixed. Internally, the library was split out of tstyles.ps1 into lib/, one file per subsystem; tstyles.ps1 went from 4,105 lines to 1,148. Everything is dot-sourced into the same scope it always shared, so there is no behaviour change -- but the module now ships a lib/ directory, which matters if you have scripted against the file layout rather than the commands.'
        }
    }
}
