# `tstyles font` listed six names and their licences, and then asked you to
# type one back exactly -- in a tool that had already taught you to arrow
# through styles with a live preview. Two vocabularies for the same act of
# choosing, and the list told you nothing about what you were choosing between:
# a licence is not what anybody picks a typeface on.
#
# The descriptions are measured, not recalled. Ligatures are the GSUB 'calt'
# feature; the zero's mark is the third contour of its glyph (roughly square and
# small is a dot, tall and narrow is a slash); x-height is OS/2 sxHeight over
# unitsPerEm. All six of these fonts mark their zero, which is the differentiator
# a guess would have got wrong.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# InModuleScope resolves the module at DISCOVERY, so importing only in
# BeforeAll fails the container before a single test runs.
BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'the font catalog' {
    InModuleScope TerminalStyles {

        It 'says what every font is' {
            $missing = @(Get-FontCatalog) | Where-Object { -not $_.description }
            $missing | Should -BeNullOrEmpty -Because 'a name and a licence are not a choice'
        }

        It 'keeps each description inside an 80-column window' {
            # The frame trims to Width - 4 and cuts at a SENTENCE, so a
            # description one character too long loses its whole second
            # sentence rather than a word -- and the second sentence is the
            # half that says what the font is like. Two of these were 76 and 79
            # and came out as "Ligatures, dotted zero." on an 80-column window.
            foreach ($f in @(Get-FontCatalog)) {
                $f.description.Length | Should -BeLessOrEqual 72 -Because "$($f.name) has to survive 80 columns whole"
            }
        }

        It 'describes rather than repeats the name' {
            foreach ($f in @(Get-FontCatalog)) {
                $f.description | Should -Not -BeLike "*$($f.name)*"
            }
        }
    }
}

Describe 'Get-FontPickerFooter' {
    InModuleScope TerminalStyles {

        It 'is always two lines, whichever terminal is asking' {
            # The frame is overwritten in place, so a footer that was two rows
            # for one terminal and one for another would strand a row on screen.
            foreach ($owner in 'command', 'style', 'terminal') {
                @(Get-FontPickerFooter -Owner $owner -TerminalName 'X').Count |
                    Should -Be 2 -Because "the $owner footer has to be the same height as the others"
            }
        }

        It 'promises to apply the font only where that is true' {
            # "Install + apply" is a promise only Windows Terminal keeps. The
            # list footer had to be fixed for saying it everywhere; this sits
            # directly above the key that is meant to do it.
            $wt = (Get-FontPickerFooter -Owner 'command'  -TerminalName 'Windows Terminal') -join ' '
            $wz = (Get-FontPickerFooter -Owner 'style'    -TerminalName 'WezTerm') -join ' '
            $tt = (Get-FontPickerFooter -Owner 'terminal' -TerminalName 'Terminal.app') -join ' '

            # The load-bearing half is the NEGATIVE. An earlier version of this
            # test only checked that each footer mentioned its own subject, and
            # a footer rewritten to say "Enter installs it and sets it as
            # Terminal.app's font" still passed -- it kept the words "own
            # settings" further along the line. The claim that matters is who
            # says ENTER sets the font, and only Windows Terminal may.
            $wt | Should -Match 'installs it and sets'
            $wz | Should -Not -Match 'installs it and sets'
            $tt | Should -Not -Match 'installs it and sets'

            # And each still has to say the thing that is true for it. "The
            # applied style sets WezTerm's font" is a claim about the style, not
            # about Enter, which is why it is allowed here and nowhere else.
            $wz | Should -Match 'applied style sets'
            $wz | Should -Not -Match 'own settings'
            $tt | Should -Match 'own settings'
            $tt | Should -Not -Match 'applied style'
        }

        It 'names the terminal it is talking about' {
            foreach ($owner in 'command', 'style', 'terminal') {
                ((Get-FontPickerFooter -Owner $owner -TerminalName 'Ghostty') -join ' ') |
                    Should -Match 'Ghostty'
            }
        }
    }
}

