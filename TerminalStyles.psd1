@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.29'
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
            ReleaseNotes = 'v0.8.29: WezTerm now receives eleven of the thirteen theme.json fields Windows Terminal honours, up from eight -- cursor shape, window opacity and acrylic blur, and the tab colour. Every option emitted is proved accepted by the real wezterm binary rather than taken from documentation, which is how the trap in the cursor mapping turned up: Windows Terminal''s cursorShape domain and WezTerm''s default_cursor_style have six values each and they are not the same six, and an invalid one does not degrade -- WezTerm falls back to its DEFAULT config, so the user loses their whole terminal appearance rather than one style. Unrecognised values now emit nothing at all. config.colors is merged field by field rather than assigned, because it is where a user keeps their own palette overrides. The picker also stopped garbling itself: its frame was budgeted at exactly the window height, so drawing it scrolled the buffer out from under the row it redraws from, and every later repaint landed one line off -- headers repeating down the screen and short rows wearing the tails of longer ones. It needs only a list long enough to fill the window, which sixteen bundled styles plus one of your own do in any window of 26 rows or fewer. The row budget is now a pure function that holds a row back and that a test can drive, every painted row erases to end of line so a resize cannot strand a longer line underneath, and a frame that cannot fit at all reclaims the screen instead of smearing. Three test files had also been writing to the operator''s own data root since May, one half-sandboxed each: the guard that watches for exactly that could not see it, because the bytes they wrote happened to match the bytes already there.'
        }
    }
}
