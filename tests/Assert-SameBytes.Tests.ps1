# Pester 5 tests: the byte comparison the packet tests rely on can tell a
# packet from one with its control characters gone.
#
# Measured on pwsh 7 under ICU: "]104" -ceq "$([char]27)]104" is True, Pester's
# Should -BeExactly passes the same pair, and .StartsWith ignores the ESC under
# the current culture. tests/Assert-SameBytes.ps1 compares UTF-8 bytes instead;
# these tests are what make that a claim rather than a hope.
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

Describe 'Assert-SameBytes' {
    InModuleScope TerminalStyles {
        BeforeAll { . (Join-Path $PSScriptRoot 'Assert-SameBytes.ps1') }

        It 'fails a packet with its ESC removed' {
            $packet = Get-OscResetPacket
            $noEsc = $packet.Replace([string][char]27, '')
            $noEsc.Length | Should -BeLessThan $packet.Length -Because 'the fixture must really have lost its ESCs'
            Test-SameBytes -Actual $noEsc -Expected $packet | Should -BeFalse
            { Assert-SameBytes -Actual $noEsc -Expected $packet } | Should -Throw
        }

        It 'fails a packet with its BEL removed' {
            $packet = Get-WezTermTagPacket -Value 'kitty' -InTmux $false
            $noBel = $packet.Replace([string][char]7, '')
            Test-SameBytes -Actual $noBel -Expected $packet | Should -BeFalse
        }

        It 'fails a tmux wrap whose ESCs were not doubled' {
            $esc = [string][char]27
            $inner = Get-WezTermTagPacket -Value 'kitty' -InTmux $false
            $undoubled = "${esc}Ptmux;" + $inner + "$esc\"
            Test-SameBytes -Actual $undoubled -Expected (Get-WezTermTagPacket -Value 'kitty' -InTmux $true) | Should -BeFalse
        }

        It 'passes the same packet, and $null only for $null' {
            Test-SameBytes -Actual (Get-OscResetPacket) -Expected (Get-OscResetPacket) | Should -BeTrue
            { Assert-SameBytes -Actual (Get-OscResetPacket) -Expected (Get-OscResetPacket) } | Should -Not -Throw
            Test-SameBytes -Actual $null -Expected $null | Should -BeTrue
            Test-SameBytes -Actual $null -Expected '' | Should -BeFalse
        }

        It 'spells both sides out when it fails' {
            $err = $null
            try { Assert-SameBytes -Actual ']104' -Expected "$([char]27)]104$([char]7)" -Because 'why' } catch { $err = "$_" }
            $err | Should -Not -BeNullOrEmpty
            $err.Contains('\e]104\a') | Should -BeTrue
            $err.Contains("but got ']104'") | Should -BeTrue
            $err.Contains('because why') | Should -BeTrue
        }
    }
}
