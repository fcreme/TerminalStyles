# palette.ps1 -- build a readable terminal colour scheme from image pixels.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Pure: takes the [int[]] (0xRRGGBB) that Read-ImagePixels returns and does no
# I/O, so it runs and is tested on every platform. Deterministic: fixed
# quantile seeds and a fixed iteration count, no random numbers.

function ConvertTo-PaletteHsl {
    # '#rrggbb' -> [double[]] h (0-360), s (0-1), l (0-1). Internal.
    param([Parameter(Mandatory)][string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16) / 255.0
    $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16) / 255.0
    $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16) / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $d = $max - $min
    if ($d -eq 0) { return , @(0.0, 0.0, $l) }
    $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
    if ($max -eq $r) { $h = (($g - $b) / $d) % 6 }
    elseif ($max -eq $g) { $h = (($b - $r) / $d) + 2 }
    else { $h = (($r - $g) / $d) + 4 }
    $h = $h * 60.0
    if ($h -lt 0) { $h += 360.0 }
    , @($h, $s, $l)
}

function ConvertFrom-PaletteHsl {
    # h (0-360), s, l (0-1) -> '#rrggbb'. Internal; reuses Convert-HueToRgb.
    param([double]$H, [double]$S, [double]$L)
    $S = [Math]::Max(0.0, [Math]::Min(1.0, $S))
    $L = [Math]::Max(0.0, [Math]::Min(1.0, $L))
    $H = $H % 360.0
    if ($H -lt 0) { $H += 360.0 }
    if ($S -eq 0) {
        $r = $L; $g = $L; $b = $L
    } else {
        $q = if ($L -lt 0.5) { $L * (1.0 + $S) } else { $L + $S - $L * $S }
        $p = 2.0 * $L - $q
        $hk = $H / 360.0
        $r = Convert-HueToRgb -P $p -Q $q -T ($hk + 1.0 / 3.0)
        $g = Convert-HueToRgb -P $p -Q $q -T $hk
        $b = Convert-HueToRgb -P $p -Q $q -T ($hk - 1.0 / 3.0)
    }
    '#{0:x2}{1:x2}{2:x2}' -f [int][Math]::Round($r * 255.0), [int][Math]::Round($g * 255.0), [int][Math]::Round($b * 255.0)
}

function Get-PaletteHueDistance {
    param([double]$A, [double]$B)
    $d = [Math]::Abs($A - $B) % 360.0
    if ($d -gt 180.0) { $d = 360.0 - $d }
    $d
}

function Get-PaletteClusters {
    # Deterministic k-means over a subsample. Returns objects with Hex and
    # Count, empty clusters dropped. Internal.
    param([int[]]$Pixels, [int]$K = 8, [int]$Iterations = 10, [int]$MaxSample = 2048)

    $n = $Pixels.Length
    $stride = [Math]::Max(1, [int][Math]::Ceiling($n / [double]$MaxSample))
    $m = [int][Math]::Ceiling($n / [double]$stride)
    $pr = New-Object 'double[]' $m
    $pg = New-Object 'double[]' $m
    $pb = New-Object 'double[]' $m
    $luma = New-Object 'double[]' $m
    $idx = New-Object 'int[]' $m
    $j = 0
    for ($i = 0; $i -lt $n -and $j -lt $m; $i += $stride) {
        $v = $Pixels[$i]
        $r = ($v -shr 16) -band 255; $g = ($v -shr 8) -band 255; $b = $v -band 255
        $pr[$j] = $r; $pg[$j] = $g; $pb[$j] = $b
        $luma[$j] = 0.299 * $r + 0.587 * $g + 0.114 * $b
        $idx[$j] = $j
        $j++
    }
    $m = $j
    # Seeds: evenly spaced quantiles of the luma-sorted sample.
    $sorted = [int[]]$idx[0..($m - 1)]
    $keys = [double[]]$luma[0..($m - 1)]
    [Array]::Sort($keys, $sorted)
    $cr = New-Object 'double[]' $K
    $cg = New-Object 'double[]' $K
    $cb = New-Object 'double[]' $K
    for ($c = 0; $c -lt $K; $c++) {
        $q = $sorted[[int][Math]::Floor(($c + 0.5) * $m / $K)]
        $cr[$c] = $pr[$q]; $cg[$c] = $pg[$q]; $cb[$c] = $pb[$q]
    }
    $assign = New-Object 'int[]' $m
    $cnt = New-Object 'int[]' $K
    for ($it = 0; $it -lt $Iterations; $it++) {
        $sr = New-Object 'double[]' $K
        $sg = New-Object 'double[]' $K
        $sb = New-Object 'double[]' $K
        $cnt = New-Object 'int[]' $K
        for ($i = 0; $i -lt $m; $i++) {
            $best = 0; $bd = [double]::MaxValue
            for ($c = 0; $c -lt $K; $c++) {
                $dr = $pr[$i] - $cr[$c]; $dg = $pg[$i] - $cg[$c]; $db = $pb[$i] - $cb[$c]
                $d = $dr * $dr + $dg * $dg + $db * $db
                if ($d -lt $bd) { $bd = $d; $best = $c }
            }
            $assign[$i] = $best
            $sr[$best] += $pr[$i]; $sg[$best] += $pg[$i]; $sb[$best] += $pb[$i]
            $cnt[$best]++
        }
        for ($c = 0; $c -lt $K; $c++) {
            if ($cnt[$c] -gt 0) {
                $cr[$c] = $sr[$c] / $cnt[$c]; $cg[$c] = $sg[$c] / $cnt[$c]; $cb[$c] = $sb[$c] / $cnt[$c]
            }
        }
    }
    $out = New-Object System.Collections.Generic.List[object]
    for ($c = 0; $c -lt $K; $c++) {
        if ($cnt[$c] -le 0) { continue }
        $hex = '#{0:x2}{1:x2}{2:x2}' -f [int][Math]::Round($cr[$c]), [int][Math]::Round($cg[$c]), [int][Math]::Round($cb[$c])
        $hsl = ConvertTo-PaletteHsl $hex
        $out.Add([pscustomobject]@{ Hex = $hex; Count = $cnt[$c]; H = $hsl[0]; S = $hsl[1]; L = $hsl[2]
                Luma = 0.299 * $cr[$c] + 0.587 * $cg[$c] + 0.114 * $cb[$c] })
    }
    , $out.ToArray()
}

