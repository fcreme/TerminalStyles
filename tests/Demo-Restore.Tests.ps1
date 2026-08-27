# Pester 5 tests for scripts/demo.ps1's park/restore of the maintainer's own
# styles. 678 lines that had no coverage at all, and one of the few things in
# this repo that moves a user's real data.
#
# The bug pinned: prep MOVES <data-root>/styles aside to styles.demo-parked, so
# the parked tree is the only copy. Restore's merge branch skipped any parked
# style whose name already existed in the live dir, then deleted the whole
# parked directory -- destroying the original with no backup and no warning,
# under a comment saying it merged rather than clobbered.
#
# It is not an exotic collision. tune's default save is "[1] Overwrite '<name>'
# (shadows the bundled style)", so a user style named after a bundled one is the
# ordinary shape, and tune's own overwrite warning cannot fire mid-demo because
# it probes the live styles dir that prep just emptied.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'demo.ps1 park/restore' {
    BeforeAll {
        $script:demoPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts') 'demo.ps1'

        function script:New-Style {
            param([string]$Root, [string]$Name, [string]$Marker)
            $d = Join-Path $Root $Name
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), $Marker,
                [System.Text.UTF8Encoding]::new($false))
            $d
        }
    }

    BeforeEach {
        # Dot-sourced per test: the script's $UserStyles / $ParkedDir are plain
        # script-scope variables, so each case gets a clean pair pointed at
        # TestDrive rather than at the maintainer's real data root.
        $TStylesDemoNoRun = $true
        . $script:demoPath
        $case        = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $UserStyles  = Join-Path $case 'styles'
        $ParkedDir   = Join-Path $case 'styles.demo-parked'
    }

    It 'dot-sources for its functions without running the demo' {
        # The demo parks real styles and takes over the terminal, so this seam is
        # load-bearing: without it no test here could exist.
        Get-Command Restore-UserStyles -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
        Get-Command Hide-UserStyles -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'restores a parked style when nothing took its place' {
        script:New-Style -Root $ParkedDir -Name 'mine' -Marker 'ORIGINAL' | Out-Null
        New-Item -ItemType Directory -Path $UserStyles -Force | Out-Null

        Restore-UserStyles 6>&1 | Out-Null

        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'mine') 'scheme.json')) |
            Should -Be 'ORIGINAL'
        Test-Path -LiteralPath $ParkedDir | Should -BeFalse -Because 'nothing was left to keep'
    }

    It 'merges a style created during the demo alongside the parked ones' {
        script:New-Style -Root $ParkedDir  -Name 'mine' -Marker 'ORIGINAL' | Out-Null
        script:New-Style -Root $UserStyles -Name 'fresh' -Marker 'NEW'     | Out-Null

        Restore-UserStyles 6>&1 | Out-Null

        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'mine') 'scheme.json'))  |
            Should -Be 'ORIGINAL'
        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'fresh') 'scheme.json')) |
            Should -Be 'NEW'
        Test-Path -LiteralPath $ParkedDir | Should -BeFalse
    }

    It 'never destroys the parked original when the name collides' {
        # The whole point. The parked copy is the ONLY copy.
        script:New-Style -Root $ParkedDir  -Name 'eva' -Marker 'MY-TUNED-EVA'    | Out-Null
        script:New-Style -Root $UserStyles -Name 'eva' -Marker 'MADE-MID-DEMO'   | Out-Null

        Restore-UserStyles 6>&1 | Out-Null

        [System.IO.File]::ReadAllText((Join-Path (Join-Path $ParkedDir 'eva') 'scheme.json')) |
            Should -Be 'MY-TUNED-EVA' -Because 'the parked tree is the only copy of the user''s own style'
        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'eva') 'scheme.json')) |
            Should -Be 'MADE-MID-DEMO' -Because 'and the demo must not clobber the live side either'
    }

    It 'says where the kept copy is rather than failing silently' {
        # Two styles claim one name and only the user knows which to keep, so the
        # script stops rather than choosing -- but it has to say so, and say where.
        script:New-Style -Root $ParkedDir  -Name 'eva' -Marker 'MY-TUNED-EVA'  | Out-Null
        script:New-Style -Root $UserStyles -Name 'eva' -Marker 'MADE-MID-DEMO' | Out-Null

        $out = Restore-UserStyles 6>&1 | Out-String

        $out | Should -Match 'eva'
        $out | Should -Match ([regex]::Escape($ParkedDir)) -Because 'the user has to be able to find it'
    }

    It 'still restores the non-colliding styles when one collides' {
        script:New-Style -Root $ParkedDir  -Name 'eva'   -Marker 'MY-TUNED-EVA'  | Out-Null
        script:New-Style -Root $ParkedDir  -Name 'other' -Marker 'ALSO-MINE'     | Out-Null
        script:New-Style -Root $UserStyles -Name 'eva'   -Marker 'MADE-MID-DEMO' | Out-Null

        Restore-UserStyles 6>&1 | Out-Null

        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'other') 'scheme.json')) |
            Should -Be 'ALSO-MINE' -Because 'one collision must not strand the rest'
        [System.IO.File]::ReadAllText((Join-Path (Join-Path $ParkedDir 'eva') 'scheme.json')) |
            Should -Be 'MY-TUNED-EVA'
    }

    It 'does nothing at all when there is no parked tree' {
        New-Item -ItemType Directory -Path $UserStyles -Force | Out-Null
        script:New-Style -Root $UserStyles -Name 'mine' -Marker 'UNTOUCHED' | Out-Null

        { Restore-UserStyles 6>&1 | Out-Null } | Should -Not -Throw
        [System.IO.File]::ReadAllText((Join-Path (Join-Path $UserStyles 'mine') 'scheme.json')) |
            Should -Be 'UNTOUCHED'
    }

    It 'refuses to park twice, which would strand the first parked tree' {
        # Hide-UserStyles moves rather than copies, so a second park over an
        # existing one would overwrite the real originals with demo leftovers.
        script:New-Style -Root $ParkedDir  -Name 'mine' -Marker 'ORIGINAL' | Out-Null
        script:New-Style -Root $UserStyles -Name 'mine' -Marker 'LATER'    | Out-Null

        Hide-UserStyles 6>&1 | Out-Null

        [System.IO.File]::ReadAllText((Join-Path (Join-Path $ParkedDir 'mine') 'scheme.json')) |
            Should -Be 'ORIGINAL'
    }
}
