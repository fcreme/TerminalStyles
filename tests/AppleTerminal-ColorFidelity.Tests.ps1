# Pester 5 tests: the colors in a generated .terminal profile must be the colors
# in scheme.json.
#
# shell/appleterminal.js built every NSColor with
# colorWithCalibratedRedGreenBlueAlpha, which stores the value in
# NSCalibratedRGBColorSpace -- Apple generic RGB at gamma 1.8. AppKit
# color-manages that on the way to the screen, so the hex did not land where
# scheme.json put it: 19 of eva's 20 colors drew wrong, by up to 27/255 on a
# channel (cursor #ff3d5a as #ff586d, red #c41e3a as #d1344a, #808080 as
# #929292). Every other consumer treats the same hex as a literal sRGB value --
# the OSC packet in lib/color.ps1, Windows Terminal's settings.json, the live
# preview -- so `-NewWindow`, documented as carrying the FULL style, showed a
# different palette from the same style in the current window. README suggests
# making that profile the Terminal.app default, which made it permanent.
#
# The code comment justified calibrated on size, and that reasoning was sound
# but aimed at the wrong alternative: sRGB archives its whole ICC profile
# (4824 base64 chars per color). Device RGB archives to 328 -- the same as
# calibrated -- and round-trips exactly.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'a generated Terminal.app profile carries the style''s actual colors' {
    BeforeDiscovery {
        # Discovery-time, deliberately: a -Skip reading a BeforeAll variable
        # gets $null, which is falsy, so the test would silently pass on the
        # Windows and Linux jobs instead of reporting as skipped.
        $script:NoOsascript = -not (
            ($PSVersionTable.PSVersion.Major -ge 6) -and $IsMacOS -and
            (Get-Command osascript -ErrorAction SilentlyContinue))
    }

    It 'every color in <_> round-trips from scheme.json to the archived NSColor' -Skip:$script:NoOsascript -ForEach @(
        'eva', 'sober', 'rain', 'tombraider'
    ) {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $helper   = Join-Path (Join-Path $repoRoot 'shell') 'appleterminal.js'
        $scheme   = Get-Content -LiteralPath (Join-Path (Join-Path (Join-Path $repoRoot 'styles') $_) 'scheme.json') -Raw |
                    ConvertFrom-Json

        $colors = [ordered]@{}
        foreach ($prop in $scheme.PSObject.Properties) {
            if ($prop.Value -is [string] -and $prop.Value -match '^#[0-9a-fA-F]{6}$') {
                $colors[$prop.Name] = $prop.Value
            }
        }
        $colors.Count | Should -BeGreaterThan 8 -Because 'the scan must be finding real colors'

        $specPath = Join-Path $TestDrive "spec-$_.json"
        $outPath  = Join-Path $TestDrive "out-$_.json"
        [System.IO.File]::WriteAllText($specPath, (@{ colors = $colors } | ConvertTo-Json -Depth 4))

        & osascript -l JavaScript $helper $specPath $outPath *> $null
        Test-Path -LiteralPath $outPath | Should -BeTrue -Because 'the helper must produce a payload'

        # Unarchive each NSColor and convert it to sRGB -- what the display
        # actually receives -- then compare against scheme.json.
        $verify = Join-Path $TestDrive "verify-$_.js"
        [System.IO.File]::WriteAllText($verify, @'
ObjC.import('AppKit');
function readFile(p){ return $.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null).js; }
var argv = $.NSProcessInfo.processInfo.arguments.js;
var out  = JSON.parse(readFile(argv[4].js));
var want = JSON.parse(readFile(argv[5].js)).colors;
function px(v){ var n = Math.round(v*255); return ('0'+n.toString(16)).slice(-2); }
Object.keys(out).forEach(function (k) {
  var d = $.NSData.alloc.initWithBase64EncodedStringOptions(out[k], 0);
  var c = $.NSKeyedUnarchiver.unarchiveObjectWithData(d);
  var s = c.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
  var got = '#' + px(s.redComponent) + px(s.greenComponent) + px(s.blueComponent);
  if (got.toLowerCase() !== String(want[k]).toLowerCase()) {
    console.log('MISMATCH ' + k + ' want=' + want[k] + ' got=' + got + ' space=' + c.colorSpaceName.js);
  }
});
'@)
        # 2>&1, not 2>$null: console.log in JXA writes to STDERR. Discarding it
        # made this assertion vacuous -- the mismatches were being printed and
        # thrown away, and the test passed against the calibrated build it was
        # written to catch. ToString() because a redirected native stderr line
        # arrives as an ErrorRecord, which -match would test the wrong property
        # of.
        $bad = @(& osascript -l JavaScript $verify $outPath $specPath 2>&1 |
                 ForEach-Object { $_.ToString() } |
                 Where-Object { $_ -match 'MISMATCH' })

        $bad -join "`n" | Should -BeNullOrEmpty `
            -Because "$_'s new-window palette must be the palette in scheme.json"
    }
}
