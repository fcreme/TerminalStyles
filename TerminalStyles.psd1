@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.9.0'
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
            ReleaseNotes = 'v0.9.0: Styles stick in VS Code''s terminal -- and in Insiders, VSCodium, Cursor and Windsurf. Until now a style there was escape sequences only: the colors held for that tab, and the font and cursor never arrived. tstyles <name>, the picker, random, tune and delete now write the style into the editor''s own settings.json -- the terminal''s 20 colors, fontFamily, fontSize, fontWeight and cursorStyle -- after asking once per editor; tstyles vscode on|off changes the answer. Every apply keeps a record of what was there before, so tstyles reset, tstyles vscode off and tstyles uninstall put your own values back and leave alone a key you changed by hand since. The picker previews the font and cursor too, and Esc puts the file back exactly as it was. It refuses rather than guesses: an editor it cannot identify, a missing settings folder and a file that does not parse each stop the write and say why. Also fixed: a settings.json that will not parse is named, rather than always called Windows Terminal''s, and the picker prints its can''t-show notice once instead of twice.'
        }
    }
}
