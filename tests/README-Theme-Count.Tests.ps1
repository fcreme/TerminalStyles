# The README opened with "arrow through 16 themes" while the folder held 15.
# It had been true; `halo` was removed and the sentence was not. Nothing checked
# it, because the per-style README guard looks at styles/<name>/README.md and
# never at the one people actually land on.
#
# The count is the first concrete claim the project makes about itself, on the
# page that is also the PSGallery listing. Worth one test.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
    $script:Bundled = @(Get-ChildItem (Join-Path $script:Root 'styles') -Directory).Count

    # Every page that tells a reader how many themes there are. docs/index.html
    # is published at fcreme.github.io, so a wrong count there is as public as
    # one in the README -- and all four of its claims were wrong while the
    # README's single one was right.
    $script:Pages = @(
        @{ Name = 'README.md';       Text = $script:Readme }
        @{ Name = 'docs/index.html'; Text = (Get-Content (Join-Path $script:Root 'docs/index.html') -Raw) }
    )

    $script:Words = @{
        one = 1; two = 2; three = 3; four = 4; five = 5; six = 6; seven = 7; eight = 8
        nine = 9; ten = 10; eleven = 11; twelve = 12; thirteen = 13; fourteen = 14
        fifteen = 15; sixteen = 16; seventeen = 17; eighteen = 18; nineteen = 19; twenty = 20
    }
}

Describe 'the README counts the themes it ships' {

    It 'states a number at all' {
        $script:Readme | Should -Match 'arrow through \d+ themes'
    }

    It 'states the number that is actually in styles/' {
        $m = [regex]::Match($script:Readme, 'arrow through (\d+) themes')
        [int]$m.Groups[1].Value | Should -Be $script:Bundled `
            -Because "styles/ holds $($script:Bundled); deleting or adding one has to update this sentence"
    }

    It 'counts correctly everywhere it counts at all, in digits or in words' {
        # The first version of this test pinned ONE sentence by its exact
        # wording -- "arrow through (\d+) themes". Two hundred lines further
        # down the same README said "Sixteen themes ship out of the box", and
        # the published site said sixteen four more times. A guard shaped like
        # one sentence only ever guards that sentence.
        $pattern = '(?i)\b(\d+|' + (($script:Words.Keys | Sort-Object) -join '|') + ')\s+themes\b'
        $wrong = @()
        foreach ($page in $script:Pages) {
            foreach ($match in [regex]::Matches($page.Text, $pattern)) {
                $raw = $match.Groups[1].Value
                $n = 0
                if (-not [int]::TryParse($raw, [ref]$n)) { $n = $script:Words[$raw.ToLowerInvariant()] }
                if ($n -ne $script:Bundled) { $wrong += "$($page.Name): '$($match.Value)'" }
            }
        }
        $wrong | Should -BeNullOrEmpty -Because "styles/ holds $($script:Bundled)"
    }

    It 'says how many at all' {
        # A count nobody states cannot be wrong, but it also cannot be the
        # first concrete thing the project says about itself.
        foreach ($page in $script:Pages) {
            $page.Text | Should -Match '(?i)\b(\d+|fifteen)\s+themes\b' -Because "$($page.Name) should say"
        }
    }

    It 'names WezTerm among the terminals that carry a background' {
        # WezTerm has driven font and animated background from the applied style
        # since 0.8.29, and off Windows it is the ONLY terminal that animates
        # one. The sentence credited Windows Terminal alone, which read as "not
        # on your Mac" to every macOS reader.
        $m = [regex]::Match($script:Readme, '(?s)font, opacity and animated background')
        $m.Success | Should -BeTrue
        $before = $script:Readme.Substring(0, $m.Index)
        $before.Substring([Math]::Max(0, $before.Length - 160)) | Should -Match 'WezTerm'
    }
}
