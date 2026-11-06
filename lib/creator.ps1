# The state behind `tstyles create`, and its live preview in Windows Terminal.
#
# The state is one hashtable the creator's pages read and change. The preview
# writes it through the same recorded session as the picker and the tuner
# (lib/previewsession.ps1), so Esc and a closed tab put settings.json back the
# same way, and through New-CreatedThemeObject, the writer Save-CreatedStyle
# is handed, so what the preview shows is what the saved style holds.

# The scheme's name while the creator is open. The style's own name is asked
# for only at the end, and a scheme named after it could replace one already
# in settings.json for as long as the preview is up.
$script:CreatorPreviewName = 'tstyles create'

function New-CreatorState {
    <#
    .SYNOPSIS
    The creator's starting state for one image: its palette, and every default.

    .DESCRIPTION
    Pixels are the ints Read-ImagePixels emitted, already read. Edited is the
    set of colour slots the user has set by hand; Update-CreatorPalette spares
    them. Name stays $null until the last page.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Pixels,
        [Parameter(Mandatory)][string]$ImagePath
    )
    $scheme = New-PaletteFromPixels -Pixels $Pixels -Name $script:CreatorPreviewName
    $accent = Get-PaletteAccent -Scheme $scheme
    if (-not $accent) { $accent = $scheme.foreground }
    @{
        Step              = 0
        ImagePath         = $ImagePath
        Pixels            = $Pixels
        Scheme            = $scheme
        Edited            = New-Object 'System.Collections.Generic.HashSet[string]'
        ImageOpacity      = 0.35
        StretchMode       = 'uniformToFill'
        Alignment         = 'center'
        FontFace          = 'Cascadia Code'
        FontSize          = 11
        CursorShape       = 'bar'
        PromptShape       = 'minimal'
        Symbol            = '$'
        PromptPathColor   = $accent
        PromptSymbolColor = $scheme.foreground
        Name              = $null
    }
}

function Get-CreatorColorSlot {
    # The scheme's own spelling of a colour slot, or $null. 'name' is not one.
    param([Parameter(Mandatory)]$Scheme, [Parameter(Mandatory)][string]$Slot)
    if ($Slot -eq 'name') { return $null }
    $p = @($Scheme.PSObject.Properties | Where-Object { $_.Name -eq $Slot })
    if ($p.Count -eq 0) { return $null }
    $p[0].Name
}

function Set-CreatorColor {
    <#
    .SYNOPSIS
    Set one colour slot by hand, and mark it edited.

    .DESCRIPTION
    Any readable colour is taken, a hard-to-read one included:
    Get-CreatorWarnings says so, nothing here refuses it. Throws on a slot the
    scheme does not have, or a value that is not a colour, and then changes
    nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Slot,
        [Parameter(Mandatory)][string]$Hex
    )
    $name = Get-CreatorColorSlot -Scheme $State.Scheme -Slot $Slot
    if (-not $name) { throw "'$Slot' is not a colour slot of this scheme." }
    $norm = ConvertTo-NormalHex $Hex
    if (-not $norm) { throw "'$Hex' is not a colour (expected #rrggbb)." }
    $State.Scheme.$name = $norm
    [void]$State.Edited.Add($name)
}

function Update-CreatorPalette {
    <#
    .SYNOPSIS
    Pull the palette from the state's pixels again, keeping the edited slots.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $fresh = New-PaletteFromPixels -Pixels $State.Pixels -Name $script:CreatorPreviewName
    foreach ($p in $fresh.PSObject.Properties) {
        if ($p.Name -eq 'name' -or $State.Edited.Contains($p.Name)) { continue }
        if ($State.Scheme.PSObject.Properties.Match($p.Name).Count) {
            $State.Scheme.($p.Name) = $p.Value
        } else {
            $State.Scheme | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        }
    }
}

