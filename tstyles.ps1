# tstyles.ps1 -- TerminalStyles loader + interactive picker.
#
# Dot-sourced from $PROFILE by install.ps1. Provides:
#   * `tstyles` (alias of Invoke-TerminalStyle) -- arrow-key live-preview picker.
#   * Auto-loads the currently selected style's profile.ps1 on shell startup.
#
# All write operations restore on Escape; the original settings.json bytes are
# snapshotted on entry so a cancel is byte-exact.

#Requires -Version 5.1

$script:TStylesModuleRoot = $PSScriptRoot
if (-not $script:TStylesModuleRoot) {
    $script:TStylesModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
function Get-TStylesPlatform {
    # 'Windows' | 'MacOS' | 'Linux'. The automatic $IsWindows/$IsMacOS/$IsLinux
    # variables only exist on PowerShell 6+; Windows PowerShell 5.1 predates
    # them and is Windows by definition, so branch on the major version first.
    # (Referencing $IsWindows under 5.1 would silently yield $null, not $true.)
    if ($PSVersionTable.PSVersion.Major -lt 6) { return 'Windows' }
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'MacOS' }
    return 'Linux'
}

function Get-PowerShellEngineCandidate {
    # The PowerShell engines to look for when registering or removing the
    # $PROFILE loader, in probe order.
    #
    # Windows ships .exe names and has two engines. Everywhere else the binary
    # is `pwsh` with no extension, and Windows PowerShell does not exist at all.
    # Probing only the .exe names made `tstyles register` and `tstyles uninstall`
    # silent no-ops on macOS and Linux -- "Neither pwsh.exe nor powershell.exe
    # was found on PATH. Nothing to do." -- on the very platforms 0.8.0 added
    # support for, and while the README tells those users to run register.
    #
    # -Platform is a test seam; real callers omit it.
    param([string]$Platform = (Get-TStylesPlatform))

    if ($Platform -eq 'Windows') {
        return @(
            [pscustomobject]@{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
            [pscustomobject]@{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
        )
    }

    # pwsh-preview is listed because it is what some macOS machines have INSTEAD
    # of pwsh, not merely alongside it -- Homebrew's stable cask went away.
    return @(
        [pscustomobject]@{ Exe = 'pwsh';         Label = 'PowerShell 7' },
        [pscustomobject]@{ Exe = 'pwsh-preview'; Label = 'PowerShell 7 (preview)' }
    )
}

function Get-TStylesDataRoot {
    # Stable per-user data dir. Survives module version upgrades (PSResourceGet
    # installs a new version to a sibling dir; state stays here). For bootstrap-
    # installed Windows users this happens to equal $script:TStylesModuleRoot --
    # backward-compatible by design, which is why Windows keeps %LOCALAPPDATA%
    # verbatim rather than moving to a new cross-platform location.
    #
    # -Platform / -HomeDir are test seams; real callers omit them.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'Windows' {
            # $env:LOCALAPPDATA is the historical location. Fall back to the
            # profile-relative path if the var is somehow unset (bare service
            # accounts, stripped environments) so we never Join-Path a $null.
            $base = $env:LOCALAPPDATA
            if (-not $base) { $base = Join-Path $HomeDir 'AppData\Local' }
            return Join-Path $base 'TerminalStyles'
        }
        'MacOS' {
            return Join-Path (Join-Path $HomeDir 'Library/Application Support') 'TerminalStyles'
        }
        default {
            # XDG Base Directory spec: honour $XDG_DATA_HOME, else ~/.local/share.
            $base = $env:XDG_DATA_HOME
            if (-not $base) { $base = Join-Path (Join-Path $HomeDir '.local') 'share' }
            return Join-Path $base 'TerminalStyles'
        }
    }
}

function Get-TStylesFontDir {
    # Per-user font directory -- the one a font can be dropped into WITHOUT
    # admin/root. Platform differences run deeper than the path:
    #   Windows: copy + an HKCU registry value + a GDI AddFontResource broadcast
    #   macOS:   copy alone is enough; CoreText picks up ~/Library/Fonts live
    #   Linux:   copy alone, though fontconfig may need `fc-cache` to notice
    # Install-Font branches on Get-TStylesPlatform for those extra steps.
    #
    # -Platform / -HomeDir are test seams; real callers omit them.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'Windows' {
            $base = $env:LOCALAPPDATA
            if (-not $base) { $base = Join-Path $HomeDir 'AppData\Local' }
            return Join-Path $base 'Microsoft\Windows\Fonts'
        }
        'MacOS' { return Join-Path (Join-Path $HomeDir 'Library') 'Fonts' }
        default {
            $base = $env:XDG_DATA_HOME
            if (-not $base) { $base = Join-Path (Join-Path $HomeDir '.local') 'share' }
            return Join-Path $base 'fonts'
        }
    }
}

# Terminal detection + capability model. Dot-sourced (not a nested module) so
# it shares $script: scope with everything below -- Get-TerminalCapability reads
# $script:TStylesCapabilityNames, and the adapters need $script:TStylesDataRoot.
. (Join-Path $script:TStylesModuleRoot 'terminals.ps1')

# The rest of the library, split by subsystem under lib/. Dot-sourced for the
# same reason as terminals.ps1: one shared $script: scope, so a function moved
# out of this file behaves exactly as it did in it.
#
# Enumerated rather than listed by name on purpose. A hardcoded list is one more
# place to forget when a file is added -- and the same mistake in
# scripts/publish.ps1's allowlist would ship a package that cannot import. The
# allowlist has a single 'lib' entry for that reason, so a new file here is
# picked up by both without being registered anywhere.
#
# Nothing under lib/ runs at load time, only defines, so alphabetical order is
# safe; the $script: initialisation below is the first thing to actually call
# any of it.
$script:TStylesLibDir = Join-Path $script:TStylesModuleRoot 'lib'
if (Test-Path -LiteralPath $script:TStylesLibDir) {
    foreach ($libFile in (Get-ChildItem -LiteralPath $script:TStylesLibDir -Filter '*.ps1' | Sort-Object Name)) {
        . $libFile.FullName
    }
}

$script:TStylesPlatform = Get-TStylesPlatform
$script:TStylesDataRoot = Get-TStylesDataRoot
if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
}
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

# Profile fields TerminalStyles writes onto a Windows Terminal profile entry.
# Single source of truth shared by Merge-StyleIntoSettings (apply) and
# Reset-StyleDirect (reset), so the two can't drift. Verified as the union of
# keys across all 16 bundled styles/*/theme.json files.
$script:TStylesBgFields    = @('backgroundImage', 'backgroundImageOpacity',
                               'backgroundImageStretchMode', 'backgroundImageAlignment')
$script:TStylesThemeFields = @('colorScheme', 'tabTitle', 'tabColor', 'cursorShape',
                               'useAcrylic', 'opacity', 'experimental.retroTerminalEffect',
                               'font', 'padding') + $script:TStylesBgFields

# === Internals ===

