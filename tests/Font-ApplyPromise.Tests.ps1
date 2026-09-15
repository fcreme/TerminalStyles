# Pester 5 tests: `tstyles font` and the two shortest descriptions of it must
# agree about who can actually apply a font.
#
# Applying a font means writing it into a profile, and the only font writer this
# command can reach is Set-ProfileFont, which knows Windows Terminal's
# settings.json and nothing else. Two things said otherwise:
#
#   * Show-FontList's footer ("Install + apply one with: tstyles font <name>")
#     and the help overview's one-line Summary ("Install a coding font and apply
#     it to the active profile") are both unconditional literals, rendered by a
#     loop with no platform branch in it. On Terminal.app they promised an apply
#     and the command then declined -- correctly, and one line later.
#   * The command gated itself on (Get-TerminalCapability).Font, which answers a
#     DIFFERENT question: "does a style apply write this terminal's font". That
#     has been $true for WezTerm since 0.8.24, where lib/wezterm.ps1 writes
#     config.font out of a style's theme.json. So on WezTerm the gate fell
#     through and `tstyles font 'JetBrains Mono'` ended in "Could not locate
#     Windows Terminal settings.json", in red, on a Mac, after an install that
#     had just succeeded -- the exact outcome the comment above the gate says
#     the gate exists to prevent.
#
# Test-FontCommandCanApply is the predicate named for the question the command
# asks. Get-TerminalKind takes an -EnvTable seam and Get-TerminalCapability
# takes -Kind, so all of this runs on every CI leg.
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

Describe 'tstyles font does not chase a settings.json that cannot exist' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:cat = @([pscustomobject]@{
                name = 'JetBrains Mono'; family = 'JetBrains Mono'; license = 'OFL-1.1'
                url = 'https://example.invalid/x.zip'; sha256 = 'deadbeef' })
            Mock Get-FontCatalog    { $script:cat }
            Mock Test-FontInstalled { $true }        # nothing downloads, nothing installs
            Mock Find-WTSettingsPath { $null }       # ...and off Windows Terminal there is none
        }

        It 'declines instead of reporting a Windows Terminal error on <kind>' -ForEach @(
            @{ kind = 'WezTerm' }        # capability .Font is $true here -- the whole defect
            @{ kind = 'AppleTerminal' }
            @{ kind = 'ITerm2' }
            @{ kind = 'Ghostty' }
        ) {
            Mock Get-TerminalKind ([scriptblock]::Create("'$kind'"))

            $out = Invoke-TerminalStyleFont -Name 'JetBrains Mono' 6>&1 | Out-String

            $out | Should -Not -Match 'Could not locate Windows Terminal' `
                -Because "$kind has no settings.json, and the install had already succeeded"
            $out | Should -Match ([regex]::Escape((Get-TerminalDisplayName -Kind $kind))) `
                -Because 'the decline has to name the terminal it is talking about'
        }

        It 'never reaches the Windows Terminal half at all on WezTerm' {
            # Not just "does not print the red line": the command must not go
            # looking. Find-WTSettingsPath is the first step of that half.
            Mock Get-TerminalKind { 'WezTerm' }
            Invoke-TerminalStyleFont -Name 'JetBrains Mono' 6>&1 | Out-Null
            Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
        }

        It 'tells a WezTerm user where the font does belong' {
            # WezTerm has no font picker to be "listed there" in -- it reads a
            # config file, which is also where a style apply writes config.font.
            Mock Get-TerminalKind { 'WezTerm' }
            $out = Invoke-TerminalStyleFont -Name 'JetBrains Mono' 6>&1 | Out-String
            $out | Should -Not -Match 'will be listed there'
            $out | Should -Match 'theme\.json'
        }

        It 'still applies on Windows Terminal' {
            # The other half of the symmetry: a gate that declines everywhere
            # would pass every assertion above and break the one terminal the
            # command serves.
            Mock Get-TerminalKind    { 'WindowsTerminal' }
            Mock Find-WTSettingsPath { 'C:\fake\settings.json' }
            Test-FontCommandCanApply -Kind 'WindowsTerminal' | Should -BeTrue
            Test-FontCommandCanApply -Kind 'WezTerm'         | Should -BeFalse
        }
    }
}

