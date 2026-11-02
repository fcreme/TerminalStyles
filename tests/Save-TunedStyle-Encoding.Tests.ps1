# Pester 5 tests: saving a tune keeps the bytes of the profile.ps1 it carries.
#
# To append its `# tstyles-tuned:` marker, Save-TunedStyle read the base's
# profile.ps1 as UTF-8 and wrote it back as UTF-8 with no byte-order mark, ever
# since the tuner shipped in 0.3.0. An Overwrite of a style the user made tunes
# that style as its own base, so this rewrote the user's own file in place: a
# byte that is not valid UTF-8 became U+FFFD for good, and a UTF-8, UTF-16 or
# UTF-32 mark was dropped -- the mark Windows PowerShell 5.1 needs to read
# UTF-8 text in a .ps1. It now reads through Read-RcFileText and writes back
# with the Encoding that read chose.
#
# Expected bytes are built here with System.Text encoders, never with
# Read-RcFileText, so the oracle does not share the code under test.
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

Describe 'Save-TunedStyle keeps the bytes of the profile.ps1 it copies' {
    InModuleScope TerminalStyles {
        BeforeAll {
            function script:Hex { param([byte[]]$Bytes) ($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ' }
            # A box pair and an em dash inside a double-quoted string, and a
            # last line ending in a star, whose UTF-8 ends in 0x85.
            $script:text = 'Write-Host "' + [char]0x2500 + [char]0x2500 + ' mine ' + [char]0x2014 + '"' + "`r`n" + '# ' + [char]0x2605
            $script:nl = [Environment]::NewLine
            $script:utf8 = [System.Text.UTF8Encoding]::new($false)

            # A style directory whose profile.ps1 holds exactly $Bytes.
            function script:New-StyleDir {
                param([string]$Path, [byte[]]$Bytes)
                [void][System.IO.Directory]::CreateDirectory($Path)
                [System.IO.File]::WriteAllText((Join-Path $Path 'theme.json'), '{"colorScheme":"x","opacity":100}', $script:utf8)
                [System.IO.File]::WriteAllText((Join-Path $Path 'scheme.json'), '{"name":"x","background":"#000000"}', $script:utf8)
                [System.IO.File]::WriteAllBytes((Join-Path $Path 'profile.ps1'), $Bytes)
            }
            function script:Save {
                param([string]$SaveName, [string]$BaseDir, [string]$BaseName)
                [void](Save-TunedStyle -AdjustedScheme ([pscustomobject]@{ name = 'x'; background = '#000000' }) `
                    -SaveName $SaveName -BaseStyleDir $BaseDir -BaseName $BaseName -OpenedStyleDir $BaseDir `
                    -Brightness 5 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12)
            }
            # How Windows PowerShell 5.1 reads a .ps1: by its byte-order mark,
            # else in the ANSI code page (fixed at 1252 so every leg agrees).
            function script:ParseErrorsAs51 {
                param([byte[]]$Bytes)
                $reader = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($Bytes), [System.Text.Encoding]::GetEncoding(1252), $true)
                try { $src = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $errors = $null
                [void][System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$errors)
                @($errors).Count
            }
        }
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:mineDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'mine'
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It "an Overwrite leaves the user's own profile.ps1 in <Label> as it was, plus the marker line, on every save" -ForEach @(
            @{ Label = 'UTF-8 with a byte-order mark'; Kind = 'utf8bom' }
            @{ Label = 'UTF-8 without one';            Kind = 'utf8' }
            @{ Label = 'UTF-16LE';                     Kind = 'utf16le' }
            @{ Label = 'UTF-16BE';                     Kind = 'utf16be' }
            @{ Label = 'UTF-32LE';                     Kind = 'utf32le' }
            @{ Label = 'UTF-32BE';                     Kind = 'utf32be' }
        ) {
            $enc = switch ($Kind) {
                'utf8bom' { [System.Text.UTF8Encoding]::new($true) }
                'utf8'    { [System.Text.UTF8Encoding]::new($false) }
                'utf16le' { [System.Text.UnicodeEncoding]::new($false, $true) }
                'utf16be' { [System.Text.UnicodeEncoding]::new($true, $true) }
                'utf32le' { [System.Text.UTF32Encoding]::new($false, $true) }
                'utf32be' { [System.Text.UTF32Encoding]::new($true, $true) }
            }
            $fixture = [byte[]]($enc.GetPreamble() + $enc.GetBytes($script:text + "`r`n"))
            New-StyleDir -Path $script:mineDir -Bytes $fixture
            if ($Kind -ne 'utf8') { $enc.GetPreamble().Count | Should -BeGreaterThan 0 -Because 'the fixture must carry its mark' }

            $expected = [byte[]]($enc.GetPreamble() + $enc.GetBytes($script:text + $script:nl + '# tstyles-tuned: mine' + $script:nl))
            foreach ($round in 1, 2) {
                Save -SaveName 'mine' -BaseDir $script:mineDir -BaseName 'mine'
                Hex ([System.IO.File]::ReadAllBytes((Join-Path $script:mineDir 'profile.ps1'))) |
                    Should -BeExactly (Hex $expected) -Because "save $round"
            }
        }

        It 'an Overwrite leaves bytes that are not UTF-8 as they were' {
            # The ANSI code page: e-acute as E9, and a line ending in a
            # no-break space, A0, which a bare TrimEnd() would also take.
            $ascii = [System.Text.Encoding]::ASCII
            $fixture = [byte[]](@(0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A) + $ascii.GetBytes("Write-Host 'x'") + @(0x20, 0xA0, 0x0D, 0x0A))
            { [System.Text.UTF8Encoding]::new($false, $true).GetString($fixture) } | Should -Throw -Because 'the fixture must not be valid UTF-8'
            New-StyleDir -Path $script:mineDir -Bytes $fixture

            $expected = [byte[]]($fixture[0..($fixture.Length - 3)] + $script:utf8.GetBytes($script:nl + '# tstyles-tuned: mine' + $script:nl))
            foreach ($round in 1, 2) {
                Save -SaveName 'mine' -BaseDir $script:mineDir -BaseName 'mine'
                Hex ([System.IO.File]::ReadAllBytes((Join-Path $script:mineDir 'profile.ps1'))) |
                    Should -BeExactly (Hex $expected) -Because "save $round"
            }
        }

        It "a Save As copy keeps the base's UTF-8 byte-order mark, and the base stays as it was" {
            $bom = [System.Text.UTF8Encoding]::new($true)
            $fixture = [byte[]]($bom.GetPreamble() + $bom.GetBytes($script:text + "`r`n"))
            $baseDir = Join-Path (Join-Path $script:TStylesDataRoot 'base') 'mine'
            New-StyleDir -Path $baseDir -Bytes $fixture

            Save -SaveName 'mine-bright' -BaseDir $baseDir -BaseName 'mine'

            $copy = Join-Path (Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'mine-bright') 'profile.ps1'
            Hex ([System.IO.File]::ReadAllBytes($copy)) |
                Should -BeExactly (Hex ([byte[]]($bom.GetPreamble() + $bom.GetBytes($script:text + $script:nl + '# tstyles-tuned: mine-bright' + $script:nl))))
            Hex ([System.IO.File]::ReadAllBytes((Join-Path $baseDir 'profile.ps1'))) | Should -BeExactly (Hex $fixture)
        }

        It 'writes the marker of a style whose name is not ASCII as the UTF-8 it has always been' {
            # An Overwrite keeps the name of a folder the user made.
            $name = 'caf' + [char]0xE9 + [char]0x65E5
            $bom = [System.Text.UTF8Encoding]::new($true)
            $dir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $name
            New-StyleDir -Path $dir -Bytes ([byte[]]($bom.GetPreamble() + $bom.GetBytes($script:text + "`r`n")))

            Save -SaveName $name -BaseDir $dir -BaseName $name

            Hex ([System.IO.File]::ReadAllBytes((Join-Path $dir 'profile.ps1'))) |
                Should -BeExactly (Hex ([byte[]]($bom.GetPreamble() + $bom.GetBytes($script:text) + $script:utf8.GetBytes($script:nl + '# tstyles-tuned: ' + $name + $script:nl))))
        }

        It 'the tuned copy reads the way Windows PowerShell 5.1 reads a script, as its base does' {
            $bom = [System.Text.UTF8Encoding]::new($true)
            $fixture = [byte[]]($bom.GetPreamble() + $bom.GetBytes($script:text + "`r`n"))
            ParseErrorsAs51 $fixture | Should -Be 0 -Because 'control: the marked base reads cleanly'
            ParseErrorsAs51 ([byte[]]$script:utf8.GetBytes($script:text + "`r`n")) | Should -BeGreaterThan 0 `
                -Because 'control: without the mark, the em dash carries a byte 5.1 reads as a closing quote'
            $baseDir = Join-Path (Join-Path $script:TStylesDataRoot 'base') 'mine'
            New-StyleDir -Path $baseDir -Bytes $fixture

            Save -SaveName 'mine-bright' -BaseDir $baseDir -BaseName 'mine'

            $copy = Join-Path (Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'mine-bright') 'profile.ps1'
            ParseErrorsAs51 ([System.IO.File]::ReadAllBytes($copy)) | Should -Be 0
        }
    }
}
