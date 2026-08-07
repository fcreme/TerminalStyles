@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.7.1'
    GUID              = '50bee3d1-bbcc-479d-852a-df363b207ef5'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Theme Windows Terminal from PowerShell: 16 bundled color schemes with an arrow-key picker that previews each theme live in your current tab (Enter keeps, Esc reverts). Switch color scheme, cursor, font, opacity, and background image in one command, and install curated coding fonts (JetBrains Mono, Fira Code, Cascadia Code and more) straight from their official sources. Works on PowerShell 7 and Windows PowerShell 5.1.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Terminal', 'Theme', 'ColorScheme', 'Prompt', 'Cursor', 'Background', 'Font', 'Customization', 'Console', 'Dotfiles', 'pwsh', 'PSEdition_Core', 'PSEdition_Desktop', 'Windows')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'v0.7.1: fixes background carryover between styles. Switching to a style that ships no background image no longer leaves the previous style''s image showing behind it -- in the picker and on a direct apply alike. A background you set yourself (your own image, or Windows Terminal''s desktopWallpaper) is still left untouched. --- v0.7.0: adds the "tstyles font" command. Installs curated coding fonts (JetBrains Mono, Fira Code, Cascadia Code, Hack, Source Code Pro, IBM Plex Mono) from their official release URLs, verifies each download against a pinned SHA-256, installs per-user (no admin), and applies the font to the active Windows Terminal profile. Run bare to list what is installed vs installable. A one-time opt-in prompt offers the set on first run, and newly installed fonts show up automatically in "tstyles tune". Also fixes the published package accidentally bundling lazily-fetched background images (3.0 MB down to 252 KB).'
        }
    }
}
