@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.2.0'
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
            ReleaseNotes = 'v0.2.0: state files relocated to %LOCALAPPDATA%\TerminalStyles\ (survives version upgrades). tstyles update / uninstall now delegate to Update-PSResource / Uninstall-PSResource for PSGallery-installed copies. README leads with Install-PSResource; iwr|iex bootstrap is now a documented fallback. Transparent migration of cached background images on first import.'
        }
    }
}
