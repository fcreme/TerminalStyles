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
