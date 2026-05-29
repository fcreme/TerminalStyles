@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.3.0'
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
            ReleaseNotes = 'v0.3.0: new `tstyles tune [name]` subcommand -- live, arrow-key tuning of a style''s brightness, saturation, opacity, font face, and font size. Colors retint instantly; Enter saves the result to your user-styles dir (Overwrite or Save As) as a full style that inherits the base background and remembers its adjustments. Purely additive -- existing behavior unchanged.'
        }
    }
}
