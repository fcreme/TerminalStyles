# VS Code's integrated terminal, wired in: the file I/O, the consent, and the
# undo records that lib/vscode.ps1 deliberately has none of.
#
# lib/vscode.ps1 is pure -- text in, text out -- and stays that way: it is what
# the round-trip tests drive. Everything here is the part that touches the
# user's machine, and it keeps three rules
# (docs/superpowers/specs/2026-10-02-vscode-settings-writer-design.md):
#
#   ASK ONCE, PER EDITOR. settings.json is a file people annotate by hand and
#   often sync between machines, so nothing is written until the user has said
#   yes for that editor. "Nobody was at the terminal to ask" is not a no, and is
#   not stored as one.
#
#   NO KEY WITHOUT A RECORD. The record of what an apply wrote is saved BEFORE
#   settings.json is written, and put back if the write fails. A write that only
#   takes ours out goes the other way round -- file first, then the record --
#   for the same reason. A crash can leave a record naming keys the file does
#   not hold -- a later reset finds them absent, which is harmless -- but not a
#   key that no command can name. The one exception is switching from one
#   style straight to another -- an apply over a style already saved, a
#   preview, the picker's Enter, or Esc back to the style the picker started
#   from: between the two writes the record names one style and the file holds
#   the other, whichever goes first.
#
#   REFUSE RATHER THAN GUESS. An editor that cannot be identified, a settings
#   folder that does not exist, a file that does not parse and a state file
#   that cannot be read all stop the write and say which.

function Get-VSCodeStatePath {
    # Where the per-editor consent and undo records live. One file for every
    # editor, keyed by the variant names Get-VSCodeVariant returns.
    Join-Path $script:TStylesDataRoot 'vscode-state.json'
}

function ConvertTo-VSCodeRecord {
    <#
    .SYNOPSIS
    A record read back from JSON, rebuilt in the shape the apply produced.

    .DESCRIPTION
    ConvertFrom-Json hands back PSCustomObjects, and on Windows PowerShell 5.1 a
    one-element array can arrive as its bare element. Invoke-VSCodeStyleReset
    walks Path as an array of key names, so a Path that collapsed to a string
    would no longer be the path it was. Rebuilding every Path as a [string[]]
    here means the reset never sees the difference between a record that went
    through a file and one that did not.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Parsed)

    if ($null -eq $Parsed) { return $null }

    $wrote = [System.Collections.Generic.List[object]]::new()
    foreach ($w in @($Parsed.Wrote)) {
        if ($null -eq $w) { continue }
        $had = $null
        if ($null -ne $w.Had) { $had = [string]$w.Had }
        $wrote.Add(@{
            Path    = [string[]]@(@($w.Path) | ForEach-Object { [string]$_ })
            Literal = [string]$w.Literal
            Had     = $had
        })
    }

    $created = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($Parsed.CreatedParents)) {
        if ($null -eq $c) { continue }
        $created.Add([string[]]@(@($c) | ForEach-Object { [string]$_ }))
    }

    return @{
        Style          = [string]$Parsed.Style
        Wrote          = $wrote.ToArray()
        CreatedParents = $created.ToArray()
    }
}

function Read-VSCodeState {
    <#
    .SYNOPSIS
    The per-editor state: @{ Ok; Path; Entries }.

    .DESCRIPTION
    Entries maps a variant name to @{ consent; settingsPath; record }. consent
    is 'yes', 'no' or '' (never asked). A missing file is Ok with no entries --
    nothing has been asked or written yet.

    A file that exists and cannot be read is NOT Ok, and is not quietly treated
    as empty. It holds the only record of which keys TerminalStyles put into a
    settings.json; starting a fresh one would throw that away, and the keys
    with it. Callers refuse to write while it is in that state and say so.
    #>
    [CmdletBinding()]
    param()

    $path = Get-VSCodeStatePath
    $entries = @{}
    if (-not [System.IO.File]::Exists($path)) {
        return @{ Ok = $true; Path = $path; Entries = $entries }
    }

    try {
        $json = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
        if (-not $json.Trim()) { return @{ Ok = $true; Path = $path; Entries = $entries } }
        $obj = $json | ConvertFrom-Json -ErrorAction Stop
        if ($obj -isnot [System.Management.Automation.PSCustomObject]) {
            return @{ Ok = $false; Path = $path; Entries = @{} }
        }
        foreach ($p in $obj.PSObject.Properties) {
            $v = $p.Value
            $entries[$p.Name] = @{
                consent      = [string]$v.consent
                settingsPath = [string]$v.settingsPath
                record       = (ConvertTo-VSCodeRecord -Parsed $v.record)
            }
        }
    } catch {
        return @{ Ok = $false; Path = $path; Entries = @{} }
    }
    return @{ Ok = $true; Path = $path; Entries = $entries }
}

function Write-VSCodeState {
    # Throws on failure, on purpose: a caller about to touch settings.json has
    # to know its record did not land first. Through Write-SettingsAtomic, so a
    # crash mid-write leaves the old file or the new one, never half of either.
    #
    # A .NET exception from inside Write-SettingsAtomic is only
    # statement-terminating -- with no try/catch around the call it is printed
    # and the caller's next line still runs, record unsaved -- so any failure is
    # rethrown here as an error of our own, which stops the caller.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entries)

    $out = [ordered]@{}
    foreach ($name in @($Entries.Keys | Sort-Object)) {
        $e = $Entries[$name]
        $out[$name] = [ordered]@{
            consent      = $e.consent
            settingsPath = $e.settingsPath
            record       = $e.record
        }
    }
    $path = Get-VSCodeStatePath
    try {
        Write-SettingsAtomic -Path $path -Json ($out | ConvertTo-Json -Depth 10)
    } catch {
        throw ("Could not write {0}: {1}" -f $path, $_.Exception.GetBaseException().Message)
    }
}

function Set-VSCodeStateEntry {
    <#
    .SYNOPSIS
    Change one editor's entry, leaving every other editor's as it was.

    .DESCRIPTION
    Only what the caller BOUND changes: -Record $null clears a record, and an
    absent -Record leaves it alone. Throws when the state file cannot be read,
    for the reason Read-VSCodeState gives -- rewriting it would drop the other
    editors' records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Variant,
        [string]$SettingsPath,
        [ValidateSet('yes', 'no')][string]$Consent,
        [AllowNull()]$Record
    )

    $state = Read-VSCodeState
    if (-not $state.Ok) { throw "Could not read $($state.Path)" }

    $entry = $state.Entries[$Variant]
    if (-not $entry) { $entry = @{ consent = ''; settingsPath = ''; record = $null } }
    if ($PSBoundParameters.ContainsKey('SettingsPath')) { $entry.settingsPath = $SettingsPath }
    if ($PSBoundParameters.ContainsKey('Consent'))      { $entry.consent      = $Consent }
    if ($PSBoundParameters.ContainsKey('Record'))       { $entry.record       = $Record }
    $state.Entries[$Variant] = $entry
    Write-VSCodeState -Entries $state.Entries
}

