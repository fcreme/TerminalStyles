# Pester 5 tests: Get-ProcessRecord reads a process the way Find-WTHostExePath
# needs it.
#
# The one test in the suite that runs the real Win32_Process query. Everything
# else mocks Get-ProcessRecord, so a wrong property name, a uint32
# ParentProcessId left uncast, or a mishandled CreationDate would otherwise
# reach users as a walk that returns $null for every one of them. It is
# read-only: it reads this process and its parent, nothing else.
#
# It runs on the two Windows legs. Elsewhere it is skipped at RUN time, with
# Set-ItResult, never with -Skip: -- which is decided at discovery.
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

Describe 'Get-ProcessRecord' {
    InModuleScope TerminalStyles {
        It 'reads this process the way the walk needs it' {
            if ((Get-TStylesPlatform) -ne 'Windows') {
                Set-ItResult -Skipped -Because 'Win32_Process exists only on Windows'
                return
            }

            $rec = Get-ProcessRecord -Id $PID
            $me  = Get-Process -Id $PID

            $rec | Should -Not -BeNullOrEmpty
            $rec.Path | Should -Be $me.Path
            $rec.Name | Should -Be ([System.IO.Path]::GetFileName($me.Path))
            $rec.ParentId | Should -BeOfType [int]
            $rec.ParentId | Should -BeGreaterThan 0
            [math]::Abs(($rec.Started - $me.StartTime.ToUniversalTime()).TotalSeconds) |
                Should -BeLessThan 2 -Because 'Started is the creation time, in UTC'

            $parent = Get-ProcessRecord -Id $rec.ParentId
            $parent | Should -Not -BeNullOrEmpty -Because 'the process that started this one is still running'
            $parent.Started | Should -BeLessOrEqual $rec.Started -Because 'a parent is older than its child'
        }
    }
}
