# The pages and keys of `tstyles create`: a pure engine over the creator state
# (lib/creator.ps1).
#
# Invoke-CreatorKey takes the state and one key, and returns the state and what
# the key loop should do next. Get-CreatorPageLines returns the page as
# strings: the controls, then a fixed sample session. Neither writes to the
# console or to a file, and neither reads the console: the loop in
# Invoke-TerminalStyleCreate does all of that. The image reader is injected,
# so every page runs and is tested on every platform.
#
# A separate file from lib/creator.ps1 only for size: the state and the
# preview live there, the page logic here.
#
# ENCODING: ASCII-only literals. Windows PowerShell 5.1 reads a BOM-less .ps1
# in the system codepage, so every non-ASCII glyph is built from its code point.

$script:CreatorStepTitles = @('Background', 'Colours', 'Font and cursor', 'Prompt', 'Name and save')

# Windows Terminal's values for backgroundImageStretchMode and
# backgroundImageAlignment, in the order Left/Right cycles them.
$script:CreatorStretchModes = @('none', 'fill', 'uniform', 'uniformToFill')
$script:CreatorAlignments = @('center', 'left', 'top', 'right', 'bottom', 'topLeft', 'topRight', 'bottomLeft', 'bottomRight')
$script:CreatorCursorShapes = @('bar', 'vintage', 'underscore', 'filledBox', 'emptyBox', 'doubleUnderscore')
# Monospace faces that come with Windows or with Windows Terminal itself, so a
# preview never names a font the machine lacks.
$script:CreatorFontFaces = @('Cascadia Code', 'Cascadia Mono', 'Consolas', 'Lucida Console', 'Courier New')
$script:CreatorFontSizeMin = 6
$script:CreatorFontSizeMax = 36

function ConvertFrom-PastedPath {
    <#
    .SYNOPSIS
    A typed or pasted path, without surrounding whitespace and one pair of quotes.

    .DESCRIPTION
    Windows Explorer's "Copy as path" wraps the path in double quotes, and some
    shells quote a dragged-in path with single quotes. One matching pair is
    removed, then the inside is trimmed; an unmatched quote is left alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory, Position = 0)][AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text.Trim()
    if ($t.Length -ge 2) {
        $first = $t[0]; $last = $t[$t.Length - 1]
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $t = $t.Substring(1, $t.Length - 2).Trim()
        }
    }
    $t
}

function New-CreatorStartState {
    <#
    .SYNOPSIS
    The creator before an image: step 0, an empty path field, no scheme.

    .DESCRIPTION
    Step 0 exists before New-CreatorState can be called, because the palette
    comes from the image. This holds only what that page needs. The first
    Enter on a readable image replaces it with New-CreatorState's full state
    (Invoke-CreatorKey), still on step 0 so the image settings appear; the
    next Enter moves to step 1.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    @{
        Step      = 0
        PathText  = ''
        Control   = 0
        HexEntry  = $null
        ImagePath = $null
        Scheme    = $null
    }
}

function Get-CreatorColorSlots {
    # The scheme's colour slots, in the order the colours page lists them:
    # every key of scheme.json except its name.
    [OutputType([string[]])]
    param()
    [string[]]@(
        'background', 'foreground', 'cursorColor', 'selectionBackground',
        'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
        'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
    )
}

function Initialize-CreatorEngineState {
    # The engine's own keys, added when a state from New-CreatorState lacks
    # them: the selected control, the path field's text, the hex entry.
    param([Parameter(Mandatory)][hashtable]$State)
    if (-not $State.ContainsKey('Control') -or $null -eq $State.Control) { $State.Control = 0 }
    if (-not $State.ContainsKey('PathText') -or $null -eq $State.PathText) {
        $State.PathText = ''
        if ($State.ImagePath) { $State.PathText = [string]$State.ImagePath }
    }
    if (-not $State.ContainsKey('HexEntry')) { $State.HexEntry = $null }
}

function Get-CreatorControlCount {
    param([Parameter(Mandatory)][hashtable]$State)
    switch ([int]$State.Step) {
        0 { if ($State.Scheme) { 4 } else { 1 } }
        1 { @(Get-CreatorColorSlots).Count }
        2 { 3 }
        3 { 4 }
        default { 1 }
    }
}

