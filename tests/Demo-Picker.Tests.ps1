# The README shows fifteen GIFs of what the styles LOOK like. It has never
# shown what the tool DOES -- the terminal repainting as you arrow down the
# list -- which is the one thing a screenshot cannot convey.
#
# scripts/demo-picker.ps1 drives the real picker through a scripted tour so
# that recording is one clean take instead of a dozen attempts at typing at the
# right speed. What is tested here is the tour arithmetic: where the highlight
# goes and how long it rests. The spawning and key-sending half lives in the
# driver and is deliberately not exercised -- a test must not open a window.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # demo-lib.ps1 defines and runs nothing, which is why it can be read here
    # at all. Dot-sourcing the driver would start a demo.
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/demo-lib.ps1')
    $script:Styles = @('alpha', 'bravo', 'charlie', 'delta', 'echo')
}

Describe 'Get-TourPlan' {

    It 'sweeps downward with no backtracking' {
        # A named tour zig-zags, and on screen that reads as indecision. It also
        # tripled the length of the first recording: 38 presses for 15 styles.
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('echo')
        @($plan).Count | Should -Be 4
        @($plan | Where-Object { $_.Key -ne 'Down' }) | Should -BeNullOrEmpty
    }

    It 'previews every style exactly once on a sweep' {
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('echo')
        $seen = @($plan | ForEach-Object { $_.Label })
        $seen | Should -Be @('bravo', 'charlie', 'delta', 'echo')
        ($seen | Select-Object -Unique).Count | Should -Be $seen.Count
    }

    It 'gives every style on the way the same beat' {
        # Racing past the intermediate styles to reach a named destination is
        # what makes a tour look hurried -- and those styles are previewing
        # too, which is the whole thing being demonstrated.
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('echo') -DwellMs 650
        $beats = @($plan[0..($plan.Count - 2)] | ForEach-Object { $_.PauseMs })
        ($beats | Select-Object -Unique) | Should -Be 650
    }

    It 'rests longer on the style Enter lands on' {
        # So the last frame of the recording is the chosen style, not a blur of
        # the key press.
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('echo') `
                    -DwellMs 650 -SettleMs 1600
        $plan[-1].PauseMs | Should -Be 1600
        $plan[-1].Label   | Should -Be 'echo'
    }

    It 'walks upward when the tour goes back up the list' {
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'echo' -Tour @('bravo')
        @($plan | ForEach-Object { $_.Key } | Select-Object -Unique) | Should -Be 'Up'
        $plan[-1].Label | Should -Be 'bravo'
    }

    It 'follows a multi-stop tour in the order given' {
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('charlie', 'bravo', 'echo')
        $plan[-1].Label | Should -Be 'echo'
        @($plan | ForEach-Object { $_.Label }) |
            Should -Be @('bravo', 'charlie', 'bravo', 'charlie', 'delta', 'echo')
    }

    It 'opens at the top when nothing is active' {
        # No active style means the picker highlights the first entry, so the
        # plan has to count from there or every arrow after it is off by one.
        $plan = Get-TourPlan -Styles $script:Styles -StartStyle '' -Tour @('charlie')
        @($plan).Count | Should -Be 2
        $plan[-1].Label | Should -Be 'charlie'
    }

    It 'names the style it cannot find, and what it could have picked' {
        # A tour naming a style that is not there would otherwise send arrows
        # into the list until it fell off the end, and land somewhere the
        # recording did not intend.
        { Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('nope') } |
            Should -Throw -ExpectedMessage "*nope*"
        { Get-TourPlan -Styles $script:Styles -StartStyle 'alpha' -Tour @('nope') } |
            Should -Throw -ExpectedMessage "*charlie*"
    }

    It 'asks for nothing when it is already there' {
        Get-TourPlan -Styles $script:Styles -StartStyle 'delta' -Tour @('delta') |
            Should -BeNullOrEmpty
    }
}

Describe 'the demo driver' {

    It 'reads its style list from the picker''s own reader' {
        # Get-AvailableStyles admits a folder on scheme.json EXISTING; the
        # picker drops the ones that will not parse. A list built the other way
        # is off by one for every arrow after a broken folder, and the tour
        # lands somewhere other than where it said.
        $src = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/demo-picker.ps1') -Raw
        $src | Should -Match 'Get-PickerStyleSet'
    }

    It 'waits for the picker rather than sleeping and hoping' {
        $src = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/demo-picker.ps1') -Raw
        $src | Should -Match 'Choose a style for'
        $src | Should -Match 'get-text'
    }

    It 'does not run anything when dot-sourced for its functions' {
        # demo-lib.ps1 is the half a test can read. If it ever grows a line
        # that executes, this file starts a demo on every suite run.
        $lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/demo-lib.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($lib, [ref]$null, [ref]$null)
        $top = @($ast.EndBlock.Statements | Where-Object {
            $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst]
        })
        $top | Should -BeNullOrEmpty -Because 'this file may define, and must not do'
    }
}