function Get-CreatorWarningSlots {
    <#
    .SYNOPSIS
    What will be hard to read, or will not show: @{ Unreadable; LowContrast }.

    .DESCRIPTION
    THE rule behind both renderings, Get-CreatorWarnings (one sentence each)
    and Get-CreatorWarningLine (the page's one line). Contrast against the
    background comes from Get-SchemeLowContrastSlots, the same bars the
    palette is pulled to (foreground 7:1), with the prompt's path and symbol
    colours held to the ANSI hues' 4.5:1 as 'prompt path colour' and 'prompt
    symbol colour'; a value that is not a colour from
    Get-SchemeUnreadableSlots, the slots the OSC packet would drop. Warnings
    only: the creator keeps the edit.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $unreadable = @(Get-SchemeUnreadableSlots -Scheme $State.Scheme | Where-Object { $_ -ne 'name' })
    $text = [ordered]@{}
    if ($State.ContainsKey('PromptPathColor')) { $text['prompt path colour'] = [string]$State.PromptPathColor }
    if ($State.ContainsKey('PromptSymbolColor')) { $text['prompt symbol colour'] = [string]$State.PromptSymbolColor }
    $low = @(Get-SchemeLowContrastSlots -Scheme $State.Scheme -Text $text)
    @{ Unreadable = [string[]]$unreadable; LowContrast = [string[]]$low }
}

function Get-CreatorWarnings {
    <#
    .SYNOPSIS
    One line per colour that will be hard to read, or will not show at all.

    .DESCRIPTION
    Get-CreatorWarningSlots' answer, a sentence each. Empty when everything
    reads.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][hashtable]$State)
    $w = Get-CreatorWarningSlots -State $State
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in $w.Unreadable) { $lines.Add(("{0} is not a colour, so it will not show." -f $k)) }
    foreach ($k in $w.LowContrast) { $lines.Add(("{0} is hard to read against the background." -f $k)) }
    # Callers wrap in @(): a bare return unrolls to nothing when empty.
    $lines.ToArray()
}

function Get-CreatorWarningLine {
    <#
    .SYNOPSIS
    Get-CreatorWarningSlots' answer as ONE line of at most -MaxLength
    characters, or $null when everything reads.

    .DESCRIPTION
    "Not a colour, will not show: cyan. Hard to read: red, green." One line
    whatever the count, so the page keeps its height; names that do not fit
    are counted ("... and 9 more.") rather than wrapped.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$State, [int]$MaxLength = 114)
    $w = Get-CreatorWarningSlots -State $State
    $groups = @(
        @{ Label = 'Not a colour, will not show'; Names = @($w.Unreadable) }
        @{ Label = 'Hard to read'; Names = @($w.LowContrast) }
    )
    $total = 0
    foreach ($g in $groups) { $total += $g.Names.Count }
    if ($total -eq 0) { return $null }
    $text = $null
    for ($keep = $total; $keep -ge 1; $keep--) {
        $left = $keep
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($g in $groups) {
            $n = [Math]::Min($left, $g.Names.Count)
            $left -= $n
            if ($n -gt 0) { $parts.Add(($g.Label + ': ' + (($g.Names[0..($n - 1)]) -join ', '))) }
        }
        $text = $parts -join '. '
        if ($keep -lt $total) { $text += (' and {0} more' -f ($total - $keep)) }
        $text += '.'
        if ($text.Length -le $MaxLength) { return $text }
    }
    $text
}

function New-CreatorPromptText {
    # The prompt a created style is saved with: New-StylePromptText from the
    # state's prompt choices, titled with the upper-cased name. No
    # -BranchColor: the git shape's branch takes the generator's default arm.
    # The save calls this, and the parity test renders what it returns, so
    # the prompt measured is the prompt shipped.
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name)
    New-StylePromptText -Shape $State.PromptShape -Symbol $State.Symbol `
        -PathColor $State.PromptPathColor -SymbolColor $State.PromptSymbolColor `
        -Title $Name.ToUpperInvariant()
}

function Get-CreatorTabColor {
    # The tab colour a created style gets: the palette's accent, else its
    # foreground, else grey. One rule, read by the preview and by the save, so
    # the tab the user saw is the tab they get.
    param([Parameter(Mandatory)]$Scheme)
    $tab = Get-PaletteAccent -Scheme $Scheme
    if (-not $tab) { $tab = ConvertTo-NormalHex $Scheme.foreground }
    if (-not $tab) { $tab = '#808080' }
    $tab
}

