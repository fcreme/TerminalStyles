@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.9.4'
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
            ReleaseNotes = 'v0.9.4: Fixes from the second half of a full audit. Closing the tab while the picker or the tuner is open no longer costs you settings.json, and an edit made to it while they are open is kept. tstyles <style> -NewWindow no longer deletes the Terminal.app profile you made your default or startup profile, and tstyles profiles -Clean deletes only the copies it recorded making. In VS Code a style never goes inside one of your comments, reset keeps notes written in the colour block, and the picker no longer overwrites a setting you changed by hand. A tuner Save As fully replaces the style it names, and a save keeps profile.ps1 in its own encoding. apply.ps1 never writes $PROFILE. -Target defaults works on a settings.json whose defaults is null. shell-init respects ~/.bash_login and login shells that are not bash, and writes keep a file''s permissions. The documentation moved to the GitHub wiki.'
        }
    }
}
