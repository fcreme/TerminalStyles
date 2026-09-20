# `tstyles list` printed a style's name, its colours, and whether it was yours.
# It did not print what the style IS -- the one thing a reader scanning the
# list is choosing between. The descriptions already existed, in each style's
# own meta.json, and the picker already read them; only the listing did not.
#
# The fitting is where this can go wrong quietly. A swatch is five colour cells
# whose bytes are almost all SGR escapes, so measuring it with .Length says 130
# columns on something 25 wide, leaves no room, and drops every description
# without failing anything.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# InModuleScope resolves the module at DISCOVERY, so importing only in
# BeforeAll fails the whole container before a single test runs.
BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Get-VisibleLength' {
    InModuleScope TerminalStyles {

        It 'counts columns, not bytes' {
            # The exact shape Get-SchemeSwatchOrNote emits: a background colour,
            # four spaces, a reset. 130-odd characters, five columns wide.
            $cell = "$([char]27)[48;2;10;0;6m    $([char]27)[49m"
            $cell.Length | Should -BeGreaterThan 20 -Because 'the raw string is mostly escape bytes'
            Get-VisibleLength $cell | Should -Be 4
        }

        It 'leaves plain text alone' {
            Get-VisibleLength 'umbrella' | Should -Be 8
        }

        It 'answers zero for nothing rather than throwing' {
            Get-VisibleLength $null | Should -Be 0
            Get-VisibleLength '' | Should -Be 0
        }
    }
}

Describe 'Get-ConsoleWidth' {
    InModuleScope TerminalStyles {

        It 'never answers zero' {
            # [Console]::WindowWidth is 0 or throws when output is redirected and
            # on a CI runner with no tty. Passing that straight through means "no
            # room for anything", which drops content exactly where nobody is
            # watching -- so the listing looks right locally and ships empty.
            Get-ConsoleWidth | Should -BeGreaterThan 20
        }

        It 'uses the fallback when the console cannot say' {
            Mock -CommandName Get-ConsoleWidth -MockWith { 100 }
            Get-ConsoleWidth | Should -Be 100
        }
    }
}

Describe 'Get-ListRowDescription' {
    InModuleScope TerminalStyles {

        BeforeAll {
            # 25 visible columns of swatch, ~130 characters of string.
            $script:Swatch = (1..5 | ForEach-Object {
                "$([char]27)[48;2;10;0;6m    $([char]27)[49m "
            }) -join ''
            $script:Desc = 'Warm sepia autumn. Amber and gold.'
        }

        It 'prints the whole description when the window has room' {
            $out = Get-ListRowDescription -Width 140 -Used (Get-VisibleLength $script:Swatch) `
                        -Description $script:Desc -HintEscape ''
            $out.Trim() | Should -BeLike "*$($script:Desc)*"
        }

        It 'measures the swatch in columns, not characters' {
            # The regression guard. With .Length the swatch alone reads as ~130
            # columns, $room goes negative, and every row loses its description.
            $plain = ' ' * (Get-VisibleLength $script:Swatch)
            $escaped = Get-ListRowDescription -Width 140 -Used (Get-VisibleLength $script:Swatch) `
                        -Description $script:Desc -HintEscape ''
            $bare = Get-ListRowDescription -Width 140 -Used $plain.Length `
                        -Description $script:Desc -HintEscape ''
            $escaped | Should -Be $bare
            $escaped | Should -Not -BeNullOrEmpty
        }

        It 'cuts at a sentence rather than mid-word on a narrow window' {
            $out = ((Get-ListRowDescription -Width 80 -Used (22 + (Get-VisibleLength $script:Swatch)) `
                        -Description $script:Desc -HintEscape '') -replace "$([char]27)\[[0-9;]*m", '').Trim()
            $out | Should -Be 'Warm sepia autumn.'
            $out | Should -Not -Match 'and$'
        }

        It 'gives up rather than printing a fragment' {
            # Four cut-off words read worse than a clean row.
            Get-ListRowDescription -Width 52 -Used (22 + (Get-VisibleLength $script:Swatch)) `
                -Description $script:Desc -HintEscape '' | Should -Be ''
        }

        It 'counts the badge against the budget too' {
            $base  = 22 + (Get-VisibleLength $script:Swatch)
            $badge = '  yours (shadows bundled)'
            $withBadge = Get-ListRowDescription -Width 96 -Used ($base + $badge.Length) `
                            -Description $script:Desc -HintEscape ''
            $without = Get-ListRowDescription -Width 96 -Used $base `
                            -Description $script:Desc -HintEscape ''
            (Get-VisibleLength $withBadge) | Should -BeLessThan (Get-VisibleLength $without)
        }

        It 'says nothing for a style with no description' {
            Get-ListRowDescription -Width 200 -Used 22 -Description '' -HintEscape '' | Should -Be ''
            Get-ListRowDescription -Width 200 -Used 22 -Description $null -HintEscape '' | Should -Be ''
        }
    }
}

Describe 'Show-StyleList' {
    InModuleScope TerminalStyles {

        It 'actually prints them' {
            # The helper being right is not the feature. This repo's recurring
            # defect is a correct function nothing calls: before this change
            # Get-StyleMeta was referenced zero times in the whole of the
            # listing, while the picker had been reading it for weeks.
            Mock -CommandName Show-UpdateNoticeIfAvailable -MockWith { }
            Mock -CommandName Get-ConsoleWidth -MockWith { 200 }
            # Strip the escapes out of the captured text rather than asking the
            # engine not to emit them: $PSStyle is PowerShell 7 only, and
            # reaching for it here failed the 5.1 job on scaffolding, not on
            # the feature. What is asserted below is text, so the colour is
            # irrelevant either way.
            $lines = (Show-StyleList 6>&1 | Out-String) -replace "$([char]27)\[[0-9;]*[A-Za-z]", ''
            $lines | Should -Match 'umbrella'
            $lines | Should -Match 'Resident-Evil survival horror'
        }
    }
}

Describe 'the comments name commands that exist' {
    It 'does not point at a wezterm-init subcommand' {
        # lib/wezterm.ps1 said the wiring line was "printed in full by
        # wezterm-init". There is no wezterm-init and there never was.
        $root = Split-Path $PSScriptRoot -Parent
        # Markdown is in scope deliberately: a README telling someone to run
        # this is the same defect as a comment claiming it exists.
        #
        # Three exclusions, each for a different reason. out/ is a staging copy
        # of an already-published version, so it records what WAS shipped and
        # cannot be edited into truth. tests/ has to name the thing it guards.
        # And CHANGELOG.md exists precisely to record what the code used to
        # say -- an entry that cannot name the wrong name says nothing.
        # Matched on the extension itself, not through -Include: on Windows
        # that wildcard also picked up TerminalStyles.psd1, whose release notes
        # describe this very fix. Unix runners matched only what was asked for,
        # so the hole was invisible until the Windows jobs ran.
        $hits = Get-ChildItem -LiteralPath $root -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.md' } |
            Where-Object {
                $rel = $_.FullName.Substring($root.Length).TrimStart([char]47, [char]92)
                $rel -notlike 'out*' -and $rel -notlike 'tests*' -and $rel -notlike '.git*' -and
                $rel -ne 'CHANGELOG.md'
            } |
            Select-String -SimpleMatch 'wezterm-init'
        $hits | Should -BeNullOrEmpty -Because 'no such subcommand is dispatched'
    }
}
