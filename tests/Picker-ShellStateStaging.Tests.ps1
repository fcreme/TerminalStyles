# Pester 5 tests: the picker must stage the zsh/bash side of a confirmed style,
# not just record its name.
#
# The bug: off Windows Terminal, `tstyles` (the picker) retinted the window live
# over OSC and called Set-CurrentStyleRecord on confirm -- but never
# Set-ShellStyleState. So current-style.osc and current-prompt.sh stayed on the
# PREVIOUS style, and every new zsh/bash tab came up in the old palette and
# banner, while `tstyles <name>` on the very same terminal got it right.
#
# These are AST assertions rather than a driven picker on purpose. The confirm
# branch lives inline in Invoke-TerminalStyle behind an interactive-stdin guard
# ([Console]::IsInputRedirected), which is always true under Pester -- so a
# behavioural test here would silently never reach the branch. That is the same
# green-but-never-run failure that hid the Terminal.app cases for three
# releases; a structural assertion that always runs beats a behavioural one
# that never does.
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

    # Every file the module dot-sources, not just tstyles.ps1. The library is
    # split across lib/, so a function these tests reason about can live in any
    # of them -- and moving one between files must not silently turn an
    # assertion into a lookup that returns $null and passes vacuously.
    $script:modulePaths = @(
        (Join-Path $repoRoot 'tstyles.ps1')
        (Join-Path $repoRoot 'terminals.ps1')
    ) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.ps1' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })

    $script:asts = @(foreach ($p in $script:modulePaths) {
        [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$null)
    })
    # Kept for the assertions that specifically mean "in tstyles.ps1".
    $script:ast = $script:asts[0]

    function script:Get-FunctionAst {
        param([string]$Name)
        foreach ($a in $script:asts) {
            $hit = @($a.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
            }, $true))
            if ($hit.Count) { return $hit[0] }
        }
        return $null
    }

    function script:Get-CalledCommandName {
        param($FunctionAst)
        @($FunctionAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.CommandAst]
        }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    }
}

Describe 'the picker stages shell state on confirm' {

    It 'Invoke-TerminalStyle calls Set-ShellStyleState' {
        # Without this the picker leaves the shell runtime on the previous
        # style. Nothing errors -- the next zsh tab is just quietly wrong.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn | Should -Not -BeNullOrEmpty
        (script:Get-CalledCommandName -FunctionAst $fn) | Should -Contain 'Set-ShellStyleState'
    }

    It 'Invoke-TerminalStyle also records the style name' {
        # The record and the staged files are two halves of the same job: the
        # record drives `tstyles current` / the `*` in `tstyles list`, the
        # staged files drive what a new zsh/bash tab actually looks like.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        (script:Get-CalledCommandName -FunctionAst $fn) | Should -Contain 'Set-CurrentStyleRecord'
    }

    It 'Apply-StyleNonWT still stages it too' {
        # The direct-apply path was always correct; pin it so a future refactor
        # cannot fix the picker by moving the call out of here.
        $fn = script:Get-FunctionAst -Name 'Apply-StyleNonWT'
        $fn | Should -Not -BeNullOrEmpty
        (script:Get-CalledCommandName -FunctionAst $fn) | Should -Contain 'Set-ShellStyleState'
    }

    It 'every Set-ShellStyleState call passes a Scheme' {
        # Set-ShellStyleState computes current-style.osc from -Scheme. Omitting
        # it is a Mandatory-parameter prompt at confirm time, on a screen the
        # picker has already taken over.
        # Across every module file: the two call sites now live in different
        # ones (the picker in tstyles.ps1, Apply-StyleNonWT in lib/applystyle.ps1).
        $calls = @(foreach ($a in $script:asts) {
            $a.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Set-ShellStyleState'
            }, $true)
        })

        $calls.Count | Should -BeGreaterOrEqual 2
        foreach ($c in $calls) {
            $params = @($c.CommandElements |
                Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                ForEach-Object { $_.ParameterName })
            $params | Should -Contain 'Scheme'
            $params | Should -Contain 'StyleName'
            $params | Should -Contain 'StyleDir'
        }
    }
}