function New-PaletteFromPixels {
    <#
    .SYNOPSIS
    A readable 21-key colour scheme from image pixels.

    .DESCRIPTION
    Clusters the pixels (k-means, k = 8, fixed seeds). The background is the
    darkest large cluster, capped dark; the foreground the lightest, raised
    until it holds 7:1 against the background. Each ANSI role takes the cluster
    nearest its hue (within 25 degrees), else the role's hue at the image's
    mean saturation, lightened until it holds 4.5:1. Brights are the same hue,
    lighter. Same pixels in, same scheme out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int[]]$Pixels,
        [Parameter(Mandatory)][string]$Name
    )

    $total = $Pixels.Length
    $clusters = if ($total -gt 0) { @(Get-PaletteClusters -Pixels $Pixels) } else { @() }
    if ($clusters.Count -eq 0) {
        $clusters = @([pscustomobject]@{ Hex = '#808080'; Count = 1; H = 0.0; S = 0.0; L = 0.5; Luma = 128.0 })
    }
    $sampleTotal = 0
    foreach ($c in $clusters) { $sampleTotal += $c.Count }
    $large = @($clusters | Where-Object { $_.Count -ge 0.05 * $sampleTotal })
    if ($large.Count -eq 0) { $large = $clusters }

    # Background: darkest large cluster, capped dark and not too colourful.
    $bgC = @($large | Sort-Object Luma, Hex)[0]
    $bg = ConvertFrom-PaletteHsl $bgC.H ([Math]::Min($bgC.S, 0.6)) ([Math]::Min($bgC.L, 0.10))

    # Foreground: lightest large cluster, raised until 7:1.
    $fgC = @($large | Sort-Object @{ Expression = 'Luma'; Descending = $true }, Hex)[0]
    $fgS = [Math]::Min($fgC.S, 0.35)
    $fgL = [Math]::Max($fgC.L, 0.6)
    $fg = ConvertFrom-PaletteHsl $fgC.H $fgS $fgL
    while ((Get-ContrastRatio $fg $bg) -lt 7.0 -and $fgL -lt 1.0) {
        $fgL = [Math]::Min(1.0, $fgL + 0.01)
        $fg = ConvertFrom-PaletteHsl $fgC.H $fgS $fgL
    }

    # Mean saturation, for roles the image has no colour for.
    $ws = 0.0
    foreach ($c in $clusters) { $ws += $c.S * $c.Count }
    $meanS = [Math]::Max(0.45, [Math]::Min(0.9, $ws / $sampleTotal))

    $roles = [ordered]@{ red = 0.0; green = 120.0; yellow = 60.0; blue = 240.0; purple = 300.0; cyan = 180.0 }
    $colourful = @($clusters | Where-Object { $_.S -ge 0.2 -and $_.L -ge 0.08 -and $_.L -le 0.97 })
    $normal = @{}
    $bright = @{}
    foreach ($role in $roles.Keys) {
        $hue = $roles[$role]
        $pick = $null; $pd = 25.0
        foreach ($c in $colourful) {
            $d = Get-PaletteHueDistance $c.H $hue
            if ($d -le $pd) { $pd = $d; $pick = $c }
        }
        if ($pick) {
            $h = $pick.H; $s = [Math]::Max(0.45, [Math]::Min(0.9, $pick.S)); $l = [Math]::Max(0.45, $pick.L)
        } else {
            $h = $hue; $s = $meanS; $l = 0.55
        }
        $hex = ConvertFrom-PaletteHsl $h $s $l
        while ((Get-ContrastRatio $hex $bg) -lt 4.5 -and $l -lt 0.9) {
            $l = [Math]::Min(0.9, $l + 0.01)
            $hex = ConvertFrom-PaletteHsl $h $s $l
        }
        $bl = [Math]::Min(0.92, $l + 0.10)
        $bhex = ConvertFrom-PaletteHsl $h $s $bl
        if ((Get-RelativeLuminance $bhex) -lt (Get-RelativeLuminance $hex)) { $bhex = $hex }
        $normal[$role] = $hex
        $bright[$role] = $bhex
    }

    # Neutrals.
    $bgHsl = ConvertTo-PaletteHsl $bg
    $fgHsl = ConvertTo-PaletteHsl $fg
    $black = ConvertFrom-PaletteHsl $bgHsl[0] $bgHsl[1] ($bgHsl[2] + 0.04)
    $bbL = $bgHsl[2] + 0.2
    $bbS = [Math]::Min($bgHsl[1], 0.3)
    $brightBlack = ConvertFrom-PaletteHsl $bgHsl[0] $bbS $bbL
    while ((Get-ContrastRatio $brightBlack $bg) -lt 3.0 -and $bbL -lt 1.0) {
        $bbL = [Math]::Min(1.0, $bbL + 0.01)
        $brightBlack = ConvertFrom-PaletteHsl $bgHsl[0] $bbS $bbL
    }
    $white = ConvertFrom-PaletteHsl $fgHsl[0] $fgHsl[1] ($fgHsl[2] - 0.1)
    if ((Get-ContrastRatio $white $bg) -lt 4.5) { $white = $fg }
    $selection = Convert-HexAdjust -Hex $bg -Brightness 30

    $o = [ordered]@{
        name                = $Name
        background          = $bg
        foreground          = $fg
        cursorColor         = $fg
        selectionBackground = $selection
        black               = $black
        red                 = $normal['red']
        green               = $normal['green']
        yellow              = $normal['yellow']
        blue                = $normal['blue']
        purple              = $normal['purple']
        cyan                = $normal['cyan']
        white               = $white
        brightBlack         = $brightBlack
        brightRed           = $bright['red']
        brightGreen         = $bright['green']
        brightYellow        = $bright['yellow']
        brightBlue          = $bright['blue']
        brightPurple        = $bright['purple']
        brightCyan          = $bright['cyan']
        brightWhite         = $fg
    }
    [pscustomobject]$o
}

