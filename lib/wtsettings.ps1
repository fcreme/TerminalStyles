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

function ConvertFrom-JsoncText {
    <#
    .SYNOPSIS
    Parse JSONC -- JSON with // and /* */ comments and trailing commas.

    .DESCRIPTION
    Windows Terminal ships settings.json with both, and Windows PowerShell 5.1's
    ConvertFrom-Json rejects both outright, so a fresh install or a hand edit
    would abort every mutating command with a raw parse error. Strips comments,
    then trailing commas, then parses.

    -SourceName and -Remedy are what the failure says. They exist because this
    was `ConvertFrom-JsoncText` and its one hard-coded message named Windows
    Terminal, its settings.json, and "open WT Settings and Save once" -- three
    claims that are all wrong in front of somebody whose VS Code settings.json
    will not parse, on a Mac, where Windows Terminal does not exist. A message
    is a claim, and this one has a second caller now.

    The Windows PowerShell 5.1 sentence is added only ON 5.1. It explains the
    cause there and is simply untrue anywhere else.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Json,
        [string]$SourceName = 'Windows Terminal settings.json',
        [string]$Remedy = 'open Windows Terminal Settings and Save once, or remove the offending text'
    )

    $clean = Remove-JsonComment -Text $Json
    $clean = Remove-JsonTrailingComma -Text $clean
    try {
        $clean | ConvertFrom-Json
    } catch {
        $why = ''
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $why = 'On Windows PowerShell 5.1, JSON comments other than // and /* */ are not supported. '
        }
        throw ("TerminalStyles: could not parse $SourceName. " + $why +
               "To fix it: $Remedy. " +
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
    not a no-op: re-serializing what ConvertFrom-JsoncText parsed drops every //
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
    form `"profiles": [ ... ]` is an array. Inside an object, `defaults` can be
    missing, `null` (which Windows Terminal loads as a missing block, and which
    a template with an empty key produces), or a value that is not an object.

    HasDefaultsSlot is the load-bearing one, because 'defaults' is the single
    target that does not have to exist yet: an apply creates the block lazily
    with `$Settings.profiles | Add-Member`. That has nothing to add to unless
    `profiles` is a JSON object. Against a missing key or a null it throws "You
    cannot call a method on a null-valued expression"; against the array form it
    is worse and does not throw at all, because Add-Member UNROLLS an array and
    grafts a `defaults` NoteProperty onto every profile IN it -- so the whole
    theme is written inside the first profile, where Windows Terminal ignores it.

    So HasDefaultsSlot means a block exists, or can be created, at
    profiles.defaults: `profiles` is an object and its `defaults` is absent,
    null or an object. It is decided from the VALUE, not the key: deciding from
    `profiles` alone let `"defaults": null` through, the resolver said yes, the
    .bak was spent, and both lazy creations -- which made the block only where
    the key was absent -- wrote into nothing under "Style applied". Defaults is
    the block or $null, so no reader reaches into `profiles` and meets a null
    or a string; DefaultsNotObject says why 'defaults' was refused.

    One question, three readers -- Resolve-WTProfileTarget decides Ok, Entry
    and Available from it, Initialize-WTDefaultsEntry makes the lazy creation
    for Merge-StyleIntoSettings and Set-ProfileFont, and Reset-StyleDirect's
    sweep enumerates Defaults and List.
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

    $isObject = { param($Value)
        $null -ne $Value -and
        $Value -isnot [System.Collections.IEnumerable] -and
        $Value -isnot [System.ValueType]
    }
    $profilesIsObject = & $isObject $profiles

    $hasSlot = $false
    $defaults = $null
    $defaultsNotObject = $false
    if ($profilesIsObject) {
        $value = $null
        if ($profiles.PSObject.Properties.Match('defaults').Count) { $value = $profiles.defaults }
        if ($null -eq $value) {
            $hasSlot = $true
        } elseif (& $isObject $value) {
            $hasSlot = $true
            $defaults = $value
        } else {
            $defaultsNotObject = $true
        }
    }

    $list = @()
    if ($profilesIsObject) {
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
        HasDefaultsSlot   = $hasSlot
        Defaults          = $defaults
        DefaultsNotObject = $defaultsNotObject
        List              = $list
        Available         = $available
    }
}

