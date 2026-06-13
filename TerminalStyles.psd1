@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.6.2'
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
            ReleaseNotes = 'v0.6.2: reliability release. settings.json writes are now atomic with a .bak rollback before live preview; fixes a Windows PowerShell 5.1 crash on settings with JSONC comments/trailing commas; fixes background images never appearing on PowerShell Gallery installs; and lifts six themes to a 3:1 contrast floor for legible syntax. No new commands.'
        }
    }
}
