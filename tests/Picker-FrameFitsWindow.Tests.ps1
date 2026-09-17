# The picker redraws by parking the cursor at a row it captured ONCE and
# overwriting in place. That only holds while the whole frame fits below that
# row: paint more rows than the window has and the buffer scrolls, the saved row
# no longer points at the top of the menu, and every later redraw lands in the
# wrong place.
#
# The frame used to be budgeted at exactly WindowHeight rows, so the newline
# ending its last line did the scrolling itself. Reported from a real WezTerm
# window with 17 styles -- the header repeating down the screen, and short rows
# wearing the tails of longer ones:
#   "Choose a style for WezTermto keep, Esc to cancel"
#   "     eva                                        el"
#
# Driven through Get-PickerFramePlan, which is the function the picker itself
# calls -- this file carries no copy of the arithmetic, or it could agree with
# itself while the picker was wrong.
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

Describe 'the picker frame never fills the window' {
    InModuleScope TerminalStyles {

        It 'holds a row back for every window height, style count and note count' {
            $checked = 0
            foreach ($total in 1, 5, 16, 17, 40, 120) {
                foreach ($notes in 0, 1, 2, 3) {
                    foreach ($wh in 14..60) {
                        $plan = Get-PickerFramePlan -Total $total -Selected ([int]($total / 2)) `
                                    -WindowHeight $wh -NoteCount $notes
                        $plan.FrameRows | Should -BeLessThan $wh -Because (
                            "a frame of $($plan.FrameRows) rows in a $wh-row window scrolls the " +
                            "buffer, and the picker's origin is a row it captured once " +
                            "(total=$total notes=$notes)")
                        $plan.Fits | Should -BeTrue
                        $checked++
                    }
                }
            }
            $checked | Should -BeGreaterThan 500 -Because 'a loop that never ran would pass silently'
        }

        It 'reports Fits false rather than lying when the chrome alone will not fit' {
            # A window shorter than the chrome scrolls whatever we do. The menu
            # still draws -- one row beats none -- but the caller is told, so it
            # reclaims the screen instead of painting at an invalidated origin.
            $plan = Get-PickerFramePlan -Total 17 -Selected 0 -WindowHeight 9 -NoteCount 3
            $plan.Count     | Should -BeGreaterThan 0 -Because 'a picker showing nothing is worse'
            $plan.FrameRows | Should -BeGreaterOrEqual 9
            $plan.Fits      | Should -BeFalse
        }

        It 'draws everything when the window height is unknown' {
            # 0 means "I don't know", not "no room" -- it reads as 0 under a pty
            # whose size was never set. Budgeting from it would collapse the menu.
            foreach ($wh in 0, -1) {
                $plan = Get-PickerFramePlan -Total 17 -Selected 3 -WindowHeight $wh
                $plan.Count | Should -Be 17 -Because 'the old unbounded behaviour is the safe fallback'
                $plan.Fits  | Should -BeTrue -Because 'there is no height to be too tall for'
            }
        }

        It 'counts the chrome the frame really paints' {
            # Leading blank, header, two hints, the blank under them, two
            # always-present scroll indicators, trailing blank -- and one row per
            # optional note. If $drawMenu gains or loses a row, this is the number
            # that has to move with it.
            (Get-PickerFramePlan -Total 5 -Selected 0 -WindowHeight 40).ChromeRows |
                Should -Be 8
            foreach ($n in 1, 2, 3) {
                (Get-PickerFramePlan -Total 5 -Selected 0 -WindowHeight 40 -NoteCount $n).ChromeRows |
                    Should -Be (8 + $n)
            }
        }

        It 'keeps the selected style inside the slice it hands back' {
            # The reason a viewport exists at all: arrowing past the edge has to
            # move the window, not walk the cursor off it.
            foreach ($sel in 0, 8, 16) {
                $plan = Get-PickerFramePlan -Total 17 -Selected $sel -WindowHeight 20 -NoteCount 1
                $sel | Should -BeGreaterOrEqual $plan.First
                $sel | Should -BeLessThan ($plan.First + $plan.Count)
            }
        }
    }
}
