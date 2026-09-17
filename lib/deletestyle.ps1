# deletestyle.ps1 -- `tstyles delete`, and the bundled-vs-yours question.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# The tuner makes creating a style a two-keystroke affair, and every result
# lands in the user styles dir as a full style that lists, tab-completes and
# shows in the picker. Until this file there was no way to remove one: the only
# path was `tstyles uninstall -DeleteData`, which destroys the whole data root.
#
# The hard part is not the removal, it is ANSWERING WHO OWNS A STYLE, and the
# obvious answer is wrong. See Get-StyleOrigin.

function Get-StyleTrashRoot {
    # Where a deleted style is kept. Same shape as Get-StyleCacheDir so there is
    # one place that knows the path. Dot-prefixed like .tune-preview, the
    # existing precedent for a private sibling of styles/.
    Join-Path $script:TStylesDataRoot '.deleted'
}

# How long a deleted style is kept. ONE definition: Get-StyleTrashEntry decides
# expiry from it, Get-StyleTrashSweepTarget filters that, and every message that
# quotes a number interpolates it. A literal in a message is a second answer to
# the same question, and the message is the half that goes stale -- "kept for 7
# days" outliving a changed window is this project's most-shipped defect class
# in one line.
$script:TStylesTrashKeepDays = 7

function Test-StylesRootsAreOne {
    <#
    .SYNOPSIS
    Are the bundled and user style directories the same directory?

    .DESCRIPTION
    On a BOOTSTRAP install they are. install.ps1 sets its install dir to
    Get-TStylesDataRoot, so $script:TStylesModuleRoot and
    $script:TStylesDataRoot are the same path and styles/ holds the sixteen
    bundled styles beside the user's own. That is the common case for this
    project and it is what makes the obvious ownership test wrong.

    NOT Get-TerminalStylesInstallKind: that compares against a freshly computed
    Get-TStylesDataRoot rather than the $script: variables, so it answers about
    the machine instead of about the roots actually in use, and reports
    'PSResourceGet' in any sandbox where the two script roots are identical.
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleStylesRoot = (Join-Path $script:TStylesModuleRoot 'styles'),
        [string]$DataStylesRoot   = (Join-Path $script:TStylesDataRoot   'styles')
    )
    Test-SameStyleDirectory -A $ModuleStylesRoot -B $DataStylesRoot
}

function Get-InstalledStyleClaim {
    <#
    .SYNOPSIS
    The style names the installer says it placed, or $null when it cannot say.

    .DESCRIPTION
    .installed-files carries one `styles/<name>` line per bundled style, which
    on a bootstrap install is the ONLY record of which styles came from the
    install and which the user made. Get-UninstallPlan (lib/update.ps1) already
    reads it for exactly this purpose, and already treats a style carrying
    tune.json as the user's regardless of what the manifest claims.

    $null -- not an empty list -- when the file is absent, unreadable, or
    contains no styles/ lines at all. The distinction is load-bearing: an empty
    CLAIM would mean "the installer placed no styles", so every bundled style
    would read as the user's and be offered for deletion. "Cannot say" must
    produce 'unknown', which is refused.
    #>
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:TStylesDataRoot '.installed-files'))

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))
    } catch { return $null }

    $names = @(foreach ($l in $lines) {
        $t = "$l".Trim().TrimEnd('/', '\')
        if ($t -match '^styles[\\/]([^\\/]+)$') { $Matches[1] }
    })
    if ($names.Count -eq 0) { return $null }
    return $names
}

function Test-PathIsUnderRoot {
    <#
    .SYNOPSIS
    Is $Path inside $Root -- at any depth?

    .DESCRIPTION
    The containment rule itself, in ONE place. It was written three times: as
    the front half of Test-PathIsStyleDirChild (the proof in front of the
    style delete), open-coded again inside Get-StyleOrigin's split-root branch
    to decide whether a style resolved out of the user root, and a third time
    in the tuner in front of the recursive delete of its scratch session. Two
    implementations of one rule diverge -- the whole of CHANGELOG is that shape
    -- and this one decides who owns a directory and whether it may be erased.
    The three had already drifted: a path GetFullPath refuses left the other two
    answering $false through their own catch, while this one's caller threw a
    raw binding error before reaching any of that.

    Both properties are load-bearing and both come from the separator:
    GetFullPath normalises `<root>/../styles/eva` and `<root>/eva/..` before
    anything is compared, and requiring `<root><sep>` rather than `<root>`
    keeps a character-prefix SIBLING (`<root>X/eva`) out -- the same boundary
    bug the prompt halves had against $HOME.

    Returns $true/$false; never throws: it is a guard, and a guard that throws
    on the input it exists to reject is not a guard. An empty or null path is
    not inside anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $sep  = [System.IO.Path]::DirectorySeparatorChar
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep)
        $root = [System.IO.Path]::GetFullPath($Root).TrimEnd($sep)
        return $full.StartsWith($root + $sep, [System.StringComparison]::Ordinal)
    } catch { return $false }
}

