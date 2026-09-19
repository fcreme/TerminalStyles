# The wordmark, once, on the first interactive `tstyles`.
#
# It has to HOLD the screen. The picker Clear-Host's on the way in and anything
# printed above the frame is wiped unread, so a banner that merely printed would
# flash and vanish -- and would have spent its one-time marker doing it. That is
# not hypothetical: the font prompt beside it lost its single offer exactly that
# way, into a redirect, and the write-up sits above that function.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Test-ShouldShowWelcome' {
    InModuleScope TerminalStyles {

        It 'shows only on a first run, and only where it can be seen' {
            Test-ShouldShowWelcome -MarkerPresent $false -Interactive $true  | Should -BeTrue
            Test-ShouldShowWelcome -MarkerPresent $true  -Interactive $true  | Should -BeFalse
            Test-ShouldShowWelcome -MarkerPresent $false -Interactive $false | Should -BeFalse `
                -Because 'a one-time banner printed into a redirect is spent on nobody'
            Test-ShouldShowWelcome -MarkerPresent $true  -Interactive $false | Should -BeFalse
        }
    }
}

Describe 'Invoke-WelcomeFirstRun' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ('w-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:marker = Join-Path $script:TStylesDataRoot '.welcomed'
            Mock Test-InteractiveConsole { $true }
            Mock Read-Host { '' }
        }

        It 'prints the wordmark and waits, the first time' {
            $out = Invoke-WelcomeFirstRun 6>&1 | Out-String
            $out | Should -Match 'themed styles for your terminal'
            foreach ($line in (Get-TStylesWordmark)) {
                $out.Contains($line) | Should -BeTrue -Because "the art has to arrive whole: '$line'"
            }
            # The hold is the whole point: without it the picker's Clear-Host
            # wipes this before anyone reads it.
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It
        }

        It 'never shows twice' {
            Invoke-WelcomeFirstRun 6>&1 | Out-Null
            Test-Path -LiteralPath $script:marker | Should -BeTrue

            $second = Invoke-WelcomeFirstRun 6>&1 | Out-String
            $second | Should -BeNullOrEmpty
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It `
                -Because 'the second run must not block on a prompt nobody asked for'
        }

        It 'says nothing, and spends nothing, in a redirected session' {
            Mock Test-InteractiveConsole { $false }
            $out = Invoke-WelcomeFirstRun 6>&1 | Out-String
            $out | Should -BeNullOrEmpty
            Test-Path -LiteralPath $script:marker | Should -BeFalse `
                -Because 'the one showing is still owed to the first real console'
            Should -Invoke Read-Host -Times 0 -Exactly -Scope It
        }

        It 'does not take the picker down when the marker cannot be written' {
            # Seeing the welcome twice is a smaller cost than failing to open.
            # No mock needed: a data root that does not exist makes Test-Path
            # answer false on its own, and the write then throws.
            $script:TStylesDataRoot = Join-Path $TestDrive 'not-a-real-dir/deeper'
            { Invoke-WelcomeFirstRun 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'fits the 80-column floor, hint line included' {
            # The art is held to 78 in Install-Hardening; a hint that wraps
            # under it undoes the point. Measured on the whole thing, because
            # the line that actually wrapped in a real window was the hint.
            $out = Invoke-WelcomeFirstRun 6>&1 | Out-String
            foreach ($line in ($out -split "`n")) {
                $line.TrimEnd().Length | Should -BeLessOrEqual 78 `
                    -Because "'$($line.TrimEnd())' has to fit"
            }
        }

        It 'names how many styles there are, from the real list' {
            $out = Invoke-WelcomeFirstRun 6>&1 | Out-String
            $n = @(Get-AvailableStyles).Count
            $out | Should -Match "$n styles ready" -Because 'a hardcoded count would go stale'
        }
    }
}

Describe 'the welcome runs before the screen is cleared' {
    InModuleScope TerminalStyles {

        It 'is called above the picker, not inside it' {
            # Structural: the picker body needs a console and a keypress loop no
            # test can drive. What matters is the ORDER -- below the Clear-Host
            # this banner would be wiped, and above it the font prompt already
            # proves output survives to be read.
            # Asked of the AST, not of the text. A string search found the
            # phrase "Clear-Host" inside a COMMENT two lines above the call it
            # was meant to be ordered against, and reported the call as coming
            # last -- the source-text fragility this project keeps paying for.
            $ast = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $callsTo = {
                param($name)
                @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq $name }, $true) |
                  ForEach-Object { $_.Extent.StartOffset })
            }
            $welcome = & $callsTo 'Invoke-WelcomeFirstRun'
            $clear   = & $callsTo 'Clear-Host'
            @($welcome).Count | Should -Be 1
            @($clear).Count   | Should -BeGreaterThan 0 -Because 'the picker does clear the screen'
            $welcome[0] | Should -BeLessThan ($clear | Measure-Object -Minimum).Minimum `
                -Because "anything printed below the picker's Clear-Host is wiped unread"
        }
    }
}
