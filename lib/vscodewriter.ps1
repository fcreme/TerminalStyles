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
    Write-SettingsAtomic -Path (Get-VSCodeStatePath) -Json ($out | ConvertTo-Json -Depth 10)
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
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
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
