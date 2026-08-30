# tune.ps1 -- `tstyles tune`: the live editor and the style it materialises.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Five knobs, split by what each can actually do. Brightness and saturation
# retint live over OSC on every terminal. Opacity and font can only be previewed
# on Windows Terminal, by writing a scratch style and running the REAL merge
# against it -- so the preview cannot drift from an apply. Off Windows Terminal
# they are recorded in the saved style and nothing there can show them.
#
# Save-TunedStyle materialises a full style, not a diff: it lands in the user
# styles dir and is thereafter indistinguishable from a hand-written one.

function New-TunedThemeObject {
    # Builds the theme.json object for a tuned style: base theme.json (or {})
    # with colorScheme/opacity/font overridden. Preserves font.weight and the
    # backgroundImage placeholder. Shared by Save-TunedStyle and the live
    # preview so the saved result matches what was previewed.
    param(
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$ColorScheme,
        [int]$Opacity,
        [string]$FontFace,
        [int]$FontSize
    )
    $themeSrc = Join-Path $BaseStyleDir 'theme.json'
    $theme = if (Test-Path -LiteralPath $themeSrc) {
        try {
            [System.IO.File]::ReadAllText($themeSrc, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        } catch { $null }
    } else { $null }

    # A base theme.json that is empty, truncated, or holds a bare JSON scalar
    # or array parses to something Add-Member cannot extend. Those failures are
    # non-terminating, so the function used to sail on and hand back $null --
    # which ConvertTo-Json writes out as the four characters `null`. The saved
    # style then had no colorScheme, no opacity and no font, while the tuner
    # reported "Style applied": on Windows Terminal that is a profile pointing
    # at nothing, with an orphaned scheme beside it. Falling back to an empty
    # object costs only the base's backgroundImage placeholder and font.weight,
    # and everything the tuner actually sets is written.
    if ($theme -isnot [System.Management.Automation.PSCustomObject]) {
        $theme = [pscustomobject]@{}
    }

    $theme | Add-Member -NotePropertyName colorScheme -NotePropertyValue $ColorScheme -Force
    $theme | Add-Member -NotePropertyName opacity     -NotePropertyValue $Opacity     -Force

    $font = if ($theme.PSObject.Properties.Match('font').Count) { $theme.font } else { [pscustomobject]@{} }
    $font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
    $font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize -Force
    $theme | Add-Member -NotePropertyName font -NotePropertyValue $font -Force
    return $theme
}


function Test-SameStyleDirectory {
    <#
    .SYNOPSIS
    Do two style paths name the same directory, as the HOST FILESYSTEM sees it?

    .DESCRIPTION
    Carved out as a pure function for the same reason Get-PickerViewport was: the
    decision is one line of subtlety that cannot be tested through its caller.
    Save-TunedStyle's effect here is "copy prompt.sh, or don't", and the case that
    matters -- styles/Eva versus styles/eva -- is not even expressible on the
    macOS and Windows filesystems the test suite mostly runs on, where the two
    are one directory. Mock Get-TStylesPlatform and ask this instead.

    Case sensitivity follows the platform, not PowerShell. -eq is case-insensitive
    everywhere, so on Linux a "Save as Eva" from a base at styles/eva looked like
    the same directory and skipped the prompt.sh copy into what was really a brand
    new style, costing it the zsh/bash prompt entirely.

    Returns $false on any path it cannot resolve: the copies this guards are
    idempotent, so a wrong $false costs a redundant write and a wrong $true costs
    a missing prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$A,
        [Parameter(Mandatory)][AllowEmptyString()][string]$B
    )

    if (-not $A -or -not $B) { return $false }
    try {
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $fa = [System.IO.Path]::GetFullPath($A).TrimEnd($sep)
        $fb = [System.IO.Path]::GetFullPath($B).TrimEnd($sep)

        # Identical spellings are the same directory on every filesystem, and
        # this is the overwhelmingly common case -- answer it without touching
        # the disk.
        if ([string]::Equals($fa, $fb, [System.StringComparison]::Ordinal)) { return $true }

        # They differ only in case (or not at all in a way that matters), so the
        # answer depends on the VOLUME, not the platform. Inferring it from
        # Get-TStylesPlatform -- Ordinal on Linux, OrdinalIgnoreCase elsewhere --
        # is wrong wherever a non-Linux volume is case-sensitive: case-sensitive
        # APFS (chosen at format time), a Windows directory flagged with
        # `fsutil file setCaseSensitiveInfo`, or a case-sensitive network mount.
        # There styles/Retro and styles/retro are two real directories, this
        # answered $true, and a Save-As differing from its base only in case
        # skipped the prompt.sh copy -- so the brand-new style shipped with no
        # zsh/bash prompt at all, silently, and the collision prompt never fired
        # because the destination genuinely did not exist.
        #
        # So ask the filesystem instead. A wrong answer here is cheap in one
        # direction only (see the .SYNOPSIS), and any probe failure falls back
        # to the platform guess rather than throwing.
        if (-not [string]::Equals($fa, $fb, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return (Test-PathCaseInsensitive -Path $fa -Other $fb)
    } catch { return $false }
}

function Test-PathCaseInsensitive {
    <#
    .SYNOPSIS
    Do two paths differing only in case resolve to the same directory on THIS volume?

    .DESCRIPTION
    Both paths are assumed already normalised and OrdinalIgnoreCase-equal. The
    probe is the only reliable answer: filesystem case sensitivity is a property
    of the volume, not of the operating system.

    Asks whichever of the two exists whether the other spelling reaches the same
    thing. Falls back to the platform's usual default when neither exists or the
    probe throws -- Ordinal on Linux, OrdinalIgnoreCase elsewhere -- which is the
    behaviour this replaced.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Other
    )

    try {
        $pExists = Test-Path -LiteralPath $Path
        $oExists = Test-Path -LiteralPath $Other
        # Both spellings resolve. Whether they resolve to ONE directory is
        # answered by canonicalising each and comparing Ordinal.
        #
        # Not by comparing (Get-Item).FullName, which is what this did first:
        # that only works on .NET Core, where the provider hands back the name
        # as the directory actually spells it. On .NET Framework -- Windows
        # PowerShell 5.1, which this module supports and CI covers -- FullName
        # echoes the caller's own casing straight back, so the two spellings
        # compared UNEQUAL on plain NTFS and the probe reported a
        # case-sensitive volume on the most case-insensitive one there is.
        # Green on pwsh 7 and red on 5.1, on the same machine and the same
        # directory.
        if ($pExists -and $oExists) {
            $cp = Get-CanonicalPathCase -Path $Path
            $co = Get-CanonicalPathCase -Path $Other
            if ($cp -and $co) {
                return [string]::Equals($cp, $co, [System.StringComparison]::Ordinal)
            }
        }
        if ($pExists -or $oExists) { return $false }
    } catch { }

    return ((Get-TStylesPlatform) -ne 'Linux')
}

function Get-CanonicalPathCase {
    <#
    .SYNOPSIS
    A path spelled the way the filesystem spells it, or $null if it cannot be walked.

    .DESCRIPTION
    Rebuilds the path one segment at a time from the names its parent directory
    actually lists, which is the only spelling both PowerShell engines agree
    on. There is no framework call for this: [Path]::GetFullPath does not touch
    the disk, and Get-Item's FullName is canonical only on .NET Core.

    An exact (Ordinal) match for a segment always wins over a case-insensitive
    one. That is what keeps the answer right on a case-SENSITIVE volume, where
    `eva` and `Eva` are two real entries and matching case-insensitively could
    otherwise canonicalise both onto whichever the listing happened to yield
    first -- turning two directories into one, which is the failure this whole
    function exists to prevent.

    Returns $null when any segment cannot be listed or matched; callers treat
    that as "cannot tell" and fall back.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($full)
        if (-not $root) { return $null }

        $rest = $full.Substring($root.Length)
        $segments = $rest.Split([char[]]@('/', '\'), [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($segments.Count -eq 0) { return $root }

        $cur = $root
        foreach ($seg in $segments) {
            $entries = @(Get-ChildItem -LiteralPath $cur -Force -ErrorAction Stop)
            $match = $entries | Where-Object {
                [string]::Equals($_.Name, $seg, [System.StringComparison]::Ordinal)
            } | Select-Object -First 1
            if (-not $match) {
                $match = $entries | Where-Object {
                    [string]::Equals($_.Name, $seg, [System.StringComparison]::OrdinalIgnoreCase)
                } | Select-Object -First 1
            }
            if (-not $match) { return $null }
            $cur = Join-Path $cur $match.Name
        }
        return $cur
    } catch { return $null }
}

function Get-StyleSchemeFingerprint {
    <#
    .SYNOPSIS
    A stable fingerprint of a style's scheme.json, or $null if it cannot be read.

    .DESCRIPTION
    A tuned style records DELTAS against a base, not colours, so it only means
    anything while the base still holds the colours the deltas were measured
    from. Overwrite-saving the base breaks that: the base's scheme.json is
    re-baked with ITS tune applied, and every tuned style pointing at it then
    re-derives from the new file. Tune `eva` -35 and save it as `eva-night`,
    Overwrite-save `eva` itself at -20, then re-open `eva-night`: it seeds -35
    against a base already darkened by -20 and previews at -55, silently, on a
    style that had looked settled. Saving from there bakes the drift in, and it
    compounds on every round.

    Recording the fingerprint at save time lets Resolve-TuneSeed notice the base
    has moved and decline to re-apply deltas that no longer mean what they meant.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

    $schemePath = Join-Path $StyleDir 'scheme.json'
    if (-not (Test-Path -LiteralPath $schemePath)) { return $null }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash([System.IO.File]::ReadAllBytes($schemePath))
            return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
    } catch { return $null }
}

function Save-TunedStyle {
    # Materializes a tuned style into $DataRoot\styles\$SaveName\:
    #   scheme.json (adjusted colors, name = $SaveName)
    #   theme.json  (base theme + colorScheme/opacity/font overrides)
    #   profile.ps1 (copied from base if present)
    #   tune.json   (deltas + base name, for re-tuning)
    param(
        [Parameter(Mandatory)]$AdjustedScheme,
        [Parameter(Mandatory)][string]$SaveName,
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$BaseName,
        [int]$Brightness, [int]$Saturation, [int]$Opacity,
        [string]$FontFace, [int]$FontSize
    )
    $destDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $SaveName
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Clone so the caller's object is not mutated (matches Get-AdjustedScheme's contract).
    $scheme = $AdjustedScheme.PSObject.Copy()
    $scheme | Add-Member -NotePropertyName name -NotePropertyValue $SaveName -Force
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'scheme.json'),
        ($scheme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $theme = New-TunedThemeObject -BaseStyleDir $BaseStyleDir -ColorScheme $SaveName `
        -Opacity $Opacity -FontFace $FontFace -FontSize $FontSize
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'theme.json'),
        ($theme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    # Re-tuning a style that was already saved with Overwrite makes $BaseStyleDir
    # and $destDir the SAME directory, so every "copy from base to dest" below is
    # really a copy of a file onto itself. Left unguarded that appends a second
    # `# tstyles-tuned:` marker to profile.ps1 on each repeat and makes Copy-Item
    # throw a red "Cannot overwrite the item with itself" for prompt.sh, at save
    # time, after the user has already committed.
    # Compared the way the HOST FILESYSTEM compares, not the way PowerShell's
    # -eq does. -eq is case-insensitive, so on Linux (case-sensitive) a "Save
    # as" of `Eva` from a base at styles/eva would look like the same directory
    # and skip the prompt.sh copy into what is really a brand-new style --
    # costing it the zsh/bash prompt the copy exists to provide.
    $sameDir = Test-SameStyleDirectory -A $destDir -B $BaseStyleDir

    # Copy-or-REMOVE, not copy-if-present, for the artefacts this function owns.
    #
    # The Save-As collision prompt promises "'<name>' already exists and will be
    # REPLACED", and this was a merge: anything the NEW base does not itself
    # ship survived from the old style. Save over `mytheme` (tuned from eva,
    # so carrying eva's profile.ps1 and prompt.sh) with a tune of `plain`
    # (which legitimately ships neither -- README documents both as optional)
    # and the new mytheme kept eva's profile.ps1 and prompt.sh: it printed the
    # wrong theme's banner and set the wrong prompt, in a style the user had
    # just been told was replaced.
    #
    # Only when the destination is a DIFFERENT directory from the base. An
    # Overwrite re-tune has them equal, where the source and the thing being
    # removed are the same file.
    $profileSrc = Join-Path $BaseStyleDir 'profile.ps1'
    $profileDst = Join-Path $destDir 'profile.ps1'
    if (-not $sameDir -and -not (Test-Path -LiteralPath $profileSrc) -and (Test-Path -LiteralPath $profileDst)) {
        Remove-Item -LiteralPath $profileDst -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $profileSrc) {
        # Append a per-style marker so the materialized profile is byte-distinct
        # from the base's (we copied it verbatim). Without this, Get-CurrentStyleName
        # -- which byte-compares current-style.ps1 against each style's profile.ps1
        # and returns the alphabetically-first match -- would attribute this tuned
        # style to its base. The marker is an inert comment (profile is dot-sourced).
        $profileContent = [System.IO.File]::ReadAllText($profileSrc, [System.Text.UTF8Encoding]::new($false))
        # Strip any marker a previous save left, so re-tuning appends exactly one
        # rather than accumulating a line per save. Idempotent either way.
        $profileContent = [regex]::Replace($profileContent,
            '(\r?\n)?^[ \t]*#[ \t]*tstyles-tuned:.*$', '', 'Multiline').TrimEnd("`r", "`n")
        $marker = [Environment]::NewLine + "# tstyles-tuned: $SaveName" + [Environment]::NewLine
        [System.IO.File]::WriteAllText(
            (Join-Path $destDir 'profile.ps1'),
            ($profileContent + $marker),
            [System.Text.UTF8Encoding]::new($false))
    }

    # The zsh/bash prompt, copied verbatim. It needs no per-style marker: unlike
    # profile.ps1, nothing byte-compares it to identify the active style. Without
    # this a tuned style has no shell prompt at all, so a zsh user who tunes
    # anything silently loses the banner and prompt while keeping the colors.
    $promptSrc = Join-Path $BaseStyleDir 'prompt.sh'
    $promptDst = Join-Path $destDir 'prompt.sh'
    if (-not $sameDir) {
        if (Test-Path -LiteralPath $promptSrc) {
            Copy-Item -LiteralPath $promptSrc -Destination $promptDst -Force
        } elseif (Test-Path -LiteralPath $promptDst) {
            # Same reasoning as profile.ps1 above: leaving the old style's
            # prompt behind gives the replaced style the wrong banner.
            Remove-Item -LiteralPath $promptDst -Force -ErrorAction SilentlyContinue
        }
    }

    $tune = [pscustomobject]@{
        schemaVersion = 1
        base          = $BaseName
        # What the deltas below were measured against. Checked on re-tune so a
        # base that has since been re-baked cannot silently double-apply them.
        baseFingerprint = (Get-StyleSchemeFingerprint -StyleDir $BaseStyleDir)
        brightness    = $Brightness
        saturation    = $Saturation
        opacity       = $Opacity
        fontFace      = $FontFace
        fontSize      = $FontSize
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'tune.json'),
        ($tune | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false))

    return $destDir
}

