# previewsession.ps1 -- a preview written to a whole file, recorded on disk.
#
# The Windows Terminal picker, the tuner and the WezTerm picker preview by
# rewriting a file as you arrow: settings.json, or the generated WezTerm module.
# Each kept its only undo in memory -- the file's text as it opened -- and
# wrote every preview, and Esc, without looking at the file first. So:
#
#   * a tab closed mid-pick ends pwsh without its finally (SIGHUP on macOS and
#     Linux; on Windows a tab close races the finally, and Stop-Process or a
#     power loss skips it), leaving a preview nothing on disk names, and the
#     next command's rolling .bak then copies that preview over the user's
#     only copy;
#   * a change made to the file while the picker is open -- Windows Terminal's
#     Settings UI, Settings Sync, another tstyles command -- was replaced by
#     the next preview, or by Esc.
#
# This is the VS Code preview session (lib/vscodewriter.ps1) ported to whole
# files. Before the first preview is written, a copy of the file and a record
# naming the session go to <DataRoot>/.preview-records. Every write first
# checks that the file still holds what the session last left in it. Esc puts
# back the bytes it found, or, when the file changed, takes the preview back
# out of it (Undo-WTSettingsPreview). And every settings.json writer, and the
# next picker for WezTerm, first puts back a preview a closed session left
# (Restore-AbandonedFilePreview).

function Get-FilePreviewRecordPath {
    # The record and the copy of the file it found, keyed on kind and path:
    # @{ Record; Original }. Lower-cased on Windows only, where paths are.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('WindowsTerminal', 'WezTerm')][string]$Kind,
        [Parameter(Mandatory)][string]$Path
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    if ((Get-TStylesPlatform) -eq 'Windows') { $full = $full.ToLowerInvariant() }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hex = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($full)) | ForEach-Object { $_.ToString('x2') })
    } finally { $sha.Dispose() }
    $prefix = if ($Kind -eq 'WindowsTerminal') { 'wt' } else { 'wezterm' }
    $dir = Join-Path $script:TStylesDataRoot '.preview-records'
    $stem = Join-Path $dir ('{0}-{1}' -f $prefix, $hex.Substring(0, 16))
    return @{ Dir = $dir; Record = "$stem.json"; Original = "$stem.original" }
}

function Get-FilePreviewTextHash {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (-join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

function Read-FilePreviewText {
    # The file as text, UTF-8 with any BOM dropped (how every snapshot here has
    # always been read), or $null when it does not exist. Shared for read so a
    # file another process has open does not fail the check.
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                      [System.IO.FileShare]::ReadWrite)
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.UTF8Encoding]::new($false), $true)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

