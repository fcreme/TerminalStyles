# Pester 5 tests: WezTerm per-tab mode, the tag packet and the per-tab record.
#
# Nothing here talks to a running WezTerm. The packet is pinned byte for byte, and
# the record is exercised against a data root under $TestDrive with this process's
# WEZTERM_UNIX_SOCKET / WEZTERM_PANE set per test and restored afterwards.
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

Describe 'Test-WezTermPerTab' {
    InModuleScope TerminalStyles {
        It 'is true only for WezTerm, off Windows, wired' {
            Mock Test-WezTermStyleWired { $true }
            Test-WezTermPerTab -Kind WezTerm -Platform MacOS | Should -BeTrue
            Test-WezTermPerTab -Kind WezTerm -Platform Windows | Should -BeFalse
            Test-WezTermPerTab -Kind ITerm2 -Platform MacOS | Should -BeFalse
        }
        It 'is false when the wiring line is absent' {
            Mock Test-WezTermStyleWired { $false }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux | Should -BeFalse
        }
        It 'forwards HomeDir to the wiring check only when bound' {
            Mock Test-WezTermStyleWired { $true }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux -HomeDir '/nowhere' | Should -BeTrue
            Should -Invoke Test-WezTermStyleWired -Times 1 -Exactly -ParameterFilter { $HomeDir -eq '/nowhere' }
            Test-WezTermPerTab -Kind WezTerm -Platform Linux | Should -BeTrue
            Should -Invoke Test-WezTermStyleWired -Times 1 -Exactly -ParameterFilter { $null -eq $HomeDir }
        }
    }
}

Describe 'WezTerm tag constants' {
    InModuleScope TerminalStyles {
        It 'holds the user variable name and the two non-style markers' {
            $script:WezTermTagVar | Should -BeExactly 'TERMINALSTYLES_STYLE'
            $script:WezTermTagUnstyled | Should -BeExactly '/unstyled'
            $script:WezTermTagPreviewPrefix | Should -BeExactly '/preview/'
        }
    }
}

Describe 'Get-WezTermTagPacket' {
    InModuleScope TerminalStyles {
        It 'base64-encodes the UTF-8 value' {
            $p = Get-WezTermTagPacket -Value "o'brién" -InTmux $false
            $p | Should -BeExactly ("$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=" +
                [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("o'brién")) + "$([char]7)")
        }
        It 'wraps for tmux with every ESC doubled' {
            $p = Get-WezTermTagPacket -Value kitty -InTmux $true
            $p.StartsWith("$([char]27)Ptmux;$([char]27)$([char]27)]1337;") | Should -BeTrue
            $p.EndsWith("$([char]27)\") | Should -BeTrue
        }
        It 'encodes an empty value as an empty user var' {
            Get-WezTermTagPacket -Value '' -InTmux $false |
                Should -BeExactly "$([char]27)]1337;SetUserVar=TERMINALSTYLES_STYLE=$([char]7)"
        }
    }
}

Describe 'per-tab record' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:origRoot = $script:TStylesDataRoot
            $script:origSock = $env:WEZTERM_UNIX_SOCKET
            $script:origPane = $env:WEZTERM_PANE
            $script:TStylesDataRoot = $TestDrive
            $script:recFile = Join-Path $TestDrive 'wezterm-tabs.json'
            if (Test-Path -LiteralPath $script:recFile) { Remove-Item -LiteralPath $script:recFile -Force }
            $script:liveSock = Join-Path $TestDrive 'live.sock'
            Set-Content -LiteralPath $script:liveSock -Value 'x'
            $env:WEZTERM_UNIX_SOCKET = $script:liveSock
            $env:WEZTERM_PANE = '3'
        }
        AfterEach {
            $script:TStylesDataRoot = $script:origRoot
            $env:WEZTERM_UNIX_SOCKET = $script:origSock
            $env:WEZTERM_PANE = $script:origPane
        }

        It 'builds the key from socket and pane, and is null when either is empty' {
            Get-WezTermTabKey | Should -BeExactly "$($script:liveSock)|3"
            $env:WEZTERM_PANE = ''
            Get-WezTermTabKey | Should -BeNullOrEmpty
            $env:WEZTERM_PANE = '3'
            $env:WEZTERM_UNIX_SOCKET = ''
            Get-WezTermTabKey | Should -BeNullOrEmpty
        }
        It 'round-trips this tab and keeps unstyled distinct from missing' {
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
            Set-WezTermTabRecord -Value '' | Should -BeExactly 'ok'
            $r = Get-WezTermTabRecord
            $null -eq $r | Should -BeFalse
            $r | Should -BeExactly ''
            $env:WEZTERM_PANE = '4'
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
        }
        It 'returns nokey and writes nothing outside WezTerm' {
            $env:WEZTERM_UNIX_SOCKET = ''
            $env:WEZTERM_PANE = ''
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'nokey'
            [System.IO.File]::Exists($script:recFile) | Should -BeFalse
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
        }
        It 'drops entries whose socket no longer exists' {
            $dead = Join-Path $TestDrive 'dead.sock'
            [System.IO.File]::WriteAllText($script:recFile,
                ('{"' + $dead + '|1":"eva","' + $script:liveSock + '|9":"kitty"}'))
            Set-WezTermTabRecord -Value 'x' | Should -BeExactly 'ok'
            $text = [System.IO.File]::ReadAllText($script:recFile)
            $text | Should -Not -BeLike '*dead.sock*'
            $env:WEZTERM_PANE = '9'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
            $env:WEZTERM_PANE = '3'
            Get-WezTermTabRecord | Should -BeExactly 'x'
        }
        It 'reads a corrupt file as no record' {
            [System.IO.File]::WriteAllText($script:recFile, 'not json')
            $null -eq (Get-WezTermTabRecord) | Should -BeTrue
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            Get-WezTermTabRecord | Should -BeExactly 'kitty'
        }
        It 'writes UTF-8 without a byte-order mark' {
            Set-WezTermTabRecord -Value 'kitty' | Should -BeExactly 'ok'
            $b = [System.IO.File]::ReadAllBytes($script:recFile)
            $b[0] | Should -Be ([byte][char]'{')
        }
    }
}
