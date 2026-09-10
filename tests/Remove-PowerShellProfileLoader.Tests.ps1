# Pester 5 tests: uninstall's $PROFILE strip, which was a second, open-coded
# copy of Unregister-ShellLoader that never received any of the fixes that one
# did.
#
# A $PROFILE is a file the USER owns and that predates us, exactly like an rc
# file, and uninstall reads the whole of it and writes the whole of it back.
# Three defects followed from having two implementations of that:
#
#   1. ENCODING. It read and wrote through UTF-8. Get-RcFileEncoding is
#      ISO-8859-1 precisely because that round-trips every byte 0-255
#      unchanged; UTF-8 decodes a latin-1 comment to U+FFFD and writes the
#      replacement character back. Measured on a $PROFILE opening with
#      `# caf\xe9`: byte e9 came back as ef bf bd, permanently -- and removal
#      takes no backup, because the FIRST TOUCH rule deliberately skips a file
#      that already carries our block.
#   2. MALFORMED. A BEGIN with no END left the string unchanged, so nothing was
#      written AND nothing was said, while the command signed off with "Open a
#      new pwsh tab to confirm the loader is gone."
#   3. UNWRITABLE. The write was unguarded, so a read-only $PROFILE threw out of
#      the middle of uninstall -- after the module and the rc blocks were gone,
#      before the user-state step ran.
#
# None of it was ever exercised, because the paths came from RUNNING each
# engine: the only $PROFILE a test could reach was the operator's own. That is
# what -Target is for, and nothing here goes near a real profile.
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

