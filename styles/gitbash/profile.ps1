# GITBASH profile -- pwsh 7 and Windows PowerShell 5.1.
# Recreates the classic Git-for-Windows MinTTY prompt:
#   <user>@<host> MINGW64 <~-relative path> (<branch>)
#   $
# Matches the colors closely: green user@host, yellow MINGW64, cyan path,
# magenta branch. Branch is detected by shelling out to git; if the cwd
# isn't a git repo, the (branch) part is omitted.
#
# No startup banner -- Git Bash itself is silent on launch.

$Host.UI.RawUI.WindowTitle = 'GITBASH // MINGW64'

function global:prompt {
    $Esc     = [char]27
    $Green   = "$Esc[38;2;0;128;0m"
    $Yellow  = "$Esc[38;2;155;150;29m"
    $Cyan    = "$Esc[38;2;0;119;119m"
    $Magenta = "$Esc[38;2;187;0;187m"
    $Gray    = "$Esc[38;2;56;56;56m"
    $X       = "$Esc[0m"

    # $env:USERNAME and $env:COMPUTERNAME are Windows-only; pwsh on macOS and
    # Linux sets neither, so this rendered as "@ MINGW64 <path>" with the
    # identity blank -- on the one style whose entire point is that line. The
    # zsh/bash half uses {USER}/{HOST}, which resolve correctly everywhere.
    $user     = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }

    # Path: substitute $HOME prefix with '~', then convert backslashes to
    # forward slashes for the authentic Git-Bash look.
    $path = $PWD.Path
    if ($path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        $path = '~' + $path.Substring($HOME.Length)
    }
    $path = $path -replace '\\', '/'

    # Branch detection. Save/restore $LASTEXITCODE so calling git here
    # doesn't pollute the user's subsequent error checks.
    $branchPart = ''
    $savedExit  = $LASTEXITCODE
    try {
        $b = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $b) {
            $branchPart = " ${Magenta}($b)${X}"
        }
    } catch { }
    $global:LASTEXITCODE = $savedExit

    "${Green}${user}@${hostname}${X} ${Yellow}MINGW64${X} ${Cyan}${path}${X}${branchPart}`n${Gray}`$${X} "
}

# PSReadLine -- colors keyed to the gitbash scheme. Light-bg means we
# need DARK syntax colors instead of the bright ones the cinematic themes use.
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    # Windows only. It is already the default there, and on macOS/Linux --
    # where PSReadLine defaults to Emacs -- EditMode Windows UNBINDS Ctrl+E,
    # Ctrl+K, Ctrl+U and Ctrl+D, and turns Ctrl+A into SelectAll. Applying a
    # colour theme silently took away Ctrl+D (end session) and Ctrl+U (clear
    # line); no style README mentions edit mode and nothing on screen explains
    # it. 5.1 predates $IsWindows and is Windows by definition, hence the
    # version test first -- the same order as Get-TStylesPlatform.
    if (($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows) {
        Set-PSReadLineOption -EditMode Windows
    }
    Set-PSReadLineOption -Colors @{
        Command   = '#383838'
        Parameter = '#0000BB'
        String    = '#A31515'
        Number    = '#098658'
        Comment   = '#008000'
        Operator  = '#383838'
        Variable  = '#007777'
        Type      = '#BB00BB'
        Keyword   = '#0000BB'
        Member    = '#383838'
        Default   = '#383838'
        Error     = '#CD3131'
        Selection = "$([char]27)[48;2;170;201;212m"
    }
    try {
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#999999' } -ErrorAction Stop
    } catch { }
}