function Write-CreatorPreview {
    <#
    .SYNOPSIS
    Show the state in Windows Terminal: write the scratch style, merge it into
    the original settings.json text, and write that through the session.

    .DESCRIPTION
    Returns Write-FilePreview's status (written | current | changed | failed),
    or 'failed' when the scratch style cannot be built or the merge has
    nothing to write. Never throws. Every preview is built
    from -OriginalJson, never from the file as the last preview left it, so
    the record's copy of the original stays the only thing Esc needs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [AllowNull()][hashtable]$Session,
        [Parameter(Mandatory)][string]$ScratchDir,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][AllowEmptyString()][string]$OriginalJson
    )
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    # Merge-StyleIntoSettings finds the scheme by theme.colorScheme, so both
    # carry the placeholder name.
    $scheme = [pscustomobject][ordered]@{}
    foreach ($p in $State.Scheme.PSObject.Properties) {
        $scheme | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
    }
    $scheme | Add-Member -NotePropertyName name -NotePropertyValue $script:CreatorPreviewName -Force

    $tab = Get-CreatorTabColor -Scheme $scheme
    try {
        # Inside the try: it validates opacity and stretch mode, and a preview
        # never throws into the creator's key loop (Write-FilePreview's rule).
        $theme = New-CreatedThemeObject -Name $script:CreatorPreviewName -FontFace $State.FontFace `
            -FontSize $State.FontSize -CursorShape $State.CursorShape -ImageOpacity $State.ImageOpacity `
            -StretchMode $State.StretchMode -Alignment $State.Alignment -TabColor $tab
        if (-not [System.IO.Directory]::Exists($ScratchDir)) { [void][System.IO.Directory]::CreateDirectory($ScratchDir) }
        [System.IO.File]::WriteAllText((Join-Path $ScratchDir 'scheme.json'), ($scheme | ConvertTo-Json -Depth 16), $utf8)
        [System.IO.File]::WriteAllText((Join-Path $ScratchDir 'theme.json'), ($theme | ConvertTo-Json -Depth 16), $utf8)
        $text = Get-StylePreviewJson -OriginalJson $OriginalJson -StyleDir $ScratchDir -TargetName $Target `
            -BackgroundImage $State.ImagePath -BackgroundImageProvided $true
    } catch { return 'failed' }
    if ($null -eq $text) { return 'failed' }
    Write-FilePreview -Session $Session -Text $text
}

# ---- the command: `tstyles create` ------------------------------------------

function Get-CreatorConsoleRedirection {
    # Is either end of this session redirected? The creator's guards ask here
    # rather than reading [Console] themselves so a test can answer: the .NET
    # statics cannot be mocked, and on CI both are true.
    [pscustomobject]@{
        Input  = [bool][Console]::IsInputRedirected
        Output = [bool][Console]::IsOutputRedirected
    }
}

function Read-CreatorConsoleKey {
    # The next key, or $null when none is waiting. Never blocks: the loop
    # draws the page and writes the debounced preview only when it is idle,
    # so a pasted path is one redraw, not one per character.
    if (-not [Console]::KeyAvailable) { return $null }
    [Console]::ReadKey($true)
}

function Remove-StaleCreatorScratch {
    <#
    .SYNOPSIS
    Remove the scratch sessions creators that are no longer running left.

    .DESCRIPTION
    Each creator writes its preview style to $Root\session-<PID> and removes
    that folder on every way out its finally block sees. A closed tab is not
    one of them -- pwsh is killed without running finally -- so the folder
    stays. A session-<n> whose process is gone goes here; this process's own,
    one whose process is still running (a creator open in another tab), and
    anything not named session-<n> are left alone. Containment is proved
    before each recursive delete (Test-PathIsUnderRoot).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    if (-not [System.IO.Directory]::Exists($Root)) { return }
    foreach ($d in [System.IO.Directory]::GetDirectories($Root)) {
        $leaf = [System.IO.Path]::GetFileName($d)
        if ($leaf -notmatch '^session-(\d{1,9})$') { continue }
        $n = [int]$Matches[1]
        if ($n -eq $PID) { continue }
        if (Get-Process -Id $n -ErrorAction SilentlyContinue) { continue }
        if (-not (Test-PathIsUnderRoot -Path $d -Root $Root)) { continue }
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TerminalStyleCreate {
    <#
    .SYNOPSIS
    `tstyles create`: build a new style step by step, previewed live in the
    Windows Terminal window it runs in.

    .DESCRIPTION
    The pages and keys are Invoke-CreatorKey's and Get-CreatorPageLines'
    (lib/creatorengine.ps1); this is the loop around them, built the way the
    tuner's is (Invoke-TerminalStyleTune): every guard before the screen is
    touched, a closed session's preview recovered before settings.json is
    read, the rolling .bak taken, colours over OSC at once and the rest
    through a debounced write of the recorded preview session, and the update
    notice held until the screen is given back.

    Esc puts settings.json back through the session and resets the colours.
    Enter on the last page saves through Save-CreatedStyle FIRST, with the
    preview still live: a name that is taken, invalid or fails to save keeps
    the user on that page, and Esc there still has everything to put back.
    Only a saved style ends the session -- the bytes the creator found go
    back, so the placeholder scheme never stays in settings.json -- and is
    then applied through Apply-StyleDirect, the apply `tstyles <name>` runs.
    #>
    [CmdletBinding()]
    param()

    # Held, and printed after the screen is given back -- see the tuner: its
    # Clear-Host takes the scrollback, and printing the notice burns the
    # throttle. Checked only past the guards.
    $pendingUpdate = $null

    # Windows Terminal only, for now. The image, font and cursor preview live
    # only through its settings.json; elsewhere a creator would show colours
    # and nothing else of a style that is mostly its image. Refused before
    # anything is read or written.
    $kind = Get-TerminalKind
    if ($kind -ne 'WindowsTerminal') {
        # Every line true for every kind: a terminal Get-TerminalDisplayName
        # does not know is not named (its fallback, "this terminal", would
        # say nothing), and the tuner's live colours are offered only where
        # Get-TerminalCapability promises an OSC palette.
        $display = Get-TerminalDisplayName -Kind $kind
        Write-Host ""
        Write-Host "  tstyles create needs Windows Terminal for now." -ForegroundColor Yellow
        Write-Host "  It previews the image, font and cursor through Windows Terminal's settings.json."
        if ($display -ne 'this terminal') { Write-Host ("  This terminal is {0}." -f $display) }
        Write-Host "  Nothing was changed."
        Write-Host ""
        if ((Get-TerminalCapability -Kind $kind).OscPalette) {
            Write-Host "  Here, tstyles tune <name> adjusts an existing style, with its colours live." -ForegroundColor DarkGray
        }
        Write-Host "  tstyles list shows the styles there are; tstyles <name> applies one." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Both console guards, before the recovery, the backup and the first
    # Clear-Host, for the reasons the tuner's carry: KeyAvailable throws on
    # redirected input, and with output redirected the page and every OSC
    # repaint go into the file while keystrokes are acted on blind.
    $redirect = Get-CreatorConsoleRedirection
    if ($redirect.Input) {
        Write-Host ""
        Write-Host "  tstyles create needs an interactive terminal." -ForegroundColor Yellow
        Write-Host "  This session's input is redirected, so there are no keystrokes to read. Nothing was changed."
        Write-Host ""
        return
    }
    if ($redirect.Output) {
        Write-Host ""
        Write-Host "  tstyles create needs a terminal to repaint." -ForegroundColor Yellow
        Write-Host "  This session's output is redirected, so there is nothing to preview against. Nothing was changed."
        Write-Host ""
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) { return }  # Find-WTSettingsPath has already said why.
    # Said now, and again at the exit the screen clear would erase.
    $recovered = Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $settingsPath
    Show-FilePreviewResult -Result $recovered

    $pendingUpdate = Test-UpdateAvailable

    try {
        $session = New-FilePreviewSession -Kind WindowsTerminal -Path $settingsPath -By creator
    } catch {
        Write-Error $_.Exception.Message
        return
    }
    $originalSettings = ConvertFrom-JsoncText $session.OriginalText
    $target = Get-CurrentWTProfileName -Settings $originalSettings
    if (-not $target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to preview against."
        return
    }
    $session.TargetName = $target

    # Crash-recovery copy before the first preview write. A failure is said
    # inside the frame: anything printed here is wiped by the first redraw.
    $backupNote = $null
    $resolved = Resolve-WTProfileTarget -Settings $originalSettings -TargetName $target
    try { Save-SettingsBackup -Path $settingsPath -ResolvedTarget $resolved -Quiet }
    catch { $backupNote = Get-BackupFailureNote -Reason "$_" -InFrame }

    # Per process, like the tuner's .tune-preview: two creators in two tabs
    # never share (or delete) one folder. Sessions a closed tab left go first.
    $scratchRoot = Join-Path $script:TStylesDataRoot '.create-preview'
    Remove-StaleCreatorScratch -Root $scratchRoot
    $scratchSession = Join-Path $scratchRoot ("session-{0}" -f $PID)
    $scratchDir = Join-Path $scratchSession 'style'

    $state = New-CreatorStartState
    $message = $null       # what the last key has to say, for the next frame
    $previewNote = $null   # a preview write that did not land
    $pendingPreview = $false
    $needsRedraw = $true
    $applied = $false
    $e = [char]27

    # Restore-TuneBaseLook is the tuner's put-back, and runs at most once per
    # session: settings.json through the session, then Get-RevertOscPacket's
    # packet (on Windows Terminal, the reset, so it repaints from the file).
    $createState = @{ Reverted = $false; SettingsRestoreError = $null; SettingsRestoreUnchecked = $false; SettingsRestore = $null }
    $restoreLook = { Restore-TuneBaseLook -State $createState -UseSettingsFile -Session $session }
    $restoreFailedHere = {
        $createState.SettingsRestoreError -and -not ($createState.SettingsRestore -and $createState.SettingsRestore.Arm -eq 'merge')
    }
    $showRestore = {
        $sr = $createState.SettingsRestore
        if ($sr -and ($sr.Status -ne 'failed' -or $sr.Arm -eq 'merge')) { Show-FilePreviewResult -Result $sr }
        Show-FilePreviewResult -Result $recovered
    }
    $showPendingUpdate = {
        if ($pendingUpdate) {
            Write-Host ("  Update available ({0} -> {1}). Run: tstyles update" -f
                        $pendingUpdate.Installed, $pendingUpdate.Remote) -ForegroundColor Yellow
            Write-Host ""
        }
    }
    $draw = {
        # No blank line first: the page is held to 28 lines
        # (Get-CreatorPageLines), so with a note or two it still fits a
        # 30-row window without scrolling its title away.
        Clear-Host
        foreach ($note in @($backupNote, $previewNote, $message)) {
            if ($note) { Write-Host ("  $e[33m! " + ([string]$note).Trim().TrimStart('!').Trim() + "$e[0m") }
        }
        # Assigned first, never @(): Get-CreatorPageLines emits its lines as
        # ONE array (a unary comma), and @() of a single array is a one-element
        # array holding it. Write-Host then got the whole page as one object --
        # joined with spaces onto one line on pwsh 7, and printed as
        # "System.String[]" on 5.1, whose remaining-arguments binding wraps it.
        $pageLines = Get-CreatorPageLines -State $state
        foreach ($line in $pageLines) { Write-Host $line }
    }

    $originalTitle = $null
    try { $originalTitle = $Host.UI.RawUI.WindowTitle } catch { }
    try { [Console]::CursorVisible = $false } catch { }
    try {
        while ($true) {
            $key = Read-CreatorConsoleKey
            if ($null -eq $key) {
                # Idle: draw first, so the page answers the key at once, then
                # the debounced write, which reloads Windows Terminal.
                $idleWork = $needsRedraw -or $pendingPreview
                if ($needsRedraw) { & $draw; $needsRedraw = $false }
                if ($pendingPreview) {
                    $pendingPreview = $false
                    $status = Write-CreatorPreview -State $state -Session $session -ScratchDir $scratchDir `
                        -Target $target -OriginalJson $session.OriginalText
                    $note = $null
                    if ($status -eq 'changed') {
                        $note = 'settings.json was changed by something else while tstyles create was open, so the image, font and cursor no longer preview here; the colours still do.'
                    } elseif ($status -eq 'failed') {
                        $note = 'The last change could not be written to settings.json, so the image, font and cursor may not show it; the colours do.'
                    }
                    if ($note -cne $previewNote) { $previewNote = $note; $needsRedraw = $true }
                }
                if (-not $idleWork) { Start-Sleep -Milliseconds 50 }
                continue
            }

            # A large image can hold the reader for seconds: say so first,
            # below the page, so it never looks frozen.
            $reading = Get-CreatorImageToRead -State $state -Key $key
            if ($reading) {
                Write-Host ("  Reading {0}..." -f [System.IO.Path]::GetFileName($reading)) -ForegroundColor DarkGray
            }
            # Always the returned state: a newly read image is a new hashtable.
            $r = Invoke-CreatorKey -State $state -Key $key
            $state = $r.State
            $action = [string]$r.Action
            $needsRedraw = $true
            $message = $null
            if ($action -like 'error:*') { $message = $action.Substring(6); continue }

            if ($action -eq 'preview') {
                [void](Write-HostOscPacket -Packet (Get-SchemeOscPacket -Scheme $state.Scheme))
                $pendingPreview = $true
                continue
            }

            if ($action -eq 'cancel') {
                $revert = & $restoreLook
                Clear-Host
                $sr = $createState.SettingsRestore
                if ($revert -eq 'failed' -and (& $restoreFailedHere)) {
                    Show-SettingsRestoreFailure -Reason $createState.SettingsRestoreError -SettingsPath $settingsPath `
                        -By creator -BackupTaken:(-not $backupNote) -Unchecked:([bool]$createState.SettingsRestoreUnchecked)
                } elseif ($revert -ne 'failed' -and (-not $sr -or $sr.Status -eq 'restored')) {
                    Write-Host "Cancelled. Your terminal is back as it was." -ForegroundColor Yellow
                } else {
                    # The file changed while the creator was open, or another
                    # command took the session over: Show-FilePreviewResult
                    # says what was and was not put back.
                    Write-Host "Cancelled." -ForegroundColor Yellow
                }
                & $showRestore
                & $showPendingUpdate
                return
            }

            if ($action -eq 'save') {
                $name = [string]$state.Name
                # Saved with the preview still live, so a refusal leaves Esc
                # everything it needs.
                $res = $null
                try {
                    $prompt = New-CreatorPromptText -State $state -Name $name
                    $theme = New-CreatedThemeObject -Name $name -FontFace $state.FontFace -FontSize $state.FontSize `
                        -CursorShape $state.CursorShape -ImageOpacity $state.ImageOpacity `
                        -StretchMode $state.StretchMode -Alignment $state.Alignment `
                        -TabColor (Get-CreatorTabColor -Scheme $state.Scheme)
                    $res = Save-CreatedStyle -Name $name -Scheme $state.Scheme -Theme $theme `
                        -BackgroundPath $state.ImagePath -Prompt $prompt
                } catch {
                    $res = [pscustomobject]@{ Status = 'failed'; Path = $null; Reason = $_.Exception.Message }
                }
                if (-not $res) { $res = [pscustomobject]@{ Status = 'failed'; Path = $null; Reason = 'the save returned no result.' } }
                if ($res.Status -ne 'saved') {
                    $message = "Not saved: " + [string]$res.Reason
                    continue
                }

                # Saved. The preview comes out through the session -- the
                # bytes the creator found go back, or, in a file that changed,
                # the preview is taken out of it -- and the style is applied
                # from there, as the tuner does.
                $saveRestore = Restore-FilePreview -Session $session -End
                Clear-Host
                $applyErr = $null
                $applyThrew = $null
                try {
                    Apply-StyleDirect -StyleName $name -Target $target -ErrorVariable applyErr
                } catch { $applyThrew = $_ }
                # Only Apply-StyleDirect's own give-ups count (Write-Error +
                # return, before anything is written); see the tuner.
                $applied = (-not $applyThrew) -and
                    (-not @($applyErr | Where-Object { $_.CategoryInfo.Activity -eq 'Write-Error' }).Count)
                if ($applied) {
                    Remove-FilePreviewRecord -Kind WindowsTerminal -Path $settingsPath -SessionId $session.Id
                    Write-Host ("Created '{0}' and applied it." -f $name) -ForegroundColor Green
                } else {
                    if ($applyThrew) { Write-Host ("  " + $applyThrew.Exception.Message) -ForegroundColor Red }
                    Write-Host ("Created '{0}', but it could not be applied. It is saved in {1}; to apply it: tstyles {0}" -f
                                $name, $res.Path) -ForegroundColor Yellow
                }
                Show-FilePreviewResult -Result $saveRestore
                Show-FilePreviewResult -Result $recovered
                & $showPendingUpdate
                return
            }
            # none | next | back: the page changed, and is redrawn when idle.
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        if (-not $applied) {
            # The safety net for anything that left the loop another way. After
            # an Esc this answers 'already' and writes nothing.
            if (Test-ShouldRestoreWindowTitle -Title $originalTitle) {
                try { $Host.UI.RawUI.WindowTitle = $originalTitle } catch { }
            }
            $finalRevert = $null
            try { $finalRevert = & $restoreLook } catch { }
            if ($finalRevert -eq 'failed' -and (& $restoreFailedHere)) {
                Show-SettingsRestoreFailure -Reason $createState.SettingsRestoreError -SettingsPath $settingsPath `
                    -By creator -BackupTaken:(-not $backupNote) -Unchecked:([bool]$createState.SettingsRestoreUnchecked)
            }
        }
        if (Test-Path -LiteralPath $scratchSession) {
            if (Test-PathIsUnderRoot -Path $scratchSession -Root $scratchRoot) {
                Remove-Item -LiteralPath $scratchSession -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
