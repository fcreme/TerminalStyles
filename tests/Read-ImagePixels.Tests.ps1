# Pester 5 tests: Read-ImagePixels, the Windows-only image reader behind
# `tstyles create`. Fixtures are generated with System.Drawing under $TestDrive.
# The Windows tests are gated at DISCOVERY (a -Skip reading a BeforeAll
# variable is $null and would silently pass); the off-Windows test runs
# everywhere else.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:ReaderAvailable = & (Get-Module TerminalStyles) { Test-ImagePixelReaderAvailable }
    $script:NoReader = -not $script:ReaderAvailable
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Read-ImagePixels' {
    It 'reads a solid PNG' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            Add-Type -AssemblyName System.Drawing
            $path = Join-Path $Dir 'red.png'
            $bmp = [System.Drawing.Bitmap]::new(4, 4)
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try { $g.Clear([System.Drawing.Color]::FromArgb(255, 0, 0)) } finally { $g.Dispose() }
                $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $bmp.Dispose() }
            $px = @(Read-ImagePixels -Path $path)
            $px.Count | Should -Be 16
            @($px | Where-Object { $_ -ne 0xFF0000 }).Count | Should -Be 0
        }
    }

    It 'scales the longest side down to MaxSide' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            Add-Type -AssemblyName System.Drawing
            $path = Join-Path $Dir 'wide.png'
            $bmp = [System.Drawing.Bitmap]::new(2000, 1000)
            try { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
            $px = @(Read-ImagePixels -Path $path -MaxSide 50)
            $px.Count | Should -BeGreaterThan 0
            $px.Count | Should -BeLessOrEqual (50 * 25)
        }
    }

    It 'reads only the first frame of a GIF' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            Add-Type -AssemblyName System.Drawing
            $path = Join-Path $Dir 'two.gif'
            $first = [System.Drawing.Bitmap]::new(4, 4)
            $second = [System.Drawing.Bitmap]::new(4, 4)
            try {
                $g = [System.Drawing.Graphics]::FromImage($first)
                try { $g.Clear([System.Drawing.Color]::FromArgb(0, 255, 0)) } finally { $g.Dispose() }
                $g = [System.Drawing.Graphics]::FromImage($second)
                try { $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 255)) } finally { $g.Dispose() }
                $enc = [System.Drawing.Imaging.Encoder]::SaveFlag
                $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                    Where-Object { $_.MimeType -eq 'image/gif' } | Select-Object -First 1
                $p = [System.Drawing.Imaging.EncoderParameters]::new(1)
                try {
                    $p.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($enc, [long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
                    $first.Save($path, $codec, $p)
                    $p.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($enc, [long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
                    $first.SaveAdd($second, $p)
                    $p.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($enc, [long][System.Drawing.Imaging.EncoderValue]::Flush)
                    $first.SaveAdd($p)
                } finally { $p.Dispose() }
            } finally { $first.Dispose(); $second.Dispose() }
            $px = @(Read-ImagePixels -Path $path)
            $px.Count | Should -Be 16
            @($px | Where-Object { $_ -ne 0x00FF00 }).Count | Should -Be 0
        }
    }

    It 'refuses a .png that is not an image' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            $path = Join-Path $Dir 'fake.png'
            [System.IO.File]::WriteAllText($path, 'hello')
            { Read-ImagePixels -Path $path } | Should -Throw '*Not an image TerminalStyles can read*'
        }
    }

    It 'refuses a missing file' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            { Read-ImagePixels -Path (Join-Path $Dir 'nope.png') } | Should -Throw '*Not an image TerminalStyles can read*'
        }
    }

    It 'says it needs Windows off Windows' -Skip:(-not $script:NoReader) {
        InModuleScope TerminalStyles {
            { Read-ImagePixels -Path 'whatever.png' } | Should -Throw '*needs Windows*'
        }
    }
}