function Get-StyleOrigin {
    <#
    .SYNOPSIS
    'bundled' | 'shadow' | 'yours' | 'unknown' for one style.

    .DESCRIPTION
    The obvious test -- "is its FullName under the data root" -- is WRONG, and
    wrong in the most common layout. On a bootstrap install the module root IS
    the data root, so every bundled style's path is under the data root too: a
    path-prefix test reports all sixteen as the user's, which would badge them
    as yours and offer to delete them.

    So the question is answered differently per layout:

      SPLIT roots (PSGallery install: module dir separate from data dir)
        the directory tells the truth. A style resolved out of the user root is
        yours; one resolved out of the module root is bundled; a user style whose
        name also exists bundled is a SHADOW -- deleting it reveals the original
        rather than removing the name. The manifest is still consulted first,
        because a coexisting bootstrap install puts SHIPPED styles in the data
        root and the path alone would call all sixteen of them the user's.

      ONE root (bootstrap)
        the directory says nothing, so ask the install manifest, which lists what
        it placed. A style it does not claim is yours. A style it does claim is
        bundled -- UNLESS Test-StyleDirectoryIsUsers says the user has made it
        theirs, which is how Get-UninstallPlan and install.ps1's styles merge
        already decide the same question (an Overwrite save writes a tuned style
        under a bundled name; a hand-dropped override writes no marker at all
        and is caught by the install's content record instead).
        With no usable manifest there is no evidence either way, and the answer
        is 'unknown': never claim ownership the tool cannot prove, and never
        delete on a guess.

    -Claim, -RootsAreOne and -StyleHash are seams: tests drive them directly,
    and Show-StyleList reads the manifest once for the whole listing rather than
    once per row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StyleDir,
        $Claim = '__unset__',
        $RootsAreOne = $null,
        $StyleHash = '__unset__'
    )

    if ($Claim -is [string] -and $Claim -eq '__unset__') { $Claim = Get-InstalledStyleClaim }
    if ($null -eq $RootsAreOne) { $RootsAreOne = Test-StylesRootsAreOne }
    if ($StyleHash -is [string] -and $StyleHash -eq '__unset__') {
        $StyleHash = Get-InstalledStyleHash -DataDir $script:TStylesDataRoot
    }

    # The third reader of one rule. It used to be a bare tune.json test here, a
    # second one in Get-UninstallPlan and a third in install.ps1's styles merge
    # -- all three agreeing about the tuner's Overwrite save and all three
    # silent about the hand-dropped override README documents, which is why
    # `tstyles list` badged it 'bundled' and `tstyles delete` refused it while
    # `tstyles update` quietly reverted it.
    $isUsers = Test-StyleDirectoryIsUsers -StyleDir $StyleDir -Recorded $StyleHash

    if (-not $RootsAreOne) {
        # Through the shared guard, not a second copy of it. This branch used
        # to open-code the same GetFullPath/TrimEnd/StartsWith computation that
        # Test-PathIsStyleDirChild makes in front of the delete, minus the
        # direct-child test -- two implementations of one containment rule,
        # one deciding ownership and one deciding whether a directory may be
        # moved to the trash.
        $userRoot = Join-Path $script:TStylesDataRoot 'styles'
        $inUser = Test-PathIsUnderRoot -Path $StyleDir -Root $userRoot

        if (-not $inUser) { return 'bundled' }

        # Sitting in the user root is not proof the USER put it there, and the
        # manifest in that same directory already knows which of us did.
        #
        # A bootstrap install writes its whole tree -- styles/ included -- into
        # what is also the data root, and README documents that a bootstrap and
        # a PSGallery install can coexist. When they do, the module root is the
        # versioned PSGallery directory and every SHIPPED style resolves out of
        # the data root instead, so all sixteen looked exactly like styles the
        # user had made: `tstyles list` badged them 'yours (shadows bundled)'
        # and `tstyles delete eva` offered to move eva to the trash, saying
        # 'your style'. `tstyles uninstall` on the PSGallery side leaves that
        # state behind, so it is reachable without ever installing twice on
        # purpose.
        #
        # A copy the user has made theirs is still theirs: an Overwrite save
        # writes tune.json under a bundled name, a hand-dropped override changes
        # the shipped content, and 'shadow' already says "yours, shadowing
        # bundled". Only a style the installer admits placing AND still
        # recognises is reclassified. With no manifest $Claim is $null, not an
        # empty list, so an ordinary PSGallery install -- where the data root
        # holds only what the user made -- keeps deciding by path as before.
        if (-not $isUsers -and $null -ne $Claim -and ($Claim -contains $Name)) {
            return 'bundled'
        }

        $bundledTwin = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $Name
        if (Test-Path -LiteralPath (Join-Path $bundledTwin 'scheme.json')) { return 'shadow' }
        return 'yours'
    }

    # One root: the path cannot distinguish anything.
    if ($isUsers) { return 'yours' }
    if ($null -eq $Claim) { return 'unknown' }
    if ($Claim -contains $Name) { return 'bundled' }
    return 'yours'
}

function Get-StyleTuneChild {
    <#
    .SYNOPSIS
    Styles whose tune.json names $StyleDir as their base.

    .DESCRIPTION
    Their recorded brightness/saturation are DELTAS against this style. If it
    goes and nothing else provides the name, those numbers are not written down
    anywhere else -- so the user has to be told before confirming, by name and
    by value.

    KeepsAdjustments is what the delete actually does to this child, decided
    here rather than guessed by the printer. It is false whenever the name goes
    -- the base stops resolving, so the deltas are dropped -- and when the name
    REVERTS to a bundled style it is the fingerprint question:
    Test-TuneBaseMoved against -RevealDir, the same comparison Resolve-TuneSeed
    will make the next time the child is tuned.

    HasFingerprint matters for the wording: a child with no baseFingerprint
    gets no "the base changed" notice on its next tune, so its adjustments
    change meaning with nothing on screen to explain it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleDir,
        # Where the name will resolve after the delete, when it survives at all
        # (a shadow reverting to its bundled original). Empty means the name
        # goes with the style.
        [AllowEmptyString()][AllowNull()][string]$RevealDir
    )

    $out = @()
    foreach ($s in (Get-AvailableStyles)) {
        if (Test-SameStyleDirectory -A $s.FullName -B $StyleDir) { continue }
        $tunePath = Join-Path $s.FullName 'tune.json'
        if (-not (Test-Path -LiteralPath $tunePath)) { continue }
        try {
            $t = [System.IO.File]::ReadAllText($tunePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        } catch { continue }
        if (-not $t.base) { continue }
        $baseDir = Get-StyleDir -StyleName ([string]$t.base)
        if (-not $baseDir) { continue }
        if (-not (Test-SameStyleDirectory -A $baseDir -B $StyleDir)) { continue }
        $recordedFp = $(if ($t.PSObject.Properties.Match('baseFingerprint').Count) { [string]$t.baseFingerprint } else { '' })
        $out += [pscustomobject]@{
            Name             = $s.Name
            Brightness       = $(if ($t.PSObject.Properties.Match('brightness').Count) { [int]$t.brightness } else { 0 })
            Saturation       = $(if ($t.PSObject.Properties.Match('saturation').Count) { [int]$t.saturation } else { 0 })
            HasFingerprint   = [bool]$recordedFp
            KeepsAdjustments = $(if ($RevealDir) {
                                     -not (Test-TuneBaseMoved -RecordedFingerprint $recordedFp -BaseDir $RevealDir)
                                 } else { $false })
        }
    }
    return @($out)
}

