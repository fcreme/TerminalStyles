@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.27'
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
            ReleaseNotes = 'v0.8.27: ten more defects, and the theme is a status that could not carry its own reason. Write-HostOscPacket returned the same $false for ''this style has no colours to paint'' and ''this terminal cannot paint'', so a style whose palette could not be read told you your terminal could not show colours -- it now returns ok / nocolors / unsupported / noterminal like the loader paths v0.8.26 fixed. {LEAF} meant two different things in the two halves of a style: zsh''s %1~ keeps the leading slash at /tmp and bash''s \W drops it, and the parity harness that exists to catch exactly this rendered only the zsh half -- it now renders both, which is what found it. A POSIX sh reading the loader out of ~/.profile errored on every prompt, because the sh branch was computed and then treated as bash; sh now gets the palette and keeps its own prompt, guarded at both call sites. tstyles register showed you one Import-Module line and wrote a different one, then told you to run a command that resolves to nothing on a bootstrap install. A failed install-SHA record was left in place naming the commit the install had just overwritten, so the update checker answered from a version that no longer existed. tstyles font spent the single rolling settings.json.bak silently, and the README named two of the five commands that spend it. Also: the tuner compared style directories with -eq on a case-insensitive filesystem, gitbash abbreviated ~ with no path boundary so a sibling of $HOME rendered as ~Xtra, the tstyles wrapper re-sourced a style prompt with no tty guard, and the help drift guard walked a hand-typed list three commands behind the module''s own.'
        }
    }
}
