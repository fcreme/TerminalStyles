@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.9.3'
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
            ReleaseNotes = 'v0.9.3: Six fixes from a full audit. In a Windows Terminal Preview or Canary tab, a style now goes into that build''s settings.json, not Stable''s; $env:TSTYLES_WT_SETTINGS names a file yourself when the build cannot be told. A $PROFILE or shell rc file saved with a byte-order mark keeps its text through register, uninstall, shell-init and every update. tstyles <style> -NewWindow no longer takes over, or later deletes, a Terminal.app profile it did not import. pwsh inside WSL under Windows Terminal applies colors instead of failing, and a VS Code opened from another terminal is styled as VS Code. tstyles reset in WezTerm takes the style out of the generated module. The test suite no longer opens prompts or writes real settings when run from a terminal.'
        }
    }
}
