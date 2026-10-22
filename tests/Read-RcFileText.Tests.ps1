# Pester 5 tests: Read-RcFileText, the one decoder for an rc file or $PROFILE
# the USER owns.
#
# Every writer of those files reads the whole file and writes the whole file
# back, so the decoding has to give back the same bytes for anything the file
# can hold. They all read with [System.IO.File]::ReadAllText(path,
# ISO-8859-1), and that overload looks for a byte-order mark first and decodes
# by it, whatever encoding it is handed. A profile saved as UTF-8 with a BOM,
# or as UTF-16, therefore arrived as Unicode text and went back out through
# ISO-8859-1, which has no byte for anything above U+00FF: the BOM was dropped
# and every prompt glyph became '?'.
#
# These pin the decode table. Each writer's own test file pins that the writer
# uses it: Invoke-TerminalStylesRegister, Remove-PowerShellProfileLoader,
# Install-Hardening, Shell-Integration and Uninstall-ReversesShellInit.
#
# Every glyph is built from [char] codes. Windows PowerShell 5.1 reads a .ps1
# with no BOM in the ANSI code page, where a non-ASCII string literal is a
# parse error.
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

Describe 'Read-RcFileText' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
        }

        # Length, not truthiness: `-not @(0)` is $true, so a one-byte 00
        # would print as nothing.
        function script:Hex([byte[]]$Bytes) {
            if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
            [System.BitConverter]::ToString($Bytes) -replace '-', ''
        }

        # A Latin-1 letter, a prompt glyph, Greek, Cyrillic, CJK, an emoji (a
        # surrogate pair) and a Powerline glyph from the private use area: one
        # of each kind that came back as '?', a look-alike or U+FFFD.
        function script:Text {
            '# caf' + [char]0xE9 + "`r`n'" + [char]0x276F + [char]0x03BB + [char]0x0416 + [char]0x65E5 +
                [char]::ConvertFromUtf32(0x1F680) + [char]0xE0B0 + "'`r`n"
        }

        # Writes the fixture for one row of the table and returns its path.
        # Bytes, never a string: writing it through any encoding at all would
        # decide the answer before the code under test ran.
        #
        # Each arm ASSIGNS rather than outputs: an array a switch arm outputs
        # is unrolled, and the empty one would arrive as $null.
        function script:New-Fixture([string]$Kind) {
            $p = Join-Path $script:d 'profile.ps1'
            $e = $null
            $bytes = [byte[]]@()
            switch ($Kind) {
                'raw'       { $bytes = [byte[]]@(0x23, 0x20, 0x78, 0xF3, 0xE9, 0x85, 0xA0, 0x0A) }
                'utf8bom'   { $e = [System.Text.UTF8Encoding]::new($true) }
                'utf8bomF3' { $bytes = [byte[]]@(0xEF, 0xBB, 0xBF, 0x23, 0x20, 0x78, 0xF3, 0x0A) }
                'utf16le'   { $e = [System.Text.UnicodeEncoding]::new($false, $true) }
                'utf16be'   { $e = [System.Text.UnicodeEncoding]::new($true, $true) }
                'utf32le'   { $e = [System.Text.UTF32Encoding]::new($false, $true) }
                'utf32be'   { $e = [System.Text.UTF32Encoding]::new($true, $true) }
                'empty'     { }
                default     { throw "No fixture kind '$Kind'." }
            }
            if ($e) { $bytes = [byte[]]($e.GetPreamble() + $e.GetBytes((script:Text))) }
            [System.IO.File]::WriteAllBytes($p, $bytes)
            $p
        }

        # CodePage, never WebName: .NET Framework calls big-endian UTF-16
        # 'unicodeFFFE', so a name would differ between the 5.1 leg and the rest.
        It 'hands back text that writes back to the same bytes, for <Label>' -ForEach @(
            @{ Label = 'no byte-order mark, bytes that are not UTF-8'; Kind = 'raw';       CodePage = 28591 }
            @{ Label = 'a UTF-8 byte-order mark';                      Kind = 'utf8bom';   CodePage = 28591 }
            @{ Label = 'a UTF-8 byte-order mark and a stray F3';       Kind = 'utf8bomF3'; CodePage = 28591 }
            @{ Label = 'UTF-16LE';                                     Kind = 'utf16le';   CodePage = 1200 }
            @{ Label = 'UTF-16BE';                                     Kind = 'utf16be';   CodePage = 1201 }
            @{ Label = 'UTF-32LE';                                     Kind = 'utf32le';   CodePage = 12000 }
            @{ Label = 'UTF-32BE';                                     Kind = 'utf32be';   CodePage = 12001 }
            @{ Label = 'an empty file';                                Kind = 'empty';     CodePage = 28591 }
        ) {
            $p = script:New-Fixture $Kind
            $r = Read-RcFileText -Path $p

            # What every writer does with the pair: the Encoding's preamble,
            # then the Text in that Encoding. That has to BE the file.
            $back = [byte[]]($r.Encoding.GetPreamble() + $r.Encoding.GetBytes([string]$r.Text))
            script:Hex $back | Should -BeExactly (script:Hex ([System.IO.File]::ReadAllBytes($p))) `
                -Because 'writing the text back with the encoding it was read in must give the file it came from'
            $r.Encoding.CodePage | Should -Be $CodePage `
                -Because 'UTF-32LE opens with FF FE too, and read as UTF-16LE it is a different file'
            if ($Kind -like 'utf16*' -or $Kind -like 'utf32*') {
                $r.Text.Contains([string][char]0x276F) | Should -BeTrue -Because 'it really decoded, rather than passing bytes through'
                [int]$r.Text[0] | Should -Not -Be 0xFEFF -Because 'the mark is the preamble''s, and in the text too it would be written twice'
            }
        }

        # The design's one lossy case, and the CHANGELOG states it: a code
        # unit that is not valid in the file's own encoding -- usually an ANSI
        # append to a UTF-16 file -- comes back as U+FFFD, which is what
        # PowerShell itself reads there.
        It 'decodes a code unit its UTF-16 encoding cannot represent to U+FFFD, as PowerShell reads it, for <Label>' -ForEach @(
            @{ Label = 'an odd trailing byte'; Bytes = [byte[]]@(0xFF, 0xFE, 0x41, 0x00, 0x42) }
            @{ Label = 'a lone surrogate';     Bytes = [byte[]]@(0xFF, 0xFE, 0x41, 0x00, 0x00, 0xD8, 0x42, 0x00) }
        ) {
            $p = Join-Path $script:d 'profile.ps1'
            [System.IO.File]::WriteAllBytes($p, $Bytes)
            $r = Read-RcFileText -Path $p
            $r.Encoding.CodePage | Should -Be 1200
            [string]$r.Text[0] | Should -BeExactly 'A'
            $r.Text.Contains([string][char]0xFFFD) | Should -BeTrue
        }

        # A writer that goes on after a failed read builds the whole file from
        # nothing, so the helper must STOP a caller that has no try. A bare
        # rethrow, a local $ErrorActionPreference = 'Stop', or no catch at all
        # each end only the caller's statement in an advanced function, and
        # the line after runs with $null. Pester runs every It inside a try,
        # where all of those shapes throw alike; a fresh runspace's top level
        # has no try and the default preference, so it is the one place in
        # here that can tell them apart. In-process on purpose: a child engine
        # would bring stderr, execution policy and engine paths with it.
        #
        # The fixture is a directory, which ReadAllBytes refuses on every
        # platform: no chmod and no ACL, so this runs on all four legs.
        It 'stops a caller that has no try, and names the file it could not read' {
            Get-Command Read-RcFileText -CommandType Function -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because 'the helper has to exist, or the runspace below measures nothing'

            $dir = Join-Path $script:d 'not-a-file'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $good = Join-Path $script:d 'good.txt'
            [System.IO.File]::WriteAllBytes($good, [byte[]]@(0x23, 0x20, 0x78, 0xE9, 0x0A))

            # The module's own text for both functions, so the runspace runs
            # exactly what the writers call.
            $defs = @(foreach ($n in 'Get-RcFileEncoding', 'Read-RcFileText') {
                "function $n {`n$((Get-Command $n -CommandType Function).ScriptBlock)`n}"
            }) -join "`n"
            $quote = { param([string]$s) "'" + $s.Replace("'", "''") + "'" }

            $ps = [powershell]::Create()
            try {
                # Positive control first: in that runspace the helper reads a
                # file, so what happens next is about the failed read and not
                # about a definition that never took.
                [void]$ps.AddScript($defs + "`n[int][char]((Read-RcFileText -Path " + (& $quote $good) + ").Text[3])")
                $first = @($ps.Invoke())
                $first.Count | Should -Be 1 -Because "the definitions must load there (errors: $(@($ps.Streams.Error) -join '; '))"
                [int]$first[0] | Should -Be 0xE9

                $ps.Commands.Clear()
                [void]$ps.AddScript("`$r = Read-RcFileText -Path " + (& $quote $dir) + "; 'CONTINUED'")
                $err = $null
                $out = @()
                try { $out = @($ps.Invoke()) } catch { $err = $_ }
                $err | Should -Not -BeNullOrEmpty `
                    -Because "a caller with no try must stop at the failed read, not go on with nothing (it printed: $($out -join ', '))"
                $err.Exception.Message | Should -Match ('Could not read ' + [regex]::Escape($dir)) `
                    -Because 'the error is the only thing that tells the user which file it was'
            } finally { $ps.Dispose() }
        }
    }
}
