# Pester 5 tests for Get-StyleCacheDir: the single source of truth for a
# style's writable, per-user background cache dir. Shared by
# Get-StyleBundledBackground, Test-StyleResolved, and the picker prefetch job
# so the writer and readers can never drift (regression guard for the picker
# prefetch writing to the wrong directory).
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

Describe 'Get-StyleCacheDir' {
    InModuleScope TerminalStyles {
        It 'resolves to $DataRoot\cache\<name>' {
            $script:TStylesDataRoot = $TestDrive
            Get-StyleCacheDir -StyleName 'eva' | Should -Be (Join-Path $TestDrive 'cache\eva')
        }

        It 'matches the cache dir Get-StyleBundledBackground writes/reads' {
            # The negative-cache marker the synchronous path writes (cacheDir) must
            # be the same dir Get-StyleCacheDir reports, so the prefetch job (which
            # uses the same formula) and the readers agree.
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $styleDir = Join-Path $script:TStylesModuleRoot 'styles\lonely'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            $cacheDir = Get-StyleCacheDir -StyleName 'lonely'
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            # A FRESH, dated marker. An empty one now reads as expired (0.8.6
            # made the negative cache time out so an offline apply cannot lose a
            # background permanently), which would send this test to the network.
            [System.IO.File]::WriteAllText((Join-Path $cacheDir '.no-background'),
                ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false))

            # A .no-background in the Get-StyleCacheDir location makes the style
            # "resolved" and suppresses the synchronous fetch.
            Test-StyleResolved -StyleDir $styleDir | Should -BeTrue
            Get-StyleBundledBackground -StyleDir $styleDir | Should -BeNullOrEmpty
        }
    }
}
