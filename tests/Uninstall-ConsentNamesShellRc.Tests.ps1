# Pester 5 tests: the uninstall consent listing must name the files it is about
# to change -- the shell rc files, and the $PROFILE of each engine.
#
# BOTH halves, because the listing was wrong in both and was fixed in two
# instalments. The rc bullet came first (below). The $PROFILE bullet above it
# was a literal -- "Strip the loader block from pwsh 7 and Windows PowerShell
# 5.1 $PROFILE files", unconditional, on every platform -- so off Windows it
# named an engine that cannot exist there, named no file at all, and this suite
# pinned that exact string, certifying it green on the macOS and Ubuntu legs.
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
            # The $PROFILE half is resolved by RUNNING each engine, so an
            # unpinned call here reaches the operator's own profile (read-only,
            # but slow, and it would put their real path in the assertions).
            # -ProfileTarget is the seam; this is the second lock on it.
            Mock Get-PowerShellProfileTarget { @() }

            # A $PROFILE of our own, in the sandbox, for the bullet that names
            # the PowerShell side. Only ever listed -- consent is refused.
            $script:fakeProfile = Join-Path $script:h 'Microsoft.PowerShell_profile.ps1'
            [System.IO.File]::WriteAllText($script:fakeProfile,
                "# ===== TerminalStyles BEGIN =====`nImport-Module TerminalStyles`n# ===== TerminalStyles END =====`n",
                [System.Text.UTF8Encoding]::new($false))
            $script:profileTarget = [pscustomobject]@{
                ProfilePath = $script:fakeProfile
                Label       = 'PowerShell 7'
                Labels      = @('PowerShell 7')
            }
        }

        It 'names the rc file carrying the loader, and cancels' {
            $rc = script:New-Rc $script:h '.zshrc' -WithBlock
            $before = [System.IO.File]::ReadAllBytes($rc)

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500

            $out | Should -Match ([regex]::Escape($rc)) `
                -Because 'the prompt must name the file it is about to edit'
            $out | Should -Match 'zsh/bash loader'
            $out | Should -Match 'Cancelled'
            [System.IO.File]::ReadAllBytes($rc) | Should -Be $before `
                -Because 'consent was refused'
        }

        It 'names ~/.profile when that is where the loader went' {
            $rc = script:New-Rc $script:h '.profile' -WithBlock
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Match ([regex]::Escape($rc))
        }

        It 'says nothing about shell rc files when none carry a block' {
            script:New-Rc $script:h '.zshrc' | Out-Null
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'zsh/bash loader' `
                -Because 'listing files it will not touch would be its own kind of wrong'
        }

        It 'names the $PROFILE it is about to strip, by path and by engine' {
            # The bullet that was already there, and was a LITERAL: "Strip the
            # loader block from pwsh 7 and Windows PowerShell 5.1 $PROFILE
            # files", unconditional, on every platform. The rc bullet directly
            # below it prints the real paths; this one named two engines and no
            # file at all, and named them from a list that is only true on
            # Windows.
            script:New-Rc $script:h '.zshrc' -WithBlock | Out-Null

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h `
                       -ProfileTarget @($script:profileTarget) 6>&1 | Out-String -Width 500

            $out | Should -Match ([regex]::Escape($script:fakeProfile)) `
                -Because 'the prompt must name the file it is about to edit'
            $out | Should -Match 'PowerShell 7' `
                -Because 'and say which engine loads out of it'
            $out | Should -Match 'Cancelled'
        }

        It 'never names an engine this platform does not have' {
            # Asserted against the platform's own probe rather than a literal:
            # on Windows "Windows PowerShell 5.1" is a real answer, and on macOS
            # and Linux it is a claim about a binary that cannot exist. The
            # literal is what the old assertion pinned, so two of the four CI
            # legs certified the wrong string green.
            script:New-Rc $script:h '.zshrc' -WithBlock | Out-Null

            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h `
                       -ProfileTarget @($script:profileTarget) 6>&1 | Out-String -Width 500

            # Anchor first. Every assertion below is a Should -Not -Match, and
            # the whole bullet is omitted when the target list is empty -- so
            # without this line the test passes loudest at the moment the
            # listing has stopped naming the file it is about to edit. That is
            # not hypothetical: it is how the single-element unroll at
            # update.ps1's $profileTargets reached CI green on three legs and
            # red on one.
            $out | Should -Match 'Strip the loader block from' `
                -Because 'there is a target, so the bullet must be there to test'

            $labels = @((Get-PowerShellEngineCandidate).Label)
            @($labels).Count | Should -BeGreaterThan 0 -Because 'an empty list would assert nothing'

            # Derived from every platform's own table, not hand-typed. A second
            # copy of the engine list here is the same duplication this test
            # exists to catch, and it would go stale the same way.
            $foreign = @(@('Windows', 'MacOS', 'Linux') |
                         ForEach-Object { Get-PowerShellEngineCandidate -Platform $_ } |
                         ForEach-Object { $_.Label } | Sort-Object -Unique |
                         Where-Object { $labels -notcontains $_ })
            foreach ($absent in $foreign) {
                $out | Should -Not -Match ([regex]::Escape($absent)) `
                    -Because "$absent is not an engine this platform registers"
            }
        }

        It 'says nothing about the PowerShell side when no $PROFILE carries a block' {
            # Same rule as the rc bullet above, which is already pinned on it:
            # an empty list means the bullet is omitted, not printed empty.
            script:New-Rc $script:h '.zshrc' -WithBlock | Out-Null
            $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -ProfileTarget @() 6>&1 | Out-String -Width 500
            $out | Should -Not -Match 'Strip the loader block from' `
                -Because 'there is no $PROFILE to strip it from'
            $out | Should -Match 'zsh/bash loader' -Because 'the rc bullet is unaffected'
        }

        It '-DeleteData names the styles and the trash it empties' {
            # Same rule as the rc files, on the other bullet. That parenthetical
            # bounds itself -- "active style, cached GIFs, throttle stamp" -- so
            # a reader is entitled to treat it as the whole list, and the two
            # things in the data root that nothing can give back were missing
            # from it. `tstyles restore` now presents the trash as a safety net
            # for seven days; this is the one command that empties it early, and
            # it was doing so without naming it.
            $saved = $script:TStylesDataRoot
            try {
                $script:TStylesDataRoot = Join-Path $script:h 'data'
                $out = Invoke-TerminalStylesUninstall -HomeDir $script:h -DeleteData 6>&1 | Out-String -Width 500
                $out | Should -Match 'DELETE the entire'
                $out | Should -Match '(?i)styles you made'
                $out | Should -Match '(?i)trash'
                $out | Should -Match 'Cancelled' -Because 'consent was refused, so nothing ran'
            } finally {
                $script:TStylesDataRoot = $saved
            }
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
            # Asked of the platforms where shell-init really registers rc files.
            # The topic is platform-qualified now -- on Windows it describes the
            # gap instead of promising a styled tab it cannot deliver -- so
            # asking the ambient platform would have meant this assertion
            # testing a different sentence on the two Windows CI legs.
            foreach ($platform in @('MacOS', 'Linux')) {
                $d = (Get-TerminalStyleHelpData -Platform $platform |
                      Where-Object Name -eq 'shell-init').Detail -join ' '
                $d | Should -Match '~/\.profile' `
                    -Because "shell-init can write ~/.profile on $platform, so the topic must name it"
            }
        }
    }
}