function Get-CreatorCycled {
    # The entry $Delta places after $Current in $List, wrapping. A current
    # value the list lacks moves to the first entry (or the last, going left).
    param([Parameter(Mandatory)][object[]]$List, $Current, [Parameter(Mandatory)][int]$Delta)
    $i = -1
    for ($n = 0; $n -lt $List.Count; $n++) { if ($List[$n] -ceq $Current) { $i = $n; break } }
    if ($i -lt 0) {
        if ($Delta -gt 0) { return $List[0] } else { return $List[$List.Count - 1] }
    }
    $List[((($i + $Delta) % $List.Count) + $List.Count) % $List.Count]
}

function Get-CreatorPromptColors {
    # The colours a prompt part can take: the foreground and the 16 terminal
    # colours, each once, as #rrggbb.
    param([Parameter(Mandatory)]$Scheme)
    $seen = New-Object System.Collections.Generic.List[string]
    foreach ($k in @(Get-CreatorColorSlots)) {
        if ($k -in 'background', 'cursorColor', 'selectionBackground') { continue }
        $hex = ConvertTo-NormalHex $Scheme.$k
        if ($hex -and -not $seen.Contains($hex)) { $seen.Add($hex) }
    }
    , $seen.ToArray()
}

function ConvertTo-CreatorKeyInput {
    # One key, as a [ConsoleKeyInfo] from the console or a key name from a
    # test ('Enter', 'Escape', 'Backspace', 'UpArrow', 'Shift+LeftArrow', or a
    # single character), or typed text. -> @{ Name; Shift; Chars }, where Name
    # is Up | Down | Left | Right | Enter | Back | Esc | PageUp | Chars | Other.
    param($Key, [AllowEmptyString()][AllowNull()][string]$Text)
    $out = @{ Name = 'Other'; Shift = $false; Chars = '' }
    if ($null -eq $Key -and $Text) {
        $out.Name = 'Chars'
        $out.Chars = -join @($Text.ToCharArray() | Where-Object { [int]$_ -ge 0x20 -and [int]$_ -ne 0x7F })
        if (-not $out.Chars) { $out.Name = 'Other' }
        return $out
    }
    $name = $null; $char = $null
    if ($Key -is [System.ConsoleKeyInfo]) {
        $out.Shift = [bool]($Key.Modifiers -band [ConsoleModifiers]::Shift)
        $name = [string]$Key.Key
        $char = $Key.KeyChar
    } elseif ($null -ne $Key) {
        $s = [string]$Key
        if ($s.Length -eq 1) {
            $char = $s[0]
        } else {
            if ($s -like 'Shift+*') { $out.Shift = $true; $s = $s.Substring(6) }
            $name = $s
        }
    }
    switch ($name) {
        { $_ -in 'UpArrow', 'Up' } { $out.Name = 'Up'; return $out }
        { $_ -in 'DownArrow', 'Down' } { $out.Name = 'Down'; return $out }
        { $_ -in 'LeftArrow', 'Left' } { $out.Name = 'Left'; return $out }
        { $_ -in 'RightArrow', 'Right' } { $out.Name = 'Right'; return $out }
        'Enter' { $out.Name = 'Enter'; return $out }
        { $_ -in 'Backspace', 'Back' } { $out.Name = 'Back'; return $out }
        { $_ -in 'Escape', 'Esc' } { $out.Name = 'Esc'; return $out }
        { $_ -in 'PageUp', 'PgUp', 'Prior' } { $out.Name = 'PageUp'; return $out }
    }
    if ($null -ne $char -and [int]$char -ge 0x20 -and [int]$char -ne 0x7F) {
        $out.Name = 'Chars'
        $out.Chars = [string]$char
    }
    $out
}