function Resolve-VSCodeTarget {
    <#
    .SYNOPSIS
    Which editor this terminal belongs to, and its settings.json:
    @{ Status; Variant; Path }.

    .DESCRIPTION
    Status is 'ok', 'unknownvariant' or 'nodir'.

      unknownvariant  Get-VSCodeVariant could not name exactly one editor.
                      NEVER defaulted to 'Code': see that function for what
                      guessing cost.
      nodir           the editor's User folder does not exist. Nothing is
                      created -- an editor that has never run has nowhere it
                      would read a file from.

    A User folder with no settings.json in it is 'ok': VS Code creates the file
    the first time a setting changes, so writing the first one is what it would
    have done.

    -Variant skips detection, for callers that already know which editor they
    mean. The rest are test seams, forwarded by what was BOUND -- and a bound
    -HomeDir also suppresses the ambient APPDATA, the way Get-VSCodeSettingsPath
    has it suppress XDG_CONFIG_HOME, so a sandboxed test on Windows cannot
    resolve to the operator's own roaming profile.
    #>
    [CmdletBinding()]
    param(
        [string]$Variant,
        [string]$HomeDir,
        [string]$AppData,
        [string]$XdgConfigHome,
        [string]$AskpassNode,
        [string]$GitAskpass
    )

    if (-not $Variant) {
        $askSplat = @{}
        if ($PSBoundParameters.ContainsKey('AskpassNode')) { $askSplat.AskpassNode = $AskpassNode }
        if ($PSBoundParameters.ContainsKey('GitAskpass'))  { $askSplat.GitAskpass  = $GitAskpass }
        $Variant = Get-VSCodeVariant @askSplat
        if (-not $Variant) { return @{ Status = 'unknownvariant'; Variant = $null; Path = $null } }
    }

    $pathSplat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $pathSplat.HomeDir = $HomeDir }
    if ($PSBoundParameters.ContainsKey('AppData')) {
        $pathSplat.AppData = $AppData
    } elseif ($PSBoundParameters.ContainsKey('HomeDir')) {
        $pathSplat.AppData = ''
    }
    if ($PSBoundParameters.ContainsKey('XdgConfigHome')) { $pathSplat.XdgConfigHome = $XdgConfigHome }

    $path = Get-VSCodeSettingsPath -Variant $Variant @pathSplat
    if (-not [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($path))) {
        return @{ Status = 'nodir'; Variant = $Variant; Path = $path }
    }
    return @{ Status = 'ok'; Variant = $Variant; Path = $path }
}

function Read-VSCodeSettingsText {
    # The file's text, or '' when there is no file yet. ReadAllText drops a
    # BOM; Write-SettingsAtomic puts it back, from the live file.
    #
    # A file that is there and cannot be read THROWS, as an error of our own that
    # names it. A bare .NET exception would only be printed, the caller's next
    # line would run on $null, and Test-VSCodeSettingsReadable calls that blank:
    # an unreadable settings.json would pass for "no settings yet". Refuse
    # rather than guess.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    try {
        return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    } catch {
        throw ("Could not read {0}: {1}" -f $Path, $_.Exception.GetBaseException().Message)
    }
}

function Test-VSCodeSettingsReadable {
    <#
    .SYNOPSIS
    Is this text something the JSONC editor can safely splice?

    .DESCRIPTION
    Blank is readable: it is what VS Code itself treats as "no settings yet".
    Otherwise the root must be an object, and that object must close.

    Asked BEFORE an apply or a reset rather than left to them, because the
    reset does not refuse broken text: on a file truncated mid-write it
    reported 'reset', removed 24 keys and kept one -- measured -- splicing
    against offsets that no longer meant what the record thought. Clearing the
    record after that would strand whatever it had not reached.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if (-not $Text.Trim()) { return $true }
    $tokens = Get-JsoncToken -Text $Text
    $open = Find-JsoncRootObject -Tokens $tokens
    if ($open -lt 0) { return $false }
    return ((Find-JsoncCloseBrace -Tokens $tokens -OpenIndex $open) -ge 0)
}

function Get-VSCodeWriterState {
    <#
    .SYNOPSIS
    Does a VS Code apply write settings.json right now, and if not, why not.

    .DESCRIPTION
    THE one answer. Get-TerminalCapability asks it (through
    Test-VSCodeWriterActive) to decide what VS Code claims, and the publisher
    asks it to decide whether to write -- so the "can't show" notice and the
    write cannot disagree about the same apply (CLAUDE.md: two implementations
    of one rule diverge).

    Returns @{ Status; Variant; Path; Entry }. Status is one of:
      active          identified editor, settings folder present, consent yes
      declined        consent no
      undecided       never asked, or nobody was there to answer
      unknownvariant  see Resolve-VSCodeTarget
      nodir           see Resolve-VSCodeTarget
      statecorrupt    vscode-state.json exists and cannot be read
    #>
    [CmdletBinding()]
    param()

    $t = Resolve-VSCodeTarget
    $out = @{ Status = $t.Status; Variant = $t.Variant; Path = $t.Path; Entry = $null }
    if ($t.Status -ne 'ok') { return $out }

    $state = Read-VSCodeState
    if (-not $state.Ok) { $out.Status = 'statecorrupt'; return $out }

    $entry = $state.Entries[$t.Variant]
    $out.Entry = $entry
    $consent = ''
    if ($entry) { $consent = $entry.consent }
    switch ($consent) {
        'yes'   { $out.Status = 'active' }
        'no'    { $out.Status = 'declined' }
        default { $out.Status = 'undecided' }
    }
    return $out
}

function Test-VSCodeWriterActive {
    # What Get-TerminalCapability's VSCode arm asks. A predicate over the one
    # decider above, not a second opinion.
    [CmdletBinding()]
    param()
    return ((Get-VSCodeWriterState).Status -eq 'active')
}

