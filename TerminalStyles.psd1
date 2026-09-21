@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.41'
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
            ReleaseNotes = 'v0.8.41: a cached background is revalidated instead of being pinned forever. Get-StyleBundledBackground returned the cached file unconditionally, so replacing an image on the gifs branch reached exactly the people who had never applied that style; anyone who had was stuck with whatever they downloaded the first time. The negative cache beside it already had two reasoned lifetimes and a comment saying why -- the gifs branch is updated independently of releases -- and every word of that applies to an asset that CHANGED. The positive cache now expires the same way: a fortnight after a successful check, an hour after a failed one, through a HEAD compared by etag or by length. Every failure path returns the image already on disk, and it never runs on the picker thread, where resolving a background happens on every arrow key. Also: the theme count was still wrong in four more places, including the published site, because the guard for it pinned one sentence by its exact wording and a count two hundred lines away was spelled out in words. It now checks every count on both pages, in digits or words. And the README puts the install commands directly after the demo rather than below the style grid, with the macOS PowerShell prerequisite named at the command that needs it rather than 537 lines further down.'
        }
    }
}
