# Pester 5 tests: what the picker tells the user about what this terminal
# cannot show -- and that it says the same thing `tstyles <name>` says.
#
# Two defects, one subject.
#
# 1. The capability notice was printed ABOVE the menu, and the picker's own
#    Clear-Host wiped it. pwsh emits Clear-Host as ESC[3J ESC[H ESC[2J, and
#    ESC[3J erases the SCROLLBACK, so the line was not scrolled off, it was
#    unrecoverable. Measured on a pty: the note at byte 283, the first ESC[3J
#    410 bytes later, one uninterrupted burst with no input wait, and the string
#    never appearing again in the capture. tstyles.ps1 had already learned this
#    three times -- $unreadableNote, $backupNote and the update notice each
#    carry a comment saying anything printed above the menu is wiped unread.
#
# 2. The confirm block said nothing about capabilities at all. On iTerm2,
#    `tstyles eva` printed "iTerm2 can't show: tab color." and the picker
#    printed only "Style applied: eva" -- two doors onto the same apply,
#    disagreeing about what the user is going to see.
#
# Both are decided in pure functions here so the answers are values a test can
# compare, with no console and no pty.
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

Describe 'Get-PickerCapabilityNote' {
    InModuleScope TerminalStyles {

        It 'names a terminal that paints the palette but not background images' {
            $note = Get-PickerCapabilityNote -Kind 'ITerm2' -UseSettingsFile $false
            $note | Should -Not -BeNullOrEmpty
            $note | Should -Match 'background images'
            $note | Should -Match ([regex]::Escape((Get-TerminalDisplayName -Kind 'ITerm2')))
        }

        It 'says the harder thing on a host that renders no colors at all' {
            # The two notices are the if and the elseif of one statement, so
            # both were wiped by the Clear-Host the same way and both have to
            # come back inside the frame. Driven through a mocked Test-StyledHost
            # because every kind in the table currently claims OscPalette -- a
            # test that looked for a real unstyled kind would report green while
            # exercising nothing.
            Mock Test-StyledHost { $false }
            $note = Get-PickerCapabilityNote -Kind 'ITerm2' -UseSettingsFile $false
            Should -Invoke Test-StyledHost -Scope It
            $note | Should -Match "doesn't render colors"
        }

        It 'and that one outranks the background-image note, even on Windows Terminal' {
            # A host that paints no colours at all is told that, not that its
            # backgrounds are missing -- and the settings.json short-circuit
            # must not swallow it.
            Mock Test-StyledHost { $false }
            Get-PickerCapabilityNote -Kind 'WindowsTerminal' -UseSettingsFile $true |
                Should -Match "doesn't render colors"
        }

        It 'says nothing on Windows Terminal' {
            # WT previews through settings.json, which carries the background
            # image, so there is nothing to warn about -- and a note that is
            # always present would cost the menu a row for nothing.
            Get-PickerCapabilityNote -Kind 'WindowsTerminal' -UseSettingsFile $true | Should -BeNullOrEmpty
        }

        It 'says nothing on a terminal that can show a background' {
            $kind = @('AppleTerminal', 'WezTerm') |
                Where-Object { (Test-StyledHost -Kind $_) -and (Get-TerminalCapability -Kind $_).BackgroundImage } |
                Select-Object -First 1
            if (-not $kind) {
                Set-ItResult -Skipped -Because 'no non-WT kind currently claims BackgroundImage'
                return
            }
            Get-PickerCapabilityNote -Kind $kind -UseSettingsFile $false | Should -BeNullOrEmpty
        }
    }
}

