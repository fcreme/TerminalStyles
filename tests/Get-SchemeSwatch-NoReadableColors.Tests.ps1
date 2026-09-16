# Pester 5 tests: what the listings say about a style whose colour values this
# tool cannot read.
#
# THE DEFECT. Get-SchemeSwatch renders a cell per readable hex value and nothing
# else, so a scheme written with X11 colour words ("black"), `rgb()` calls or a
# typo produced a bare four-byte reset. Every reader printed that beside the
# style's name: `tstyles list` drew the name and then whitespace, and the picker
# drew a row with an empty colour column -- while APPLYING the very same style
# says, in as many words, "this style defines no colors this tool can read,
# so the terminal was not asked to change any" (0.8.27). One input, two answers.
#
# The picker half matters twice over: such a style PARSES, so Get-PickerStyleSet
# keeps it and does not list it under Unreadable. It is offered, selectable and
# appliable, and its row was the one row in the menu that said nothing at all
# about itself.
#
# `tstyles current` is the third reader and shares the same call, but its swatch
# branch runs only when stdout is NOT redirected -- under Pester it always is,
# and it prints the bare name by design -- so it cannot be driven from here.
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

Describe 'a style whose colour values cannot be read' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            # Both roots into $TestDrive: Get-AvailableStyles, Get-StyleDir and
            # Get-InstalledStyleClaim all derive from them, and nothing here may
            # read or write the real install.
            $script:TStylesModuleRoot = Join-Path $TestDrive ('mod-'  + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesDataRoot   = Join-Path $TestDrive ('data-' + [guid]::NewGuid().Guid.Substring(0, 8))

            $script:wordsDir = Join-Path $script:TStylesModuleRoot 'styles/words'
            New-Item -ItemType Directory -Path $script:wordsDir -Force | Out-Null
            # Every value a terminal would understand and this tool would not.
            [System.IO.File]::WriteAllText((Join-Path $script:wordsDir 'scheme.json'),
                '{"name":"words","background":"black","foreground":"rgb(255,0,0)","cursorColor":"blue"}',
                $script:enc)

            $script:readableDir = Join-Path $script:TStylesModuleRoot 'styles/readable'
            New-Item -ItemType Directory -Path $script:readableDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:readableDir 'scheme.json'),
                '{"name":"readable","background":"#101010","foreground":"#f0f0f0","cursorColor":"#ff0000"}',
                $script:enc)

            $script:words = [pscustomobject]@{
                name = 'words'; background = 'black'; foreground = 'rgb(255,0,0)'; cursorColor = 'blue'
            }
        }

        It 'is a style the apply path names rather than paints (the premise)' {
            # Without this the cases below could pass against a fixture that was
            # merely mis-shaped, rather than against the one the apply path has
            # a sentence for.
            Get-SchemeOscPacket -Scheme $script:words | Should -BeNullOrEmpty
            Get-SchemeSwatch    -Scheme $script:words |
                Should -Not -Match '\[48;2;' -Because 'no value in it can become a cell'
        }

        It 'tstyles list says so where the colours would be' {
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentStyleName { $null }

            $out = Show-StyleList 6>&1 | Out-String -Width 500

            $out | Should -Match 'words' -Because 'the row must still be listed'
            $out | Should -Match '(?i)no colors this tool can read' `
                -Because 'a name followed by whitespace is the listing refusing to answer'
            # Control in the same output: a readable style keeps its cells and
            # gets no note. Counted rather than matched on the escape bytes --
            # PowerShell strips ANSI from a captured information stream, so
            # `[48;2;` is simply not in $out however the row was drawn. That the
            # readable style DOES render cells is asserted on the live string in
            # the last case below, and per bundled theme in
            # tests/Get-SchemeSwatch.Tests.ps1.
            $out | Should -Match 'readable'
            ([regex]::Matches($out, '(?i)no colors this tool can read')).Count | Should -Be 1 `
                -Because 'only the style that has none gets told it has none'
        }

        It 'the picker draws the same note on the row it keeps' {
            $set = Get-PickerStyleSet -Styles @(Get-Item -LiteralPath $script:wordsDir -Force)

            @($set.Styles | ForEach-Object { $_.Name }) | Should -Contain 'words' `
                -Because 'the scheme parses, so the picker keeps it and will apply it'
            @($set.Unreadable | ForEach-Object { $_ }).Count | Should -Be 0 `
                -Because 'it is not an unreadable FILE, which is the other message'
            $set.Swatches[0] | Should -Match '(?i)no colors this tool can read'
        }

        It 'leaves a readable style with its cells and no note' {
            $set = Get-PickerStyleSet -Styles @(Get-Item -LiteralPath $script:readableDir -Force)
            $set.Swatches[0] | Should -Match '\[48;2;'
            $set.Swatches[0] | Should -Not -Match '(?i)no colors'
        }
    }
}
