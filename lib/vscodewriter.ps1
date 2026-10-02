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
            try { Set-VSCodeStateEntry -Variant $w.Variant -SettingsPath $w.Path -Record $stored } catch { }
            $result.Status = 'writefailed'; $result.FailedPath = $w.Path
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
        }
        'statecorrupt' {
            Write-Host ("  Could not read {0}, which records what tstyles wrote to settings.json." -f (Get-VSCodeStatePath)) -ForegroundColor Yellow
            Write-Host "  Nothing was written, so nothing became impossible to undo. Fix or delete that file." -ForegroundColor Yellow
        }
    }
}