function Get-PaletteAccent {
    # The most vivid colour in the scheme (highest HSL chroma among the six
    # hue slots and their brights); the first wins a tie. '#rrggbb'.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scheme)

    $best = $null; $bc = -1.0
    foreach ($k in 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan') {
        $hex = ConvertTo-NormalHex $Scheme.$k
        if (-not $hex) { continue }
        $hsl = ConvertTo-PaletteHsl $hex
        $chroma = $hsl[1] * (1.0 - [Math]::Abs(2.0 * $hsl[2] - 1.0))
        if ($chroma -gt $bc) { $bc = $chroma; $best = $hex }
    }
    $best
}

function Get-SchemeLowContrastSlots {
    <#
    .SYNOPSIS
    Which colour slots fall below their contrast bar against the background?

    .DESCRIPTION
    foreground needs 7.0; the six ANSI hues, white and their brights 4.5;
    brightBlack 3.0 (it is the dim-text colour). black is exempt. Works on any
    scheme object or dictionary with those keys; a slot that is missing or does
    not parse is skipped (Get-SchemeUnreadableSlots reports unparsable values).
    Returns names in a fixed order; empty when every slot passes.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Scheme)

    $bars = [ordered]@{ foreground = 7.0 }
    foreach ($k in 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white') { $bars[$k] = 4.5 }
    foreach ($k in 'Red', 'Green', 'Yellow', 'Blue', 'Purple', 'Cyan', 'White') { $bars["bright$k"] = 4.5 }
    $bars['brightBlack'] = 3.0

    $bg = ConvertTo-NormalHex $Scheme.background
    if (-not $bg) { return , [string[]]@() }
    $low = New-Object System.Collections.Generic.List[string]
    foreach ($k in $bars.Keys) {
        $hex = ConvertTo-NormalHex $Scheme.$k
        if (-not $hex) { continue }
        if ((Get-ContrastRatio $hex $bg) -lt $bars[$k]) { $low.Add($k) }
    }
    , $low.ToArray()
}
