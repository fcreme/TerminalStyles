@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.40'
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
            ReleaseNotes = 'v0.8.40: the README opens with a banner instead of a plain heading. GitHub strips CSS from a README, so a title cannot be given a typeface -- an attractive one has to become an image. This one is the tstyles wordmark the tool itself prints on first run, set in JetBrains Mono, a font tstyles font installs, in the umbrella palette, over a strip of the real accent colour every bundled style paints. It is rendered by scripts/make-banner.py rather than screenshotted, so it is deterministic and does not depend on a terminal being visible on the right desktop; the first version was a capture and the capture caught a browser instead. The banner is also a claim: it states a theme count and paints one swatch per style, both read from the styles folder when it renders, and this project shipped sixteen themes against a folder of fifteen for several releases. A PNG cannot be inspected by a test, so the generator writes docs/banner.json with what it drew and a test compares that against the styles folder. Adding or removing a style without regenerating now fails the build.'
        }
    }
}
