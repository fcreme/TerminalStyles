@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.21'
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
            ReleaseNotes = 'v0.8.21: almost entirely macOS and Linux, where these bugs were invisible on Windows. Nine styles overwrote your own shell variables on every new tab -- four releases after the changelog said they had stopped, because the lint guarding the rule only ever looked at the first column of each line. Applying any style silently disabled Ctrl+D, Ctrl+U, Ctrl+E and Ctrl+K: all sixteen profile.ps1 files set -EditMode Windows, which is already the default on Windows and unbinds those four keys outright on Unix. Fourteen styles printed an absolute path in PowerShell where their shell half printed a ~-abbreviated one, and gitbash rendered its MINGW64 line with a blank identity off Windows; all sixteen now render byte-identically in both halves, which every prompt.sh header has promised since 0.8.0. Every colour in a Terminal.app profile was archived in the wrong colour space, so -NewWindow drew a measurably different palette from the same style in the current window -- 19 of 20 colours off on eva, by up to 27/255 on a channel. tstyles register replaced a working bootstrap loader with a broken one and reported success, leaving every new tab without the tstyles command; and the zsh/bash shim pinned a PSGallery install to one version, so tstyles update printed Update complete and the next tstyles still ran the old code. Also: cancelling the picker or the tuner blanked the window title on Terminal.app and iTerm2 instead of restoring it, shell-init could leave its loader in a file login bash never reads, and there is now a project page at docs/index.html.'
        }
    }
}
