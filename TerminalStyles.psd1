@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.46'
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
            ReleaseNotes = 'v0.8.46: a shell script is written with LF endings at the point it is staged into your data root, not only checked upstream of it. A carriage return is part of the token to zsh and bash, so one in a staged .sh is command not found, caret M, on every interactive shell -- which is what 0.8.32 and 0.8.33 shipped. Three guards were added after that release and every one of them sits upstream: git attributes stop a Windows checkout converting the file, a test pins the repo, and the publish script refuses a package carrying one. None of them protects a machine that already has a bad copy, and none runs at the moment the bytes land in somebody''s home directory. That gap mattered because the failure blocks its own cure: the tstyles shell function is defined by the file that is broken, so tstyles update from zsh cannot run at all, and recovering meant knowing to open pwsh and call the update function by hand. Anyone still on those releases now recovers by applying a style. The same rule covers each style''s prompt file, which is sourced by the same shells and breaks the same way.'
        }
    }
}