function Invoke-CreatorKey {
    <#
    .SYNOPSIS
    Apply one key to the creator state. -> @{ State; Action }.

    .DESCRIPTION
    Action is one of:
      none     nothing for the preview to show (the page may still have changed,
               for example a typed character; redraw it)
      preview  the look changed; write a preview
      next     moved to the next step
      back     moved to the previous step
      cancel   Esc: put everything back
      save     Enter on step 4 with a free, valid name
      error:<message>  nothing changed but what is said; show the message

    Keys: Up/Down choose a control, Left/Right change it, Enter goes to the
    next step, PageUp to the previous one on every page, Esc cancels.
    Typed characters go to the path field on step 0, the name on step 4 and
    the hex entry on step 1. Backspace NEVER navigates from a text field: there
    it only deletes, and on an empty field does nothing. On steps 1-3, outside
    hex entry, Backspace goes back too. Going back to step 0 focuses the
    opacity control, not the path field, so a held Backspace stops there
    instead of eating the path. On step 1, Shift+Left/Right moves the hue, H
    opens hex entry (Enter applies it, Esc leaves it, not the creator) and P
    pulls the palette from the image again, keeping the colours set by hand.

    Step 0 starts from New-CreatorStartState, which has no scheme. Enter reads
    the typed path: it is unquoted (ConvertFrom-PastedPath) and made absolute
    against the current location, then handed to -ReadImage. A readable image
    returns a NEW state from New-CreatorState, still on step 0. A different
    path typed later is read the same way; the new state keeps the settings
    chosen so far and the colours set by hand, and takes its other colours,
    and the prompt's, from the new image. Enter on the path already read moves
    on.

    -Key is a [ConsoleKeyInfo] or a key name; -Text is typed characters, for
    tests. -ReadImage is the reader (default Read-ImagePixels).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        $Key,
        [AllowEmptyString()][string]$Text,
        [scriptblock]$ReadImage = { param($p) @(Read-ImagePixels -Path $p) }
    )
    Initialize-CreatorEngineState -State $State
    $in = ConvertTo-CreatorKeyInput -Key $Key -Text $Text
    $result = { param($s, $a) @{ State = $s; Action = $a } }

    if ($null -ne $State.HexEntry) { return (Invoke-CreatorHexKey -State $State -In $in) }
    if ($in.Name -eq 'Esc') { return (& $result $State 'cancel') }

    $count = Get-CreatorControlCount -State $State
    if ($in.Name -eq 'Up') {
        if ($State.Control -gt 0) { $State.Control-- }
        return (& $result $State 'none')
    }
    if ($in.Name -eq 'Down') {
        if ($State.Control -lt $count - 1) { $State.Control++ }
        return (& $result $State 'none')
    }

    if ($in.Name -eq 'PageUp') {
        if ([int]$State.Step -eq 0) { return (& $result $State 'none') }
        return (Step-CreatorBack -State $State)
    }
    switch ([int]$State.Step) {
        0 { return (Invoke-CreatorImageKey -State $State -In $in -ReadImage $ReadImage) }
        4 { return (Invoke-CreatorNameKey -State $State -In $in) }
    }

    if ($in.Name -eq 'Enter') {
        $State.Step++; $State.Control = 0
        return (& $result $State 'next')
    }
    if ($in.Name -eq 'Back' -or $in.Name -eq 'PageUp') { return (Step-CreatorBack -State $State) }
    $delta = 0
    if ($in.Name -eq 'Right') { $delta = 1 }
    if ($in.Name -eq 'Left') { $delta = -1 }

    switch ([int]$State.Step) {
        1 { return (Invoke-CreatorColorKey -State $State -In $in -Delta $delta) }
        2 {
            if ($delta -eq 0) { return (& $result $State 'none') }
            switch ([int]$State.Control) {
                0 { $State.FontFace = Get-CreatorCycled -List $script:CreatorFontFaces -Current $State.FontFace -Delta $delta }
                1 {
                    $size = [Math]::Max($script:CreatorFontSizeMin, [Math]::Min($script:CreatorFontSizeMax, [int]$State.FontSize + $delta))
                    if ($size -eq [int]$State.FontSize) { return (& $result $State 'none') }
                    $State.FontSize = $size
                }
                2 { $State.CursorShape = Get-CreatorCycled -List $script:CreatorCursorShapes -Current $State.CursorShape -Delta $delta }
            }
            return (& $result $State 'preview')
        }
        3 {
            # The prompt shows only in the sample session, so nothing here
            # changes the terminal: the loop just redraws the page.
            if ($delta -eq 0) { return (& $result $State 'none') }
            switch ([int]$State.Control) {
                0 { $State.PromptShape = Get-CreatorCycled -List @(Get-StylePromptShapes) -Current $State.PromptShape -Delta $delta }
                1 { $State.Symbol = Get-CreatorCycled -List @(Get-StylePromptSymbols) -Current $State.Symbol -Delta $delta }
                2 { $State.PromptPathColor = Get-CreatorCycled -List (Get-CreatorPromptColors -Scheme $State.Scheme) -Current (ConvertTo-NormalHex $State.PromptPathColor) -Delta $delta }
                3 { $State.PromptSymbolColor = Get-CreatorCycled -List (Get-CreatorPromptColors -Scheme $State.Scheme) -Current (ConvertTo-NormalHex $State.PromptSymbolColor) -Delta $delta }
            }
            return (& $result $State 'none')
        }
    }
    & $result $State 'none'
}