function Request-VSCodeWriterConsent {
    <#
    .SYNOPSIS
    Ask, once per editor, whether TerminalStyles may write its settings.json.
    Returns the writer status after asking (see Get-VSCodeWriterState).

    .DESCRIPTION
    Only an 'undecided' editor is asked, and only at a real console. The
    console check comes FIRST and is this function's own, not Confirm-Action's:
    that function answers $false both for "the user said no" and for "nobody
    could be asked", and storing the second as a no would turn the writer off
    for good the first time `tstyles eva` ran from a script.

    An answer that cannot be stored is reported, and the editor stays
    undecided: without a stored state the publisher could not save an undo
    record either, so honouring the yes for this run would only end in a
    failed write.
    #>
    [CmdletBinding()]
    param()

    $w = Get-VSCodeWriterState
    if ($w.Status -ne 'undecided') { return $w.Status }
    if (-not (Test-InteractiveConsole)) { return 'undecided' }

    Write-Host ""
    Write-Host ("  Save styles to {0}'s settings.json, so new terminals keep them?" -f $w.Variant)
    Write-Host "  This sets the terminal's colors, font and cursor there; tstyles reset" -ForegroundColor DarkGray
    Write-Host "  puts back whatever was there before. Change your mind any time with" -ForegroundColor DarkGray
    Write-Host "  tstyles vscode on  or  tstyles vscode off." -ForegroundColor DarkGray
    $answer = 'no'
    if (Confirm-Action -Question '  Save to settings.json? [y/N]') { $answer = 'yes' }

    try {
        Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Consent $answer
    } catch {
        Write-Host ("  Could not save that answer to {0}, so nothing is written to" -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        Write-Host "  settings.json this time, and you will be asked again." -ForegroundColor Yellow
        return 'undecided'
    }
    # The one decider says what the stored answer means, rather than a second
    # copy of its switch here.
    return (Get-VSCodeWriterState).Status
}

function Split-VSCodeKept {
    <#
    .SYNOPSIS
    Split the keys an undo kept by whether the style written next sets them
    again: @{ Left; Replaced }.

    .DESCRIPTION
    An undo keeps a key the user changed after the outgoing style wrote it.
    When the style written next sets that key too, the user's value is
    written over -- and kept in the new record, as the value a reset puts
    back: Replaced. Only the rest are still as the user set them: Left.

    The publisher and Esc's merge both report this split, and both get it
    from here, so the two cannot come to name the same key differently
    (CLAUDE.md: two implementations of one rule diverge). Keys are named the
    way the undo names them, Path joined with '/'. -Record is the next
    style's record; with none, every kept key is Left.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Kept,
        [AllowNull()]$Record
    )

    $written = @()
    if ($Record) { $written = @(@($Record.Wrote) | ForEach-Object { @($_.Path) -join '/' }) }
    return @{
        Left     = @(@($Kept) | Where-Object { $written -notcontains $_ })
        Replaced = @(@($Kept) | Where-Object { $written -contains $_ })
    }
}

function Publish-StyleVSCodeConfig {
    <#
    .SYNOPSIS
    Write a style into this editor's settings.json, with its undo record.
    Returns a result for Show-VSCodeWriteResult, or $null off VS Code.

    .DESCRIPTION
    The fourth config writer's door, beside Publish-StyleWezTermConfig and
    called from the same places: Apply-StyleNonWT, and the picker's Enter.
    It never asks -- callers ask first, so the "can't show" notice printed
    before it already reflects the answer -- and it never prints: the picker
    computes it above a Clear-Host and shows it below one.

    -Session is the picker's preview session. While the picker runs, the file
    holds a PREVIEW, and the apply undoes it by the session's record of what
    is on disk. A write that fails here rolls the stored record back to that
    one, the record of what the file still holds -- normally the stored record
    too, but not after a preview whose write and rollback both failed. If the
    rollback fails as well, the session's RecordAhead is left set, so Esc's
    restore puts it right.

    Kept is split in two on the way out. The apply's Kept names keys the
    outgoing style's undo left alone because the user had changed them; the
    incoming style then writes over any of those it sets itself, keeping the
    user's value as the one a reset restores. "Left as you set it" is only
    true of the others. Split-VSCodeKept draws that line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][hashtable]$Session
    )

    if ($Kind -ne 'VSCode') { return $null }

    $w = Get-VSCodeWriterState
    $result = @{
        Status = $w.Status; Variant = $w.Variant; Path = $w.Path
        Kept = @(); Replaced = @(); Overrides = @()
        Backup = $null; FailedPath = $null; Detail = $null
    }
    if ($w.Status -ne 'active') { return $result }

    $stored = $null
    if ($w.Entry) { $stored = $w.Entry.record }
    $onDisk = $stored
    if ($Session) {
        $onDisk = $Session.OnDiskRecord
        $result.Backup = $Session.Backup
    }

    try {
        $text = Read-VSCodeSettingsText -Path $w.Path
    } catch {
        # Refused, not guessed: a file that exists and cannot be read is not
        # "no settings yet", and writing over it would replace it outright.
        $result.Status = 'wontparse'; $result.Detail = 'it could not be read'
        return $result
    }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) {
        $result.Status = 'wontparse'; $result.Detail = 'it does not parse as a JSON object'
        return $result
    }

    # VS Code's own empty settings file is "{}"; a blank or missing one means
    # the same, and is the one case a reset does not return byte for byte --
    # it leaves "{}", which VS Code reads identically.
    $base = $text
    if (-not $base.Trim()) { $base = '{}' }

    $a = Invoke-VSCodeStyleApply -Text $base -StyleDir $StyleDir -StyleName $StyleName -PreviousRecord $onDisk
    if ($a.Status -ne 'applied') {
        $result.Status = 'wontparse'
        $result.Detail = switch ($a.Status) {
            'parentnotobject' { 'workbench.colorCustomizations in it is not an object' }
            default           { 'it does not parse as a JSON object' }
        }
        return $result
    }

    # FIRST touch: only while none of our keys are in the file. A copy taken
    # later would capture a file that already carries a style (CLAUDE.md,
    # "Encoding and culture, on files the user owns").
    if (-not $onDisk -and $text -and -not $result.Backup) {
        $result.Backup = Save-FirstTouchBackup -Path $w.Path -Content $text
    }

    try {
        Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $a.Record
        if ($Session) { $Session.RecordAhead = $true }
    } catch {
        $result.Status = 'writefailed'; $result.FailedPath = (Get-VSCodeStatePath)
        return $result
    }

    if ($a.Text -cne $text) {
        try {
            Write-SettingsAtomic -Path $w.Path -Json $a.Text
        } catch {
            $result.Status = 'writefailed'; $result.FailedPath = $w.Path
            try {
                # Back to the record of what the file still holds: $onDisk, not
                # $stored. Under a session they differ when a preview's write
                # failed and its record could not be put back.
                Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $onDisk
                if ($Session) { $Session.RecordAhead = $false }
            } catch {
                # Both writes failed. The record now describes keys that never
                # landed, and the keys still in the file are named by no record --
                # say so, rather than let a later reset leave them without a word.
                $result.Detail = 'its undo record could not be restored either'
            }
            return $result
        }
    }
    # The record and the file agree again: the commit landed, or wrote nothing.
    if ($Session) { $Session.RecordAhead = $false }

    $split = Split-VSCodeKept -Kept $a.Kept -Record $a.Record
    $ids = @(@($a.Record.Wrote) |
             Where-Object { @($_.Path).Count -eq 2 -and $_.Path[0] -eq 'workbench.colorCustomizations' } |
             ForEach-Object { $_.Path[1] })
    # Assigned, not wrapped: Get-VSCodeColorOverride returns ,$arr.
    $overrides = Get-VSCodeColorOverride -Text $a.Text -Ids $ids

    $result.Status    = 'written'
    $result.Kept      = $split.Left
    $result.Replaced  = $split.Replaced
    $result.Overrides = $overrides
    return $result
}

