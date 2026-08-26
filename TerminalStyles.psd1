@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.9'
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
            ReleaseNotes = 'v0.8.9: cancelling the picker now actually puts your colours back, and the zsh/bash side stops leaking. Esc emitted the OSC reset, which hands colour control to the TERMINAL''s own defaults -- right on Windows Terminal, where settings.json has just been restored byte-exactly and WT repaints from it, and wrong everywhere else, where the style you arrived with was itself only escape sequences. So cancelling dropped you to a stock palette instead of back to your style. Ctrl+C was worse: it skipped the revert entirely and left the preview applied. From zsh or bash, every tstyles command first repainted the terminal with the CURRENTLY applied style and printed its banner, because the generated shim imported the module normally; and afterwards the wrapper re-sourced the prompt on any exit code 0, so "tstyles list" printed the banner a second time. A % in a git branch name corrupted the zsh prompt -- 100%done rendered as 100, the current directory, then one -- and the branch segment printed its own colour codes as literal text in bash. "tstyles uninstall" never undid "tstyles shell-init", leaving every new zsh tab fully themed with the documented recovery already broken. Also: an apostrophe in the module path produced a shell shim that could not parse, and one unwritable rc file aborted shell-init mid-loop with a raw .NET error.'
        }
    }
}
