# Pester 5 tests for Get-PickerViewport -- which slice of the style list the
# picker draws.
#
# The bug it fixes: the picker redraws by parking the cursor at a fixed row and
# overwriting in place, which only works while the whole frame fits below that
# row. Draw more rows than the terminal has and it scrolls; the saved home row
# then no longer points at the top of the menu, and every later redraw lands in
# the wrong place and garbles the screen.
#
# It was already close. With 17 styles the frame is 23 rows, and a stock
# Terminal.app window is 24 -- two more user styles and it breaks.
#
# The arithmetic is a pure function precisely so it can be tested without a
# terminal, the same reasoning that carved out Invoke-StylePickerLoop.
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

Describe 'Get-PickerViewport' {
    InModuleScope TerminalStyles {

        It 'shows everything when it all fits' {
            $v = Get-PickerViewport -Total 5 -Selected 2 -Available 40
            $v.First | Should -Be 0
            $v.Count | Should -Be 5
            $v.More  | Should -BeFalse
        }

        It 'never draws more rows than the window has' {
            # This is the whole point: one row too many and the frame scrolls,
            # which invalidates the fixed home row every redraw depends on.
            foreach ($avail in 1..25) {
                $v = Get-PickerViewport -Total 40 -Selected 20 -Available $avail
                $v.Count | Should -BeLessOrEqual $avail -Because "window is $avail rows"
            }
        }

        It 'keeps the selection inside the visible slice' {
            # Arrowing to a style you cannot see would be worse than the garbling.
            foreach ($sel in 0..39) {
                $v = Get-PickerViewport -Total 40 -Selected $sel -Available 9
                $sel | Should -BeGreaterOrEqual $v.First
                $sel | Should -BeLessThan ($v.First + $v.Count)
            }
        }

        It 'clamps at the top rather than showing negative indices' {
            $v = Get-PickerViewport -Total 17 -Selected 0 -Available 10
            $v.First | Should -Be 0
            $v.Count | Should -Be 10
        }

        It 'clamps at the bottom rather than running past the end' {
            $v = Get-PickerViewport -Total 17 -Selected 16 -Available 10
            $v.First | Should -Be 7
            ($v.First + $v.Count) | Should -Be 17
        }

        It 'centres the selection in the middle of a long list' {
            $v = Get-PickerViewport -Total 17 -Selected 8 -Available 10
            $v.First | Should -Be 3
            $v.Count | Should -Be 10
        }

        It 'always offers at least one row, however short the window' {
            # A picker showing nothing is worse than one showing a single entry,
            # and Available can go non-positive once the chrome is subtracted
            # from a very short terminal.
            foreach ($avail in -5, 0, 1) {
                $v = Get-PickerViewport -Total 17 -Selected 3 -Available $avail
                $v.Count | Should -Be 1
                $v.First | Should -Be 3
            }
        }

        It 'reports More only when something is actually hidden' {
            (Get-PickerViewport -Total 5  -Selected 0 -Available 10).More | Should -BeFalse
            (Get-PickerViewport -Total 5  -Selected 0 -Available 5 ).More | Should -BeFalse
            (Get-PickerViewport -Total 17 -Selected 0 -Available 10).More | Should -BeTrue
        }

        It 'handles an empty style list without throwing' {
            $v = Get-PickerViewport -Total 0 -Selected 0 -Available 10
            $v.Count | Should -Be 0
            $v.More  | Should -BeFalse
        }

        It 'never returns a slice that runs off either end' {
            foreach ($total in 1, 2, 17, 40) {
                foreach ($avail in 1, 3, 10, 50) {
                    foreach ($sel in 0, [int]($total / 2), ($total - 1)) {
                        $v = Get-PickerViewport -Total $total -Selected $sel -Available $avail
                        $v.First | Should -BeGreaterOrEqual 0
                        ($v.First + $v.Count) | Should -BeLessOrEqual $total
                    }
                }
            }
        }
    }
}

Describe 'the picker frame keeps a constant height' {
    InModuleScope TerminalStyles {

        It 'emits both scroll indicators unconditionally' {
            # The frame is overwritten in place rather than cleared, so its row
            # count has to be identical on every redraw. An indicator row that
            # appeared and disappeared would strand the taller frame's last line
            # on screen -- which is the same class of bug as the one the
            # viewport fixes.
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $draw = [regex]::Match($src, '(?s)\$drawMenu = \{.*?\n        \}').Value
            $draw | Should -Match 'more above'
            $draw | Should -Match 'more below'
            # Each indicator has an else-branch that writes a blank line.
            ([regex]::Matches($draw, '\} else \{\s*\n\s*Write-Host ""')).Count |
                Should -BeGreaterOrEqual 2
        }

        It 'asks the viewport how much room it has' {
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match 'Get-PickerViewport -Total \$styles\.Count'
            $src | Should -Match 'WindowHeight'
        }

        It 'falls back to the full list when the window height is unavailable' {
            # [Console]::WindowHeight throws with no console attached, and --
            # verified under a pty whose size was never set -- returns 0 rather
            # than throwing in other cases. Subtracting the chrome from 0 would
            # collapse the menu to one row, which is worse than the unbounded
            # frame the viewport exists to prevent. Both cases must fall back to
            # drawing everything.
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match '\$available = \$styles\.Count'
            $src | Should -Match 'if \(\$wh -gt 0\)'
        }

        It 'treats a zero window height as unknown, not as no room' {
            # The distinction that matters: Get-PickerViewport clamps a genuinely
            # tiny window to one row on purpose, so the caller must never hand it
            # a 0 that really meant "unmeasured".
            (Get-PickerViewport -Total 17 -Selected 3 -Available 0).Count | Should -Be 1
            (Get-PickerViewport -Total 17 -Selected 3 -Available 17).Count | Should -Be 17
        }
    }
}
