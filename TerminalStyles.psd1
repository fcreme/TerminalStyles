@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.24'
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
            ReleaseNotes = 'v0.8.24: the largest bug-fix release this project has had, from an audit that reproduced every finding against the real code before fixing it. THE ONES THAT COST YOU DATA: on a machine whose locale is not Gregorian (ar-SA, fa-IR) the trash stamp was written in that calendar and read back as Gregorian, so `tstyles delete` erased styles seconds after printing ''Kept for 7 days''. `tstyles shell-init` deleted your own lines out of ~/.zshrc when the file carried a stray BEGIN marker -- on the one path that never takes a backup -- and the same span was built in four places, all of them wrong. `tstyles uninstall` corrupted a $PROFILE containing any byte that is not valid UTF-8, silently and with no backup. One failed file copy during an install or update DELETED your install, leaving every new tab with no `tstyles` command, after printing a message that reads as ''nothing was changed''. And applying a style could delete a wallpaper you set yourself, decided by nothing more than the directory your shell was started in. THE ONES YOU WOULD HAVE NOTICED: every style deleted your own PSReadLine key bindings on Windows, on every new tab -- the comment saying that was free had been wrong since it was written. One style with a malformed scheme.json killed bare `tstyles` outright for every zsh and bash user, and in pwsh quietly showed the previous style''s colours under the broken style''s name. Under `set -u` the shell runtime printed eleven errors per tab and applied no style at all. `tstyles <style> -NewWindow` added a permanent duplicate Terminal.app profile every single time it ran; `tstyles profiles -Clean` removes the ones already there. An unusable tune.json dropped your recorded adjustments in silence and severed the style''s lineage on the next save. ALSO: the test suite was writing into your real TerminalStyles install, four times a run, and now fails the run if any test touches your own files; and a guard that was supposed to prove every theme''s swatch is distinct had been comparing zero pairs of themes for its whole life.'
        }
    }
}
