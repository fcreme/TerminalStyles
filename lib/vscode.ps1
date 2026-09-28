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
# HOW IT WRITES. Through lib/jsonctext.ps1, which splices the original text
# rather than reparsing and reserialising it. The round trip this replaced
# dropped every comment and all formatting in a file people hand-annotate far
# more than they do a terminal's config. Nothing here touches a file; the
# functions take text and give text back, which is what lets the tests drive
# every hard case as a string.
#
# HOW IT UNDOES. Off a RECORD of what the apply wrote, not off the style.
# For each key the record keeps the literal written and the literal that was
# there before. Two defects follow from not having one:
#
#   - "this key holds our value" is not "this key is ours". Somebody who set
#     terminal.integrated.cursorStyle to block years ago collides with
#     koholint, whose filledBox maps to block; value-matching deletes their
#     setting and calls it cleanup.
#   - a reset that rebuilds the key list from the style cannot run once the
#     style is gone. `tstyles delete koholint` then reset used to strand
#     twenty colour keys with nothing able to name them.
#
# UNITS. Windows Terminal's font.size is POINTS, VS Code's
# terminal.integrated.fontSize is PIXELS. See ConvertTo-VSCodePixelSize.

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

function Get-VSCodeVariant {
    <#
    .SYNOPSIS
    Which VS Code-family editor this terminal belongs to, or $null if unsure.

    .DESCRIPTION
    Pure. Cursor, Windsurf and VSCodium all set TERM_PROGRAM=vscode in their
    integrated terminals, so Get-TerminalKind's 'VSCode' says WHICH FAMILY and
    cannot say which application. Defaulting that to stable VS Code writes a
    Cursor user's style into ~/Library/Application Support/Code/User/settings.json
    -- creating that file for an editor they may not have installed -- while the
    terminal they are looking at does not change and the command reports
    success. The same bug has been filed against other tools that guessed here
    (anthropics/claude-code#33454).

    The evidence is the application path VS Code's own git integration exports:
    VSCODE_GIT_ASKPASS_NODE, or GIT_ASKPASS. A fork ships that from its own
    install directory, so the path carries the application name.

    Matching is by PATH SEGMENT, not substring, and an ambiguous answer is no
    answer:

      - each segment is compared whole (with a trailing .app removed) against
        the known names. A substring match would read /Users/cursor/... as
        Cursor for somebody whose username is cursor.
      - if the segments name exactly one variant, that is the answer.
      - if they name none, or more than one, the answer is $null. A caller
        that cannot tell which editor it is in must refuse, not guess: writing
        the wrong application's settings file and reporting success is worse
        than doing nothing, and the user has no reason to look for it.

    -AskpassNode / -GitAskpass are test seams; real callers omit them.
    #>
    [CmdletBinding()]
    param(
        [string]$AskpassNode = $env:VSCODE_GIT_ASKPASS_NODE,
        [string]$GitAskpass  = $env:GIT_ASKPASS
    )

    # <lowercased path segment> -> <the -Variant name Get-VSCodeSettingsPath takes>
    $known = @{
        'cursor'                     = 'Cursor'
        'windsurf'                   = 'Windsurf'
        'vscodium'                   = 'VSCodium'
        'codium'                     = 'VSCodium'
        'code - insiders'            = 'Code - Insiders'
        'visual studio code - insiders' = 'Code - Insiders'
        'code-insiders'              = 'Code - Insiders'
        'visual studio code'         = 'Code'
        'code'                       = 'Code'
    }

    $seen = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($AskpassNode, $GitAskpass)) {
        if (-not $candidate) { continue }
        foreach ($segment in ($candidate -split '[\\/]')) {
            if (-not $segment) { continue }
            $name = $segment
            if ($name.Length -gt 4 -and $name.Substring($name.Length - 4) -eq '.app') {
                $name = $name.Substring(0, $name.Length - 4)
            }
            $name = $name.ToLowerInvariant()
            if ($known.ContainsKey($name)) {
                $variant = $known[$name]
                if (-not $seen.Contains($variant)) { $seen.Add($variant) }
            }
        }
    }

    if ($seen.Count -eq 1) { return $seen[0] }
    return $null
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

function ConvertTo-VSCodePixelSize {
    <#
    .SYNOPSIS
    A Windows Terminal font size (POINTS) as a VS Code font size (PIXELS).

    .DESCRIPTION
    Pure, and the reason it exists is that the two are not the same unit and
    nothing said so. Windows Terminal documents `font.size` as "the profile's
    font size in points"; VS Code documents `terminal.integrated.fontSize` as
    the size in pixels. Copying the number across writes a terminal about a
    quarter smaller than the style asks for -- 11pt is 14.7px, not 11px -- on
    every bundled style, which makes it the normal outcome rather than an edge
    case.

    96 CSS pixels to the inch, 72 points to the inch, so the ratio is 4/3.

    Rounds AWAY FROM ZERO, not with [Math]::Round's default. That default is
    banker's rounding: [Math]::Round(14.5) is 14, not 15, which would quietly
    shrink every half-point size by one pixel.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$PointSize)

    if ($PointSize -le 0) { return 0 }
    return [int][Math]::Round(($PointSize * 4.0 / 3.0), [System.MidpointRounding]::AwayFromZero)
}