function Step-CreatorBack {
    # One step back, landing on a control that is not a text field: step 0's
    # opacity (it has a scheme by then), the first control elsewhere.
    param([Parameter(Mandatory)][hashtable]$State)
    $State.Step = [int]$State.Step - 1
    $State.Control = 0
    if ($State.Step -eq 0 -and $State.Scheme) { $State.Control = 1 }
    @{ State = $State; Action = 'back' }
}

function Invoke-CreatorImageKey {
    # Step 0: the path field (control 0), then opacity, fit and position.
    param([hashtable]$State, [hashtable]$In, [scriptblock]$ReadImage)
    $result = { param($s, $a) @{ State = $s; Action = $a } }
    switch ($In.Name) {
        'Chars' {
            $State.Control = 0
            $State.PathText = [string]$State.PathText + $In.Chars
            return (& $result $State 'none')
        }
        'Back' {
            # Deletes in the path field; never goes back -- there is no step
            # before this one.
            if ($State.Control -eq 0 -and $State.PathText.Length -gt 0) {
                $State.PathText = $State.PathText.Substring(0, $State.PathText.Length - 1)
            }
            return (& $result $State 'none')
        }
        'Enter' { return (Read-CreatorImage -State $State -ReadImage $ReadImage) }
    }
    $delta = 0
    if ($In.Name -eq 'Right') { $delta = 1 }
    if ($In.Name -eq 'Left') { $delta = -1 }
    if ($delta -eq 0 -or -not $State.Scheme) { return (& $result $State 'none') }
    switch ([int]$State.Control) {
        1 {
            $o = [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, [double]$State.ImageOpacity + 0.05 * $delta)), 2)
            if ($o -eq [double]$State.ImageOpacity) { return (& $result $State 'none') }
            $State.ImageOpacity = $o
        }
        2 { $State.StretchMode = Get-CreatorCycled -List $script:CreatorStretchModes -Current $State.StretchMode -Delta $delta }
        3 { $State.Alignment = Get-CreatorCycled -List $script:CreatorAlignments -Current $State.Alignment -Delta $delta }
        default { return (& $result $State 'none') }
    }
    & $result $State 'preview'
}

function Read-CreatorImage {
    # Enter on step 0. See Invoke-CreatorKey for what it does.
    param([hashtable]$State, [scriptblock]$ReadImage)
    $result = { param($s, $a) @{ State = $s; Action = $a } }
    $typed = ConvertFrom-PastedPath $State.PathText
    if (-not $typed) { return (& $result $State 'error:Type or paste the path to a PNG, JPEG or GIF image, then press Enter.') }
    try {
        $base = (Get-Location -PSProvider FileSystem).ProviderPath
        $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $typed))
    } catch {
        return (& $result $State "error:'$typed' is not a path this computer can use.")
    }
    # Refused here, before the reader, by the rule Save-CreatedStyle applies:
    # an image the save would refuse must not get the user to the last page.
    if (-not (Get-BackgroundImageSaveExtension -Path $full)) {
        return (& $result $State ("error:'{0}' is not a file type tstyles create takes. Use a {1} file." -f
            [System.IO.Path]::GetFileName($full), (Get-BackgroundImageTypesText)))
    }
    if ($State.Scheme -and ([string]$State.ImagePath) -ceq $full) {
        $State.Step = 1; $State.Control = 0
        return (& $result $State 'next')
    }
    try {
        $px = [int[]]@(& $ReadImage $full)
        $new = New-CreatorState -Pixels $px -ImagePath $full
    } catch {
        return (& $result $State ('error:' + $_.Exception.Message))
    }
    if ($State.Scheme) {
        foreach ($k in 'ImageOpacity', 'StretchMode', 'Alignment', 'FontFace', 'FontSize', 'CursorShape', 'PromptShape', 'Symbol', 'Name') {
            $new[$k] = $State[$k]
        }
        foreach ($slot in @($State.Edited)) {
            Set-CreatorColor -State $new -Slot $slot -Hex $State.Scheme.$slot
        }
    }
    $new.PathText = $State.PathText
    $new.Control = $State.Control
    $new.HexEntry = $null
    & $result $new 'preview'
}

