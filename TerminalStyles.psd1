@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.32'
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
            ReleaseNotes = 'v0.8.32: two WezTerm compositions restored, and a steadier picker. A style''s background image was always CENTRED whatever the style asked for -- backgroundImageAlignment was read by nothing, so tombraider and marquee (right), golden-forest (topLeft) and kitty (bottomRight) all had their composition undone; tombraider''s own README describes the right-aligned image that puts text on the left half, and it was being drawn under the text instead. Windows Terminal carries both axes in one value and WezTerm takes two, so the map splits it, case-exactly, because a rejected enum does not misplace the image -- it replaces the user''s whole config with the default one. The picker also stopped reflowing the terminal while you arrow through the list: font size and padding are pinned for the whole preview session to whatever style is applied, and the chosen style''s own arrive on confirm. WezTerm relays out the terminal for either, so the three styles that differ (gitbash, rain, sober) made the list stutter on exactly those rows. And the halo style was removed at the author''s request, leaving fifteen bundled styles.'
        }
    }
}
