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

function Get-CreatorWarnings {
    <#
    .SYNOPSIS
    One line per colour slot that will be hard to read, or will not show at all.

    .DESCRIPTION
    Contrast against the background comes from Get-SchemeLowContrastSlots, the
    same bars the palette is pulled to (foreground 7:1); a value that is not a
    colour from Get-SchemeUnreadableSlots, the slots the OSC packet would drop.
    Warnings only: the creator keeps the edit. Empty when everything reads.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][hashtable]$State)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in @(Get-SchemeUnreadableSlots -Scheme $State.Scheme)) {
        if ($k -eq 'name') { continue }
        $lines.Add(("{0} is not a colour, so it will not show." -f $k))
    }
    foreach ($k in @(Get-SchemeLowContrastSlots -Scheme $State.Scheme)) {
        $lines.Add(("{0} is hard to read against the background." -f $k))
    }
    # Callers wrap in @(): a bare return unrolls to nothing when empty.
    $lines.ToArray()
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

    $tab = Get-PaletteAccent -Scheme $scheme
    if (-not $tab) { $tab = ConvertTo-NormalHex $scheme.foreground }
    if (-not $tab) { $tab = '#808080' }
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
