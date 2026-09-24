# A screenshot makes a claim about what a style looks like on a real terminal,
# and two kinds of file sit in docs/screenshots/ making it: captures taken by
# scripts/capture-screenshots.ps1 on a Windows box, and renders drawn by
# scripts/make-preview.py from the style's own data.
#
# A render is reproducible anywhere, which is why it exists; it is also NOT a
# photograph, and koholint's README says so in as many words. Saying it for
# some renders and not others is "every user-facing message is a claim" in its
# quietest form -- a reader cannot tell the two apart by looking, so an
# undisclosed render reads as a photograph of a real terminal.
#
# eva, neon-rain and phosphor were all rendered and none of them said so. The
# rule needed a reader, so here it is.
#
# The render size is parsed out of make-preview.py rather than restated here:
# the generator stays the one place that decides what a render measures.
#
# Everything a case needs is computed at DISCOVERY, and the sanity checks
# throw there rather than being assertions. A guard that cannot classify its
# inputs must not be able to report green while skipping every case -- and an
# `It` cannot be trusted to catch that, because `@($null).Count` is 1.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = Split-Path $PSScriptRoot -Parent

    $gen = [System.IO.File]::ReadAllText((Join-Path $root 'scripts/make-preview.py'),
              [System.Text.UTF8Encoding]::new($false))
    $m = [regex]::Match($gen, '(?m)^\s*W\s*,\s*H\s*=\s*(\d+)\s*,\s*(\d+)')
    if (-not $m.Success) {
        throw 'Could not read the canvas size (W, H = ...) from scripts/make-preview.py'
    }
    $renderW = [int]$m.Groups[1].Value
    $renderH = [int]$m.Groups[2].Value

    $shots = @(Get-ChildItem (Join-Path $root 'docs/screenshots') -Filter '*.png' | ForEach-Object {
        # No System.Drawing: absent on some .NET Core hosts, and this runs on
        # all four CI legs. IHDR width/height are big-endian uint32 at bytes
        # 16..23 of every PNG.
        #
        # The [int] casts are load-bearing. PowerShell's -shl keeps the
        # operand's width, so [byte]3 -shl 8 is 0, not 768: without them a
        # 900x340 render reads as 132x84 and every case below quietly
        # classifies it as a capture.
        $b = [byte[]]::new(24)
        $fs = [System.IO.File]::OpenRead($_.FullName)
        try { [void]$fs.Read($b, 0, 24) } finally { $fs.Dispose() }
        $w = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
        $h = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
        # A hashtable, not a [pscustomobject]: Pester defines a variable per
        # KEY, so `$Name` and `$ReadmePath` exist inside the case. Objects
        # only arrive as `$_`, and the case titles come out reading `$null`.
        @{
            Name       = $_.BaseName
            IsRender   = ($w -eq $renderW -and $h -eq $renderH)
            ReadmePath = Join-Path $root "styles/$($_.BaseName)/README.md"
        }
    })

    # demo.png documents the tool, not a style, so it has no style README.
    $script:RenderCases  = @($shots | Where-Object { $_.IsRender })
    $script:CaptureCases = @($shots | Where-Object { -not $_.IsRender -and (Test-Path $_.ReadmePath) })

    if ($script:RenderCases.Count -eq 0)  { throw 'No rendered screenshots found -- the size rule stopped matching.' }
    if ($script:CaptureCases.Count -eq 0) { throw 'No captured screenshots found -- the size rule stopped matching.' }
}

Describe 'a screenshot says which kind of picture it is' {

    It '<Name> is rendered, and its README says so' -ForEach $script:RenderCases {
        $ReadmePath | Should -Exist -Because "a render of $Name needs somewhere to disclose it"
        $readme = [System.IO.File]::ReadAllText($ReadmePath, [System.Text.UTF8Encoding]::new($false))
        # The note has to name ITS OWN picture. Matching the phrase alone
        # passes on a note copy-pasted from another style, which is the most
        # likely way this ever goes wrong -- all five were written that way.
        $pattern = '`docs/screenshots/' + [regex]::Escape($Name) + '\.png` is \*\*rendered\*\*'
        $readme | Should -Match $pattern `
            -Because "docs/screenshots/$Name.png is drawn, not photographed, and a reader cannot tell by looking"
    }

    It '<Name> is a capture, and does not claim to be rendered' -ForEach $script:CaptureCases {
        # The other direction of the same rule: a note left behind after a
        # render is replaced by a real capture is just as wrong.
        $readme = [System.IO.File]::ReadAllText($ReadmePath, [System.Text.UTF8Encoding]::new($false))
        $readme | Should -Not -Match 'is \*\*rendered\*\*' `
            -Because "docs/screenshots/$Name.png is a real capture"
    }
}