function Find-WTSettingsPath {
    # Prefer the settings.json of the Windows Terminal build hosting THIS session.
    # WT sets $env:WT_SETTINGS_PATH to its live file, so honoring it makes a user
    # on WT Preview (with Stable also installed) edit Preview's file -- not
    # Stable's, which the static list below would otherwise win. Falls back to the
    # candidate list (Stable > Preview > unpackaged) when the env var is absent.
    if ($env:WT_SETTINGS_PATH -and (Test-Path -LiteralPath $env:WT_SETTINGS_PATH)) {
        return $env:WT_SETTINGS_PATH
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-CurrentWTProfileName {
    param($Settings)
    if (-not $env:WT_PROFILE_ID) { return $null }
    $entry = $Settings.profiles.list | Where-Object { $_.guid -eq $env:WT_PROFILE_ID } | Select-Object -First 1
    if ($entry) { return $entry.name }
    return $null
}

function Get-StyleCacheDir {
    # The per-user, WRITABLE cache dir for a style's lazily-fetched background.
    # Single source of truth shared by Get-StyleBundledBackground, Test-StyleResolved,
    # and the picker's prefetch job so the writer and the readers can never drift.
    # The prefetch job runs in a separate runspace without $script: scope, so it
    # re-derives the same path from the data root -- keep this formula in sync
    # with that derivation (Join-Path (Join-Path $DataRoot 'cache') <name>).
    #
    # Nested Join-Path, NOT "cache\$StyleName": the 3-argument Join-Path is
    # PowerShell 6+ only (WinPS 5.1 takes two positional paths), and a literal
    # backslash is not a separator on macOS/Linux -- it would produce a single
    # file named "cache\eva" instead of the cache/eva directory.
    param([Parameter(Mandatory)][string]$StyleName)
    Join-Path (Join-Path $script:TStylesDataRoot 'cache') $StyleName
}


function Invoke-TerminalStylesStateMigration {
    # Migrates pre-0.2.0 data layout to 0.2.0:
    #   - Cached background.<ext> files move from $ModuleRoot\styles\<name>\
    #     to $DataRoot\cache\<name>\.
    #   - .no-background negative-cache markers move similarly.
    # Idempotent. Skips work if the marker file exists.
    $marker = Join-Path $script:TStylesDataRoot '.migrated-0.2.0'
    if (Test-Path -LiteralPath $marker) { return }

    # Claim the migration immediately (before the move loop) so a second shell
    # importing the module concurrently -- e.g. several WT tabs opened at once --
    # sees the marker and bails instead of racing the same Move-Item calls. The
    # moves are best-effort and self-healing (a background missed here re-fetches
    # into the cache dir on demand), so claiming up front is the safe trade.
    try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) { return }

    foreach ($styleDir in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        $styleName = $styleDir.Name
        $cacheDir = Join-Path (Join-Path $script:TStylesDataRoot 'cache') $styleName

        # Move cached background files
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $src = Join-Path $styleDir.FullName "background.$ext"
            if (Test-Path -LiteralPath $src) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
                }
                $dest = Join-Path $cacheDir "background.$ext"
                try {
                    Move-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                } catch {
                    # Source might be read-only (PSGallery install with stale
                    # bundled file from manual user copy). Acceptable -- the
                    # bundled file stays readable in place.
                }
            }
        }

        # Move negative-cache marker
        $srcMarker = Join-Path $styleDir.FullName '.no-background'
        if (Test-Path -LiteralPath $srcMarker) {
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
            }
            try {
                Move-Item -LiteralPath $srcMarker -Destination (Join-Path $cacheDir '.no-background') -Force -ErrorAction Stop
            } catch { }
        }
    }
    # Marker was already written at the top (claim-before-work); nothing to do here.
}


# Every word Invoke-TerminalStyle dispatches BEFORE it considers a style name.
# A style called one of these can be created and will list, tab-complete and
# show in the picker -- and can never be applied, because the dispatch arm wins.
# Naming a style `reset` was the sharp case: `tstyles reset` ran Reset-StyleDirect
# (OSC reset, cleared the style record and shell state, deleted current-style.ps1)
# and reported "Reset <terminal> to its unstyled default."
$script:TStylesSubcommands = @(
    'font', 'help', 'list', 'ls', 'current', 'random', 'register', 'reset',
    'shell-init', 'shell-remove', 'tune', 'update', 'uninstall')

function Test-StyleNameIsSingleSegment {
    <#
    .SYNOPSIS
    Is $Name one directory name, rather than a path?

    .DESCRIPTION
    The gate every name-to-path conversion passes through. It rejects ONLY what
    stops a name being a single path segment -- it is deliberately not a
    taste test.

    Why it exists: the tuner composes its scratch directory under the data root
    and removes it, whole and recursive, in a finally block. `.tune-preview` and
    `styles` are both single-segment children of that root, so a name reaching
    up a level makes the two paths the same directory -- the scratch dir IS the
    style dir -- and `tstyles tune ../styles/eva` deleted styles/eva on the way
    out, reporting "Reverted." and exiting 0. A tune.json `base` carrying the
    same thing did it with nothing unusual typed.

    Why it is not the stricter rule the tuner applies to names it CREATES: a
    hand-authored style is just a folder the user drops in, and README's
    "Adding your own style" puts no constraint on what it is called. Rejecting
    spaces or non-ASCII here would strand every such style in a state worse
    than not existing -- Get-AvailableStyles enumerates directories with no
    filter, so `My Theme` would still list, still tab-complete, and then fail
    at every use site (apply, tune, current, the shell-startup re-emit,
    background inheritance). Reject paths, not names.

    Returns $true/$false; never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -eq '.' -or $Name -eq '..')    { return $false }
    if ($Name.IndexOfAny([char[]]@('/', '\')) -ge 0) { return $false }
    if ($Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    # Control characters are legal in a POSIX filename and never intended here.
    if ($Name -match '[\x00-\x1f\x7f]')      { return $false }
    # One path segment cannot exceed this on any filesystem the project targets.
    if ($Name.Length -gt 255)                { return $false }
    return $true
}

function Test-StyleNameValid {
    <#
    .SYNOPSIS
    Is $Name acceptable for a style this tool is about to CREATE?

    .DESCRIPTION
    Stricter than Test-StyleNameIsSingleSegment, and applied only where the
    tool invents a new directory rather than resolving one that already exists
    -- today that is the tuner's Save-As prompt, which has enforced
    `^[A-Za-z0-9._-]+$` since it was written.

    Two things the character class alone still admits are excluded. `.` and
    `..` match it and are not names but directories: saving under either wrote
    the style's four files into the styles directory itself or its parent,
    producing something `tstyles list` could never show. And a name long enough
    to push the path past the OS limit threw a raw .NET path exception from
    inside Save-TunedStyle, after the user had already committed to the save.

    Resolving an EXISTING style deliberately does not use this -- see
    Test-StyleNameIsSingleSegment for why.

    Returns $true/$false; never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Name)

    if (-not (Test-StyleNameIsSingleSegment -Name $Name)) { return $false }
    if ($Name.Length -gt 64) { return $false }
    # A subcommand name produces a style that can never be applied: the dispatch
    # arm for it runs first, so `tstyles <name>` does the subcommand instead.
    if ($script:TStylesSubcommands -contains $Name.ToLowerInvariant()) { return $false }
    return ($Name -match '^[A-Za-z0-9._-]+$')
}

function Get-StyleDir {
    # Resolves a style name to its on-disk directory, checking the user
    # dir first ($DataRoot\styles\<name>\) then the bundled dir
    # ($ModuleRoot\styles\<name>\). Returns $null if neither has a
    # scheme.json for that name. User-wins matches Get-AvailableStyles'
    # union-and-dedup precedence.
    param([Parameter(Mandatory)][string]$StyleName)

    # The choke point. Every path built from a style name -- the style dir
    # itself, the tuner's scratch dir, the background cache -- starts from a
    # name that resolved here, so refusing a name that is not a single
    # directory segment here keeps a separator out of all of them. Callers
    # already handle $null as "no such style", which is the honest answer:
    # `../styles/eva` is not a style, and treating it as one let the tuner
    # delete the real one.
    #
    # The SEGMENT test, not the stricter create-time one: a hand-authored style
    # is whatever folder name the user chose, and rejecting spaces or non-ASCII
    # here would break styles that already work and that README invites.
    if (-not (Test-StyleNameIsSingleSegment -Name $StyleName)) { return $null }

    $userDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $StyleName
    if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) { return $userDir }

    $bundledDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $StyleName
    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) { return $bundledDir }

    return $null
}

