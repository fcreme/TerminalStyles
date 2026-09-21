@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.45'
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
            ReleaseNotes = 'v0.8.45: phosphor, an eighteenth theme and the first that is not a picture. Early terminals could not choose a colour -- the inside of the tube carried a single phosphor and that was the whole palette, P1 green on the VT220 and the IBM 5151, P3 amber on the Wyse -- so emphasis was not a different colour, it was more electrons. Twelve of the sixteen colour slots are one green at different intensities; the four that are not are amber, because a machine that genuinely needed to signal alarm on a green tube is a machine with two phosphors in it. It is the only style that turns the retro terminal effect on, which suits a tube and not a photograph, and its background is a solid colour rather than an animation. Two backgrounds also stop being scaled up. skyline was too SHORT -- covering was driven by height -- so its picture was widened by mirroring the cityscape, with the moon painted out of the reflections, and it now sits flush with the bottom where its only visible edge goes off-screen. neon-rain was too NARROW, the opposite problem: covering enlarged it by half again and threw away most of its height, so it sits at its own size at street level. Neither is enlarged now.'
        }
    }
}