function Get-VSCodeStylePlan {
    <#
    .SYNOPSIS
    Everything a style asks VS Code for, as a flat list of path/value entries.

    .DESCRIPTION
    Pure, and the ONE place that decides what a style means for VS Code. The
    apply reads it to write, and the apply's RECORD is what the reset reads --
    so the two halves cannot drift into different opinions about which keys are
    involved.

    Each entry is @{ Path = <string[]>; Value = <object> }. Path is an array
    because VS Code keys contain dots: "terminal.integrated.fontSize" is one
    top-level key, and "terminal.background" is one key nested inside
    "workbench.colorCustomizations". Nothing here ever splits a string on '.'.

    A key the style has no opinion about is omitted rather than defaulted: "this
    style does not say" and "this style says the default" are different claims
    and only one of them is true.
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

    $entries = [System.Collections.Generic.List[object]]::new()

    $colors = Get-VSCodeTerminalColor -Scheme $scheme
    foreach ($id in $colors.Keys) {
        $entries.Add(@{ Path = @('workbench.colorCustomizations', $id); Value = $colors[$id] })
    }

    if ($theme) {
        if ($theme.font -and $theme.font.face) {
            $entries.Add(@{ Path = @('terminal.integrated.fontFamily'); Value = $theme.font.face })
        }
        if ($theme.font -and $theme.font.size) {
            $entries.Add(@{ Path = @('terminal.integrated.fontSize')
                            Value = (ConvertTo-VSCodePixelSize -PointSize ([double]$theme.font.size)) })
        }
        if ($theme.font -and $theme.font.weight) {
            $w = Get-VSCodeFontWeight -Weight $theme.font.weight
            if ($null -ne $w) { $entries.Add(@{ Path = @('terminal.integrated.fontWeight'); Value = $w }) }
        }
        $cursor = Get-VSCodeCursorStyle -CursorShape $theme.cursorShape
        if ($cursor) { $entries.Add(@{ Path = @('terminal.integrated.cursorStyle'); Value = $cursor }) }
    }

    return ,$entries.ToArray()
}

function Invoke-VSCodeStyleApply {
    <#
    .SYNOPSIS
    Apply a style to settings.json TEXT. Returns @{ Text; Record; Changed; Status }.

    .DESCRIPTION
    Pure: text in, text out, no file touched. Every write goes through
    lib/jsonctext.ps1, so comments and formatting survive.

    The RECORD is the point. For every key it writes, it keeps the literal it
    wrote and the literal that was there BEFORE -- or $null when the key was
    absent. That record, not the style, is what a later reset reads.

    Two things follow from that, and both were defects without it:

      - Reset can tell OUR key from a key that merely holds our value. A user
        who set "terminal.integrated.cursorStyle": "block" years ago collides
        with koholint, whose filledBox maps to block; value-matching deletes
        their setting and calls it cleanup.
      - Reset does not need the style any more. `tstyles delete koholint`
        followed by a reset used to leave twenty colour keys stranded with no
        command able to name them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$StyleDir,
        [string]$StyleName
    )

    $plan = Get-VSCodeStylePlan -StyleDir $StyleDir
    $current = $Text
    $wrote = [System.Collections.Generic.List[object]]::new()
    $created = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $plan) {
        # A nested key needs its parent object to exist. Creating it is
        # recorded, so a reset that empties it again can take it away rather
        # than leaving an empty block behind.
        if ($entry.Path.Count -gt 1) {
            $parentPath = $entry.Path[0..($entry.Path.Count - 2)]
            if ($null -eq (Get-JsoncValueLiteral -Text $current -Path $parentPath)) {
                $mk = Set-JsoncLiteral -Text $current -Path $parentPath -Literal '{}'
                if (-not $mk.Changed) {
                    return @{ Text = $Text; Record = $null; Changed = $false; Status = $mk.Status }
                }
                $current = $mk.Text
                $created.Add($parentPath)
            }
        }

        $had = Get-JsoncValueLiteral -Text $current -Path $entry.Path
        $literal = ConvertTo-JsoncLiteral -Value $entry.Value
        $r = Set-JsoncLiteral -Text $current -Path $entry.Path -Literal $literal
        if ($r.Status -eq 'rootnotobject' -or $r.Status -eq 'parentnotobject' -or
            $r.Status -eq 'parentmissing' -or $r.Status -eq 'unterminated') {
            return @{ Text = $Text; Record = $null; Changed = $false; Status = $r.Status }
        }
        $current = $r.Text
        $wrote.Add(@{ Path = $entry.Path; Literal = $literal; Had = $had })
    }

    $record = @{
        Style          = $StyleName
        Wrote          = $wrote.ToArray()
        CreatedParents = $created.ToArray()
    }
    return @{ Text = $current; Record = $record; Changed = ($current -cne $Text); Status = 'applied' }
}

