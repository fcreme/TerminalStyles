# Pester 5 tests: the uninstall consent listing must name the shell rc files it
# is about to change.
#
# THE DEFECT. `tstyles uninstall` prints a bulleted list of what it will do and
# then asks "Continue? [y/N]". Step 2 of the command strips the loader block
# from ~/.zshrc, ~/.bashrc, ~/.bash_profile and ~/.profile -- and the list did
# not mention shell rc files at all. Step 2 was ADDED because uninstall used to
# leave the shell side running; the behaviour was fixed and the consent text
# never caught up.
#
# It is not a summary that happens to be short. The bullet above it names the
# two PowerShell $PROFILE files precisely, and the bullet below promises what
# the command will NOT touch ("Will NOT modify Windows Terminal's
# settings.json") -- a list that specific, that goes out of its way to bound
# itself, is one a reader is entitled to treat as complete. The user then
# watched "Removed shell loader from ~/.zshrc" scroll past for a file the
# prompt never mentioned.
#
# Consent is not exercised here by ANSWERING the prompt: Confirm-Action is
# mocked to refuse, so a bug in console detection can never turn one of these
# tests into a real uninstall of the machine it runs on. -HomeDir keeps the rc
# half inside TestDrive for the same reason.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    # InModuleScope resolves at DISCOVERY, so the import has to happen here too.
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-ShellLoaderPresent' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
        }

        function script:New-Rc([string]$Dir, [string]$Name, [switch]$WithBlock) {
            $p = Join-Path $Dir $Name
            $text = "# original $Name`nexport MINE=1`n"
            if ($WithBlock) {
                $text += "# ===== TerminalStyles BEGIN =====`nif [ -r '/x/tstyles.sh' ]; then . '/x/tstyles.sh'; fi`n# ===== TerminalStyles END =====`n"
            }
            [System.IO.File]::WriteAllText($p, $text, [System.Text.UTF8Encoding]::new($false))
            $p
        }

        It 'sees a block that is there' {
            Test-ShellLoaderPresent -Path (script:New-Rc $script:h '.zshrc' -WithBlock) | Should -BeTrue
        }

        It 'does not see one that is not' {
            Test-ShellLoaderPresent -Path (script:New-Rc $script:h '.bashrc') | Should -BeFalse
        }

        It 'returns false for a file that does not exist rather than throwing' {
            Test-ShellLoaderPresent -Path (Join-Path $script:h 'nope') | Should -BeFalse
        }

        It 'reads without writing' {
            # It runs before consent, so it must not be able to change anything.
            #
            # [System.IO.File], not Get-Item: an rc file is dot-prefixed, which
            # is HIDDEN on Unix, and Get-Item without -Force does not return a
            # hidden item. The first draft of this test used it and both sides
            # of the comparison came back $null, so it asserted $null -eq $null
            # and reported green while measuring nothing at all.
            $p = script:New-Rc $script:h '.zshrc' -WithBlock
            $before = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($p))
            $stamp  = [System.IO.File]::GetLastWriteTimeUtc($p)
            $stamp  | Should -Not -Be ([datetime]'1601-01-01') -Because 'the probe must be reading a real file'

            Test-ShellLoaderPresent -Path $p | Out-Null

            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($p)) | Should -BeExactly $before
            [System.IO.File]::GetLastWriteTimeUtc($p) | Should -Be $stamp
        }
    }
}

Describe 'Get-UninstallShellRcTarget' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
        }

        It 'names only the files that actually carry a block' {
            script:New-Rc $script:h '.zshrc' -WithBlock | Out-Null
            script:New-Rc $script:h '.bashrc'           | Out-Null

            $names = @((Get-UninstallShellRcTarget -HomeDir $script:h).Path |
                       ForEach-Object { Split-Path $_ -Leaf })
            $names | Should -Be @('.zshrc')
        }

        It 'names ~/.profile, which the registration list deliberately omits' {
            # The whole reason this is the REMOVAL superset. A user whose loader
            # went into ~/.profile is exactly the user the old listing failed.
            script:New-Rc $script:h '.profile' -WithBlock | Out-Null

            @((Get-UninstallShellRcTarget -HomeDir $script:h).Path |
              ForEach-Object { Split-Path $_ -Leaf }) | Should -Be @('.profile')
        }

        It 'names nothing when no rc file carries a block' {
            script:New-Rc $script:h '.zshrc'  | Out-Null
            script:New-Rc $script:h '.bashrc' | Out-Null
            @(Get-UninstallShellRcTarget -HomeDir $script:h).Count | Should -Be 0
        }

        It 'a bound -HomeDir still suppresses the ambient ZDOTDIR' {
            # The rule Get-ShellRcCandidate documents: -HomeDir means a sandbox,
            # and it has to survive every hop or a test run reaches into the
            # developer's own zsh config. Asserted here because this function
            # adds one more hop to survive.
            $zdot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $zdot -Force | Out-Null
            script:New-Rc $zdot '.zshrc' -WithBlock | Out-Null

            $prev = $env:ZDOTDIR
            try {
                $env:ZDOTDIR = $zdot
                @(Get-UninstallShellRcTarget -HomeDir $script:h).Count |
                    Should -Be 0 -Because 'the sandboxed home said nothing about a zsh config dir'
            } finally { $env:ZDOTDIR = $prev }
        }
    }
}

Describe 'the uninstall consent listing names what it will change' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:h -Force | Out-Null
            # Refuse, always. Nothing past the prompt may run on this machine.
            Mock Confirm-Action { $false }
        }

        It 'names the rc file carrying the loader, and cancels' {
            $rc = script:New-Rc $script:h '.zshrc' -WithBlock
            $before = [System.IO.File]::ReadAllBytes($rc)

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h 6>&1 | Out-String

            $out | Should -Match ([regex]::Escape($rc)) `
                -Because 'the prompt must name the file it is about to edit'
            $out | Should -Match 'zsh/bash loader'
            $out | Should -Match 'Cancelled'
            [System.IO.File]::ReadAllBytes($rc) | Should -Be $before `
                -Because 'consent was refused'
        }

        It 'names ~/.profile when that is where the loader went' {
            $rc = script:New-Rc $script:h '.profile' -WithBlock
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h 6>&1 | Out-String
            $out | Should -Match ([regex]::Escape($rc))
        }

        It 'says nothing about shell rc files when none carry a block' {
            script:New-Rc $script:h '.zshrc' | Out-Null
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h 6>&1 | Out-String
            $out | Should -Not -Match 'zsh/bash loader' `
                -Because 'listing files it will not touch would be its own kind of wrong'
        }

        It 'still names the PowerShell side' {
            # The bullet that was already right must survive the new one.
            script:New-Rc $script:h '.zshrc' -WithBlock | Out-Null
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h 6>&1 | Out-String
            $out | Should -Match 'Windows PowerShell 5\.1'
        }
    }
}

Describe 'help describes the files these commands really touch' {
    InModuleScope TerminalStyles {
        It 'uninstall help mentions the shell rc side, not just $PROFILE' {
            $d = (Get-TerminalStyleHelpData | Where-Object Name -eq 'uninstall').Detail -join ' '
            $d | Should -Match 'zsh/bash' -Because 'uninstall strips that block too'
        }

        It 'shell-init help names ~/.profile, which it can write to' {
            $d = (Get-TerminalStyleHelpData | Where-Object Name -eq 'shell-init').Detail -join ' '
            $d | Should -Match '~/\.profile'
        }
    }
}
