#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Pester 5 tests for install.ps1 hardening. The installer is dot-sourced
# with $TStylesInstallNoRun = $true so its functions load WITHOUT running
# the download/install flow -- mirrors apply.ps1's $TStylesApplyNoRun seam.

Describe 'install.ps1 test seam' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath   # if the guard fails, this would attempt a network download
    }

    It 'loads functions without running the installer' {
        Get-Command Get-ShellInfo            -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Register-LoaderInProfile -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Resolve-ExecutionPolicy  -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
