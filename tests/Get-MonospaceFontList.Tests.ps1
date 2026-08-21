# Pester 5 tests for Get-MonospaceFontList. Uses the -Installed injection
# param to bypass real System.Drawing font enumeration.
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

Describe 'Get-MonospaceFontList' {
    InModuleScope TerminalStyles {
        It 'returns the allowlist intersected with installed fonts' {
            $installed = @('Consolas','JetBrains Mono','Arial','Times New Roman')
            $list = Get-MonospaceFontList -Current 'Consolas' -Installed $installed -MonospaceNames @()
            $list | Should -Contain 'Consolas'
            $list | Should -Contain 'JetBrains Mono'
            $list | Should -Not -Contain 'Arial'
        }
        It 'puts the current font first and de-duplicates' {
            $installed = @('Consolas','JetBrains Mono')
            $list = Get-MonospaceFontList -Current 'JetBrains Mono' -Installed $installed -MonospaceNames @()
            $list[0] | Should -Be 'JetBrains Mono'
            ($list | Where-Object { $_ -eq 'JetBrains Mono' }).Count | Should -Be 1
        }
        It 'includes a current font that is not on the allowlist' {
            $list = Get-MonospaceFontList -Current 'My Custom Mono' -Installed @('Consolas') -MonospaceNames @()
            $list[0] | Should -Be 'My Custom Mono'
            $list    | Should -Contain 'Consolas'
        }
        It 'falls back to a font that exists on this platform when nothing intersects' {
            # The fallback has to be a font the host actually ships. Consolas is
            # Windows-only -- naming it on a Mac would set the terminal to a
            # family that does not resolve, which renders as the system default
            # and looks like the setting was ignored.
            $expected = switch (Get-TStylesPlatform) {
                'MacOS' { 'Menlo' }
                'Linux' { 'DejaVu Sans Mono' }
                default { 'Consolas' }
            }
            $list = Get-MonospaceFontList -Current '' -Installed @('Arial') -MonospaceNames @()
            $list | Should -Be @($expected)
        }
        It 'includes installed monospace fonts beyond the favorites' {
            $list = Get-MonospaceFontList -Current 'Consolas' `
                -Installed @('Consolas','MonoLisa','Arial') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list | Should -Contain 'MonoLisa'
            $list | Should -Not -Contain 'Arial'
        }
        It 'floats favorites above other monospace fonts, others alphabetical' {
            $list = Get-MonospaceFontList -Current '' `
                -Installed @('Consolas','Aardvark Mono','MonoLisa') `
                -MonospaceNames @('Aardvark Mono','MonoLisa','Consolas')
            $idxFav = [array]::IndexOf($list, 'Consolas')       # a favorite
            $idxA   = [array]::IndexOf($list, 'Aardvark Mono')  # non-favorite
            $idxM   = [array]::IndexOf($list, 'MonoLisa')       # non-favorite
            $idxFav | Should -BeLessThan $idxA
            $idxA   | Should -BeLessThan $idxM   # non-favorites alphabetical
        }
        It 'keeps the current font first even when it is a non-favorite monospace' {
            $list = Get-MonospaceFontList -Current 'MonoLisa' `
                -Installed @('Consolas','MonoLisa') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list[0] | Should -Be 'MonoLisa'
        }
    }
}
