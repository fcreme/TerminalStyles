#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-ShouldPromptFonts' {
    InModuleScope TerminalStyles {
        It 'prompts only when interactive and not previously prompted' {
            Test-ShouldPromptFonts -MarkerPresent $false -Interactive $true  | Should -BeTrue
            Test-ShouldPromptFonts -MarkerPresent $true  -Interactive $true  | Should -BeFalse
            Test-ShouldPromptFonts -MarkerPresent $false -Interactive $false | Should -BeFalse
            Test-ShouldPromptFonts -MarkerPresent $true  -Interactive $false | Should -BeFalse
        }
    }
}

Describe 'Invoke-FontFirstRunPrompt' {
    InModuleScope TerminalStyles {
        It 'does not burn the one-time offer when the session is not really interactive' {
            # The gate above is pure and was always green; what it was HANDED
            # was the defect. [Environment]::UserInteractive is $true whenever
            # the process has a console, redirected stdin included, so a bare
            # `tstyles` with stdin from a pipe or a file reached Read-Host --
            # which returns empty at EOF rather than throwing -- and then wrote
            # the marker regardless of the answer. The offer is one-time by
            # design, so it was spent: nobody saw the question, and no
            # interactive session was ever asked again.
            #
            # Pester itself is the condition under test: [Console] reports
            # redirected here, exactly as it does under a pipe or in CI. Before
            # the fix this test wrote the marker and consumed stdin; after it,
            # the function must decline and leave the offer intact.
            ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) |
                Should -BeTrue -Because 'this test is only meaningful in a redirected host'

            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $marker = Join-Path $root '.fonts-prompted'

            # Restored: InModuleScope shares module state with every other file
            # in the run, and the data root is where the rest of them look.
            $saved = $script:TStylesDataRoot
            try {
                $script:TStylesDataRoot = $root
                Invoke-FontFirstRunPrompt
            } finally {
                $script:TStylesDataRoot = $saved
            }

            Test-Path -LiteralPath $marker | Should -BeFalse `
                -Because 'a run nobody could answer must leave the one-time offer unspent'
        }
    }
}
