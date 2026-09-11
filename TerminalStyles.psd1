@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.25'
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
            ReleaseNotes = 'v0.8.25: five more defects from the same audit, three of which damaged a file you own. Opening the picker on a style that ships no theme.json stripped EVERY COMMENT out of your settings.json, wrote none of the style, and printed ''Style applied'' in green -- measured through the real picker, the file''s hash changed and its four comments became one. Applying a style to the `defaults` profile did the same thing through a different door: the resolver declared ''defaults'' always addressable, the merge then threw on a settings.json with no `profiles` key, and because a method call on null aborts only the statement the unmerged object was written out anyway -- with the backup already spent, and the second run copying the stripped file over the good one. On the legacy array form of `profiles` it never threw at all and grafted the whole theme onto the wrong object silently. `tstyles shell-init` could leave a zsh user''s zsh completely unstyled while printing two green ''added'' lines and inventing a ~/.bash_profile they never had, because which shell you log in to was decided inside a branch that almost never runs. The installer''s execution-policy fix verified the scope it had just written instead of the effective policy, so it reported success on exactly the machines where Group Policy had defeated it -- and the advice it printed on failure blamed a scope that cannot possibly have been the cause. Also: only `tstyles <style>` warned you that a profile name was duplicated, while the picker, reset, font, tune and apply.ps1 all resolved one silently. And CI now notices when a release is tagged but never published, which is how 0.8.22 and 0.8.23 reached nobody.'
        }
    }
}
