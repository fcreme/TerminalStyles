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
            # The console is pinned rather than inherited. Test-InteractiveConsole
            # is the one predicate the gate asks (its truth table is
            # Consent-Gates.Tests.ps1's), so its no must mean no question and no
            # marker -- on every leg, and at the terminal CONTRIBUTING runs the
            # suite from. This used to assert that Pester's own host was
            # redirected, which is true in CI and false there, so it failed at
            # every terminal. Counting the predicate's calls still catches the
            # original defect: a gate that reads [Environment]::UserInteractive
            # again never asks it, and where that is true it reaches the
            # Read-Host, which throws.
            Mock Test-InteractiveConsole { $false }
            Mock Read-Host { throw 'the font offer must not ask with nobody at the console' }

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
            Should -Invoke Test-InteractiveConsole -Times 1 -Exactly -Scope It `
                -Because 'the gate has to ask the shared predicate, not a .NET static of its own'
        }
    }
}
