# Pester 5 tests: `tstyles <name> -KeepPrompt` threads the switch to
# Apply-StyleDirect.
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

Describe 'tstyles <name> -KeepPrompt dispatch' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Apply-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'eva'; FullName = 'X' }) }
        }
        It 'threads -KeepPrompt to Apply-StyleDirect when set' {
            Invoke-TerminalStyle -Arg 'eva' -KeepPrompt
            Should -Invoke Apply-StyleDirect -Times 1 -ParameterFilter { $StyleName -eq 'eva' -and $KeepPrompt }
        }
        It 'does not set -KeepPrompt when the flag is absent' {
            Invoke-TerminalStyle -Arg 'eva'
            Should -Invoke Apply-StyleDirect -Times 1 -ParameterFilter { $StyleName -eq 'eva' -and -not $KeepPrompt }
        }
    }
}