function Test-PathIsStyleDirChild {
    <#
    .SYNOPSIS
    Is $Path a direct child of the user styles directory?

    .DESCRIPTION
    Proof before a move, not trust in how the path was built. Same reasoning as
    the tuner's scratch-directory guard: `tstyles tune ../styles/eva` once
    deleted a real style because a composed path was assumed to be inside the
    directory it was composed from.

    Returns $true/$false; never throws -- including for an empty or null path.
    #>
    [CmdletBinding()]
    param(
        # Empty and null are ALLOWED so they can be ANSWERED. Without these two
        # attributes the parameter binder threw
        # "Cannot bind argument to parameter 'Path' because it is an empty
        # string" before a line of the guard ran -- a raw binding error out of
        # the containment proof that stands in front of a Move-Item and a
        # recursive Remove-Item, where the only safe answer to "is '' a style
        # directory?" is $false. The two sibling guards this one is modelled on
        # (Test-StyleNameIsSingleSegment, Test-StyleNameValid) carry both
        # attributes and both promise never to throw; this one promised nothing
        # and was covered by no test at all.
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Path,
        [string]$Root = (Join-Path $script:TStylesDataRoot 'styles')
    )
    # The containment half is Test-PathIsUnderRoot's, so the rule lives in one
    # place; only the direct-child half is decided here.
    if (-not (Test-PathIsUnderRoot -Path $Path -Root $Root)) { return $false }
    try {
        $sep  = [System.IO.Path]::DirectorySeparatorChar
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep)
        $root = [System.IO.Path]::GetFullPath($Root).TrimEnd($sep)
        # A direct child, not something nested deeper.
        return ([System.IO.Path]::GetDirectoryName($full).TrimEnd($sep) -eq $root)
    } catch { return $false }
}

function Get-StyleDeletePlan {
    <#
    .SYNOPSIS
    Everything the confirmation needs, decided before anything is touched.

    .DESCRIPTION
    Pure: reads the disk, writes nothing. That makes the whole decision -- what
    is about to happen, what survives, what does not -- unit-testable without a
    single mutation, which is the part of a destructive command worth testing.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Name, $Claim = '__unset__', $RootsAreOne = $null)

    $plan = [pscustomobject]@{
        Ok = $false; Reason = $null; Name = $Name; Dir = $null; Origin = $null
        IsLink = $false; RevealDir = $null; WasActive = $false
        Children = @(); KeptCache = $null; KeptProfile = $null
        TrashPath = $null; Consequence = $null; SweepTargets = @()
    }

    # Before Get-StyleDir: its parameter is a Mandatory [string], so an empty
    # name throws a raw binding error rather than returning $null.
    if ([string]::IsNullOrWhiteSpace($Name)) { $plan.Reason = 'noname'; return $plan }

    $dir = Get-StyleDir -StyleName $Name
    if (-not $dir) { $plan.Reason = 'notfound'; return $plan }
    $plan.Dir = $dir

    if ($Claim -is [string] -and $Claim -eq '__unset__') { $Claim = Get-InstalledStyleClaim }
    if ($null -eq $RootsAreOne) { $RootsAreOne = Test-StylesRootsAreOne }
    $plan.Origin = Get-StyleOrigin -Name $Name -StyleDir $dir -Claim $Claim -RootsAreOne $RootsAreOne

    if ($plan.Origin -eq 'bundled') { $plan.Reason = 'bundled'; return $plan }
    if ($plan.Origin -eq 'unknown') { $plan.Reason = 'unknown'; return $plan }

    if (-not (Test-PathIsStyleDirChild -Path $dir)) { $plan.Reason = 'outside'; return $plan }

    try {
        $item = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
        $plan.IsLink = [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    } catch { }

    # Shadow: the name survives, revealing the bundled original.
    if ($plan.Origin -eq 'shadow') {
        $plan.RevealDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $Name
    } elseif ($RootsAreOne -and ($Claim -ne $null) -and ($Claim -contains $Name)) {
        # One root, manifest claims the name, but the user has made it theirs
        # -- a tuner Overwrite save, or the hand-dropped override README
        # documents. There is only ONE directory of that name on this layout, so
        # removing it leaves nothing behind; `tstyles update` restores the
        # shipped copy under that name.
        $plan.RevealDir = $null
    }

    # Captured BEFORE the move: Get-CurrentStyleName answers differently
    # afterwards, and in opposite directions depending on whether the name
    # survives.
    try { $plan.WasActive = ((Get-CurrentStyleName) -eq $Name) } catch { }

    # After RevealDir on purpose: what a tuned child keeps depends on whether
    # the name survives the delete, and on what it resolves to if it does.
    $plan.Children = @(Get-StyleTuneChild -StyleDir $dir -RevealDir $plan.RevealDir)

    $cache = Get-StyleCacheDir -StyleName $Name
    if (Test-Path -LiteralPath $cache) { $plan.KeptCache = $cache }
    $prof = Join-Path (Join-Path $script:TStylesDataRoot 'profiles') "$Name.terminal"
    if (Test-Path -LiteralPath $prof) { $plan.KeptProfile = $prof }

    # What confirming this delete will also erase for good.
    $plan.SweepTargets = @(Get-StyleTrashSweepTarget)

    # InvariantCulture, because Get-StyleTrashTimestamp reads this back with it.
    # `Get-Date -Format` formats through CurrentCulture, and therefore through
    # that culture's DEFAULT CALENDAR: under ar-SA (UmAlQura) today stamps as
    # 14480326 and under fa-IR (Persian) as 14050617, both of which parse
    # cleanly as Gregorian years ~580 in the past -- so the folder was already
    # expired the instant it was created, and the next delete of any style
    # erased it having just printed "Kept for 7 days". th-TH (ThaiBuddhist)
    # fails the other way, stamping 2569 and making the trash unsweepable.
    #
    # The name still matched the reader's `-(\d{8})-(\d{6})$` pattern, so the
    # "no stamp -- fall back to LastWriteTime" escape hatch never engaged. Only
    # the reader had been pinned; this is the other half of that pair.
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)
    $plan.TrashPath = Join-Path (Get-StyleTrashRoot) "$Name-$stamp"

    $plan.Consequence = if ($plan.RevealDir) {
        "moves your '$Name' aside; the name reverts to the bundled style"
    } else {
        "moves '$Name' aside; nothing else provides that name"
    }
    $plan.Ok = $true
    return $plan
}

