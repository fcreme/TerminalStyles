# The banner is not decoration. It states a theme count and paints one swatch
# per bundled style, both read from styles/ when it is rendered -- so it makes
# the same kind of claim the README's prose does, and this project has already
# shipped "16 themes" against a folder of 15.
#
# A PNG cannot be inspected, so scripts/make-banner.py writes docs/banner.json
# with what it drew. Comparing THAT to styles/ is the only way a picture can be
# held to what it says: if someone adds or removes a style, this fails and the
# banner has to be regenerated.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Manifest = Get-Content (Join-Path $script:Root 'docs/banner.json') -Raw | ConvertFrom-Json
    $script:StyleDirs = @(Get-ChildItem (Join-Path $script:Root 'styles') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') })
}

Describe 'the banner matches the styles it claims' {

    It 'counts the styles that actually ship' {
        $script:Manifest.themes | Should -Be $script:StyleDirs.Count `
            -Because 'regenerate it with: python3 scripts/make-banner.py'
    }

    It 'names those styles, in the order the banner drew them' {
        @($script:Manifest.styles) | Should -Be @($script:StyleDirs.Name | Sort-Object)
    }

    It 'paints each style''s real accent, not a chosen one' {
        # The strip is the tool's palette range. A hand-picked set of pretty
        # colours would be a nicer picture and a false one.
        for ($i = 0; $i -lt $script:StyleDirs.Count; $i++) {
            $dir = $script:StyleDirs | Sort-Object Name | Select-Object -Index $i
            $scheme = Get-Content (Join-Path $dir.FullName 'scheme.json') -Raw | ConvertFrom-Json
            $expected = if ($scheme.brightRed) { $scheme.brightRed } else { $scheme.red }
            $script:Manifest.accents[$i] | Should -Be $expected -Because "$($dir.Name) paints $expected"
        }
    }

    It 'is what the README actually shows' {
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $readme | Should -Match 'docs/banner\.png' -Because 'a banner nothing references is not a banner'
    }

    It 'ships the image it describes' {
        # banner.json could always be compared to styles/, but nothing could
        # tell whether the IMAGE had been regenerated after the JSON was. A
        # 15-swatch banner beside 16 styles got as far as being caught by eye.
        $png = Join-Path $script:Root 'docs/banner.png'
        Test-Path -LiteralPath $png | Should -BeTrue -Because 'the banner lives in the repo now, not on the gifs branch'
        $script:Manifest.sha256 | Should -Not -BeNullOrEmpty
        $actual = (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant()
        $actual | Should -Be $script:Manifest.sha256 `
            -Because 'regenerate both with: python3 scripts/make-banner.py'
    }

    It 'does not reach off to another branch for it' {
        # The gifs branch exists to keep 32MB of style animations off main. A
        # 21KB banner there was one more copy to forget to push, and the
        # PowerShell Gallery does not render the README anyway -- it shows the
        # release notes -- so the absolute URL bought nothing.
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $readme | Should -Not -Match 'gifs/tstyles-banner\.png'
    }

    It 'leaves the page with a name when the image does not load' {
        # The banner replaced the H1, so alt text is what carries the name
        # when the image does not render -- a reader on a plain-text view, a
        # screen reader, or a mirror that did not copy docs/.
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $m = [regex]::Match($readme, 'docs/banner\.png"[^>]*alt="([^"]+)"')
        $m.Success | Should -BeTrue -Because 'the banner needs alt text'
        $m.Groups[1].Value | Should -Match 'tstyles'
    }
}
