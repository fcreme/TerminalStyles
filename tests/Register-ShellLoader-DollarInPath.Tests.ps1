# Pester 5 tests: the rc loader refresh writes the data-root path as it is.
#
# Register-ShellLoader refreshed a block already in the file with
# [regex]::Replace and passed the new block as the REPLACEMENT string, where `$`
# is special: `$_` is the whole input, `$&`, `$0`, `${0}` and `$+` the match,
# `` $` `` and `$'` the text before and after it, `$$` one `$`. The block
# carries the data-root path, so one of those in a home or XDG path copied the
# rc file or the old block into the quoted path, or wrote it one `$` short, and
# said 'updated'. The expected text is built independently of the code under
# test (the literal path line), and the full-file oracle rejects a no-op.
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

Describe 'the loader refresh writes the data-root path as it is' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:dir)
            $script:user = "# my rc`nexport EDITOR=vim`n"
            $script:tail = "alias gs='git status'`n"
            $script:enc  = [System.Text.UTF8Encoding]::new($false)
            # The 0.8.0-0.8.17 block, which differs from the current one and so
            # takes the refresh on a plain shell-init.
            $script:oldBlock = {
                param([string]$Runtime)
                "# ===== TerminalStyles BEGIN =====`n[ -r `"$Runtime`" ] && . `"$Runtime`"`n# ===== TerminalStyles END ====="
            }
            # The line the block must carry, built from the path alone.
            $script:literalLine = {
                param([string]$Runtime)
                $q = $Runtime.Replace("'", "'\''")
                "if [ -r '$q' ]; then . '$q'; fi"
            }
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedRoot
        }

        # The eight substitution tokens, and three that were always literal
        # (they pin that the escape changes nothing that was right before).
        It 'refreshes a 0.8.17 block to the literal path when the data root holds <token>' -ForEach @(
            @{ token = '$_' }, @{ token = '$&' }, @{ token = '$0' }, @{ token = '${0}' },
            @{ token = '$+' }, @{ token = '$`' }, @{ token = "`$'" }, @{ token = '$$' },
            @{ token = '$1' }, @{ token = '${x}' }, @{ token = 'end$' }
        ) {
            # Never created: Register-ShellLoader only reads the string.
            $script:TStylesDataRoot = Join-Path $script:dir ('odd' + $token + 'dir')
            $runtime = Join-Path $script:TStylesDataRoot 'tstyles.sh'
            $rc = Join-Path $script:dir '.bashrc'
            [System.IO.File]::WriteAllText($rc, $script:user + (& $script:oldBlock $runtime) + "`n" + $script:tail, $script:enc)

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'updated'

            $after = [System.IO.File]::ReadAllText($rc, $script:enc)
            $after.Contains((& $script:literalLine $runtime)) | Should -BeTrue -Because 'the path is written as it is, not expanded by .NET'
            [regex]::Matches($after, [regex]::Escape('# ===== TerminalStyles BEGIN =====')).Count | Should -Be 1
            $after | Should -BeExactly ($script:user + (Get-ShellLoaderBlock).Trim() + "`n" + $script:tail)

            Register-ShellLoader -Path $rc 6>$null | Should -Be 'unchanged'
            [System.IO.File]::ReadAllText($rc, $script:enc) | Should -BeExactly $after
        }

        It 'leaves a current block byte-identical under -Force when the data root holds <token>' -ForEach @(
            @{ token = '$_' }, @{ token = '$&' }, @{ token = '$0' }, @{ token = '${0}' },
            @{ token = '$+' }, @{ token = '$`' }, @{ token = "`$'" }, @{ token = '$$' }
        ) {
            $script:TStylesDataRoot = Join-Path $script:dir ('odd' + $token + 'dir')
            $runtime = Join-Path $script:TStylesDataRoot 'tstyles.sh'
            $rc = Join-Path $script:dir '.zshrc'
            [System.IO.File]::WriteAllText($rc, $script:user, $script:enc)
            Register-ShellLoader -Path $rc 6>$null | Should -Be 'added' -Because 'the fixture must plant a real block'
            [System.IO.File]::AppendAllText($rc, $script:tail, $script:enc)
            $planted = [System.IO.File]::ReadAllText($rc, $script:enc)
            $planted.Contains((& $script:literalLine $runtime)) | Should -BeTrue -Because 'the append writes the path as it is'

            Register-ShellLoader -Path $rc -Force 6>$null | Should -Be 'updated'

            [System.IO.File]::ReadAllText($rc, $script:enc) | Should -BeExactly $planted `
                -Because 'a -Force refresh of the current block changes nothing'
        }

        It 'shell-init over 0.8.17 blocks writes each one as it is, says updated, then unchanged' {
            $h = Join-Path $script:dir 'home'
            [void][System.IO.Directory]::CreateDirectory($h)
            # A real directory: Sync-ShellRuntime writes the runtime into it.
            $root = Join-Path (Join-Path $script:dir 'data') 'odd$_dir'
            [void][System.IO.Directory]::CreateDirectory($root)
            $script:TStylesDataRoot = $root
            $runtime = Join-Path $root 'tstyles.sh'
            $files = @('.zshrc', '.bashrc', '.bash_profile')
            foreach ($f in $files) {
                [System.IO.File]::WriteAllText((Join-Path $h $f),
                    "# original $f`n" + (& $script:oldBlock $runtime) + "`n" + $script:tail, (Get-RcFileEncoding))
            }

            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/bash'
                $out = Invoke-TerminalStylesShellInit -HomeDir $h 6>&1 | Out-String -Width 500
                foreach ($f in $files) {
                    $p = Join-Path $h $f
                    $out | Should -Match ('updated\s+' + [regex]::Escape($p))
                    (Read-RcFileText -Path $p).Text |
                        Should -BeExactly ("# original $f`n" + (Get-ShellLoaderBlock).Trim() + "`n" + $script:tail)
                }
                $again = Invoke-TerminalStylesShellInit -HomeDir $h 6>&1 | Out-String -Width 500
                foreach ($f in $files) {
                    $again | Should -Match ('unchanged\s+' + [regex]::Escape((Join-Path $h $f)))
                }
            } finally { $env:SHELL = $prev }
        }
    }
}
