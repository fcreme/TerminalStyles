@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.8.11'
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
            ReleaseNotes = 'v0.8.11: the picker could cache a truncated background image permanently. The prefetch job downloads each style''s image in the background and is killed the moment you pick -- but it wrote straight to the final cache path, so a half-finished transfer left a partial file exactly where every reader treats it as a valid cache hit, and nothing revalidates a file that exists. Downloads now land in a .part and are renamed only once complete. The picker also burned roughly 176 ms of work per second doing nothing on every terminal except Windows Terminal: its idle slice ran a filesystem probe per style about 20 times a second, then checked whether the result was wanted at all. And the update notice was printed a few lines before the picker cleared the screen, so it was wiped before it could be read while still costing the HTTP check. Also in this release: a login bash window printed the style''s banner twice and re-emitted its palette twice, because shell-init registers the same loader into both ~/.bashrc and ~/.bash_profile and the usual convention is for one to source the other; the loader now runs once per shell, with the guard set after the non-interactive check so ssh/scp/rsync stay silent.'
        }
    }
}