Describe 'the two shortest descriptions of tstyles font tell the truth' {
    InModuleScope TerminalStyles {

        It 'the font list footer promises no apply on <kind>' -ForEach @(
            @{ kind = 'WezTerm' }
            @{ kind = 'AppleTerminal' }
            @{ kind = 'ITerm2' }
            @{ kind = 'Kitty' }
            @{ kind = 'Ghostty' }
            @{ kind = 'Alacritty' }
            @{ kind = 'VSCode' }
        ) {
            Mock Get-TerminalKind ([scriptblock]::Create("'$kind'"))
            $cat = @([pscustomobject]@{ name = 'Fira Code'; family = 'Fira Code'; license = 'OFL-1.1' })

            $out = Show-FontList -Catalog $cat -Installed @() 6>&1 | Out-String

            $out | Should -Match 'tstyles font <name>' -Because 'the footer must still say how to install one'
            $out | Should -Not -Match 'apply' `
                -Because "tstyles font cannot apply a font on $kind, and says so when you run it"
        }

        It 'and still promises it where it is kept' {
            Mock Get-TerminalKind { 'WindowsTerminal' }
            $cat = @([pscustomobject]@{ name = 'Fira Code'; family = 'Fira Code'; license = 'OFL-1.1' })
            (Show-FontList -Catalog $cat -Installed @() 6>&1 | Out-String) |
                Should -Match 'Install \+ apply one with'
        }

        It 'the help overview row promises no apply on <kind>' -ForEach @(
            @{ kind = 'WezTerm' }
            @{ kind = 'AppleTerminal' }
            @{ kind = 'ITerm2' }
            @{ kind = 'Kitty' }
            @{ kind = 'Ghostty' }
            @{ kind = 'Alacritty' }
            @{ kind = 'VSCode' }
        ) {
            Mock Get-TerminalKind ([scriptblock]::Create("'$kind'"))

            $row = @(Show-TerminalStyleHelp 6>&1 | Out-String) -split "`r?`n" |
                   Where-Object { $_ -match '^\s+font \[name\]' }

            @($row).Count | Should -BeGreaterThan 0 -Because 'an overview with no font row would assert nothing'
            ($row -join ' ') | Should -Not -Match 'apply it to the active profile' `
                -Because 'the overview is rendered by a branch-free loop, so the line has to be true everywhere'
        }

        It 'the help summary still describes the command it names' {
            $font = Get-TerminalStyleHelpData | Where-Object { $_.Name -eq 'font' }
            $font.Summary | Should -Match '(?i)font'
            $font.Summary | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'README says the same thing the command does' {
    BeforeAll {
        $script:readme = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'README.md'),
            [System.Text.UTF8Encoding]::new($false))
    }

    It 'the site''s command list does not promise the apply everywhere either' {
        # The fourth copy of the same sentence, and the one a reader meets
        # before they install anything.
        $html = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/index.html'),
            [System.Text.UTF8Encoding]::new($false))
        $row = @($html -split "`r?`n" | Where-Object { $_ -match 'tstyles font \[name\]' })
        @($row).Count | Should -BeGreaterThan 0 -Because 'the row this test is about must still be there'
        if (($row -join ' ') -match '(?i)appl(y|ies|ied)') {
            ($row -join ' ') | Should -Match '(?i)windows terminal' `
                -Because 'the apply half is the Windows Terminal half'
        }
    }

    It 'scopes the apply half of tstyles font to the terminal that has it' {
        # The fenced recipe read "# install it (if needed) and apply it to the
        # active profile", with no qualifier anywhere in the section.
        $section = ([regex]::Match($script:readme, '(?ms)^### Installing a coding font.*?(?=^#{2,3} )')).Value
        $section | Should -Not -BeNullOrEmpty -Because 'this test is about that section'
        $section | Should -Match '(?i)windows terminal' `
            -Because 'applying the font to a profile is the only half that is Windows Terminal only'
    }
}
