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
            $px[0] | Should -BeOfType [int]
            @($px | Where-Object { $_ -ne 0xFF0000 }).Count | Should -Be 0
            # A bare assignment must also give the flat 16 values.
            $bare = Read-ImagePixels -Path $path
            $bare.Count | Should -Be 16
            $bare[0] | Should -BeOfType [int]
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
            $px.Count | Should -Be (50 * 25)
        }
    }

    It 'reads only the first frame of a GIF' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            # Hand-written GIF89a, so the fixture does not depend on the GDI+
            # encoder (which quantises colours). Layout:
            #   header 'GIF89a'; logical screen 4x4, packed 0x81 (global colour
            #   table, 4 entries), background 0, aspect 0;
            #   global colour table: [0]=00FF00 green, [1]=0000FF blue, [2] black, [3] white;
            #   per frame: Graphic Control Extension (21 F9 04 00 0A 00 00 00),
            #   image descriptor (2C, left 0, top 0, 4x4, no local table),
            #   LZW min code size 2 (clear=4, end=5, 3-bit codes), then one data
            #   sub-block. The stream is: clear, px, px, clear, px, px ... x8,
            #   then end. Clearing every two pixels keeps the code size at 3.
            #   Frame 1 = 16 x index 0 (green), frame 2 = 16 x index 1 (blue);
            #   trailer 3B.
            [byte[]]$gif = @(
                0x47,0x49,0x46,0x38,0x39,0x61, 0x04,0x00,0x04,0x00, 0x81,0x00,0x00,
                0x00,0xFF,0x00, 0x00,0x00,0xFF, 0x00,0x00,0x00, 0xFF,0xFF,0xFF,
                0x21,0xF9,0x04,0x00,0x0A,0x00,0x00,0x00,
                0x2C,0x00,0x00,0x00,0x00,0x04,0x00,0x04,0x00,0x00,
                0x02, 0x0A, 0x04,0x08,0x10,0x20,0x40,0x80,0x00,0x01,0x02,0x05, 0x00,
                0x21,0xF9,0x04,0x00,0x0A,0x00,0x00,0x00,
                0x2C,0x00,0x00,0x00,0x00,0x04,0x00,0x04,0x00,0x00,
                0x02, 0x0A, 0x4C,0x98,0x30,0x61,0xC2,0x84,0x09,0x13,0x26,0x05, 0x00,
                0x3B)
            $path = Join-Path $Dir 'two.gif'
            [System.IO.File]::WriteAllBytes($path, $gif)
            $px = @(Read-ImagePixels -Path $path)
            $found = ($px | Group-Object | Sort-Object Name | ForEach-Object {
                    ('0x{0:X6} x{1}' -f [int]$_.Name, $_.Count) }) -join ', '
            $px.Count | Should -Be 16 -Because "values read: $found"
            $px[0] | Should -BeOfType [int]
            @($px | Where-Object { $_ -ne 0x00FF00 }).Count | Should -Be 0 -Because "values read: $found"
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

    It 'a failure after the decode (drawing, locking) is the same not-an-image message' -Skip:$script:NoReader {
        InModuleScope TerminalStyles -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            Add-Type -AssemblyName System.Drawing
            $path = Join-Path $Dir 'decodes.png'
            $bmp = [System.Drawing.Bitmap]::new(8, 8)
            try { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
            # Called while the downscale is being set up, after the decode.
            Mock Get-ImagePixelsInterpolation { throw 'A generic error occurred in GDI+.' }
            { Read-ImagePixels -Path $path } | Should -Throw "Not an image TerminalStyles can read: $path"
            Should -Invoke Get-ImagePixelsInterpolation -Times 1 -Exactly
        }
    }

    It 'says it needs Windows off Windows' -Skip:(-not $script:NoReader) {
        InModuleScope TerminalStyles {
            { Read-ImagePixels -Path 'whatever.png' } | Should -Throw '*needs Windows*'
        }
    }
}

Describe 'Get-ImagePixelsInterpolation' {
    # Pure, so it runs on every platform: which GDI+ mode the downscale uses.
    It 'uses bicubic down to a quarter, and the cheaper bilinear below it (<Scale>)' -ForEach @(
        @{ Scale = 1.0; Want = 'HighQualityBicubic' }, @{ Scale = 0.25; Want = 'HighQualityBicubic' },
        @{ Scale = 0.2499; Want = 'HighQualityBilinear' }, @{ Scale = (96 / 6000.0); Want = 'HighQualityBilinear' }) {
        InModuleScope TerminalStyles -Parameters @{ Scale = $Scale; Want = $Want } {
            param($Scale, $Want)
            Get-ImagePixelsInterpolation -Scale $Scale | Should -BeExactly $Want
        }
    }
}
