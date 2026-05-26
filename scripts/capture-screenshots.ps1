# capture-screenshots.ps1 -- capture a screenshot of each bundled theme
# applied to the current Windows Terminal tab. Outputs PNGs to
# docs/screenshots/<name>.png, one per theme.
#
# USAGE:
#   1. Open a Windows Terminal tab (this script must run INSIDE WT).
#      Resize the window to a reasonable thumbnail-friendly size,
#      e.g. ~900x600 pixels, before starting.
#   2. From this repo:
#        pwsh -File .\scripts\capture-screenshots.ps1
#   3. Do not touch the keyboard / window focus while it runs (~3-4
#      seconds per theme).
#   4. When done, the original theme is restored automatically.
#   5. Review docs/screenshots/, then commit.
#
# NOTE: requires the tstyles installation at %LOCALAPPDATA%\TerminalStyles\.
# If you've been editing themes locally without installing, run
# .\install.ps1 (or 'iwr | iex' the one-liner) first.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# --- Win32 PrintWindow with PW_RENDERFULLCONTENT (works for WT) ---
Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class WTScreenCapture {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public static void CaptureForegroundTo(string outputPath) {
        IntPtr hWnd = GetForegroundWindow();
        if (hWnd == IntPtr.Zero) throw new InvalidOperationException("No foreground window.");

        RECT r;
        GetWindowRect(hWnd, out r);
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) throw new InvalidOperationException("Foreground window has zero size.");

        using (var bmp = new Bitmap(w, h))
        {
            using (var g = Graphics.FromImage(bmp)) {
                IntPtr hdc = g.GetHdc();
                // 2 = PW_RENDERFULLCONTENT, required for DirectX-rendered
                // windows like Windows Terminal.
                PrintWindow(hWnd, hdc, 2);
                g.ReleaseHdc(hdc);
            }
            bmp.Save(outputPath, ImageFormat.Png);
        }
    }
}
"@ -ReferencedAssemblies System.Drawing

# --- Sanity checks ---
if (-not $env:WT_SESSION) {
    throw "This script must be run from inside a Windows Terminal tab. The PrintWindow capture only works on the focused WT window."
}

if (-not (Get-Command tstyles -ErrorAction SilentlyContinue)) {
    throw "The 'tstyles' command is not available in this session. Run install.ps1 first, or '. `$PROFILE'."
}

$installDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
$installStylesDir = Join-Path $installDir 'styles'
if (-not (Test-Path -LiteralPath $installStylesDir)) {
    throw "TerminalStyles install not found at $installDir. Run install.ps1 first."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot 'docs\screenshots'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# --- Enumerate themes from the INSTALL directory (matches what tstyles sees) ---
$themes = Get-ChildItem -LiteralPath $installStylesDir -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
    Sort-Object Name

if (-not $themes) {
    throw "No themes found at $installStylesDir."
}

# --- Save current theme so we can restore it at the end ---
$originalTheme = (tstyles current 2>$null) -join ''
$originalTheme = "$originalTheme".Trim()
if (-not $originalTheme -or $originalTheme -match 'no bundled style') {
    $originalTheme = $null
}

Write-Host ""
Write-Host "Capturing $($themes.Count) theme screenshots into:" -ForegroundColor Cyan
Write-Host "  $outDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Don't touch the keyboard or change window focus while this runs." -ForegroundColor Yellow
Write-Host "Starting in 3 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$captured = @()
foreach ($theme in $themes) {
    # Apply silently (Apply-StyleDirect's "Style applied: X" status line
    # would clutter the screenshot if we let it print into the same tab).
    tstyles $theme.Name *>&1 | Out-Null

    # Wipe the tab and re-render just the banner + prompt fresh, so the
    # screenshot is the cleanest possible representation of the theme.
    Clear-Host
    $stylePs1 = Join-Path $installDir 'current-style.ps1'
    if (Test-Path -LiteralPath $stylePs1) {
        . $stylePs1
    }

    # Give WT a beat to re-render colors, font, cursor, bg before snapping.
    Start-Sleep -Milliseconds 700

    $outFile = Join-Path $outDir "$($theme.Name).png"
    try {
        [WTScreenCapture]::CaptureForegroundTo($outFile)
        $size = (Get-Item -LiteralPath $outFile).Length
        $captured += [pscustomobject]@{ Name = $theme.Name; Path = $outFile; Bytes = $size }
    } catch {
        Write-Host "  ! Failed to capture $($theme.Name): $_" -ForegroundColor Red
    }
}

# --- Restore the original theme ---
if ($originalTheme) {
    tstyles $originalTheme *>&1 | Out-Null
}

Clear-Host
Write-Host ""
Write-Host "Captured $($captured.Count) screenshot(s):" -ForegroundColor Green
foreach ($c in $captured) {
    Write-Host ("  - {0,-16} {1,8:N0} bytes  ->  {2}" -f $c.Name, $c.Bytes, $c.Path)
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open docs/screenshots/ and review each PNG." -ForegroundColor Gray
Write-Host "  2. If any look wrong, re-run this script (it overwrites)." -ForegroundColor Gray
Write-Host "  3. Commit:  git add docs/screenshots/ ; git commit -m 'Refresh theme screenshots'" -ForegroundColor Gray
Write-Host ""
