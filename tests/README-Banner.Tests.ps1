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
        $readme | Should -Match 'tstyles-banner\.png' -Because 'a banner nothing references is not a banner'
    }

    It 'leaves the page with a name when the image does not load' {
        # raw.githubusercontent is not this project's to rely on, and the banner
        # replaced the H1. Alt text is what carries the name when it 404s.
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $m = [regex]::Match($readme, 'tstyles-banner\.png"[^>]*alt="([^"]+)"')
        $m.Success | Should -BeTrue -Because 'the banner needs alt text'
        $m.Groups[1].Value | Should -Match 'tstyles'
    }
}
