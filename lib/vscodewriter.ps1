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
#   settings.json is written, and put back if the write fails. A crash can leave
#   a record naming keys that never landed -- a later reset finds them absent,
#   which is harmless -- and never a key in the user's file that no command can
#   name.
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
    if ($answer -eq 'yes') { return 'active' }
    return 'declined'
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
    holds a PREVIEW, described by the session's record rather than the stored
    one; undoing it by the stored record would miss the preview's keys and
    take them for the user's own edits.

    Kept is split in two on the way out. The apply's Kept names keys the
    outgoing style's undo left alone because the user had changed them; the
    incoming style then writes over any of those it sets itself, keeping the
    user's value as the one a reset restores. "Left as you set it" is only
    true of the others.
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
                Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $stored
            } catch {
                # Both writes failed. The record now describes keys that never
                # landed, and the keys still in the file are named by no record --
                # say so, rather than let a later reset leave them without a word.
                $result.Detail = 'its undo record could not be restored either'
            }
            return $result
        }
    }

    $writtenNames = @(@($a.Record.Wrote) | ForEach-Object { @($_.Path) -join '/' })
    $kept = @($a.Kept)
    $ids = @(@($a.Record.Wrote) |
             Where-Object { @($_.Path).Count -eq 2 -and $_.Path[0] -eq 'workbench.colorCustomizations' } |
             ForEach-Object { $_.Path[1] })
    # Assigned, not wrapped: Get-VSCodeColorOverride returns ,$arr.
    $overrides = Get-VSCodeColorOverride -Text $a.Text -Ids $ids

    $result.Status    = 'written'
    $result.Kept      = @($kept | Where-Object { $writtenNames -notcontains $_ })
    $result.Replaced  = @($kept | Where-Object { $writtenNames -contains $_ })
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
            Write-Host "  Couldn't tell which editor this terminal belongs to, so nothing was saved" -ForegroundColor Yellow
            Write-Host "  -- the colors apply to this terminal only." -ForegroundColor Yellow
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
    to. Works off the RECORDED settings path, so uninstall and `tstyles vscode
    off` can run it from any terminal.

    Returns @{ Status; Variant; Path; Kept; Restored; Removed; Detail }, Status
    one of reset, norecord, unknownvariant, statecorrupt, wontparse,
    writefailed. Detail says why for wontparse: the file could not be read, or
    does not parse.
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
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    switch ($Result.Status) {
        'reset' {
            Write-Host ("  Took the style back out of {0}'s settings.json." -f $Result.Variant) -ForegroundColor DarkGray
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
            Write-Host "  so nothing was taken out of it. Fix that file and reset again -- deleting it would" -ForegroundColor Yellow
            Write-Host "  leave the style in settings.json with no record to take it out by." -ForegroundColor Yellow
        }
        'wontparse' {
            Write-Host ("  Could not edit {0} safely: {1}, so the style was left in it." -f $Result.Path, $Result.Detail) -ForegroundColor Yellow
            Write-Host "  Fix the file and reset again -- the record of what to take out is kept." -ForegroundColor Yellow
        }
        'writefailed' {
            Write-Host ("  Could not write {0}, so the style is still in it." -f $Result.Path) -ForegroundColor Yellow
            Write-Host "  The record of what to take out is kept; reset again once it can be written." -ForegroundColor Yellow
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

    The state file is not touched. A preview is not an apply; Enter is, and
    Esc must find the stored record exactly as the picker found it.

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
        Write-SettingsAtomic -Path $Session.Path -Json $p.Text
    } catch {
        return 'failed'
    }
    $Session.LastWrittenText = $p.Text
    $Session.OnDiskRecord = $p.Record
    return 'written'
}

