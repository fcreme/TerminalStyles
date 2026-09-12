# wtsettings.ps1 -- reading, merging and writing Windows Terminal's settings.json.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# One of exactly two config writers in the project (the other is
# New-AppleTerminalProfile in terminals.ps1); everything else is escape
# sequences. Three concerns live here and each has a sharp edge:
#
#   JSONC     -- Windows Terminal ships settings.json with comments and trailing
#                commas, which Windows PowerShell 5.1's ConvertFrom-Json rejects.
#                Hand-written string state machines strip them.
#   Merging   -- Merge-StyleIntoSettings decides what a style may change and,
#                via Test-ManagedBackgroundPath, whose background it is allowed
#                to clear.
#   Writing   -- atomic replace through a sibling temp file, at depth 100,
#                because the default depth silently stringifies a deep file.

function Remove-JsonComment {
    # Strip // line comments and /* */ block comments from a JSON/JSONC string,
    # leaving comment-like sequences INSIDE string literals (URLs, globs, paths)
    # intact. Windows Terminal's default settings.json ships with // comments,
    # which Windows PowerShell 5.1's ConvertFrom-Json rejects; this normalizes the
    # text so 5.1 and pwsh 7 parse identically. Round-tripping back through
    # ConvertTo-Json drops comments anyway, so stripping costs no fidelity.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $n) {
            $next = $Text[$i + 1]
            if ($next -eq '/') {
                # Line comment: skip to (but keep) the newline.
                $i += 2
                while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($next -eq '*') {
                # Block comment: skip through the closing */.
                $i += 2
                while ($i -lt $n -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function Remove-JsonTrailingComma {
    # Drop trailing commas (a ',' whose next non-whitespace char is '}' or ']')
    # OUTSIDE string literals. Windows Terminal and hand edits leave these; pwsh 7
    # tolerates them but Windows PowerShell 5.1's ConvertFrom-Json rejects them
    # with "extra trailing ','", crashing every mutating command. Commas inside
    # string values (e.g. "a,b") are preserved. Run AFTER Remove-JsonComment so a
    # comment between the comma and the bracket can't hide the trailing comma.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq ',') {
            # Peek past whitespace: a comma immediately preceding } or ] is trailing.
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $n -and ($Text[$j] -eq '}' -or $Text[$j] -eq ']')) {
                $i++   # skip the comma; leave the whitespace/bracket intact
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function ConvertFrom-WTJson {
    # Parse a Windows Terminal settings.json string, tolerating the // and /* */
    # comments and trailing commas WT writes by default. On Windows PowerShell 5.1
    # ConvertFrom-Json rejects both outright, so a fresh WT install (or a hand edit)
    # would otherwise abort every mutating command with a raw parse error. Strips
    # comments first, then trailing commas, then parses; throws one actionable
    # message if the text still isn't valid JSON.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $clean = Remove-JsonComment -Text $Json
    $clean = Remove-JsonTrailingComma -Text $clean
    try {
        $clean | ConvertFrom-Json
    } catch {
        throw ("TerminalStyles: could not parse Windows Terminal settings.json. " +
               "On Windows PowerShell 5.1, JSON comments other than // and /* */ are not supported -- " +
               "open WT Settings and Save once, or remove the offending text. " +
               "Underlying error: $($_.Exception.Message)")
    }
}

function Test-ManagedBackgroundPath {
    # True when a profile's backgroundImage points at a file TerminalStyles put
    # there itself: a bundled styles\<name>\background.* under the module root,
    # or a lazily-fetched copy under the data root's cache\. Anything else --
    # the user's own image, or Windows Terminal keywords like
    # 'desktopWallpaper' -- is theirs, and the merge leaves it alone.
    #
    # This is what lets a bundle-less style clear the PREVIOUS style's
    # background without also clobbering a background the user chose.
    #
    # It is the ownership proof for a DELETE from a file the user owns, so it
    # says "ours" only for an ABSOLUTE path under one of those roots -- see the
    # guard below for the other shapes Windows Terminal accepts here.
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    # Windows Terminal accepts more than absolute paths here: the keyword
    # 'desktopWallpaper', a relative path, and environment-variable forms like
    # '%USERPROFILE%\Pictures\bg.png'. None of those is a path this module could
    # have written -- every background it writes is Join-Path'd onto an absolute
    # $script:TStylesModuleRoot or $script:TStylesDataRoot -- so all of them are
    # the user's, and saying so here is what keeps them.
    #
    # Saying so is also the only safe answer, because [Path]::GetFullPath below
    # resolves a non-absolute value against the PROCESS working directory
    # ([Environment]::CurrentDirectory, which Set-Location does NOT move -- a
    # child pwsh inherits it from the parent's location instead). Launch pwsh
    # inside the clone, the data root, or a ...\Modules\TerminalStyles parent --
    # `cd TerminalStyles; pwsh -File .\apply.ps1 ...` does exactly that -- and
    # 'desktopWallpaper' normalises to <cwd>\desktopWallpaper, lands under a
    # root, and the user's own background is stripped by the guard that exists
    # to protect it.
    if (-not [System.IO.Path]::IsPathRooted($Path)) { return $false }
    # Rooted is not quite enough on Windows: 'C:bg.png' carries a drive but no
    # separator, so it resolves through THAT DRIVE's current directory and is
    # CWD-dependent in the same way. [Path]::IsPathFullyQualified would rule out
    # both shapes in one call, but it is .NET Core only and CI runs Windows
    # PowerShell 5.1 on .NET Framework. On Unix nothing reaches this line but a
    # leading '/', which cannot match.
    if ($Path -match '^[A-Za-z]:(?![\\/])') { return $false }

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($script:TStylesModuleRoot, $script:TStylesDataRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($r)) { $roots.Add($r) }
    }
    # PSResourceGet installs each version to its own sibling dir
    # (...\Modules\TerminalStyles\<version>\), so a background written by an
    # earlier version sits OUTSIDE the current module root. Treat the whole
    # ...\Modules\TerminalStyles\ tree as ours -- but only when the parent is
    # literally named TerminalStyles, so this can't swallow a neighbouring
    # module's files.
    $parent = Split-Path $script:TStylesModuleRoot -Parent
    if ($parent -and (Split-Path $parent -Leaf) -eq 'TerminalStyles') {
        $roots.Add($parent)
    }

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        try {
            # GetFullPath normalises separators/casing-insensitive comparison and
            # resolves any '..'; it does not require the file to exist. Only
            # absolute paths get this far -- the guard above rejected everything
            # whose resolution would depend on the process working directory.
            $full     = [System.IO.Path]::GetFullPath($Path)
            $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') +
                        [System.IO.Path]::DirectorySeparatorChar
        } catch {
            continue   # unparseable path (invalid chars) -- treat as not ours
        }
        # Compare against the root WITH a trailing separator so a sibling like
        # 'TerminalStylesEvil\x.gif' can't match the 'TerminalStyles' root.
        if ($full.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-StyleSettingsPayload {
    <#
    .SYNOPSIS
    Does this style have anything to write into settings.json?

    .DESCRIPTION
    The style half of the rule the -Target guard covers for profiles: find out
    BEFORE touching the user's file whether the operation can do anything.

    Merge-StyleIntoSettings returns the settings object UNTOUCHED for a style
    with no theme.json -- correctly, because a colour scheme is only reachable
    through a profile's colorScheme key, which theme.json carries, so writing
    the scheme anyway would strand it where Reset can never remove it. But
    every caller then wrote the returned object regardless, and that write is
    not a no-op: re-serializing what ConvertFrom-WTJson parsed drops every //
    and /* */ comment the user wrote. So applying a scheme-only style destroyed
    the comments in settings.json, applied nothing, and reported "Style
    applied" in green.

    A style with scheme.json and no theme.json is LEGAL -- README documents
    theme.json as optional, and off Windows Terminal scheme.json is the whole
    style -- so this is not an error, it is "nothing for THIS writer to do".
    A missing scheme.json is different: the directory changed under us, and
    the caller should say so rather than throw from inside the merge.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

    if (-not (Test-Path -LiteralPath (Join-Path $StyleDir 'scheme.json'))) {
        return [pscustomobject]@{ Ok = $false; Missing = 'scheme.json' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $StyleDir 'theme.json'))) {
        return [pscustomobject]@{ Ok = $false; Missing = 'theme.json' }
    }
    return [pscustomobject]@{ Ok = $true; Missing = $null }
}

function Get-WTProfileShape {
    <#
    .SYNOPSIS
    What `profiles` actually is in this settings.json, and what a -Target may name.

    .DESCRIPTION
    Windows Terminal writes `"profiles": { "defaults": {...}, "list": [...] }`
    and every read here assumed it. Files in the wild are not always that shape:
    a hand-minimised settings.json can have no `profiles` key at all,
    `"profiles": null` parses to nothing, an interrupted or truncated write
    leaves a zero-byte file (so $Settings ITSELF is $null), and the legacy flat
    form `"profiles": [ ... ]` is an array.

    HasDefaultsSlot is the load-bearing one, because 'defaults' is the single
    target that does not have to exist yet: an apply creates the block lazily
    with `$Settings.profiles | Add-Member`. That has nothing to add to unless
    `profiles` is a JSON object. Against a missing key or a null it throws "You
    cannot call a method on a null-valued expression"; against the array form it
    is worse and does not throw at all, because Add-Member UNROLLS an array and
    grafts a `defaults` NoteProperty onto every profile IN it -- so the whole
    theme is written inside the first profile, where Windows Terminal ignores it.

    One question, four readers -- Resolve-WTProfileTarget decides Ok and
    Available from it, Merge-StyleIntoSettings and Set-ProfileFont guard their
    lazy creation with it, Reset-StyleDirect enumerates profiles with it.
    Sharing it is the point: the resolver answering "yes, addressable" while the
    merge assumed a shape the file did not have is what spent the user's rolling
    backup and then wrote a comment-stripped settings.json back over their own
    file, under "Style applied" in green.

    ConvertFrom-Json gives a PSCustomObject for `{...}` and an Object[] for
    `[...]`, on pwsh 7 and Windows PowerShell 5.1 alike. The test below asks the
    question structurally rather than by type name -- "is this something a
    member can be hung on", i.e. not null, not a collection, not a scalar --
    because that is the property the lazy creation actually depends on. (Testing
    `-is [pscustomobject]` would be wrong anyway: that accelerator is
    System.Management.Automation.PSObject, which the parsed object is not.)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Settings)

    $profiles = $null
    try { $profiles = $Settings.profiles } catch { $profiles = $null }

    $hasSlot = ($null -ne $profiles -and
                $profiles -isnot [System.Collections.IEnumerable] -and
                $profiles -isnot [System.ValueType])

    $list = @()
    if ($hasSlot) {
        # @($null) is a one-element array holding $null, not an empty one, so a
        # profiles object with no `list` key would otherwise report one profile.
        $list = @($profiles.list | Where-Object { $null -ne $_ })
    } elseif ($profiles -is [array]) {
        $list = @($profiles | Where-Object { $null -ne $_ })
    }

    # What the user may pass to -Target, in the order they should see it.
    # 'defaults' is listed only where it can actually be written: offering it
    # for a file that cannot carry it is the error message promising the one
    # answer that is guaranteed to fail.
    $available = @()
    if ($hasSlot) { $available += 'defaults' }
    $available += @($list | ForEach-Object { $_.name } | Where-Object { $_ })

    return [pscustomobject]@{
        HasDefaultsSlot = $hasSlot
        List            = $list
        Available       = $available
    }
}

function Resolve-WTProfileTarget {
    <#
    .SYNOPSIS
    Resolve a -Target name against settings.json. Reports nothing; decides only.

    .DESCRIPTION
    One rule, four callers. Apply, reset, font and the picker each resolved the
    target themselves, and each did it at a different point relative to the
    damage -- which is how a mistyped -Target came to destroy the rolling
    backup on two of them while erroring cleanly on a third.

    Ok vs Entry is a real distinction, not a convenience. 'defaults' is
    ADDRESSABLE without existing (an apply creates the block lazily) so Ok can be
    $true with no Entry -- and reset has nothing to strip from a profile that is
    not there. Callers that write want Ok; callers that modify an existing entry
    want Entry. Addressable is not unconditional, though: it needs a `profiles`
    object to create the block on, which is Get-WTProfileShape's question.

    Available is for the caller's error message, so every one of them can name
    the same set of real profiles.

    TieBreak says HOW a duplicated name was resolved, because the caller has to
    tell the user: 'Session' when $PreferGuid picked one of the namesakes,
    'First' when it could not and the file order decided. It is $null exactly
    when Ambiguous is $false.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Settings,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TargetName,
        # The session's own profile GUID. Used ONLY to disambiguate between
        # profiles that share $TargetName -- never to override a different
        # -Target the user asked for explicitly. Ambient default with a seam,
        # like Test-InteractiveConsole, so every caller gets it right without
        # threading it through five call sites.
        [AllowEmptyString()][string]$PreferGuid = $env:WT_PROFILE_ID
    )

    $shape     = Get-WTProfileShape -Settings $Settings
    $list      = $shape.List
    $available = $shape.Available

    if ($TargetName -eq 'defaults') {
        # Ok was $true here UNCONDITIONALLY, and that is the whole of the defect
        # this guard closes. Apply-StyleDirect's -Target guard asks this
        # question, so it passed for a settings.json with no `profiles` object;
        # the rolling backup was spent; Merge-StyleIntoSettings then threw "You
        # cannot call a method on a null-valued expression" on the lazy
        # creation. A method call on null aborts the STATEMENT, not the command,
        # so the assignment never happened, $settings still held the
        # parsed-but-unmerged object, and the write on the next line re-
        # serialized it: every JSONC comment in the user's file deleted, "Style
        # applied" in green, and no profile touched. Run it twice and the .bak
        # -- the one copy that still had the comments -- was overwritten with
        # the stripped file. See Get-WTProfileShape for the four shapes.
        $entry = $null
        if ($shape.HasDefaultsSlot -and $Settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $entry = $Settings.profiles.defaults
        }
        return [pscustomobject]@{
            Ok         = $shape.HasDefaultsSlot
            Entry      = $entry
            IsDefaults = $true
            Available  = $available
            Ambiguous  = $false
            TieBreak   = $null
        }
    }

    # NOT $matches: that is an AUTOMATIC variable, rewritten by every -match
    # in the same scope. Correct here only because this function uses none --
    # and one -match added above the reads below would silently replace the
    # profile list with regex capture strings. Measured: a 2-element list
    # became a 1-element list of [String] after a single unrelated -match.
    $named = @($list | Where-Object name -eq $TargetName)

    # Windows Terminal allows two profiles with the SAME name and different
    # GUIDs -- a hand-copied profile, or a dynamic/fragment profile colliding
    # with a manually defined one. Every resolution here was
    # `Select-Object -First 1`, and Get-CurrentWTProfileName finds the session's
    # entry by $env:WT_PROFILE_ID and then returns only its NAME, throwing the
    # GUID away. So `tstyles <style>` in the SECOND of two same-named profiles
    # styled the first one: the user's own window was unchanged, an unrelated
    # profile was silently restyled, "Style applied" printed in green, and
    # -Target could not rescue it because the two are indistinguishable by name.
    # `tstyles reset` then stripped the same wrong profile.
    #
    # The GUID only breaks a tie. If it names a profile whose name is NOT
    # $TargetName, the user asked for a different profile than the one they are
    # sitting in, and that request wins.
    $entry    = $null
    $tieBreak = $null
    if ($named.Count -gt 1) {
        if ($PreferGuid) {
            $entry = $named | Where-Object { $_.guid -eq $PreferGuid } | Select-Object -First 1
        }
        # Recorded HERE, where the choice is actually made. The note the callers
        # print used to assert "Applied to the one this session is running in"
        # on every ambiguous resolution -- false whenever $PreferGuid names a
        # THIRD profile (reset run from an Ubuntu tab, say), which is the
        # ordinary modern-WT shape. Re-deriving it at the call site would be a
        # second copy of this decision, so the decision reports itself.
        $tieBreak = if ($entry) { 'Session' } else { 'First' }
    }
    if (-not $entry) { $entry = $named | Select-Object -First 1 }

    return [pscustomobject]@{
        Ok = [bool]$entry; Entry = $entry; IsDefaults = $false; Available = $available
        # True when the name alone was not enough to identify a profile.
        Ambiguous = ($named.Count -gt 1)
        # 'Session', 'First', or $null when there was no tie to break.
        TieBreak  = $tieBreak
    }
}

function Get-WTTargetNotFoundMessage {
    <#
    .SYNOPSIS
    The one sentence every caller says when Resolve-WTProfileTarget says no.

    .DESCRIPTION
    Three callers wrote this message, two of them identically, and all three
    ended in "Available: " + the list -- which is a dead end when the list is
    EMPTY. That is not a hypothetical shape: it is exactly the settings.json
    that used to be accepted for -Target defaults and then cost the user their
    JSONC comments (no `profiles` key, a null one, a zero-byte file). Refusing
    it is the fix; refusing it with a sentence that stops mid-air would only
    move the confusion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$ResolvedTarget,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TargetName
    )

    $available = @()
    if ($ResolvedTarget) { $available = @($ResolvedTarget.Available) }
    if (-not $available.Count) {
        # "not an object" rather than "empty": `"profiles": {}` IS usable -- the
        # defaults block can be created in it -- so this list names only the
        # shapes that are not.
        return ("Windows Terminal's settings.json has no profile to apply to: its 'profiles' key is " +
                "missing, null, or not an object. Check the file, or let Windows Terminal rewrite it.")
    }
    return "Windows Terminal profile '$TargetName' not found. Available: $($available -join ', ')"
}

function Write-AmbiguousTargetNote {
    <#
    .SYNOPSIS
    Say that a -Target name matched more than one profile, and which one won.

    .DESCRIPTION
    Two Windows Terminal profiles may carry the same `name`, and from outside
    they are indistinguishable: -Target cannot separate them, so a user cannot
    check which one a command chose. Resolve-WTProfileTarget breaks the tie with
    the session's own GUID, which is almost always what was wanted -- and
    "almost always" is worth one line wherever it is acted on.

    It was acted on in five places and said in one. `tstyles <style>` printed
    the note; the picker, `tstyles reset`, `tstyles font` and the standalone
    apply.ps1 resolved the same tie in silence -- and reset is the one that
    matters most, because it strips every field an apply may write (padding,
    opacity, useAcrylic, font.face among them) off whichever namesake it picked
    and then reports "Reset '<name>' to its unstyled default." in green.

    So the note lives here, next to the resolver, and every caller that acts on
    a resolution reads it. $Verb is the caller's own word for what it did, so
    the sentence stays true for a reset as well as an apply.

    The second line is NOT unconditional. It claimed the session's profile every
    time, which is false when the tie could not be broken -- the session is in a
    third profile, or there is no WT_PROFILE_ID at all -- and that is precisely
    the sentence a user reads to decide whether the right profile was hit. The
    resolver records which branch it took; this only reports it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$ResolvedTarget,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TargetName,
        # The caller's verb: 'Applied to', 'Reset', 'Applying to'.
        [string]$Verb = 'Used'
    )

    if (-not $ResolvedTarget -or -not $ResolvedTarget.Ambiguous) { return }

    Write-Host "  Note: more than one profile is named '$TargetName'." -ForegroundColor DarkGray
    if ($ResolvedTarget.TieBreak -eq 'Session') {
        Write-Host ("  {0} the one this session is running in." -f $Verb) -ForegroundColor DarkGray
    } else {
        Write-Host ("  {0} the first one in settings.json, guid {1}." -f
                    $Verb, $ResolvedTarget.Entry.guid) -ForegroundColor DarkGray
    }
}

function Save-SettingsBackup {
    <#
    .SYNOPSIS
    Take the rolling settings.json.bak -- only once the operation is known possible.

    .DESCRIPTION
    Taking this backup is itself DESTRUCTIVE: there is one .bak, and writing it
    consumes the user's undo of their last real apply. So a command that turns
    out to do nothing must not take it.

    That is why -ResolvedTarget is MANDATORY and is checked here. It is not
    defensive typing -- it is the invariant made structural. A caller cannot
    take the backup before resolving the target, because it has nothing to pass
    until it has. `tstyles reset -Target <typo>` and `tstyles font <name>
    -Target <typo>` both used to copy settings.json over the backup and only
    then discover the profile did not exist, printing "nothing to reset" over
    the wreckage of the user's one-line undo.

    Copy-Item rather than a read/write round-trip, so the bytes are preserved
    exactly -- a BOM included.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        # The result of Resolve-WTProfileTarget for the operation about to run.
        [Parameter(Mandatory)][AllowNull()]$ResolvedTarget,
        # The picker and the tuner take this as crash-recovery behind a menu
        # that redraws every frame; announcing it would be noise.
        [switch]$Quiet
    )

    if (-not $ResolvedTarget -or -not $ResolvedTarget.Ok) {
        throw "Save-SettingsBackup called before the target was known to be valid. This is a bug: the backup consumes the user's undo, so it must be taken only once the operation is known to be possible."
    }

    Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force -ErrorAction Stop
    if (-not $Quiet) {
        Write-Host "Backed up settings to: $Path.bak" -ForegroundColor Gray
    }
}

