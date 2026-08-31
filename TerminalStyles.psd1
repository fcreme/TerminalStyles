@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.20'
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
            ReleaseNotes = 'v0.8.20: `tstyles delete <name>` removes a style you made, and `tstyles list` marks which styles are yours. The tuner makes creating a style a two-keystroke affair and every result lands in your styles dir as a full style -- but until now the only way to remove one was `tstyles uninstall -DeleteData`, which destroys the whole data root. Delete MOVES the folder to .deleted/&lt;name&gt;-&lt;timestamp&gt; and keeps it for 7 days rather than erasing it, so a mistake is undone by moving it back. The confirmation itemises what will happen first: whether the NAME survives (deleting a style that shadows a bundled one reveals the original instead of removing the name), whether the terminal is re-applied or reset, and every style tuned from this one by name with the exact brightness and saturation it loses. Bundled styles are refused. Which styles are yours is answered from the install manifest rather than from the folder path -- on a bootstrap install the install directory IS the data directory, so a path test reports every bundled style as the user''s -- and where there is no evidence either way the answer is "unknown", which is refused rather than guessed. Also fixed: deleting a style silently wiped the adjustments of every style tuned from it, because "the base is gone" and "the base is this style" were folded into one test -- the deltas vanished with no notice and the next save severed the child''s inherited background permanently.'
        }
    }
}