Describe 'the picker paints that note inside its frame, not above it' {
    InModuleScope TerminalStyles {

        It 'decides it once, before the loop' {
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $defs = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$capabilityNote' }, $true))
            @($defs).Count | Should -Be 1 -Because 'a note that can change mid-picker would change the frame''s height'
            $defs[0].Right.Extent.Text | Should -Match 'Get-PickerCapabilityNote'
        }

        It 'paints it from inside $drawMenu' {
            # The whole point: the frame is what survives the Clear-Host.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $draw = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$drawMenu' }, $true))
            @($draw).Count | Should -Be 1
            $draw[0].Extent.Text | Should -Match '\$capabilityNote'
        }

        It 'buys the row it paints' {
            # $chrome is the viewport's budget for everything that is not a
            # style row. A painted line that is not counted pushes the menu off
            # the bottom of the window -- the same accounting $unreadableNote
            # and $backupNote already do.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $draw = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$drawMenu' }, $true))
            $bumps = @($draw[0].FindAll({ param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and
                $n.Clauses[0].Item1.Extent.Text -match '^\$capabilityNote$' -and
                $n.Clauses[0].Item2.Extent.Text -match '\$notes\+\+' }, $true))
            @($bumps).Count | Should -Be 1 -Because 'the note costs a row, so the budget has to know about it'

            # And that a counted note really does cost a row, measured rather
            # than matched: the count reaches the budget as -NoteCount.
            $without = Get-PickerFramePlan -Total 17 -Selected 0 -WindowHeight 30
            $with    = Get-PickerFramePlan -Total 17 -Selected 0 -WindowHeight 30 -NoteCount 1
            ($with.ChromeRows - $without.ChromeRows) | Should -Be 1
        }

        It 'no longer prints it above the menu' {
            # The regression. Any Write-Host of these literals outside $drawMenu
            # is a line the Clear-Host eats.
            $fn  = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $src = $fn.Extent.Text
            foreach ($literal in "doesn't render colors", 'renders the palette but not background images') {
                # The literals live in Get-PickerCapabilityNote now, and nowhere
                # in the picker itself.
                $src.Contains($literal) | Should -BeFalse `
                    -Because "'$literal' printed from the picker body is wiped by its own Clear-Host"
            }
        }
    }
}

Describe 'the shared unsupported-field reader, as both doors call it' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:sd  = Join-Path $TestDrive ('unsup-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:sd -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:sd 'scheme.json'),
                '{"name":"x","background":"#101010","foreground":"#f0f0f0"}', $script:enc)
            Mock Get-StyleBundledBackground { Join-Path $TestDrive 'bg.gif' }
        }

        # Reads a parsed theme rather than the path, so each caller does its own
        # guarded parse. These were written against Get-UnsupportedStyleFeatureNote,
        # a second and NARROWER implementation of the same rule -- it asked two
        # hardcoded questions and could not name font, cursor shape or padding.
        # It is gone; the properties it pinned belong to the one that stayed.
        function script:Read-Theme { param([string]$Json)
            [System.IO.File]::WriteAllText((Join-Path $script:sd 'theme.json'), $Json, $script:enc)
            [System.IO.File]::ReadAllText((Join-Path $script:sd 'theme.json'), $script:enc) | ConvertFrom-Json
        }

        It 'names both when the terminal can show neither' {
            $t = script:Read-Theme '{"colorScheme":"x","backgroundImage":"{{BACKGROUND_IMAGE}}","tabColor":"#ff0000"}'
            $fields = @(Get-UnsupportedStyleField -Theme $t -StyleDir $script:sd -Kind 'ITerm2')
            $fields | Should -Contain 'background image'
            $fields | Should -Contain 'tab color'
            (Show-UnsupportedStyleField -Field $fields -Kind 'ITerm2' 6>&1 | Out-String) |
                Should -Match "can't show"
        }

        It 'says nothing for a style that ships no theme.json' {
            # ...and asks the network nothing either: Get-StyleBundledBackground
            # can make four serial 10-second attempts against the gifs branch.
            @(Get-UnsupportedStyleField -Theme $null -StyleDir $script:sd -Kind 'ITerm2') |
                Should -BeNullOrEmpty
            Should -Invoke Get-StyleBundledBackground -Times 0 -Exactly -Scope It
        }

        It 'does not resolve a background the terminal CAN show' {
            # Capability first: as the left operand of the -and, the resolver
            # ran even where the answer could not matter.
            $t = script:Read-Theme '{"colorScheme":"x","backgroundImage":"{{BACKGROUND_IMAGE}}"}'
            @(Get-UnsupportedStyleField -Theme $t -StyleDir $script:sd -Kind 'AppleTerminal') |
                Should -BeNullOrEmpty
            Should -Invoke Get-StyleBundledBackground -Times 0 -Exactly -Scope It
        }
    }
}

Describe 'both apply doors answer the capability question the same way' {
    InModuleScope TerminalStyles {

        It 'the picker''s confirm and Apply-StyleNonWT read the same note' {
            # The divergence: every other line in the picker's confirm block
            # carries a comment saying it exists so the two doors say the same
            # thing -- Show-ShellStagingFailure, the settings-payload qualifier
            # -- and this one was simply absent. Structural because the confirm
            # branch sits behind an interactive-stdin guard Pester cannot
            # satisfy; the note itself is driven above.
            foreach ($name in 'Invoke-TerminalStyle', 'Apply-StyleNonWT') {
                $calls = @((Get-Command $name).ScriptBlock.Ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Get-UnsupportedStyleField' }, $true))
                @($calls).Count | Should -BeGreaterThan 0 `
                    -Because "$name applies a style off Windows Terminal and owes the user this line"
            }
        }

        It 'and neither keeps its own copy of the wording' {
            # One literal. Two would drift, which is how the picker came to have
            # none at all.
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $hits = @()
            # terminals.ps1 is in the set because that is where the one builder
            # lives -- Show-UnsupportedStyleField. Scanning only tstyles.ps1 and
            # lib/ made this assertion answer 0, which is the shape of a guard
            # that has stopped watching the thing it names rather than of a
            # defect: a file list is its own second implementation.
            foreach ($f in @('tstyles.ps1', 'terminals.ps1') + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.ps1' |
                                                 ForEach-Object { $_.FullName })) {
                $p = if ([System.IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $repoRoot $f }
                $src = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
                $hits += [regex]::Matches($src, "can't show: \{1\}") | ForEach-Object { $p }
            }
            @($hits).Count | Should -Be 1 -Because 'the sentence is built in exactly one place'
        }
    }
}