function Get-StyleTrashEntry {
    <#
    .SYNOPSIS
    What is in the trash right now: one row per deleted style, with how long it
    has left.

    .DESCRIPTION
    The trash was write-only. `tstyles delete` printed the folder it had just
    moved a style into, and after that scrollback line nothing in the tool could
    say what was in there, when it went, or how much of its window was left --
    while the next delete of any style erased everything past it. A user who
    deleted a style, stopped deleting and came back a month later had a folder
    no command would list and no command would clear. Measured: `tstyles list`,
    `tstyles current` and every other subcommand said nothing about an expired
    entry sitting on disk, and `tstyles trash` did not exist to ask.

    Pure -- it reads the trash root and writes nothing -- so the listing can be
    printed without touching anything, exactly like Get-StyleTrashSweepTarget,
    which is now a FILTER over this: the window is decided in one place.

    No -KeepDays parameter, for the reason the sweep's own comment gives: a
    second place to set the window is a second answer to disagree with the
    first. $script:TStylesTrashKeepDays is that place.

    Newest deletion first, which is also the order `tstyles restore` resolves a
    repeated name in.
    #>
    [CmdletBinding()]
    param([datetime]$Now = (Get-Date))

    $trashRoot = Get-StyleTrashRoot
    if (-not (Test-Path -LiteralPath $trashRoot)) { return @() }

    $rows = foreach ($d in @(Get-ChildItem -LiteralPath $trashRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        # The same containment proof the sweep insists on. Something nested
        # deeper, or reached through a link, is not a folder this tool put here,
        # and neither listing it as recoverable nor offering to move it is honest.
        if (-not (Test-PathIsStyleDirChild -Path $d.FullName -Root $trashRoot)) { continue }

        $deletedAt = Get-StyleTrashTimestamp -Name $d.Name -Fallback $d.LastWriteTime
        $expiresAt = $deletedAt.AddDays($script:TStylesTrashKeepDays)

        # The name WITHOUT the stamp this tool appended. A restore lands at
        # styles/<StyleName>: the stamped name must never reach styles/, where
        # it would be a directory no listing shows under the name the user is
        # looking for and the next delete of the real name would not touch.
        # Same anchored pattern Get-StyleTrashTimestamp reads, so a style called
        # `solarized-2024` keeps its digits.
        $styleName = [regex]::Replace($d.Name, '-(\d{8})-(\d{6})$', '')
        if ([string]::IsNullOrWhiteSpace($styleName)) { $styleName = $d.Name }

        [pscustomobject]@{
            Name      = $d.Name
            StyleName = $styleName
            Path      = $d.FullName
            DeletedAt = $deletedAt
            ExpiresAt = $expiresAt
            # -lt, matching the sweep's `$deletedAt -ge $cutoff` exactly:
            # deleted-at + window < now is the same comparison, moved.
            Expired   = ($expiresAt -lt $Now)
            DaysLeft  = [int][math]::Ceiling(($expiresAt - $Now).TotalDays)
            # A folder with no scheme.json restores to something Get-StyleDir
            # cannot resolve and no listing can show. Carried so the restore can
            # say that instead of reporting a style.
            IsStyle   = (Test-Path -LiteralPath (Join-Path $d.FullName 'scheme.json'))
            # Whether the name is free to restore INTO. Asked of the user styles
            # dir, not of Get-StyleDir: a trashed style that shadowed a bundled
            # one restores over nothing, and refusing that would refuse the
            # shadow case the delete plan goes out of its way to explain.
            NameFree  = -not (Test-Path -LiteralPath (Join-Path (Join-Path $script:TStylesDataRoot 'styles') $styleName))
            # The DirectoryInfo itself, so the sweep keeps the object it needs
            # for the ReparsePoint test rather than re-enumerating the disk.
            Item      = $d
        }
    }
    @($rows | Sort-Object -Property DeletedAt -Descending)
}

function Get-StyleTrashSweepTarget {
    <#
    .SYNOPSIS
    The trashed styles the next delete will remove for good.

    .DESCRIPTION
    The sweep decided this inline, so the only way to find out what a delete was
    about to erase was to let it erase them. The consent listing therefore could
    not mention it, and ended on "Nothing is erased: move the folder back to
    undo." -- while pressing y ran a recursive Remove-Item over every trashed
    style past the window. Measured: a style deleted weeks earlier and still
    recoverable was gone the moment the user confirmed the deletion of an
    unrelated one, having been told nothing would be.

    Bounded trash is the point of the feature; the listing not saying so was the
    defect. Pure -- it reads the trash root and writes nothing -- so the prompt
    can name the folders before the question is asked, and
    Move-StyleDirectoryToTrash sweeps exactly what was named because the rule
    lives here rather than in both.

    A filter over Get-StyleTrashEntry, which is the same argument one level up:
    `tstyles trash` prints the window to the user and this erases by it, so the
    two must not each own a copy of the comparison. -KeepDays is gone with the
    duplicate -- nothing ever passed it, and a per-call window is exactly the
    second answer this docstring argues against.

    Returns the DirectoryInfo rows, not the entries: Move-StyleDirectoryToTrash
    tests .Attributes for a ReparsePoint before deleting, and Show-StyleDeletePlan
    prints .Name. Projected with ForEach-Object, since member access on an empty
    array yields one $null.
    #>
    [CmdletBinding()]
    param([datetime]$Now = (Get-Date))

    @(Get-StyleTrashEntry -Now $Now | Where-Object { $_.Expired } | ForEach-Object { $_.Item })
}

function Show-StyleDeletePlan {
    # Everything that is about to happen, itemised, before the question is
    # asked. Colours follow Invoke-TerminalStylesUninstall: Yellow for actions,
    # RED only for what does not come back, Gray for what is kept.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    Write-Host ""
    Write-Host "This will delete your style '$($Plan.Name)':" -ForegroundColor Yellow
    Write-Host "  - MOVE $($Plan.Dir)" -ForegroundColor Yellow
    Write-Host "      to $($Plan.TrashPath)" -ForegroundColor Yellow

    if ($Plan.RevealDir) {
        Write-Host "  - The name '$($Plan.Name)' STAYS: it reverts to the bundled '$($Plan.Name)'" -ForegroundColor Gray
    } else {
        Write-Host "  - The name '$($Plan.Name)' GOES: nothing else provides it" -ForegroundColor Yellow
    }

    if ($Plan.WasActive) {
        if ($Plan.RevealDir) {
            Write-Host "  - RE-APPLY the bundled '$($Plan.Name)' now, because yours is the active style" -ForegroundColor Yellow
        } else {
            Write-Host "  - RESET the terminal to its unstyled default, because '$($Plan.Name)' is active" -ForegroundColor Yellow
        }
    }

    # On KeepsAdjustments, not on which branch of the delete this is. A child
    # keeps its deltas only where the base its fingerprint was taken from is
    # still what the name resolves to, so the reveal branch said "same
    # brightness/saturation" in Gray while the tuner dropped them to 0, for
    # every child saved since the fingerprint was introduced.
    foreach ($c in $Plan.Children) {
        if ($c.KeepsAdjustments) {
            Write-Host ("  - '{0}' was tuned from this style and re-seeds from the bundled one: same brightness/saturation, different colours" -f $c.Name) -ForegroundColor Gray
            if (-not $c.HasFingerprint) {
                Write-Host ("      it records no base fingerprint, so its next tune will not mention the change") -ForegroundColor DarkGray
            }
        } else {
            Write-Host ("  - '{0}' loses the brightness {1:+#;-#;0} and saturation {2:+#;-#;0} it was tuned by" -f $c.Name, $c.Brightness, $c.Saturation) -ForegroundColor Red
            if ($Plan.RevealDir) {
                Write-Host ("      they were measured against your '{0}', not the bundled one; nothing else records them, and its own colours do not change" -f $Plan.Name) -ForegroundColor DarkGray
            } else {
                Write-Host ("      nothing else records those values") -ForegroundColor DarkGray
            }
        }
    }

    if ($Plan.KeptCache)   { Write-Host "  - KEEP $($Plan.KeptCache)" -ForegroundColor Gray }
    if ($Plan.KeptProfile) { Write-Host "  - KEEP $($Plan.KeptProfile)" -ForegroundColor Gray }
    if ($Plan.IsLink) {
        Write-Host "  - This style is a symlink; only the link is moved, its target is untouched" -ForegroundColor Gray
    }
    # RED, because this is the one thing on the list that does not come back.
    foreach ($sw in $Plan.SweepTargets) {
        Write-Host ("  - ERASE {0}, deleted over {1} days ago" -f $sw.Name, $script:TStylesTrashKeepDays) -ForegroundColor Red
    }
    if ($Plan.SweepTargets.Count -gt 0) {
        Write-Host "      the trash keeps $($script:TStylesTrashKeepDays) days; this delete is what clears the rest" -ForegroundColor DarkGray
        Write-Host "      tstyles trash lists them, with the days each has left" -ForegroundColor DarkGray
    }
    # Scoped to THIS style. Unqualified, it was the opposite of what the line
    # above describes. It named the undo as a file-manager move because that was
    # the only undo there was; `tstyles restore` is the one the tool performs.
    Write-Host "  - Nothing of '$($Plan.Name)' is erased: tstyles restore $($Plan.Name) puts it back." -ForegroundColor Gray
    Write-Host ""
}

function Get-StyleTrashTimestamp {
    <#
    .SYNOPSIS
    When was this trashed style deleted? Read from its folder name, not its
    LastWriteTime.

    .DESCRIPTION
    The sweep used $old.LastWriteTime as the deletion time. Move-Item renames
    within the data root, and a rename does not touch the directory's
    LastWriteTime -- so that timestamp is when the STYLE was last edited, which
    is the one thing it cannot be. A style tuned once and left alone for a month
    arrived in the trash already a month stale, and the next `tstyles delete` of
    any style swept it on the spot, seconds after "Kept for 7 days at ..." said
    otherwise. The longer a style had gone untouched -- the better the reason to
    want it back -- the less of the promised window it actually got, and a style
    edited today got the full seven days.

    Get-StyleDeletePlan already stamps the trash folder name with the deletion
    time (`<name>-yyyyMMdd-HHmmss`), so the answer was on disk the whole time.
    Reading it from the name also means the sweep never has to WRITE to the
    trashed item to keep its own clock: stamping LastWriteTime would follow a
    symlinked style dir and modify the link's target, the exact thing
    Move-StyleDirectoryToTrash moves-as-a-link to avoid.

    Anything whose name does not carry a stamp -- trash from before this, or a
    folder some other hand put there -- falls back to LastWriteTime, which is
    the previous behaviour rather than a folder that can never be swept.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][datetime]$Fallback
    )

    # [regex]::Match rather than -match: the automatic $Matches is shared state,
    # and the suite has already been bitten once by code that wrote to it.
    $m = [regex]::Match($Name, '-(\d{8})-(\d{6})$')
    if ($m.Success) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact(($m.Groups[1].Value + $m.Groups[2].Value),
                                      'yyyyMMddHHmmss',
                                      [cultureinfo]::InvariantCulture,
                                      [System.Globalization.DateTimeStyles]::None,
                                      [ref]$parsed)) {
            return $parsed
        }
    }
    return $Fallback
}

