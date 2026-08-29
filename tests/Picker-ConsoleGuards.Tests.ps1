# Pester 5 tests: the picker must refuse to run when it has no real console --
# in EITHER direction.
#
# Input was guarded from 0.8.0: [Console]::KeyAvailable throws outright when
# stdin is not a console, so the failure was loud.
#
# Output was not, and failed quietly instead. With stdout redirected -- `tstyles
# > log.txt`, `tstyles | tee`, any wrapper capturing the command -- stdin is
# still a console, so the input check did not fire and the picker ran. Measured
# on a pty: 42 bytes reached the terminal and 6291 bytes reached the file,
# containing four full menu frames, the OSC palette packets, two ESC[3J
# scrollback wipes and one "Style applied". The user sees a shell that appears
# to hang, while their keystrokes are read and acted on: arrows write
# settings.json on Windows Terminal and Enter applies a style they never saw.
#
# lib/tune.ps1 was given this guard in 0.8.18 with a comment describing the same
# failure. The picker is the other half of that pair and never got it.
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

Describe 'the picker refuses a session with no real console' {
    InModuleScope TerminalStyles {

        It 'guards on output as well as input' {
            # Pinned on the AST rather than behaviour because the discriminating
            # case -- stdin a console, stdout a file -- cannot be built from
            # inside Pester, which is redirected on both. It was reproduced on a
            # pty instead; see this file's header for the measurements.
            $ast = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast

            $guards = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and
                $n.Clauses[0].Item1.Extent.Text -match 'IsOutputRedirected' }, $true))

            $guards.Count | Should -Be 1 `
                -Because 'the picker must have exactly one redirected-output guard'
            $guards[0].Clauses[0].Item1.Extent.Text | Should -Match 'IsInputRedirected' `
                -Because 'one guard covers both directions, so neither can be forgotten'
        }

        It 'guards before it touches the screen or writes settings.json' {
            # The ordering IS the fix. Bailing out late is what put four menu
            # frames and two scrollback wipes into the capture file.
            $ast = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast

            $guard = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and
                $n.Clauses[0].Item1.Extent.Text -match 'IsOutputRedirected' }, $true))
            $guard.Count | Should -Be 1
            $guardAt = $guard[0].Extent.StartOffset

            # Read-Host is the one that matters most, and the one this test did
            # not name when it was first written -- so it passed while the
            # picker still prompted for a target 65 lines ABOVE the guard.
            # `tstyles > log.txt` therefore went on writing "Target profile:"
            # into the capture and blocking forever on a question the user
            # could not see, which is exactly what the guard was added to stop.
            # An ordering test that omits the call it should be ordering is
            # worth nothing.
            #
            # Clear-Host is the scrollback wipe and Merge-StyleIntoSettings is
            # the first thing that builds a settings.json to write.
            #
            # NOT Write-SettingsAtomic, though it is the actual write: its one
            # call site lives inside the $writeSettings scriptblock, which is
            # DEFINED above the guard and invoked below it. Comparing source
            # offsets would flag that as a violation and be wrong -- the check
            # measures where code is written, not when it runs.
            foreach ($name in 'Read-Host', 'Clear-Host', 'Merge-StyleIntoSettings') {
                $calls = @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq $name }, $true))
                $calls.Count | Should -BeGreaterThan 0 `
                    -Because "$name should still be reachable after the guard"
                foreach ($c in $calls) {
                    $c.Extent.StartOffset | Should -BeGreaterThan $guardAt `
                        -Because "the guard must run before $name"
                }
            }
        }

        It 'bails out with a message naming what is wrong' {
            # Behavioural half. Pester's host is redirected, so this exercises
            # the guard for real -- it just cannot choose which branch of the
            # message it gets.
            if (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
                Set-ItResult -Skipped -Because 'this test run has a real console attached'
                return
            }

            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $styleDir = Join-Path $TestDrive 'styles/fakeStyle'
            New-Item -ItemType Directory -Path $styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $styleDir 'scheme.json'),
                '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))

            Mock Get-TerminalKind          { 'AppleTerminal' }
            Mock Find-WTSettingsPath       { $null }
            Mock Invoke-FontFirstRunPrompt {}
            Mock Test-UpdateAvailable      { $null }
            Mock Write-Host                {}
            # None of these may run: the guard returns before the picker takes
            # the screen, so the user's scrollback survives.
            Mock Clear-Host          { throw 'the picker must not clear the screen before bailing out' }
            Mock Write-SettingsAtomic { throw 'the picker must not write settings.json without a console' }

            { Invoke-TerminalStyle } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'needs an interactive terminal' }
        }
    }
}