function Show-VSCodeWriteResult {
    <#
    .SYNOPSIS
    Say what Publish-StyleVSCodeConfig did, in the words for that outcome.

    .DESCRIPTION
    One arm per status and no shared "success" line: "Saved" is printed on the
    written path and nowhere else (CLAUDE.md: every message is a claim, and a
    status is not a boolean). Leading blank line, no trailing one -- the
    callers own their spacing, as with Show-UnsupportedStyleField.
    #>
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    Write-Host ""
    switch ($Result.Status) {
        'written' {
            Write-Host ("  Saved to {0}'s settings.json -- new terminals keep it." -f $Result.Variant) -ForegroundColor DarkGray
            if ($Result.Backup) {
                Write-Host ("  The file as it was before is kept at {0}" -f $Result.Backup) -ForegroundColor DarkGray
            }
            foreach ($k in @($Result.Kept)) {
                Write-Host ("  Left {0} as you set it (you changed it after the last style wrote it)." -f $k) -ForegroundColor DarkGray
            }
            foreach ($k in @($Result.Replaced)) {
                Write-Host ("  Replaced {0}, which you had changed by hand; tstyles reset puts yours back." -f $k) -ForegroundColor DarkGray
            }
            foreach ($o in @($Result.Overrides)) {
                Write-Host ("  {0} in workbench.colorCustomizations also sets {1}," -f $o.Scope, (@($o.Ids) -join ', ')) -ForegroundColor Yellow
                Write-Host "  and wins over this style while that color theme is active." -ForegroundColor Yellow
            }
        }
        'declined' {
            Write-Host ("  Not saved to {0}'s settings.json, as you chose. tstyles vscode on changes that." -f $Result.Variant) -ForegroundColor DarkGray
        }
        'undecided' {
            Write-Host ("  Not saved to {0}'s settings.json: there is no answer on record for it yet." -f $Result.Variant) -ForegroundColor DarkGray
            Write-Host "  tstyles vscode on gives one." -ForegroundColor DarkGray
        }
        'unknownvariant' {
            # Not "the colors apply to this terminal only": wherever the shell
            # loader is registered, new terminals take the colors too.
            Write-Host "  Couldn't tell which editor this terminal belongs to," -ForegroundColor Yellow
            Write-Host "  so nothing was saved to its settings.json." -ForegroundColor Yellow
        }
        'nodir' {
            Write-Host ("  Found no settings folder for {0} at {1}, so nothing was saved." -f
                        $Result.Variant, [System.IO.Path]::GetDirectoryName($Result.Path)) -ForegroundColor Yellow
        }
        'wontparse' {
            Write-Host ("  Could not edit {0} safely: {1}." -f $Result.Path, $Result.Detail) -ForegroundColor Yellow
            Write-Host "  Nothing was written to it. Fix the file and apply the style again." -ForegroundColor Yellow
        }
        'writefailed' {
            Write-Host ("  Could not write {0}." -f $Result.FailedPath) -ForegroundColor Yellow
            Write-Host "  This terminal keeps the colors; new terminals won't." -ForegroundColor Yellow
            if ($Result.Detail) {
                Write-Host ("  And {0}, so a reset may leave some of the previous style's settings in place." -f $Result.Detail) -ForegroundColor Yellow
            }
        }
        'statecorrupt' {
            Write-Host ("  Could not read {0}, which records what tstyles wrote to settings.json." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host "  Nothing was written. Fix that file: deleting it lets tstyles write again, but loses" -ForegroundColor Yellow
            Write-Host "  its record of any style already in settings.json." -ForegroundColor Yellow
        }
    }
}

function Reset-StyleVSCodeConfig {
    <#
    .SYNOPSIS
    Take a style back out of one editor's settings.json, by its record.

    .DESCRIPTION
    The record says what to undo, and Invoke-VSCodeStyleReset decides per key:
    restored, removed, or kept because the user changed it since. The record
    is cleared only AFTER the file is written: clearing it first and then
    failing the write would leave keys in the file that no command could name.

    -Variant names the editor; omitted, it is the one this terminal belongs
    to. Works off the RECORDED settings path, so uninstall can run it from any
    terminal. (`tstyles vscode off` calls it too, but refuses outside an
    editor terminal it can identify.)

    Returns @{ Status; Variant; Path; Kept; Restored; Removed; Detail }, Status
    one of reset, norecord, unknownvariant, statecorrupt, wontparse,
    writefailed. Detail says why for wontparse: the file could not be read, or
    does not parse. On reset it is set when the file was put back but the
    record could not be cleared afterwards.
    #>
    [CmdletBinding()]
    param([string]$Variant)

    $result = @{ Status = 'norecord'; Variant = $Variant; Path = $null; Kept = @(); Restored = @(); Removed = @(); Detail = $null }

    if (-not $Variant) {
        $t = Resolve-VSCodeTarget
        if (-not $t.Variant) { $result.Status = 'unknownvariant'; return $result }
        $Variant = $t.Variant
        $result.Variant = $Variant
    }

    $state = Read-VSCodeState
    if (-not $state.Ok) { $result.Status = 'statecorrupt'; return $result }
    $entry = $state.Entries[$Variant]
    if (-not $entry -or -not $entry.record) { return $result }
    $result.Path = $entry.settingsPath

    try {
        $text = Read-VSCodeSettingsText -Path $entry.settingsPath
    } catch {
        $result.Status = 'wontparse'; $result.Detail = 'it could not be read'
        return $result
    }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) {
        $result.Status = 'wontparse'; $result.Detail = 'it does not parse as a JSON object'
        return $result
    }

    $r = Invoke-VSCodeStyleReset -Text $text -Record $entry.record
    if ($r.Text -cne $text) {
        try {
            Write-SettingsAtomic -Path $entry.settingsPath -Json $r.Text
        } catch {
            $result.Status = 'writefailed'
            return $result
        }
    }
    try {
        Set-VSCodeStateEntry -Variant $Variant -Record $null
    } catch {
        # The file is clean, but the record still names the style's values, so
        # the next reset or apply would take the user's own settings for hand
        # edits. Say so rather than leave it to be misread later.
        $result.Detail = 'its record could not be cleared'
    }

    $result.Status   = 'reset'
    $result.Kept     = @($r.Kept)
    $result.Restored = @($r.Restored)
    $result.Removed  = @($r.Removed)
    return $result
}

