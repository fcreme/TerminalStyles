# Pester 5 tests: photograph the operator's own state BEFORE any other test runs.
#
# The comparison lives in tests/Zz-RealStateUntouched.Tests.ps1; this file exists
# only to take the baseline, and it exists SEPARATELY because of when Pester runs
# things.
#
# THE TIMING BUG THIS FILE FIXES. The baseline used to sit in the guard file's own
# BeforeDiscovery, on the documented Pester 5 behaviour that every container is
# discovered before any is executed ("Starting discovery in N files" precedes
# "Running tests"). Pester 6 does not do that. It discovers and executes each file
# in turn -- its output is a bare "Running tests from '<file>'" per file, with no
# global discovery pass -- so a guard file that sorts LAST took its baseline AFTER
# every other file had already run and written. The baseline contained the damage,
# the comparison found nothing, and the guard reported green while measuring
# nothing at all. That is the exact defect class the guard was written to catch,
# in the guard.
#
# It matters beyond one developer's machine: .github/workflows/test.yml installs
# Pester with `[5.0.0,)` / `-MinimumVersion 5.0.0`, which resolves to the newest
# release, so CI legs run whichever major is current.
#
# Sorting FIRST is what makes the baseline early under both majors, and the test
# below asserts it still does.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null

    $global:TStylesGuardFileName = Split-Path -Leaf $PSCommandPath

    # ONE implementation of "what does the operator's state look like right
    # now", called for the baseline here and for the comparison in the test
    # below. Two would drift, and a drift between them reads as a leak.
    #
    # Metadata rather than content: a warm data root holds cached GIFs, and
    # hashing them on every run would cost more than the guard is worth. Length
    # plus LastWriteTimeUtc catches a creation, a deletion, a truncation and a
    # rewrite. The one write it cannot see is a Copy-Item whose source is
    # byte-identical, because Copy-Item carries the source's timestamp across --
    # which is also the one case where nothing was damaged.
    #
    # Ticks, not a formatted date: a timestamp that is compared has to be
    # culture-proof, and under a non-Gregorian calendar a formatted one is not.
    #
    # -Force on the enumeration is load-bearing. Without it a dotfile
    # (.migrated-0.2.0, .no-background) is invisible on Unix, and both sides of
    # the comparison would agree about a file neither of them can see.
    $global:TStylesRealStateProbe = {
        param([string[]]$Path)
        $state = [ordered]@{}
        foreach ($p in $Path) {
            if ([System.IO.Directory]::Exists($p)) {
                $state[$p] = 'directory'
                foreach ($e in @(Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue)) {
                    $entry = 'directory'
                    if (-not $e.PSIsContainer) {
                        $entry = '{0} bytes, mtime {1}' -f $e.Length, $e.LastWriteTimeUtc.Ticks
                    }
                    $state[$e.FullName] = $entry
                }
            } elseif ([System.IO.File]::Exists($p)) {
                $f = New-Object System.IO.FileInfo $p
                $state[$p] = '{0} bytes, mtime {1}' -f $f.Length, $f.LastWriteTimeUtc.Ticks
            } else {
                $state[$p] = 'absent'
            }
        }
        $state
    }

    # The files this module knows how to write, asked of the module itself
    # rather than re-listed here: a second list of rc files is a second answer,
    # and the two halves of that symmetry are exactly what 0.8.22 found had
    # diverged. No -HomeDir on the call, deliberately -- the live $HOME is the
    # whole point of this file.
    $m = Get-Module TerminalStyles
    $global:TStylesRealStateWatch = @(& $m { Get-TStylesDataRoot }) +
        @(& $m { Get-ShellRcRemovalCandidate } | ForEach-Object { $_.Path }) +
        @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)

    $global:TStylesRealStateBefore = & $global:TStylesRealStateProbe -Path $global:TStylesRealStateWatch
}

Describe 'the real-state baseline' {
    It 'sorts first in tests/, or the baseline is taken too late' {
        # Under Pester 6 a file is discovered immediately before it is executed,
        # so anything sorting ahead of this one has already had the chance to
        # write before the photograph was taken.
        $mine = Split-Path -Leaf $PSCommandPath
        $earlier = @(
            Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
                ForEach-Object { $_.Name } |
                Where-Object { [string]::Compare($_, $mine, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 }
        )
        $earlier.Count | Should -Be 0 -Because (
            "these sort before the baseline and could write before it is taken: " + ($earlier -join ', '))
    }

    It 'actually captured something' {
        $global:TStylesRealStateBefore | Should -Not -BeNullOrEmpty
        @($global:TStylesRealStateWatch).Count | Should -BeGreaterThan 0
    }
}
