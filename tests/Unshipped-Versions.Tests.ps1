# docs/unshipped-versions.txt records versions that were tagged and never
# reached the PowerShell Gallery, so release-drift.yml can tell a gap somebody
# already knows about from a new one.
#
# The file is only worth having if it is accurate, and it is the kind of file
# that rots quietly: a typo'd version is not a version, and a record for a tag
# that does not exist records nothing. Neither would be noticed by the workflow
# that reads it -- an unrecognised entry just fails to match a tag, which looks
# exactly like a tag that was published.
#
# No network here. Whether a version is on the Gallery is release-drift.yml's
# question and needs the internet; whether this file describes real tags is
# answerable from the repo, on every CI leg, offline.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = Split-Path $PSScriptRoot -Parent
    $path = Join-Path $root 'docs/unshipped-versions.txt'
    if (-not (Test-Path -LiteralPath $path)) { throw "docs/unshipped-versions.txt is missing." }

    $script:Entries = @(
        [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false)) |
            Where-Object { $_ -and $_ -notmatch '^\s*#' } |
            ForEach-Object {
                $parts = @($_ -split '\s+' | Where-Object { $_ })
                @{ Line = $_; Version = $parts[0]; SupersededBy = $parts[1]; Fields = $parts.Count }
            }
    )
    if ($script:Entries.Count -eq 0) { throw 'No entries found; the format must have changed.' }
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Tags = @(git -C $script:Root tag -l 'v*' | Where-Object { $_ -match '^v\d+(\.\d+){1,3}$' })

    # Parsed again here on purpose. A BeforeDiscovery variable is not reliably
    # there at run time, and a test that reads one gets $null -- whose .Count
    # is 1 once wrapped, so a "no duplicates" check passes against nothing.
    $script:Rows = @(
        [System.IO.File]::ReadAllLines((Join-Path $script:Root 'docs/unshipped-versions.txt'),
            [System.Text.UTF8Encoding]::new($false)) |
            Where-Object { $_ -and $_ -notmatch '^\s*#' } |
            ForEach-Object { ($_ -split '\s+' | Where-Object { $_ })[0] }
    )
}

Describe 'docs/unshipped-versions.txt' {

    It 'records <Version> as a version that really was tagged' -ForEach $script:Entries {
        # A typo'd version records nothing: release-drift.yml would not match
        # it against any tag, which is indistinguishable from the tag having
        # been published.
        $script:Tags | Should -Contain "v$Version"
    }

    It 'names a real tag as what superseded <Version>' -ForEach $script:Entries {
        $SupersededBy | Should -Not -BeNullOrEmpty -Because 'the second field says what shipped instead'
        $script:Tags | Should -Contain "v$SupersededBy"
    }

    It 'says <Version> was superseded by something NEWER' -ForEach $script:Entries {
        # A skipped version is only harmless because a later one carried its
        # code. Pointing at an older version would be a record that explains
        # nothing.
        ([version]$SupersededBy) | Should -BeGreaterThan ([version]$Version)
    }

    It 'gives <Version> exactly the two fields the reader parses' -ForEach $script:Entries {
        $Fields | Should -Be 2
    }

    It 'records each version once' {
        $script:Rows.Count | Should -BeGreaterThan 0 -Because 'an empty file would pass every check below'
        @($script:Rows | Sort-Object -Unique).Count | Should -Be $script:Rows.Count
    }

    It 'is actually read by the workflow that needs it' {
        # The record and its reader are two halves of one rule. A file nothing
        # reads is a note to nobody, and a reader pointed at a path that does
        # not exist turns every recorded gap back into a failure.
        $wf = [System.IO.File]::ReadAllText((Join-Path $script:Root '.github/workflows/release-drift.yml'),
                  [System.Text.UTF8Encoding]::new($false))
        $wf | Should -Match 'docs/unshipped-versions\.txt'
        # Not "does the file mention $PSScriptRoot" -- the comment explaining
        # why not to use it says the word. What must not appear is a path BUILT
        # from it: a pwsh run: block lives in a temp file on the runner, so
        # $PSScriptRoot is that temp directory and every recorded gap would
        # silently come back as a failure.
        $wf | Should -Not -Match 'Join-Path \$PSScriptRoot'
        $wf | Should -Match 'GITHUB_WORKSPACE'
    }
}
