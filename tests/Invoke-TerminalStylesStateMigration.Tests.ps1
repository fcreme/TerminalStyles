# Pester 5 tests for Invoke-TerminalStylesStateMigration: the one-time pre-0.2.0
# -> 0.2.0 data-layout move (cached backgrounds + .no-background markers migrate
# from $ModuleRoot\styles\<name>\ to $DataRoot\cache\<name>\). Previously
# untested. Also locks the marker gate so a completed migration is a no-op.
#
# Each test uses its OWN data/module roots under $TestDrive because TestDrive
# persists across It blocks within a Describe.
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

Describe 'Invoke-TerminalStylesStateMigration' {
    InModuleScope TerminalStyles {
        It 'moves a legacy styles\<name>\background.* into cache\<name>\ and writes the marker' {
            $script:TStylesDataRoot   = Join-Path $TestDrive 'move\data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'move\module'
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $legacyStyle = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $legacyStyle -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $legacyStyle 'background.gif'), [byte[]](1,2,3))

            Invoke-TerminalStylesStateMigration

            Test-Path -LiteralPath (Join-Path $legacyStyle 'background.gif') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'cache\eva\background.gif') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.migrated-0.2.0') | Should -BeTrue
        }

        It 'is a no-op once the marker exists (does not move newly-placed legacy files)' {
            $script:TStylesDataRoot   = Join-Path $TestDrive 'noop\data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'noop\module'
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $legacyStyle = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $legacyStyle -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:TStylesDataRoot '.migrated-0.2.0'), '', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllBytes((Join-Path $legacyStyle 'background.gif'), [byte[]](1,2,3))

            Invoke-TerminalStylesStateMigration

            # Marker already present => gate short-circuits => legacy file stays put.
            Test-Path -LiteralPath (Join-Path $legacyStyle 'background.gif') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'cache\eva\background.gif') | Should -BeFalse
        }
    }
}
