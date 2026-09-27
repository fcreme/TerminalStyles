# VS Code's integrated terminal: the fourth config writer.
#
# WHAT VS CODE CAN AND CANNOT DO, because the difference decides the whole
# shape of this file. `workbench.colorCustomizations` exposes every colour a
# scheme carries -- terminal.background, terminal.foreground, the cursor, and
# all sixteen terminal.ansi* IDs -- and `terminal.integrated.*` covers the font
# and the cursor shape. There is NO background image: `terminal.background` is
# a solid colour, the extension API has no hook for one, and the request has
# been open since 2016. The extensions that appear to do it rewrite VS Code's
# own CSS on disk, which earns the "installation appears corrupt" warning and
# breaks on every update. So `BackgroundImage` stays $false for this kind and
# Get-UnsupportedStyleField says so on screen -- claiming it would be exactly
# the false promise CLAUDE.md's capability rule exists to prevent.
#
# JSONC, AND WHAT A WRITE COSTS. settings.json is JSON with comments, same as
# Windows Terminal's, so Remove-JsonComment already solves the parse. The write
# is the problem: a parse/serialise round trip drops every comment and all
# formatting, and people hand-maintain this file far more than they do
# settings.json for a terminal. That is a real cost, not a footnote -- see the
# note on Merge-StyleIntoVSCodeSettings. Nothing here writes a file; the
# functions take a parsed object and give one back, which is also what makes
# them testable without going near anyone's real editor.
#
# The shape mirrors lib/wtsettings.ps1 on purpose. Two writers that merge a
# style into a JSONC config should not invent two vocabularies for it.

function Get-VSCodeSettingsPath {
    <#
    .SYNOPSIS
    Where a VS Code variant keeps its user settings.json.

    .DESCRIPTION
    Four families ship the same settings file under different directory names:
    stable, Insiders, VSCodium and the forks (Cursor, Windsurf). They can be
    installed side by side, and a user running Insiders has no settings.json at
    the stable path at all -- so the variant is a parameter, never a guess.

    -Platform / -HomeDir / -AppData are test seams; real callers omit them.
    Returns a path string. It does NOT check the file exists: a variant that is
    installed but never opened has a User directory and no settings.json yet,
    and "not there" is the caller's decision to make, not this function's.

    The answer depends on -Platform and on NOTHING ABOUT THE HOST. Neither of
    the obvious joins gets that right:

      Join-Path goes through the PowerShell provider and resolves the drive, so
      joining onto 'C:\Users\x' throws "a drive with the name 'C' does not
      exist" on macOS and Linux -- which is where the Windows branch gets
      exercised.

      [System.IO.Path]::Combine has no opinion about drives, but it separates
      with the HOST's character. Asked for a macOS path on Windows it returns
      '/Users/x\Library\Application Support\...', which is not a path on either
      system. CI caught exactly that: both Windows legs red, both Unix legs
      green, on a function whose output should not have known the difference.

    So the separator comes from the platform being ASKED ABOUT. A parameterised
    answer that varies by machine is not a parameterised answer.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Code', 'Code - Insiders', 'VSCodium', 'Cursor', 'Windsurf')]
        [string]$Variant = 'Code',
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME,
        [string]$AppData  = $env:APPDATA,
        [string]$XdgConfigHome = $env:XDG_CONFIG_HOME
    )

    $sep = Get-PlatformPathSeparator -Platform $Platform

    switch ($Platform) {
        'Windows' {
            # %APPDATA% (Roaming), not LOCALAPPDATA: settings.json is the file
            # that follows a roaming profile, which is why VS Code puts it
            # there and the extension cache elsewhere.
            $root = if ($AppData) { $AppData } else { Join-PlatformPath -Separator $sep -Parts @($HomeDir, 'AppData', 'Roaming') }
            return (Join-PlatformPath -Separator $sep -Parts @($root, $Variant, 'User', 'settings.json'))
        }
        'MacOS' {
            return (Join-PlatformPath -Separator $sep -Parts @($HomeDir, 'Library', 'Application Support', $Variant, 'User', 'settings.json'))
        }
        default {
            # Linux and anything else XDG-shaped.
            #
            # A BOUND -HomeDir suppresses the ambient XDG_CONFIG_HOME, the same
            # way a bound -HomeDir suppresses $env:ZDOTDIR everywhere else in
            # this repo. Reading the live variable through a seam is how the
            # ubuntu leg went red while the other three passed: the runner sets
            # XDG_CONFIG_HOME, so the caller said where home was and the
            # machine answered anyway. Binding both is still honoured -- that
            # caller is asking about an XDG layout on purpose.
            $xdg = $XdgConfigHome
            if ($PSBoundParameters.ContainsKey('HomeDir') -and
                -not $PSBoundParameters.ContainsKey('XdgConfigHome')) { $xdg = $null }
            $cfg = if ($xdg) { $xdg } else { Join-PlatformPath -Separator $sep -Parts @($HomeDir, '.config') }
            return (Join-PlatformPath -Separator $sep -Parts @($cfg, $Variant, 'User', 'settings.json'))
        }
    }
}

