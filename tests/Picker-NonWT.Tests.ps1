# Pester 5 tests for the picker's behaviour off Windows Terminal.
#
# Every case here is a bug that shipped in 0.8.0. The picker is a keyboard UI,
# so the Windows CI legs never exercised its non-WT branch at all -- the crash
# below reached users with all four legs green.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'picker guards on a non-console session' {
    InModuleScope TerminalStyles {
        It 'explains itself instead of throwing .NET console internals' {
            # Regression: the picker drew its whole menu, then died on
            # [Console]::KeyAvailable with "Cannot see if a key has been pressed
            # ... Try Console.In.Peek". Anything running tstyles with stdin
            # detached -- a pipe, a redirect, a CI step, an agent shell -- hit it.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Invoke-FontFirstRunPrompt {}
            Mock Write-Host {}
            # Clear-Host must NOT run: the guard returns before the picker takes
            # over the screen, so the user's scrollback survives.
            Mock Clear-Host { throw 'the picker must not clear the screen before bailing out' }
            Mock Invoke-StylePickerLoop { throw 'the picker loop must not start without a console' }

            if ([Console]::IsInputRedirected) {
                { Invoke-TerminalStyle } | Should -Not -Throw
                Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'needs an interactive terminal' }
            } else {
                Set-ItResult -Skipped -Because 'this test run has a real console attached'
            }
        }
    }
}

Describe 'picker background handling off Windows Terminal' {
    InModuleScope TerminalStyles {
        It 'does not treat a missing background as unresolved when none can be shown' {
            # The picker was downloading a GIF per style from the gifs branch --
            # megabytes over the network, and a "...fetching background" row next
            # to every entry -- for an image Terminal.app can never draw.
            (Get-TerminalCapability -Kind 'AppleTerminal').BackgroundImage | Should -BeFalse
            (Get-TerminalCapability -Kind 'WindowsTerminal').BackgroundImage | Should -BeTrue
        }
    }
}

Describe 'picker header target label' {
    InModuleScope TerminalStyles {
        It 'names the terminal when there is no profile to name' {
            # Off Windows Terminal $Target is empty, and the header read
            # "Choose a style for ''", which looks like a bug in the tool.
            Get-TerminalDisplayName -Kind 'AppleTerminal' | Should -Be 'Terminal.app'
            Get-TerminalDisplayName -Kind 'AppleTerminal' | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'OSC packet is available before the picker paints' {
    InModuleScope TerminalStyles {
        It 'builds a packet from a scheme without needing the per-key cache' {
            # The 0.8.0 crash: the initial paint indexed $oscPackets, which is
            # populated ~50 lines further down for the per-keystroke path and was
            # still $null -- "Cannot index into a null array", before a single
            # row was drawn. The fix builds that one packet from $schemes, so
            # this must work standing alone.
            $scheme = [System.IO.File]::ReadAllText(
                (Join-Path (Get-StyleDir -StyleName 'eva') 'scheme.json'),
                [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $packet = Get-SchemeOscPacket -Scheme $scheme
            $packet | Should -Not -BeNullOrEmpty
            $packet | Should -Match ([regex]::Escape("$([char]27)]11;"))
        }
    }
}
