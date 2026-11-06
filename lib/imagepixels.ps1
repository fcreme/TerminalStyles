# imagepixels.ps1 -- read an image's pixels for `tstyles create`.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Windows only: System.Drawing.Common is Windows-only from .NET 6 onward, and
# there is no other decoder in the module. Off Windows the reader says so
# rather than returning nothing.

function Test-ImagePixelReaderAvailable {
    # True on Windows when System.Drawing loads.
    if ((Get-TStylesPlatform) -ne 'Windows') { return $false }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Read-ImagePixels {
    [OutputType([int[]])]
    # Returns the pixels as [int] values, each 0xRRGGBB, unrolled onto the
    # pipeline (see the end of the function for the caller contract). Reads the first frame of a GIF, ignores
    # alpha (transparent pixels are drawn over black), and
    # scales the longest side down to at most -MaxSide before sampling.
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 4096)][int]$MaxSide = 96
    )
    if (-not (Test-ImagePixelReaderAvailable)) {
        throw 'Reading images needs Windows.'
    }
    $notImage = "Not an image TerminalStyles can read: $Path"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $notImage }

    $img = $null
    $small = $null
    $g = $null
    $attr = $null
    try {
        try {
            $full = (Resolve-Path -LiteralPath $Path).ProviderPath
            $img = [System.Drawing.Image]::FromFile($full)
            if ($img.FrameDimensionsList.Count -gt 0) {
                $dim = [System.Drawing.Imaging.FrameDimension]::new($img.FrameDimensionsList[0])
                if ($img.GetFrameCount($dim) -gt 1) { [void]$img.SelectActiveFrame($dim, 0) }
            }
        } catch {
            throw $notImage
        }
        $w = [int]$img.Width
        $h = [int]$img.Height
        if ($w -lt 1 -or $h -lt 1) { throw $notImage }
        $scale = [Math]::Min(1.0, $MaxSide / [double][Math]::Max($w, $h))
        $tw = [Math]::Max(1, [int][Math]::Round($w * $scale))
        $th = [Math]::Max(1, [int][Math]::Round($h * $scale))

        $small = [System.Drawing.Bitmap]::new($tw, $th, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($small)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Black)
        # TileFlipXY so edge samples blend with the mirrored image, not with
        # transparent, which would darken the border over the black Clear.
        $attr = [System.Drawing.Imaging.ImageAttributes]::new()
        $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $dest = [System.Drawing.Rectangle]::new(0, 0, $tw, $th)
        $g.DrawImage($img, $dest, 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel, $attr)

        $rect = [System.Drawing.Rectangle]::new(0, 0, $tw, $th)
        $data = $small.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $argb = [int[]]::new($tw * $th)
            if ($data.Stride -ne $tw * 4) {
                # Rows are padded: copy row by row.
                $row = [int[]]::new($tw)
                for ($y = 0; $y -lt $th; $y++) {
                    [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + [int64]$y * $data.Stride), $row, 0, $tw)
                    [Array]::Copy($row, 0, $argb, $y * $tw, $tw)
                }
            } else {
                [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $argb, 0, $argb.Length)
            }
        } finally {
            $small.UnlockBits($data)
        }
        $out = [int[]]::new($argb.Length)
        for ($i = 0; $i -lt $argb.Length; $i++) { $out[$i] = $argb[$i] -band 0xFFFFFF }
        # Emit the elements (no unary comma): the pipeline unrolls them, so the
        # caller gets a flat sequence of [int] whether or not it wraps the call
        # in @(). Callers that need an array use @(Read-ImagePixels ...); a bare
        # assignment is an [int[]] except for a 1x1 image, which arrives as one
        # [int] and still binds to an [int[]] parameter.
        $out
    } finally {
        if ($attr) { $attr.Dispose() }
        if ($g) { $g.Dispose() }
        if ($small) { $small.Dispose() }
        if ($img) { $img.Dispose() }
    }
}