function Get-PlatformPathSeparator {
    # The separator a given platform uses, NOT the one this machine uses.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Platform)
    if ($Platform -eq 'Windows') { return '\' }
    return '/'
}

function Join-PlatformPath {
    # Join path parts with an explicit separator. Pure string work: no
    # provider, no drive resolution, no [System.IO.Path], and so no dependence
    # on the host. Trailing separators on a part are trimmed so a HomeDir of
    # 'C:\Users\x\' does not produce a doubled one.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Separator,
        [Parameter(Mandatory)][string[]]$Parts
    )
    return (@($Parts | ForEach-Object { "$_".TrimEnd('\', '/') }) -join $Separator)
}

function Get-VSCodeTerminalColor {
    <#
    .SYNOPSIS
    A scheme's colours as the theme-color IDs VS Code actually reads.

    .DESCRIPTION
    Pure. Returns an ordered hashtable of <theme colour ID> -> <hex>, holding
    only the IDs the scheme has a value for: a scheme with no
    selectionBackground must not write an empty string, which VS Code reports
    as an invalid colour rather than ignoring.

    Note `purple` -> `ansiMagenta`. scheme.json speaks Windows Terminal's
    vocabulary and VS Code speaks ANSI's; this is the one place the two names
    for slot 5 are reconciled, so nothing downstream has to know.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scheme)

    # <scheme field> -> <VS Code theme colour ID>
    $map = [ordered]@{
        'background'          = 'terminal.background'
        'foreground'          = 'terminal.foreground'
        'cursorColor'         = 'terminalCursor.foreground'
        'selectionBackground' = 'terminal.selectionBackground'
        'black'               = 'terminal.ansiBlack'
        'red'                 = 'terminal.ansiRed'
        'green'               = 'terminal.ansiGreen'
        'yellow'              = 'terminal.ansiYellow'
        'blue'                = 'terminal.ansiBlue'
        'purple'              = 'terminal.ansiMagenta'
        'cyan'                = 'terminal.ansiCyan'
        'white'               = 'terminal.ansiWhite'
        'brightBlack'         = 'terminal.ansiBrightBlack'
        'brightRed'           = 'terminal.ansiBrightRed'
        'brightGreen'         = 'terminal.ansiBrightGreen'
        'brightYellow'        = 'terminal.ansiBrightYellow'
        'brightBlue'          = 'terminal.ansiBrightBlue'
        'brightPurple'        = 'terminal.ansiBrightMagenta'
        'brightCyan'          = 'terminal.ansiBrightCyan'
        'brightWhite'         = 'terminal.ansiBrightWhite'
    }

    $out = [ordered]@{}
    foreach ($field in $map.Keys) {
        $value = $null
        if ($Scheme.PSObject.Properties[$field]) { $value = $Scheme.$field }
        if ($value -is [string] -and $value.Trim()) { $out[$map[$field]] = $value }
    }
    return $out
}

function Get-VSCodeCursorStyle {
    <#
    .SYNOPSIS
    A theme.json cursorShape as terminal.integrated.cursorStyle.

    .DESCRIPTION
    Pure. VS Code takes exactly three: block, line, underline. Windows
    Terminal has five, so two of them have no exact answer and are mapped to
    the nearest shape rather than dropped -- an unset cursorStyle leaves the
    user's own, which is a different style's cursor, not this one's.
    Returns $null for a shape this does not know, which the caller treats as
    "write nothing".
    #>
    [CmdletBinding()]
    param([string]$CursorShape)

    switch ("$CursorShape".ToLowerInvariant()) {
        'filledbox'  { return 'block' }
        'emptybox'   { return 'block' }      # VS Code has no hollow cursor.
        'bar'        { return 'line' }
        'underscore' { return 'underline' }
        'vintage'    { return 'underline' }  # WT's vintage is a filled underscore.
        default      { return $null }
    }
}

function Get-VSCodeFontWeight {
    <#
    .SYNOPSIS
    A theme.json font weight as terminal.integrated.fontWeight.

    .DESCRIPTION
    Pure. VS Code takes 'normal', 'bold', or a number 1-1000. Windows Terminal
    takes CSS-style names, and the ones that are not normal/bold have to become
    numbers or VS Code rejects the whole setting. Returns $null for a weight
    this does not know.
    #>
    [CmdletBinding()]
    param([string]$Weight)

    switch ("$Weight".ToLowerInvariant()) {
        'thin'       { return 100 }
        'extra-light' { return 200 }
        'light'      { return 300 }
        'normal'     { return 'normal' }
        'medium'     { return 500 }
        'semi-bold'  { return 600 }
        'bold'       { return 'bold' }
        'extra-bold' { return 800 }
        'black'      { return 900 }
        default      { return $null }
    }
}

function Set-JsonMember {
    # Set a property on a PSCustomObject whether or not it is already there.
    # ConvertFrom-Json gives PSCustomObject on every engine this ships to
    # (-AsHashtable is pwsh-only), so this is the one way to write a key.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties[$Name].Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-VSCodeStyleSetting {
    <#
    .SYNOPSIS
    Everything a style asks VS Code for, as flat <setting key> -> <value>.

    .DESCRIPTION
    Pure, and deliberately the ONLY place that decides what a style means for
    VS Code. Both the merge and the removal read it, so "what did we write"
    and "what should we take back" cannot drift into two answers -- the defect
    shape CLAUDE.md warns about, and the one that had a registration list and a
    removal list disagreeing here before.

    The terminal colours are returned nested under 'workbench.colorCustomizations'
    because that is how they sit in the file; everything else is flat.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

    $enc = [System.Text.UTF8Encoding]::new($false)
    $scheme = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'scheme.json'), $enc) | ConvertFrom-Json
    $theme = $null
    $themePath = Join-Path $StyleDir 'theme.json'
    if (Test-Path -LiteralPath $themePath) {
        try { $theme = [System.IO.File]::ReadAllText($themePath, $enc) | ConvertFrom-Json } catch { }
    }

    $flat = [ordered]@{}
    if ($theme) {
        if ($theme.font -and $theme.font.face) {
            $flat['terminal.integrated.fontFamily'] = $theme.font.face
        }
        if ($theme.font -and $theme.font.size) {
            $flat['terminal.integrated.fontSize'] = $theme.font.size
        }
        if ($theme.font -and $theme.font.weight) {
            $w = Get-VSCodeFontWeight -Weight $theme.font.weight
            if ($null -ne $w) { $flat['terminal.integrated.fontWeight'] = $w }
        }
        $cursor = Get-VSCodeCursorStyle -CursorShape $theme.cursorShape
        if ($cursor) { $flat['terminal.integrated.cursorStyle'] = $cursor }
    }

    return [ordered]@{
        Colors   = (Get-VSCodeTerminalColor -Scheme $scheme)
        Settings = $flat
    }
}

function Merge-StyleIntoVSCodeSettings {
    <#
    .SYNOPSIS
    Merge a style into a parsed settings.json object. Returns the object.

    .DESCRIPTION
    Takes what ConvertFrom-Json gave and gives it back merged. It writes no
    file, which is what lets a test drive it without going near a real editor
    -- and it is the caller's job to take the first-touch backup before
    serialising, because a round trip through ConvertTo-Json DROPS EVERY
    COMMENT AND ALL FORMATTING in the file. settings.json is hand-maintained
    far more often than a terminal's config is, so that cost lands on more
    people here than it does in lib/wtsettings.ps1. Preserving comments would
    mean editing the text in place rather than reparsing it, and this
    prototype does not.

    What it will NOT touch:
      - any colour customisation that is not one of the terminal IDs a style
        sets, so an editor or statusBar override the user made survives
      - any setting outside terminal.integrated.*
      - any terminal.integrated.* key a style has no opinion about

    A style with no font block leaves the font alone rather than resetting it
    to a default: "this style does not say" and "this style says default" are
    different, and only one of them is true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$StyleDir
    )

    $plan = Get-VSCodeStyleSetting -StyleDir $StyleDir

    if ($plan.Colors.Count -gt 0) {
        $custom = $null
        if ($Settings.PSObject.Properties['workbench.colorCustomizations']) {
            $custom = $Settings.'workbench.colorCustomizations'
        }
        if (-not $custom) { $custom = [pscustomobject]@{} }
        foreach ($id in $plan.Colors.Keys) {
            Set-JsonMember -Object $custom -Name $id -Value $plan.Colors[$id]
        }
        Set-JsonMember -Object $Settings -Name 'workbench.colorCustomizations' -Value $custom
    }

    foreach ($key in $plan.Settings.Keys) {
        Set-JsonMember -Object $Settings -Name $key -Value $plan.Settings[$key]
    }

    return $Settings
}