function Initialize-WTDefaultsEntry {
    <#
    .SYNOPSIS
    The profiles.defaults block to write into, created if it is absent or null.

    .DESCRIPTION
    The one lazy creation. Merge-StyleIntoSettings and Set-ProfileFont each had
    a copy, and both made the block only where the KEY was absent -- so a
    `"defaults": null` passed the shape guard and both wrote into nothing.

    Absent or null means created. A null is replaced where it stands, so
    `defaults` keeps its place before `list` (Add-Member -Force re-adds the
    member at the end). Returns $null for every shape that cannot carry the
    block, which is each caller's existing "no target" answer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Settings)

    $shape = Get-WTProfileShape -Settings $Settings
    if (-not $shape.HasDefaultsSlot) { return $null }
    if ($null -ne $shape.Defaults)   { return $shape.Defaults }
    $block = [pscustomobject]@{}
    if ($Settings.profiles.PSObject.Properties.Match('defaults').Count) {
        $Settings.profiles.defaults = $block
    } else {
        $Settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue $block
    }
    return $block
}

function Test-WTProfileRunsPowerShell {
    <#
    .SYNOPSIS
    Does this Windows Terminal profile start PowerShell? Decides whether an
    apply installs the style's prompt. Pure.

    .DESCRIPTION
    The one copy of the rule, for the module's apply path, the picker and
    apply.ps1. Each used to carry its own, and all three wanted `pwsh.exe` or
    `powershell.exe` somewhere in the commandline, so a profile running `pwsh`,
    which Windows Terminal resolves off PATH, took the colours and never the
    prompt.

    It counts when the PowerShell Core dynamic profile's source says so (that
    profile carries no commandline); when the program the commandline starts is
    pwsh or powershell, with or without .exe and a path; or by that old match,
    kept so every profile it accepted still counts -- `cmd.exe /k pwsh.exe`
    does start PowerShell.

    The program is the quoted part when the commandline opens with a quote.
    When it opens with a path (a drive, `\\` or `%`), it runs to the first
    `.exe` that ends a word, so an unquoted `C:\Program Files\...\pwsh.exe` is
    one program, as Windows resolves it. Otherwise it is the first word: only
    a path is read past a space, or `pwsh -Command C:\x\init.exe a` would be
    taken for init.exe.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Entry)
    if ($null -eq $Entry) { return $false }
    if ("$($Entry.source)" -eq 'Windows.Terminal.PowershellCore') { return $true }
    $cmd = "$($Entry.commandline)".Trim()
    if (-not $cmd) { return $false }
    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        $program = if ($end -lt 0) { $cmd.Substring(1) } else { $cmd.Substring(1, $end - 1) }
    } elseif ($cmd -match '^(?:[A-Za-z]:|\\\\|%)' -and $cmd -match '^(?<p>.*?\.exe)(?=\s|$)') {
        $program = $Matches['p']
    } else {
        $program = ($cmd -split '\s+', 2)[0]
    }
    $leaf = @($program -split '[\\/]')[-1]
    if ($leaf -match '^(?i:pwsh|powershell)(?i:\.exe)?$') { return $true }
    return ($cmd -match '(?i)\bpwsh\.exe\b' -or $cmd -match '(?i)\bpowershell\.exe\b')
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
    object and a `defaults` that is absent, null or an object --
    Get-WTProfileShape's question.

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
        # the stripped file. See Get-WTProfileShape for the shapes.
        #
        # The same failure came back through `"defaults": null`: the guard asked
        # about `profiles`, and both lazy creations asked whether the KEY
        # existed. Ok and Entry now come from the value, through the shape.
        return [pscustomobject]@{
            Ok                = $shape.HasDefaultsSlot
            Entry             = $shape.Defaults
            IsDefaults        = $true
            Available         = $available
            Ambiguous         = $false
            TieBreak          = $null
            DefaultsNotObject = $shape.DefaultsNotObject
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
        # A fact about the file, like Available: carried so the one message
        # function can name why 'defaults' is not on offer.
        DefaultsNotObject = $shape.DefaultsNotObject
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

    A `defaults` that is present but not an object gets its own sentence:
    "not found" is false about a key the user can see, and "'profiles' key is
    missing" is false about a `profiles` object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$ResolvedTarget,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TargetName
    )

    $available = @()
    $defaultsNotObject = $false
    if ($ResolvedTarget) {
        $available = @($ResolvedTarget.Available)
        $defaultsNotObject = [bool]$ResolvedTarget.DefaultsNotObject
    }
    # Concatenated, never passed through -f: the sentences carry {}.
    if ($defaultsNotObject -and $TargetName -eq 'defaults') {
        $msg = "Windows Terminal's settings.json cannot take -Target defaults: its 'defaults' under " +
               "'profiles' is not an object, so there is nothing to write into. Make it {} or remove it."
        if ($available.Count) { $msg += " Available: $($available -join ', ')" }
        return $msg
    }
    if ($defaultsNotObject -and -not $available.Count) {
        return ("Windows Terminal's settings.json has no profile to apply to: it lists none, and its " +
                "'defaults' under 'profiles' is not an object. Make it {} or remove it.")
    }
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
        # The picker, the tuner and the creator take this as crash-recovery
        # behind a menu that redraws every frame; announcing it would be noise.
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