function Read-FilePreviewRecord {
    # @{ Exists; Valid; Data }. A record that cannot be parsed, or names another
    # schema, is Exists and not Valid: left alone rather than guessed at.
    param([Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Path)
    $p = Get-FilePreviewRecordPath -Kind $Kind -Path $Path
    if (-not [System.IO.File]::Exists($p.Record)) { return @{ Exists = $false; Valid = $false; Data = $null } }
    try {
        $d = [System.IO.File]::ReadAllText($p.Record, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return @{ Exists = $true; Valid = $false; Data = $null } }
    $ok = $d -and "$($d.schemaVersion)" -eq '1' -and $d.session -and "$($d.kind)" -eq $Kind
    return @{ Exists = $true; Valid = [bool]$ok; Data = $d }
}

function Test-FilePreviewRecordOurs {
    param([Parameter(Mandatory)][hashtable]$Session)
    $r = Read-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path
    return ($r.Valid -and "$($r.Data.session)" -ceq $Session.Id)
}

function Remove-FilePreviewRecord {
    <#
    .SYNOPSIS
    Delete the record and the copy for one file -- only the ones naming
    -SessionId, when given.

    .DESCRIPTION
    The WezTerm apply and reset call it with no -SessionId before they write the
    module: a preview can be byte-identical to an explicit apply (most bundled
    styles share a font and padding), and a record that survived the apply
    would let a later recovery, or the picker's Esc, put the old module back
    over it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [string]$SessionId
    )
    $p = Get-FilePreviewRecordPath -Kind $Kind -Path $Path
    if ($SessionId) {
        $r = Read-FilePreviewRecord -Kind $Kind -Path $Path
        if (-not ($r.Valid -and "$($r.Data.session)" -ceq $SessionId)) { return }
    }
    foreach ($f in $p.Record, $p.Original) {
        if ([System.IO.File]::Exists($f)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

function New-FilePreviewSession {
    <#
    .SYNOPSIS
    A preview session for one whole file. Reads it once; writes nothing.

    .DESCRIPTION
    OriginalText is the snapshot every preview is built from, read once. A
    record already on disk for this file -- a recovery that failed, so it holds
    the only copy of what a closed session found -- makes this session's
    writes refuse ('Blocked'), so its copy is never written over.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('WindowsTerminal', 'WezTerm')][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('picker', 'tuner', 'creator')][string]$By,
        [string]$TargetName
    )
    $existed = [System.IO.File]::Exists($Path)
    $text = $null
    if ($existed) {
        try { $text = Read-FilePreviewText -Path $Path }
        catch { throw ("Could not read {0}: {1}" -f $Path, $_.Exception.GetBaseException().Message) }
    }
    return @{
        Kind            = $Kind
        Path            = $Path
        By              = $By
        TargetName      = $TargetName
        Id              = [guid]::NewGuid().ToString('n')
        OriginalExisted = $existed
        OriginalText    = $text
        LastWrittenText = $null
        Recorded        = $false
        Changed         = $false
        Blocked         = (Read-FilePreviewRecord -Kind $Kind -Path $Path).Exists
    }
}

function Write-FilePreview {
    <#
    .SYNOPSIS
    Write one preview through the session. Returns written | current | changed
    | failed, and never throws.

    .DESCRIPTION
    'changed' is sticky: once the file holds something other than what the
    session last left in it, nothing more is written into it, and Esc and Enter
    work from the file as it is. The record and the copy are saved BEFORE the
    file is written, so a session that ends at any point has left a record of
    what is on disk; one that cannot be saved writes no preview.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][hashtable]$Session,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    if (-not $Session) { return 'failed' }
    if ($Session.Changed) { return 'changed' }
    if ($Session.Blocked) { return 'failed' }
    try {
        if ($Session.Recorded -and -not (Test-FilePreviewRecordOurs -Session $Session)) {
            $Session.Changed = $true
            return 'changed'
        }
        $now = Read-FilePreviewText -Path $Session.Path
        $expected = $Session.LastWrittenText
        if ($null -eq $expected) { $expected = $Session.OriginalText }
        if ($now -cne $expected) {
            $Session.Changed = $true
            return 'changed'
        }
        if ($Text -ceq $now) { return 'current' }

        $p = Get-FilePreviewRecordPath -Kind $Session.Kind -Path $Session.Path
        if (-not $Session.Recorded) {
            if (-not [System.IO.Directory]::Exists($p.Dir)) { [void][System.IO.Directory]::CreateDirectory($p.Dir) }
            if ($Session.OriginalExisted) {
                Copy-Item -LiteralPath $Session.Path -Destination $p.Original -Force -ErrorAction Stop
            }
        }
        $record = [ordered]@{
            schemaVersion = 1
            kind          = $Session.Kind
            path          = [System.IO.Path]::GetFullPath($Session.Path)
            session       = $Session.Id
            by            = $Session.By
            existed       = [bool]$Session.OriginalExisted
            written       = @((Get-FilePreviewTextHash -Text $now), (Get-FilePreviewTextHash -Text $Text) | Where-Object { $_ })
        }
        Write-SettingsAtomic -Path $p.Record -Json (ConvertTo-Json -InputObject $record -Depth 4)
        $Session.Recorded = $true

        if ($Session.Kind -eq 'WindowsTerminal') {
            Write-SettingsAtomic -Path $Session.Path -Json $Text
        } else {
            if ((Write-WezTermModuleText -Path $Session.Path -Text $Text) -eq 'failed') { return 'failed' }
        }
        $Session.LastWrittenText = $Text
        return 'written'
    } catch { return 'failed' }
}

function Restore-FilePreview {
    <#
    .SYNOPSIS
    Esc: put back what the session found, or take its preview out of a file
    that changed. Returns @{ Event='restore'; Status; ... }, never throws.

    .DESCRIPTION
    Status is none | restored | merged | left | failed.
      none      nothing of the session's is in the file; nothing written
      restored  the file still held the preview, so the bytes it found went back
      merged    the file changed (Windows Terminal): the preview's keys were
                taken out of it as it is now, and Kept names a key changed again
      left      another tstyles command took the session over, or (WezTerm)
                another writer rewrote the module, which wins
      failed    nothing could be put back; the record and copy stay for the
                next command. Arm says which step failed.
    -End drops the record and the copy, but only if the record names this
    session.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][hashtable]$Session,
        [switch]$End
    )
    $out = @{ Event = 'restore'; Status = 'none'; Kind = $null; By = $null; Path = $null; Kept = @(); Reason = $null; Arm = $null }
    if (-not $Session) { return $out }
    $out.Kind = $Session.Kind; $out.By = $Session.By; $out.Path = $Session.Path

    if ($null -eq $Session.LastWrittenText) {
        if ($End) { Remove-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path -SessionId $Session.Id }
        return $out
    }
    try {
        if ($Session.Recorded -and -not (Test-FilePreviewRecordOurs -Session $Session)) {
            $out.Status = 'left'
            $Session.LastWrittenText = $null
            return $out
        }
        $now = Read-FilePreviewText -Path $Session.Path
        if ($now -ceq $Session.LastWrittenText) {
            $out.Arm = 'restore'
            if ($Session.Kind -eq 'WindowsTerminal') {
                Write-SettingsAtomic -Path $Session.Path -Json $Session.OriginalText
            } elseif ($Session.OriginalExisted) {
                if ((Write-WezTermModuleText -Path $Session.Path -Text $Session.OriginalText) -eq 'failed') {
                    throw "the module could not be written"
                }
            } else {
                Remove-Item -LiteralPath $Session.Path -Force -ErrorAction Stop
            }
            $out.Status = 'restored'
        } elseif ($Session.Kind -eq 'WindowsTerminal') {
            $out.Arm = 'merge'
            $u = Undo-WTSettingsPreview -OriginalJson $Session.OriginalText -PreviewJson $Session.LastWrittenText `
                    -CurrentJson $now -TargetName $Session.TargetName
            if (@($u.Undone).Count -gt 0) {
                Write-SettingsAtomic -Path $Session.Path -Json $u.Text
                $out.Status = 'merged'
            } else {
                # Every key the preview set was changed again: nothing of it
                # is left to take out.
                $out.Status = 'left'
            }
            $out.Kept = @($u.Kept)
        } else {
            $out.Status = 'left'
        }
        $Session.LastWrittenText = $null
        if ($End) { Remove-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path -SessionId $Session.Id }
    } catch {
        $out.Status = 'failed'
        $out.Reason = $_.Exception.GetBaseException().Message
    }
    return $out
}

function Complete-FilePreview {
    <#
    .SYNOPSIS
    Enter: keep the preview on disk, or merge the chosen style into a file that
    changed. Returns @{ Event='commit'; Status done | merged | failed; ... }.

    .DESCRIPTION
    When nobody else wrote the file, the commit is the chosen style's preview
    as -Merge builds it from the text the session found: 'done' when the file
    already holds it (the last preview was that style), and written, still
    'done', when it does not -- the last preview write failed, or the session
    could write none. 'done' never means "nothing happened to a style the
    picker then calls applied". When the file changed, the session's own
    preview is taken out of it as it is now (when the record is still this
    session's) and -Merge is run over the result: 'merged'. Without -Merge (the
    picker's finally after an error), a file that still holds the preview is
    kept as the commit; a changed one has the preview taken out. The record is
    dropped only when it names this session.

    WezTerm: the publish that follows Enter writes the module itself, so this
    only drops the session's record.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][hashtable]$Session,
        [scriptblock]$Merge
    )
    $out = @{ Event = 'commit'; Status = 'done'; Kind = $null; By = $null; Path = $null; Kept = @(); Reason = $null; Style = $null }
    if (-not $Session) { return $out }
    $out.Kind = $Session.Kind; $out.By = $Session.By; $out.Path = $Session.Path
    if ($Session.Kind -eq 'WezTerm') {
        Remove-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path -SessionId $Session.Id
        $Session.LastWrittenText = $null
        return $out
    }
    try {
        $ours = $Session.Recorded -and (Test-FilePreviewRecordOurs -Session $Session)
        $now = Read-FilePreviewText -Path $Session.Path
        $expected = $Session.LastWrittenText
        if ($null -eq $expected) { $expected = $Session.OriginalText }
        if ((-not $Session.Recorded -or $ours) -and $now -ceq $expected) {
            if ($Merge) {
                $chosen = & $Merge $Session.OriginalText
                if ($null -eq $chosen) { $chosen = $Session.OriginalText }
                if ($chosen -cne $now) { Write-SettingsAtomic -Path $Session.Path -Json $chosen }
            }
            Remove-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path -SessionId $Session.Id
            $Session.LastWrittenText = $null
            return $out
        }

        $base = $now
        if ($ours -and $null -ne $Session.LastWrittenText) {
            $u = Undo-WTSettingsPreview -OriginalJson $Session.OriginalText -PreviewJson $Session.LastWrittenText `
                    -CurrentJson $now -TargetName $Session.TargetName
            if (@($u.Undone).Count -gt 0) { $base = $u.Text }
            $out.Kept = @($u.Kept)
        }
        $final = $base
        if ($Merge) {
            $m = & $Merge $base
            if ($null -ne $m) { $final = $m }
        }
        if ($final -cne $now) {
            Write-SettingsAtomic -Path $Session.Path -Json $final
            $out.Status = 'merged'
        }
        Remove-FilePreviewRecord -Kind $Session.Kind -Path $Session.Path -SessionId $Session.Id
        $Session.LastWrittenText = $null
    } catch {
        $out.Status = 'failed'
        $out.Reason = $_.Exception.GetBaseException().Message
    }
    return $out
}

