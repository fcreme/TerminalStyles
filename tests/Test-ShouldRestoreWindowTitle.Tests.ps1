# Pester 5 tests for Test-ShouldRestoreWindowTitle -- the guard on the picker's
# and the tuner's "put the window title back" step.
#
# The bug it fixes (issue #10): both flows snapshot $Host.UI.RawUI.WindowTitle
# before taking over the screen and write it back if the user cancels. On
# Terminal.app and iTerm2 that getter returns an EMPTY STRING -- the title is
# the terminal's to know, not the host's -- so the restore assigned '' and
# blanked whatever the window was showing. Pressing Esc in the picker wiped the
# previous style's title (set by its own profile.ps1 / ts_title) instead of
# leaving it alone, which is a worse end state than not restoring at all.
#
# The decision is a pure function so it can be tested without a host that has a
# title bar -- the same reasoning that carved out Get-PickerViewport.
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

Describe 'Test-ShouldRestoreWindowTitle' {
    InModuleScope TerminalStyles {

        It 'restores a real title -- the Windows Terminal case' {
            Test-ShouldRestoreWindowTitle -Title 'pwsh'                | Should -BeTrue
            Test-ShouldRestoreWindowTitle -Title 'eva'                 | Should -BeTrue
            Test-ShouldRestoreWindowTitle -Title '~/TerminalStyles'    | Should -BeTrue
        }

        # Terminal.app and iTerm2, verified on macOS 26:
        #   pwsh -NoProfile -c '"[" + $Host.UI.RawUI.WindowTitle + "]"'  ->  []
        It 'declines when the host reported no title at all' {
            Test-ShouldRestoreWindowTitle -Title ''    | Should -BeFalse
            Test-ShouldRestoreWindowTitle -Title $null | Should -BeFalse
        }

        # Assigning these blanks the window just as surely as '' does, so they
        # are nothing to put back for the same reason.
        It 'declines on a whitespace-only title' {
            foreach ($t in ' ', '   ', "`t", "`n", " `t `n ") {
                Test-ShouldRestoreWindowTitle -Title $t |
                    Should -BeFalse -Because "'$($t -replace '\s', '.')' is not a title"
            }
        }

        It 'never throws, whatever it is handed' {
            { Test-ShouldRestoreWindowTitle -Title $null } | Should -Not -Throw
            { Test-ShouldRestoreWindowTitle -Title ''     } | Should -Not -Throw
        }
    }
}

Describe 'the picker and the tuner both go through that guard' {
    # The restore itself is one line inside a keyboard UI that no test can drive,
    # so assert the shape of the call instead: a bare assignment in either finally
    # block is the bug coming back.
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    It 'has no unguarded WindowTitle restore in <file>' -ForEach @(
        @{ file = 'tstyles.ps1' }
        @{ file = 'lib/tune.ps1' }
    ) {
        $src = Get-Content -LiteralPath (Join-Path $script:repoRoot $file) -Raw

        # Every write-back of the saved title must sit under the guard.
        $writes = [regex]::Matches($src, '\$Host\.UI\.RawUI\.WindowTitle\s*=\s*\$originalTitle')
        $guards = [regex]::Matches($src, 'Test-ShouldRestoreWindowTitle\s+-Title\s+\$originalTitle')

        $writes.Count | Should -BeGreaterThan 0 -Because 'the restore should still exist'
        $guards.Count | Should -Be $writes.Count -Because 'each restore needs its own guard'
    }
}

Describe 'a preview may only move a title the same rule can put back' {
    # The half the restore guard did not cover. The PICKER also WRITES
    # $Host.UI.RawUI.WindowTitle -- on its first preview and on every arrow key
    # -- and on Unix that setter really works: PowerShell emits OSC 0 ; <title>
    # BEL, and all 16 bundled styles ship a tabTitle. The restore was gated on a
    # snapshot that Terminal.app and iTerm2 answer as '', so on exactly the host
    # class the guard exists for, the picker changed a thing it had already
    # decided it could not change back.
    #
    # Measured under the zsh/bash shim, where it always bites (the shim sets
    # $TStylesNoAutoLoad, so no style profile has ever run in that process and
    # the snapshot is empty every time): four OSC 0 title writes during a
    # cancelled session, no restoring one after it, and "Reverted." printed
    # under the rejected style's title -- which then survived for the life of
    # the tab, because every style sets its title once at load and never from
    # `prompt`.
    #
    # The fix is NOT to restore '': assigning an empty title blanks whatever the
    # window was showing, which is the worse end state the restore guard exists
    # to avoid. The two gates therefore have to give the same answer.
    InModuleScope TerminalStyles {

        It 'agrees with the restore gate on every input' {
            foreach ($t in 'pwsh', 'Windows Terminal', 'eva', '', '   ', "`t") {
                Test-ShouldPreviewWindowTitle -SnapshotTitle $t |
                    Should -Be (Test-ShouldRestoreWindowTitle -Title $t) `
                    -Because "a title the picker may move is exactly one it can put back ('$t')"
            }
            Test-ShouldPreviewWindowTitle -SnapshotTitle $null | Should -BeFalse
        }

        It 'refuses the host that reports no title' {
            # The concrete case: Terminal.app / iTerm2, and any fresh pwsh where
            # no style profile has loaded.
            Test-ShouldPreviewWindowTitle -SnapshotTitle '' | Should -BeFalse
        }

        It 'lets Windows Terminal preview as before' {
            Test-ShouldPreviewWindowTitle -SnapshotTitle 'pwsh' | Should -BeTrue
        }

        It 'and every title write in the picker is gated on it' {
            # Three writes: the first preview, and the two in $applyTheme. A
            # bare one is the bug coming back.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $writes = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$Host.UI.RawUI.WindowTitle' -and
                $n.Right.Extent.Text -match '^\$titles\[' }, $true))
            @($writes).Count | Should -BeGreaterThan 0 -Because 'the title preview should still exist'
            foreach ($w in $writes) {
                # Walk up to the enclosing if and read its condition.
                $node = $w.Parent
                $cond = $null
                while ($node) {
                    if ($node -is [System.Management.Automation.Language.IfStatementAst]) {
                        $cond = $node.Clauses[0].Item1.Extent.Text
                        break
                    }
                    $node = $node.Parent
                }
                $cond | Should -Not -BeNullOrEmpty -Because 'a title write must be conditional at all'
                $cond | Should -Match '\$canPreviewTitle' `
                    -Because ("the write at line {0} must ask whether this host reports a title" -f
                              $w.Extent.StartLineNumber)
            }
        }
    }
}
