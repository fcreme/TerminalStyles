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
        bundled -- UNLESS it carries tune.json, which is how Get-UninstallPlan
        already decides a shipped style has become the user's (an Overwrite save
        writes a tuned style under a bundled name).
        With no usable manifest there is no evidence either way, and the answer
        is 'unknown': never claim ownership the tool cannot prove, and never
        delete on a guess.

    -Claim and -RootsAreOne are seams: tests drive them directly, and
    Show-StyleList reads the manifest once for the whole listing rather than
    once per row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StyleDir,
        $Claim = '__unset__',
        $RootsAreOne = $null
    )

    if ($Claim -is [string] -and $Claim -eq '__unset__') { $Claim = Get-InstalledStyleClaim }
    if ($null -eq $RootsAreOne) { $RootsAreOne = Test-StylesRootsAreOne }

    $hasTune = Test-Path -LiteralPath (Join-Path $StyleDir 'tune.json')

    if (-not $RootsAreOne) {
        $userRoot = Join-Path $script:TStylesDataRoot 'styles'
        $inUser = $false
        try {
            $sep  = [System.IO.Path]::DirectorySeparatorChar
            $full = [System.IO.Path]::GetFullPath($StyleDir).TrimEnd($sep)
            $root = [System.IO.Path]::GetFullPath($userRoot).TrimEnd($sep)
            $inUser = $full.StartsWith($root + $sep, [System.StringComparison]::Ordinal)
        } catch { }

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
        # A tuned copy is still the user's: an Overwrite save writes tune.json
        # under a bundled name, and 'shadow' already says "yours, shadowing
        # bundled". Only an UNtuned style the installer admits placing is
        # reclassified. With no manifest $Claim is $null, not an empty list, so
        # an ordinary PSGallery install -- where the data root holds only what
        # the user made -- keeps deciding by path exactly as before.
        if (-not $hasTune -and $null -ne $Claim -and ($Claim -contains $Name)) {
            return 'bundled'
        }

        $bundledTwin = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $Name
        if (Test-Path -LiteralPath (Join-Path $bundledTwin 'scheme.json')) { return 'shadow' }
        return 'yours'
    }

    # One root: the path cannot distinguish anything.
    if ($hasTune) { return 'yours' }
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

    HasFingerprint matters for the wording: a child with no baseFingerprint
    gets no "the base changed" notice on its next tune, so its adjustments
    change meaning with nothing on screen to explain it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

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
        $out += [pscustomobject]@{
            Name           = $s.Name
            Brightness     = $(if ($t.PSObject.Properties.Match('brightness').Count) { [int]$t.brightness } else { 0 })
            Saturation     = $(if ($t.PSObject.Properties.Match('saturation').Count) { [int]$t.saturation } else { 0 })
            HasFingerprint = [bool]($t.PSObject.Properties.Match('baseFingerprint').Count -and $t.baseFingerprint)
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Root = (Join-Path $script:TStylesDataRoot 'styles')
    )
    try {
        $sep  = [System.IO.Path]::DirectorySeparatorChar
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep)
        $root = [System.IO.Path]::GetFullPath($Root).TrimEnd($sep)
        if (-not $full.StartsWith($root + $sep, [System.StringComparison]::Ordinal)) { return $false }
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
        TrashPath = $null; Consequence = $null
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
        # One root, manifest claims the name, but tune.json made it the user's:
        # removing it leaves nothing behind, and `tstyles update` will restore
        # the shipped copy under that name.
        $plan.RevealDir = $null
    }

    # Captured BEFORE the move: Get-CurrentStyleName answers differently
    # afterwards, and in opposite directions depending on whether the name
    # survives.
    try { $plan.WasActive = ((Get-CurrentStyleName) -eq $Name) } catch { }

    $plan.Children = @(Get-StyleTuneChild -StyleDir $dir)

    $cache = Get-StyleCacheDir -StyleName $Name
    if (Test-Path -LiteralPath $cache) { $plan.KeptCache = $cache }
    $prof = Join-Path (Join-Path $script:TStylesDataRoot 'profiles') "$Name.terminal"
    if (Test-Path -LiteralPath $prof) { $plan.KeptProfile = $prof }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $plan.TrashPath = Join-Path (Get-StyleTrashRoot) "$Name-$stamp"

    $plan.Consequence = if ($plan.RevealDir) {
        "moves your '$Name' aside; the name reverts to the bundled style"
    } else {
        "moves '$Name' aside; nothing else provides that name"
    }
    $plan.Ok = $true
    return $plan
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

    foreach ($c in $Plan.Children) {
        if ($Plan.RevealDir) {
            Write-Host ("  - '{0}' was tuned from this style and re-seeds from the bundled one: same brightness/saturation, different colours" -f $c.Name) -ForegroundColor Gray
            if (-not $c.HasFingerprint) {
                Write-Host ("      it records no base fingerprint, so its next tune will not mention the change") -ForegroundColor DarkGray
            }
        } else {
            Write-Host ("  - '{0}' loses the brightness {1:+#;-#;0} and saturation {2:+#;-#;0} it was tuned by" -f $c.Name, $c.Brightness, $c.Saturation) -ForegroundColor Red
            Write-Host ("      nothing else records those values") -ForegroundColor DarkGray
        }
    }

    if ($Plan.KeptCache)   { Write-Host "  - KEEP $($Plan.KeptCache)" -ForegroundColor Gray }
    if ($Plan.KeptProfile) { Write-Host "  - KEEP $($Plan.KeptProfile)" -ForegroundColor Gray }
    if ($Plan.IsLink) {
        Write-Host "  - This style is a symlink; only the link is moved, its target is untouched" -ForegroundColor Gray
    }
    Write-Host "  - Nothing is erased: move the folder back to undo." -ForegroundColor Gray
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
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan, [int]$KeepDays = 7)

    $trashRoot = Get-StyleTrashRoot

    # Sweep first, and only inside the trash root.
    if (Test-Path -LiteralPath $trashRoot) {
        $cutoff = (Get-Date).AddDays(-$KeepDays)
        foreach ($old in @(Get-ChildItem -LiteralPath $trashRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            $deletedAt = Get-StyleTrashTimestamp -Name $old.Name -Fallback $old.LastWriteTime
            if ($deletedAt -ge $cutoff) { continue }
            if (-not (Test-PathIsStyleDirChild -Path $old.FullName -Root $trashRoot)) { continue }
            try {
                if ($old.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    [System.IO.Directory]::Delete($old.FullName, $false)
                } else {
                    Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction Stop
                }
            } catch { }
        }
    }

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
        throw "Move did not complete: '$($Plan.Dir)' -> '$($Plan.TrashPath)'. Nothing else was changed."
    }
}

