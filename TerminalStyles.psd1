@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.18'
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
            ReleaseNotes = 'v0.8.18: The tuner. "tstyles tune ../styles/eva" DELETED styles/eva, printed "Reverted." and exited 0 -- the scratch directory it removes on every exit path was the style directory, and a tune.json base carrying the same traversal did it with nothing unusual typed. The "Font face" knob was dead on every platform and the first press on it killed the session, losing every adjustment. The tuner''s own menu could dye itself invisible, measured at exactly 1.000:1 on the bundled light theme, where the slider that caused it can no longer be read or reversed. "[1] Overwrite" said "(shadows the bundled style)" while destroying a style that had no bundled original; two tune sessions open at once destroyed each other''s work; a Save-As over an existing style was a merge, not the replace it promised; and re-tuning silently doubled the adjustments when the base had been re-baked since. Beyond the tuner: a scheme value could smuggle an arbitrary escape sequence into every new shell -- persisted to current-style.osc and replayed on every shell start, indefinitely. "tstyles uninstall" deleted a style you had tuned in place and "tstyles update" reverted it to stock while leaving its tune.json claiming otherwise. "tstyles current" reported no active style right after applying one on Windows Terminal. And the font knob offered a fraction of the monospace families it promised, including three the module''s own table already names.'
        }
    }
}
