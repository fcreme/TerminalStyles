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
        It 'copies font files to the per-user dir and writes registry values' {
            $src = Join-Path $TestDrive 'Fake-Regular.ttf'
            [System.IO.File]::WriteAllText($src, 'FAKE')
            $fontsDir = Join-Path $TestDrive 'UserFonts'
            $regRoot  = 'HKCU:\Software\TerminalStylesTest\Fonts'
            try {
                $n = Install-Font -FontFiles @($src) -FontsDir $fontsDir -RegistryRoot $regRoot
                $n | Should -Be 1
                Test-Path -LiteralPath (Join-Path $fontsDir 'Fake-Regular.ttf') | Should -BeTrue
                (Get-ItemProperty -Path $regRoot).'Fake-Regular (TrueType)' | Should -Be (Join-Path $fontsDir 'Fake-Regular.ttf')
            } finally {
                if (Test-Path 'HKCU:\Software\TerminalStylesTest') {
                    Remove-Item 'HKCU:\Software\TerminalStylesTest' -Recurse -Force
                }
            }
        }
    }
}