Describe 'the picker honours -KeepPrompt' {

    It 'guards the current-style.ps1 COPY on -KeepPrompt' {
        # -KeepPrompt means "this style's colors, my prompt". Copying the style's
        # profile.ps1 over current-style.ps1 is exactly what installs its prompt,
        # so the picker doing it unconditionally made the flag a no-op there --
        # while the direct-apply path honoured it.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn.Extent.Text | Should -Match '-not\s+\$KeepPrompt\s+-and\s+\(Test-Path\s+-LiteralPath\s+\$styleProfile\)'
    }

    It 'does NOT hoist the guard above the elseif that clears a stale file' {
        # The guard belongs on the inner condition. Hoisted to the outer `if`
        # it also skips `elseif { Remove-Item $script:TStylesCurrent }`, so the
        # PREVIOUS style's current-style.ps1 survives, gets dot-sourced, and
        # Get-CurrentStyleName then reports the old style -- a worse bug than
        # the one the guard was added to fix, because -KeepPrompt's contract is
        # that the file ends up ABSENT rather than stale.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn.Extent.Text | Should -Not -Match '\$isPwshTarget\s+-and\s+-not\s+\$KeepPrompt'
    }

    It 'shapes the guard the same way both direct-apply paths do' {
        # Apply-StyleDirect and Apply-StyleNonWT are the reference. Pin all
        # three to one shape so the picker cannot drift from them again.
        foreach ($name in 'Invoke-TerminalStyle', 'Apply-StyleDirect', 'Apply-StyleNonWT') {
            $f = script:Get-FunctionAst -Name $name
            $f | Should -Not -BeNullOrEmpty -Because "$name should exist"
            $f.Extent.Text |
                Should -Match '-not\s+\$KeepPrompt\s+-and\s+\(Test-Path\s+-LiteralPath\s+\$styleProfile\)' `
                -Because "$name must guard the copy, not the whole block"
        }
    }
}

Describe 'Save-TunedStyle same-directory detection' {
    # This pair used to assert nothing about the module. One checked that both
    # StringComparison names appeared SOMEWHERE in Save-TunedStyle -- true with
    # the branches swapped -- and the other called [string]::Equals on two
    # TestDrive paths and asserted the BCL behaves as documented, never entering
    # the module at all. Swapping the platform branch back left both green.
    #
    # The decision is now Test-SameStyleDirectory, a pure function over two paths
    # and the platform, so it can be asked directly. The filesystem effect cannot
    # be tested end-to-end: on macOS and Windows styles/Eva and styles/eva are
    # one directory, so the interesting case does not exist to be set up.
    InModuleScope TerminalStyles {

        It 'treats a case-variant sibling as a DIFFERENT directory on Linux' {
            Mock Get-TStylesPlatform { 'Linux' }
            $base = Join-Path (Join-Path $TestDrive 'styles') 'eva'
            $dest = Join-Path (Join-Path $TestDrive 'styles') 'Eva'
            Test-SameStyleDirectory -A $dest -B $base | Should -BeFalse `
                -Because 'a Linux filesystem has two directories here, and the new one needs its own prompt.sh'
        }

        It 'treats it as the SAME directory where the filesystem is case-insensitive' {
            # Not symmetry for its own sake: on Windows and macOS these really are
            # one directory, and a $false there makes every copy below a copy of a
            # file onto itself -- a duplicated tstyles-tuned marker, and a red
            # "Cannot overwrite the item with itself" for prompt.sh at save time.
            foreach ($platform in 'Windows', 'macOS') {
                Mock Get-TStylesPlatform { $platform }.GetNewClosure()
                $base = Join-Path (Join-Path $TestDrive 'styles') 'eva'
                $dest = Join-Path (Join-Path $TestDrive 'styles') 'Eva'
                Test-SameStyleDirectory -A $dest -B $base | Should -BeTrue -Because "on $platform they are one directory"
            }
        }

        It 'recognises the re-tune case on every platform' {
            # The original reason the guard exists: saving over the style you are
            # tuning makes base and dest literally identical.
            foreach ($platform in 'Linux', 'Windows', 'macOS') {
                Mock Get-TStylesPlatform { $platform }.GetNewClosure()
                $d = Join-Path (Join-Path $TestDrive 'styles') 'eva'
                Test-SameStyleDirectory -A $d -B $d | Should -BeTrue -Because "on $platform a re-tune is a self-copy"
            }
        }

        It 'normalises trailing separators and relative segments' {
            Mock Get-TStylesPlatform { 'Linux' }
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $d   = Join-Path (Join-Path $TestDrive 'styles') 'eva'
            Test-SameStyleDirectory -A ($d + $sep) -B $d | Should -BeTrue
            Test-SameStyleDirectory -A (Join-Path (Join-Path $d '..') 'eva') -B $d | Should -BeTrue
        }

        It 'answers not-the-same rather than throwing on a path it cannot resolve' {
            # Reached with a caller-supplied name, so it must not take down a save.
            Mock Get-TStylesPlatform { 'Linux' }
            { Test-SameStyleDirectory -A '' -B 'x' } | Should -Not -Throw
            Test-SameStyleDirectory -A '' -B 'x' | Should -BeFalse
            $bad = "$([char]0)invalid"
            { Test-SameStyleDirectory -A $bad -B 'x' } | Should -Not -Throw
            Test-SameStyleDirectory -A $bad -B 'x' | Should -BeFalse
        }

    }

    It 'is what Save-TunedStyle actually asks' {
        # Keeps the decision from being inlined back into the caller, where it
        # would stop being reachable by the tests above. Outside InModuleScope:
        # the file's script:Get-FunctionAst helper is not visible inside one.
        $fn = script:Get-FunctionAst -Name 'Save-TunedStyle'
        $fn | Should -Not -BeNullOrEmpty
        $fn.Extent.Text | Should -Match '\$sameDir\s*=\s*Test-SameStyleDirectory'
    }
}

