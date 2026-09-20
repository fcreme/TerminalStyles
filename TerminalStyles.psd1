@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.39'
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
            ReleaseNotes = 'v0.8.39: the README now opens with the tool working rather than with its output. Fifteen styles previewing live as the picker arrows down the list -- neither the screenshots nor the per-style GIFs could show that, because every one of them shows what a style looks like and none of them shows the thing being used. It is recorded by scripts/demo-picker.ps1, a scripted tour that drives the real picker so a take is one clean sweep rather than someone typing at the right speed. The driver waits for the picker to be drawn rather than sleeping and hoping, and measures the window before spending ten seconds on it, because a new WezTerm window is 75x24 and at 24 rows a fifteen-style list scrolls. Two stale claims went with it. The opening paragraph said sixteen themes while the folder holds fifteen, true once and left behind when halo was removed; and it credited the font, opacity and animated background to Windows Terminal alone, which reads as not on your Mac to every macOS reader, when WezTerm has carried all three from the applied style since 0.8.29 and off Windows is the only terminal that animates one. Both are tested now. Also: the font list pads its licence column, so the descriptions line up instead of starting wherever the licence happened to end.'
        }
    }
}
