@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.6'
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
            ReleaseNotes = 'v0.8.6: data safety. The bootstrap installer removed its install directory on every update -- and that directory IS the module''s data root, so each `tstyles update` destroyed the cached background images, every style saved by `tstyles tune`, the active-style record, the staged zsh/bash runtime, the font cache and the generated Terminal.app profiles. The one thing it tried to preserve it looked for at the pre-0.2.0 location, so since 0.2.0 it preserved nothing. The installer now removes only what the release actually ships. NOTE: bootstrap users receive this fix by re-running the installer, and the version they run it FROM still wipes the data root one last time on the way in -- a fix can only protect the update after the one that delivers it. PSGallery installs were never affected. Also: `tstyles uninstall -DeleteData` could not be invoked at all, though it was documented in three places; a mistyped `-Target` reported "Style applied" in green while silently deleting every comment in your settings.json; one apply made while offline could cost a style its background permanently, because a 404 and an unreachable network wrote the same undated marker; a style shipping no theme.json left an unreferenced color scheme behind on every apply; and switching to a style whose theme.json omits background fields left the previous style''s image showing through the new palette.'
        }
    }
}