function Show-VSCodeResetResult {
    # Say what Reset-StyleVSCodeConfig did. Quiet on 'norecord': nothing of
    # ours was there, and saying so on every reset in every VS Code terminal
    # would be noise. No leading blank line: it is printed inside other
    # commands' blocks (reset, uninstall, `tstyles vscode off`).
    # -Uninstalling: uninstall has removed the module by then; its sign-off says what to do instead.
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result, [switch]$Uninstalling)

    if (-not $Result) { return }
    switch ($Result.Status) {
        'reset' {
            # Filtered, not counted: @() around a missing member is one $null,
            # which would claim a key was taken out when none was.
            $undone = @(@($Result.Restored) + @($Result.Removed) | Where-Object { $_ })
            if ($undone.Count -gt 0) {
                Write-Host ("  Took the style back out of {0}'s settings.json." -f $Result.Variant) -ForegroundColor DarkGray
            } else {
                Write-Host ("  Found none of the style left in {0}'s settings.json to take out." -f $Result.Variant) -ForegroundColor DarkGray
            }
            foreach ($k in @($Result.Kept)) {
                Write-Host ("  Left {0} as you set it (you changed it after the style wrote it)." -f $k) -ForegroundColor DarkGray
            }
            if ($Result.Detail) {
                Write-Host ("  But {0}, so the next apply or reset may wrongly call some of your settings hand edits." -f $Result.Detail) -ForegroundColor Yellow
            }
        }
        'unknownvariant' {
            Write-Host "  Couldn't tell which editor this terminal belongs to, so no settings.json" -ForegroundColor Yellow
            Write-Host "  was touched." -ForegroundColor Yellow
        }
        'statecorrupt' {
            Write-Host ("  Could not read {0}, which records what tstyles wrote to settings.json," -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            if ($Uninstalling) {
                Write-Host "  so nothing was taken out of it." -ForegroundColor Yellow
            } else {
                Write-Host "  so nothing was taken out of it. Fix that file and reset again -- deleting it would" -ForegroundColor Yellow
                Write-Host "  leave the style in settings.json with no record to take it out by." -ForegroundColor Yellow
            }
        }
        'wontparse' {
            Write-Host ("  Could not edit {0} safely: {1}, so the style was left in it." -f $Result.Path, $Result.Detail) -ForegroundColor Yellow
            if (-not $Uninstalling) {
                Write-Host "  Fix the file and reset again -- the record of what to take out is kept." -ForegroundColor Yellow
            }
        }
        'writefailed' {
            Write-Host ("  Could not write {0}, so the style is still in it." -f $Result.Path) -ForegroundColor Yellow
            if (-not $Uninstalling) {
                Write-Host "  The record of what to take out is kept; reset again once it can be written." -ForegroundColor Yellow
            }
        }
    }
}

function New-VSCodePreviewSession {
    <#
    .SYNOPSIS
    The picker's VS Code state for one run, or $null when it previews colours
    only.

    .DESCRIPTION
    The picker's body needs a console and a keypress loop no test can drive,
    so everything VS Code does in it lives here, as data a test can hold:
    the file's exact original text, the record of the style that was on when
    the picker opened, and the record of whatever preview is on disk now.

    The stored record follows the file: each preview saves its record before
    it writes (Invoke-VSCodePreview), and Esc puts the record of what it puts
    back in step with the file -- before the write when a style goes back in,
    after it when the write only takes ours out (Restore-VSCodePreview). So a
    picker killed outright -- the terminal closed, no Esc and no finally --
    leaves a preview the stored record names, and tstyles reset takes it out.
    RecordAhead marks the times the record may have got ahead of the file.

    Asks first (once per editor) when nobody has answered -- the picker calls
    this below its console guard, so there is someone to ask. $null when the
    writer is off, or when the file does not parse: previews would refuse
    anyway, and Enter reports the reason through the publisher.
    #>
    [CmdletBinding()]
    param()

    if ((Request-VSCodeWriterConsent) -ne 'active') { return $null }
    $w = Get-VSCodeWriterState
    if ($w.Status -ne 'active') { return $null }

    $existed = [System.IO.File]::Exists($w.Path)
    # A file that cannot be read gets no session: there would be nothing exact
    # to put back on Esc, and a preview written over it would replace it. Enter
    # still reaches the publisher, which says why it wrote nothing.
    try { $text = Read-VSCodeSettingsText -Path $w.Path } catch { return $null }
    if (-not (Test-VSCodeSettingsReadable -Text $text)) { return $null }

    $start = $null
    if ($w.Entry) { $start = $w.Entry.record }
    return @{
        Variant         = $w.Variant
        Path            = $w.Path
        OriginalText    = $text
        OriginalExisted = $existed
        StartRecord     = $start
        OnDiskRecord    = $start
        LastWrittenText = $null
        Cache           = @{}
        BackedUp        = $false
        Backup          = $null
        # Set while the stored record may name text the file does not hold:
        # between a preview's or a commit's record save and its write, and
        # after a failed write whose record could not be put back.
        # Restore-VSCodePreview puts the right one back.
        RecordAhead     = $false
    }
}

