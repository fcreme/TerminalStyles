# Pester 5 tests for Show-TerminalStyleHelp (overview + per-command detail).
# Write-Host output is captured via the information stream (6>&1).
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

Describe 'Show-TerminalStyleHelp' {
    InModuleScope TerminalStyles {
        It 'overview lists every command name' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            foreach ($name in (Get-TerminalStyleHelpData).Name) {
                $out | Should -Match ([regex]::Escape($name))
            }
        }
        It 'overview shows USAGE and the docs link' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            $out | Should -Match 'USAGE'
            $out | Should -Match 'github\.com/fcreme/TerminalStyles'
        }
        It 'help <command> shows that command''s detail' {
            $out = Show-TerminalStyleHelp -Command 'tune' 6>&1 | Out-String
            $out | Should -Match 'brightness'
            $out | Should -Match 'Esc'
        }
        It 'command lookup is case-insensitive' {
            $out = Show-TerminalStyleHelp -Command 'TUNE' 6>&1 | Out-String
            $out | Should -Match 'brightness'
        }
        It 'command lookup is case-insensitive the same way in every culture' {
            # The case-insensitivity above was implemented as $Command.ToLower(),
            # which lowercases with the CURRENT culture. Under tr-TR and az-AZ an
            # uppercase 'I' lowercases to the dotless 'i', so `tstyles help LIST`
            # printed "No help topic 'LIST'." directly above a topics line
            # containing 'list' -- while `tstyles LIST` worked in the same
            # session, because the dispatcher compares with a bare -eq.
            #
            # 'TUNE' could never catch it: the bug needs an I in the token. Every
            # topic that has one is checked here.
            $withI = @((Get-TerminalStyleHelpData).Name | Where-Object { $_ -match 'i' })
            @($withI).Count | Should -BeGreaterThan 0 -Because 'otherwise this test proves nothing'

            $prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture =
                    [System.Globalization.CultureInfo]::new('tr-TR')
                foreach ($topic in $withI) {
                    $out = Show-TerminalStyleHelp -Command $topic.ToUpperInvariant() 6>&1 | Out-String
                    $out | Should -Not -Match 'No help topic' `
                        -Because "help $($topic.ToUpperInvariant()) must resolve under tr-TR as it does anywhere else"
                }
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev
            }
        }
        It 'unknown topic shows a not-found message and lists topics' {
            $out = Show-TerminalStyleHelp -Command 'frobnicate' 6>&1 | Out-String
            $out | Should -Match "No help topic 'frobnicate'"
            $out | Should -Match 'tune'
        }
        It 'renders a command with no KEYS (e.g. list) without error' {
            $out = Show-TerminalStyleHelp -Command 'list' 6>&1 | Out-String
            $out | Should -Match 'tstyles list'
            $out | Should -Match 'asterisk'   # from list's Detail
            $out | Should -Not -Match 'KEYS'  # list has Keys = @(), so no KEYS section
        }
    }
}

Describe 'help does not promise Windows Terminal behaviour to everyone else' {
    # The existing tests here check the SHAPE of the help -- that every command
    # has a Name, Usage and Summary, that lookup is case-insensitive. Nothing
    # checked whether what it says is true, and on macOS and Linux three things
    # were not:
    #
    #   * the overview title read "themed styles for Windows Terminal", which
    #     was the first line a user of Terminal.app, iTerm2, kitty, WezTerm,
    #     Ghostty, Alacritty or VS Code read;
    #   * `reset` promised "Writes a settings.json.bak first", and off Windows
    #     Terminal Reset-StyleNonWT writes no backup and there is no
    #     settings.json at all -- a safety net offered where none exists;
    #   * `font` said it "applies it to the active Windows Terminal profile",
    #     while Invoke-TerminalStyleFont prints, correctly, that the terminal
    #     takes its font from its own preferences and it cannot.
    #
    # In all three the runtime was already platform-correct. Only the help lied.
    InModuleScope TerminalStyles {

        It 'the overview title does not name one terminal as though it were the only one' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            $title = ($out -split "`r?`n" | Where-Object { $_ -match 'tstyles - ' } | Select-Object -First 1)
            $title | Should -Not -BeNullOrEmpty
            $title | Should -Not -Match 'Windows Terminal' `
                -Because 'this module styles eight other terminals, and says so in the README'
        }

        It 'the reset topic does not promise a backup that only Windows Terminal gets' {
            $reset = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'reset' })
            $detail = ($reset.Detail -join ' ')
            if ($detail -match 'settings\.json\.bak') {
                $detail | Should -Match '(?i)(elsewhere|outside|other terminals?|non-|no \.bak)' `
                    -Because 'off Windows Terminal there is no settings.json and no .bak is written'
            }
        }

        It 'the font topic does not claim to apply a font every terminal will accept' {
            $font = (Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'font' })
            $detail = ($font.Detail -join ' ')
            if ($detail -match '(?i)appl(y|ies)') {
                $detail | Should -Match '(?i)(own preferences|by hand|select|Windows Terminal,)' `
                    -Because 'every other terminal takes its font from its own settings'
            }
        }
    }
}
