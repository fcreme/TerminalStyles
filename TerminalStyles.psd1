@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.6.0'
    GUID              = '50bee3d1-bbcc-479d-852a-df363b207ef5'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Windows Terminal themes for PowerShell -- 16 bundled styles with arrow-key live-preview picker.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Themes', 'Color', 'Prompt', 'pwsh')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'v0.6.0: new `tstyles reset [-Target <name>]` subcommand reverts a Windows Terminal profile to its unstyled default -- strips the colors, cursor, font, opacity, and background a style added, removes the orphan color scheme, and restores your own prompt. The inverse of applying a style; writes a settings.json.bak first. Purely additive.'
        }
    }
}