function Invoke-CreatorColorKey {
    # Step 1: one colour slot per control.
    param([hashtable]$State, [hashtable]$In, [int]$Delta)
    $result = { param($s, $a) @{ State = $s; Action = $a } }
    $slot = @(Get-CreatorColorSlots)[[int]$State.Control]
    if ($In.Name -eq 'Chars') {
        switch -CaseSensitive ($In.Chars) {
            { $_ -in 'h', 'H' } { $State.HexEntry = ''; return (& $result $State 'none') }
            { $_ -in 'p', 'P' } { Update-CreatorPalette -State $State; return (& $result $State 'preview') }
        }
        return (& $result $State 'none')
    }
    if ($Delta -eq 0) { return (& $result $State 'none') }
    $hex = ConvertTo-NormalHex $State.Scheme.$slot
    if (-not $hex) { return (& $result $State "error:$slot is not a colour; press H to type one.") }
    $hsl = ConvertTo-PaletteHsl $hex
    if ($In.Shift) {
        $new = ConvertFrom-PaletteHsl -H ($hsl[0] + 10.0 * $Delta) -S $hsl[1] -L $hsl[2]
    } else {
        $new = ConvertFrom-PaletteHsl -H $hsl[0] -S $hsl[1] -L ($hsl[2] + 0.03 * $Delta)
    }
    if ($new -eq $hex) { return (& $result $State 'none') }
    Set-CreatorColor -State $State -Slot $slot -Hex $new
    & $result $State 'preview'
}

function Invoke-CreatorHexKey {
    # Step 1 with hex entry open: a text field for the selected slot.
    param([hashtable]$State, [hashtable]$In)
    $result = { param($s, $a) @{ State = $s; Action = $a } }
    switch ($In.Name) {
        'Esc' { $State.HexEntry = $null; return (& $result $State 'none') }
        'Back' {
            if ($State.HexEntry.Length -gt 0) { $State.HexEntry = $State.HexEntry.Substring(0, $State.HexEntry.Length - 1) }
            return (& $result $State 'none')
        }
        'Chars' {
            $t = $State.HexEntry + $In.Chars
            if ($t.Length -gt 9) { $t = $t.Substring(0, 9) }
            $State.HexEntry = $t
            return (& $result $State 'none')
        }
        'Enter' {
            $slot = @(Get-CreatorColorSlots)[[int]$State.Control]
            $typed = [string]$State.HexEntry
            if (-not $typed.Trim()) { return (& $result $State 'error:Type a colour as #rrggbb.') }
            if (-not (ConvertTo-NormalHex $typed)) {
                return (& $result $State "error:'$typed' is not a colour. Type a colour as #rrggbb.")
            }
            try {
                Set-CreatorColor -State $State -Slot $slot -Hex $State.HexEntry
            } catch {
                return (& $result $State ('error:' + $_.Exception.Message))
            }
            $State.HexEntry = $null
            return (& $result $State 'preview')
        }
    }
    & $result $State 'none'
}

function Invoke-CreatorNameKey {
    # Step 4: the name field.
    param([hashtable]$State, [hashtable]$In)
    $result = { param($s, $a) @{ State = $s; Action = $a } }
    $name = [string]$State.Name
    switch ($In.Name) {
        'Chars' {
            $State.Name = $name + $In.Chars
            return (& $result $State 'none')
        }
        'Back' {
            # Deletes only; on an empty name it does nothing (PageUp goes back).
            if ($name.Length -gt 0) { $State.Name = $name.Substring(0, $name.Length - 1) }
            return (& $result $State 'none')
        }
        'Enter' {
            if (-not $name) { return (& $result $State 'error:Type a name for the style.') }
            if ($script:TStylesSubcommands -contains $name.ToLowerInvariant()) {
                return (& $result $State "error:'$name' is a tstyles command, so it cannot be a style name.")
            }
            if (-not (Test-StyleNameValid -Name $name)) {
                return (& $result $State ("error:'$name' is not a usable name. " + (Get-StyleNameRuleText)))
            }
            if (Test-CreatedStyleNameTaken -Name $name) {
                return (& $result $State "error:'$name' is taken: a style with that name already exists. Choose another.")
            }
            return (& $result $State 'save')
        }
    }
    & $result $State 'none'
}

# ---- the page ----------------------------------------------------------------

