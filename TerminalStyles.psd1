@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.23'
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
            ReleaseNotes = 'v0.8.23: two consent prompts that asked about a smaller command than the one that ran. `tstyles delete` itemises what it is about to do and closed on "Nothing is erased: move the folder back to undo" -- and pressing y ran the trash sweep, a recursive delete over every trashed style past the seven-day window. Measured: a style deleted weeks earlier and still recoverable was present before the prompt and gone after it, while the user was deleting something else entirely. The folders about to go are now named in RED before the question is asked, the undo promise is scoped to the style being deleted, and the sweep takes that list off the plan rather than recomputing it after the prompt -- the window can close while the user reads. `tstyles uninstall` asked for consent with a list naming the two PowerShell $PROFILE files precisely, and going on to promise what it would NOT touch, while step 2 stripped the loader block from ~/.zshrc, ~/.bashrc, ~/.bash_profile and ~/.profile -- named nowhere. It now prints the rc files themselves, and only those that really carry a block. Also: uninstall and shell-init help both described a narrower command than the one that runs, and the rc half of uninstall gained the test seams it needed to be exercised at all -- it resolves paths from the live $HOME, so it could not be tested without editing the operator''s own ~/.zshrc, which is why the omission went four releases without a test noticing.'
        }
    }
}
