@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.43'
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
            ReleaseNotes = 'v0.8.43: koholint fills the window. A square picture cannot fill a wide terminal without being cropped, stretched, or ringed with margins -- those are the only three outcomes, and 0.8.42 picked the least bad one by asking for native size. So the picture is wider now instead of the fit being compromised: the sky, the cloud band, the horizon and the open water are mirrored outward two hundred pixels each side, where they continue seamlessly. Link and his raft are NOT mirrored; any pixel in the margin belonging to them is replaced with open water, because the first attempt grew a second Link at both edges -- his hat and hair on the left, his tunic and hand on the right, which is the duplication tombraider had to be fixed for. At 900 by 500 the background is close enough to a terminal''s shape to cover again: an ordinary window costs it a quarter more scale and an eighty-pixel crop, against twice the scale and six hundred pixels at the square source. Anyone already on 0.8.42 has been fetching the wide image from the gifs branch since it was pushed; this release is what tells their theme to cover with it.'
        }
    }
}