function Get-BackupFailureNote {
    <#
    .SYNOPSIS
    What a caller says when the rolling settings.json.bak could NOT be taken.

    .DESCRIPTION
    One sentence, in one place, for the five commands that roll the one .bak.
    Three of them said nothing at all: the call sat in `try { ... } catch { }`,
    so a Copy-Item that really failed -- measured with the .bak alone unwritable
    while its directory stayed writable, which is what a sync client, an editor
    or an AV scanner holding the file open looks like -- rewrote settings.json
    and left the .bak holding the state from the user's LAST REAL APPLY, with
    not one word on screen. On the success path the same site prints "Backed up
    settings to: <path>", so failure and success differed only by an absence;
    with -Quiet they were byte-identical.

    README teaches that file as the only route back to a colorScheme, a
    font.face or the JSONC comments an apply drops, so "the backup could not be
    taken" and "the backup was taken" must not be the same outcome.

    -InFrame is for the picker and the tuner, whose menus Clear-Host on every
    redraw: a line printed where the failure happened is wiped unread, so theirs
    is phrased as a standing state and painted inside the frame.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Reason,
        [switch]$InFrame
    )

    if ($InFrame) {
        return "  ! settings.json.bak could not be written ($Reason) -- your undo is still the copy the last apply left"
    }
    return "Warning: could not write backup ($Reason); proceeding anyway."
}

