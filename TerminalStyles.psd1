@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.16'
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
            ReleaseNotes = 'v0.8.16: On Terminal.app the interactive picker could never deliver a background image. "tstyles" + arrow + Enter applied colors and prompt, said "Style applied", and stopped -- no profile written, no mention that the style ships a background, no hint -- while "tstyles <name>" on the same terminal did all three. "tstyles -NewWindow" was accepted without error and did nothing at all. kitty''s selection highlight made selected text unreadable: selectionBackground was a byte-identical copy of cursorColor, a near-white pink, putting the foreground at 1.34:1 and brightRed at 1.00:1. "tstyles random -BackgroundImage <path>" silently dropped the flag while "tstyles <name> -BackgroundImage <path>" honoured it. "tstyles help LIST" failed under Turkish and Azerbaijani locales, printing "No help topic" above a topics line that contained it. Also: scripts/demo.ps1 -Restore could permanently delete a personal style on a name collision, and resolved its data root to a Linux path under Windows PowerShell 5.1. An audit of the test suite itself found seven assertions that could not fail, including both guards protecting the lib/ split; Get-PublishStagePlan now refuses an uncommitted file under a directory allowlist entry, which is what those guards always claimed it did.'
        }
    }
}
