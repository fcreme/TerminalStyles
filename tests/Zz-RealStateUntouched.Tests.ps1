# Pester 5 tests: a run of this suite must leave the operator's own files
# exactly as it found them.
#
# THE DEFECT CLASS, not a defect. This module edits files the user owns and that
# predate it -- ~/.zshrc, ~/.bashrc, ~/.bash_profile, ~/.profile, the PowerShell
# $PROFILE -- and stages its own runtime under a data root derived from the live
# $HOME. Every seam that keeps a test out of those files (-HomeDir, -ZDotDir,
# -Targets, $script:TStylesDataRoot) is OPT-IN, so a test that forgets one is
# silently correct: it passes, prints nothing, and edits the machine running it.
# That has now happened three times.
#
#   * 0.8.22: one rc candidate read the ambient $env:ZDOTDIR rather than the
#     sandboxed -HomeDir, so the suite appended a loader block to the
#     developer's real .zshrc -- pointing at a Pester temp dir deleted when the
#     run ended.
#   * FirstTouch-Backup.Tests.ps1 passed -HomeDir but never a data root, and
#     shell-init reaches Sync-ShellRuntime before it registers anything. Four
#     times a run it rewrote the operator's INSTALLED tstyles-cli.ps1 with an
#     install kind read off the checkout; on a bootstrap install that is the
#     by-name `Import-Module TerminalStyles`, which resolves to nothing there.
#     A green 7/7 run left every new zsh tab with no working `tstyles`.
#   * Merge-StyleIntoSettings.Tests.ps1 named its fixture style eva, so the
#     background probe lazy-fetched the real 3 MB eva.gif from the gifs branch
#     into the operator's own cache.
#
# Fixing each of those fixes one file, and the next one to forget a seam starts
# the count again. This file fails the RUN: it photographs the operator's state
# before any test executes and compares it after the last one, so the suite --
# not the developer noticing their prompt is gone -- is what catches it.
#
# HOW THE TIMING WORKS. Pester discovers every container before it runs any of
# them ("Starting discovery in N files" precedes "Running tests"), so
# BeforeDiscovery here is the earliest point in the run and photographs a state
# nothing has had the chance to touch yet. The comparison then has to be the
# LAST thing to execute, which is why this file is named to sort last in tests/
# -- and why the first test below asserts that it still does.
#
# WHAT IS DELIBERATELY NOT WATCHED. Windows Terminal's settings.json and
# ~/Library/Preferences/com.apple.Terminal.plist are rewritten by the terminal
# itself whenever it feels like it, on a schedule no test controls. Watching
# them would fail runs for something no test did, and a guard that cries wolf
# gets deleted. They stay covered by the -Path/-Targets seams alone.
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

Describe 'the suite leaves the operator''s own state alone' {

    It 'sorts last in tests/, or it is guarding nothing' {
        # The comparison below is only a guard if every other file has already
        # had its turn. A file added later that sorts after this one would move
        # its writes past the photograph and out of view -- silently, which is
        # this project's favourite way for a test to keep passing while
        # measuring nothing. So: fail here instead.
        #
        # Asserted on the NAMES rather than on the order Get-ChildItem happens
        # to return, because that order is the provider's business and differs
        # by platform; the name ordering is the property Pester's own expansion
        # of Run.Path follows, and it is the same on all four CI legs.
        $mine = $global:TStylesGuardFileName
        $mine | Should -Not -BeNullOrEmpty -Because 'the name is captured in BeforeDiscovery; without it every file below sorts "after" nothing'
        $later = @(
            Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
                ForEach-Object { $_.Name } |
                Where-Object { [string]::Compare($_, $mine, [StringComparison]::OrdinalIgnoreCase) -gt 0 }
        )
        $later.Count | Should -Be 0 -Because (
            "this file must run last; these sort after it and would escape the check: " +
            ($later -join ', '))
    }

    It 'notices a write, so a green result here means something' {
        # The guard's own mechanism, measured rather than assumed. If the probe
        # ever stopped seeing writes -- a swallowed error, an enumeration that
        # skips dotfiles -- the real check below would report all-clear for the
        # rest of this project's life, which is worse than having no guard.
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dot = Join-Path $dir '.hidden-on-unix'
        [System.IO.File]::WriteAllText($dot, 'x')

        $before = & $global:TStylesRealStateProbe -Path @($dir)

        [System.IO.File]::WriteAllText((Join-Path $dir 'created'), 'y')
        [System.IO.File]::WriteAllText($dot, 'xx')
        $after = & $global:TStylesRealStateProbe -Path @($dir)

        $after.Contains((Join-Path $dir 'created')) | Should -BeTrue -Because 'a new file must be visible'
        $before.Contains($dot) | Should -BeTrue -Because 'a dotfile must be visible, which is what -Force buys'
        $after[$dot] | Should -Not -Be $before[$dot] -Because 'a rewritten file must not compare equal'
    }

    It 'has created, changed or removed nothing under the data root, the rc files or $PROFILE' {
        $before = $global:TStylesRealStateBefore
        $before | Should -Not -BeNullOrEmpty -Because 'the baseline is taken in BeforeDiscovery; with none, this test measures nothing'
        @($global:TStylesRealStateWatch).Count | Should -BeGreaterThan 0 -Because 'the watch list is what the baseline was taken of'

        $after = & $global:TStylesRealStateProbe -Path $global:TStylesRealStateWatch

        $changes = @()
        foreach ($k in $before.Keys) {
            if (-not $after.Contains($k)) {
                $changes += "REMOVED  $k"
            } elseif ($after[$k] -cne $before[$k]) {
                $changes += "CHANGED  $k  [$($before[$k])] -> [$($after[$k])]"
            }
        }
        foreach ($k in $after.Keys) {
            if (-not $before.Contains($k)) { $changes += "CREATED  $k  [$($after[$k])]" }
        }

        $changes.Count | Should -Be 0 -Because (
            "a test wrote to the operator's real state. Sandbox it with -HomeDir/-ZDotDir/-Targets " +
            "AND `$script:TStylesDataRoot -- both, see CLAUDE.md. Changed during this run:`n    " +
            ($changes -join "`n    ") + "`n")
    }
}