function Restore-AbandonedFilePreview {
    <#
    .SYNOPSIS
    Put back a preview a closed session left in a file, before reading it.
    Returns @{ Event='recover'; Status none | restored | kept | failed; ... }.

    .DESCRIPTION
    Called by every settings.json writer before it reads the file or rolls its
    .bak, and by the WezTerm picker before it opens its session.

      restored  the file holds one of the session's previews: the copy of what
                it found goes back, and the record goes
      kept      settings.json changed since: left as it is, and the copy is
                moved beside it under a name nothing else writes
      none      no record, one that cannot be read (left alone), or nothing to
                put back
      failed    the copy could not be put back; both stay for the next command

    No liveness check: a picker still open in another tab is treated as closed,
    and its own Esc then finds the record gone and leaves the file ('left').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('WindowsTerminal', 'WezTerm')][string]$Kind,
        [Parameter(Mandatory)][string]$Path
    )
    $out = @{ Event = 'recover'; Status = 'none'; Kind = $Kind; By = $null; Path = $Path; Backup = $null; Copy = $null; Reason = $null }
    $p = Get-FilePreviewRecordPath -Kind $Kind -Path $Path
    $r = Read-FilePreviewRecord -Kind $Kind -Path $Path
    if (-not $r.Valid) { return $out }
    $d = $r.Data
    $out.By = "$($d.by)"
    $full = [System.IO.Path]::GetFullPath($Path)
    $cmp = if ((Get-TStylesPlatform) -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not [string]::Equals("$($d.path)", $full, $cmp)) { return $out }

    try {
        $now = Read-FilePreviewText -Path $Path
        $copy = $null
        if ([System.IO.File]::Exists($p.Original)) { $copy = Read-FilePreviewText -Path $p.Original }
        $existed = [bool]$d.existed
        if (($existed -and $null -eq $copy) -or ($Kind -eq 'WindowsTerminal' -and -not $existed)) {
            Remove-FilePreviewRecord -Kind $Kind -Path $Path
            return $out
        }
        if (($null -eq $now -and $null -eq $copy) -or ($null -ne $now -and $now -ceq $copy)) {
            Remove-FilePreviewRecord -Kind $Kind -Path $Path
            return $out
        }
        $written = @(@($d.written) | ForEach-Object { "$_" })
        if ($null -ne $now -and $written -ccontains (Get-FilePreviewTextHash -Text $now)) {
            if ($Kind -eq 'WindowsTerminal') {
                Write-SettingsAtomic -Path $Path -Json $copy
            } elseif ($existed) {
                if ((Write-WezTermModuleText -Path $Path -Text $copy) -eq 'failed') { throw 'the module could not be written' }
            } else {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
            Remove-FilePreviewRecord -Kind $Kind -Path $Path
            $out.Status = 'restored'
            return $out
        }
        if ($Kind -eq 'WindowsTerminal' -and $null -ne $copy) {
            # Not "$Path.bak-<timestamp>": apply.ps1 copies to exactly that name,
            # without -Force, milliseconds after its own recovery.
            $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)
            $dest = "$Path.preview-$stamp"
            $n = 1
            while ([System.IO.File]::Exists($dest)) { $dest = "$Path.preview-$stamp-$n"; $n++ }
            Move-Item -LiteralPath $p.Original -Destination $dest -ErrorAction Stop
            Remove-FilePreviewRecord -Kind $Kind -Path $Path
            $out.Status = 'kept'
            $out.Backup = $dest
            return $out
        }
        Remove-FilePreviewRecord -Kind $Kind -Path $Path
    } catch {
        $out.Status = 'failed'
        $out.Reason = $_.Exception.GetBaseException().Message
        $out.Copy = $p.Original
    }
    return $out
}