function Get-AvailableStyles {
    # Returns DirectoryInfo for every styles/<name>/ that has a scheme.json,
    # merged from two locations:
    #   1. $DataRoot\styles\<name>\ -- user dir, persistent across updates
    #   2. $ModuleRoot\styles\<name>\ -- bundled, install-managed
    # User-wins on name collision (matches Get-StyleDir's precedence).
    # Sorted alphabetically by name.
    $userStylesDir    = Join-Path $script:TStylesDataRoot   'styles'
    $bundledStylesDir = Join-Path $script:TStylesModuleRoot 'styles'

    $user = if (Test-Path -LiteralPath $userStylesDir) {
        @(Get-ChildItem -LiteralPath $userStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $bundled = if (Test-Path -LiteralPath $bundledStylesDir) {
        @(Get-ChildItem -LiteralPath $bundledStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $userNames = @($user | ForEach-Object Name)
    @(@($user) + @($bundled | Where-Object { $_.Name -notin $userNames })) | Sort-Object Name
}

function Get-CurrentStyleName {
    # Detects which bundled style is currently active by byte-comparing
    # current-style.ps1 against each style's profile.ps1. Returns $null
    # if nothing matches (custom profile, no current style, etc).
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        $current = [System.IO.File]::ReadAllText($script:TStylesCurrent, [System.Text.UTF8Encoding]::new($false))
        foreach ($style in (Get-AvailableStyles)) {
            $sp = Join-Path $style.FullName 'profile.ps1'
            if (-not (Test-Path -LiteralPath $sp)) { continue }
            $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
            if ($current -eq $styleContent) { return $style.Name }
        }
    }

    # Fall back to the recorded style. The byte-compare above can't see a style
    # applied with -KeepPrompt (which deliberately leaves current-style.ps1
    # absent) -- on OSC-driven terminals that would report "no style" while the
    # colors are plainly applied. The record knows regardless of the prompt.
    $record = Get-CurrentStyleRecord
    if ($record -and $record.name) {
        if (Get-StyleDir -StyleName $record.name) { return $record.name }
    }

    return $null
}

function Test-StyleResolved {
    # A style is "resolved" if we know its background state -- either a
    # bundled background.<ext> exists under $StyleDir (module root), or a
    # cached background.<ext>/.no-background exists under $DataRoot\cache\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir, [switch]$NoInherit)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir = Get-StyleCacheDir -StyleName $styleName
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $cacheDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }

    # Tuned styles inherit resolution from their base. -NoInherit suppresses
    # this (used on the recursive base call) so a cyclic tune.json (A->B->A)
    # cannot recurse -- resolution is strictly one hop.
    if (-not $NoInherit) {
        $tuneFile = Join-Path $StyleDir 'tune.json'
        if (Test-Path -LiteralPath $tuneFile) {
            try {
                $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($tune.base) {
                    $baseDir = Get-StyleDir -StyleName $tune.base
                    # Compared the way the host filesystem compares, so that on a
                    # case-sensitive volume a base differing from the style only
                    # in case is still a different directory. See
                    # Test-SameStyleDirectory for why -eq/-ne is wrong here.
                    if ($baseDir -and -not (Test-SameStyleDirectory -A $baseDir -B $StyleDir)) {
                        return (Test-StyleResolved -StyleDir $baseDir -NoInherit)
                    }
                }
            } catch { }
        }
    }
    return $false
}


# Canonical display names for families TerminalStyles knows about, keyed by
# Get-FontComparisonKey. Used to turn a scanned filename back into the name the
# terminal expects -- "JetBrainsMono-Regular.ttf" is the family "JetBrains Mono",
# and setting a font to "Jet Brains Mono" would simply not resolve.
$script:TStylesKnownFontNames = @{}
foreach ($n in @(
        'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'Cascadia Mono', 'Hack',
        'Source Code Pro', 'IBM Plex Mono', 'DejaVu Sans Mono', 'Liberation Mono',
        'Ubuntu Mono', 'Noto Sans Mono', 'Consolas', 'Lucida Console',
        'Courier New', 'Courier', 'Menlo', 'Monaco', 'SF Mono', 'Andale Mono',
        'PT Mono', 'MonoLisa', 'Iosevka', 'Victor Mono', 'Cousine')) {
    $script:TStylesKnownFontNames[(($n -replace '[^A-Za-z0-9]', '').ToLowerInvariant())] = $n
}


# === Public command ===

function Invoke-TerminalStyle {
    [CmdletBinding()]
    param(
        # Positional argument: a subcommand (list / current / random / tune /
        # register / update / uninstall / help), or a bundled style name
        # (umbrella / eva / ...). Use -Target to specify a Windows Terminal
        # profile explicitly; an unrecognized arg prints help.
        [Parameter(Position=0)]
        [string]$Arg,
        # Second positional: a style name for `tstyles tune <name>`. Backward-
        # compatible -- existing single-positional usage binds to $Arg only.
        [Parameter(Position=1)]
        [string]$SubArg,
        # Explicit Windows Terminal profile to apply to (defaults to the
        # current tab's profile via $env:WT_PROFILE_ID).
        [string]$Target,
        [string]$BackgroundImage,
        [switch]$Update,
        # Used with `tstyles update -Force` to skip the same-SHA optimization
        # and force a full reinstall (e.g., after a botched install).
        [switch]$Force,
        # Apply a style's visuals but keep your own prompt (skip the style's
        # prompt/banner). Threaded to Apply-StyleDirect for `tstyles <name>`.
        [switch]$KeepPrompt,
        # Terminal.app only: open a new window carrying the style's background
        # image, which no escape sequence can deliver to the current one.
        [switch]$NewWindow,
        # `tstyles uninstall -DeleteData`: also delete the data root (active
        # style, cached backgrounds, tuned styles, shell staging). Without it
        # uninstall removes only install-managed files and leaves user state,
        # so a reinstall picks up where you left off.
        [switch]$DeleteData
    )

    $bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')

    # --- Subcommand dispatch ---
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'font')                 { Invoke-TerminalStyleFont -Name $SubArg -Target $Target; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               {
        Invoke-RandomStyle -Target $Target `
            -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
            -KeepPrompt:$KeepPrompt -NewWindow:$NewWindow
        return
    }
    if ($Arg -eq 'reset')                {
        # `tstyles reset Ubuntu` puts "Ubuntu" in $SubArg, the second positional.
        # Reading only -Target meant the name was silently ignored and the
        # AUTO-DETECTED profile was reset instead -- the wrong profile, with a
        # success message. -Target still wins when both are given.
        $resetTarget = if ($Target) { $Target } else { $SubArg }
        Reset-StyleDirect -Target $resetTarget; return
    }
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
    if ($Arg -eq 'help')                 { Show-TerminalStyleHelp -Command $SubArg; return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
    if ($Arg -eq 'shell-init')           { Invoke-TerminalStylesShellInit -Force:$Force; return }
    if ($Arg -eq 'shell-remove')         { Invoke-TerminalStylesShellInit -Remove; return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall -DeleteData:$DeleteData; return }

    # If $Arg matches a bundled style, apply it directly (no picker).
    if ($Arg) {
        $styleMatch = Get-AvailableStyles | Where-Object Name -eq $Arg | Select-Object -First 1
        if ($styleMatch) {
            Apply-StyleDirect -StyleName $Arg -Target $Target `
                -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
                -KeepPrompt:$KeepPrompt -NewWindow:$NewWindow
            return
        }
        # Not a subcommand and not a style name: show help instead of silently
        # opening the picker against a (likely bogus) profile name. To target a
        # specific Windows Terminal profile, use the -Target parameter.
        Write-Host "Unknown command or style: '$Arg'" -ForegroundColor Yellow
        Show-TerminalStyleHelp
        Write-Host "To target a Windows Terminal profile, use: tstyles -Target '<name>'" -ForegroundColor DarkGray
        return
    }

    # One-time opt-in font prompt (fires only in interactive sessions, never for
    # subcommands — they all `return` above before reaching this point).
    Invoke-FontFirstRunPrompt

    # Update-notice path runs on every passive invocation, but the PICKER is a
    # special case: it Clear-Host's before drawing its menu, so a notice printed
    # here was wiped a few lines later and never read -- while still costing the
    # HTTP check that produced it. Hold the result and print it after the picker
    # gives the screen back, below.
    $pendingUpdate = Test-UpdateAvailable

    # Windows Terminal previews a style by writing settings.json and letting WT
    # reload; every other terminal previews purely through the OSC packet the
    # render loop already emits. So settings.json handling is conditional from
    # here down: $useSettingsFile gates the read, the snapshot, the per-arrow
    # writes, and the Esc revert.
    $termKind        = Get-TerminalKind
    $useSettingsFile = ($termKind -eq 'WindowsTerminal')

    $settingsPath = $null
    if ($useSettingsFile) {
        $settingsPath = Find-WTSettingsPath
        if (-not $settingsPath) {
            Write-Error "Could not locate Windows Terminal settings.json."
            return
        }
    }

    # Enumerate via the shared helper so the picker shows user + tuned styles
    # too (the same union that list/current/random/dispatch/tab-completion use),
    # not just the bundled set.
    $styles = @(Get-AvailableStyles)
    if (-not $styles) {
        Write-Error "No styles found."
        return
    }

    # Snapshot original (byte-exact for revert)
    # MUST be UTF-8 explicit: Get-Content -Raw in Windows PowerShell 5.1
    # defaults to the system ANSI codepage (Windows-1252 on Spanish locale),
    # which mangles non-ASCII profile names (e.g. "Símbolo del sistema").
    # The mangled string then round-trips through ConvertTo-Json + WriteAllText
    # as UTF-8, doubling the byte count of non-ASCII chars on every call.
    $originalJson     = $null
    $originalSettings = $null
    if ($useSettingsFile) {
        $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
        $originalSettings = ConvertFrom-WTJson $originalJson

        if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $originalSettings }
        if (-not $Target) {
            Write-Host "Could not auto-detect the current Windows Terminal profile."
            Write-Host "Available: $((@('defaults') + @($originalSettings.profiles.list.name)) -join ', ')"
            $Target = (Read-Host "Target profile").Trim()
            if (-not $Target) { return }
        }
    }

    # Single choke point for every settings.json write in the picker. Off
    # Windows Terminal this is a no-op, so the loop below reads the same in
    # both worlds instead of repeating the guard at each call site.
    $writeSettings = {
        param([string]$Json)
        if ($useSettingsFile -and $Json) {
            Write-SettingsAtomic -Path $settingsPath -Json $Json
        }
    }

    # What the picker header names as the thing being styled. On Windows
    # Terminal that is the profile the style gets written to. Elsewhere there is
    # no profile at all, and $Target is empty -- the header read "Choose a style
    # for ''", which looks like a bug. Name the terminal instead, since that is
    # what actually changes.
    # The picker is a keyboard-driven UI: it polls [Console]::KeyAvailable, which
    # throws outright when stdin is not a console -- piped input, a redirect, a
    # CI step, or a tool that runs commands with stdin detached. The raw failure
    # is ".NET: Cannot see if a key has been pressed ... Try Console.In.Peek",
    # thrown AFTER the menu has been drawn, which reads like the picker broke
    # rather than like it needs a terminal. Check up front and say so.
    if ([Console]::IsInputRedirected) {
        Write-Host ""
        Write-Host "  The style picker needs an interactive terminal." -ForegroundColor Yellow
        Write-Host "  This session's input is redirected, so there are no keystrokes to read."
        Write-Host ""
        Write-Host "  Apply a style directly instead:" -ForegroundColor DarkGray
        Write-Host "    tstyles <name>     " -NoNewline -ForegroundColor DarkGray
        Write-Host "(tstyles list shows them all)" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $pickerTargetLabel = if ($useSettingsFile) { "'$Target'" }
                         else { Get-TerminalDisplayName -Kind $termKind }

    if (-not (Test-StyledHost -Kind $termKind)) {
        Write-Host "Note: this host doesn't render colors; you'll get the prompt but not the palette." -ForegroundColor Yellow
    } elseif (-not $useSettingsFile) {
        $caps = Get-TerminalCapability -Kind $termKind
        if (-not $caps.BackgroundImage) {
            Write-Host ("Note: {0} renders the palette but not background images." -f (Get-TerminalDisplayName -Kind $termKind)) -ForegroundColor DarkGray
        }
    }

    # Start on the currently active style if we can detect one -- opening
    # the picker should land where the user already is, not at the first
    # alphabetical entry. Falls back to 0 for custom/unrecognized profiles.
    $idx = 0
    $currentName = Get-CurrentStyleName
    if ($currentName) {
        for ($i = 0; $i -lt $styles.Count; $i++) {
            if ($styles[$i].Name -eq $currentName) { $idx = $i; break }
        }
    }
    $confirmed = $false

    # What "revert" has to put back. On Windows Terminal it is the byte-exact
    # settings.json, which WT repaints from on its own. Off Windows Terminal the
    # applied style exists ONLY as escape sequences in this tab, so there is
    # nothing to repaint from -- reverting has to re-emit the style the user
    # arrived with, and only when there was one. $startIdx is captured here
    # because $idx is the live cursor and has moved by the time Esc arrives.
    $startIdx        = $idx
    $hadCurrentStyle = [bool]$currentName
    # A hashtable, not a [bool]: the revert runs inside a scriptblock, and a
    # plain assignment there would land in the scriptblock's own child scope and
    # never be seen out here. The finally block needs to know whether the revert
    # already happened.
    $pickerState     = @{ Reverted = $false }

    # Pre-load each style's color swatch AND the parsed scheme object.
    # Schemes are reused per-arrow to emit OSC color escapes (see the
    # render loop below) so the terminal repaints colors in <5ms, well
    # before the eventual settings.json write triggers Windows Terminal's
    # full reload cycle.
    $swatches = @{}
    $schemes  = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $sp = Join-Path $styles[$i].FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatches[$i] = Get-SchemeSwatch -Scheme $scheme
        $schemes[$i]  = $scheme
    }

    # Pre-load each style's tabTitle (from theme.json). settings.json's
    # tabTitle isn't honored by Windows Terminal for a tab whose shell has
    # already set $Host.UI.RawUI.WindowTitle (every theme's profile.ps1
    # does), so we have to set WindowTitle explicitly on each arrow change
    # to make the title preview live. Themes without a tabTitle simply
    # leave the current title untouched while highlighted.
    $titles = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $tp = Join-Path $styles[$i].FullName 'theme.json'
        if (-not (Test-Path -LiteralPath $tp)) { continue }
        try {
            $theme = [System.IO.File]::ReadAllText($tp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($theme.PSObject.Properties.Match('tabTitle').Count -gt 0) {
                $titles[$i] = $theme.tabTitle
            }
        } catch { }
    }

    # Background prefetch: kick off ONE job that downloads any missing GIFs
    # from the gifs branch serially. The picker stays interactive while this
    # runs; by the time the user arrow-keys through a few styles, the rest
    # are usually already cached locally. Worst case: the user reaches a
    # style before its GIF arrives -- the synchronous fetch in
    # Get-StyleBundledBackground handles it (same code path as today).
    #
    # Skipped entirely when the terminal cannot show a background image. On
    # Terminal.app the picker was downloading a GIF per style from the gifs
    # branch -- megabytes over the network, and a "...fetching background" row
    # next to every entry -- for an image that can never be drawn.
    $wantsBackgrounds = (Get-TerminalCapability -Kind $termKind).BackgroundImage

    $missingPaths = @()
    if ($wantsBackgrounds) {
        foreach ($s in $styles) {
            if (-not (Test-StyleResolved -StyleDir $s.FullName)) {
                $missingPaths += $s.FullName
            }
        }
    }
    $prefetchJob = $null
    if ($missingPaths.Count -gt 0) {
        # Prefer Start-ThreadJob if available -- it's ~10x faster to start
        # than Start-Job (pwsh 7 ships it; WinPS 5.1 has it only if the
        # user installed the ThreadJob module). Falls back to Start-Job.
        $jobStarter = if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            'Start-ThreadJob'
        } else {
            'Start-Job'
        }
        $prefetchJob = & $jobStarter -ScriptBlock {
            param($Paths, $DataRoot)
            $ProgressPreference = 'SilentlyContinue'
            foreach ($styleDir in $Paths) {
                $styleName = Split-Path -Leaf $styleDir
                # Write into the per-user CACHE dir -- the same location
                # Get-StyleBundledBackground/Test-StyleResolved read from. The job
                # runs in a separate runspace without $script: scope, so the cache
                # path is re-derived from the $DataRoot passed via -ArgumentList
                # (kept in sync with Get-StyleCacheDir). Writing into $styleDir
                # instead would be a no-op on read-only PSGallery installs and would
                # strand the .no-background marker where no reader looks.
                $cacheDir = Join-Path (Join-Path $DataRoot 'cache') $styleName
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { continue }
                }
                $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
                $success = $false
                foreach ($ext in 'gif','png','jpg','jpeg') {
                    $local = Join-Path $cacheDir "background.$ext"
                    # Download to a sibling .part and rename into place only once
                    # the transfer finished. This job is killed with Stop-Job the
                    # moment the user picks, and writing -OutFile straight to the
                    # final name left a HALF-DOWNLOADED file sitting at the path
                    # every reader treats as a valid cache hit -- so a truncated
                    # GIF became that style's background permanently, since
                    # nothing revalidates a file that exists. A killed job now
                    # leaves only a .part, which no reader looks for.
                    $part = "$local.part"
                    try {
                        Invoke-WebRequest -Uri "$remoteBase.$ext" -OutFile $part `
                            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        if ((Get-Item -LiteralPath $part -ErrorAction SilentlyContinue).Length -gt 0) {
                            Move-Item -LiteralPath $part -Destination $local -Force
                            $success = $true
                            break
                        } else {
                            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
                    }
                }
                if (-not $success) {
                    # Dated marker, matching Get-StyleBundledBackground's format.
                    # An undated one reads as expired (0.8.6), so the prefetch's
                    # negative caching was silently doing nothing.
                    try {
                        $marker = [pscustomobject]@{
                            schemaVersion = 1
                            kind          = 'absent'
                            at            = [datetime]::UtcNow.ToString('o')
                        }
                        [System.IO.File]::WriteAllText((Join-Path $cacheDir '.no-background'),
                            ($marker | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
                    } catch { }
                }
            }
        } -ArgumentList $missingPaths, $script:TStylesDataRoot
    }

    # Memoization: cache the final JSON string per style index. Only cache
    # AFTER the style is resolved (so we don't pin a JSON that was computed
    # while the GIF was still pending). Arrow-keying back to a previously-
    # visited resolved style writes the cached string straight to disk --
    # skips ConvertFrom-Json + Merge + ConvertTo-Json (~100ms per cycle).
    $mergedCache = @{}

    # On-disk rolling backup before any preview write. The picker reverts in
    # memory on Esc, but a hard kill mid-preview would otherwise leave the
    # last-previewed theme with no recoverable original; this .bak (same one the
    # direct-apply/reset paths roll) is that recovery copy.
    # Crash-recovery copy -- only meaningful when a settings.json exists.
    if ($useSettingsFile) { try { [System.IO.File]::WriteAllText("$settingsPath.bak", $originalJson, [System.Text.UTF8Encoding]::new($false)) } catch { } }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle
    try {
        # Apply first preview before showing the menu. The merge is skipped
        # entirely off Windows Terminal: there is no $originalJson to merge into,
        # and the OSC packet emitted by the render loop is the whole preview.
        if ($useSettingsFile) {
            $preview = ConvertFrom-WTJson $originalJson
            $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$idx].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
            $initialJson = $preview | ConvertTo-Json -Depth 100
            & $writeSettings $initialJson
            if (Test-StyleResolved -StyleDir $styles[$idx].FullName) {
                $mergedCache[$idx] = $initialJson
            }
        } else {
            # Paint the starting style, which on Windows Terminal the
            # settings.json write above would have done. Built from $schemes
            # rather than the $oscPackets cache: that cache is populated further
            # down, for the per-keystroke path, and is still $null here --
            # indexing it threw "Cannot index into a null array" and took the
            # picker down before it drew a single row.
            Write-HostOscPacket -Packet (Get-SchemeOscPacket -Scheme $schemes[$idx])
        }
        if ($titles.ContainsKey($idx)) { $Host.UI.RawUI.WindowTitle = $titles[$idx] }

        # Truecolor mid-gray for the picker's secondary text. PowerShell's
        # "DarkGray" maps to each scheme's brightBlack slot, which on
        # low-contrast themes (rain, forest, golden-forest) sits too close
        # to the background to read. A fixed #a0a0a0 stays legible on every
        # background -- dark themes and the light gitbash alike.
        $hintColor  = "$([char]27)[38;2;160;160;160m"
        $resetColor = "$([char]27)[0m"

        # Clear once, then capture the buffer Y of the picker's home row.
        # Subsequent iterations reposition the cursor here and overwrite in
        # place instead of Clear-Host-ing per arrow press -- the per-arrow
        # clear was the source of the visible flicker. The number of lines
        # is constant (header + hint + blank + N styles + blank), so the
        # overwrite covers the previous frame exactly with no leftover
        # characters. \e[K appended to each potentially shrinking line
        # would defend against future content-width changes; not needed
        # today since every row has stable width.
        Clear-Host
        $renderHomeY = [Console]::CursorTop

        # Non-blocking render loop with three responsibilities, in
        # strict priority order:
        #   1. Process pending keypresses -- update $idx, redraw the
        #      menu IMMEDIATELY so the cursor visually moves, but do
        #      NOT apply the theme yet. Set $pendingApply = $idx and
        #      loop back to drain any further keypresses.
        #   2. Apply the pending theme (settings.json write + tab
        #      title) once the keypress queue is empty. Mashed arrows
        #      collapse to a single apply at the final position --
        #      Windows Terminal does one reload instead of N.
        #   3. Prebuild the next uncached resolved theme's merged
        #      JSON during idle slices so future applies are pure
        #      WriteAllText (no parse / merge / serialize).
        #
        # Net effect:
        #   Single tap  -> cursor jumps in ~5ms, theme applies after
        #                  ~50-100ms once the gap is detected.
        #   Mash 5 keys -> cursor moves through all 5 visually, only
        #                  the final position is written to settings.json,
        #                  WT does one reload instead of five.
        # Build pre-serialized OSC color packets, one per theme. Each
        # packet is a single string of ANSI OSC sequences that, when
        # written to stdout, instantly retints the terminal's
        # foreground / background / cursor / selection / 16-color
        # palette to that theme -- no settings.json write, no Windows
        # Terminal reload. The eventual settings.json write (deferred
        # to when the keypress queue drains) still happens and brings
        # the background image, cursor shape, font, etc. into line a
        # few hundred ms later, but the colors have already shifted
        # so the perceived freeze drops to near-zero.
        $oscPackets = @{}
        for ($i = 0; $i -lt $styles.Count; $i++) {
            $oscPackets[$i] = Get-SchemeOscPacket -Scheme $schemes[$i]
        }

        $drawMenu = {
            param($idx)
            [Console]::SetCursorPosition(0, $renderHomeY)
            Write-Host ""
            Write-Host "  Choose a style for " -NoNewline
            Write-Host $pickerTargetLabel -ForegroundColor Cyan
            Write-Host "$hintColor  Up/Down to preview, Enter to keep, Esc to cancel$resetColor"
            Write-Host "$hintColor  Tip: run 'tstyles help' for all commands$resetColor"
            Write-Host ""
            # Rows the frame spends on anything that is not a style: the leading
            # blank, the header line, the two hint lines, the two always-present
            # scroll indicators, the trailing blank, and one spare so the shell's
            # own prompt has somewhere to land.
            $chrome = 8
            # A non-positive WindowHeight means "I don't know", not "no room".
            # It reads as 0 under a pty whose size was never set -- some CI
            # runners, some SSH sessions before the first SIGWINCH -- and
            # subtracting the chrome from that would collapse the menu to a
            # single row, which is far worse than the unbounded frame this
            # viewport exists to prevent. Fall back to the old behaviour of
            # drawing everything, which was fine for years.
            $available = $styles.Count
            try {
                $wh = [Console]::WindowHeight
                if ($wh -gt 0) { $available = $wh - $chrome }
            } catch { }
            $vp = Get-PickerViewport -Total $styles.Count -Selected $idx -Available $available
            # Both indicator rows are ALWAYS emitted, blank when there is
            # nothing to report. The frame is overwritten in place rather than
            # cleared, so its height has to be identical every redraw -- a row
            # that comes and goes would leave the taller frame's last line
            # stranded on screen.
            if ($vp.More -and $vp.First -gt 0) {
                Write-Host "$hintColor     ... $($vp.First) more above$resetColor"
            } else {
                Write-Host ""
            }
            for ($i = $vp.First; $i -lt ($vp.First + $vp.Count); $i++) {
                $name = $styles[$i].Name
                # "Resolved" means the style's background image is on disk. That
                # only gates the swatch when a background can actually be shown;
                # where it cannot, every style is ready the moment it is listed,
                # and reporting "...fetching background" would be describing work
                # that is deliberately never done.
                $resolved = (-not $wantsBackgrounds) -or (Test-StyleResolved -StyleDir $styles[$i].FullName)
                $color = if ($i -eq $idx) { 'Yellow' } else { 'Gray' }
                $prefix = if ($i -eq $idx) { '   > ' } else { '     ' }
                Write-Host ($prefix + ('{0,-16}  ' -f $name)) -ForegroundColor $color -NoNewline
                if ($resolved) {
                    Write-Host $swatches[$i]
                } else {
                    Write-Host "$hintColor...fetching background$resetColor"
                }
            }
            $below = $styles.Count - ($vp.First + $vp.Count)
            if ($vp.More -and $below -gt 0) {
                Write-Host "$hintColor     ... $below more below$resetColor"
            } else {
                Write-Host ""
            }
            Write-Host ""
        }

        $applyTheme = {
            param([int]$i)
            # Off Windows Terminal the OSC retint in $onRetint already did the
            # whole preview -- there is no deferred settings.json write to make.
            if (-not $useSettingsFile) {
                if ($titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
                return
            }
            $resolved = Test-StyleResolved -StyleDir $styles[$i].FullName
            if ($resolved -and $mergedCache.ContainsKey($i)) {
                & $writeSettings $mergedCache[$i]
            } else {
                $preview = ConvertFrom-WTJson $originalJson
                $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$i].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $json = $preview | ConvertTo-Json -Depth 100
                & $writeSettings $json
                if ($resolved) { $mergedCache[$i] = $json }
            }
            if ($titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
        }

        # Per-keystroke instant retint (OSC color packet). The deferred
        # settings.json write is $applyTheme, passed as -OnPreview.
        $onRetint = { param($i) [Console]::Out.Write($oscPackets[$i]) }

        # Esc: restore the byte-exact original settings.json and undo the live
        # OSC retint so the cancelled preview's colors don't linger.
        #
        # Get-OscResetPacket hands color control back to the terminal's OWN
        # defaults, which is right on Windows Terminal -- settings.json has just
        # been restored and WT repaints from it. Off Windows Terminal there is no
        # such file: the style the user arrived with was itself only escape
        # sequences, so resetting drops them to the terminal's stock palette
        # rather than back to their style. Re-emit it instead.
        $restoreOriginalLook = {
            & $writeSettings $originalJson
            if (-not $useSettingsFile -and $hadCurrentStyle -and $schemes.ContainsKey($startIdx)) {
                Write-HostOscPacket -Packet (Get-SchemeOscPacket -Scheme $schemes[$startIdx]) | Out-Null
            } else {
                [Console]::Out.Write((Get-OscResetPacket))
            }
            $pickerState.Reverted = $true
        }
        $onRevert = $restoreOriginalLook

        # Idle slice: prebuild the next uncached resolved theme's merged JSON,
        # else sleep briefly. (Verbatim from the old idle branch.)
        $onIdle = {
            # Nothing to prebuild when no settings.json is being written, so bail
            # BEFORE the scan rather than after it. The loop below calls
            # Test-StyleResolved -- a filesystem probe -- once per style, and the
            # idle slice runs roughly 20 times a second: measured at 8.8 ms per
            # full scan over 17 styles, that was ~176 ms of work per second spent
            # computing a value the very next line threw away, on every terminal
            # that is not Windows Terminal.
            if (-not $useSettingsFile) { Start-Sleep -Milliseconds 50; return }

            $nextPrebuild = -1
            for ($j = 0; $j -lt $styles.Count; $j++) {
                if ($mergedCache.ContainsKey($j)) { continue }
                if (-not (Test-StyleResolved -StyleDir $styles[$j].FullName)) { continue }
                $nextPrebuild = $j
                break
            }
            if ($nextPrebuild -ge 0) {
                $pp = ConvertFrom-WTJson $originalJson
                $pp = Merge-StyleIntoSettings -Settings $pp -StyleDir $styles[$nextPrebuild].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $mergedCache[$nextPrebuild] = $pp | ConvertTo-Json -Depth 100
            } else {
                Start-Sleep -Milliseconds 50
            }
        }

        # Real-console input adapter -- the one seam not under automated test.
        # Contract: the engine's switch dispatches on string key names
        # ('UpArrow'/'DownArrow'/'Enter'/'Escape'); [Console]::ReadKey($true).Key
        # is a [ConsoleKey] that PowerShell's switch matches by string. Preserve
        # that .Key shape if this adapter ever changes.
        $readKey = { if ([Console]::KeyAvailable) { [Console]::ReadKey($true) } else { $null } }

        $result = Invoke-StylePickerLoop -StyleCount $styles.Count -StartIndex $idx `
            -ReadKey $readKey -OnPreview $applyTheme -OnRevert $onRevert `
            -OnDraw $drawMenu -OnRetint $onRetint -OnIdle $onIdle

        if ($result.Outcome -eq 'cancelled') {
            Clear-Host
            Write-Host "Reverted." -ForegroundColor Yellow
            return
        }

        $idx       = $result.Index
        $confirmed = $true

        # Confirmed -- maybe install profile.ps1
        $selectedStyle = $styles[$idx]
        $styleProfile  = Join-Path $selectedStyle.FullName 'profile.ps1'

        # "Is the target a PowerShell profile?" is a Windows Terminal question:
        # it decides whether writing a PowerShell prompt into that WT profile
        # makes sense. Off WT there are no profiles to disambiguate -- this shell
        # IS PowerShell, so the prompt always applies.
        $isPwshTarget = $true
        if ($useSettingsFile) {
            $isPwshTarget = $false
            if ($Target -eq 'defaults') {
                $isPwshTarget = $true
            } else {
                $entry = $originalSettings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
                $cmd = "$($entry.commandline)"
                $src = "$($entry.source)"
                if ($src -eq 'Windows.Terminal.PowershellCore' -or
                    $cmd -match '(?i)\bpwsh\.exe\b' -or
                    $cmd -match '(?i)\bpowershell\.exe\b') {
                    $isPwshTarget = $true
                }
            }

            # Same reason as the non-WT arm below, and as Apply-StyleDirect's
            # Windows Terminal path: a style with no profile.ps1 leaves nothing
            # for Get-CurrentStyleName to byte-compare, so without a record
            # `tstyles current` reports no active style right after the picker
            # applied one.
            Set-CurrentStyleRecord -StyleName $styles[$idx].Name -Kind $termKind
        } else {
            # Record the confirmed style so a new tab comes up in it -- the OSC
            # preview alone would die with this tab.
            Set-CurrentStyleRecord -StyleName $styles[$idx].Name -Kind $termKind

            # ...and stage the zsh/bash side, exactly as Apply-StyleNonWT does.
            # Without this the picker retints the window live but leaves
            # current-style.osc and current-prompt.sh on the PREVIOUS style, so
            # every new zsh/bash tab comes up in the old palette and banner --
            # while `tstyles <name>` on the same terminal gets it right.
            Set-ShellStyleState -StyleName $selectedStyle.Name `
                                -StyleDir $selectedStyle.FullName `
                                -Scheme $schemes[$idx] -KeepPrompt:$KeepPrompt

            # ...and the background image, which is the other half of what
            # Apply-StyleNonWT does. Without this, `tstyles` + Enter on
            # Terminal.app applied colors and prompt, said "Style applied: eva",
            # and stopped -- no profile written, no mention that the style ships
            # a background, no hint -- while `tstyles eva` on the same terminal
            # wrote the profile and told the user how to see it. -NewWindow was
            # declared on the param block and read by the two apply paths only,
            # so `tstyles -NewWindow` was accepted in silence and did nothing:
            # the same defect CHANGELOG records for `tstyles random`, in the last
            # place it survived.
            #
            # The fetch is free here: this terminal reports BackgroundImage, so
            # the prefetch above has already resolved every style's image.
            Publish-StyleBackgroundProfile -StyleName $selectedStyle.Name `
                                           -StyleDir $selectedStyle.FullName `
                                           -Scheme $schemes[$idx] `
                                           -Kind $termKind -NewWindow:$NewWindow | Out-Null
        }

        # -KeepPrompt means "this style's colors, my prompt". Copying the
        # style's profile.ps1 over current-style.ps1 is what installs its
        # prompt, so under -KeepPrompt it must not happen -- the direct-apply
        # path has always honoured that (see Apply-StyleDirect); the picker
        # used to overwrite regardless.
        #
        # The guard belongs on the INNER condition, exactly as in
        # Apply-StyleDirect and Apply-StyleNonWT. Hoisting it to the outer `if`
        # would also skip the elseif, leaving the PREVIOUS style's
        # current-style.ps1 in place -- which then gets dot-sourced below and
        # makes Get-CurrentStyleName report the old style. -KeepPrompt's
        # contract is that current-style.ps1 ends up ABSENT, not stale; the
        # record fallback at Get-CurrentStyleName exists because of it.
        if ($isPwshTarget) {
            if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
                Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
            } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
                Remove-Item -LiteralPath $script:TStylesCurrent -Force
            }
        }

        Clear-Host
        Write-Host ""
        Write-Host "  Style applied: " -NoNewline
        Write-Host $selectedStyle.Name -ForegroundColor Green
        Write-Host ""
        if ($pendingUpdate) {
            Write-Host ("  Update available ({0} -> {1}). Run: tstyles update" -f
                        $pendingUpdate.Installed, $pendingUpdate.Remote) -ForegroundColor Yellow
            Write-Host ""
        }

        # Live-reload: dot-source the newly active profile so the title,
        # prompt, banner, and PSReadLine colors update in THIS session
        # without requiring the user to open a new tab. Each theme's
        # profile.ps1 uses `function global:prompt` so the binding escapes
        # this function's scope.
        if (Test-ShouldLiveReloadPrompt -IsPwshTarget $isPwshTarget `
                -ProfilePresent (Test-Path -LiteralPath $script:TStylesCurrent)) {
            . $script:TStylesCurrent
        }
    } finally {
        [Console]::CursorVisible = $true
        # Restore the original window title on cancel / exception. The
        # confirm path already had the selected theme's profile.ps1
        # dot-sourced (which sets its own title), so we only restore when
        # the user didn't confirm.
        if (-not $confirmed) {
            $Host.UI.RawUI.WindowTitle = $originalTitle

            # Ctrl+C, or anything that throws out of the loop, skips the Escape
            # branch entirely -- so the last previewed style stayed applied,
            # with settings.json still holding the preview on Windows Terminal
            # and the preview palette still painted everywhere else. Only the
            # cursor and the title were ever put back. Revert here too, unless
            # Escape already did it.
            if (-not $pickerState.Reverted -and $restoreOriginalLook) {
                try { & $restoreOriginalLook } catch { }
            }
        }
        # Clean up the background prefetch job. If it's still mid-fetch (user
        # picked quickly) the transfer is cut off, and the next
        # Get-StyleBundledBackground call fetches synchronously instead -- which
        # is only true because the job downloads to a .part and renames on
        # completion. Writing to the final name directly would leave a truncated
        # file that every reader accepts as a cache hit.
        if ($prefetchJob) {
            Stop-Job -Job $prefetchJob -ErrorAction SilentlyContinue
            Remove-Job -Job $prefetchJob -Force -ErrorAction SilentlyContinue
        }
    }
}

Set-Alias -Name tstyles -Value Invoke-TerminalStyle -Force

# Tab completion: complete the positional Arg with subcommands + style names.
# Applies to both the function and the tstyles alias (PowerShell extends
# argument completers across aliases automatically).
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = $script:TStylesSubcommands
    # Get-AvailableStyles already unions $DataRoot\styles\ + $ModuleRoot\styles\
    # with user-wins dedup -- single source of truth for what `tstyles <name>`
    # can target.
    $styleNames = @(Get-AvailableStyles | ForEach-Object Name)
    $all = @($subcommands + $styleNames | Sort-Object -Unique)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# One-time data-layout migration for users upgrading from pre-0.2.0.
# Idempotent; gated by a marker file.
Invoke-TerminalStylesStateMigration

# === Auto-load the currently selected style at shell startup ===
# Gated on Test-StyledHost rather than Test-InWindowsTerminal: hosts that cannot
# render a style (a plain pipe, a dumb console) would show a half-themed look --
# banner and prompt glyphs with none of the colors. Every terminal that CAN take
# an OSC palette or a written config qualifies. Module functions import
# regardless of the gate.
#
# $TStylesNoAutoLoad suppresses this block for callers that want the library
# without its shell-startup behaviour -- apply.ps1 dot-sources this file for its
# functions, and re-emitting the CURRENTLY applied style's palette on the way in
# would repaint the terminal with the old style moments before applying the new
# one. Same shape as $TStylesApplyNoRun / $TStylesInstallNoRun.
if (-not $TStylesNoAutoLoad -and (Test-StyledHost) -and (Test-HostOutputVisible)) {

    # Windows Terminal reads its colors from settings.json, which the apply
    # already wrote, so the palette is live before this shell even starts.
    # OSC-driven terminals have no such persistence: the escape sequences only
    # ever touched the tab they were emitted into. Re-emit them here so a new
    # tab/window/split comes up in the applied style instead of the terminal's
    # own default.
    #
    # Skipped on WT to avoid fighting its own scheme, and skipped when the
    # terminal can persist a real config AND we wrote one (that path handles
    # itself). Failures are swallowed inside Write-HostOscPacket -- a missing
    # color is never worth blocking a shell from starting.
    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        try {
            $record = Get-CurrentStyleRecord
            if ($record -and $record.name) {
                $styleDir = Get-StyleDir -StyleName $record.name
                if ($styleDir) {
                    $schemePath = Join-Path $styleDir 'scheme.json'
                    if (Test-Path -LiteralPath $schemePath) {
                        $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                        [void](Invoke-TerminalStyleOscApply -Scheme $scheme)
                    }
                }
            }
        } catch { }
    }

    # Guarded, because this runs on EVERY module import -- which means every new
    # shell tab, and (through the generated shim) every `tstyles` command run
    # from zsh or bash. current-style.ps1 is a file we wrote, but it can still be
    # broken: a style's profile.ps1 with a syntax error, a copy interrupted
    # mid-write, a disk that filled. Unguarded that became a parse error on every
    # new tab AND on every `tstyles` invocation -- including the ones that would
    # have fixed it, since `tstyles <name>` and `tstyles reset` both have to
    # import the module first. A style whose prompt will not load is worth one
    # warning, not a shell that cannot start.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        try {
            . $script:TStylesCurrent
        } catch {
            Write-Warning ("TerminalStyles: could not load the active style's prompt. " +
                           "Run 'tstyles reset' to clear it, or 'tstyles <name>' to apply " +
                           "another. Details: $($_.Exception.Message)")
        }
    }
}
