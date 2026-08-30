# Pester 5 tests: the two background downloaders must not share a temp file,
# and a temp that vanishes must never be recorded as "this style has no
# background".
#
# THE RACE. On a first picker run the prefetch job (tstyles.ps1) and the
# synchronous resolver (lib/background.ps1) both fetch the SAME style, and both
# derived their temp path from the same cache dir as "$local.part". The loser's
# temp vanished mid-flight, so `Get-Item` returned $null and
# `$null.Length -gt 0` quietly took the "the server sent an empty file" branch
# instead of the catch -- leaving $definitelyAbsent true, so the call returned
# $null and wrote a .no-background marker of kind 'absent'. Measured: 3 of 4
# consecutive runs lost it.
#
# What that actually costs, stated carefully. When the loser lost because the
# WINNER renamed the image into place, the marker is dead bytes: the cached-file
# check at the top of Get-StyleBundledBackground returns before the marker is
# ever read. The cost is that ONE call -- a WT profile written with no
# backgroundImage, persisting in settings.json until the next apply. The 'absent'
# marker's 30-day TTL only bites in the OTHER ordering, where the sibling's catch
# unlinks an in-flight temp and no image lands at all. Both halves of the fix
# still earn their place; the first prevents the common case, the second bounds
# the uncommon one to an hour.
#
# Two independent fixes, because either alone leaves a hole:
#   * distinct temp names, so the race does not happen; and
#   * missing != empty, so if anything else ever removes a temp, the result is
#     inconclusive (1-hour 'unreachable') rather than a month-long lie.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'the two downloaders do not share a temp path' {
    It 'the synchronous resolver and the prefetch job use different temp names' {
        # The whole defect in one assertion. Both derive from the same cache
        # directory, so identical suffixes means one path and a guaranteed
        # collision whenever both run for the same style -- which is the normal
        # first run after an install.
        $repoRoot = Split-Path $PSScriptRoot -Parent

        $bg  = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'lib/background.ps1'))
        $ts  = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tstyles.ps1'))

        $syncTemp = ([regex]::Match($bg, '\$part\s*=\s*"(\$local\.part[^"]*)"')).Groups[1].Value
        $jobTemp  = ([regex]::Match($ts, '\$part\s*=\s*"(\$local\.part[^"]*)"')).Groups[1].Value

        $syncTemp | Should -Not -BeNullOrEmpty -Because 'the synchronous resolver must still download to a temp'
        $jobTemp  | Should -Not -BeNullOrEmpty -Because 'the prefetch job must still download to a temp'
        $syncTemp | Should -Not -Be $jobTemp `
            -Because 'sharing one temp path is what made a finished download report as no background'
    }

    It 'neither temp name is one a reader would treat as a cache hit' {
        # The original reason for .part-and-rename: a file at background.<ext>
        # is treated as a complete cache entry and nothing revalidates it, so a
        # truncated download must never land there.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        foreach ($f in 'lib/background.ps1', 'tstyles.ps1') {
            $src = [System.IO.File]::ReadAllText((Join-Path $repoRoot $f))
            $src | Should -Match '\$part\s*=\s*"\$local\.part' `
                -Because "$f must download beside the final name, not onto it"
            $src | Should -Match 'Move-Item -LiteralPath \$part' `
                -Because "$f must rename into place only once the transfer finished"
        }
    }
}

Describe 'a vanished temp is inconclusive, not a definite absence' {
    InModuleScope TerminalStyles {
        It 'does not write a 30-day absent marker when the temp disappears' {
            # Drives the real resolver with a download that "succeeds" and then
            # leaves nothing behind -- exactly what losing the race looks like
            # from inside this function.
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $styleDir = Join-Path $root 'styles/racy'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"racy"}')

            # Succeeds, writes nothing: the file is gone by the time it is checked.
            Mock Invoke-WebRequest { }

            # Built from $root directly, NOT via Get-StyleCacheDir after the
            # finally below has restored the real data root -- that mistake
            # pointed the assertion at the wrong directory, found no marker,
            # and combined with an `if (Test-Path ...)` wrapper made the whole
            # test pass vacuously on a broken tree.
            $marker = Join-Path (Join-Path (Join-Path $root 'cache') 'racy') '.no-background'

            $saved = $script:TStylesDataRoot
            try {
                $script:TStylesDataRoot = $root
                $result = Get-StyleBundledBackground -StyleDir $styleDir
            } finally { $script:TStylesDataRoot = $saved }

            $result | Should -BeNullOrEmpty -Because 'nothing was actually fetched'

            Test-Path -LiteralPath $marker | Should -BeTrue -Because 'the probe did record a result'
            ([System.IO.File]::ReadAllText($marker) | ConvertFrom-Json).kind |
                Should -Be 'unreachable' `
                -Because 'a temp that vanished is not the server saying the file is absent, and absent buys 30 days'
        }

        It 'still records a real 404 as absent, which is worth a month' {
            # The other direction: the fix must not turn every failure into a
            # one-hour marker, or a style with genuinely no background re-probes
            # four URLs every hour forever.
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $styleDir = Join-Path $root 'styles/nobg'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'), '{"name":"nobg"}')

            Mock Invoke-WebRequest { throw 'not found' }
            Mock Test-HttpNotFound { $true }

            $marker = Join-Path (Join-Path (Join-Path $root 'cache') 'nobg') '.no-background'

            $saved = $script:TStylesDataRoot
            try {
                $script:TStylesDataRoot = $root
                Get-StyleBundledBackground -StyleDir $styleDir | Out-Null
            } finally { $script:TStylesDataRoot = $saved }

            Test-Path -LiteralPath $marker | Should -BeTrue
            ([System.IO.File]::ReadAllText($marker) | ConvertFrom-Json).kind | Should -Be 'absent'
        }
    }
}