Describe 'the picker puts the terminal back when you cancel' {
    # Esc is documented as "revert to exactly how it looked before". On Windows
    # Terminal it restores settings.json byte-exactly and WT repaints from it.
    # Off Windows Terminal the applied style exists ONLY as escape sequences in
    # the tab, so emitting Get-OscResetPacket -- which hands control back to the
    # terminal's OWN defaults -- dropped the user to a stock palette instead of
    # the style they arrived with.

    It 'revert re-emits the starting style off Windows Terminal' {
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match '\$startIdx'
        $src | Should -Match '\$hadCurrentStyle'
        $src | Should -Match 'Get-SchemeOscPacket -Scheme \$schemes\[\$startIdx\]'
    }

    It 'captures the starting index before the cursor moves' {
        # $idx is the live cursor and has moved by the time Esc arrives, so the
        # revert cannot read it.
        #
        # Asked of the AST, not of the source text. The ordering half of this used
        # to be $src.IndexOf('$startIdx        = $idx'), with the alignment padding
        # baked into the needle: re-space the line while moving it and IndexOf
        # returns -1, which is less than any real offset, so the assertion passed
        # precisely when the regression was present.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn | Should -Not -BeNullOrEmpty

        $assign = @($fn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$startIdx' }, $true))
        @($assign).Count | Should -BeGreaterThan 0 -Because '$startIdx must be captured somewhere'

        $loopCall = @($fn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Invoke-StylePickerLoop' }, $true))
        @($loopCall).Count | Should -BeGreaterThan 0

        $firstAssign = ($assign | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum
        $firstLoop   = ($loopCall | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum
        $firstAssign | Should -BeLessThan $firstLoop `
            -Because 'the revert reads $startIdx, so it must be captured before the cursor starts moving'
    }

    It 'still hands control back to the terminal when there was no active style' {
        # Nothing to restore: the stock palette IS correct there.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn.Extent.Text | Should -Match 'Get-OscResetPacket'
    }

    It 'reverts on Ctrl+C or an exception, not only on Esc' {
        # Anything that throws out of the loop skips the Escape branch, so the
        # last previewed style stayed applied while only the cursor and title
        # were put back.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match '\$pickerState\.Reverted'
        $src | Should -Match '-not \$pickerState\.Reverted -and \$restoreOriginalLook'
    }

    It 'tracks the revert in a reference type, not a plain bool' {
        # A scriptblock assigning to a [bool] would land in its own child scope
        # and the finally would never see it, so the revert would run twice.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn.Extent.Text | Should -Match '\$pickerState\s*=\s*@\{\s*Reverted\s*=\s*\$false\s*\}'
    }
}

Describe 'the picker does not burn work it throws away' {

    It 'bails out of the idle slice BEFORE scanning every style' {
        # The idle slice runs ~20x/second. Its loop calls Test-StyleResolved --
        # a filesystem probe -- once per style, and then the very next line
        # returned early on any terminal that is not Windows Terminal, discarding
        # the result. Measured at 8.8 ms per full scan over 17 styles, that is
        # ~176 ms of work per second spent computing nothing.
        $fn  = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $idle = [regex]::Match($src, '(?s)\$onIdle = \{.*?\n        \}').Value
        $idle | Should -Not -BeNullOrEmpty -Because 'the $onIdle scriptblock should still be there'
        # Matched on the CALL forms, not the bare names: the comment above the
        # early-out explains the fix and names Test-StyleResolved, so a search
        # for the bare word finds the prose rather than the code.
        $bail = $idle.IndexOf('if (-not $useSettingsFile) { Start-Sleep')
        $scan = $idle.IndexOf('-not (Test-StyleResolved -StyleDir')
        $bail | Should -BeGreaterOrEqual 0 -Because 'the early-out should still be there'
        $scan | Should -BeGreaterOrEqual 0 -Because 'the prebuild scan should still be there'
        $bail | Should -BeLessThan $scan -Because 'the early-out has to come before the scan'
    }

    It 'still prebuilds on Windows Terminal, where the scan is used' {
        # The fix must not have cost WT its prebuild -- that cache is what makes
        # arrow-keying back to a visited style instant.
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $idle = [regex]::Match($fn.Extent.Text, '(?s)\$onIdle = \{.*?\n        \}').Value
        $idle | Should -Match 'Merge-StyleIntoSettings'
        $idle | Should -Match 'mergedCache\['
    }
}

Describe 'the background prefetch cannot leave a truncated cache entry' {

    It 'downloads to a .part and renames on completion' {
        # The job is killed with Stop-Job the moment the user picks. Writing
        # -OutFile straight to the final name left a half-downloaded file at the
        # exact path every reader treats as a valid cache hit -- and nothing
        # revalidates a file that exists, so a truncated GIF became that style's
        # background permanently.
        $fn  = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match '\$part = "\$local\.part"'
        $src | Should -Match 'Invoke-WebRequest -Uri "\$remoteBase\.\$ext" -OutFile \$part'
        $src | Should -Match 'Move-Item -LiteralPath \$part -Destination \$local -Force'
    }

    It 'never points -OutFile at the final cache path' {
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $fn.Extent.Text | Should -Not -Match '-OutFile \$local\b'
    }

    It 'writes a dated negative-cache marker, like the synchronous path' {
        # An undated marker reads as expired since 0.8.6, so the prefetch's
        # negative caching was silently doing nothing at all.
        # Searched over the whole function rather than a sliced-out job body:
        # the prefetch job is the only thing in Invoke-TerminalStyle that writes
        # a .no-background marker, so these are unambiguous here.
        $fn  = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match "kind\s*=\s*'absent'"
        $src | Should -Match 'UtcNow'
        $src | Should -Not -Match "New-Item -ItemType File -Path \(Join-Path \`$cacheDir '\.no-background'\)"
    }
}

Describe 'the update notice survives the picker clearing the screen' {

    It 'is held until after the picker gives the screen back' {
        # It was printed before the menu was drawn, and the picker's first
        # Clear-Host wiped it a few lines later -- while still paying for the
        # HTTP check that produced it.
        $fn  = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match '\$pendingUpdate = Test-UpdateAvailable'
        # Compared against the picker loop, NOT the first Clear-Host in the
        # function -- an earlier subcommand branch clears the screen too, so
        # that index belongs to a different code path entirely.
        $src.IndexOf('$pendingUpdate = Test-UpdateAvailable') |
            Should -BeLessThan $src.IndexOf('Invoke-StylePickerLoop')
        # ...and it is actually printed somewhere after the confirm output.
        $src.IndexOf('Style applied: ') |
            Should -BeLessThan $src.LastIndexOf('$pendingUpdate')
    }

    It 'still throttles through Test-UpdateAvailable rather than checking twice' {
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        ([regex]::Matches($src, 'Test-UpdateAvailable')).Count | Should -Be 1
        $src | Should -Not -Match 'Show-UpdateNoticeIfAvailable'
    }
}

Describe 'the AST helper actually finds what it is asked for' {
    # These tests reason about functions by parsing source. Splitting the library
    # across lib/ means a function can move between files -- and a lookup that
    # returns $null would make every assertion built on it pass vacuously, which
    # is worse than a failure. Pin that the helper resolves each name it is used
    # with, wherever that function currently lives.

    It 'resolves <_>' -ForEach @(
        'Invoke-TerminalStyle', 'Apply-StyleNonWT', 'Apply-StyleDirect',
        'Save-TunedStyle', 'Invoke-TerminalStyleTune', 'Get-PickerViewport',
        'Invoke-TerminalStylesUninstall', 'Invoke-TerminalStylesShellInit'
    ) {
        script:Get-FunctionAst -Name $_ | Should -Not -BeNullOrEmpty `
            -Because 'a null lookup would make the assertions built on it meaningless'
    }

    It 'returns nothing for a name that does not exist' {
        script:Get-FunctionAst -Name 'Definitely-NotAFunction' | Should -BeNullOrEmpty
    }

    It 'searches every file the module dot-sources' {
        $script:modulePaths.Count | Should -BeGreaterThan 2
        ($script:modulePaths | Where-Object { $_ -like '*lib*' }).Count | Should -BeGreaterThan 0
    }
}
