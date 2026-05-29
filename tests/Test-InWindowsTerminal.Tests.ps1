# Pester 5 tests for Test-InWindowsTerminal: detects the Windows Terminal host
# via $env:WT_SESSION (the gate for loading a style's prompt/banner).
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

Describe 'Test-InWindowsTerminal' {
    InModuleScope TerminalStyles {
        BeforeEach { $script:savedWT = $env:WT_SESSION }
        AfterEach  {
            if ($null -eq $script:savedWT) { Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue }
            else { $env:WT_SESSION = $script:savedWT }
        }

        It 'returns $true when WT_SESSION is set' {
            $env:WT_SESSION = 'abc-123-session'
            Test-InWindowsTerminal | Should -BeTrue
        }
        It 'returns $false when WT_SESSION is empty' {
            $env:WT_SESSION = ''
            Test-InWindowsTerminal | Should -BeFalse
        }
        It 'returns $false when WT_SESSION is not set' {
            Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
            Test-InWindowsTerminal | Should -BeFalse
        }
    }
}
