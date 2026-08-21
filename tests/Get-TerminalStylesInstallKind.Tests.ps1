# Pester 5 tests for Get-TerminalStylesInstallKind.
#
# The function decides whether the module was installed via PSResourceGet
# (e.g., Install-PSResource into ~/Documents/PowerShell/Modules/) or via
# the iwr|iex bootstrap installer (always lands at %LOCALAPPDATA%\TerminalStyles\).
# The downstream consumers (Invoke-TerminalStylesUpdate, Invoke-TerminalStylesUninstall,
# Test-UpdateAvailable) branch their behavior on the result.
#
# Pure path comparison; no external calls. The function is module-private,
# so all tests run inside InModuleScope.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-TerminalStylesInstallKind' {
    InModuleScope TerminalStyles {
        # The bootstrap dir is wherever Get-TStylesDataRoot resolves to on THIS
        # platform (%LOCALAPPDATA%\TerminalStyles on Windows, ~/Library/Application
        # Support/TerminalStyles on macOS, $XDG_DATA_HOME/TerminalStyles on Linux).
        # Deriving it from the same helper the function uses keeps the test
        # meaningful everywhere instead of pinning it to Windows env vars, which
        # are null off Windows.
        BeforeAll {
            $script:OriginalModuleRoot = $script:TStylesModuleRoot
        }
        AfterAll {
            # Restore: $script:TStylesModuleRoot is module-wide state, and leaving
            # a bogus value behind would leak into later tests in this run.
            $script:TStylesModuleRoot = $script:OriginalModuleRoot
        }

        It "returns 'Bootstrap' when ModuleRoot equals the per-user data root" {
            $script:TStylesModuleRoot = Get-TStylesDataRoot
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap'
        }

        It "returns 'PSResourceGet' when ModuleRoot is under a PSModulePath dir" {
            # Simulate a typical PSResourceGet install path
            $script:TStylesModuleRoot =
                Join-Path (Join-Path $HOME 'Documents/PowerShell/Modules/TerminalStyles') '0.2.0'
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
        }

        It "returns 'PSResourceGet' when ModuleRoot is any path that isn't the bootstrap dir" {
            $script:TStylesModuleRoot = Join-Path $TestDrive 'arbitrary/unrelated/path'
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
        }
    }
}
