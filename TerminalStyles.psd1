@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.5'
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
            ReleaseNotes = 'v0.8.5: the four things that were wrong outside Windows Terminal. Choosing a style in the picker left every new zsh/bash tab on the PREVIOUS style''s palette and banner -- it recorded the name and retinted the current window, but never staged the shell runtime, so nothing errored and the next tab was simply wrong. The picker also ignored -KeepPrompt and installed the style''s prompt anyway. "tstyles font <name>" installed the font and then reported failure, hunting for a settings.json that cannot exist off Windows Terminal. An apply resolved the style''s background image twice on the hot path, which for an uncached style meant up to 80 seconds of HTTP for a result that was thrown away. And re-tuning a style saved with Overwrite copied files onto themselves, while the tuner promised opacity and font would show in a new window that cannot show either. Also in this release: the capability table now claims only what a writer actually delivers, so iTerm2, Ghostty, WezTerm, kitty and Alacritty report "can''t show: background image" instead of reporting success and painting nothing -- and stop prefetching megabytes of GIFs they could never draw. The live OSC retint is unchanged everywhere.'
        }
    }
}