function Move-StyleDirectoryToTrash {
    <#
    .SYNOPSIS
    Move the style aside. Never a recursive delete of a live style directory.

    .DESCRIPTION
    A rename within the data root, not Remove-Item -Recurse, and the choice
    carries three separate safety properties: it is reversible; it cannot leave
    a half-removed directory (removing scheme.json first makes a style
    invisible to BOTH Get-AvailableStyles and Get-StyleDir while its other
    files sit on disk); and it moves a symlinked style dir as a link rather
    than descending into the target, which Windows PowerShell 5.1's recursive
    delete is known to do.

    Old trash is swept here rather than by a separate command, so the store
    cannot grow without bound -- the very complaint this feature exists to fix.

    The reversible step runs FIRST and the irreversible one LAST. It was the
    other way round, so every ordinary way the move can fail -- the folder open
    in an editor on Windows, a permissions failure, the style removed by hand or
    by a second terminal between the plan and the keystroke -- still erased the
    expired trash for good, while the only thing printed was that the style
    could NOT be deleted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $trashRoot = Get-StyleTrashRoot

    # Re-prove containment at the moment of the move, not just when the plan
    # was built.
    if (-not (Test-PathIsStyleDirChild -Path $Plan.Dir)) {
        throw "Refusing to move '$($Plan.Dir)': it is not a style directory under the data root."
    }
    if (-not (Test-Path -LiteralPath $trashRoot)) {
        New-Item -ItemType Directory -Path $trashRoot -Force | Out-Null
    }

    Move-Item -LiteralPath $Plan.Dir -Destination $Plan.TrashPath -ErrorAction Stop

    if ((Test-Path -LiteralPath $Plan.Dir) -or -not (Test-Path -LiteralPath $Plan.TrashPath)) {
        throw "Move did not complete: '$($Plan.Dir)' -> '$($Plan.TrashPath)'."
    }

    # Only now, with the move verified: a delete that did not happen erases
    # nothing.
    #
    # Sweep the list the user was SHOWN, off the plan -- not a fresh one.
    # Calling Get-StyleTrashSweepTarget again here would re-read the clock AFTER
    # the prompt, and Confirm-Action blocks for as long as the user takes to
    # read it: a folder sitting at six days and twenty-three hours when the
    # listing was drawn crosses the window while they decide, and confirming
    # erases it having never named it. That is this same defect one step later,
    # and it is why the window is not a parameter here -- a second place to set
    # it is a second answer to disagree with the first.
    #
    # A plan carrying no SweepTargets sweeps nothing, which is the safe
    # direction to fail: the trash grows rather than losing something unnamed.
    foreach ($old in @($Plan.SweepTargets)) {
        try {
            if ($old.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                [System.IO.Directory]::Delete($old.FullName, $false)
            } else {
                Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction Stop
            }
        } catch { }
    }
}

