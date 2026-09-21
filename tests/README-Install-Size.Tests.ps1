# The README stated the install size twice, with two different numbers -- "~100
# KB" in the Background image section and "~350 KB" under Known limitations --
# and the package actually weighed 917 KB. Three claims about one fact, none of
# them right, on the page that is also the PSGallery listing.
#
# A size claim cannot be pinned exactly: it moves with every file added. What
# CAN be pinned is that there is one number, that it is the same everywhere it
# appears, and that it is the right order of magnitude for what publish.ps1
# would actually stage.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Readme = Get-Content (Join-Path $script:Root 'README.md') -Raw

    # The same set publish.ps1 stages, read from its allowlist rather than
    # listed again here -- a second copy of that list is how the package and
    # the claim about it would drift apart in the first place.
    $pub = Get-Content (Join-Path $script:Root 'scripts/publish.ps1') -Raw
    $block = [regex]::Match($pub, '(?s)\$allowlist = @\((.*?)\n\)')
    $script:Allow = @([regex]::Matches($block.Groups[1].Value, "'([^']+)'") |
        ForEach-Object { $_.Groups[1].Value })

    $bytes = 0L
    foreach ($entry in $script:Allow) {
        $path = Join-Path $script:Root $entry
        if (Test-Path -LiteralPath $path -PathType Container) {
            $bytes += (Get-ChildItem -LiteralPath $path -Recurse -File |
                       Where-Object { $_.Name -notlike 'background.*' } |
                       Measure-Object Length -Sum).Sum
        } elseif (Test-Path -LiteralPath $path) {
            $bytes += (Get-Item -LiteralPath $path).Length
        }
    }
    $script:StagedKB = [int]($bytes / 1KB)
}

Describe 'the README states one install size, and states it once' {

    It 'reads its allowlist from publish.ps1 rather than a second copy' {
        $script:Allow | Should -Contain 'styles'
        $script:Allow | Should -Contain 'lib'
        $script:Allow | Should -Not -Contain 'tests'
        $script:StagedKB | Should -BeGreaterThan 100
    }

    It 'never gives two different answers' {
        # "~100 KB" and "~350 KB" sat 260 lines apart, both describing the same
        # package. A reader who saw both learned only that neither was checked.
        $claims = @([regex]::Matches($script:Readme, '~(\d+)\s*KB') |
                    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $claims.Count | Should -BeLessOrEqual 1 -Because "the README claims: $($claims -join ', ') KB"
    }

    It 'is the right size, not merely a consistent one' {
        $m = [regex]::Match($script:Readme, '~(\d+)\s*KB')
        $m.Success | Should -BeTrue -Because 'the README should say how big the install is'
        $claimed = [int]$m.Groups[1].Value
        # Half to double: the number is approximate by design ("~"), but 100 KB
        # against a 900 KB package is not approximation.
        $claimed | Should -BeGreaterThan ($script:StagedKB / 2) -Because "publish.ps1 would stage about $($script:StagedKB) KB"
        $claimed | Should -BeLessThan  ($script:StagedKB * 2) -Because "publish.ps1 would stage about $($script:StagedKB) KB"
    }
}

Describe 'the README does not deny its own features' {

    It 'does not say WezTerm gets no background image' {
        # One section explained animated backgrounds on WezTerm across 37 lines.
        # Another, 68 lines earlier, ended "no other terminal gets one yet".
        # WezTerm has carried one from the applied style since 0.8.29 and is the
        # only terminal off Windows that animates it.
        $script:Readme | Should -Match '(?m)^### Animated backgrounds on WezTerm'
        # Anchored to the line start, because '##' also matches inside '###' --
        # the first version of this grabbed '### Background images on
        # Terminal.app' instead and failed on a section that was already fine.
        #
        # \r? on both ends, because actions/checkout hands Windows a CRLF
        # working tree: '$' matches only before the \n, and with \r sitting
        # in between, '^## Background image$' matched nothing there. macOS and
        # Linux passed; the two Windows jobs did not.
        $bg = [regex]::Match($script:Readme, '(?sm)^## Background image\r?$.*?(?=\r?\n## )').Value
        $bg | Should -Not -BeNullOrEmpty -Because 'the section has to be found before it can be checked'
        $bg | Should -Match 'WezTerm' -Because 'the section about background images has to mention the terminal that shows them best'
        $bg | Should -Not -Match 'no other terminal gets one yet'
    }
}
