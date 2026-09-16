@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.28'
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
            ReleaseNotes = 'v0.8.28: twenty-seven defects, the largest of this audit, and most of them are a claim the code did not honour or a test that could not have caught one. `tstyles delete` moved a style somewhere no command could name and nothing put it back -- there are now `tstyles trash` and `tstyles restore`, and the delete names the undo on its own success line. The uninstall consent screen stopped naming the $PROFILE it was about to edit on any machine with exactly one PowerShell engine, and only under Windows PowerShell 5.1: a single-element array emitted from an `if` block is unrolled, and .Count on the bare object answers 1 under pwsh 7 and $null under 5.1. That screen, and `tstyles help register`, also named Windows PowerShell 5.1 on macOS and Linux, where it cannot exist. `tstyles register` counted two engines where the machine has one $PROFILE file and wrote it twice; -Force overwrote your pristine backup on every run. `tstyles help` had a topic for all fourteen subcommands and none for `tstyles <style>`, the command the tool is for. `tstyles font <name>` ended in a red Windows Terminal error on WezTerm. The tuner offered to overwrite an untouched SHIPPED style and called it ''your saved style'', kept the replaced style''s wallpaper after saying REPLACED, and recorded a style''s own hash as its missing base so every later open reported a change that never happened. `tstyles reset` printed success whether the packet repainted the window or reached nothing at all, and the Terminal.app profile silently dropped colour slots every other path accepts. The zsh/bash runtime told Linux users to run brew. On the test side: the parity harness deleted every colour and tab title before comparing, so it could not check the byte-identity it exists to guarantee; the shell-leak tests certified a leaking style clean whenever the checkout path contained a space; two guards had been running zero assertions since the code they matched on moved; and the README''s command reference is now pinned to the module in both directions.'
        }
    }
}
