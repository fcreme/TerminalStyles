# Pester 5 tests: what a cancelled preview puts back on the screen.
#
# Esc in the picker and Esc in the tuner both have to undo a live OSC retint,
# and both face the same fork. On Windows Terminal the answer is
# Get-OscResetPacket -- settings.json has just been restored byte-exactly and WT
# repaints from it, so handing colour control back to the terminal IS the
# restore. Off Windows Terminal there is no such file: the style the user
# arrived with existed only as escape sequences in that tab, so the reset drops
# them to the terminal's stock palette rather than back to their style.
#
# That fork lived inline in both callers and was pinned in both places by a
# `-Match` against the enclosing function's source text. Both call sites sit
# inside the one extent, so no such assertion can see WHICH arm is which:
# swapping the two arms -- precisely the regression the rule exists to prevent
# -- left all 1821 tests green. These tests compare the bytes instead, which
# needs no console and runs on all four CI legs.
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

    $script:modulePaths = @(
        (Join-Path $repoRoot 'tstyles.ps1')
        (Join-Path $repoRoot 'terminals.ps1')
    ) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.ps1' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })

    function script:Get-FunctionAst {
        param([string]$Name)
        foreach ($p in $script:modulePaths) {
            $a = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$null)
            $hit = @($a.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
            }, $true))
            if ($hit.Count) { return $hit[0] }
        }
        return $null
    }
}

Describe 'Get-RevertOscPacket' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:opened = [pscustomobject]@{
                background = '#0a0006'; foreground = '#ffe8e8'; cursorColor = '#ff3d5a'
            }
        }

        It 're-emits the starting style off Windows Terminal' {
            # The whole point. A reset here would hand the user the terminal's
            # stock palette, not the style they opened the picker on.
            Get-RevertOscPacket -UseSettingsFile:$false -HadStartingStyle:$true -StartingScheme $script:opened |
                Should -Be (Get-SchemeOscPacket -Scheme $script:opened)
        }

        It 'resets when no style was active' {
            # Nothing to put back: the cursor started on the first style in the
            # list, which the user was never looking at. The stock palette is
            # the correct end state, and $StartingScheme is non-null here on
            # purpose -- "there was a scheme at that index" and "the user was
            # using it" are different questions.
            Get-RevertOscPacket -UseSettingsFile:$false -HadStartingStyle:$false -StartingScheme $script:opened |
                Should -Be (Get-OscResetPacket)
        }

        It 'resets on Windows Terminal even when a style was active' {
            # settings.json has just been restored and WT repaints from it, so
            # the OSC overrides are what has to go.
            Get-RevertOscPacket -UseSettingsFile:$true -HadStartingStyle:$true -StartingScheme $script:opened |
                Should -Be (Get-OscResetPacket)
        }

        It 'resets when the starting index carried no scheme' {
            # $schemes[$startIdx] on a missing key is $null, not an error --
            # this is the ContainsKey guard the picker used to spell out.
            Get-RevertOscPacket -UseSettingsFile:$false -HadStartingStyle:$true -StartingScheme $null |
                Should -Be (Get-OscResetPacket)
        }

        It 'never answers with nothing' {
            # A scheme whose values are X11 colour words renders to an empty
            # packet. Emitting that leaves the CANCELLED preview painted, which
            # is the one end state Esc must not produce -- so fall back to the
            # reset rather than to silence.
            $unreadable = [pscustomobject]@{ background = 'black'; foreground = 'rgb(255,0,0)' }
            (Get-SchemeOscPacket -Scheme $unreadable) | Should -BeNullOrEmpty -Because 'the fixture must really be unreadable'
            Get-RevertOscPacket -UseSettingsFile:$false -HadStartingStyle:$true -StartingScheme $unreadable |
                Should -Be (Get-OscResetPacket)
        }

        It 'answers the same question for both callers' {
            # One rule, one implementation. Tuning a style opened off Windows
            # Terminal has to come back to that style too.
            Get-RevertOscPacket -UseSettingsFile:$false -HadStartingStyle:($null -ne $script:opened) -StartingScheme $script:opened |
                Should -Be (Get-SchemeOscPacket -Scheme $script:opened)
        }
    }
}

Describe 'the picker and the tuner both ask it' {
    # The behaviour above is only the picker's and the tuner's behaviour while
    # they keep asking. Inlining the fork back into either caller would put it
    # out of reach of every assertion in this file -- the same reason
    # tests/Picker-ShellStateStaging.Tests.ps1 pins Save-TunedStyle's use of
    # Test-SameStyleDirectory. Asked of the AST rather than of a `-Match`, so
    # re-spacing or re-wrapping the call cannot turn it into a vacuous pass.

    BeforeDiscovery {
        # The tuner's half moved INTO Restore-TuneBaseLook when that gained the
        # run-at-most-once flag, so that is the function that now emits the
        # tuner's revert -- Invoke-TerminalStyleTune reaches it through
        # $restoreBaseLook, which the last It in this Describe pins. The rule
        # being guarded is unchanged: whoever emits a revert asks
        # Get-RevertOscPacket for the answer instead of re-deciding the fork.
        $script:revertCallers = @('Invoke-TerminalStyle', 'Restore-TuneBaseLook')
    }

    It '<_> calls Get-RevertOscPacket' -ForEach $script:revertCallers {
        $fn = script:Get-FunctionAst -Name $_
        $fn | Should -Not -BeNullOrEmpty
        $calls = @($fn.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Get-RevertOscPacket'
        }, $true))
        @($calls).Count | Should -BeGreaterThan 0
    }

    It '<_> emits the answer through Write-HostOscPacket' -ForEach $script:revertCallers {
        # Not [Console]::Out.Write. That is the raw form the reset arm used, and
        # it skips the redirected-stream guard Write-HostOscPacket exists to
        # enforce -- so a cancelled picker wrote escape bytes into a captured
        # stdout that an applied style is careful to keep out of.
        $fn = script:Get-FunctionAst -Name $_
        $emit = @($fn.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Write-HostOscPacket' -and
            $n.Extent.Text -match 'Get-RevertOscPacket'
        }, $true))
        @($emit).Count | Should -BeGreaterThan 0
    }

    It 'the tuner restores the style the user OPENED, not the working base' {
        # This half is the CALLER's decision and cannot be seen from the helper:
        # tuning 'eva-night' resolves its base 'eva' as the working base, so
        # restoring $baseScheme repainted the terminal as eva and called it
        # "Reverted." -- leaving the user on a style they never chose.
        #
        # Asked of BOTH hops now that the emit lives in Restore-TuneBaseLook:
        # the tuner hands it -OpenedScheme $openedScheme, and it forwards that
        # to Get-RevertOscPacket. Checking only one of the two would leave the
        # other free to substitute the base again.
        $tuner = script:Get-FunctionAst -Name 'Invoke-TerminalStyleTune'
        $hand = @($tuner.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Restore-TuneBaseLook'
        }, $true))
        @($hand).Count | Should -BeGreaterThan 0 `
            -Because 'the tuner must route its revert through the one place that carries the flag'
        $hand[0].Extent.Text | Should -Match '\$openedScheme'
        $hand[0].Extent.Text | Should -Not -Match '\$baseScheme'

        $fn = script:Get-FunctionAst -Name 'Restore-TuneBaseLook'
        $call = @($fn.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Get-RevertOscPacket'
        }, $true))[0]
        $call.Extent.Text | Should -Match '\$OpenedScheme'
        $call.Extent.Text | Should -Not -Match '\$BaseScheme'
    }
}
