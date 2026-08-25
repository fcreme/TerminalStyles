@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.8'
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
            ReleaseNotes = 'v0.8.8: the macOS and Linux gaps left over from 0.8.0. `tstyles register` did nothing on those platforms -- it probed only pwsh.exe and powershell.exe, and off Windows the binary is `pwsh` with no extension while Windows PowerShell does not exist at all, so it reported "Neither pwsh.exe nor powershell.exe was found on PATH. Nothing to do." and did exactly that, while the README tells macOS users to run it. `tstyles uninstall` shared the probe and so could not strip the loader either. The bootstrap installer had the same probe but threw instead of skipping, AFTER the files were already in place, leaving you installed with no loader and a stack trace; it now prints the one line to add to your profile. And shell/appleterminal.js had two guards that guarded nothing: a malformed hex reached parseInt, whose NaN NSColor accepts silently, so the archive carried NSRGB = "nan nan nan"; and the missing-image check read !bookmark, but a nil ObjC return arrives in JXA as a truthy wrapper, so a missing background produced a bookmark archiving nothing. Both are the shape Terminal rejects as a corrupt profile without naming the offending key. Also in this release: CONTRIBUTING.md never mentioned prompt.sh, which CI requires of every theme -- following the guide exactly turned the Linux and macOS legs red on a first PR -- and SECURITY.md listed 0.6.x as supported while pointing reporters at a private-reporting button this repository does not have.'
        }
    }
}
