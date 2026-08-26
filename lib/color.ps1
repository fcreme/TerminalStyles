# color.ps1 -- HSL colour maths and the OSC packets built from it.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# The maths is deliberately simple and was verified exhaustively: an identity
# sweep over all 16,777,216 colours and ~970k knob combinations produced no
# malformed output. Brightness is ADDITIVE in L and saturation MULTIPLICATIVE in
# S -- they are not symmetric, and the tuner's sliders depend on that.
#
# Get-SchemeOscPacket is the other half: the same scheme rendered as escape
# sequences, which is how every terminal except Windows Terminal is themed.

function Get-SchemeSwatch {
    # Returns a one-line ANSI swatch (up to 5 colored blocks) summarising a
    # theme. Picks slots that actually distinguish themes from each other --
    # background, foreground, cursor accent, and two anchor ANSI hues -- and
    # falls back to other ANSI slots when those duplicate (e.g. sober has
    # cursorColor == foreground, eva has cursorColor == brightRed, which
    # would otherwise show the same color twice). Renders each slot as a
    # background-colored cell so even near-black colors stay visible against
    # the terminal background. Trailing reset.
    param([Parameter(Mandatory)]$Scheme)
    # Primary picks first, then fallbacks in order of theme-distinguishing
    # power. The first 5 unique hex values from this list are rendered.
    $candidates = @(
        $Scheme.background,
        $Scheme.foreground,
        $Scheme.cursorColor,
        $Scheme.brightRed,
        $Scheme.brightCyan,
        $Scheme.selectionBackground,
        $Scheme.brightPurple,
        $Scheme.brightYellow,
        $Scheme.brightGreen,
        $Scheme.brightBlue
    )
    $seen = @{}
    $picks = @()
    foreach ($hex in $candidates) {
        if ($picks.Count -ge 5) { break }
        if (-not $hex) { continue }
        $key = ([string]$hex).TrimStart('#').ToLowerInvariant()
        if ($key -notmatch '^[0-9a-f]{6}$') { continue }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $picks += $hex
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($hex in $picks) {
        $h = ([string]$hex).TrimStart('#')
        if ($h.Length -lt 6) { continue }
        $r = [Convert]::ToInt32($h.Substring(0,2), 16)
        $g = [Convert]::ToInt32($h.Substring(2,2), 16)
        $b = [Convert]::ToInt32($h.Substring(4,2), 16)
        [void]$sb.Append([char]27).Append("[48;2;${r};${g};${b}m    ").Append([char]27).Append('[49m ')
    }
    [void]$sb.Append([char]27).Append('[0m')
    return $sb.ToString()
}

function Convert-HueToRgb {
    # HSL hue helper. Internal to Convert-HexAdjust.
    param([double]$P, [double]$Q, [double]$T)
    if ($T -lt 0) { $T += 1.0 }
    if ($T -gt 1) { $T -= 1.0 }
    if ($T -lt (1.0/6.0)) { return $P + ($Q - $P) * 6.0 * $T }
    if ($T -lt (1.0/2.0)) { return $Q }
    if ($T -lt (2.0/3.0)) { return $P + ($Q - $P) * ((2.0/3.0) - $T) * 6.0 }
    return $P
}

function Convert-HexAdjust {
    # hex -> RGB -> HSL -> adjust (L additive, S multiplicative) -> RGB -> hex.
    # Brightness/Saturation in -100..+100. Preserves a leading '#'. Lowercase out.
    param(
        [Parameter(Mandatory)][string]$Hex,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $hadHash = $Hex.StartsWith('#')
    $h = $Hex.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($h.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($h.Substring(4,2),16) / 255.0

    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $d = $max - $min
    if ($d -eq 0) {
        $hh = 0.0; $s = 0.0
    } else {
        $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        if     ($max -eq $r) { $hh = (($g - $b) / $d) % 6 }
        elseif ($max -eq $g) { $hh = (($b - $r) / $d) + 2 }
        else                 { $hh = (($r - $g) / $d) + 4 }
        $hh = $hh * 60.0
        if ($hh -lt 0) { $hh += 360.0 }
    }

    $l = [Math]::Max(0.0, [Math]::Min(1.0, $l + ($Brightness / 100.0) * 0.5))
    $s = [Math]::Max(0.0, [Math]::Min(1.0, $s * (1.0 + ($Saturation / 100.0))))

    if ($s -eq 0) {
        $r2 = $l; $g2 = $l; $b2 = $l
    } else {
        $q = if ($l -lt 0.5) { $l * (1.0 + $s) } else { $l + $s - $l * $s }
        $p = 2.0 * $l - $q
        $hk = $hh / 360.0
        $r2 = Convert-HueToRgb -P $p -Q $q -T ($hk + 1.0/3.0)
        $g2 = Convert-HueToRgb -P $p -Q $q -T $hk
        $b2 = Convert-HueToRgb -P $p -Q $q -T ($hk - 1.0/3.0)
    }

    $ri = [int][Math]::Round($r2 * 255.0)
    $gi = [int][Math]::Round($g2 * 255.0)
    $bi = [int][Math]::Round($b2 * 255.0)
    $out = '{0:x2}{1:x2}{2:x2}' -f $ri, $gi, $bi
    if ($hadHash) { return "#$out" } else { return $out }
}

function Get-AdjustedScheme {
    # Returns a NEW scheme object (does not mutate $Scheme) with every hex
    # color slot adjusted by the brightness/saturation deltas in HSL space.
    # Non-color props (name, etc.) pass through. Missing slots skipped;
    # malformed hex passed through unchanged.
    param(
        [Parameter(Mandatory)]$Scheme,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $slots = @('background','foreground','cursorColor','selectionBackground',
               'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite')
    $out = [pscustomobject]@{}
    foreach ($prop in $Scheme.PSObject.Properties) {
        $name = $prop.Name
        $val  = $prop.Value
        if (($name -in $slots) -and ($val -is [string]) -and ($val -match '^#?[0-9a-fA-F]{6}$')) {
            $val = Convert-HexAdjust -Hex $val -Brightness $Brightness -Saturation $Saturation
        }
        $out | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
    return $out
}

function Get-SchemeOscPacket {
    # Returns a single string of OSC escape sequences that, when written to
    # stdout, instantly retints the terminal's fg/bg/cursor/selection + the
    # 16-color palette to $Scheme -- no settings.json write, no WT reload.
    # Extracted from the picker so the tuner reuses the exact same format.
    param([Parameter(Mandatory)]$Scheme)
    $BEL = [char]7
    $E   = [char]27
    $palette = 'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite'
    $sb = [System.Text.StringBuilder]::new()
    if ($Scheme.foreground)          { [void]$sb.Append("$E]10;$($Scheme.foreground)$BEL") }
    if ($Scheme.background)          { [void]$sb.Append("$E]11;$($Scheme.background)$BEL") }
    if ($Scheme.cursorColor)         { [void]$sb.Append("$E]12;$($Scheme.cursorColor)$BEL") }
    if ($Scheme.selectionBackground) { [void]$sb.Append("$E]17;$($Scheme.selectionBackground)$BEL") }
    for ($p = 0; $p -lt $palette.Count; $p++) {
        $color = $Scheme.($palette[$p])
        if ($color) { [void]$sb.Append("$E]4;${p};${color}$BEL") }
    }
    return $sb.ToString()
}

function Get-OscResetPacket {
    # Returns OSC sequences that RESET the terminal's dynamic colors back to the
    # profile defaults: the full palette (OSC 104, no params) plus foreground
    # (110), background (111), cursor (112), and selection (117). The picker and
    # tuner retint live via Get-SchemeOscPacket; on Esc/cancel those overrides
    # would otherwise persist over the reverted settings.json, so we emit this to
    # hand color control back to Windows Terminal's configured scheme.
    $BEL = [char]7
    $E   = [char]27
    return "$E]104$BEL" + "$E]110$BEL" + "$E]111$BEL" + "$E]112$BEL" + "$E]117$BEL"
}
