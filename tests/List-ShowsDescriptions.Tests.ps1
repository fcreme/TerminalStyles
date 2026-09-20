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
            $out = Get-ListRowDescription -Width 140 -Swatch $script:Swatch -Badge '' `
                        -Description $script:Desc -HintEscape ''
            $out.Trim() | Should -BeLike "*$($script:Desc)*"
        }

        It 'measures the swatch in columns, not characters' {
            # The regression guard. With .Length the swatch alone reads as ~130
            # columns, $room goes negative, and every row loses its description.
            $plain = ' ' * (Get-VisibleLength $script:Swatch)
            $escaped = Get-ListRowDescription -Width 140 -Swatch $script:Swatch -Badge '' `
                        -Description $script:Desc -HintEscape ''
            $bare = Get-ListRowDescription -Width 140 -Swatch $plain -Badge '' `
                        -Description $script:Desc -HintEscape ''
            $escaped | Should -Be $bare
            $escaped | Should -Not -BeNullOrEmpty
        }

        It 'cuts at a sentence rather than mid-word on a narrow window' {
            $out = ((Get-ListRowDescription -Width 80 -Swatch $script:Swatch -Badge '' `
                        -Description $script:Desc -HintEscape '') -replace "$([char]27)\[[0-9;]*m", '').Trim()
            $out | Should -Be 'Warm sepia autumn.'
            $out | Should -Not -Match 'and$'
        }

        It 'gives up rather than printing a fragment' {
            # Four cut-off words read worse than a clean row.
            Get-ListRowDescription -Width 52 -Swatch $script:Swatch -Badge '' `
                -Description $script:Desc -HintEscape '' | Should -Be ''
        }

        It 'counts the badge against the budget too' {
            $badge = '  yours (shadows bundled)'
            $withBadge = Get-ListRowDescription -Width 96 -Swatch $script:Swatch -Badge $badge `
                            -Description $script:Desc -HintEscape ''
            $without = Get-ListRowDescription -Width 96 -Swatch $script:Swatch -Badge '' `
                            -Description $script:Desc -HintEscape ''
            (Get-VisibleLength $withBadge) | Should -BeLessThan (Get-VisibleLength $without)
        }

        It 'says nothing for a style with no description' {
            Get-ListRowDescription -Width 200 -Swatch $script:Swatch -Badge '' `
                -Description '' -HintEscape '' | Should -Be ''
            Get-ListRowDescription -Width 200 -Swatch $script:Swatch -Badge '' `
                -Description $null -HintEscape '' | Should -Be ''
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
            $lines = & {
                $orig = $PSStyle.OutputRendering
                $PSStyle.OutputRendering = 'PlainText'
                try { Show-StyleList 6>&1 | Out-String } finally { $PSStyle.OutputRendering = $orig }
            }
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
        # Sources only: out/ is a staging copy of a previously published
        # version, and tests/ is allowed to name the thing it is guarding.
        $hits = Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1', '*.psm1', '*.md' |
            Where-Object {
                $rel = $_.FullName.Substring($root.Length).TrimStart([char]47, [char]92)
                $rel -notlike 'out*' -and $rel -notlike 'tests*' -and $rel -notlike '.git*'
            } |
            Select-String -SimpleMatch 'wezterm-init'
        $hits | Should -BeNullOrEmpty -Because 'no such subcommand is dispatched'
    }
}