function Invoke-VSCodePreview {
    <#
    .SYNOPSIS
    Put one style's preview into settings.json. Returns written, current,
    changed, wontparse or failed.

    .DESCRIPTION
    Always computed from the ORIGINAL text, undoing the style that was on when
    the picker opened -- never from the previous preview, so previews cannot
    build on each other. Cached per style: one apply costs 0.2-1.3 s depending
    on the file (measured), and arrowing back to a style should not pay twice.

    The preview's record is saved BEFORE the preview is written, as for every
    write in this file, and put back if the write fails; a record that cannot
    be saved writes no preview. A picker can end without its finally: closing
    the terminal tab, Kill Terminal and quitting VS Code all send SIGHUP, which
    ends pwsh outright. The preview left behind is then one the stored record
    names, and tstyles reset takes it out. A preview is still not an apply --
    Enter is. Esc over an unchanged file puts the stored record back as the
    picker found it; after an outside edit it saves the record of what it
    merged (see Restore-VSCodePreview). A write that fails, with a record that
    cannot be put back either, leaves RecordAhead set for Esc to put right.

    'changed': the file no longer holds what the session last left in it, so
    somebody else wrote it while the picker was open. Nothing is written over
    that edit. Esc and Enter both start from the file as it is now, so both
    keep the edit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir
    )

    if (-not $Session.Cache.ContainsKey($StyleName)) {
        $base = $Session.OriginalText
        if (-not $base.Trim()) { $base = '{}' }
        $a = Invoke-VSCodeStyleApply -Text $base -StyleDir $StyleDir -StyleName $StyleName -PreviousRecord $Session.StartRecord
        if ($a.Status -ne 'applied') { return 'wontparse' }
        $Session.Cache[$StyleName] = @{ Text = $a.Text; Record = $a.Record }
    }
    $p = $Session.Cache[$StyleName]

    $onDiskText = $Session.OriginalText
    if ($null -ne $Session.LastWrittenText) { $onDiskText = $Session.LastWrittenText }
    if ($p.Text -ceq $onDiskText) {
        $Session.OnDiskRecord = $p.Record
        return 'current'
    }

    try {
        # VS Code's settings UI, Settings Sync or a hand edit can write the
        # file while the picker is open. A preview computed from the original
        # would throw that edit away.
        if ((Read-VSCodeSettingsText -Path $Session.Path) -cne $onDiskText) { return 'changed' }
        if (-not $Session.BackedUp) {
            if (-not $Session.StartRecord -and $Session.OriginalExisted -and $Session.OriginalText) {
                $Session.Backup = Save-FirstTouchBackup -Path $Session.Path -Content $Session.OriginalText
            }
            $Session.BackedUp = $true
        }
        # Record first, as for every write that puts keys in. A picker can die
        # without its finally -- closing the terminal ends pwsh on SIGHUP -- and
        # the preview left behind must still be one a reset can take out.
        Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $p.Record
        $Session.RecordAhead = $true
    } catch {
        return 'failed'
    }
    try {
        Write-SettingsAtomic -Path $Session.Path -Json $p.Text
    } catch {
        # The file still holds what OnDiskRecord describes, so the record must
        # too. If putting it back fails as well, RecordAhead stays set and
        # Restore-VSCodePreview tries again on Esc.
        try {
            Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.OnDiskRecord
            $Session.RecordAhead = $false
        } catch {
            # Left to RecordAhead: nothing more can be done from here.
        }
        return 'failed'
    }
    $Session.LastWrittenText = $p.Text
    $Session.OnDiskRecord = $p.Record
    $Session.RecordAhead = $false
    return 'written'
}

function Restore-VSCodePreview {
    <#
    .SYNOPSIS
    Esc, Ctrl+C or an error in the picker: take the preview back out.
    Returns @{ Status; Path; Kept; Replaced; Reason; Detail }, Status none,
    restored, merged, failed or recordstale. Never throws.

    .DESCRIPTION
    Two cases, decided by whether the file still holds what the picker last
    wrote.

      It does    -> the original text goes back, byte for byte -- or the file
                    goes away again, if there was none -- and the stored
                    record goes back to the one the picker found. With a style
                    on before the picker, that record goes back first, as the
                    publisher's does. With none, the file goes first, so a
                    terminal closed in between leaves the preview's record
                    beside the user's own file rather than a preview no record
                    names; a record that then cannot be cleared is Detail.
      It doesn't -> somebody edited settings.json while the picker was open,
                    most likely in VS Code itself. Writing the original back
                    would throw that edit away. Instead the preview is undone
                    by its own record, which leaves the edit standing, and the
                    style that was on before is put back over it. Kept and
                    Replaced split the way the publisher's do, through the
                    same Split-VSCodeKept: when the starting style sets a key
                    the user edited, that key is replaced, and the edited
                    value is what a reset restores. The record is saved
                    before the file when the starting style goes back in;
                    with none to put back, after it, as above.

    Nothing of the picker's in the file is 'none' -- unless a preview's or a
    commit's write failed and its record could not be put back (RecordAhead).
    Then the record the file matches goes back here, and 'recordstale' says so
    if even that cannot be written.

    A file that no longer parses is not undone at all. The record's offsets no
    longer mean what the record thinks, so this fails rather than splices.

    On failure the stored record is left naming the preview, because the
    preview is what the file still holds: `tstyles reset` can then take it
    out. Every preview saved its own record before it was written, so a
    failure before this has moved the record leaves that one on file. A
    failure after it moved the record puts it back, and so does a failure
    while RecordAhead says an earlier write left the record ahead of the file.
    If putting it back fails too, Detail says so, and the message does not
    promise the reset.

    After either success nothing is left written, so a second call returns
    'none' -- which is what the picker's finally needs after an Esc.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Session)

    $out = @{ Status = 'none'; Path = $Session.Path; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
    if ($null -eq $Session.LastWrittenText) {
        # Nothing of the picker's is in settings.json. A preview whose write
        # failed, and whose record could not be put back either, still left the
        # record naming text that never landed: put back the one the file
        # matches.
        if ($Session.RecordAhead) {
            try {
                Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.OnDiskRecord
                $Session.RecordAhead = $false
            } catch {
                $out.Status = 'recordstale'
                $out.Reason = "$_"
            }
        }
        return $out
    }

    # The original text goes back byte for byte -- or the file goes away again,
    # if there was none.
    $putOriginalBack = {
        if ($Session.OriginalExisted) {
            Write-SettingsAtomic -Path $Session.Path -Json $Session.OriginalText
        } elseif ([System.IO.File]::Exists($Session.Path)) {
            Remove-Item -LiteralPath $Session.Path -Force -ErrorAction Stop
        }
    }

    # Set once a record save below has landed. Until then the preview's own
    # record, saved before the preview was written, is the one on file.
    $recordMoved = $false
    try {
        $now = Read-VSCodeSettingsText -Path $Session.Path
        if ($now -ceq $Session.LastWrittenText) {
            if ($Session.StartRecord) {
                # A style was on before the picker: its record goes back first,
                # as the publisher's does. Either order leaves a moment when the
                # record and the file name different styles.
                Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.StartRecord
                $recordMoved = $true
                & $putOriginalBack
            } else {
                # No style before the picker: this write only takes ours out, so
                # the file goes back FIRST, as in the reset. A terminal closed
                # between the two writes then leaves the preview's record beside
                # the user's own file -- a reset reads its keys as already gone,
                # or as the user's own -- rather than a preview that no record
                # names.
                & $putOriginalBack
                try {
                    Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $null
                } catch {
                    $out.Detail = 'its record could not be cleared'
                }
            }
            $Session.OnDiskRecord = $Session.StartRecord
            # The file is back. A record that could not then be cleared names
            # keys the file no longer holds -- the harmless kind, reported in
            # Detail -- so there is nothing for a later call to put right.
            $Session.RecordAhead = $false
            $out.Status = 'restored'
        } else {
            if (-not (Test-VSCodeSettingsReadable -Text $now)) {
                throw 'it changed while the picker was open and no longer parses as a JSON object'
            }
            $undo = Invoke-VSCodeStyleReset -Text $now -Record $Session.OnDiskRecord
            $text = $undo.Text
            $record = $null
            $startStyle = $null
            if ($Session.StartRecord) { $startStyle = $Session.StartRecord.Style }
            if ($startStyle) {
                $startDir = Get-StyleDir -StyleName $startStyle
                if ($startDir) {
                    $re = Invoke-VSCodeStyleApply -Text $text -StyleDir $startDir -StyleName $startStyle
                    if ($re.Status -eq 'applied') { $text = $re.Text; $record = $re.Record }
                }
            }
            if ($record) {
                # Record first: this write puts the starting style's keys back in.
                Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $record
                $recordMoved = $true
                Write-SettingsAtomic -Path $Session.Path -Json $text
            } else {
                # No style to put back: this write only takes ours out, so the
                # file goes first, as in the restored arm above.
                Write-SettingsAtomic -Path $Session.Path -Json $text
                try {
                    Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $null
                } catch {
                    $out.Detail = 'its record could not be cleared'
                }
            }
            $Session.OnDiskRecord = $record
            $Session.RecordAhead = $false
            $split = Split-VSCodeKept -Kept $undo.Kept -Record $record
            $out.Status   = 'merged'
            $out.Kept     = $split.Left
            $out.Replaced = $split.Replaced
        }
        $Session.LastWrittenText = $null
    } catch {
        # Reason first, before the try below can replace $_.
        $out.Status = 'failed'
        $out.Reason = "$_"
        # The record goes back to what the file still holds if this call moved
        # it, or if an earlier write left it ahead of the file (RecordAhead: a
        # preview, or a commit, whose write and rollback both failed). Left
        # alone otherwise, it is already that record.
        if ($recordMoved -or $Session.RecordAhead) {
            try {
                Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.OnDiskRecord
                $Session.RecordAhead = $false
            } catch {
                $out.Detail = 'its undo record could not be saved either'
                $Session.RecordAhead = $true
            }
        }
    }
    return $out
}

function Undo-VSCodeFailedCommit {
    <#
    .SYNOPSIS
    The picker's Enter when Publish-StyleVSCodeConfig did not write: put the
    file, and the record with it, back as the picker found them. Returns
    Restore-VSCodePreview's result.

    .DESCRIPTION
    A commit whose write and rollback both failed says so in -Result's Detail
    ("its undo record could not be restored either"). The restore here can
    put that record right, and once it has -- the session no longer marks the
    record ahead of the file -- that sentence is no longer true, so it is
    dropped before the picker prints the commit's result.

    Only on 'writefailed'. On 'wontparse' Detail is why the file was refused,
    and that stays true whatever the restore does. A record the restore could
    not clear also leaves RecordAhead false -- it names keys the file no
    longer holds -- and the restore's own Detail then says so.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][hashtable]$Result
    )

    $restore = Restore-VSCodePreview -Session $Session
    if ($Result.Status -eq 'writefailed' -and -not $Session.RecordAhead) { $Result.Detail = $null }
    return $restore
}

