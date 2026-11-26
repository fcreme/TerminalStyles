# A style's text is shown, never obeyed (audit #89). Its meta.json description
# and quote, and its theme.json tabTitle, used to reach the terminal as they
# were, so an escape sequence in one retitled the window, wrote the clipboard
# (OSC 52) or redrew the screen the moment the style was listed or browsed --
# before anyone chose to apply it. ConvertTo-VisibleText is the one rule: the
# maintainer's review script used it already, and now the module does too.
#
# Characters are built with [char], never typed: Windows PowerShell 5.1 reads
# a BOM-less .ps1 in the system codepage.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
}

Describe 'ConvertTo-VisibleText in the module' {
    InModuleScope TerminalStyles {
        It 'shows an OSC title sequence instead of sending it' {
            $t = 'a' + [char]27 + ']0;x' + [char]7 + 'b'
            ConvertTo-VisibleText -Text $t | Should -BeExactly 'a\x1b]0;x\x07b'
        }

        It 'shows a C1 control and a bidi override' {
            # The expected text is built, not typed: backslash, then u202e.
            $bidiShown = [string][char]92 + 'u202e'
            ConvertTo-VisibleText -Text ([string][char]0x9B)   | Should -BeExactly '\x9b'
            ConvertTo-VisibleText -Text ([string][char]0x202E) | Should -BeExactly $bidiShown
        }

        It 'keeps a line break and a tab, which multi-line text needs' {
            ConvertTo-VisibleText -Text "a`nb`tc" | Should -BeExactly "a`nb`tc"
        }

        It 'puts a one-line field on one line with -SingleLine' {
            ConvertTo-VisibleText -Text "a`r`n`tb" -SingleLine | Should -BeExactly 'a b'
        }
    }
}

Describe 'Get-StyleTitlePreview' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
        }

        It 'shows an escape in tabTitle instead of letting it reach the title' {
            [System.IO.File]::WriteAllText((Join-Path $script:d 'theme.json'), '{"tabTitle":"a\u001bb"}',
                [System.Text.UTF8Encoding]::new($false))
            Get-StyleTitlePreview -StyleDir $script:d | Should -BeExactly 'a\x1bb'
        }

        It 'answers $null for <Case>' -ForEach @(
            @{ Case = 'a theme without tabTitle'; Json = '{"colorScheme":"x"}' }
            @{ Case = 'an unreadable theme.json';  Json = '{' }
        ) {
            [System.IO.File]::WriteAllText((Join-Path $script:d 'theme.json'), $Json, [System.Text.UTF8Encoding]::new($false))
            Get-StyleTitlePreview -StyleDir $script:d | Should -BeNullOrEmpty
        }
    }
}

Describe 'the review script uses the module''s rule' {
    It 'defines no ConvertTo-VisibleText of its own' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path (Join-Path $script:repoRoot 'scripts') 'review-submission.ps1'), [ref]$null, [ref]$null)
        $own = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq 'ConvertTo-VisibleText' }, $true))
        $own.Count | Should -Be 0 -Because 'a second copy of the rule drifts from the first'
    }
}
