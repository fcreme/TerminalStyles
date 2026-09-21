@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.44'
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
            ReleaseNotes = 'v0.8.44: skyline, a seventeenth theme -- a balcony over a lit city at night, with a crescent moon, a strip of green signage along the far bank, and towers with about a third of their windows still on. Its palette is sampled from the frames rather than chosen. The indigo the whole picture sits in is 26.9% of every pixel and becomes the background; the signage strip is 2% of the frame and the brightest thing in it, so it is the cursor; and the one warm colour anywhere in the picture is what errors are painted in. The foreground measures just under 16 to 1 on that background, and every colour slot clears the 3 to 1 accent floor. Nothing else in the set is indigo, and unlike koholint the source is already close to a terminal''s shape, so it covers without needing to be widened first. Also fixed: the script that renders a style preview hardcoded one style''s prompt while its own documentation claimed to read each style''s own, so skyline''s preview came out wearing koholint''s. It runs the style''s profile now and reads the prompt that function actually returns.'
        }
    }
}
