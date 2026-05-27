# Pester 5 tests for Apply-StyleDirect's rolling settings.json.bak.
#
# Locks in the backup invariants from
# docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md:
#   - .bak captures the PRIOR state (not the merged state).
#   - .bak rolls (overwrites) on every direct apply.
#   - Copy-Item failure prints a yellow warning and lets the function
#     continue past the failure -- doesn't block the apply.
#   - .bak is written next to settings.json as "<settingsPath>.bak"
#     (not in a temp dir, not anywhere else).
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # Dot-source tstyles.ps1 to bring Apply-StyleDirect into scope.
    # Suppress its load-time output so the test runner stays clean.
    . (Join-Path $repoRoot 'tstyles.ps1') *> $null
}

Describe 'Apply-StyleDirect backup behavior' {
    BeforeEach {
        # Heavy mocking: no real settings.json mutation, no real merge,
        # no real network. We're testing the backup block in isolation.
        $script:TStylesRoot = $TestDrive

        # Fake settings.json with known content -- the backup should capture
        # this exact byte sequence before any mutation happens.
        $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
        $initialContent = '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}'
        [System.IO.File]::WriteAllText($script:fakeSettings, $initialContent, [System.Text.UTF8Encoding]::new($false))

        # Fake style directory so the StyleName-not-found early-exit doesn't fire
        $script:styleDir = Join-Path $TestDrive 'styles\fakeStyle'
        New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $script:styleDir 'scheme.json'),
            '{"name":"fakeScheme"}',
            [System.Text.UTF8Encoding]::new($false)
        )

        # Mock everything around the backup block so only the backup runs for real
        Mock Find-WTSettingsPath        { $script:fakeSettings }
        Mock Show-UpdateNoticeIfAvailable {}                          # skip the throttle path
        Mock Get-CurrentWTProfileName   { 'PowerShell' }
        Mock Merge-StyleIntoSettings    { param($Settings) $Settings } # passthrough, no real merge
        Mock Write-SettingsFile         {}                            # no real write
    }

    It 'writes settings.json.bak with the prior contents before merging' {
        $initial = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

        $bak = "$script:fakeSettings.bak"
        Test-Path $bak | Should -BeTrue
        [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $initial
    }

    It 'rolls the .bak file on a second invocation' {
        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
        $bak = "$script:fakeSettings.bak"
        $firstBakHash = (Get-FileHash $bak).Hash

        # Simulate the prior apply actually changing settings.json (normally
        # Merge-StyleIntoSettings + Write-SettingsFile would, but we mocked
        # them, so mutate the source manually to make a different second-run
        # pre-state).
        [System.IO.File]::WriteAllText(
            $script:fakeSettings,
            '{"profiles":{"list":[{"name":"DIFFERENT","guid":"{y}"}]}}',
            [System.Text.UTF8Encoding]::new($false)
        )

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
        $secondBakHash = (Get-FileHash $bak).Hash

        $secondBakHash | Should -Not -Be $firstBakHash
    }

    It 'prints yellow warning and continues when Copy-Item throws' {
        # Force the backup to fail. Filter by destination path so we don't
        # accidentally break other Copy-Item calls deeper in the function
        # (e.g., the profile.ps1 copy).
        Mock Copy-Item { throw 'simulated permission denied' } `
            -ParameterFilter { $Destination -like '*.bak' }
        Mock Write-Host { }   # capture color/text via Should -Invoke

        { Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell' } | Should -Not -Throw

        Should -Invoke Write-Host -ParameterFilter {
            $ForegroundColor -eq 'Yellow' -and "$Object" -match 'could not write backup'
        } -Times 1

        # Function continued past the backup failure -- the merge + write
        # mocks were still invoked.
        Should -Invoke Write-SettingsFile -Times 1
    }

    It 'writes the backup as <settingsPath>.bak (not anywhere else)' {
        $expectedBak = "$script:fakeSettings.bak"

        # Spy on Copy-Item via -ParameterFilter
        Mock Copy-Item { } -ParameterFilter {
            $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
        }

        Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
        }
    }
}