function Show-SettingsRestoreFailure {
    <#
    .SYNOPSIS
    What the picker and the tuner print, in place of "Reverted.", when
    settings.json could not be put back the way they found it.

    .DESCRIPTION
    Both put the file back on Esc, an aborted save and in their finally, and
    both printed "Reverted." whether or not that write landed. It now stops at
    the writer's own error, so the exit can say which happened.

    -BackupTaken says the session took settings.json.bak when it opened, so
    that copy is the file as it found it, and this prints the Copy-Item that
    puts it back. Without it, the .bak still holds the last real apply's state,
    and pointing at it would undo more than the session. -Unchecked is for a
    put-back the tuner could not read back afterwards: it cannot say whether
    the file is back. Paths are single-quoted with any ' doubled, so the line
    pastes as it is.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Reason,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][ValidateSet('picker', 'tuner', 'creator')][string]$By,
        [switch]$BackupTaken,
        [switch]$Unchecked
    )

    Write-Host "  $Reason" -ForegroundColor Red
    if ($Unchecked) {
        Write-Host "  settings.json could not be read back, so the $By cannot say whether it is as it" -ForegroundColor Yellow
        Write-Host "  found it." -ForegroundColor Yellow
    } else {
        Write-Host "  settings.json is not back as the $By found it." -ForegroundColor Yellow
    }
    if ($BackupTaken) {
        $quote = { param([string]$s) "'" + $s.Replace("'", "''") + "'" }
        Write-Host "  The copy it took when it opened is settings.json.bak, beside it. To put that back:" -ForegroundColor Yellow
        Write-Host ("    Copy-Item -LiteralPath {0} -Destination {1} -Force" -f
                    (& $quote ($SettingsPath + '.bak')), (& $quote $SettingsPath)) -ForegroundColor Cyan
    } else {
        Write-Host "  And settings.json.bak could not be taken when it opened," -ForegroundColor Yellow
        Write-Host "  so it does not hold that copy either." -ForegroundColor Yellow
    }
}

function ConvertTo-CanonicalJson {
    # A value as text that compares equal whenever Windows Terminal would read
    # the two the same: object keys sorted ordinally, every number as a double
    # in invariant 'R' form (11 and 11.0 are one value), arrays in order. So a
    # file Windows Terminal re-serialised -- keys reordered, 11 written 11.0 --
    # still compares equal to the preview that wrote it.
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return (ConvertTo-Json -InputObject $Value -Compress) }
    if ($Value -is [datetime]) { return ('"' + $Value.ToString('o', [cultureinfo]::InvariantCulture) + '"') }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or
        $Value -is [single] -or $Value -is [byte] -or $Value -is [int16] -or
        # By name: pwsh 7 parses a huge integer as BigInteger, and the type is
        # not loaded on Windows PowerShell 5.1, where a type literal would throw.
        $Value.GetType().FullName -eq 'System.Numerics.BigInteger') {
        return ([double]$Value).ToString('R', [cultureinfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object { "$_" })
        [array]::Sort($keys, [System.StringComparer]::Ordinal)
        return ('{' + (($keys | ForEach-Object { (ConvertTo-Json -InputObject $_ -Compress) + ':' + (ConvertTo-CanonicalJson $Value[$_]) }) -join ',') + '}')
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return ('[' + ((@($Value) | ForEach-Object { ConvertTo-CanonicalJson $_ }) -join ',') + ']')
    }
    $props = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $_.Name })
    [array]::Sort($props, [System.StringComparer]::Ordinal)
    return ('{' + (($props | ForEach-Object { (ConvertTo-Json -InputObject $_ -Compress) + ':' + (ConvertTo-CanonicalJson $Value.$_) }) -join ',') + '}')
}

