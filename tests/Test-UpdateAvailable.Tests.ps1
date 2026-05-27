# Pester 5 tests for Test-UpdateAvailable (the 24h-throttled update check).
#
# Locks in the throttle invariants from
# docs/superpowers/specs/2026-05-27-update-check-throttle-design.md:
#   - Fresh stamp short-circuits the API call entirely (no IRM invocation).
#   - Stale / missing stamp triggers the API call and writes a fresh stamp.
#   - Corrupt stamp falls through and self-heals (overwritten with valid value).
#   - API failure still writes the stamp -- the bug that motivated the spec
#     was an offline machine retrying the 2s timeout on every invocation.
#   - Update-available returns abbreviated 7-char SHA pair.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # Dot-source tstyles.ps1 to bring Test-UpdateAvailable into scope.
    # Suppress its load-time output so the test runner stays clean.
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Test-UpdateAvailable' {
    BeforeEach {
        # Redirect file I/O to a per-test temp dir so we never touch the
        # user's real .last-update-check or .installed-sha files.
        $script:TStylesRoot = $TestDrive
        $stampFile = Join-Path $TestDrive '.last-update-check'
        $shaFile   = Join-Path $TestDrive '.installed-sha'
        Remove-Item $stampFile -ErrorAction SilentlyContinue
        Remove-Item $shaFile   -ErrorAction SilentlyContinue
    }

    It 'returns $null and skips the API when the stamp is fresh (< 24h)' {
        $fresh = (Get-Date).AddMinutes(-30).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $fresh, [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { throw 'API should NOT be called inside the throttle window' }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'fires the API call when the stamp is stale (> 24h)' {
        $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }   # matches installed SHA

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty                    # SHA matches, no update
        Should -Invoke Invoke-RestMethod -Times 1
        Test-Path $stampFile | Should -BeTrue              # stamp rewritten
    }

    It 'fires the API call when no stamp file exists' {
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 1
        Test-Path $stampFile | Should -BeTrue
    }

    It 'self-heals on corrupt stamp (unparseable contents)' {
        [System.IO.File]::WriteAllText($stampFile, 'garbage not a date', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

        { Test-UpdateAvailable } | Should -Not -Throw

        Should -Invoke Invoke-RestMethod -Times 1
        # Stamp was overwritten with a valid timestamp
        $written = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false))
        { [datetime]::Parse($written, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } | Should -Not -Throw
    }

    It 'still writes the stamp when the API call fails' {
        # THE key invariant: without write-on-failure, an offline machine
        # would retry the 2s timeout on every single tstyles invocation.
        [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { throw 'simulated network failure' }

        $result = Test-UpdateAvailable

        $result | Should -BeNullOrEmpty
        Test-Path $stampFile | Should -BeTrue
    }

    It 'returns the abbreviated SHA pair when remote SHA differs from installed' {
        $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($shaFile, '0000000000000000000000000000000000000000', [System.Text.UTF8Encoding]::new($false))

        Mock Invoke-RestMethod { @{ sha = 'abc123def4567aaaaaaaaaaaaaaaaaaaaaaaaaaa' } }

        $result = Test-UpdateAvailable

        $result | Should -Not -BeNullOrEmpty
        $result.Installed | Should -Be '0000000'
        $result.Remote    | Should -Be 'abc123d'
    }
}