function Show-DeletableStyleList {
    # `tstyles delete` with no name. Shows only what the command can act on.
    [CmdletBinding()]
    param()
    $claim = Get-InstalledStyleClaim
    $one   = Test-StylesRootsAreOne
    $yours = @(foreach ($s in (Get-AvailableStyles)) {
        $o = Get-StyleOrigin -Name $s.Name -StyleDir $s.FullName -Claim $claim -RootsAreOne $one
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
    Write-Host "  Bundled styles are refused. A deleted folder is kept for 7 days under" -ForegroundColor DarkGray
    Write-Host "  $(Get-StyleTrashRoot)" -ForegroundColor DarkGray
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
        return
    }

    Write-Host ""
    Write-Host "  Deleted $($plan.Name)." -ForegroundColor Green
    Write-Host "  Kept for 7 days at $($plan.TrashPath)" -ForegroundColor Gray
    if ($plan.KeptCache)   { Write-Host "  Kept $($plan.KeptCache)" -ForegroundColor DarkGray }
    if ($plan.KeptProfile) { Write-Host "  Kept $($plan.KeptProfile)" -ForegroundColor DarkGray }

    # Reconciliation LAST, and only once the move is verified, so a failed move
    # never repaints the terminal.
    if ($plan.WasActive) {
        if ($plan.RevealDir) {
            Apply-StyleDirect -StyleName $plan.Name -Target $Target
        } else {
            Reset-StyleDirect -Target $Target
        }
    }
}
