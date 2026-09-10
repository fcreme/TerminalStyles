# Pester 5 tests: one style with a malformed scheme.json must not take the
# picker down, and must not be silently previewed as the style before it.
#
# Get-AvailableStyles admits a folder on scheme.json EXISTING, never on it
# parsing, so a hand-authored style with a JSON typo -- or a `tstyles tune` save
# killed mid-write -- arrives at the picker as an ordinary entry. The pre-load
# loop parsed it with no guard, and what that cost depended on
# $ErrorActionPreference:
#
#   Stop     -- what the generated tstyles-cli.ps1 sets, and shell/tstyles.sh
#               runs that for every `tstyles` call from zsh and bash. Bare
#               `tstyles` died with a raw .NET parse error and no menu.
#   Continue -- pwsh's default. The error was only statement-terminating, so the
#               loop carried on with the PREVIOUS style's scheme still in
#               $scheme and the broken style inherited its swatch, its live
#               preview and, on Enter, its palette -- persisted under the broken
#               style's name.
#
# `tstyles list` has survived the same folder since 0.8.x (see
# Subcommand-Robustness.Tests.ps1) by guarding the read and marking the row
# "(unreadable scheme.json)". This is the picker catching up to it.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-PickerStyleSet' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Nothing here reaches the data root, but it is pointed at the test
            # drive anyway so a future edit to this file cannot start.
            $script:TStylesDataRoot = $TestDrive

            function script:New-FakeStyle {
                param([string]$Name, [string]$Scheme)
                $d = Join-Path (Join-Path $TestDrive 'styles') $Name
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), $Scheme,
                    [System.Text.UTF8Encoding]::new($false))
                return [pscustomobject]@{ Name = $Name; FullName = $d }
            }
            function script:New-GoodStyle {
                param([string]$Name)
                script:New-FakeStyle -Name $Name -Scheme (
                    '{{"name":"{0}","background":"#101010","foreground":"#e0e0e0","cursorColor":"#ff0000"}}' -f $Name)
            }
            # A truncated Save-TunedStyle write, byte for byte: lib/tune.ps1
            # writes scheme.json with a plain WriteAllText, so a kill or a full
            # disk leaves exactly this.
            $script:TruncatedScheme = '{"name":"bbb","background":"#11223'
        }

        It 'drops the style that will not parse and keeps the others' {
            $good1 = script:New-GoodStyle -Name 'aaa'
            $bad   = script:New-FakeStyle -Name 'bbb' -Scheme $script:TruncatedScheme
            $good2 = script:New-GoodStyle -Name 'ccc'

            # Called twice on purpose: a scriptblock handed to Should -Not -Throw
            # runs in its own child scope, so an assignment made inside it is
            # invisible out here and every later assertion would be comparing
            # $null with $null.
            { Get-PickerStyleSet -Styles @($good1, $bad, $good2) } | Should -Not -Throw
            $set = Get-PickerStyleSet -Styles @($good1, $bad, $good2)
            @($set.Styles | ForEach-Object Name)         | Should -Be @('aaa', 'ccc')
            @($set.Unreadable)                           | Should -Be @('bbb')
        }

        It 'pairs every style it keeps with its OWN scheme' {
            # The failure this exists for is not a crash. Under pwsh's default
            # $ErrorActionPreference the old parse was statement-terminating, so
            # $scheme kept the PREVIOUS style's object and the entry keyed to the
            # broken style carried the good style before it -- measured as a
            # byte-identical swatch, a preview in the wrong palette, and that
            # palette written into current-style.osc under the wrong name. A test
            # that only asserts "it did not throw" passes straight through it.
            $good1 = script:New-GoodStyle -Name 'aaa'
            $bad   = script:New-FakeStyle -Name 'bbb' -Scheme $script:TruncatedScheme
            $good2 = script:New-GoodStyle -Name 'ccc'

            $set = Get-PickerStyleSet -Styles @($good1, $bad, $good2)
            @($set.Styles).Count | Should -BeGreaterThan 0
            for ($i = 0; $i -lt @($set.Styles).Count; $i++) {
                $set.Schemes[$i].name | Should -Be $set.Styles[$i].Name `
                    -Because 'a scheme must belong to the style it is keyed to'
                $set.Swatches.ContainsKey($i) | Should -BeTrue `
                    -Because 'the picker draws a row per kept style'
            }
        }

        It 'survives the broken style being the FIRST one' {
            # Sorted first, the old loop had no previous scheme to inherit: it
            # left $schemes[0] null and the null bound its way into the draw
            # path -- Get-SchemeOscPacket -Scheme $schemes[$idx] on the picker's
            # own first frame.
            $bad  = script:New-FakeStyle -Name 'aaa-bad' -Scheme '{not json at all'
            $good = script:New-GoodStyle -Name 'bbb'

            $set = Get-PickerStyleSet -Styles @($bad, $good)
            @($set.Styles | ForEach-Object Name) | Should -Be @('bbb')
            $set.Schemes[0].name                 | Should -Be 'bbb'
            @($set.Unreadable)                   | Should -Be @('aaa-bad')
        }

        It 'survives the broken style being the LAST one' {
            $good = script:New-GoodStyle -Name 'aaa'
            $bad  = script:New-FakeStyle -Name 'zzz' -Scheme '{not json at all'

            $set = Get-PickerStyleSet -Styles @($good, $bad)
            @($set.Styles | ForEach-Object Name) | Should -Be @('aaa')
            $set.Schemes[0].name                 | Should -Be 'aaa'
            @($set.Unreadable)                   | Should -Be @('zzz')
        }

        It 'survives the broken style being the ONLY one' {
            $bad = script:New-FakeStyle -Name 'bbb' -Scheme $script:TruncatedScheme

            $set = Get-PickerStyleSet -Styles @($bad)
            @($set.Styles).Count | Should -Be 0
            @($set.Unreadable)   | Should -Be @('bbb')
        }

        It 'counts an empty scheme.json as unreadable rather than as a scheme' {
            # "It did not throw" is not the test: pwsh 7's ConvertFrom-Json
            # returns $null for an empty or whitespace-only file instead of
            # raising, and a $null scheme is refused by every -Scheme parameter
            # downstream. A bare try/catch would have kept this style.
            $empty = script:New-FakeStyle -Name 'bbb' -Scheme ''
            $blank = script:New-FakeStyle -Name 'ccc' -Scheme "   `n"

            $set = Get-PickerStyleSet -Styles @($empty, $blank)
            @($set.Styles).Count | Should -Be 0
            @($set.Unreadable)   | Should -Be @('bbb', 'ccc')
        }

        It 'holds under $ErrorActionPreference = Stop, which is how zsh and bash run it' {
            # terminals.ps1 emits `$ErrorActionPreference = 'Stop'` into
            # tstyles-cli.ps1 and shell/tstyles.sh runs that for every `tstyles`
            # call, which is what turned a statement-terminating parse error into
            # a dead command with no menu. Set here, inside the module scope, so
            # the preference reaches the function through the call stack.
            $ErrorActionPreference = 'Stop'
            $bad  = script:New-FakeStyle -Name 'bbb' -Scheme $script:TruncatedScheme
            $good = script:New-GoodStyle -Name 'ccc'

            { Get-PickerStyleSet -Styles @($bad, $good) } | Should -Not -Throw
            $set = Get-PickerStyleSet -Styles @($bad, $good)
            @($set.Styles | ForEach-Object Name) | Should -Be @('ccc')
        }

        It 'accepts an empty style list rather than refusing to bind' {
            $set = Get-PickerStyleSet -Styles @()
            @($set.Styles).Count     | Should -Be 0
            @($set.Unreadable).Count | Should -Be 0
        }
    }
}

