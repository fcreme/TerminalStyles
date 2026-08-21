#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Install-Font' {
    InModuleScope TerminalStyles {
        # Copying into the per-user font dir is the whole install on macOS
        # (CoreText scans ~/Library/Fonts live) and on Linux; Windows needs an
        # HKCU registration on top. So the copy is asserted everywhere and the
        # registry half only where a registry exists.
        It 'copies font files to the per-user dir' {
            $src = Join-Path $TestDrive 'Fake-Regular.ttf'
            [System.IO.File]::WriteAllText($src, 'FAKE')
            $fontsDir = Join-Path $TestDrive 'UserFonts'

            $n = Install-Font -FontFiles @($src) -FontsDir $fontsDir
            $n | Should -Be 1
            Test-Path -LiteralPath (Join-Path $fontsDir 'Fake-Regular.ttf') | Should -BeTrue
        }

        It 'writes HKCU registry values' -Skip:((Get-TStylesPlatform) -ne 'Windows') {
            $src = Join-Path $TestDrive 'Fake-Reg.ttf'
            [System.IO.File]::WriteAllText($src, 'FAKE')
            $fontsDir = Join-Path $TestDrive 'UserFontsReg'
            $regRoot  = 'HKCU:\Software\TerminalStylesTest\Fonts'
            try {
                $n = Install-Font -FontFiles @($src) -FontsDir $fontsDir -RegistryRoot $regRoot
                $n | Should -Be 1
                (Get-ItemProperty -Path $regRoot).'Fake-Reg (TrueType)' | Should -Be (Join-Path $fontsDir 'Fake-Reg.ttf')
            } finally {
                if (Test-Path 'HKCU:\Software\TerminalStylesTest') {
                    Remove-Item 'HKCU:\Software\TerminalStylesTest' -Recurse -Force
                }
            }
        }
    }
}