function Merge-StyleIntoSettings {
    param(
        $Settings,
        [string]$StyleDir,
        [string]$TargetName,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided
    )

    $scheme = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    # Resolve / validate the target FIRST. A non-existent named profile must not
    # cause us to inject the color scheme -- that would leave an orphan scheme in
    # settings.json that Reset's cleanup can never remove (no profile references
    # it). 'defaults' is created lazily below, only when there's a theme to write.
    # Through the shared resolver, so the merge writes to the SAME profile every
    # other path resolved -- including the GUID tie-break above. Its own
    # first-match lookup is what actually wrote the style onto the wrong one of
    # two same-named profiles.
    $namedEntry = $null
    if ($TargetName -ne 'defaults') {
        $resolved = Resolve-WTProfileTarget -Settings $Settings -TargetName $TargetName
        if (-not $resolved.Ok) { return $Settings }   # missing named target: leave settings untouched
        $namedEntry = $resolved.Entry
    }

    # Everything that could still make us bail happens BEFORE the scheme is
    # upserted. A scheme is only reachable through a profile's colorScheme key,
    # which lives in theme.json -- so writing the scheme and then discovering
    # there is no theme.json, or no profile entry to write it to, leaves a
    # scheme nothing references. Reset-StyleDirect cleans up the scheme named by
    # the profile it is resetting, so an unreferenced one can never be removed
    # and accumulates in settings.json on every apply.
    #
    # That is precisely the failure the target guard above was added to prevent;
    # the missing-theme.json route into it was left open next to it.
    $themePath = Join-Path $StyleDir 'theme.json'
    if (-not (Test-Path -LiteralPath $themePath)) { return $Settings }
    $theme = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    # The lazy creation, guarded rather than assumed. Add-Member needs a
    # `profiles` OBJECT to add the block to: on a missing key or a null this
    # line threw, and on the legacy flat-array form it unrolled the array and
    # grafted `defaults` onto every profile in it without a word. The resolver
    # now refuses 'defaults' for both shapes, so a caller that went through it
    # never arrives here -- this is the same rule stated where the write
    # happens, for the two callers that merge without resolving first (the
    # picker's preview and the tuner). Falling through to the existing
    # `if (-not $entry)` keeps the no-target contract: settings returned
    # untouched, and no orphan scheme, since the scheme is upserted below.
    $entry = if ($TargetName -eq 'defaults') {
        if ((Get-WTProfileShape -Settings $Settings).HasDefaultsSlot) {
            if (-not $Settings.profiles.PSObject.Properties.Match('defaults').Count) {
                $Settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
            }
            $Settings.profiles.defaults
        }
    } else {
        $namedEntry
    }
    if (-not $entry) { return $Settings }

    if (-not $Settings.PSObject.Properties.Match('schemes').Count) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
    }
    $Settings.schemes = @($Settings.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme

    # Resolve effective background:
    #   1. User passed -BackgroundImage <path>  -> use that
    #   2. User passed -BackgroundImage ""      -> strip (remove fields entirely)
    #   3. Style ships a bundled background.*   -> use that
    #   4. Otherwise                            -> leave user's existing bg alone
    $effectiveBg = $BackgroundImage
    $applyBg = $BackgroundImageProvided
    if (-not $applyBg) {
        $bundled = Get-StyleBundledBackground -StyleDir $StyleDir
        if ($bundled) {
            $effectiveBg = $bundled
            $applyBg = $true
        }
    }

    # Three actions for bg fields:
    #   skip   : don't touch them
    #   remove : strip them from the profile (explicit empty path => disable)
    #   apply  : substitute the placeholder and write all bg fields
    #
    # When the new style ships no background, what happens depends on WHOSE
    # background is currently on the profile. One we wrote for the previously
    # applied style gets cleared -- otherwise it bleeds through and the new
    # style is shown behind the old style's GIF. A background the user set
    # themselves is left alone, which is what the skip is for.
    #
    # "On the profile" has to mean what the profile SHOWS, not what its own
    # entry happens to spell out: Windows Terminal resolves every named profile
    # against profiles.defaults, so an image written there by
    # `tstyles <style> -Target defaults` is live on this profile with nothing on
    # its entry to show for it. Read only the entry -- as this did -- and
    # $existingBg is $null, the ownership test is asked about nothing, the
    # action falls to 'skip', and the next bundle-less style applied to the
    # profile the user is sitting in is drawn behind the previous style's GIF.
    # Asked through the shared resolver rather than reached for directly,
    # because `profiles` is not always an object: against the legacy flat-array
    # form or a missing key, `$Settings.profiles.defaults` is a method call on
    # null. The resolver already answers "what entry does this target name
    # resolve to", for all four shapes, and hands back $null when there is none.
    $inheritedEntry = $null
    if ($TargetName -ne 'defaults') {
        $inheritedEntry = (Resolve-WTProfileTarget -Settings $Settings -TargetName 'defaults').Entry
    }
    $inheritedBg = if ($inheritedEntry -and
                       $inheritedEntry.PSObject.Properties.Match('backgroundImage').Count -gt 0) {
        [string]$inheritedEntry.backgroundImage
    } else { $null }

    # The profile's own key shadows the inherited one, so it is the one that
    # answers "whose background is on screen".
    $existingBg = if ($entry.PSObject.Properties.Match('backgroundImage').Count -gt 0) {
        [string]$entry.backgroundImage
    } else { $inheritedBg }

    $bgAction = if ($applyBg) {
                    if ([string]::IsNullOrEmpty($effectiveBg)) { 'remove' } else { 'apply' }
                }
                elseif (Test-ManagedBackgroundPath -Path $existingBg) { 'remove' }
                else { 'skip' }

    $bgFields = $script:TStylesBgFields

    # 'remove' is driven by what is already ON the profile, not by what the new
    # style's theme.json happens to mention -- and a style that ships no
    # background has no reason to mention background fields at all. Running this
    # inside the property loop below meant the clear only fired for styles whose
    # theme.json named the fields, so switching to one that omitted them left the
    # PREVIOUS style's image showing through the new palette.
    if ($bgAction -eq 'remove') {
        foreach ($bgField in $bgFields) {
            if ($entry.PSObject.Properties.Match($bgField).Count -gt 0) {
                $entry.PSObject.Properties.Remove($bgField)
            }
        }
        # And from profiles.defaults when that is where the image the profile
        # shows actually lives: stripping the entry alone hands the profile
        # straight back to the inherited copy, which is the same bleed one
        # level up. Guarded on the INHERITED value being ours, separately from
        # the decision above -- the entry can carry one of ours over a
        # background the user chose for every profile, and that one is theirs
        # to keep. Only 'remove' reaches here: an 'apply' writes the new
        # style's image onto the entry, where it shadows defaults, so nothing
        # of the old style is visible on this profile and clearing defaults
        # would silently restyle every other profile too.
        if ($inheritedEntry -and (Test-ManagedBackgroundPath -Path $inheritedBg)) {
            foreach ($bgField in $bgFields) {
                if ($inheritedEntry.PSObject.Properties.Match($bgField).Count -gt 0) {
                    $inheritedEntry.PSObject.Properties.Remove($bgField)
                }
            }
        }
    }

    foreach ($prop in $theme.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($name -in $bgFields) {
            # skip: leave the user's own background alone.
            # remove: already stripped above; re-adding it here would undo that.
            if ($bgAction -ne 'apply') { continue }
            if ($name -eq 'backgroundImage' -and $value -eq '{{BACKGROUND_IMAGE}}') {
                $value = $effectiveBg
            }
        }

        if ($entry.PSObject.Properties.Match($name).Count -gt 0) {
            $entry.$name = $value
        } else {
            $entry | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }

    return $Settings
}

function Write-SettingsAtomic {
    # Write settings.json durably: serialize to a sibling temp file, then
    # atomically replace the live file. WriteAllText truncates-then-writes, so a
    # crash/kill or a concurrent reader (Windows Terminal watches settings.json
    # and reloads on change) can observe a half-written/empty file. A same-volume
    # rename is atomic on NTFS, so the live file is only ever the old bytes or the
    # complete new bytes -- never a truncated middle. Falls back to a direct copy
    # if Replace/Move is unsupported (e.g. an odd filesystem). UTF-8, keeping the
    # byte-order mark the live file already had and adding none to a new file.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    # Whether settings.json starts with a BOM is the FILE's property, not this
    # caller's, and the single writer is the only place that can keep it. Every
    # snapshot in the module is taken with [File]::ReadAllText, whose overload
    # builds its StreamReader with detectEncodingFromByteOrderMarks:true no
    # matter which encoding it is handed -- so a leading EF BB BF is consumed as
    # an encoding marker and is simply not in the string. Writing
    # UTF8Encoding($false) unconditionally then dropped it, three bytes at a
    # time, from a file the user owns: the picker's Esc and the tuner's Esc are
    # both documented as restoring the ORIGINAL BYTES (tstyles.ps1 header,
    # README "reverts in-memory to the exact prior bytes"), and both came back
    # shorter than they went in. The rolling .bak is taken with Copy-Item
    # precisely so it keeps every byte, a BOM included -- which left the backup
    # and the live file disagreeing about the header. Sniffing here fixes the
    # preview write, the revert, apply, reset and the font writer in one place;
    # asking at the revert alone would still have lost it on the first preview.
    #
    # A missing, locked or unreadable file falls through to no BOM, which is
    # today's behaviour and the right default for a file we are creating.
    $hadBom = $false
    try {
        if (Test-Path -LiteralPath $Path) {
            $head = [byte[]]::new(3)
            # FileShare::ReadWrite, not OpenRead's FileShare::Read: Windows
            # Terminal watches settings.json and may hold it open, and an
            # exception here would silently cost the BOM on exactly the
            # machines this runs on.
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
                                                [System.IO.FileAccess]::Read,
                                                [System.IO.FileShare]::ReadWrite)
            try { $read = $fs.Read($head, 0, 3) } finally { $fs.Dispose() }
            $hadBom = ($read -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)
        }
    } catch { $hadBom = $false }

    $enc = [System.Text.UTF8Encoding]::new($hadBom)
    $tmp = "$Path.tstmp"
    [System.IO.File]::WriteAllText($tmp, $Json, $enc)
    try {
        if (Test-Path -LiteralPath $Path) {
            # backupFileName = [NullString]::Value: replace without keeping a
            # copy. A bare $null is coerced by PowerShell to '' here, which makes
            # Replace throw "path is empty" on PS7 and silently fall back to the
            # non-atomic in-place write below; [NullString]::Value passes a true
            # null so the atomic same-volume rename actually runs.
            [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        # Best-effort fallback (cross-volume temp, Replace unsupported, etc.).
        # The cleanup is in a finally because the fallback can throw too -- a
        # read-only or locked settings.json fails BOTH the Replace and the
        # WriteAllText, and the exception then escaped past the cleanup line,
        # leaving a .tstmp beside the user's settings.json on every attempt.
        try {
            [System.IO.File]::WriteAllText($Path, $Json, $enc)
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Write-SettingsFile {
    param([string]$Path, $Settings)
    # Depth 100 (the JSON max) rather than 32: a deeply-nested user settings.json
    # over depth 32 is silently stringified (corrupted) by ConvertTo-Json --
    # without warning on Windows PowerShell 5.1.
    $json = $Settings | ConvertTo-Json -Depth 100
    Write-SettingsAtomic -Path $Path -Json $json
}
