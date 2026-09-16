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

Describe 'help names the PowerShell engines this platform really has' {
    # THE DEFECT THIS EXISTS FOR. The `register` topic read, on every platform:
    #
    #   Adds the Import-Module loader to both PowerShell 7 and Windows
    #   PowerShell 5.1 $PROFILE files (with a confirm prompt) so tstyles
    #   loads on every new tab.
    #
    # Measured on macOS with the shipped functions: the topic named 'Windows
    # PowerShell 5.1' while the engines register and uninstall actually probe
    # there are pwsh [PowerShell 7] and pwsh-preview [PowerShell 7 (preview)].
    # Windows PowerShell does not exist off Windows at all -- and "both" is
    # wrong a second way even on Windows, because the discovery loop `continue`s
    # past an engine that is not on PATH and register writes only to the ones it
    # found.
    #
    # The runtime was already right (it prints each target's real $t.Label);
    # only the sentence was a literal. So this asserts the sentence against the
    # same table the command probes with, in BOTH directions -- every label this
    # platform has is named, and no label from another platform's table is. A
    # second hand-typed engine list, in the help or in a test, is how the first
    # one went stale.
    InModuleScope TerminalStyles {
        It 'the register topic names exactly the engines register probes on <_>' -ForEach @('Windows', 'MacOS', 'Linux') {
            $platform = $_
            $detail = ((Get-TerminalStyleHelpData -Platform $platform |
                        Where-Object { $_.Name -eq 'register' }).Detail -join ' ')
            $detail | Should -Not -BeNullOrEmpty

            # Projected with ForEach-Object: `.Label` on an empty array is one
            # $null, and a list holding nothing has Count 1.
            $labels = @(Get-PowerShellEngineCandidate -Platform $platform |
                        ForEach-Object { $_.Label })
            @($labels).Count | Should -BeGreaterThan 0 -Because 'an empty list would assert nothing'

            foreach ($label in $labels) {
                $detail | Should -Match ([regex]::Escape($label)) `
                    -Because "register writes to $label on $platform, so the topic must name it"
            }

            $foreign = @(@('Windows', 'MacOS', 'Linux') |
                         ForEach-Object { Get-PowerShellEngineCandidate -Platform $_ } |
                         ForEach-Object { $_.Label } | Sort-Object -Unique |
                         Where-Object { $_ -notin $labels })
            @($foreign).Count | Should -BeGreaterThan 0 -Because 'the platforms differ, or this half asserts nothing'
            foreach ($label in $foreign) {
                $detail | Should -Not -Match ([regex]::Escape($label)) `
                    -Because "there is no $label on $platform"
            }
        }

        It 'the register topic does not promise it writes to every engine' {
            # "both" was also wrong about what happens when only one is
            # installed: the loop skips an engine it cannot find.
            $detail = ((Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'register' }).Detail -join ' ')
            $detail | Should -Match '(?i)(found on your PATH|on your PATH)'
            $detail | Should -Match '(?i)skipped'
        }
    }
}