Describe 'the picker itself' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
        }

        It 'refuses by NAME when nothing left has a readable scheme.json' {
            # The one part of the picker a test can reach: this check sits beside
            # the existing "No styles found" one, above the console guard, so it
            # runs in a redirected session too. Before the fix the parse happened
            # below that guard and this said nothing at all -- the command either
            # died on the shim or drew a menu keyed to a null scheme.
            $d = Join-Path (Join-Path $TestDrive 'styles') 'aaa-bad'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{not json at all',
                [System.Text.UTF8Encoding]::new($false))
            $bad = [pscustomobject]@{ Name = 'aaa-bad'; FullName = $d }

            Mock Get-AvailableStyles       { @($bad) }
            Mock Get-TerminalKind          { 'AppleTerminal' }
            Mock Get-CurrentStyleName      { $null }
            Mock Invoke-FontFirstRunPrompt {}
            Mock Test-UpdateAvailable      { $null }
            Mock Write-Host                {}
            $errors = [System.Collections.ArrayList]::new()
            Mock Write-Error { [void]$errors.Add("$Message") }
            # Neither may run: with nothing to pick from, the picker must not
            # take over the screen, and must not block on a keyboard. These also
            # keep the test from hanging on a machine that has a real console
            # attached while the fix is reverted.
            Mock Clear-Host { throw 'the picker must not clear the screen with nothing to show' }
            Mock Invoke-StylePickerLoop { throw 'the picker loop must not start with no styles' }

            { Invoke-TerminalStyle } | Should -Not -Throw
            ($errors -join "`n") | Should -Match 'readable scheme\.json'
            ($errors -join "`n") | Should -Match 'aaa-bad' `
                -Because 'the raw .NET error named a line of tstyles.ps1 and never the folder at fault'
        }

        It 'holds no unguarded parse of a user-authored file' {
            # The picker's body cannot be driven from a test -- it returns at the
            # console guard the moment stdin or stdout is redirected, which is
            # every Pester run -- so this is a shape assertion, on the AST and on
            # the property that carried the defect: every ConvertFrom-Json inside
            # Invoke-TerminalStyle is inside a try. The theme.json pre-load
            # twelve lines below the broken scheme.json one always was; the
            # scheme.json parse was the only one that was not.
            #
            # Deliberately not "no pipeline mentions both scheme.json and
            # ConvertFrom-Json": the path was held in $sp on the line above, so
            # that phrasing passes against the exact code it is meant to catch.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $fn | Should -Not -BeNullOrEmpty

            $parses = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'ConvertFrom-Json' }, $true))
            $unguarded = @($parses | Where-Object {
                $p = $_.Parent
                $guarded = $false
                while ($p) {
                    if ($p -is [System.Management.Automation.Language.TryStatementAst]) { $guarded = $true; break }
                    $p = $p.Parent
                }
                -not $guarded
            })
            @($unguarded | ForEach-Object { $_.Extent.Text }) | Should -BeNullOrEmpty `
                -Because 'one unparseable style must cost its own row, not the whole menu'
        }

        It 'takes the schemes and the swatches from ONE guarded read' {
            # $swatches and $schemes are keyed by position and consumed by the
            # draw path, the OSC preview and the apply. Filling them in a second
            # loop of the picker's own would put a style's row and a style's
            # scheme behind two different parses that agree only until one of
            # them fails -- which is how the broken style came to be previewed,
            # and applied, in the palette of the style before it.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            foreach ($name in '$swatches', '$schemes') {
                $a = @($fn.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left.Extent.Text -eq $name }, $true))
                @($a).Count | Should -Be 1 -Because "$name must be assigned once, from the shared read"
                $a[0].Right.Extent.Text | Should -Match '^\$styleSet\.'
            }
        }

        It 'drops the unreadable styles BEFORE it decides where to open' {
            # Order is the whole of the currently-active case. The picker opens
            # on the active style by finding its name in $styles, and $startIdx
            # -- what Esc puts back -- is taken from that. Filter after the
            # search and the index points into the unfiltered list: every row
            # below the broken style is off by one, and the style the user
            # arrived in is not the one Esc restores.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $filter = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$styleSet' }, $true))
            @($filter).Count | Should -Be 1
            $lookup = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Get-CurrentStyleName' }, $true))
            @($lookup).Count | Should -BeGreaterThan 0

            $filter[0].Extent.StartOffset | Should -BeLessThan `
                (($lookup | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum)
        }

        It 'treats an active style the menu does not carry as no active style' {
            # Get-CurrentStyleName answers from current-style.ps1 or from the
            # record, neither of which knows whether the style still parses -- so
            # `[bool]$currentName` was true for a style with no row, and the Esc
            # revert re-emitted index 0, some other style entirely, while saying
            # it was restoring what the user had.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $a = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$hadCurrentStyle' }, $true))
            @($a).Count | Should -Be 1
            $a[0].Right.Extent.Text | Should -Match '\$currentIdx'
            $a[0].Right.Extent.Text | Should -Not -Match '\$currentName' `
                -Because 'a name the menu does not carry is not a position the revert can use'
        }

        It 'names the styles it dropped, in the frame the user is reading' {
            # Every other notice the picker prints before its menu is wiped by
            # its own Clear-Host -- the reason the update notice is held until
            # afterwards. A style that simply vanished from the list, with the
            # explanation scrolled away, would leave `tstyles list` and the
            # picker disagreeing about what exists and nothing saying why.
            $fn  = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $src = $fn.Extent.Text
            $src | Should -Match 'unreadable scheme\.json' `
                -Because 'the wording `tstyles list` already uses for the same file'

            $draw = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$drawMenu' }, $true))
            @($draw).Count | Should -Be 1
            $draw[0].Right.Extent.Text | Should -Match '\$unreadableNote' `
                -Because 'the frame is the only place a picker message survives to be read'
            # The frame is overwritten in place, so a row that appears without
            # being counted strands the previous frame's last line on screen.
            $draw[0].Right.Extent.Text | Should -Match '\$chrome\s*=\s*if \(\$unreadableNote\)'
        }
    }
}
