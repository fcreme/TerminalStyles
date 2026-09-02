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
