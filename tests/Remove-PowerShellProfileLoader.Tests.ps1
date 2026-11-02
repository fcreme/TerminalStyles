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

        Context 'a $PROFILE saved with a byte-order mark' {
            # Unregister-ShellLoader read with [System.IO.File]::ReadAllText(path,
            # ISO-8859-1), which looks for a byte-order mark first and decodes by
            # it whatever encoding it is handed, and wrote the text back through
            # ISO-8859-1. Measured: status 'removed', no backup, and
            # `ef bb bf 23 20 63 61 66 c3 a9 ..` back as `23 20 63 61 66 e9 ..`,
            # with the prompt glyph U+276F as 3f. Removal takes no copy by the
            # first-touch rule, so nothing could be recovered.
            #
            # Glyphs from [char] codes: 5.1 reads a BOM-less .ps1 in the ANSI
            # code page, where a non-ASCII literal is a parse error.
            It 'strips the block and keeps the BOM and every character, for <Label>' -ForEach @(
                @{ Label = 'UTF-8 with BOM'; Kind = 'utf8bom' }
                @{ Label = 'UTF-16LE';       Kind = 'utf16le' }
            ) {
                $enc = if ($Kind -eq 'utf8bom') { [System.Text.UTF8Encoding]::new($true) }
                       else { [System.Text.UnicodeEncoding]::new($false, $true) }
                $text = '# caf' + [char]0xE9 + "`nfunction prompt { '" + [char]0x276F + [char]0x03BB + ' ' +
                        [char]::ConvertFromUtf32(0x1F680) + " ' }`n"
                $block = "`n# ===== TerminalStyles BEGIN =====`nImport-Module TerminalStyles`n# ===== TerminalStyles END =====`n"
                $kept = [byte[]]($enc.GetPreamble() + $enc.GetBytes($text))
                $p = Join-Path $script:d 'p.ps1'
                [System.IO.File]::WriteAllBytes($p, [byte[]]($kept + $enc.GetBytes($block)))

                $r = Remove-PowerShellProfileLoader -Target @([pscustomobject]@{ ProfilePath = $p; Label = 'PowerShell 7' }) 6>$null

                $r.Removed | Should -Be 1
                @($r.Problems).Count | Should -Be 0
                $after = [System.IO.File]::ReadAllBytes($p)
                # The whole file when it came back shorter -- transcoded to single
                # bytes, say -- so the comparison shows where it differs.
                $head = if ($after.Length -ge $kept.Length) { [byte[]]$after[0..($kept.Length - 1)] } else { $after }
                ([System.BitConverter]::ToString($head) -replace '-', '') |
                    Should -BeExactly ([System.BitConverter]::ToString($kept) -replace '-', '') `
                    -Because 'the byte-order mark and every character of the user''s text are theirs'
                $enc.GetString($after, $kept.Length, $after.Length - $kept.Length) | Should -MatchExactly '^\s*$' `
                    -Because 'the block is gone, and only the line break the strip leaves follows the user''s text'
                @(Get-ChildItem -LiteralPath $script:d -Filter 'p.ps1.bak-*' -Force).Count | Should -Be 0
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

        Context 'a $PROFILE that cannot be read' {
            It 'says it could not read it, and claims no loader in it' {
                $dir = Join-Path $script:d 'p.ps1'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                { [System.IO.File]::ReadAllBytes($dir) } | Should -Throw -Because 'the fixture has to be unreadable on this leg'
                $t = [pscustomobject]@{ ProfilePath = $dir; Label = 'PowerShell 7' }

                { script:Say @($t) } | Should -Not -Throw
                $out = script:Say @($t)
                $out | Should -Match ('could not read ' + [regex]::Escape($dir))
                $out | Should -Not -Match ('could not write ' + [regex]::Escape($dir))
                $out | Should -Not -Match 'The loader is still there'
                @(Get-ChildItem -Force -LiteralPath $dir).Count | Should -Be 0
            }
        }

        Context 'what it reports back to the caller' {
            It 'hands back a $PROFILE it could not read as Unreadable, not as a problem' {
                $ok = script:New-Profile 'a.ps1' ([byte[]]@())
                $dir = Join-Path $script:d 'b.ps1'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                { [System.IO.File]::ReadAllBytes($dir) } | Should -Throw -Because 'the fixture has to be unreadable on this leg'

                $r = Remove-PowerShellProfileLoader -Target @($ok, [pscustomobject]@{ ProfilePath = $dir; Label = 'x' }) 6>$null

                $r.Removed | Should -Be 1
                @($r.Problems).Count | Should -Be 0
                $r.PSObject.Properties.Match('Unreadable').Count | Should -Be 1
                @($r.Unreadable) | Should -Be @($dir)
            }

            # A COUNT was all it reported, and that is the shape of the defect
            # the whole file is about, one level up: 'malformed' and 'failed'
            # were printed per file and then dropped, so uninstall's sign-off
            # had no way to know about them and closed on the unqualified
            # "TerminalStyles uninstalled." with the block still in a file it
            # had just said it could not write. Remove-ShellLoaderBlock, the rc
            # half of the same job, has returned Removed + Problems since it was
            # fixed; this is the other half of that symmetry.
            It 'counts only the profiles it really stripped' {
                $ok   = script:New-Profile 'a.ps1' ([byte[]]@())
                $bad  = script:New-Profile 'b.ps1' ([byte[]]@()) -Malformed
                $none = Join-Path $script:d 'c.ps1'
                [System.IO.File]::WriteAllText($none, "# mine`n")

                $r = Remove-PowerShellProfileLoader -Target @(
                        $ok, $bad, [pscustomobject]@{ ProfilePath = $none; Label = 'x' }) 6>$null
                $r.Removed | Should -Be 1
            }

            It 'hands back every profile still carrying a block' {
                $ok   = script:New-Profile 'a.ps1' ([byte[]]@())
                $bad  = script:New-Profile 'b.ps1' ([byte[]]@()) -Malformed
                $ro   = script:New-Profile 'c.ps1' ([byte[]]@())
                $none = Join-Path $script:d 'd.ps1'
                [System.IO.File]::WriteAllText($none, "# mine`n")
                # IsReadOnly rather than chmod: one .NET attribute on every
                # platform the suite runs on. -Force because the same call on a
                # dotfile fixture returns nothing without it, and an assertion
                # against $null passes while measuring nothing.
                $f = Get-Item -LiteralPath $ro.ProfilePath -Force
                $f.IsReadOnly = $true
                try {
                    $r = Remove-PowerShellProfileLoader -Target @(
                            $ok, $bad, $ro, [pscustomobject]@{ ProfilePath = $none; Label = 'x' }) 6>$null

                    $r.Removed        | Should -Be 1
                    @($r.Problems)    | Should -Contain $bad.ProfilePath
                    @($r.Problems)    | Should -Contain $ro.ProfilePath
                    @($r.Problems).Count | Should -Be 2 `
                        -Because 'a clean strip and a file that never carried a block are not problems'
                } finally { $f.IsReadOnly = $false }
            }

            It 'reports no problems when every profile came out clean' {
                # The other direction: a caller that qualifies its sign-off on
                # this list must not qualify it on the ordinary path.
                $ok = script:New-Profile 'a.ps1' ([byte[]]@())
                $r = Remove-PowerShellProfileLoader -Target @($ok) 6>$null
                @($r.Problems).Count | Should -Be 0
                $r.Removed | Should -Be 1
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