function Remove-StyleFromVSCodeSettings {
    <#
    .SYNOPSIS
    Take a style back out of a parsed settings.json object.

    .DESCRIPTION
    The other half of the merge, and written against the same plan so the two
    cannot describe different key sets.

    It removes a key only when the value still matches what the style put
    there. A user who changed terminal.ansiRed by hand after applying a style
    meant it, and reset is not entitled to that edit -- "remove what an apply
    put there, leave the user's own settings alone" is the rule the Windows
    Terminal reset already states in those words.

    `workbench.colorCustomizations` is deleted outright if emptying it leaves
    nothing, rather than leaving `{}` behind: an orphan object in a config we
    were asked to clean out is the same defect as an orphan colour scheme.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$StyleDir
    )

    $plan = Get-VSCodeStyleSetting -StyleDir $StyleDir

    if ($Settings.PSObject.Properties['workbench.colorCustomizations']) {
        $custom = $Settings.'workbench.colorCustomizations'
        if ($custom) {
            foreach ($id in $plan.Colors.Keys) {
                $prop = $custom.PSObject.Properties[$id]
                if ($prop -and $prop.Value -eq $plan.Colors[$id]) {
                    $custom.PSObject.Properties.Remove($id)
                }
            }
            if (@($custom.PSObject.Properties).Count -eq 0) {
                $Settings.PSObject.Properties.Remove('workbench.colorCustomizations')
            }
        }
    }

    foreach ($key in $plan.Settings.Keys) {
        $prop = $Settings.PSObject.Properties[$key]
        if ($prop -and $prop.Value -eq $plan.Settings[$key]) {
            $Settings.PSObject.Properties.Remove($key)
        }
    }

    return $Settings
}
