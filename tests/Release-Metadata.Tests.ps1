# Pester 5 tests: the version, the CHANGELOG and the release notes must describe
# the same release.
#
# This drifted twice in one day. 0.8.18's heading was cut, then five more
# commits landed under [Unreleased] while ModuleVersion still said 0.8.18 -- so
# the tree carried work the release notes did not mention, and PSGallery
# versions are immutable. It was caught by hand both times, one of them minutes
# before an irreversible publish. docs/RELEASING.md has four manual steps here
# and nothing checked that they agreed.
#
# What is NOT asserted: that [Unreleased] is empty. Entries accumulating there
# between releases is the normal state. It only becomes wrong at PUBLISH time,
# which is where scripts/publish.ps1 gates it.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:repoRoot  = Split-Path $PSScriptRoot -Parent
    $script:manifest  = Join-Path $script:repoRoot 'TerminalStyles.psd1'
    $script:changelog = Join-Path $script:repoRoot 'CHANGELOG.md'

    $script:psd = Import-PowerShellDataFile -LiteralPath $script:manifest
    $script:version = [string]$script:psd.ModuleVersion
    $script:log = Get-Content -LiteralPath $script:changelog -Raw
    $script:notes = [string]$script:psd.PrivateData.PSData.ReleaseNotes
}

Describe 'the release metadata agrees with itself' {

    It 'has a plausible ModuleVersion' {
        $script:version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'the CHANGELOG has a dated section for this exact version' {
        # Bumping the manifest without cutting the section is half a release:
        # the package ships as X.Y.Z while the changelog still calls that work
        # unreleased.
        $script:log | Should -Match ("(?m)^## \[" + [regex]::Escape($script:version) + "\] - \d{4}-\d{2}-\d{2}\s*$") `
            -Because "CHANGELOG.md needs a '## [$($script:version)] - <date>' heading"
    }

    It 'the release notes are for this version, not the previous one' {
        # PSGallery shows these on the version's page and they cannot be
        # changed after upload, so notes describing the wrong release are
        # permanent.
        $script:notes | Should -Not -BeNullOrEmpty
        $script:notes | Should -Match ("^v" + [regex]::Escape($script:version) + ":") `
            -Because "ReleaseNotes should open with 'v$($script:version):'"
    }

    It 'the [Unreleased] compare link points at this version' {
        $script:log | Should -Match ("(?m)^\[Unreleased\]:\s*\S+/compare/v" + [regex]::Escape($script:version) + "\.\.\.HEAD\s*$")
    }

    It 'this version has its own compare link' {
        $script:log | Should -Match ("(?m)^\[" + [regex]::Escape($script:version) + "\]:\s*\S+/compare/")
    }

    It 'every dated section has a reference link, and vice versa' {
        # A section with no link renders as bare text on GitHub; a link with no
        # section is a leftover from a version that was renamed or dropped.
        $sections = @([regex]::Matches($script:log, '(?m)^## \[(\d+\.\d+\.\d+)\]') |
            ForEach-Object { $_.Groups[1].Value })
        $links = @([regex]::Matches($script:log, '(?m)^\[(\d+\.\d+\.\d+)\]:') |
            ForEach-Object { $_.Groups[1].Value })

        $sections.Count | Should -BeGreaterThan 5 -Because 'the scan must be finding real sections'

        $missingLink = @($sections | Where-Object { $_ -notin $links })
        $missingLink -join ', ' | Should -BeNullOrEmpty -Because 'each released section needs a compare link'

        $orphanLink = @($links | Where-Object { $_ -notin $sections })
        $orphanLink -join ', ' | Should -BeNullOrEmpty -Because 'each compare link needs a section'
    }

    It 'the newest dated section is this version' {
        # Catches a bump that added a section below an older one, or a release
        # cut that was never bumped.
        $first = [regex]::Match($script:log, '(?m)^## \[(\d+\.\d+\.\d+)\]')
        $first.Success | Should -BeTrue
        $first.Groups[1].Value | Should -Be $script:version `
            -Because 'the top dated section should be the version being shipped'
    }
}
