@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.7'
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
            ReleaseNotes = 'v0.8.7: apply.ps1 deleted a background image you had set yourself. The scriptable entry point carried copy-pasted forks of five library functions, and its merge stripped the background fields whenever the style resolved no background of its own -- with no check of whose background was there. Applying any style to a profile carrying your own image, or Windows Terminal''s desktopWallpaper, silently removed it. All sixteen bundled styles trigger it. The module has always decided by ownership and left yours alone. apply.ps1 now dot-sources the library instead of duplicating it (446 lines down to 221), so there is one implementation and the module''s own tests cover it. Two further drifts went with it: it wrote its background cache into the STYLE directory in the pre-0.2.0 layout -- which on a PSGallery install belongs to the installed module -- using the old undated marker format that 0.8.6 reads as expired; and it wrote current-style.ps1 beside itself rather than into the data root, which coincide only for bootstrap installs. apply.ps1 now also sees tuned and user-authored styles, the same set `tstyles list` shows, rather than only those in its own folder.'
        }
    }
}
