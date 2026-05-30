@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.5.0'
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
            ReleaseNotes = 'v0.5.0: new `-KeepPrompt` flag (`tstyles <name> -KeepPrompt`, and `apply.ps1 -KeepPrompt`) applies a style''s colors, cursor, font, opacity, and background but leaves your prompt alone -- for Oh My Posh / Starship users. apply.ps1''s prior `-NoProfile` is kept as an alias. Purely additive.'
        }
    }
}