function Show-VSCodeRestoreResult {
    # What the picker's Esc did to settings.json, when that is worth a line:
    # quiet for 'none' and 'restored', which are the file exactly as it was --
    # unless the record beside it could not be put right.
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    # Filtered, not just wrapped: @() around a missing member is one $null,
    # which would print a line naming nothing.
    $replaced = @($Result.Replaced | Where-Object { $_ })
    $kept     = @($Result.Kept | Where-Object { $_ })
    switch ($Result.Status) {
        'restored' {
            if ($Result.Detail) {
                Write-Host ""
                Write-Host ("  settings.json is back as it was, but {0}, so the next apply or" -f $Result.Detail) -ForegroundColor Yellow
                Write-Host "  reset may wrongly call some of your settings hand edits." -ForegroundColor Yellow
            }
        }
        'recordstale' {
            Write-Host ""
            Write-Host ("  {0}" -f $Result.Reason) -ForegroundColor Yellow
            Write-Host "  settings.json was not changed, but the record in that file still names a style" -ForegroundColor Yellow
            Write-Host "  that never reached it, so the next apply or reset may wrongly call some of your" -ForegroundColor Yellow
            Write-Host "  settings hand edits." -ForegroundColor Yellow
        }
        'merged' {
            Write-Host ""
            Write-Host "  settings.json changed while the picker was open, so the preview was taken" -ForegroundColor Yellow
            Write-Host "  back out of it instead of the file being put back as it was." -ForegroundColor Yellow
            if ($replaced.Count -eq 0) {
                Write-Host "  Your edit is still there." -ForegroundColor Yellow
            } else {
                Write-Host "  What you changed is still there, except where the style you started with" -ForegroundColor Yellow
                Write-Host "  sets a key again:" -ForegroundColor Yellow
                foreach ($k in $replaced) {
                    Write-Host ("  Replaced {0}, which you had changed by hand; tstyles reset puts yours back." -f $k) -ForegroundColor DarkGray
                }
            }
            foreach ($k in $kept) {
                Write-Host ("  Left {0} as you set it." -f $k) -ForegroundColor DarkGray
            }
            if ($Result.Detail) {
                Write-Host ("  But {0}, so the next apply or reset may wrongly call some of your" -f $Result.Detail) -ForegroundColor Yellow
                Write-Host "  settings hand edits." -ForegroundColor Yellow
            }
        }
        'failed' {
            Write-Host ""
            Write-Host ("  Could not put {0} back: {1}" -f $Result.Path, $Result.Reason) -ForegroundColor Red
            if ($Result.Detail) {
                Write-Host ("  The preview is still in it, and {0}, so tstyles reset cannot take it out." -f $Result.Detail) -ForegroundColor Red
            } else {
                Write-Host "  The preview is still in it; tstyles reset takes it out once the file" -ForegroundColor Red
                Write-Host "  parses and can be written." -ForegroundColor Red
            }
        }
    }
}

