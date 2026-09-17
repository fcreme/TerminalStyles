# Pester 5 tests for Write-SettingsAtomic: writes settings.json via a
# same-directory temp file + atomic replace so a crash/kill mid-write can never
# leave a truncated settings.json, and never leaves the temp file behind.
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

Describe 'Write-SettingsAtomic' {
    InModuleScope TerminalStyles {
        It 'writes the exact content as UTF-8 without BOM' {
            $f = Join-Path $TestDrive 'settings.json'
            Write-SettingsAtomic -Path $f -Json '{"a":1}'
            [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false)) | Should -Be '{"a":1}'
            $bytes = [System.IO.File]::ReadAllBytes($f)
            # No UTF-8 BOM (EF BB BF) prefix.
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }

        It 'preserves a UTF-8 BOM the file it replaces already had' {
            # The snapshot/restore round trip that every Esc path is built on:
            # [File]::ReadAllText builds its StreamReader with
            # detectEncodingFromByteOrderMarks:true NO MATTER which encoding it
            # is handed, so a leading EF BB BF is eaten as an encoding marker
            # and never reaches the string. Writing UTF8Encoding($false) back
            # unconditionally therefore rewrote the user's header -- on the
            # picker's cancel, which tstyles.ps1 and README both call byte-exact,
            # and on the tuner's. The bytes are the file's property, not the
            # caller's: Save-SettingsBackup is a Copy-Item for exactly this
            # reason, and the .bak kept a BOM the live file lost.
            $f = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($f, '{"a":1}', [System.Text.UTF8Encoding]::new($true))
            $before = [System.IO.File]::ReadAllBytes($f)
            ($before[0] -eq 0xEF -and $before[1] -eq 0xBB -and $before[2] -eq 0xBF) |
                Should -BeTrue -Because 'the fixture must really carry a BOM or this case measures nothing'

            $snapshot = [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false))
            [int]$snapshot[0] | Should -Be 123 -Because 'the read strips the BOM; that is the half that cannot be fixed at the reader'

            Write-SettingsAtomic -Path $f -Json $snapshot

            $after = [System.IO.File]::ReadAllBytes($f)
            @(Compare-Object $before $after -SyncWindow 0).Count | Should -Be 0
        }

        It 'adds no BOM to a file that did not have one' {
            $f = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($f, '{"a":1}', [System.Text.UTF8Encoding]::new($false))
            Write-SettingsAtomic -Path $f -Json '{"b":2}'
            $bytes = [System.IO.File]::ReadAllBytes($f)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }

        It 'overwrites an existing file' {
            $f = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($f, '{"old":true}', [System.Text.UTF8Encoding]::new($false))
            Write-SettingsAtomic -Path $f -Json '{"new":true}'
            [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false)) | Should -Be '{"new":true}'
        }

        It 'leaves no temp file behind' {
            $f = Join-Path $TestDrive 'settings.json'
            Write-SettingsAtomic -Path $f -Json '{"a":1}'
            Test-Path -LiteralPath "$f.tstmp" | Should -BeFalse
        }

        It 'replaces an existing file atomically (swaps in a new file, never rewrites in place)' {
            # Regression: File.Replace's 3rd arg (backupFileName) must be a real
            # null. Passing $null makes PowerShell coerce it to '' -> Replace
            # throws "path is empty" -> the catch silently degrades to a
            # non-atomic in-place WriteAllText. We force the atomic path to be
            # observable: hard-link the destination's underlying file before the
            # write. An atomic Replace swaps in a brand-new file, so the original
            # file -- still reachable through the hard link -- keeps its OLD
            # bytes. A non-atomic in-place rewrite writes through the shared
            # file, so the hard link would instead observe the NEW bytes.
            $enc  = [System.Text.UTF8Encoding]::new($false)
            $f    = Join-Path $TestDrive 'settings.json'
            $link = Join-Path $TestDrive 'settings.hardlink.json'
            [System.IO.File]::WriteAllText($f, '{"v":"OLD"}', $enc)
            New-Item -ItemType HardLink -Path $link -Target $f | Out-Null

            Write-SettingsAtomic -Path $f -Json '{"v":"NEW"}'

            [System.IO.File]::ReadAllText($f, $enc)    | Should -Be '{"v":"NEW"}'
            [System.IO.File]::ReadAllText($link, $enc) | Should -Be '{"v":"OLD"}'
        }

        It 'writes THROUGH a symlinked settings.json instead of replacing the link' {
            # The other half of a symmetry fixed in install.ps1's
            # Write-TextFileAtomic, which has the identical Replace shape.
            # Keeping settings.json in a dotfiles repo and linking it into
            # LocalState is the ordinary arrangement on Windows; File.Replace
            # operates on the LINK, so every apply, every picker arrow key,
            # every tuner keystroke and every font write swapped it for a
            # regular file and silently detached the repo copy. Nothing is lost
            # on either side, which is exactly why nobody notices until the next
            # `chezmoi apply` overwrites it.
            $enc   = [System.Text.UTF8Encoding]::new($false)
            $store = Join-Path $TestDrive ('store-' + [guid]::NewGuid().Guid.Substring(0,8))
            New-Item -ItemType Directory -Force -Path $store | Out-Null
            $real  = Join-Path $store 'settings.json'
            [System.IO.File]::WriteAllText($real, '{"v":"REPO"}', $enc)
            $linkDir = Join-Path $TestDrive ('ls-' + [guid]::NewGuid().Guid.Substring(0,8))
            New-Item -ItemType Directory -Force -Path $linkDir | Out-Null
            $link = Join-Path $linkDir 'settings.json'
            try { New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop | Out-Null }
            catch {
                # Run-time, not -Skip:, which is evaluated at discovery and
                # could never see this.
                Set-ItResult -Skipped -Because 'this platform or account cannot create symlinks'
                return
            }

            Write-SettingsAtomic -Path $link -Json '{"v":"NEW"}'

            # -Force: without it Get-Item answers nothing for a path like this
            # on Unix and both sides of the comparison come back $null.
            (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
            [System.IO.File]::ReadAllText($real, $enc) | Should -Be '{"v":"NEW"}' `
                -Because 'the dotfiles copy is the file the link points at'
        }
    }
}
