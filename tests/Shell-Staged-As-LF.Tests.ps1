# PSGallery 0.8.32 and 0.8.33 shipped every .sh with CRLF, and a CR is part of
# the token to zsh and bash:
#
#   tstyles.sh:37: command not found: ^M
#   tstyles.sh:41: parse error near `in^M'
#
# on every interactive shell. Three guards were added afterwards and every one
# sits upstream: .gitattributes stops a Windows checkout converting the file,
# tests/Shell-Files-Are-LF pins the repo, and scripts/publish.ps1 refuses to
# publish a package carrying one.
#
# None of them protects a machine that ALREADY has a bad copy, and none runs at
# the moment the bytes land in someone's home directory. That gap matters
# because the failure blocks its own cure -- the `tstyles` shell function is
# defined by the file that is broken, so `tstyles update` from zsh cannot run.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Copy-ShellFileAsLf' {
    InModuleScope TerminalStyles {

        BeforeEach {
            $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("lf-" + [Guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
            $script:Src = Join-Path $script:Dir 'in.sh'
            $script:Dst = Join-Path $script:Dir 'out.sh'
        }
        AfterEach {
            if (Test-Path -LiteralPath $script:Dir) {
                Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'strips a CR from every line, not just the last' {
            # 0.8.32 had one on every line. TrimEnd would have fixed the file's
            # tail and left thirty-six broken lines above it.
            [System.IO.File]::WriteAllText($script:Src, "one`r`ntwo`r`nthree`r`n")
            Copy-ShellFileAsLf -Source $script:Src -Destination $script:Dst
            $bytes = [System.IO.File]::ReadAllBytes($script:Dst)
            $bytes | Should -Not -Contain 13
            ([System.IO.File]::ReadAllText($script:Dst)) | Should -Be "one`ntwo`nthree`n"
        }

        It 'leaves a file that is already LF byte-identical' {
            $lf = "#!/bin/sh`necho hi`n"
            [System.IO.File]::WriteAllText($script:Src, $lf)
            Copy-ShellFileAsLf -Source $script:Src -Destination $script:Dst
            [System.IO.File]::ReadAllText($script:Dst) | Should -Be $lf
        }

        It 'handles a lone CR, not only CRLF' {
            # Classic-Mac endings are rarer but break a shell script identically.
            [System.IO.File]::WriteAllText($script:Src, "one`rtwo`rthree")
            Copy-ShellFileAsLf -Source $script:Src -Destination $script:Dst
            [System.IO.File]::ReadAllBytes($script:Dst) | Should -Not -Contain 13
            [System.IO.File]::ReadAllText($script:Dst) | Should -Be "one`ntwo`nthree"
        }

        It 'writes no BOM' {
            # A BOM at the top of a sourced script is the same class of bug in
            # a different disguise: the shell reads it as part of the first token.
            [System.IO.File]::WriteAllText($script:Src, "echo hi`n")
            Copy-ShellFileAsLf -Source $script:Src -Destination $script:Dst
            $b = [System.IO.File]::ReadAllBytes($script:Dst)
            ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeFalse
        }

        It 'keeps non-ASCII content intact' {
            $text = "echo 'café — naïve'`n"
            [System.IO.File]::WriteAllText($script:Src, $text, [System.Text.UTF8Encoding]::new($false))
            Copy-ShellFileAsLf -Source $script:Src -Destination $script:Dst
            [System.IO.File]::ReadAllText($script:Dst, [System.Text.UTF8Encoding]::new($false)) |
                Should -Be $text
        }
    }
}

Describe 'Sync-ShellRuntime' {
    InModuleScope TerminalStyles {

        BeforeEach {
            # Both roots sandboxed. CLAUDE.md is explicit that overriding the
            # data root alone is not containment -- several paths resolve rc
            # files from the live $HOME -- but Sync-ShellRuntime writes only
            # under the data root and reads only from the module root, so
            # pointing both at a temp directory is enough for THIS function.
            $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("sync-" + [Guid]::NewGuid())
            $script:FakeModule = Join-Path $script:Sandbox 'module'
            New-Item -ItemType Directory -Path (Join-Path $script:FakeModule 'shell') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:Sandbox 'data') -Force | Out-Null
            $script:OldData = $script:TStylesDataRoot
            $script:OldModule = $script:TStylesModuleRoot
            $script:TStylesDataRoot = Join-Path $script:Sandbox 'data'
            $script:TStylesModuleRoot = $script:FakeModule
            Copy-Item -LiteralPath (Join-Path $script:OldModule 'TerminalStyles.psd1') `
                      -Destination (Join-Path $script:FakeModule 'TerminalStyles.psd1') -Force
        }
        AfterEach {
            $script:TStylesDataRoot = $script:OldData
            $script:TStylesModuleRoot = $script:OldModule
            if (Test-Path -LiteralPath $script:Sandbox) {
                Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'stages a CRLF source as LF' {
            # The behaviour, not the source text: a byte copy reproduces
            # faithfully whatever it is given, which is exactly how a CRLF
            # module reached a user's home directory in 0.8.32.
            $src = Join-Path (Join-Path $script:FakeModule 'shell') 'tstyles.sh'
            [System.IO.File]::WriteAllText($src, "ts_hi() {`r`n  echo hi`r`n}`r`n")
            (Sync-ShellRuntime) | Should -Be 'ok'
            $staged = Get-ShellRuntimePath
            Test-Path -LiteralPath $staged | Should -BeTrue
            [System.IO.File]::ReadAllBytes($staged) | Should -Not -Contain 13 `
                -Because 'a CR is part of the token to zsh: command not found: ^M'
        }

        It 'leaves an LF source unchanged' {
            $src = Join-Path (Join-Path $script:FakeModule 'shell') 'tstyles.sh'
            $lf = "ts_hi() {`n  echo hi`n}`n"
            [System.IO.File]::WriteAllText($src, $lf)
            (Sync-ShellRuntime) | Should -Be 'ok'
            [System.IO.File]::ReadAllText((Get-ShellRuntimePath)) | Should -Be $lf
        }

        It 'still reports nosource when the module ships no shell script' {
            # The status vocabulary is load-bearing here -- 'nosource' and
            # 'failed' were one boolean once, and the caller named the wrong
            # cause for both.
            (Sync-ShellRuntime) | Should -Be 'nosource'
        }
    }
}