function Get-CreatorFg {
    # A 24-bit foreground escape for a #rrggbb, or '' when it is not a colour.
    param($Hex)
    $h = ConvertTo-NormalHex $Hex
    if (-not $h) { return '' }
    "$([char]27)[38;2;{0};{1};{2}m" -f [Convert]::ToInt32($h.Substring(1, 2), 16), [Convert]::ToInt32($h.Substring(3, 2), 16), [Convert]::ToInt32($h.Substring(5, 2), 16)
}

function Get-CreatorSampleLines {
    # The fixed sample session: made up, never the user's folder or branch.
    param([Parameter(Mandatory)][hashtable]$State)
    $e = [char]27
    $x = "$e[0m"
    $pathC = ''; $symC = ''; $curC = ''
    if ($State.Scheme) {
        $pathC = Get-CreatorFg $State.PromptPathColor
        $symC = Get-CreatorFg $State.PromptSymbolColor
        $curC = Get-CreatorFg $State.Scheme.cursorColor
    }
    $pathEnd = ''; if ($pathC) { $pathEnd = $x }
    $symEnd = ''; if ($symC) { $symEnd = $x }
    $shape = [string]$State.PromptShape
    if (-not $shape) { $shape = 'minimal' }
    $symbol = [string]$State.Symbol
    if (-not $symbol) { $symbol = '$' }

    $where = 'projects'
    if ($shape -eq 'path' -or $shape -eq 'twoline') { $where = '~/code/projects' }
    $head = $pathC + $where + $pathEnd
    if ($shape -eq 'git') { $head += ' (main)' }
    $sym = $symC + $symbol + $symEnd
    # Each prompt is a list of lines; the command goes after the last one.
    $prompt = {
        param([string]$Command)
        if ($shape -eq 'twoline') { $head; ($sym + ' ' + $Command) }
        else { ($head + ' ' + $sym + ' ' + $Command) }
    }
    $cursor = switch ([string]$State.CursorShape) {
        'vintage' { [string][char]0x2584 }
        'underscore' { '_' }
        'doubleUnderscore' { '=' }
        'filledBox' { [string][char]0x2588 }
        'emptyBox' { [string][char]0x25AF }
        default { [string][char]0x2502 }
    }
    $curEnd = ''; if ($curC) { $curEnd = $x }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in @(& $prompt 'git status')) { $lines.Add($l) }
    $lines.Add('On branch main')
    $lines.Add('Changes not staged for commit:')
    $lines.Add("    $e[31mmodified: readme.md$x")
    $lines.Add("    $e[31mdeleted:  old.txt$x")
    $lines.Add('')
    foreach ($l in @(& $prompt 'ls')) { $lines.Add($l) }
    $lines.Add("$e[34msrc$x  $e[34mdocs$x  build.ps1")
    foreach ($l in @(& $prompt ($curC + $cursor + $curEnd))) { $lines.Add($l) }
    # Unrolled on purpose: the caller enumerates it.
    $lines.ToArray()
}

