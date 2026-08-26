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

    $script:tstylesPath = Join-Path $repoRoot 'tstyles.ps1'
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:tstylesPath, [ref]$null, [ref]$null)

    function script:Get-FunctionAst {
        param([string]$Name)
        @($script:ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
        }, $true))[0]
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
        $calls = @($script:ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Set-ShellStyleState'
        }, $true))

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

    It 'compares paths the way the host filesystem does' {
        # PowerShell's -eq is case-insensitive. On Linux, where the filesystem
        # is not, that made a "Save as Eva" from a base at styles/eva look like
        # the same directory and skip the prompt.sh copy into a genuinely new
        # style -- leaving it with colors and no zsh/bash prompt.
        $fn = script:Get-FunctionAst -Name 'Save-TunedStyle'
        $fn | Should -Not -BeNullOrEmpty
        $fn.Extent.Text | Should -Match 'StringComparison\]::Ordinal\b'
        $fn.Extent.Text | Should -Match 'StringComparison\]::OrdinalIgnoreCase'
    }

    It 'treats a case-variant sibling as a DIFFERENT directory on Linux' {
        $sep  = [System.IO.Path]::DirectorySeparatorChar
        $a    = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $TestDrive 'styles') 'Eva')).TrimEnd($sep)
        $b    = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $TestDrive 'styles') 'eva')).TrimEnd($sep)
        [string]::Equals($a, $b, [System.StringComparison]::Ordinal) | Should -BeFalse
        # ...and the same directory where the filesystem is case-insensitive.
        [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
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
        $fn = script:Get-FunctionAst -Name 'Invoke-TerminalStyle'
        $src = $fn.Extent.Text
        $src | Should -Match '\$startIdx\s*=\s*\$idx'
        $src.IndexOf('$startIdx        = $idx') | Should -BeLessThan $src.IndexOf('Invoke-StylePickerLoop')
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
