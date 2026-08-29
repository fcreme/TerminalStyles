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
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

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
            # resolves any '..'; it does not require the file to exist. A WT
            # keyword like 'desktopWallpaper' resolves against the CWD and so
            # never lands under one of our roots.
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

function Resolve-WTProfileTarget {
    <#
    .SYNOPSIS
    Resolve a -Target name against settings.json. Reports nothing; decides only.

    .DESCRIPTION
    One rule, four callers. Apply, reset, font and the picker each resolved the
    target themselves, and each did it at a different point relative to the
    damage -- which is how a mistyped -Target came to destroy the rolling
    backup on two of them while erroring cleanly on a third.

    Ok vs Entry is a real distinction, not a convenience. 'defaults' is always
    ADDRESSABLE (an apply creates the block lazily) so Ok is $true, but it has
    no Entry until the block exists -- and reset has nothing to strip from a
    profile that is not there. Callers that write want Ok; callers that modify
    an existing entry want Entry.

    Available is for the caller's error message, so every one of them can name
    the same set of real profiles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Settings,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TargetName
    )

    $list = @()
    try { $list = @($Settings.profiles.list) } catch { $list = @() }
    $available = @('defaults') + @($list | ForEach-Object { $_.name } | Where-Object { $_ })

    if ($TargetName -eq 'defaults') {
        $entry = $null
        try {
            if ($Settings.profiles.PSObject.Properties.Match('defaults').Count) {
                $entry = $Settings.profiles.defaults
            }
        } catch { }
        return [pscustomobject]@{ Ok = $true; Entry = $entry; IsDefaults = $true; Available = $available }
    }

    $entry = $list | Where-Object name -eq $TargetName | Select-Object -First 1
    return [pscustomobject]@{
        Ok = [bool]$entry; Entry = $entry; IsDefaults = $false; Available = $available
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
    $namedEntry = $null
    if ($TargetName -ne 'defaults') {
        $namedEntry = $Settings.profiles.list | Where-Object name -eq $TargetName | Select-Object -First 1
        if (-not $namedEntry) { return $Settings }   # missing named target: leave settings untouched
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

    $entry = if ($TargetName -eq 'defaults') {
        if (-not $Settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $Settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $Settings.profiles.defaults
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
    $existingBg = if ($entry.PSObject.Properties.Match('backgroundImage').Count -gt 0) {
        [string]$entry.backgroundImage
    } else { $null }

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
    # if Replace/Move is unsupported (e.g. an odd filesystem). UTF-8 no BOM.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    $enc = [System.Text.UTF8Encoding]::new($false)
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