function Restore-VSCodePreview {
    <#
    .SYNOPSIS
    Esc, Ctrl+C or an error in the picker: take the preview back out.
    Returns @{ Status; Path; Kept; Replaced; Reason; Detail }, Status none,
    restored, merged or failed. Never throws.

    .DESCRIPTION
    Two cases, decided by whether the file still holds what the picker last
    wrote.

      It does    -> the original text goes back, byte for byte -- or the file
                    goes away again, if there was none.
      It doesn't -> somebody edited settings.json while the picker was open,
                    most likely in VS Code itself. Writing the original back
                    would throw that edit away. Instead the preview is undone
                    by its own record, which leaves the edit standing, and the
                    style that was on before is put back over it. Kept and
                    Replaced split the way the publisher's do: when the
                    starting style sets a key the user edited, that key is
                    replaced, and the edited value is what a reset restores.

    A file that no longer parses is not undone at all. The record's offsets no
    longer mean what the record thinks, so this fails rather than splices.

    On failure the stored record is set to the preview's, because the preview
    is what the file still holds: `tstyles reset` can then take it out. If
    that record cannot be saved either, Detail says so, and the message does
    not promise the reset.

    After either success nothing is left written, so a second call returns
    'none' -- which is what the picker's finally needs after an Esc.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Session)

    $out = @{ Status = 'none'; Path = $Session.Path; Kept = @(); Replaced = @(); Reason = $null; Detail = $null }
    if ($null -eq $Session.LastWrittenText) { return $out }

    try {
        $now = Read-VSCodeSettingsText -Path $Session.Path
        if ($now -ceq $Session.LastWrittenText) {
            if ($Session.OriginalExisted) {
                Write-SettingsAtomic -Path $Session.Path -Json $Session.OriginalText
            } elseif ([System.IO.File]::Exists($Session.Path)) {
                Remove-Item -LiteralPath $Session.Path -Force -ErrorAction Stop
            }
            $Session.OnDiskRecord = $Session.StartRecord
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
            # Record first, as everywhere in this file.
            Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $record
            Write-SettingsAtomic -Path $Session.Path -Json $text
            $Session.OnDiskRecord = $record
            $rewritten = @()
            if ($record) { $rewritten = @(@($record.Wrote) | ForEach-Object { @($_.Path) -join '/' }) }
            $out.Status   = 'merged'
            $out.Kept     = @(@($undo.Kept) | Where-Object { $rewritten -notcontains $_ })
            $out.Replaced = @(@($undo.Kept) | Where-Object { $rewritten -contains $_ })
        }
        $Session.LastWrittenText = $null
    } catch {
        # Reason first, before the try below can replace $_.
        $out.Status = 'failed'
        $out.Reason = "$_"
        try {
            Set-VSCodeStateEntry -Variant $Session.Variant -SettingsPath $Session.Path -Record $Session.OnDiskRecord
        } catch {
            $out.Detail = 'its undo record could not be saved either'
        }
    }
    return $out
}

function Show-VSCodeRestoreResult {
    # What the picker's Esc did to settings.json, when that is worth a line:
    # quiet for 'none' and 'restored', which are the file exactly as it was.
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Result)

    if (-not $Result) { return }
    # Filtered, not just wrapped: @() around a missing member is one $null,
    # which would print a line naming nothing.
    $replaced = @($Result.Replaced | Where-Object { $_ })
    $kept     = @($Result.Kept | Where-Object { $_ })
    switch ($Result.Status) {
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
        }
        'failed' {
            Write-Host ""
            Write-Host ("  Could not put {0} back: {1}" -f $Result.Path, $Result.Reason) -ForegroundColor Red
            if ($Result.Detail) {
                Write-Host ("  The preview is still in it, and {0}, so tstyles reset cannot take it out." -f $Result.Detail) -ForegroundColor Red
            } else {
                Write-Host "  The preview is still in it; tstyles reset takes it out." -ForegroundColor Red
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
    off  takes the saved style back out FIRST, then records a no. If the style
         cannot be taken out, saving is left on and the command says so: a no
         on record beside keys still in the file would leave the user believing
         they had been removed.
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
    Show-VSCodeResetResult -Result $r
    if ($r.Status -ne 'reset' -and $r.Status -ne 'norecord') {
        Write-Host "  Saving stays on until the style can be taken out first." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    try {
        Set-VSCodeStateEntry -Variant $t.Variant -SettingsPath $t.Path -Consent 'no'
    } catch {
        Write-Host ("  Could not save that to {0}." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
        Write-Host ""
        return
    }
    Write-Host ("  tstyles will not write {0}'s settings.json again." -f $t.Variant)
    Write-Host "  tstyles vscode on turns it back on."
    Write-Host ""
}