Describe 'Remove-PowerShellProfileLoader' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
        }

        # Bytes, not a string: the whole point of these tests is what survives
        # the round trip, and writing the fixture through any encoding at all
        # would decide the answer before the code under test ran.
        # Host output only. The function also RETURNS a count, and a bare 6>&1
        # capture mixes the two -- the first draft asserted on '0' and failed
        # on output that was correct.
        function script:Say([object[]]$T) {
            @(Remove-PowerShellProfileLoader -Target $T 6>&1 |
              Where-Object { $_ -is [System.Management.Automation.InformationRecord] }) -join "`n"
        }

        function script:New-Profile([string]$Name, [byte[]]$Lead, [switch]$Malformed) {
            $p = Join-Path $script:d $Name
            $body = if ($Malformed) {
                "# ===== TerminalStyles BEGIN =====`nImport-Module TerminalStyles`n"
            } else {
                "# ===== TerminalStyles BEGIN =====`nImport-Module TerminalStyles`n# ===== TerminalStyles END =====`nfunction prompt { 'hi> ' }`n"
            }
            [System.IO.File]::WriteAllBytes($p, ([byte[]]$Lead + [System.Text.Encoding]::ASCII.GetBytes($body)))
            [pscustomobject]@{ ProfilePath = $p; Label = 'PowerShell 7' }
        }

        Context 'a $PROFILE the user owns' {
            It 'removes the block and reports it' {
                $t = script:New-Profile 'p.ps1' ([byte[]]@())
                script:Say @($t) | Should -Match 'Removed loader from'
                [System.IO.File]::ReadAllText($t.ProfilePath) | Should -Not -Match 'TerminalStyles BEGIN'
            }

            It 'keeps the rest of the file' {
                $t = script:New-Profile 'p.ps1' ([byte[]]@())
                Remove-PowerShellProfileLoader -Target @($t) 6>&1 | Out-Null
                [System.IO.File]::ReadAllText($t.ProfilePath) | Should -Match "function prompt"
            }

            It 'says nothing about a $PROFILE that carries no block' {
                $p = Join-Path $script:d 'clean.ps1'
                [System.IO.File]::WriteAllText($p, "# just mine`n")
                script:Say @([pscustomobject]@{ ProfilePath = $p; Label = 'x' }) |
                    Should -BeNullOrEmpty -Because "'none' is the ordinary case for an engine never registered"
                [System.IO.File]::ReadAllText($p) | Should -Be "# just mine`n"
            }
        }

        Context 'a byte that is not valid UTF-8' {
            It 'leaves every other byte in the file exactly as it was' {
                # 0xE9 -- "e" acute in latin-1, in a comment the user wrote.
                # Through UTF-8 this came back as ef bf bd, the replacement
                # character, and there is no backup on the removal path.
                $t = script:New-Profile 'p.ps1' ([byte[]]@(0x23,0x20,0x63,0x61,0x66,0xE9,0x0A))
                Remove-PowerShellProfileLoader -Target @($t) 6>&1 | Out-Null

                $after = [System.IO.File]::ReadAllBytes($t.ProfilePath)
                $after[0..6] | Should -Be ([byte[]]@(0x23,0x20,0x63,0x61,0x66,0xE9,0x0A)) `
                    -Because 'the user wrote that byte and did not ask us to change it'
                $after | Should -Not -Contain 0xFD -Because 'ef bf bd is U+FFFD, the corruption'
            }
        }

        Context 'a block with BEGIN and no END' {
            It 'says so loudly instead of silently doing nothing' {
                # The command signs off with "Open a new pwsh tab to confirm the
                # loader is gone", so silence here is worse than an error.
                $t = script:New-Profile 'p.ps1' ([byte[]]@()) -Malformed
                $out = script:Say @($t)

                $out | Should -Match 'no matching END'
                $out | Should -Match 'by hand'
                $out | Should -Not -Match 'Removed loader from'
            }

            It 'leaves the file alone' {
                $t = script:New-Profile 'p.ps1' ([byte[]]@()) -Malformed
                $before = [System.IO.File]::ReadAllBytes($t.ProfilePath)
                Remove-PowerShellProfileLoader -Target @($t) 6>&1 | Out-Null
                [System.IO.File]::ReadAllBytes($t.ProfilePath) | Should -Be $before
            }
        }

        Context 'a $PROFILE that cannot be written' {
            It 'reports it and does not throw out of the middle of an uninstall' {
                # The nix / chezmoi store case. Unguarded, this threw after the
                # module and the rc blocks were already gone and before the
                # user-state step ran.
                # IsReadOnly rather than chmod: it is one .NET attribute on
                # every platform the suite runs on, where chmod is an external
                # binary that happens to be on the Windows runners because Git
                # for Windows ships it.
                $t = script:New-Profile 'p.ps1' ([byte[]]@())
                $f = Get-Item -LiteralPath $t.ProfilePath -Force
                $f.IsReadOnly = $true
                try {
                    { script:Say @($t) } | Should -Not -Throw `
                        -Because 'it throws out of the middle of an uninstall otherwise'
                    script:Say @($t) | Should -Match 'could not write'
                    [System.IO.File]::ReadAllText($t.ProfilePath) |
                        Should -Match 'TerminalStyles BEGIN' -Because 'the loader really is still there'
                } finally { $f.IsReadOnly = $false }
            }
        }

        Context 'the count it returns' {
            It 'counts only the profiles it really stripped' {
                $ok   = script:New-Profile 'a.ps1' ([byte[]]@())
                $bad  = script:New-Profile 'b.ps1' ([byte[]]@()) -Malformed
                $none = Join-Path $script:d 'c.ps1'
                [System.IO.File]::WriteAllText($none, "# mine`n")

                $n = Remove-PowerShellProfileLoader -Target @(
                        $ok, $bad, [pscustomobject]@{ ProfilePath = $none; Label = 'x' }) 6>$null
                $n | Should -Be 1
            }
        }
    }
}

Describe 'tstyles register writes a $PROFILE through the same encoding' {
    InModuleScope TerminalStyles {
        It 'does not corrupt a byte that is not valid UTF-8' {
            # register has the same read-whole/write-whole shape, and had the
            # same UTF-8. It does take a first-touch backup -- Copy-Item, so the
            # backup itself is fine -- but the live file was still rewritten
            # with the user's byte replaced.
            $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            $p = Join-Path $d 'profile.ps1'
            [System.IO.File]::WriteAllBytes($p, [byte[]]@(0x23,0x20,0x63,0x61,0x66,0xE9,0x0A))

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                ProfilePath = $p; Exists = $true; HasLoader = $false; Label = 'PowerShell 7'
            }) 6>&1 | Out-Null

            # The user's TEXT, not the line terminator: register joins with
            # "`r`n" by its own design, and that is not what is under test here.
            $after = [System.IO.File]::ReadAllBytes($p)
            $after[0..5] | Should -Be ([byte[]]@(0x23,0x20,0x63,0x61,0x66,0xE9))
            $after | Should -Not -Contain 0xFD -Because 'ef bf bd is U+FFFD, the corruption'
            [System.IO.File]::ReadAllText($p) | Should -Match 'TerminalStyles BEGIN'
        }
    }
}