function Show-FilePreviewResult {
    # What a recovery, an Esc or an Enter did, in the user's terms. Quiet when
    # there is nothing to say: none, a clean Esc, a clean Enter.
    [CmdletBinding()]
    param([AllowNull()]$Result)
    if (-not $Result) { return }
    $by = if ($Result.By) { $Result.By } else { 'picker' }
    $wez = ($Result.Kind -eq 'WezTerm')
    switch ("$($Result.Event)/$($Result.Status)") {
        'recover/restored' {
            if ($wez) {
                Write-Host "  WezTerm's module held a preview from a tstyles picker that was closed without Enter or" -ForegroundColor Yellow
                Write-Host "  Esc (or is still open in another tab), so the module it found was put back first." -ForegroundColor Yellow
            } else {
                Write-Host ("  settings.json held a preview from a tstyles {0} that was closed without Enter or" -f $by) -ForegroundColor Yellow
                Write-Host "  Esc (or is still open in another tab), so the file it found was put back first." -ForegroundColor Yellow
            }
        }
        'recover/kept' {
            Write-Host ("  settings.json holds a preview from a tstyles {0} that was closed without Enter or Esc," -f $by) -ForegroundColor Yellow
            Write-Host ("  and it has changed since, so it was left as it is. The file as that {0} found it is" -f $by) -ForegroundColor Yellow
            Write-Host ("  kept at {0}." -f $Result.Backup) -ForegroundColor Yellow
        }
        'recover/failed' {
            Write-Host ("  {0} holds a preview from a tstyles {1} that was closed without Enter or Esc, and" -f $Result.Path, $by) -ForegroundColor Yellow
            Write-Host ("  putting back the file it found failed: {0}" -f $Result.Reason) -ForegroundColor Yellow
            $again = if ($wez) { 'the next tstyles picker tries again' } else { 'the next tstyles command that writes it tries again' }
            Write-Host ("  That file is kept at {0}; {1}." -f $Result.Copy, $again) -ForegroundColor Yellow
        }
        'restore/merged' {
            Write-Host ("  settings.json changed while the {0} was open, so the preview was taken back out of it" -f $by) -ForegroundColor Yellow
            Write-Host "  instead of the file being put back as it was. The change is kept." -ForegroundColor Yellow
            if (@($Result.Kept).Count -gt 0) {
                Write-Host ("  Left {0} as the file has them now: they changed after the preview wrote them." -f (@($Result.Kept) -join ', ')) -ForegroundColor DarkGray
            }
        }
        'restore/left' {
            if ($wez) {
                Write-Host "  WezTerm's module changed while the picker was open, so it was left as it is now." -ForegroundColor Yellow
            } else {
                Write-Host ("  settings.json changed while the {0} was open, so it was left as it is now." -f $by) -ForegroundColor Yellow
            }
        }
        'restore/failed' {
            Write-Host ("  Could not put {0} back: {1}" -f $Result.Path, $Result.Reason) -ForegroundColor Red
            $next = if ($wez) { 'the next tstyles picker' } else { 'the next tstyles command that writes it' }
            if ($Result.Arm -eq 'merge') {
                Write-Host ("  It changed while it was open and still holds the preview; {0}" -f $next) -ForegroundColor Red
                Write-Host ("  keeps the file the {0} found beside it." -f $by) -ForegroundColor Red
            } else {
                Write-Host ("  It still holds the preview; {0} puts back the file the {1} found." -f $next, $by) -ForegroundColor Red
            }
        }
        'commit/merged' {
            Write-Host ("  settings.json changed while the {0} was open, so '{1}' was merged into it as it is" -f $by, $Result.Style) -ForegroundColor DarkGray
            Write-Host ("  now, the way tstyles {0} would. The change is kept, except where the style sets the same key." -f $Result.Style) -ForegroundColor DarkGray
        }
        'commit/failed' {
            Write-Host ("  Could not write '{0}' into {1}: {2}" -f $Result.Style, $Result.Path, $Result.Reason) -ForegroundColor Yellow
        }
    }
}
