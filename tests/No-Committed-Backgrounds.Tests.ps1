# Pester 5 guard: per-style background images must NOT be committed to main.
# They live on the `gifs` branch and are lazy-fetched at runtime
# (Get-StyleBundledBackground), keeping the PSGallery package and install ZIP
# small. This test fails if any styles/*/background.* file is tracked by git,
# so the ~9MB of binaries can't silently creep back in via `git add -f`.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Committed background images' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    It 'does not track any styles/*/background.* binaries' {
        if (-not (Test-Path (Join-Path $script:repoRoot '.git'))) {
            Set-ItResult -Skipped -Because 'not a git checkout'
            return
        }
        $tracked = @(
            & git -C $script:repoRoot ls-files 'styles' |
                Where-Object { $_ -match '/background\.(gif|png|jpe?g)$' }
        )
        $tracked -join ', ' | Should -BeNullOrEmpty -Because 'background.* belongs on the gifs branch, not main'
    }
}
