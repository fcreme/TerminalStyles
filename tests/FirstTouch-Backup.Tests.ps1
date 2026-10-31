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
        # -HomeDir sandboxes the rc lookup and NOTHING else. shell-init reaches
        # Sync-ShellRuntime before it registers anything, and that stages
        # shell/tstyles.sh and regenerates tstyles-cli.ps1 under the DATA ROOT,
        # which -HomeDir does not touch. Unsandboxed, the four calls below
        # rewrote the shim in the operator's OWN install, with an install kind
        # derived from this checkout rather than from their install: on a
        # bootstrap machine that is the by-name `Import-Module TerminalStyles`,
        # which resolves to nothing there -- so a green run left every new zsh
        # tab with no working `tstyles`, the 0.8.21 defect delivered by the test
        # suite. Saved and restored rather than assigned once, because the
        # module's $script: state outlives this Describe.
        BeforeEach {
            $script:savedDataRoot   = $script:TStylesDataRoot
            $script:TStylesDataRoot = $TestDrive
        }
        AfterEach { $script:TStylesDataRoot = $script:savedDataRoot }

        # The ~/.bash_profile shell-init CREATES. Its seed was written by a
        # second writer, then Register-ShellLoader found an existing file with
        # no block and copied it as "your original"; after shell-remove left
        # the seed, every later init copied it again.
        It 'does not back up the ~/.bash_profile it is creating, for the <label> layout' -ForEach @(
            @{ label = '.bashrc only';   files = @('.bashrc'); bashrcBaks = 1 }
            @{ label = 'nothing at all'; files = @();          bashrcBaks = 0 }
        ) {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            foreach ($f in $files) { [System.IO.File]::WriteAllText((Join-Path $h $f), "# mine`n") }
            $bp = Join-Path $h '.bash_profile'

            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                $out = Invoke-TerminalStylesShellInit -HomeDir $h 6>&1 | Out-String -Width 500
            } finally { $env:SHELL = $prev }

            [System.IO.File]::ReadAllText($bp) | Should -Match 'TerminalStyles BEGIN' -Because 'the create path ran'
            @(Get-ChildItem -LiteralPath $h -Filter '.bash_profile.bak-*' -Force).Count | Should -Be 0
            $out | Should -Not -Match ('backed up your original to: ' + [regex]::Escape($bp))
            @(Get-ChildItem -LiteralPath $h -Filter '.bashrc.bak-*' -Force).Count | Should -Be $bashrcBaks `
                -Because "the user's own file is still copied"
        }

        It 'takes away the ~/.bash_profile it made on shell-remove, and backs up nothing on the next init' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $h '.bashrc'), "# mine`n")
            $bp = Join-Path $h '.bash_profile'

            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                Invoke-TerminalStylesShellInit -HomeDir $h *> $null
                [System.IO.File]::ReadAllText($bp) | Should -Match 'Created by TerminalStyles'
                Invoke-TerminalStylesShellInit -HomeDir $h -Remove *> $null
                [System.IO.File]::Exists($bp) | Should -BeFalse `
                    -Because 'it held nothing but the lines shell-init wrote, and left in place it shadows ~/.bash_login'
                $out2 = Invoke-TerminalStylesShellInit -HomeDir $h 6>&1 | Out-String -Width 500
            } finally { $env:SHELL = $prev }

            [System.IO.File]::ReadAllText($bp) | Should -Match 'TerminalStyles BEGIN' -Because 'the second init ran'
            @(Get-ChildItem -LiteralPath $h -Filter '.bash_profile.bak-*' -Force).Count | Should -Be 0
            $out2 | Should -Not -Match ('backed up your original to: ' + [regex]::Escape($bp))
        }

        It 'keeps a ~/.bash_profile that holds anything of the user''s besides the seed' {
            $h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $h -Force | Out-Null
            $bp = Join-Path $h '.bash_profile'
            # The bare line users write themselves: never taken for ours.
            [System.IO.File]::WriteAllText($bp, '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' + "`n")
            Register-ShellLoader -Path $bp | Should -Be 'added'

            Invoke-TerminalStylesShellInit -HomeDir $h -Remove *> $null

            [System.IO.File]::Exists($bp) | Should -BeTrue
            [System.IO.File]::ReadAllText($bp) | Should -Not -Match 'TerminalStyles BEGIN'
        }

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
