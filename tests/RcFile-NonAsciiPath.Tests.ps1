# Pester 5 tests: a loader line that carries a path that is not ASCII lands in
# the user's rc file or $PROFILE as UTF-8.
#
# Those files are read and written back one byte per character
# (Get-RcFileEncoding), so their own bytes survive whatever they are. Text the
# writers ADDED went out the same way: a data root under /Users/jos<e-acute>
# put its e-acute into ~/.zshrc as the one byte E9, not C3 A9, and anything
# above U+00FF as '?'. zsh and bash then tested a path that does not exist, and
# the runtime never loaded. Save-TunedStyle already converted its marker line;
# Register-ShellLoader, Invoke-TerminalStylesRegister and the installer's
# Register-LoaderInProfile did not.
#
# Non-ASCII characters are built from code points: a .ps1 without a BOM is read
# in the ANSI code page by Windows PowerShell 5.1.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    # Not reachable from inside InModuleScope, where $script: is the module's;
    # those Its repeat the list.
    $script:Names = @(
        @{ Label = 'Latin-1 letter'; Dir = ('jos' + [char]0x00E9) }
        @{ Label = 'CJK';              Dir = ([string][char]0x65E5 + [char]0x672C) }
    )
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'shell-init writes a non-ASCII data root as UTF-8' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:dir)
            $script:utf8 = [System.Text.UTF8Encoding]::new($false)
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedRoot
        }

        It 'puts the UTF-8 bytes of a <Label> path into the rc file, and calls it unchanged next time' -ForEach @(
            @{ Label = 'Latin-1 letter'; Dir = ('jos' + [char]0x00E9) }
            @{ Label = 'CJK';              Dir = ([string][char]0x65E5 + [char]0x672C) }
        ) {
            # Never created: Register-ShellLoader only reads the string.
            $script:TStylesDataRoot = Join-Path (Join-Path $script:dir $Dir) 'terminalstyles'
            $runtime = Join-Path $script:TStylesDataRoot 'tstyles.sh'
            $rc = Join-Path $script:dir '.zshrc'
            # The user's own line carries a Latin-1 byte, which must stay one.
            $mine = [byte[]]@(0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0A)
            [System.IO.File]::WriteAllBytes($rc, $mine)

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'added'

            $bytes = [System.IO.File]::ReadAllBytes($rc)
            [System.BitConverter]::ToString($bytes, 0, $mine.Length) |
                Should -Be ([System.BitConverter]::ToString($mine)) -Because "the user's own bytes are kept"
            $script:utf8.GetString($bytes, $mine.Length, $bytes.Length - $mine.Length) |
                Should -BeExactly ((Get-ShellLoaderBlock).Trim() + "`n")
            $script:utf8.GetString($bytes).Contains($runtime) | Should -BeTrue

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'unchanged'
            [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($rc)) |
                Should -Be ([System.BitConverter]::ToString($bytes))
        }

        It 'refreshes a block an earlier release wrote as Latin-1' {
            $script:TStylesDataRoot = Join-Path (Join-Path $script:dir ('jos' + [char]0x00E9)) 'terminalstyles'
            $rc = Join-Path $script:dir '.bashrc'
            $latin1 = (Get-ShellLoaderBlock).Trim() + "`n"
            [System.IO.File]::WriteAllText($rc, $latin1, [System.Text.Encoding]::GetEncoding(28591))

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'updated'

            [System.IO.File]::ReadAllText($rc, $script:utf8) | Should -BeExactly $latin1
        }

        It 'writes the path as text into a UTF-16 rc file' {
            # A file read in its own encoding takes the block as text; the
            # UTF-8 conversion is only for a file read one byte per character.
            $script:TStylesDataRoot = Join-Path (Join-Path $script:dir ('jos' + [char]0x00E9)) 'terminalstyles'
            $rc = Join-Path $script:dir '.profile'
            $u16 = [System.Text.UnicodeEncoding]::new($false, $true)
            [System.IO.File]::WriteAllText($rc, "# mine`n", $u16)

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'added'

            [System.IO.File]::ReadAllText($rc, $u16) | Should -BeExactly ("# mine`n" + (Get-ShellLoaderBlock).Trim() + "`n")
        }
    }
}