function Undo-WTSettingsPreview {
    <#
    .SYNOPSIS
    Take a preview back out of settings.json as it is NOW, keeping every other
    change. Pure. Returns @{ Text; Undone; Kept }.

    .DESCRIPTION
    The inverse of Merge-StyleIntoSettings, for a file that changed after the
    preview was written -- Windows Terminal's Settings UI, Settings Sync,
    another command -- where putting the old text back would throw that change
    away. It touches only what the merge can change: the target entry
    (resolved as the merge resolves it), profiles.defaults when it is not the
    target, and schemes by name. For each value the preview changed:

      still the preview's   -> the original's goes back, or the key goes when
                               the original had none (Undone)
      back at the original  -> nothing to do
      anything else         -> left as it is, and named (Kept)

    Values compare through ConvertTo-CanonicalJson. A defaults block or schemes
    key the preview created and the undo leaves empty goes too. Throws on a
    current file that does not parse; callers turn that into 'failed'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$OriginalJson,
        [Parameter(Mandatory)][AllowEmptyString()][string]$PreviewJson,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CurrentJson,
        [AllowEmptyString()][string]$TargetName
    )
    $o = ConvertFrom-JsoncText $OriginalJson
    $p = ConvertFrom-JsoncText $PreviewJson
    $c = ConvertFrom-JsoncText $CurrentJson
    if ($null -eq $c) { throw 'settings.json does not parse as a JSON object' }
    $undone = [System.Collections.Generic.List[string]]::new()
    $kept   = [System.Collections.Generic.List[string]]::new()

    $has   = { param($obj, $k) $null -ne $obj -and @($obj.PSObject.Properties.Match($k)).Count -gt 0 }
    $canon = { param($obj, $k) if (& $has $obj $k) { ConvertTo-CanonicalJson $obj.$k } else { '<absent>' } }

    # One object's keys, compared across the three texts.
    $undoObject = {
        param($oe, $pe, $ce, [string]$Prefix)
        if ($null -eq $ce) { return }
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($x in @($oe, $pe)) {
            if ($null -eq $x) { continue }
            foreach ($pr in $x.PSObject.Properties) { if (-not $names.Contains($pr.Name)) { $names.Add($pr.Name) } }
        }
        foreach ($k in $names) {
            $ov = & $canon $oe $k
            $pv = & $canon $pe $k
            if ($ov -ceq $pv) { continue }
            $cv = & $canon $ce $k
            if ($cv -ceq $ov) { continue }
            if ($cv -ceq $pv) {
                if (& $has $oe $k) {
                    if (& $has $ce $k) { $ce.$k = $oe.$k }
                    else { $ce | Add-Member -NotePropertyName $k -NotePropertyValue $oe.$k }
                } else {
                    [void]$ce.PSObject.Properties.Remove($k)
                }
                $undone.Add($Prefix + $k)
            } else {
                $kept.Add($Prefix + $k)
            }
        }
    }

    $target = $TargetName
    if (-not $target) { $target = 'defaults' }
    $ro = Resolve-WTProfileTarget -Settings $o -TargetName $target
    $rp = Resolve-WTProfileTarget -Settings $p -TargetName $target
    $rc = Resolve-WTProfileTarget -Settings $c -TargetName $target
    & $undoObject $ro.Entry $rp.Entry $rc.Entry ''

    if ($target -ne 'defaults') {
        $so = (Get-WTProfileShape -Settings $o).Defaults
        $sp = (Get-WTProfileShape -Settings $p).Defaults
        $sc = (Get-WTProfileShape -Settings $c).Defaults
        & $undoObject $so $sp $sc 'defaults/'
    }
    # A defaults block the preview created and the undo left empty.
    $dc = (Get-WTProfileShape -Settings $c).Defaults
    if ($null -ne $dc -and @($dc.PSObject.Properties).Count -eq 0 -and $null -eq (Get-WTProfileShape -Settings $o).Defaults -and
        $null -ne (Get-WTProfileShape -Settings $p).Defaults) {
        [void]$c.profiles.PSObject.Properties.Remove('defaults')
    }

    # Schemes, by name.
    $byName = { param($doc) $h = @{}; if (& $has $doc 'schemes') { foreach ($sx in @($doc.schemes)) { if ($null -ne $sx -and $sx.name) { $h["$($sx.name)"] = $sx } } }; $h }
    $so = & $byName $o; $sp = & $byName $p; $sc = & $byName $c
    $schemeNames = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $so, $sp) { foreach ($k in $h.Keys) { if (-not $schemeNames.Contains($k)) { $schemeNames.Add($k) } } }
    foreach ($n in $schemeNames) {
        $ov = if ($so.ContainsKey($n)) { ConvertTo-CanonicalJson $so[$n] } else { '<absent>' }
        $pv = if ($sp.ContainsKey($n)) { ConvertTo-CanonicalJson $sp[$n] } else { '<absent>' }
        if ($ov -ceq $pv) { continue }
        $cv = if ($sc.ContainsKey($n)) { ConvertTo-CanonicalJson $sc[$n] } else { '<absent>' }
        if ($cv -ceq $ov) { continue }
        if ($cv -ceq $pv) {
            $list = @(@($c.schemes) | Where-Object { -not ($null -ne $_ -and "$($_.name)" -ceq $n) })
            if ($so.ContainsKey($n)) { $list += $so[$n] }
            $c.schemes = $list
            $undone.Add("schemes/$n")
        } else {
            $kept.Add("schemes/$n")
        }
    }
    if ((& $has $c 'schemes') -and @($c.schemes).Count -eq 0 -and -not (& $has $o 'schemes')) {
        [void]$c.PSObject.Properties.Remove('schemes')
    }

    return @{
        Text   = ($c | ConvertTo-Json -Depth 100)
        Undone = $undone.ToArray()
        Kept   = $kept.ToArray()
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

    # The lazy creation, guarded rather than assumed (Initialize-WTDefaultsEntry,
    # shared with Set-ProfileFont; it covers an absent key and a null). Add-Member needs a
    # `profiles` OBJECT to add the block to: on a missing key or a null this
    # line threw, and on the legacy flat-array form it unrolled the array and
    # grafted `defaults` onto every profile in it without a word. The resolver
    # now refuses 'defaults' for both shapes, so a caller that went through it
    # never arrives here -- this is the same rule stated where the write
    # happens, for the two callers that merge without resolving first (the
    # picker's preview and the tuner). Falling through to the existing
    # `if (-not $entry)` keeps the no-target contract: settings returned
    # untouched, and no orphan scheme, since the scheme is upserted below.
    $entry = if ($TargetName -eq 'defaults') { Initialize-WTDefaultsEntry -Settings $Settings } else { $namedEntry }
    if (-not $entry) { return $Settings }

    if (-not $Settings.PSObject.Properties.Match('schemes').Count) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
    }
    # $null -ne $_ first: a null `schemes` pipes one $null down, `$_.name -ne`
    # lets it through, and that wrote [null, {...}].
    $Settings.schemes = @($Settings.schemes | Where-Object { $null -ne $_ -and $_.name -ne $scheme.name }) + $scheme

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

    # Which background fields the INCOMING theme.json will actually put back.
    # theme.json keys are optional and hand-authorable -- README documents the
    # file that way and Get-AvailableStyles admits a folder without one -- so
    # this is a question about the style in front of us, never a constant.
    $themeBgNames = @($theme.PSObject.Properties |
                      Where-Object { $_.Name -in $bgFields } |
                      ForEach-Object { $_.Name })
    # An image of ours ends up on the entry -- shadowing profiles.defaults --
    # only when the merge is applying one AND this theme.json names the key
    # that carries it.
    $entryWillShadow = ($bgAction -eq 'apply') -and ($themeBgNames -contains 'backgroundImage')

    # The clear is driven by what is already ON the profile, not by what the new
    # style's theme.json happens to mention -- for BOTH non-skip actions.
    # Running it inside the property loop below meant it only fired for styles
    # whose theme.json named the fields, so switching to one that omitted them
    # left the PREVIOUS style's image showing through the new palette. 'remove'
    # was hoisted out for that reason; 'apply' was left inside, which is the
    # same asymmetry on the other half of the same switch: a hand-authored
    # theme.json naming only colorScheme and backgroundImage inherited the last
    # style's opacity, stretch mode and alignment, and one naming no background
    # key at all kept the last style's IMAGE outright while its own
    # background.gif was never written. Cleared here, rewritten below by
    # whatever the incoming theme declares.
    if ($bgAction -ne 'skip') {
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
        # to keep. Guarded a second time on nothing of ours landing on the
        # entry: where an apply writes the new style's image there it shadows
        # defaults, so no old image is visible on this profile and clearing
        # defaults would silently restyle every OTHER profile too. Where it
        # does not -- an apply whose theme.json never names backgroundImage --
        # the inherited copy is exactly what the user keeps looking at, which
        # is the bleed this block exists to stop.
        if ($inheritedEntry -and (Test-ManagedBackgroundPath -Path $inheritedBg) -and (-not $entryWillShadow)) {
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
            # apply: the whole set was stripped above too, so what this loop
            #        writes is exactly what THIS style declares -- no field of
            #        the previously applied style survives underneath it.
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
    # On macOS and Linux Replace is a bare rename(2): it keeps nothing of the
    # file it replaces and asks only the directory, so Initialize-ReplaceTemp
    # runs first.
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

    # A failure is ONE error of this function's own, "Could not write <path>:
    # <why>", thrown. A .NET exception here only ends its own statement, so
    # with no try above it -- an interactive pwsh -- the caller's next line
    # ran: apply printed "Style applied" and recorded a style over a file it
    # never wrote, reset cleared the record, font said "Applied".
    try {
        # A symlinked settings.json is written THROUGH, never replaced -- the
        # same rule install.ps1's Write-TextFileAtomic applies to a symlinked
        # $PROFILE, and for the same reason. Keeping settings.json in a dotfiles
        # repo and linking it into LocalState is the ordinary arrangement on
        # Windows; [System.IO.File]::Replace below would swap that link for a
        # regular file on every apply, preview, tuner keystroke and font write,
        # silently detaching the repo copy. See Test-PathIsSymlink.
        if (Test-PathIsSymlink -Path $Path) {
            [System.IO.File]::WriteAllText($Path, $Json, $enc)
            return
        }

        # One temp per process. It was one name, settings.json.tstmp, for every
        # writer: a second tstyles holding it, or a temp that could not be
        # written, fell through to Replace (swapping in another writer's
        # half-written copy) or to the in-place write below, the one this
        # function exists to avoid.
        $tmp = '{0}.{1}.tstmp' -f $Path, $PID
        # On macOS and Linux Replace is a bare rename(2): it keeps nothing of
        # the file it replaces and asks only the directory. See
        # Initialize-ReplaceTemp.
        Initialize-ReplaceTemp -Path $Path -TempPath $tmp
        # Nothing has touched settings.json yet, and a failure here keeps it
        # that way: no Replace of a partial or foreign temp, no truncating
        # fallback. Only a regular file at that name is ours to remove.
        try {
            [System.IO.File]::WriteAllText($tmp, $Json, $enc)
        } catch {
            $why = $_.Exception.GetBaseException().Message
            if ([System.IO.File]::Exists($tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            throw ("its temporary copy {0} could not be written: {1}" -f $tmp, $why)
        }
        try {
            if (Test-Path -LiteralPath $Path) {
                # backupFileName = [NullString]::Value: replace without keeping a
                # copy. A bare $null is coerced by PowerShell to '' here, which
                # makes Replace throw "path is empty" on PS7 and silently fall
                # back to the non-atomic in-place write below; [NullString]::Value
                # passes a true null so the atomic same-volume rename actually runs.
                [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
        } catch {
            # Best-effort fallback (Replace unsupported by the filesystem, etc.).
            # The cleanup is in a finally because the fallback can throw too --
            # on Windows a read-only or locked settings.json fails BOTH the
            # Replace and the WriteAllText, and the exception then escaped past
            # the cleanup line, leaving a temp beside the user's settings.json on
            # every attempt. On macOS and Linux a read-only one never gets here:
            # Initialize-ReplaceTemp refuses it before the temp exists.
            try {
                [System.IO.File]::WriteAllText($Path, $Json, $enc)
            } finally {
                if ([System.IO.File]::Exists($tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch {
        throw ("Could not write {0}: {1}" -f $Path, $_.Exception.GetBaseException().Message)
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