function Invoke-VSCodeStyleReset {
    <#
    .SYNOPSIS
    Undo an apply, using its record. Returns @{ Text; Restored; Removed; Kept; Status }.

    .DESCRIPTION
    Pure. Walks the record and, for each key we wrote:

      - the value is no longer the literal we wrote  -> KEPT, untouched. The
        user changed it after we did, and that edit is theirs. It is reported,
        not silently skipped: "I left it because it looks like yours" must not
        collapse into "there was nothing to do", which CLAUDE.md names as a
        defect this repo has already shipped once.
      - there was a value before we wrote            -> RESTORED to it, exactly
        as it was, byte for byte. Not deleted: the user had a setting and we
        overwrote it, so putting it back is the undo. Deleting it would be a
        second, uninvited change.
      - there was no key before                      -> REMOVED.

    Comparison is ORDINAL (-cne). '#F5F5F5' is the same colour as '#f5f5f5' and
    is not the same text; if the bytes differ, something other than us wrote
    them, and the safe reading of that is "leave it alone".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowNull()]$Record
    )

    if (-not $Record -or -not $Record.Wrote) {
        return @{ Text = $Text; Restored = @(); Removed = @(); Kept = @(); Status = 'norecord' }
    }

    $current = $Text
    $restored = [System.Collections.Generic.List[string]]::new()
    $removed  = [System.Collections.Generic.List[string]]::new()
    $kept     = [System.Collections.Generic.List[string]]::new()

    foreach ($w in $Record.Wrote) {
        $name = ($w.Path -join '/')
        $now = Get-JsoncValueLiteral -Text $current -Path $w.Path
        if ($null -eq $now) { continue }                 # already gone; nothing to undo
        if ($now -cne $w.Literal) { $kept.Add($name); continue }

        if ($null -eq $w.Had) {
            $r = Remove-JsoncValue -Text $current -Path $w.Path
            if ($r.Changed) { $current = $r.Text; $removed.Add($name) }
        } else {
            $r = Set-JsoncLiteral -Text $current -Path $w.Path -Literal $w.Had
            if ($r.Changed) { $current = $r.Text; $restored.Add($name) }
        }
    }

    # A parent object this apply created, and which is empty again, goes too --
    # an orphan {} left in a config we were asked to clean out is the same
    # defect as an orphan colour scheme in Windows Terminal's settings.
    foreach ($parentPath in @($Record.CreatedParents)) {
        if (-not $parentPath) { continue }
        $tokens = Get-JsoncToken -Text $current
        $found = Resolve-JsoncPath -Text $current -Tokens $tokens -Path $parentPath
        if (-not $found.Member -or $found.Member.ValueOpen -lt 0) { continue }
        # NOT @(...) around this call. Get-JsoncObjectMember returns ,$arr to
        # stop a one-member object unrolling into a bare hashtable -- and a
        # comma-wrapped return put back inside @() is an array of ONE, whatever
        # it holds. Wrapping it here reported an empty object as having one
        # member, so the emptied colour block was never taken away.
        $members = Get-JsoncObjectMember -Text $current -Tokens $tokens -OpenIndex $found.Member.ValueOpen
        if (@($members).Count -eq 0 -or $null -eq $members -or $members.Count -eq 0) {
            $r = Remove-JsoncValue -Text $current -Path $parentPath
            if ($r.Changed) { $current = $r.Text; $removed.Add(($parentPath -join '/')) }
        }
    }

    return @{
        Text     = $current
        Restored = $restored.ToArray()
        Removed  = $removed.ToArray()
        Kept     = $kept.ToArray()
        Status   = 'reset'
    }
}