Describe 'Get-FontPickerFrame' {
    InModuleScope TerminalStyles {

        BeforeAll { $script:Cat = @(Get-FontCatalog) }

        It 'is the same height wherever the highlight sits' {
            # THE bug class for an in-place redraw. A frame one row taller for
            # one font strands the previous frame's last line and smears from
            # there until the picker exits.
            foreach ($wh in 16, 20, 24, 40) {
                $heights = 0..($script:Cat.Count - 1) | ForEach-Object {
                    (Get-FontPickerFrame -Catalog $script:Cat -Index $_ -WindowHeight $wh -Width 80).Count
                }
                ($heights | Select-Object -Unique).Count | Should -Be 1 -Because "height $wh must not depend on the highlight"
            }
        }

        It 'never paints the window''s last row' {
            # The newline ending that row scrolls the buffer, which moves the
            # frame out from under the fixed origin every later redraw uses.
            foreach ($wh in 16, 18, 20, 24, 40) {
                $rows = (Get-FontPickerFrame -Catalog $script:Cat -Index 0 -WindowHeight $wh -Width 80).Count
                $rows | Should -BeLessThan $wh -Because "a $wh-row window cannot hold a $rows-row frame"
            }
        }

        It 'keeps the cursor and the install state as separate marks' {
            # '>' is where the cursor is; '[+]' is what is on this machine.
            # They are unrelated facts and one mark cannot carry both.
            $f = Get-FontPickerFrame -Catalog $script:Cat -Installed @($script:Cat[3].family) `
                    -Index 0 -WindowHeight 24 -Width 80
            $rows = $f | Where-Object { $_ -match '\[[+ ]\]' }
            ($rows | Where-Object { $_ -match '^\s*>' }) | Should -HaveCount 1
            $cursorRow = $rows | Where-Object { $_ -match '^\s*>' }
            $cursorRow | Should -Match ([regex]::Escape($script:Cat[0].name))
            $cursorRow | Should -Match '\[ \]' -Because 'the highlighted font is not the installed one here'
            ($rows | Where-Object { $_ -match '\[\+\]' }) | Should -HaveCount 1
        }

        It 'shows the highlighted font''s description whole at 80 columns' {
            for ($i = 0; $i -lt $script:Cat.Count; $i++) {
                $f = (Get-FontPickerFrame -Catalog $script:Cat -Index $i -WindowHeight 24 -Width 80) -join "`n"
                $f | Should -Match ([regex]::Escape($script:Cat[$i].description))
            }
        }

        It 'reports the install state of the highlighted font' {
            $inst = (Get-FontPickerFrame -Catalog $script:Cat -Installed @($script:Cat[0].family) `
                        -Index 0 -WindowHeight 24 -Width 80) -join "`n"
            $not  = (Get-FontPickerFrame -Catalog $script:Cat -Installed @() `
                        -Index 0 -WindowHeight 24 -Width 80) -join "`n"
            $inst | Should -Match 'installed'
            $not  | Should -Match 'not installed'
        }
    }
}

Describe 'Invoke-FontPicker' {
    InModuleScope TerminalStyles {

        BeforeAll {
            $script:Cat = @(Get-FontCatalog)
            function script:NewKeys([string[]]$names) {
                $q = [System.Collections.Queue]::new()
                foreach ($n in $names) { $q.Enqueue([pscustomobject]@{ Key = $n }) }
                { if ($q.Count) { $q.Dequeue() } else { $null } }.GetNewClosure()
            }
        }

        It 'returns the font the arrows landed on' {
            $r = Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                    -ReadKey (NewKeys 'DownArrow', 'DownArrow', 'Enter') -Write { }
            $r.Outcome | Should -Be 'confirmed'
            $r.Index   | Should -Be 2
            $r.Font.name | Should -Be $script:Cat[2].name
        }

        It 'returns nothing to install when cancelled' {
            $r = Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                    -ReadKey (NewKeys 'DownArrow', 'Escape') -Write { }
            $r.Outcome | Should -Be 'cancelled'
            $r.Font    | Should -BeNullOrEmpty -Because 'Esc must not install anything'
        }

        It 'clears the screen once, not on every keystroke' {
            # GetNewClosure captures by VALUE, so a [bool] flag assigned inside
            # the draw block wrote a local and never survived to the next key --
            # the picker still worked and flickered the whole screen on every
            # arrow, which is the exact thing drawing in place exists to avoid.
            Mock -CommandName Clear-Host -MockWith { }
            Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                -ReadKey (NewKeys 'DownArrow', 'DownArrow', 'DownArrow', 'Enter') -Write { } | Out-Null
            Should -Invoke Clear-Host -Times 1 -Exactly
        }

        It 'survives a console that cannot be cleared' {
            # Clear-Host sets the cursor position on Windows, so with no console
            # handle it throws "The handle is invalid" -- which took the picker
            # down on both Windows CI jobs while every Unix one passed. A picker
            # that cannot clear the screen should still draw on it.
            Mock -CommandName Clear-Host -MockWith { throw [System.IO.IOException]::new('The handle is invalid.') }
            $painted = [System.Collections.Generic.List[string]]::new()
            $r = Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                    -ReadKey (NewKeys 'DownArrow', 'Enter') -Write { param($l) $painted.Add($l) }
            $r.Outcome | Should -Be 'confirmed'
            $painted.Count | Should -BeGreaterThan 0 -Because 'the frame still has to be painted'
        }

        It 'does not retry a clear that threw' {
            # Once per picker, not once per keystroke: a console that cannot be
            # cleared cannot be cleared the second time either.
            Mock -CommandName Clear-Host -MockWith { throw [System.IO.IOException]::new('The handle is invalid.') }
            Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                -ReadKey (NewKeys 'DownArrow', 'DownArrow', 'Enter') -Write { } | Out-Null
            Should -Invoke Clear-Host -Times 1 -Exactly
        }

        It 'repaints for every arrow' {
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-FontPicker -Catalog $script:Cat -Installed @() `
                -ReadKey (NewKeys 'DownArrow', 'DownArrow', 'Enter') `
                -Write { param($l) $painted.Add($l) } | Out-Null
            # Three frames: the first draw, and one per arrow.
            $cursorRows = @($painted | Where-Object { $_ -match '^\S*\s*>' })
            $cursorRows.Count | Should -Be 3
        }
    }
}

Describe 'tstyles font with no argument' {
    InModuleScope TerminalStyles {

        It 'lists rather than blocking where no one can press a key' {
            # A redirected run, a script, a CI runner: the picker would wait
            # forever on a keystroke nobody can send.
            Mock -CommandName Test-InteractiveConsole -MockWith { $false }
            Mock -CommandName Show-FontList -MockWith { }
            Mock -CommandName Invoke-FontPicker -MockWith { }
            Invoke-TerminalStyleFont
            Should -Invoke Show-FontList -Times 1
            Should -Invoke Invoke-FontPicker -Times 0
        }

        It 'picks where someone can' {
            Mock -CommandName Test-InteractiveConsole -MockWith { $true }
            Mock -CommandName Show-FontList -MockWith { }
            Mock -CommandName Clear-Host -MockWith { }
            Mock -CommandName Invoke-FontPicker -MockWith { @{ Outcome = 'cancelled'; Font = $null } }
            Invoke-TerminalStyleFont
            Should -Invoke Invoke-FontPicker -Times 1
            Should -Invoke Show-FontList -Times 0
        }
    }
}
