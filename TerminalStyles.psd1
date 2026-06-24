@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.6.3'
    GUID              = '50bee3d1-bbcc-479d-852a-df363b207ef5'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Theme Windows Terminal from PowerShell: 16 bundled color schemes with an arrow-key picker that previews each theme live in your current tab (Enter keeps, Esc reverts). Switch color scheme, cursor, font, opacity, and background image in one command. Works on PowerShell 7 and Windows PowerShell 5.1.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Terminal', 'Theme', 'ColorScheme', 'Prompt', 'Cursor', 'Background', 'Customization', 'Console', 'Dotfiles', 'pwsh', 'PSEdition_Core', 'PSEdition_Desktop', 'Windows')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'v0.6.3: discoverability + reliability. Refreshes the PowerShell Gallery listing (clearer description, expanded tags including the PSEdition/Windows platform tags so the package appears in Gallery search filters) and fixes a PowerShell 7 edge case where an interrupted settings.json write could silently degrade from an atomic replace to an in-place write. No new commands.'
        }
    }
}