function Get-TunedBaseBackground {
    # If $StyleDir is a tuned style (tune.json with a 'base'), resolve and
    # return the base style's background (with the base's own lazy-fetch).
    # $null if not tuned / base missing / base has no background. Strictly one
    # hop: the base is resolved with -NoInherit, so cyclic tune.json (A->B->A)
    # cannot recurse.
    param([Parameter(Mandatory)][string]$StyleDir)
    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (-not (Test-Path -LiteralPath $tuneFile)) { return $null }
    try {
        $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return $null }
    if (-not $tune.base) { return $null }
    $baseDir = Get-StyleDir -StyleName $tune.base
    # Compared the way the host filesystem compares -- see Test-SameStyleDirectory.
    if (-not $baseDir -or (Test-SameStyleDirectory -A $baseDir -B $StyleDir)) { return $null }
    return Get-StyleBundledBackground -StyleDir $baseDir -NoInherit
}

function Resolve-TuneSeed {
    # Computes the working base style + the initial knob values for `tstyles tune`.
    # Extracted from Invoke-TerminalStyleTune so the seeding rules are unit-testable.
    #
    # Rules:
    #   * A tuned style (tune.json with a base that still resolves) seeds the base
    #     dir + the recorded deltas, so re-deriving never double-applies onto the
    #     already-baked scheme.
    #   * Otherwise (a plain style, OR a tuned style whose recorded base was
    #     deleted/renamed) the working base is the style itself, and opacity/font
    #     seed from that style's OWN theme.json -- so re-tuning preserves the saved
    #     values instead of snapping back to the hardcoded defaults.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir
    )

    $seed = [pscustomobject]@{
        BaseName = $StyleName; BaseDir = $StyleDir
        Brightness = 0; Saturation = 0; Opacity = 100; FontFace = $null; FontSize = 12
        # Set when a recorded base was found but has changed since the save, so
        # the caller can say why the knobs came up neutral instead of leaving
        # the user to wonder where their adjustments went.
        BaseChanged = $false
        # The name of the base that moved, for the notice. Distinct from
        # BaseName, which stays the style itself when the deltas are dropped.
        ChangedBaseName = $null
    }
    $seededFromTune = $false

    # Reads the opacity/font a style declares for itself, guarding each property
    # so an absent one stays absent rather than becoming [int]$null == 0.
    $readThemeKnobs = {
        param([string]$Dir)
        $out = [pscustomobject]@{ Opacity = $seed.Opacity; FontFace = $seed.FontFace; FontSize = $seed.FontSize }
        $themePath = Join-Path $Dir 'theme.json'
        if (Test-Path -LiteralPath $themePath) {
            try {
                $t = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($t -is [System.Management.Automation.PSCustomObject]) {
                    if ($t.PSObject.Properties.Match('opacity').Count) { $out.Opacity = [int]$t.opacity }
                    if ($t.PSObject.Properties.Match('font').Count -and
                        $t.font -is [System.Management.Automation.PSCustomObject]) {
                        if ($t.font.PSObject.Properties.Match('face').Count) { $out.FontFace = [string]$t.font.face }
                        if ($t.font.PSObject.Properties.Match('size').Count) { $out.FontSize = [int]$t.font.size }
                    }
                }
            } catch { }
        }
        return $out
    }

    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (Test-Path -LiteralPath $tuneFile) {
        try {
            $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($tune.base) {
                $resolvedBaseDir = Get-StyleDir -StyleName $tune.base
                # Guard against a self-referential base (an Overwrite save writes
                # the baked scheme back onto the base name and records base = that
                # name). Re-seeding the deltas here would re-apply them on top of
                # the already-baked scheme -- color drift on every re-tune. Fall
                # through to own-theme.json seeding (neutral brightness/saturation)
                # instead. Mirrors the self-reference guard in Get-TunedBaseBackground.
                # The deltas are only meaningful against the scheme they were
                # measured from. If the base has been re-baked since (an
                # Overwrite save on the base does exactly that), re-applying
                # them stacks one tune on top of another -- -35 seeded against
                # a base already carrying -20 previews at -55, and saving bakes
                # that in. Fall through to own-theme seeding instead, the same
                # way the self-reference guard above does.
                #
                # A tune.json written before the fingerprint existed has none;
                # that is "unknown", not "changed", so those keep seeding as
                # they always did rather than silently losing their knobs.
                $recordedFp = [string]$tune.baseFingerprint
                $baseMoved  = $false
                # Only meaningful when the base is a DIFFERENT directory. An
                # Overwrite save records the fingerprint of the bundled copy it
                # baked from, and then resolves user-first to its own baked
                # result -- so comparing there always differs, and the warning
                # fired on the first re-tune of every overwrite-saved style,
                # claiming a style had changed under itself. The self-reference
                # guard below already handles that case, silently and correctly.
                # Test-SameStyleDirectory, not -ne: PowerShell's operators are
                # case-insensitive everywhere, so on a case-sensitive volume
                # styles/eva and styles/Eva are two directories that -ne
                # collapses into one -- and the guard then fires when it should
                # not, dropping the deltas of a style legitimately based on a
                # name differing only in case. The helper two functions above
                # exists for exactly this decision and was being used by
                # Save-TunedStyle alone.
                $baseIsSelf = (-not $resolvedBaseDir) -or
                              (Test-SameStyleDirectory -A $resolvedBaseDir -B $StyleDir)
                if (-not $baseIsSelf -and $recordedFp) {
                    $currentFp = Get-StyleSchemeFingerprint -StyleDir $resolvedBaseDir
                    # $null means the base could not be READ -- a lock, a
                    # permission denial, an antivirus hold. That is "unknown",
                    # exactly as a missing recorded fingerprint is, and must not
                    # be read as "changed": doing so discarded the user's
                    # deltas and, on save, rewrote tune.json with the style as
                    # its own base, severing the lineage for good.
                    if ($currentFp) { $baseMoved = ($recordedFp -ne $currentFp) }
                }
                if ($baseMoved) {
                    $seed.BaseChanged = $true
                    # The name of the base that MOVED. $seed.BaseName stays the
                    # style itself here (the fallback seeds from its own
                    # theme.json), so without this the on-screen notice named
                    # the style the user was tuning and read as self-contradictory.
                    $seed.ChangedBaseName = [string]$tune.base
                }

                if (-not $baseIsSelf -and -not $baseMoved) {
                    # Converted into locals FIRST, and committed to $seed only
                    # once every one of them succeeded. These assignments used
                    # to write straight into $seed in this order, so a tune.json
                    # whose brightness was not a number -- hand-edited, shared,
                    # truncated by a full disk -- threw on the [int] with
                    # BaseName and BaseDir already swapped to the base and
                    # $seededFromTune still $false. The catch swallowed it and
                    # the fallback then seeded from the BASE's theme.json with
                    # neutral knobs: the tuner opened on the base style, and
                    # saving re-baked the user's tuned style as a copy of it.
                    # All or nothing is the only safe shape here.
                    # Guarded PER PROPERTY, the way the fallback block below
                    # reads a theme.json. `{"base":"eva"}` is a shape this
                    # project itself writes and treats as valid -- the live
                    # preview writes exactly that, and
                    # Get-StyleBundledBackground-Inherit.Tests.ps1 asserts
                    # inheritance works from it -- and `[int]$null` is 0. So a
                    # tune.json carrying only `base` seeded Opacity 0 and
                    # FontSize 0, throwing away the style's own theme.json;
                    # the tuner opened showing "Opacity 0%" and "Font size 0",
                    # and a straight Enter save wrote opacity 0 (fully
                    # transparent) and font size 0 onto the Windows Terminal
                    # profile. Recovery was asymmetric too: Left clamps font
                    # size at 6, Right walked a seeded 0 up through 1..6.
                    # An absent field means "not recorded", so fall back to
                    # what the style itself declares.
                    $own = & $readThemeKnobs $StyleDir
                    # Present-AND-not-null. A key written as `"opacity": null`
                    # is recorded absence, not a recorded 0, and [int]$null is
                    # 0 either way -- which is a fully transparent window.
                    $has = {
                        param([string]$Prop)
                        ($tune.PSObject.Properties.Match($Prop).Count -gt 0) -and
                        ($null -ne $tune.$Prop)
                    }
                    $b  = if (& $has 'brightness') { [int]$tune.brightness }  else { $seed.Brightness }
                    $s  = if (& $has 'saturation') { [int]$tune.saturation }  else { $seed.Saturation }
                    $o  = if (& $has 'opacity')    { [int]$tune.opacity }     else { $own.Opacity }
                    $ff = if (& $has 'fontFace')   { [string]$tune.fontFace } else { $own.FontFace }
                    $fs = if (& $has 'fontSize')   { [int]$tune.fontSize }    else { $own.FontSize }

                    $seed.BaseName   = $tune.base
                    $seed.BaseDir    = $resolvedBaseDir
                    $seed.Brightness = $b
                    $seed.Saturation = $s
                    $seed.Opacity    = $o
                    $seed.FontFace   = $ff
                    $seed.FontSize   = $fs
                    $seededFromTune  = $true
                }
            }
        } catch { }
    }

    # When NOT seeded from a resolvable tune, take opacity/font from the working
    # base's own theme.json (the base for a plain style; the style itself for a
    # tuned style whose base vanished).
    if (-not $seededFromTune) {
        $baseThemePath = Join-Path $seed.BaseDir 'theme.json'
        if (Test-Path -LiteralPath $baseThemePath) {
            try {
                $baseTheme = [System.IO.File]::ReadAllText($baseThemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($baseTheme.PSObject.Properties.Match('opacity').Count) { $seed.Opacity = [int]$baseTheme.opacity }
                if ($baseTheme.PSObject.Properties.Match('font').Count) {
                    if ($baseTheme.font.PSObject.Properties.Match('face').Count) { $seed.FontFace = [string]$baseTheme.font.face }
                    if ($baseTheme.font.PSObject.Properties.Match('size').Count) { $seed.FontSize = [int]$baseTheme.font.size }
                }
            } catch { }
        }
    }

    return $seed
}

