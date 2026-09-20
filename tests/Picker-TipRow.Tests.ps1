# The picker painted two hint lines on every redraw:
#
#   Up/Down to preview, Enter to keep, Esc to cancel
#   Tip: run 'tstyles help' for all commands
#
# The first is what the keys do and has to be there every time. The second is
# onboarding, and onboarding that never ends is a tax -- it cost a viewport row
# on every redraw of every session forever, which is one fewer style visible in
# the window. On a 24-row terminal with 15 styles that is 13 visible instead of
# 14.
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

Describe 'Test-ShouldShowPickerTip' {
    InModuleScope TerminalStyles {

        It 'shows it while the commands are still new' {
            foreach ($n in 1, 2, 3) {
                Test-ShouldShowPickerTip -RunCount $n | Should -BeTrue -Because "run $n is still early"
            }
        }

        It 'gives the row back after that' {
            foreach ($n in 4, 5, 40) {
                Test-ShouldShowPickerTip -RunCount $n | Should -BeFalse -Because "run $n has seen it three times"
            }
        }

        It 'shows it on a machine that has never opened the picker' {
            # 0 is what an unreadable or missing counter reads as, and the
            # failure has to mean "show it": state this tool cannot read is not
            # a reason to hide the line pointing a newcomer at the commands.
            Test-ShouldShowPickerTip -RunCount 0 | Should -BeTrue
        }
    }
}

Describe 'the run counter' {
    InModuleScope TerminalStyles {

        BeforeEach {
            $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("tip-" + [Guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:Sandbox -Force | Out-Null
        }
        AfterEach {
            if (Test-Path -LiteralPath $script:Sandbox) {
                Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'starts at zero and counts up' {
            Get-PickerRunCount -DataDir $script:Sandbox | Should -Be 0
            Add-PickerRun -DataDir $script:Sandbox | Should -Be 1
            Add-PickerRun -DataDir $script:Sandbox | Should -Be 2
            Get-PickerRunCount -DataDir $script:Sandbox | Should -Be 2
        }

        It 'persists across readers' {
            Add-PickerRun -DataDir $script:Sandbox | Out-Null
            Add-PickerRun -DataDir $script:Sandbox | Out-Null
            Add-PickerRun -DataDir $script:Sandbox | Out-Null
            Get-PickerRunCount -DataDir $script:Sandbox | Should -Be 3
            Test-ShouldShowPickerTip -RunCount (Get-PickerRunCount -DataDir $script:Sandbox) | Should -BeTrue
            Add-PickerRun -DataDir $script:Sandbox | Out-Null
            Test-ShouldShowPickerTip -RunCount (Get-PickerRunCount -DataDir $script:Sandbox) | Should -BeFalse
        }

        It 'reads anything it cannot parse as zero' {
            foreach ($junk in 'banana', '', '-4', '3.7', "$([char]0)") {
                [System.IO.File]::WriteAllText((Join-Path $script:Sandbox '.picker-runs'), $junk)
                Get-PickerRunCount -DataDir $script:Sandbox |
                    Should -Be 0 -Because "'$junk' is not a count, and the tip should stay"
            }
        }

        It 'does not take the picker down when it cannot write' {
            # A counter whose only job is to retire a hint must never be the
            # reason the picker fails to open.
            $gone = Join-Path $script:Sandbox 'no/such/dir/at/all'
            Mock -CommandName New-Item -MockWith { throw 'denied' }
            { Add-PickerRun -DataDir $gone } | Should -Not -Throw
            Add-PickerRun -DataDir $gone | Should -Be 1 -Because 'the session still counts as one opening'
        }
    }
}

Describe 'Get-PickerFramePlan' {
    InModuleScope TerminalStyles {

        It 'spends exactly one row on the tip' {
            $with    = Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24 -TipRow $true
            $without = Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24 -TipRow $false
            ($with.ChromeRows - $without.ChromeRows) | Should -Be 1
        }

        It 'gives that row to the list' {
            $with    = Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24 -TipRow $true
            $without = Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24 -TipRow $false
            $with.Count    | Should -Be 13
            $without.Count | Should -Be 14 -Because 'the reclaimed row is one more style, not one more blank'
        }

        It 'still keeps the frame off the window''s last row' {
            foreach ($tip in $true, $false) {
                foreach ($wh in 14, 18, 24, 40) {
                    $p = Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight $wh -TipRow $tip
                    if ($p.Fits) {
                        $p.FrameRows | Should -BeLessThan $wh -Because "tip=$tip in a $wh-row window"
                    }
                }
            }
        }

        It 'costs the same as before for a caller that does not mention the tip' {
            # The parameter defaults to the old behaviour, so every existing
            # caller and test keeps the budget it was written against.
            (Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24).ChromeRows |
                Should -Be (Get-PickerFramePlan -Total 15 -Selected 0 -WindowHeight 24 -TipRow $true).ChromeRows
        }
    }
}

Describe 'the picker actually gates the row' {
    It 'wraps the tip in the gate, and tells the plan about it' {
        # Through the AST, not a string search: the words "Tip: run" and
        # "showPickerTip" both appear in comments around this code, and a
        # grep-shaped test would pass on the comments alone after someone
        # deleted the gate. This repo has already shipped that mistake once.
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'tstyles.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)

        $tipWrite = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Write-Host' -and
            ($n.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
                $_.Value -match "Tip: run"
            })
        }, $true)
        $tipWrite | Should -HaveCount 1 -Because 'there is one tip line'

        $guarded = $false
        $node = $tipWrite[0].Parent
        while ($node) {
            if ($node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -match 'showPickerTip') {
                $guarded = $true; break
            }
            $node = $node.Parent
        }
        $guarded | Should -BeTrue -Because 'an ungated tip is the permanent row this change removes'

        $planCall = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Get-PickerFramePlan'
        }, $true)
        $planCall | Should -Not -BeNullOrEmpty
        ($planCall[0].CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'TipRow'
        }) | Should -Not -BeNullOrEmpty -Because 'a painted row the budget does not know about is what garbles the frame'
    }
}
