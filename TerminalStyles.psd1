@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.15'
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
            ReleaseNotes = 'v0.8.15: "tstyles reset <profile>" reset the WRONG profile. The name lands in the second positional slot and the dispatcher read only -Target, so it was silently ignored and the auto-detected profile was reset instead, reported as a success. -Target still wins when both are given. Also: "tstyles ls" is an accepted alias for "list" and was missing from tab-completion, so you only found it if you already knew it existed; the coding-font download had no timeout, unlike every other fetch, so a stalled connection hung "tstyles font"; and a font published as a bare .ttf rather than a zip could never have installed, because the direct-file branch took its extension from the local download name. Documentation: the README claimed the picker writes no settings.json.bak (it does, so the README was talking you out of a recovery path that exists), pointed at the pre-0.2.0 location for cached background images, and described the bundled GIFs as committed binaries when they are deliberately not.'
        }
    }
}