function Invoke-TerminalStyleTune {
    # `tstyles tune [name]` -- interactive live tuning of a style's brightness,
    # saturation, opacity, font face, and font size. Colors retint instantly
    # via OSC; opacity/font ride a debounced settings.json write (through a
    # scratch style dir reusing Merge-StyleIntoSettings). Esc reverts byte-
    # exact; Enter prompts Save / Save As into the user-styles dir.
    [CmdletBinding()]
    param([string]$StyleName)

    # NOT Show-UpdateNoticeIfAvailable. The tuner Clear-Host's before drawing
    # its menu, and pwsh emits that as ESC[3J ESC[H ESC[2J -- ESC[3J takes the
    # SCROLLBACK too, so a notice printed here is not merely overwritten, it is
    # unrecoverable by scrolling up. It was on screen for the 900ms notice sleep
    # off Windows Terminal, and essentially zero time on it. Worse, printing it
    # burned the throttle: Test-UpdateAvailable stamps .last-update-check on
    # every attempt, so having flashed the notice unreadably it then stayed
    # silent for 24 hours and no other command would show it either.
    #
    # Hold it and print it after the tuner gives the screen back, on every exit
    # path -- the same trade the picker makes for the same reason. The check
    # itself is deferred until past the console guards below, so a
    # non-interactive run pays neither the HTTP timeout nor the throttle write.
    $pendingUpdate = $null

    # Windows Terminal previews every knob live, by merging a scratch style into
    # settings.json and letting WT reload. Elsewhere only the color knobs can be
    # previewed -- brightness and saturation ride the OSC packet, while opacity
    # and font can reach the terminal only through a profile, which applies to a
    # new window rather than this one.
    #
    # That is a reduced tuner, not a broken one: the color work is the part
    # people actually sit and adjust, and the font/opacity values are still
    # saved with the style. So run it, and say up front which knobs will not
    # move on screen -- earlier versions refused outright here, which was more
    # conservative than the facts warranted.
    $tuneKind        = Get-TerminalKind
    $tuneUsesSettings = ($tuneKind -eq 'WindowsTerminal')

    # --- Resolve the style (all guards run BEFORE any console interaction) ---
    if (-not $StyleName) {
        $StyleName = Get-CurrentStyleName
        if (-not $StyleName) {
            Write-Error "No active style detected. Try: tstyles tune <name>"
            return
        }
    }
    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    $settingsPath = $null
    if ($tuneUsesSettings) {
        $settingsPath = Find-WTSettingsPath
        if (-not $settingsPath) {
            Write-Error "Could not locate Windows Terminal settings.json."
            return
        }
    }

    # The tuner is a keyboard-driven UI: it polls [Console]::KeyAvailable, which
    # throws outright when stdin is not a console -- piped input, a redirect, a
    # CI step, or a tool that runs commands with stdin detached. The picker was
    # fixed for exactly this and guards the same way; the tuner never was.
    #
    # The order mattered as much as the crash. The raw failure landed AFTER the
    # 900ms notice, after the first preview write, after the OSC packet had
    # repainted the live terminal and after Clear-Host had wiped the scrollback
    # -- so a redirected `tstyles tune <name>` destroyed the user's screen and
    # scrollback, printed .NET console internals, and exited 0, which the
    # zsh/bash shim reads as a successful run. Guard before any of that.
    if ([Console]::IsInputRedirected) {
        Write-Host ""
        Write-Host "  The tuner needs an interactive terminal." -ForegroundColor Yellow
        Write-Host "  This session's input is redirected, so there are no keystrokes to read."
        Write-Host ""
        Write-Host "  Apply a style directly instead:" -ForegroundColor DarkGray
        Write-Host "    tstyles <name>     " -NoNewline -ForegroundColor DarkGray
        Write-Host "(tstyles list shows them all)" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # ...and the other half of the same requirement. `tstyles tune eva > out.txt`
    # typed at a real terminal has a console for stdin, so the guard above does
    # not fire -- and the tuner then drove a screen nobody could see: the menu,
    # the swatch and every OSC repaint went into the file (151 escape sequences
    # measured on a pty run), the terminal showed nothing, and keystrokes were
    # read and acted on blind. The project already draws this distinction in the
    # shell half, which checks IsOutputRedirected before emitting a palette.
    if ([Console]::IsOutputRedirected) {
        Write-Host ""
        Write-Host "  The tuner needs a terminal to repaint." -ForegroundColor Yellow
        Write-Host "  This session's output is redirected, so there is nothing to preview against."
        Write-Host ""
        Write-Host "  Run it directly in your terminal, or apply a style instead:" -ForegroundColor DarkGray
        Write-Host "    tstyles <name>     " -NoNewline -ForegroundColor DarkGray
        Write-Host "(tstyles list shows them all)" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $pendingUpdate = Test-UpdateAvailable

    # --- Establish working base scheme + seed knob values ---
    # If this style is itself a tuned style (has tune.json), the working base
    # is its recorded base's PRISTINE scheme, and knobs seed from the deltas
    # (so re-deriving never double-applies onto the baked file). Otherwise the
    # working base is this style's own scheme with neutral knobs.
    $seed = Resolve-TuneSeed -StyleName $StyleName -StyleDir $styleDir
    $baseName   = $seed.BaseName
    $baseDir    = $seed.BaseDir
    $brightness = $seed.Brightness
    $saturation = $seed.Saturation
    $opacity    = $seed.Opacity
    $fontFace   = $seed.FontFace
    $fontSize   = $seed.FontSize
    $baseChanged = $seed.BaseChanged
    $changedBaseName = $seed.ChangedBaseName

    $baseScheme = [System.IO.File]::ReadAllText((Join-Path $baseDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    # What Esc has to put back is the style the user OPENED the tuner on, which
    # is not always the working base. Tuning `eva-night` (a tuned style whose
    # tune.json records base `eva`) makes $baseDir eva's directory, because that
    # is what the deltas are measured from -- so restoring $baseScheme repainted
    # the terminal as EVA and said "Reverted.", leaving the user on a style they
    # had not chosen and did not have before. For a plain style the two files
    # are the same and this is the same object.
    $openedScheme = if ($styleDir -eq $baseDir) { $baseScheme } else {
        try {
            [System.IO.File]::ReadAllText((Join-Path $styleDir 'scheme.json'),
                [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        } catch { $baseScheme }
    }

    # NOT wrapped in @(). Get-MonospaceFontList ends with `return ,@(...)`, which
    # emits the list as ONE object so a single-font machine cannot unroll to a
    # [string]. @() around that does not re-enumerate it -- it nests it, giving a
    # Count of 1 whose only element is the whole array. The knob then had nothing
    # to cycle (`% 1` is always 0) and the first Left/Right assigned the array to
    # $fontFace, which New-TunedThemeObject's [string]$FontFace refuses outright.
    # The comma is the whole contract; a wrapper here can only break it.
    $fontList = Get-MonospaceFontList -Current $fontFace
    if (-not $fontFace) { $fontFace = $fontList[0] }
    $fontIdx = [Math]::Max(0, [array]::IndexOf($fontList, $fontFace))

    # --- Target WT profile ---
    $originalJson = $null
    $target = $null
    if ($tuneUsesSettings) {
        $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
        $originalSettings = ConvertFrom-WTJson $originalJson
        $target = Get-CurrentWTProfileName -Settings $originalSettings
        if (-not $target) {
            Write-Error "Could not auto-detect a Windows Terminal profile to preview against."
            return
        }
        if (-not $env:WT_SESSION) {
            Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
        }
    } else {
        # Set expectations before the screen is taken over: the two color knobs
        # move on screen, the other three are only recorded.
        #
        # They are recorded and nothing more. Off Windows Terminal the only
        # writer is New-AppleTerminalProfile, whose profile carries colors and a
        # background image -- no font, no opacity (see Get-AppleTerminalProfileData).
        # Every other terminal gets escape sequences, which cannot carry either.
        # So promising "a new window shows them" sent the user to open one and
        # compare an unchanged font against the screenshot.
        Write-Host ""
        Write-Host ("  Tuning on {0}: brightness and saturation preview live." -f (Get-TerminalDisplayName -Kind $tuneKind)) -ForegroundColor DarkGray
        Write-Host "  Opacity and font are saved with the style, but this terminal cannot show them." -ForegroundColor DarkGray
        Write-Host ""
        Start-Sleep -Milliseconds 900
    }

    # --- Scratch dir for the debounced settings.json preview (reuses Merge) ---
    # Keyed on the PROCESS, not on the style name. It used to be
    # .tune-preview/$baseName, which gave two live tuner sessions on the same
    # base the same scratch directory -- and since the finally block below
    # removes it whole and recursive on every exit, whichever session ended
    # first deleted the other's, and the survivor's next preview write threw
    # from inside the save path and lost everything it had tuned.
    #
    # A name can no longer climb out of here (Get-StyleDir refuses anything
    # that is not one directory segment), but the delete below is recursive and
    # unconditional, so it is checked against the containing directory rather
    # than trusted. Cheap, and the failure it guards is unrecoverable.
    # The session directory is the unique part; the style directory INSIDE it
    # still carries the base's name. Both halves matter:
    #
    #   * per-session, because keying the scratch dir on the base name alone
    #     gave two live tuners on the same base one directory -- and the
    #     finally block below removes it whole and recursive on every exit, so
    #     whichever ended first deleted the other's, and the survivor's next
    #     write threw from inside the save path.
    #   * leaf = base name, because Get-StyleBundledBackground derives the
    #     background cache directory from `Split-Path -Leaf $StyleDir`. A leaf
    #     of `session-1234` matches no cache entry and no .no-background
    #     marker, so every preview fell through to the lazy fetch and tried
    #     four Invoke-WebRequest calls for `session-1234.{gif,png,jpg,jpeg}`
    #     against the gifs branch, 10s timeout each -- up to 40 seconds on a
    #     blank screen before the first menu draw -- then left a permanent
    #     cache/session-<PID>/ behind. With the base's name back on the leaf it
    #     reuses the base's cache and marker exactly as it did before.
    $scratchRoot = Join-Path $script:TStylesDataRoot '.tune-preview'
    $scratchSession = Join-Path $scratchRoot ("session-{0}" -f $PID)
    $scratchDir  = Join-Path $scratchSession $baseName
    if ($tuneUsesSettings -and -not (Test-Path -LiteralPath $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }

    # Knob model: index 0..4 = brightness, saturation, opacity, font face, size.
    $sel = 0
    $confirmed = $false
    $applied = $false   # set true only after a saved style is applied; gates the revert
    $pendingApply = $false  # the explicit `& $writePreview` below seeds the preview; this gates only knob edits

    $hint  = "$([char]27)[38;2;160;160;160m"
    $reset = "$([char]27)[0m"

    # Recompute the adjusted scheme + cache its OSC packet.
    $adjusted   = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
    $oscPacket  = Get-SchemeOscPacket -Scheme $adjusted

    $writePreview = {
        # Write scratch scheme/theme then merge into settings.json (brings
        # opacity/font/background live). Colors are already shown via OSC.
        #
        # The whole body is Windows-Terminal-only. The scratch style exists to
        # be fed to Merge-StyleIntoSettings below and to nothing else -- the
        # comment that used to sit here said "Save-TunedStyle reads it on
        # Enter", which was never true: Save-TunedStyle is called with
        # -BaseStyleDir $baseDir, not with $scratchDir. So off Windows Terminal
        # these three writes produced a directory no one read, three files per
        # keypress, and one more way for the Enter path to throw from inside
        # the save -- which is exactly how it lost a whole tuning session when
        # the directory went missing underneath it.
        if (-not $tuneUsesSettings) { return }

        $adj = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        $adj | Add-Member -NotePropertyName name -NotePropertyValue $baseScheme.name -Force
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'scheme.json'),
            ($adj | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        $theme = New-TunedThemeObject -BaseStyleDir $baseDir -ColorScheme $baseScheme.name `
            -Opacity $opacity -FontFace $fontFace -FontSize $fontSize
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'theme.json'),
            ($theme | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        # tune.json so background inheritance resolves the base GIF in preview.
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'tune.json'),
            ('{"base":"' + $baseName + '"}'), [System.Text.UTF8Encoding]::new($false))

        $preview = ConvertFrom-WTJson $originalJson
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $scratchDir `
            -TargetName $target -BackgroundImage '' -BackgroundImageProvided $false
        Write-SettingsAtomic -Path $settingsPath -Json ($preview | ConvertTo-Json -Depth 100)
    }

    $bar = {
        param([int]$Value, [int]$Min, [int]$Max)
        $width = 10
        $pos = [int][Math]::Round(($Value - $Min) / [double]($Max - $Min) * ($width - 1))
        $pos = [Math]::Max(0, [Math]::Min($width - 1, $pos))
        $cells = (1..$width | ForEach-Object { if (($_ - 1) -eq $pos) { 'o' } else { '-' } }) -join ''
        return "[$cells]"
    }

    # The tuner's own chrome, derived from the background it is PREVIEWING.
    #
    # $drawMenu used to pass -ForegroundColor Cyan/DarkGray/Yellow/Gray, and
    # PowerShell maps those ConsoleColors onto SGR 96/90/93/37 -- brightCyan,
    # brightBlack, brightYellow and white, which are exactly the palette slots
    # the tuner has just retinted over OSC 4 on the previous keypress. So the
    # menu dyed itself with the colours being edited: on the bundled light theme
    # gitbash (#ffffff background, L clamped at 1.0 so the background cannot
    # move) the rows climbed into the background as brightness rose -- 1.482:1
    # at +20, and exactly 1.000:1 at +55, where the menu is invisible and the
    # user cannot read the slider they are dragging or find Esc.
    #
    # Truecolor SGR against the adjusted background instead, so the chrome is
    # always legible whatever the preview is doing. The hint line above has
    # always done this; this just covers the other four elements.
    $chrome = {
        param($Scheme)
        $bgHex = ConvertTo-NormalHex -Hex $Scheme.background
        $bg = @(0, 0, 0)
        if ($bgHex) {
            $h = $bgHex.TrimStart('#')
            $bg = @(0, 2, 4) | ForEach-Object { [Convert]::ToInt32($h.Substring($_, 2), 16) }
        }

        # Relative luminance, WCAG.
        $lumOf = {
            param($rgb)
            $c = $rgb | ForEach-Object {
                $v = $_ / 255.0
                if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) }
            }
            0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]
        }
        $bgLum = & $lumOf $bg

        # Two FIXED palettes chosen on a single `$lum -gt 0.5` bit is what this
        # replaced, and it only worked at the extremes. A background in the
        # middle of the range takes one branch or the other and neither has any
        # contrast against it: measured on the shipped code, gitbash at
        # brightness -55 gives #b9b9b9 (luminance 0.485), which selects the
        # DARK-background palette -- light-grey ink on light grey, 1.35:1 for
        # the row the user is dragging. forest +95, rain +85 and snowday +95
        # reached exactly 1.00:1. Every one of the 16 bundled styles has a
        # brightness where the menu disappeared.
        #
        # So fit each colour to THIS background instead of picking a preset:
        # keep the role's hue, then walk it toward whichever extreme is further
        # from the background until it clears the target ratio. The hue is
        # cosmetic; being readable is not.
        $fit = {
            param($rgb, $target)
            # Direction by which extreme actually has more headroom, NOT by
            # `is the background dark`. Those are different questions and the
            # difference is the whole bug: against a background at luminance
            # 0.485, walking toward white tops out at (1.05)/(0.485+0.05) =
            # 1.96:1 -- pure white is still barely legible -- while walking
            # toward black reaches (0.485+0.05)/0.05 = 10.7:1. A `-lt 0.5`
            # test sends the chrome the wrong way for every background between
            # about 0.18 and 0.5, which is exactly the mid band where the
            # shipped code lost the menu.
            #
            # The crossover is where the two ceilings meet:
            #   1.05/(L+0.05) = (L+0.05)/0.05  =>  L = sqrt(0.0525) - 0.05
            $ceilWhite = 1.05 / ($bgLum + 0.05)
            $ceilBlack = ($bgLum + 0.05) / 0.05
            $toWhite = ($ceilWhite -ge $ceilBlack)
            $best = $rgb
            for ($i = 0; $i -le 24; $i++) {
                $t = $i / 24.0
                $cand = $rgb | ForEach-Object {
                    if ($toWhite) { [int][Math]::Round($_ + (255 - $_) * $t) }
                    else          { [int][Math]::Round($_ * (1 - $t)) }
                }
                $l = & $lumOf $cand
                $hi = [Math]::Max($l, $bgLum); $lo = [Math]::Min($l, $bgLum)
                $best = $cand
                if ((($hi + 0.05) / ($lo + 0.05)) -ge $target) { break }
            }
            $best
        }

        $sgr = { param($rgb) "$([char]27)[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m" }
        # Selected row and title carry the most meaning, so they get the most
        # contrast; Dim is allowed to sit lower because it is supporting text.
        [pscustomobject]@{
            Title = (& $sgr (& $fit @(90, 200, 220) 7.0))
            Sel   = (& $sgr (& $fit @(250, 195, 70) 7.0))
            Row   = (& $sgr (& $fit @(160, 160, 160) 6.0))
            Dim   = (& $sgr (& $fit @(130, 130, 130) 4.5))
            Warn  = (& $sgr (& $fit @(240, 130, 60) 6.0))
            Reset = "$([char]27)[0m"
        }
    }

    $drawMenu = {
        Clear-Host
        Write-Host ""
        $ui = & $chrome $adjusted
        Write-Host "  Tuning " -NoNewline
        Write-Host "$($ui.Title)'$StyleName'$($ui.Reset)" -NoNewline
        Write-Host "$($ui.Dim)                      base: $baseName$($ui.Reset)"
        Write-Host "$hint  Up/Down select   Left/Right adjust   R reset color   Enter save   Esc cancel$reset"
        if ($baseChanged) {
            # Silence here read as "the tuner forgot my settings". It did not:
            # the base was re-baked under this style, so the saved deltas no
            # longer describe a distance from it and re-applying them would
            # double the tune.
            Write-Host "$($ui.Warn)  '$changedBaseName' has changed since this style was tuned -- starting from its current colours.$($ui.Reset)"
        }
        Write-Host ""
        $rows = @(
            @{ Label = 'Brightness'; Display = (& $bar $brightness -100 100); Value = ('{0:+#;-#;0}' -f $brightness) },
            @{ Label = 'Saturation'; Display = (& $bar $saturation -100 100); Value = ('{0:+#;-#;0}' -f $saturation) },
            @{ Label = 'Opacity';    Display = (& $bar $opacity 0 100);       Value = "$opacity%" },
            @{ Label = 'Font face';  Display = "< $fontFace >";                Value = '' },
            @{ Label = 'Font size';  Display = (& $bar $fontSize 6 36);        Value = "$fontSize" }
        )
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $color  = if ($i -eq $sel) { $ui.Sel } else { $ui.Row }
            $prefix = if ($i -eq $sel) { '   > ' } else { '     ' }
            Write-Host ($color + $prefix + ('{0,-12} ' -f $rows[$i].Label) +
                        ('{0,-14} ' -f $rows[$i].Display) + $rows[$i].Value + $ui.Reset)
        }
        Write-Host ""
        Write-Host "  Preview  " -NoNewline
        Write-Host (Get-SchemeSwatch -Scheme $adjusted)
        Write-Host ""
    }

    # On-disk rolling backup before any preview write, so a hard kill mid-tune
    # leaves a recoverable copy (the in-memory $originalJson snapshot dies with
    # the process). Same rolling .bak the direct-apply/reset paths write.
    # Crash-recovery copy -- only meaningful where a settings.json is written.
    # Same single writer as the picker and the direct apply.
    if ($tuneUsesSettings) {
        $resolvedForBackup = Resolve-WTProfileTarget -Settings $originalSettings -TargetName $target
        try { Save-SettingsBackup -Path $settingsPath -ResolvedTarget $resolvedForBackup -Quiet } catch { }
    }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle

    # Undo the live preview and put the terminal back the way it was found.
    #
    # Get-OscResetPacket hands colour control to the TERMINAL's own defaults,
    # which is right on Windows Terminal -- settings.json has just been restored
    # and WT repaints from it. Off Windows Terminal there is no such file: the
    # style being tuned was itself only escape sequences, so resetting drops the
    # user to a stock palette instead of the style they opened the tuner on.
    # Re-emit the unmodified base scheme there. Same fix, and the same reasoning,
    # as the picker's Esc.
    $restoreBaseLook = {
        if ($tuneUsesSettings) { Write-SettingsAtomic -Path $settingsPath -Json $originalJson }
        # $openedScheme, not $baseScheme: on a tuned style those are different
        # files, and the base is not what the user was looking at.
        if (-not $tuneUsesSettings -and $openedScheme) {
            [Console]::Out.Write((Get-SchemeOscPacket -Scheme $openedScheme))
        } else {
            [Console]::Out.Write((Get-OscResetPacket))
        }
    }
    $showPendingUpdate = {
        if ($pendingUpdate) {
            Write-Host ("  Update available ({0} -> {1}). Run: tstyles update" -f
                        $pendingUpdate.Installed, $pendingUpdate.Remote) -ForegroundColor Yellow
            Write-Host ""
        }
    }

    $needsRedraw = $true
    try {
        # Guarded like the other two call sites. The preview is a courtesy in
        # every position: what a save reads is the knob variables, not the
        # scratch style. Letting any of these throw unwinds the whole session
        # into the finally block, which reverts and discards everything tuned.
        try { & $writePreview } catch { }   # initial preview from seeds
        [Console]::Out.Write($oscPacket)

        while (-not $confirmed) {
            if ($needsRedraw) { & $drawMenu; $needsRedraw = $false }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $isColor = ($sel -eq 0 -or $sel -eq 1)
                switch ($key.Key) {
                    'UpArrow'   { if ($sel -gt 0) { $sel-- }; $needsRedraw = $true; continue }
                    'DownArrow' { if ($sel -lt 4) { $sel++ }; $needsRedraw = $true; continue }
                    'LeftArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Max(-100, $brightness - 5) }
                            1 { $saturation = [Math]::Max(-100, $saturation - 5) }
                            2 { $opacity    = [Math]::Max(0,    $opacity - 5) }
                            3 { $fontIdx = ($fontIdx - 1 + $fontList.Count) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Max(6, $fontSize - 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'RightArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Min(100, $brightness + 5) }
                            1 { $saturation = [Math]::Min(100, $saturation + 5) }
                            2 { $opacity    = [Math]::Min(100, $opacity + 5) }
                            3 { $fontIdx = ($fontIdx + 1) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Min(36, $fontSize + 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'R' {
                        $brightness = 0; $saturation = 0
                        $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness 0 -Saturation 0
                        $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                        [Console]::Out.Write($oscPacket)
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'Enter'  {
                        # The last preview is a courtesy -- the save that follows
                        # reads the knob variables, not the preview. Letting it
                        # throw here unwound past the Save/Save-As prompt and past
                        # Save-TunedStyle, so a failed settings.json write lost
                        # everything the user had just tuned. Commit to the save
                        # regardless.
                        if ($pendingApply) {
                            try { & $writePreview } catch { }
                            $pendingApply = $false
                        }
                        $confirmed = $true; continue
                    }
                    'Escape' {
                        & $restoreBaseLook
                        Clear-Host
                        Write-Host "Reverted." -ForegroundColor Yellow
                        & $showPendingUpdate
                        return
                    }
                }
                continue
            }

            # The debounced write -- this is the one that runs on EVERY knob
            # adjustment, so it is where a transient Write-SettingsAtomic
            # failure (another WT tab holding the file, OneDrive, antivirus, a
            # full disk) is actually likely. It was the one left unguarded.
            if ($pendingApply) { $pendingApply = $false; try { & $writePreview } catch { }; continue }
            Start-Sleep -Milliseconds 50
        }

        # --- Confirmed: Save / Save As prompt ---
        # Painted with the SAME fitted chrome as the menu. It used to use
        # -ForegroundColor Cyan/Gray, which PowerShell maps onto SGR 96/37 --
        # brightCyan and white, two of the palette slots the tuner has just
        # retinted over OSC. The 0.8.18 contrast fix stopped at $drawMenu, 160
        # lines above, so this screen kept the defect: on gitbash at +55 the
        # heading rendered at 1.25:1 and "Cancelled." at exactly 1.000:1. That
        # is the one screen where the user has to read a destructive prompt and
        # answer it, and declining looked identical to the tool doing nothing.
        #
        # The OSC retint is still live here -- the palette is only restored
        # later, in $restoreBaseLook -- so truecolor is the only safe way to
        # write on this screen.
        $saveUi = & $chrome $adjusted
        Clear-Host
        Write-Host ""
        Write-Host ($saveUi.Title + "  Save tuned '$StyleName'?" + $saveUi.Reset)

        # Which collision option [1] actually is depends on where this style
        # lives, and the two outcomes are not comparable. A BUNDLED style is
        # only shadowed: the original stays in the module and comes back if the
        # user copy is deleted. A style that exists ONLY in the user dir -- one
        # hand-authored per the README, or saved here earlier with Save As --
        # has no original to come back, so option [1] destroys it, with no
        # backup and no undo. The label said "(shadows the bundled style)"
        # unconditionally, which for that case asserted the exact opposite of
        # what was about to happen. Save As twenty lines below has drawn this
        # distinction since 0.8.x; option [1] never did.
        $overwriteUserDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $StyleName
        $overwriteReplaces = Test-Path -LiteralPath (Join-Path $overwriteUserDir 'scheme.json')
        $overwriteNote = if ($overwriteReplaces) { '(REPLACES your saved style)' }
                         else                    { '(shadows the bundled style)' }

        Write-Host "    [1] Overwrite '$StyleName'   $overwriteNote"
        Write-Host "    [2] Save as a new name"
        Write-Host ""
        $choice = (Read-Host "  Choose [1/2]").Trim()
        $saveName = $null
        if ($choice -eq '1') {
            # Gated the same way Save As gates the same outcome.
            if ($overwriteReplaces) {
                $warn = "$(Read-Host "  '$StyleName' will be replaced and cannot be undone. Continue? [y/N]")".Trim()
                if ($warn -notmatch '^(?i)y') {
                    Write-Host ($saveUi.Dim + "  Cancelled." + $saveUi.Reset)
                } else {
                    $saveName = $StyleName
                }
            } else {
                $saveName = $StyleName
            }
        } else {
            while (-not $saveName) {
                $candidate = (Read-Host "  New style name").Trim()
                if (-not $candidate) { Write-Host ($saveUi.Dim + "  Cancelled." + $saveUi.Reset); break }
                # Test-StyleNameValid, not a local regex: the character class on
                # its own still admits `.` and `..`, which are not names but
                # directories -- a save under either wrote the style's four
                # files into the styles dir itself (or its parent), producing
                # something `tstyles list` could never show -- and admits a name
                # long enough to throw a raw .NET path exception from inside
                # Save-TunedStyle, after the user had committed to the save.
                if (-not (Test-StyleNameValid -Name $candidate)) {
                    Write-Host ($saveUi.Warn + "  Use letters, digits, dot, underscore, or hyphen (max 64, and not '.' or '..')." + $saveUi.Reset)
                    continue
                }
                # Two different collisions, and only one of them loses work.
                #
                # A USER style of the same name is in the directory Save-TunedStyle
                # writes to, so saving over it destroys it -- and that was the case
                # with no warning at all. A BUNDLED style of the same name is only
                # shadowed: the original stays in the module and comes back if the
                # user style is deleted. The prompt used to warn about the harmless
                # one and stay silent about the destructive one.
                $userDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $candidate
                if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) {
                    $warn = "$(Read-Host "  '$candidate' already exists and will be REPLACED. Continue? [y/N]")".Trim()
                    if ($warn -notmatch '^(?i)y') { continue }
                } else {
                    $bundledDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $candidate
                    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) {
                        $warn = "$(Read-Host "  That shadows bundled '$candidate'. Continue? [y/N]")".Trim()
                        if ($warn -notmatch '^(?i)y') { continue }
                    }
                }
                $saveName = $candidate
            }
        }

        if (-not $saveName) {
            # Treat an aborted save like a cancel: revert and exit.
            & $restoreBaseLook
            Write-Host "  Reverted (nothing saved)." -ForegroundColor Yellow
            & $showPendingUpdate
            return
        }

        # Bake + persist, then apply the saved style from a clean settings.json
        # so no preview-scheme pollution lingers.
        $finalScheme = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        Save-TunedStyle -AdjustedScheme $finalScheme -SaveName $saveName `
            -BaseStyleDir $baseDir -BaseName $baseName `
            -Brightness $brightness -Saturation $saturation -Opacity $opacity `
            -FontFace $fontFace -FontSize $fontSize | Out-Null

        if ($tuneUsesSettings) { Write-SettingsAtomic -Path $settingsPath -Json $originalJson }
        # -Target is a Windows Terminal profile name; off WT it is $null and the
        # apply resolves the host terminal itself.
        #
        # $applied gates the finally block's revert, so it has to mean "the style
        # really went on", not "we reached this line". Apply-StyleDirect's failure
        # modes are all Write-Error, which is non-terminating: setting $applied
        # unconditionally meant a failed apply skipped the OSC reset and left the
        # tuner's preview colors painted over an already-restored settings.json.
        # Filtered on Activity, not just "any error": Apply-StyleDirect's three
        # give-up paths are Write-Error + return, and all three return before
        # touching anything. An incidental non-terminating error from a cmdlet
        # further in (the Copy-Item/Remove-Item that install current-style.ps1)
        # means the style DID go on, so counting it as failure would revert a
        # good apply -- the opposite bug.
        $applyErr = $null
        if ($tuneUsesSettings) { Apply-StyleDirect -StyleName $saveName -Target $target -ErrorVariable applyErr }
        else { Apply-StyleDirect -StyleName $saveName -ErrorVariable applyErr }
        $applied = -not @($applyErr | Where-Object { $_.CategoryInfo.Activity -eq 'Write-Error' }).Count
        # The third exit path. Esc and the aborted save print it too.
        & $showPendingUpdate
    } finally {
        [Console]::CursorVisible = $true
        if (-not $applied) {
            # Safety net: restore settings.json + title unless a saved style was
            # applied. Esc / aborted-save already reverted explicitly; this also
            # covers an exception thrown mid-session (the key loop is not tested).
            # $restoreBaseLook may not exist yet if something threw very early.
            if ($restoreBaseLook) { & $restoreBaseLook }
            $Host.UI.RawUI.WindowTitle = $originalTitle
        }
        # Recursive and forced, so prove the target is really under the scratch
        # root before running it. This block deleted a user's style directory
        # outright when the composed path resolved back onto styles/<name>.
        # The whole SESSION directory goes, not just the style inside it, so a
        # tuner run leaves nothing behind under .tune-preview.
        if (Test-Path -LiteralPath $scratchSession) {
            $sep  = [System.IO.Path]::DirectorySeparatorChar
            $safe = $false
            try {
                $full = [System.IO.Path]::GetFullPath($scratchSession).TrimEnd($sep)
                $root = [System.IO.Path]::GetFullPath($scratchRoot).TrimEnd($sep)
                $safe = $full.StartsWith($root + $sep, [System.StringComparison]::Ordinal)
            } catch { $safe = $false }
            if ($safe) {
                Remove-Item -LiteralPath $scratchSession -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
