@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.4.1'
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
            ReleaseNotes = 'v0.4.1: bugfix -- the interactive picker (bare `tstyles`) now lists your own styles too. It was enumerating only the bundled set, so styles saved via `tstyles tune` or added to the user-styles dir did not appear in the picker (they did show in list/current/random/tab-completion). The picker now uses the same union as every other command.'
        }
    }
}
