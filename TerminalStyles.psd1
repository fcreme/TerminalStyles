@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.19'
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
            ReleaseNotes = 'v0.8.19: A sweep of the tuner, which 0.8.18 had rewritten, found that three of its fixes were incomplete. The tuner''s menu still went invisible: the chrome picked between two FIXED palettes on a single lightness test, so it tracked the background only at the extremes -- gitbash at brightness -55 gave 1.35:1 on the row being dragged, and forest, rain and snowday all reached exactly 1.00:1. Every bundled style had a brightness where the menu vanished. Each colour is now fitted to the actual background, worst case 4.50:1 across all 16 styles and the full range. The Save / Save-As prompt was still painted in the palette slots the tuner had just retinted -- "Cancelled." rendered at exactly 1.000:1 on the one screen where a destructive prompt has to be read. And a drifted base permanently severed a tuned style''s background: dropping the now-meaningless deltas also dropped the ancestry, so the style became its own base and lost the cached image for good, with the next apply stripping every background field off the profile. Also fixed: with two Windows Terminal profiles sharing a name the style landed on the wrong one, and reset stripped the wrong one; a lost download race made a style report no background; the tuner''s font face and size were dropped when a base theme.json had a non-object font key; scripts/publish.ps1 would have shipped a package that cannot work, because its only gate never executed the module; and running the test suite wrote into the developer''s own data root.'
        }
    }
}