function Show-StyleTrashList {
    <#
    .SYNOPSIS
    `tstyles trash` -- what is in the trash, and what the next delete erases.

    .DESCRIPTION
    Read-only, on purpose. The erasure keeps the one consent screen it already
    has -- the delete plan, which names every expired folder in red before the
    question is asked -- and this command exists so that screen is not the only
    place the state is ever visible. It erases nothing itself.

    Colours follow Show-StyleDeletePlan: RED for what does not come back.
    #>
    [CmdletBinding()]
    param()

    $entries = @(Get-StyleTrashEntry)

    Write-Host ""
    if (-not $entries) {
        Write-Host "  The trash is empty." -ForegroundColor Gray
        Write-Host "  Deleting a style moves it here for $($script:TStylesTrashKeepDays) days: tstyles delete <name>" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # A name can be in here twice -- deleted, made again, deleted again -- and
    # `tstyles restore <name>` puts back exactly one of them. Saying which is
    # the difference between a listing and a listing you can act on.
    $repeated = @($entries | Group-Object -Property StyleName |
        Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    $newestSeen = @{}

    Write-Host "Deleted styles:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($e in $entries) {
        $when = $e.DeletedAt.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
        if ($e.Expired) {
            Write-Host ("    {0,-16}  deleted {1}  EXPIRED -- the next delete erases it" -f $e.StyleName, $when) -ForegroundColor Red
        } else {
            $left = if ($e.DaysLeft -eq 1) { '1 day left' } else { "$($e.DaysLeft) days left" }
            Write-Host ("    {0,-16}  deleted {1}  {2}" -f $e.StyleName, $when, $left)
        }
        if ($repeated -contains $e.StyleName) {
            # Newest first, so the first row of a group is the one restore takes.
            if (-not $newestSeen.ContainsKey($e.StyleName)) {
                $newestSeen[$e.StyleName] = $true
                Write-Host ("      folder {0} -- the copy 'tstyles restore {1}' puts back" -f $e.Name, $e.StyleName) -ForegroundColor DarkGray
            } else {
                Write-Host ("      folder {0} -- an older copy of the same name; move it back by hand" -f $e.Name) -ForegroundColor DarkGray
            }
        }
        if (-not $e.NameFree) {
            Write-Host ("      a style called '{0}' exists again, so restoring refuses until that one is renamed or deleted" -f $e.StyleName) -ForegroundColor DarkGray
        }
        if (-not $e.IsStyle) {
            Write-Host ("      no scheme.json in it: restored, nothing would list it") -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  Put one back with: tstyles restore <name>" -ForegroundColor DarkGray
    Write-Host "  Kept for $($script:TStylesTrashKeepDays) days under $(Get-StyleTrashRoot)" -ForegroundColor DarkGray
    Write-Host "  Nothing here is erased until the next tstyles delete, which lists what it takes." -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-TerminalStyleRestore {
    <#
    .SYNOPSIS
    `tstyles restore [name]` -- put a deleted style back.

    .DESCRIPTION
    The reverse of the move Move-StyleDirectoryToTrash makes, and deliberately
    only that: it moves the folder back and touches nothing else. The delete's
    other halves -- the reset or re-apply it ran, the cache and Terminal.app
    profile it KEPT -- are not undone here, because two of them were never
    changed and the third is the user's current terminal, which this command has
    no business repainting.

    Nothing is overwritten. If the name is in use again the restore REFUSES: the
    folder standing there is a style the user has since made, and no consent was
    given to spend it. That is what makes this safe to run without a prompt.

    Returns a STATUS, not a boolean -- 'restored' / 'noname' / 'none' / 'taken'
    / 'outside' / 'failed' -- the convention Unregister-ShellLoader established
    here after "it failed" and "there was nothing to do" became the same answer
    and the user was told the opposite of the truth.

    The timestamp is stripped unconditionally: see Get-StyleTrashEntry.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        # Same shape as `tstyles delete` with no name: show what the command can
        # act on rather than an error about the argument.
        Show-StyleTrashList
        return 'noname'
    }

    # The segment gate, not the stricter create-time one -- a trashed style is
    # whatever folder name the user chose, and this resolves an existing one.
    if (-not (Test-StyleNameIsSingleSegment -Name $Name)) {
        Write-Host "'$Name' is not a style name." -ForegroundColor Yellow
        return 'outside'
    }

    $entry = @(Get-StyleTrashEntry | Where-Object { $_.StyleName -eq $Name }) | Select-Object -First 1
    if (-not $entry) {
        Write-Host "Nothing in the trash under '$Name'." -ForegroundColor Yellow
        Write-Host "  tstyles trash      lists what is in there" -ForegroundColor DarkGray
        return 'none'
    }

    $dest = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $entry.StyleName
    if (Test-Path -LiteralPath $dest) {
        Write-Host "'$($entry.StyleName)' is taken -- something already lives at" -ForegroundColor Yellow
        Write-Host "  $dest" -ForegroundColor Yellow
        Write-Host "  Refusing rather than overwriting it. Rename or delete that one first;" -ForegroundColor DarkGray
        Write-Host "  the trashed copy stays where it is:" -ForegroundColor DarkGray
        Write-Host "  $($entry.Path)" -ForegroundColor DarkGray
        return 'taken'
    }

    # Containment re-proved at the moment of the move, on BOTH ends, rather than
    # trusted from the row the listing was built from.
    if (-not (Test-PathIsStyleDirChild -Path $entry.Path -Root (Get-StyleTrashRoot))) {
        Write-Host "Refusing to move '$($entry.Path)': it is not a trashed style directory." -ForegroundColor Yellow
        return 'outside'
    }
    if (-not (Test-PathIsStyleDirChild -Path $dest)) {
        Write-Host "Refusing to restore to '$dest': it is not a direct child of your styles directory." -ForegroundColor Yellow
        return 'outside'
    }

    try {
        $stylesRoot = Join-Path $script:TStylesDataRoot 'styles'
        if (-not (Test-Path -LiteralPath $stylesRoot)) {
            New-Item -ItemType Directory -Path $stylesRoot -Force | Out-Null
        }
        Move-Item -LiteralPath $entry.Path -Destination $dest -ErrorAction Stop
        if ((Test-Path -LiteralPath $entry.Path) -or -not (Test-Path -LiteralPath $dest)) {
            throw "Move did not complete: '$($entry.Path)' -> '$dest'."
        }
    } catch {
        Write-Host "Could not restore '$($entry.StyleName)': $_" -ForegroundColor Red
        return 'failed'
    }

    Write-Host ""
    Write-Host "  Restored $($entry.StyleName)." -ForegroundColor Green
    Write-Host "  to $dest" -ForegroundColor Gray
    if ($entry.IsStyle) {
        Write-Host "  Apply it with: tstyles $($entry.StyleName)" -ForegroundColor DarkGray
    } else {
        # It is back, and saying "restored" and stopping would be a claim the
        # listing cannot keep.
        Write-Host "  It carries no scheme.json, so tstyles list and the picker will not show it." -ForegroundColor Yellow
    }
    Write-Host ""
    return 'restored'
}

function Show-DeletableStyleList {
    # `tstyles delete` with no name. Shows only what the command can act on.
    [CmdletBinding()]
    param()
    $claim = Get-InstalledStyleClaim
    $one   = Test-StylesRootsAreOne
    $hash  = Get-InstalledStyleHash -DataDir $script:TStylesDataRoot
    $yours = @(foreach ($s in (Get-AvailableStyles)) {
        $o = Get-StyleOrigin -Name $s.Name -StyleDir $s.FullName -Claim $claim -RootsAreOne $one -StyleHash $hash
        if ($o -eq 'yours' -or $o -eq 'shadow') { [pscustomobject]@{ Name = $s.Name; Origin = $o } }
    })

    Write-Host ""
    if (-not $yours) {
        Write-Host "  You have no styles of your own to delete." -ForegroundColor Gray
        Write-Host "  Make one with: tstyles tune" -ForegroundColor DarkGray
        Write-Host ""
        return
    }
    Write-Host "Your styles:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($y in $yours) {
        if ($y.Origin -eq 'shadow') {
            Write-Host ("    {0,-16}  shadows the bundled '{0}'" -f $y.Name)
        } else {
            Write-Host ("    {0,-16}" -f $y.Name)
        }
    }
    Write-Host ""
    Write-Host "  Delete one with: tstyles delete <name>" -ForegroundColor DarkGray
    Write-Host "  Bundled styles are refused. A deleted folder is kept for $($script:TStylesTrashKeepDays) days under" -ForegroundColor DarkGray
    Write-Host "  $(Get-StyleTrashRoot)" -ForegroundColor DarkGray
    Write-Host "  tstyles trash      lists what is in there, with the days each has left" -ForegroundColor DarkGray
    Write-Host "  tstyles restore <name>   puts one back" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-TerminalStyleDelete {
    # `tstyles delete [name]`.
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Name, [string]$Target, [switch]$Yes)

    $plan = Get-StyleDeletePlan -Name $Name

    if (-not $plan.Ok) {
        switch ($plan.Reason) {
            'noname'  { Show-DeletableStyleList; return }
            'notfound' {
                Write-Host "Unknown style: '$Name'" -ForegroundColor Yellow
                Write-Host "  tstyles delete     lists the styles you can delete" -ForegroundColor DarkGray
                return
            }
            'bundled' {
                Write-Host "'$Name' is a bundled style -- it came with TerminalStyles, so there is nothing of yours to delete." -ForegroundColor Yellow
                Write-Host "  To stop using it: tstyles reset" -ForegroundColor DarkGray
                return
            }
            'unknown' {
                # No manifest and no tune.json: the tool genuinely cannot tell
                # whether this style is the user's. Refusing is the only honest
                # answer -- deleting a bundled style here is unrecoverable
                # short of a reinstall.
                Write-Host "Cannot tell whether '$Name' is yours or came with TerminalStyles." -ForegroundColor Yellow
                Write-Host "  The install record ($(Join-Path $script:TStylesDataRoot '.installed-files')) is missing or unreadable," -ForegroundColor DarkGray
                Write-Host "  and '$Name' carries no tune.json. Refusing rather than guessing." -ForegroundColor DarkGray
                Write-Host "  Move the folder by hand if you are sure: $($plan.Dir)" -ForegroundColor DarkGray
                return
            }
            'outside' {
                Write-Host "'$Name' does not live in your styles directory -- refusing to touch it." -ForegroundColor Yellow
                return
            }
            default { Write-Host "Cannot delete '$Name'." -ForegroundColor Yellow; return }
        }
    }

    Show-StyleDeletePlan -Plan $plan

    if (-not (Confirm-Action -Question "Delete '$($plan.Name)'? [y/N]" -Consequence $plan.Consequence -Yes:$Yes)) {
        Write-Host "  Cancelled." -ForegroundColor Gray
        return
    }

    try {
        Move-StyleDirectoryToTrash -Plan $plan
    } catch {
        Write-Host "Could not delete '$($plan.Name)': $_" -ForegroundColor Red
        # The listing above named trash this delete would erase, in red, and the
        # user consented to it as part of one act. Saying the delete failed does
        # not say that half did not happen, and the failure paths through
        # Move-Item throw before the sweep can be reported any other way.
        if (@($plan.SweepTargets).Count -gt 0) {
            Write-Host "  Nothing was erased: the trash is swept only after the move lands." -ForegroundColor DarkGray
        }
        return
    }

    Write-Host ""
    Write-Host "  Deleted $($plan.Name)." -ForegroundColor Green
    Write-Host "  Kept for $($script:TStylesTrashKeepDays) days at $($plan.TrashPath)" -ForegroundColor Gray
    # The recovery route, on the screen where it is needed. It was a `Move-Item`
    # the user had to compose from the path above, documented only in
    # `tstyles help delete`.
    Write-Host "  Undo with: tstyles restore $($plan.Name)" -ForegroundColor DarkGray
    if ($plan.KeptCache)   { Write-Host "  Kept $($plan.KeptCache)" -ForegroundColor DarkGray }
    if ($plan.KeptProfile) { Write-Host "  Kept $($plan.KeptProfile)" -ForegroundColor DarkGray }

    # Reconciliation LAST, and only once the move is verified, so a failed move
    # never repaints the terminal. The cost of that order is that the style is
    # no longer where the reset looks for it: -KnownStyleName carries the
    # ownership the plan proved while it was still there, or the reset refuses
    # the one profile it is certain about and the RESET line above is a lie.
    if ($plan.WasActive) {
        if ($plan.RevealDir) {
            Apply-StyleDirect -StyleName $plan.Name -Target $Target
        } else {
            Reset-StyleDirect -Target $Target -KnownStyleName $plan.Name
        }
    }
}