Describe 'tstyles register writes a non-ASCII bootstrap module path as UTF-8' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedModule = $script:TStylesModuleRoot
            Mock Read-Host { '' }
            # The full-path form is the non-Windows one; on Windows the line
            # names $env:LOCALAPPDATA and carries no path.
            Mock Get-TStylesPlatform { 'macOS' }
        }
        AfterEach { $script:TStylesModuleRoot = $script:savedModule }

        It 'a <Label> module path' -ForEach @(
            @{ Label = 'Latin-1 letter'; Dir = ('jos' + [char]0x00E9) }
            @{ Label = 'CJK';              Dir = ([string][char]0x65E5 + [char]0x672C) }
        ) {
            $root = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))) $Dir
            [void][System.IO.Directory]::CreateDirectory($root)
            Mock Get-TStylesDataRoot { $root }
            $script:TStylesModuleRoot = $root
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap' -Because 'the fixture must set the branch under test'
            $profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $profilePath; Exists = $false; HasLoader = $false }) 6>$null

            $want = 'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $root 'TerminalStyles.psd1')
            [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false)).Contains($want) |
                Should -BeTrue -Because 'pwsh reads a $PROFILE with no byte-order mark as UTF-8'
        }

        It 'replaces a block an earlier release wrote as Latin-1, without -Force' {
            $root = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))) ('jos' + [char]0x00E9)
            [void][System.IO.Directory]::CreateDirectory($root)
            Mock Get-TStylesDataRoot { $root }
            $script:TStylesModuleRoot = $root
            $want = 'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $root 'TerminalStyles.psd1')
            $profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
            $old = "# mine`r`n`r`n# ===== TerminalStyles BEGIN =====`r`n$want`r`n# ===== TerminalStyles END =====`r`n"
            [System.IO.File]::WriteAllText($profilePath, $old, [System.Text.Encoding]::GetEncoding(28591))

            $out = Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $profilePath; Exists = $true; HasLoader = $true }) 6>&1 | Out-String

            $out | Should -Not -Match 'Already registered'
            $after = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
            $after.Contains($want) | Should -BeTrue
            $after.StartsWith('# mine') | Should -BeTrue
            [regex]::Matches($after, 'TerminalStyles BEGIN').Count | Should -Be 1

            $again = Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $profilePath; Exists = $true; HasLoader = $true }) 6>&1 | Out-String
            $again | Should -Match 'Already registered' -Because 'the block it just wrote is current'
            [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false)) | Should -BeExactly $after
        }
    }
}

Describe 'the installer writes a non-ASCII loader line as UTF-8' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'a <Label> install directory' -ForEach $script:Names {
        # Not $dir: variable names ignore case, and that would overwrite $Dir.
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $installDir = Join-Path $base $Dir
        [void][System.IO.Directory]::CreateDirectory((Join-Path $installDir 'styles'))
        $installDir.EndsWith($Dir) | Should -BeTrue -Because 'control: the path carries the case under test'
        $profilePath = Join-Path $base 'profile.ps1'
        $begin = '# ===== TerminalStyles BEGIN ====='
        $end   = '# ===== TerminalStyles END ====='
        $line  = 'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $installDir 'TerminalStyles.psd1')

        Register-LoaderInProfile -ProfilePath $profilePath -Label 'PowerShell 7' -InstallDir $installDir `
            -LoaderBegin $begin -LoaderEnd $end -LoaderBody ($begin + "`r`n" + $line + "`r`n" + $end) 6>$null

        [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false)).Contains($line) |
            Should -BeTrue
    }

    It 'rewrites a block an earlier release wrote as Latin-1' {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $installDir = Join-Path $base ('jos' + [char]0x00E9)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $installDir 'styles'))
        $profilePath = Join-Path $base 'profile.ps1'
        $begin = '# ===== TerminalStyles BEGIN ====='
        $end   = '# ===== TerminalStyles END ====='
        $line  = 'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $installDir 'TerminalStyles.psd1')
        $body  = $begin + "`r`n" + $line + "`r`n" + $end
        [System.IO.File]::WriteAllText($profilePath, "# mine`r`n`r`n" + $body + "`r`n", [System.Text.Encoding]::GetEncoding(28591))

        Register-LoaderInProfile -ProfilePath $profilePath -Label 'PowerShell 7' -InstallDir $installDir `
            -LoaderBegin $begin -LoaderEnd $end -LoaderBody $body 6>$null

        $after = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
        $after.Contains($line) | Should -BeTrue
        [regex]::Matches($after, 'TerminalStyles BEGIN').Count | Should -Be 1
    }
}
