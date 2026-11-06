# Pester 5 tests for lib/creator.ps1: the creator's state -- its defaults,
# colour edits that a re-pull keeps, and readability warnings that never block
# an edit.
#
# Pure in-memory: nothing here touches a file.
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

Describe 'the creator state' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:px = [int[]]@(
                foreach ($c in 0x0a0a2a, 0x1a1a4a, 0xff7a1a, 0xc2306a, 0x2fa04a, 0x3060d0, 0xe0e0f0) {
                    for ($i = 0; $i -lt 40; $i++) { $c }
                }
            )
        }

        It 'starts on the listed defaults' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s | Should -BeOfType [hashtable]
            $s.Step | Should -Be 0
            $s.ImagePath | Should -BeExactly '/img/a.png'
            @($s.Pixels).Count | Should -Be $script:px.Count
            @($s.Edited).Count | Should -Be 0
            $s.ImageOpacity | Should -Be 0.35
            $s.StretchMode | Should -BeExactly 'uniformToFill'
            $s.Alignment | Should -BeExactly 'center'
            $s.FontFace | Should -BeExactly 'Cascadia Code'
            $s.FontSize | Should -Be 11
            $s.CursorShape | Should -BeExactly 'bar'
            $s.PromptShape | Should -BeExactly 'minimal'
            $s.Symbol | Should -BeExactly '$'
            $s.PromptPathColor | Should -BeExactly (Get-PaletteAccent -Scheme $s.Scheme)
            $s.PromptSymbolColor | Should -BeExactly $s.Scheme.foreground
            $s.Name | Should -BeNullOrEmpty
            $s.ContainsKey('Name') | Should -BeTrue
        }

        It 'pulls its scheme from the pixels' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $want = New-PaletteFromPixels -Pixels $script:px -Name 'x'
            foreach ($k in 'background', 'foreground', 'red', 'brightCyan') {
                $s.Scheme.$k | Should -BeExactly $want.$k
            }
        }

        It 'Set-CreatorColor changes the slot and records it as edited' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            Set-CreatorColor -State $s -Slot red -Hex '#123456'
            $s.Scheme.red | Should -BeExactly '#123456'
            $s.Edited.Contains('red') | Should -BeTrue
            @($s.Edited).Count | Should -Be 1
        }

        It 'Set-CreatorColor refuses a slot the scheme does not have, and a colour that does not parse' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            { Set-CreatorColor -State $s -Slot 'name' -Hex '#123456' } | Should -Throw
            { Set-CreatorColor -State $s -Slot 'nosuch' -Hex '#123456' } | Should -Throw
            $before = $s.Scheme.red
            { Set-CreatorColor -State $s -Slot red -Hex 'not-a-colour' } | Should -Throw
            $s.Scheme.red | Should -BeExactly $before
            @($s.Edited).Count | Should -Be 0
        }

        It 'Update-CreatorPalette keeps an edited slot and refreshes the rest' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $pulledGreen = $s.Scheme.green
            Set-CreatorColor -State $s -Slot red -Hex '#123456'
            # Not through Set-CreatorColor, so not edited: a re-pull puts it back.
            $s.Scheme.green = '#000001'
            Update-CreatorPalette -State $s
            $s.Scheme.red | Should -BeExactly '#123456'
            $s.Edited.Contains('red') | Should -BeTrue
            $s.Scheme.green | Should -BeExactly $pulledGreen
        }

        It 'Update-CreatorPalette re-pulls from changed pixels, still sparing the edited slots' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            Set-CreatorColor -State $s -Slot red -Hex '#123456'
            $other = [int[]]@(foreach ($c in 0x201008, 0x40ff40, 0xffffff) { for ($i = 0; $i -lt 50; $i++) { $c } })
            $s.Pixels = $other
            Update-CreatorPalette -State $s
            $want = New-PaletteFromPixels -Pixels $other -Name 'x'
            $s.Scheme.background | Should -BeExactly $want.background
            $s.Scheme.green | Should -BeExactly $want.green
            $s.Scheme.red | Should -BeExactly '#123456'
        }

        It 'a freshly pulled palette has no warnings' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            @(Get-CreatorWarnings -State $s).Count | Should -Be 0
        }

        It 'red set to the background colour warns about red, and the edit is kept' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            Set-CreatorColor -State $s -Slot red -Hex $s.Scheme.background
            $s.Scheme.red | Should -BeExactly $s.Scheme.background
            $w = @(Get-CreatorWarnings -State $s)
            $w.Count | Should -Be 1
            $w[0] | Should -BeOfType [string]
            $w[0].Contains('red') | Should -BeTrue
        }

        It 'a dim foreground warns once, naming foreground' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            Set-CreatorColor -State $s -Slot foreground -Hex $s.Scheme.background
            $w = @(Get-CreatorWarnings -State $s)
            @($w | Where-Object { $_.Contains('foreground') }).Count | Should -Be 1
        }

        It 'an unparseable slot warns, naming it' {
            $s = New-CreatorState -Pixels $script:px -ImagePath '/img/a.png'
            $s.Scheme.cyan = 'rgb(1,2,3)'
            $w = @(Get-CreatorWarnings -State $s)
            @($w | Where-Object { $_.Contains('cyan') }).Count | Should -Be 1
        }
    }
}
