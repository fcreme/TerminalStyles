# Pester 5 tests: the rc loader refresh tells paths apart by case.
#
# Register-ShellLoader decided a block already in the file was 'unchanged' with
# -eq, which ignores case. A data root whose path changed only in case -- a home
# folder renamed from /home/Jo to /home/jo on a case-sensitive volume -- kept
# the old block, whose `[ -r ... ]` guard then failed on every new shell, and
# shell-init reported nothing to do.
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

Describe 'the loader refresh tells paths apart by case' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:dir)
            $script:enc = [System.Text.UTF8Encoding]::new($false)
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedRoot
        }

        It 'refreshes a block whose data-root path differs only in case' {
            # Never created: Register-ShellLoader only reads the string.
            $script:TStylesDataRoot = Join-Path $script:dir 'Jo/terminalstyles'
            $rc = Join-Path $script:dir '.zshrc'
            [System.IO.File]::WriteAllText($rc, "# mine`n", $script:enc)
            Register-ShellLoader -Path $rc 6>$null | Should -Be 'added' -Because 'the fixture must plant a real block'
            $oldRuntime = Join-Path $script:TStylesDataRoot 'tstyles.sh'

            $script:TStylesDataRoot = Join-Path $script:dir 'jo/terminalstyles'
            $newRuntime = Join-Path $script:TStylesDataRoot 'tstyles.sh'
            (Get-ShellLoaderBlock) -eq ([System.IO.File]::ReadAllText($rc, $script:enc) -replace '^# mine\n', '').Trim() |
                Should -BeTrue -Because 'control: the case-insensitive compare calls the old block current'

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'updated'

            $after = [System.IO.File]::ReadAllText($rc, $script:enc)
            $after.Contains($newRuntime) | Should -BeTrue
            $after.Contains($oldRuntime) | Should -BeFalse
            $after | Should -BeExactly ("# mine`n" + (Get-ShellLoaderBlock).Trim() + "`n")
            Register-ShellLoader -Path $rc 6>$null | Should -Be 'unchanged'
        }
    }
}
