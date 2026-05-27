@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.2.1'
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
            ReleaseNotes = 'v0.2.1: user-added themes at %LOCALAPPDATA%\TerminalStyles\styles\<name>\ are now picked up alongside bundled themes AND survive any update path (bootstrap re-install, Update-PSResource). User-wins on name collision lets you locally override a bundled theme without forking. Purely additive -- zero behavior change if you don''t use the new user-styles dir.'
        }
    }
}