function Get-CreatorPageLines {
    <#
    .SYNOPSIS
    The page for the state's step, as lines: the controls, any warnings, then
    the fixed sample session.

    .DESCRIPTION
    Pure: reads only the state, so the sample never shows the user's folder or
    branch. Colours are escape sequences; the sample's command output uses the
    terminal's own palette (the scheme being previewed), the prompt the
    prompt's chosen colours.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][hashtable]$State)
    $e = [char]27
    $x = "$e[0m"
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $step = [int]$State.Step
    $control = 0; if ($State.ContainsKey('Control') -and $null -ne $State.Control) { $control = [int]$State.Control }
    $hexEntry = $null; if ($State.ContainsKey('HexEntry')) { $hexEntry = $State.HexEntry }
    $pathText = [string]$State.PathText
    if (-not $State.ContainsKey('PathText') -and $State.ImagePath) { $pathText = [string]$State.ImagePath }
    $caret = "$e[7m $x"
    # A text field longer than its room shows its end, after '...': the page
    # stays one line per row in a 120-column window (the row's label takes 19).
    $field = {
        param([string]$Text, [int]$Room = 96)
        if ($Text.Length -le $Room) { return $Text }
        '...' + $Text.Substring($Text.Length - ($Room - 3))
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('  tstyles create   Step {0} of 5: {1}' -f ($step + 1), $script:CreatorStepTitles[$step]))
    $lines.Add('')
    $row = {
        param([int]$Index, [string]$Label, [string]$Value)
        $mark = ' '; if ($Index -eq $control) { $mark = '>' }
        ('  {0} {1,-14} {2}' -f $mark, $Label, $Value)
    }
    $swatch = {
        param($Value)
        $h = ConvertTo-NormalHex $Value
        if (-not $h) { return ([string]$Value) }
        $bg = "$e[48;2;{0};{1};{2}m" -f [Convert]::ToInt32($h.Substring(1, 2), 16), [Convert]::ToInt32($h.Substring(3, 2), 16), [Convert]::ToInt32($h.Substring(5, 2), 16)
        ('{0} {1}    {2}' -f $h, $bg, $x)
    }
    $hint = ''
    $showWarnings = $false
    switch ($step) {
        0 {
            $pathValue = & $field $pathText
            if ($control -eq 0) { $pathValue += $caret }
            $lines.Add((& $row 0 'Image' $pathValue))
            if ($State.Scheme) {
                $lines.Add((& $row 1 'Opacity' ([double]$State.ImageOpacity).ToString('0.00', $inv)))
                $lines.Add((& $row 2 'Fit' ([string]$State.StretchMode)))
                $lines.Add((& $row 3 'Position' ([string]$State.Alignment)))
                $hint = 'Up/Down choose, Left/Right change, Enter next, Esc cancel. Type another path and Enter to read it.'
            } else {
                $hint = 'Type or paste the path to a PNG, JPEG or GIF image, then press Enter. Esc cancels.'
            }
        }
        1 {
            $slots = @(Get-CreatorColorSlots)
            $half = [int][Math]::Ceiling($slots.Count / 2.0)
            for ($i = 0; $i -lt $half; $i++) {
                $left = & $row $i $slots[$i] (& $swatch $State.Scheme.($slots[$i]))
                $j = $i + $half
                if ($j -lt $slots.Count) {
                    $right = & $row $j $slots[$j] (& $swatch $State.Scheme.($slots[$j]))
                    $left = $left + '   ' + $right
                }
                $lines.Add($left)
            }
            if ($null -ne $hexEntry) {
                # On the hint's line, so hex entry does not make the page taller.
                $hint = ('Hex for {0}: {1}{2}  Type #rrggbb. Enter applies, Esc leaves hex entry.' -f $slots[$control], $hexEntry, $caret)
            } else {
                # One line of at most 100: PgUp and Backspace going back are on
                # the next pages' hints; P keeps the colours set by hand.
                $hint = 'Up/Down pick, Left/Right lightness, Shift+Left/Right hue, H hex, P re-pull, Enter next, Esc cancel.'
            }
            $showWarnings = $true
        }
        2 {
            $lines.Add((& $row 0 'Font' ([string]$State.FontFace)))
            $lines.Add((& $row 1 'Font size' ([string]$State.FontSize)))
            $lines.Add((& $row 2 'Cursor' ([string]$State.CursorShape)))
            $hint = 'Up/Down choose, Left/Right change, Enter next, PgUp or Backspace previous step, Esc cancel.'
        }
        3 {
            $lines.Add((& $row 0 'Shape' ([string]$State.PromptShape)))
            $lines.Add((& $row 1 'Symbol' ([string]$State.Symbol)))
            $lines.Add((& $row 2 'Path colour' (& $swatch $State.PromptPathColor)))
            $lines.Add((& $row 3 'Symbol colour' (& $swatch $State.PromptSymbolColor)))
            $hint = 'Up/Down choose, Left/Right change, Enter next, PgUp or Backspace previous step, Esc cancel.'
        }
        4 {
            $lines.Add((& $row 0 'Name' ((& $field ([string]$State.Name)) + $caret)))
            $hint = 'Type a name. Backspace deletes, Enter saves and applies it, PgUp previous step, Esc cancels.'
            $showWarnings = $true
        }
    }
    $lines.Add('')
    $lines.Add("  $hint")
    if ($showWarnings -and $State.Scheme) {
        # One line however many there are, so the page fits a 120x30 window.
        $w = Get-CreatorWarningLine -State $State
        if ($w) { $lines.Add("  $e[33m! $w$x") }
    }
    $lines.Add('')
    foreach ($l in @(Get-CreatorSampleLines -State $State)) { $lines.Add($l) }
    , $lines.ToArray()
}
