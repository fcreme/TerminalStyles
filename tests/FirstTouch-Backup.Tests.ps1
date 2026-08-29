# Pester 5 tests: the user's own rc file and $PROFILE get backed up the first
# time TerminalStyles writes to them.
#
# install.ps1 has done this since it was written -- `<path>.bak-<timestamp>`,
# once, skipped when the loader block is already present, pinned by
# tests/Install-Hardening.Tests.ps1. The MODULE half never did, so `tstyles
# shell-init` and `tstyles register` rewrote a hand-maintained .zshrc or
# profile.ps1 with no copy kept anywhere. Same project, same file, two
# different standards of care depending on which entry point the user reached.
#
# FIRST TOUCH is the rule: once our block is in the file, a fresh copy would
# capture a file that already carries it, so the version worth keeping exists
# only before the first write.
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

Describe 'Save-FirstTouchBackup' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:f = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.zshrc')
            [System.IO.File]::WriteAllText($script:f, "# the user's own config`nexport EDITOR=vim`n")
        }

        It 'copies the file when our block is not in it yet' {
            $content = [System.IO.File]::ReadAllText($script:f)
            $bak = Save-FirstTouchBackup -Path $script:f -Content $content -BlockPattern 'TerminalStyles BEGIN'

            $bak | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($bak) | Should -Be $content
            $bak | Should -Match '\.bak-\d{8}-\d{6}$' -Because 'install.ps1 already established this naming'
        }

        It 'does NOT copy when our block is already there' {
            # The pristine copy was taken on the first touch. Backing up again
            # would capture a file that already carries our block, which is not
            # the version the user would want back.
            $content = "# mine`n# ===== TerminalStyles BEGIN =====`n. x`n# ===== TerminalStyles END =====`n"
            Save-FirstTouchBackup -Path $script:f -Content $content -BlockPattern 'TerminalStyles BEGIN' |
                Should -BeNullOrEmpty
        }

        It 'still backs up when the pattern is empty, rather than skipping everything' {
            # The trap. `'anything' -match ''` is TRUE for every string, so a
            # bare `$Content -match $BlockPattern` with an empty pattern reports
            # "already ours" and silently skips the backup on EVERY call -- the
            # exact inverse of the intent. The `$BlockPattern -and` guard is
            # what makes an unknown pattern err toward keeping a copy.
            '' -eq '' | Should -BeTrue   # (sanity: the case below is about $BlockPattern, not $Content)
            'anything at all' -match '' | Should -BeTrue -Because 'this is why the -and is load-bearing'

            $content = [System.IO.File]::ReadAllText($script:f)
            Save-FirstTouchBackup -Path $script:f -Content $content -BlockPattern '' |
                Should -Not -BeNullOrEmpty -Because 'an unknown block pattern must not disable the backup'
        }

        It 'returns nothing rather than throwing when the file is not there' {
            Save-FirstTouchBackup -Path (Join-Path $TestDrive 'no-such-file') -Content '' -BlockPattern 'x' |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'shell-init keeps a copy of the rc file it edits' {
    InModuleScope TerminalStyles {
        It 'backs up an existing .zshrc before adding the loader' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $rc = Join-Path $h '.zshrc'
            $original = "# a hand-maintained zsh config`nalias g=git`n"
            [System.IO.File]::WriteAllText($rc, $original)

            Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null

            [System.IO.File]::ReadAllText($rc) | Should -Match 'TerminalStyles BEGIN'
            $baks = @(Get-ChildItem -LiteralPath $h -Filter '.zshrc.bak-*' -Force)
            $baks.Count | Should -Be 1 -Because 'the pristine file must be recoverable'
            [System.IO.File]::ReadAllText($baks[0].FullName) | Should -Be $original
        }

        It 'does not pile up a backup on every re-run' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $rc = Join-Path $h '.zshrc'
            [System.IO.File]::WriteAllText($rc, "# mine`n")

            Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null
            Invoke-TerminalStylesShellInit -HomeDir $h -Force *> $null

            @(Get-ChildItem -LiteralPath $h -Filter '.zshrc.bak-*' -Force).Count |
                Should -Be 1 -Because 'after the first touch the block is present, so there is nothing pristine left to copy'
        }
    }
}

Describe 'register keeps a copy of the $PROFILE it edits' {
    InModuleScope TerminalStyles {
        It 'backs up an existing profile before writing the loader' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $prof = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
            $original = "# my own prompt`nSet-Alias ll Get-ChildItem`n"
            [System.IO.File]::WriteAllText($prof, $original)

            Mock Write-Host {}
            $target = [pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $prof; Exists = $true; HasLoader = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            [System.IO.File]::ReadAllText($prof) | Should -Match 'TerminalStyles BEGIN'
            $baks = @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1.bak-*' -Force)
            $baks.Count | Should -Be 1
            [System.IO.File]::ReadAllText($baks[0].FullName) | Should -Be $original `
                -Because "the user's own prompt must be recoverable after we rewrite their profile"
        }
    }
}