function Show-VSCodeWriterStatus {
    # `tstyles vscode` with no action: what is on record, for this editor and
    # every other one that has been asked.
    [CmdletBinding()]
    param()

    $t = Resolve-VSCodeTarget
    $state = Read-VSCodeState
    Write-Host ""
    if (-not $state.Ok) {
        Write-Host ("  Could not read {0}." -f $state.Path) -ForegroundColor Yellow
        Write-Host "  It records what tstyles wrote to settings.json. Fix it: deleting it lets tstyles" -ForegroundColor Yellow
        Write-Host "  write again, but loses its record of any style already saved there." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    if ($t.Variant) {
        Write-Host ("  This terminal belongs to {0}." -f $t.Variant)
        if ($t.Status -eq 'nodir') {
            Write-Host "  Its settings folder does not exist yet, so nothing is saved there:" -ForegroundColor Yellow
            Write-Host ("    {0}" -f [System.IO.Path]::GetDirectoryName($t.Path)) -ForegroundColor DarkGray
        }
    } elseif ((Get-TerminalKind) -eq 'VSCode') {
        Write-Host "  This looks like a VS Code-family terminal, but tstyles can't tell which" -ForegroundColor Yellow
        Write-Host "  editor it is, so it will not write any settings.json from here." -ForegroundColor Yellow
    }

    $names = @($state.Entries.Keys | Sort-Object)
    if ($t.Variant -and $names -notcontains $t.Variant) { $names = @($t.Variant) + $names }
    if ($names.Count -eq 0) {
        Write-Host "  No VS Code editor has been asked yet." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    foreach ($n in $names) {
        $e = $state.Entries[$n]
        $consent = ''; $style = $null; $path = $null
        if ($e) {
            $consent = $e.consent
            $path = $e.settingsPath
            if ($e.record) { $style = $e.record.Style }
        }
        if (-not $path -and $n -eq $t.Variant) { $path = $t.Path }
        $saving = switch ($consent) {
            'yes'   { 'saving: on' }
            'no'    { 'saving: off' }
            default { 'saving: not asked yet' }
        }
        $saved = 'no style saved'
        if ($style) { $saved = "style saved: $style" }
        Write-Host ("  {0,-16}{1}, {2}" -f $n, $saving, $saved)
        if ($path) { Write-Host ("  {0,-16}{1}" -f '', $path) -ForegroundColor DarkGray }
    }
    Write-Host ""
}

function Invoke-TerminalStyleVSCode {
    <#
    .SYNOPSIS
    `tstyles vscode [on|off]`: the way to change an answer an apply asks for
    only once.

    .DESCRIPTION
    on   records a yes for this editor. It writes nothing now -- the next apply
         does, and saying otherwise would be a claim about a write that has
         not happened.
    off  takes the saved style back out FIRST, then records a no (and clears
         the record, should the reset have left it). If the style cannot be
         taken out, the answer on record is not changed and the command says
         so: a no on record beside keys still in the file would leave the user
         believing they had been removed.
    #>
    [CmdletBinding()]
    param([string]$Action)

    if (-not $Action) { Show-VSCodeWriterStatus; return }
    if ($Action -ne 'on' -and $Action -ne 'off') {
        Write-Host ""
        Write-Host ("  Unknown vscode action '{0}'. Use: tstyles vscode [on|off]" -f $Action) -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $t = Resolve-VSCodeTarget
    Write-Host ""
    if (-not $t.Variant) {
        Write-Host "  Can't tell which editor this terminal belongs to -- VS Code, Insiders," -ForegroundColor Yellow
        Write-Host "  VSCodium, Cursor or Windsurf -- so there is no settings.json to turn this" -ForegroundColor Yellow
        Write-Host ("  {0} for. Run it from that editor's own terminal." -f $Action) -ForegroundColor Yellow
        Write-Host ""
        return
    }

    if ($Action -eq 'on') {
        try {
            Set-VSCodeStateEntry -Variant $t.Variant -SettingsPath $t.Path -Consent 'yes'
        } catch {
            Write-Host ("  Could not save that to {0}." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host ""
            return
        }
        Write-Host ("  From the next apply, tstyles saves styles to {0}'s settings.json:" -f $t.Variant)
        Write-Host ("    {0}" -f $t.Path) -ForegroundColor DarkGray
        Write-Host "  Nothing was written now." -ForegroundColor DarkGray
        if ($t.Status -eq 'nodir') {
            Write-Host "  That folder does not exist yet, so an apply will say so until the editor" -ForegroundColor Yellow
            Write-Host "  has created it." -ForegroundColor Yellow
        }
        Write-Host ""
        return
    }

    $r = Reset-StyleVSCodeConfig -Variant $t.Variant
    if ($r.Status -ne 'reset' -and $r.Status -ne 'norecord') {
        Show-VSCodeResetResult -Result $r
        Write-Host "  Saving was not changed; the style has to come out of settings.json first." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    try {
        # -Record $null too: a reset that put the file back but could not clear
        # its record gets a second chance here, so the no is not left beside a
        # record of keys the file no longer holds.
        Set-VSCodeStateEntry -Variant $t.Variant -SettingsPath $t.Path -Consent 'no' -Record $null
    } catch {
        Show-VSCodeResetResult -Result $r
        # Read back, not assumed: "still on" is only true of an editor that had
        # said yes. One never asked, or already off, is simply left as it was.
        $now = Read-VSCodeState
        if ($now.Ok -and $now.Entries[$t.Variant] -and $now.Entries[$t.Variant].consent -eq 'yes') {
            Write-Host ("  Could not save that to {0}, so saving is still on." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        } else {
            Write-Host ("  Could not save that to {0}." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        }
        Write-Host ""
        return
    }
    # Shown after the write above, not before: that write cleared any record
    # the reset could not, so a warning about one would no longer be true. On
    # 'reset', a record left uncleared is the only thing Detail ever says.
    if ($r.Status -eq 'reset') { $r.Detail = $null }
    Show-VSCodeResetResult -Result $r
    Write-Host ("  tstyles will not write {0}'s settings.json again." -f $t.Variant)
    Write-Host "  tstyles vscode on turns it back on."
    Write-Host ""
}

function Get-VSCodeUninstallTarget {
    # The editors whose settings.json holds a saved style: one object per
    # editor, @{ Variant; Path }, from the RECORD rather than from detection --
    # uninstall runs from any terminal, and has to reach every editor.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Ok) { return }
    foreach ($name in @($State.Entries.Keys | Sort-Object)) {
        $e = $State.Entries[$name]
        if ($e.record) { [pscustomobject]@{ Variant = $name; Path = $e.settingsPath } }
    }
}
