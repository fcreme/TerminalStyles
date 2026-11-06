# Pester 5 tests: New-StylePromptText writes both halves of a generated
# style's prompt -- profile.ps1 for PowerShell, prompt.sh for zsh/bash.
#
# These are the static promises, true on every platform. That the two halves
# render the same bytes is measured by rendering them, in
# Style-PromptParity.Tests.ps1, next to the shipped styles.
#
#   * profile.ps1 is ASCII-only. Windows PowerShell 5.1 reads a BOM-less .ps1
#     in the system codepage, so a literal U+276F in a string is mojibake at
#     best and a parse error at worst. The symbol has to reach the file as
#     [char]0x276F.
#   * prompt.sh has no CR, and every name it assigns is _ts_-prefixed: it is
#     sourced into the user's own shell.
#   * profile.ps1 parses, and does not touch PSReadLine.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $mod = Get-Module TerminalStyles
    $shapes  = @(& $mod { Get-StylePromptShapes })
    $symbols = @(& $mod { Get-StylePromptSymbols })
    # Every shape x every symbol: the escaping of a symbol must not depend on
    # which shape it sits in.
    $script:Pairs = @(foreach ($sh in $shapes) {
        foreach ($sy in $symbols) {
            @{ Shape = $sh; Symbol = $sy; Code = ('U+{0:X4}' -f [int][char]$sy[0]) }
        }
    })
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'the prompt shapes and symbols on offer' {
    InModuleScope TerminalStyles {
        It 'offers exactly the four shapes, in order' {
            $s = @(Get-StylePromptShapes)
            ($s -join ',') | Should -BeExactly 'minimal,path,twoline,git'
        }

        It 'offers <Name> as a symbol' -ForEach @(
            @{ Name = 'dollar'; Code = 0x24 }
            @{ Name = 'greater-than'; Code = 0x3E }
            @{ Name = 'hash'; Code = 0x23 }
            @{ Name = 'heavy angle U+276F'; Code = 0x276F }
            @{ Name = 'lambda U+03BB'; Code = 0x03BB }
            @{ Name = 'guillemet U+00BB'; Code = 0x00BB }
        ) {
            $want = [string][char]$Code
            @(Get-StylePromptSymbols) -ccontains $want | Should -BeTrue
        }
    }
}

Describe 'New-StylePromptText halves (<Shape>, <Code>)' -ForEach $script:Pairs {
    BeforeAll {
        $mod = Get-Module TerminalStyles
        $script:Gen = & $mod {
            param($Shape, $Symbol)
            New-StylePromptText -Shape $Shape -Symbol $Symbol -PathColor '#7a9999' `
                -SymbolColor '#D08770' -BranchColor '#bb00bb' -Title ('My ' + [char]0x03BB + " 'style'")
        } $Shape $Symbol
    }

    It 'returns both halves' {
        $script:Gen.Profile | Should -Not -BeNullOrEmpty
        $script:Gen.Shell   | Should -Not -BeNullOrEmpty
    }

    It 'writes profile.ps1 in ASCII only' {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:Gen.Profile)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $script:Gen.Profile | Should -Not -Match '\r'
    }

    It 'parses profile.ps1 with no errors' {
        $errs = $null; $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseInput(
            $script:Gen.Profile, [ref]$tokens, [ref]$errs) | Out-Null
        @($errs).Count | Should -Be 0
    }

    It 'leaves PSReadLine alone' {
        $script:Gen.Profile | Should -Not -Match 'PSReadLine'
    }

    It 'defines global:prompt and sets the window title' {
        $script:Gen.Profile | Should -Match 'function global:prompt'
        $script:Gen.Profile | Should -Match '\$Host\.UI\.RawUI\.WindowTitle'
    }

    It 'writes prompt.sh with no CR' {
        $script:Gen.Shell.Contains("`r") | Should -BeFalse
    }

    It 'writes the symbol into prompt.sh as UTF-8 text, not an escape' {
        $script:Gen.Shell.Contains($Symbol) | Should -BeTrue
    }

    It 'assigns only _ts_-prefixed names in prompt.sh' {
        $names = @([regex]::Matches($script:Gen.Shell,
            '(?m)(?:^|[;&|\s])(?:export\s+|local\s+)?([A-Za-z_][A-Za-z0-9_]*)\+?=') |
            ForEach-Object { $_.Groups[1].Value })
        $names.Count | Should -BeGreaterThan 0 -Because 'the colours are assigned, so a scan finding nothing measured nothing'
        foreach ($n in $names) { $n | Should -CMatch '^_ts_' }
    }

    It 'colours with ts_c and titles with ts_title' {
        $script:Gen.Shell | Should -Match "_ts_pPath=\`$\(ts_c '122;153;153'\)"
        $script:Gen.Shell | Should -Match "_ts_pSym=\`$\(ts_c '208;135;112'\)"
        $script:Gen.Shell | Should -Match '(?m)^ts_title '
        $script:Gen.Shell | Should -Match 'ts_prompt_apply "\$\(ts_prompt_expand '
    }
}

Describe 'New-StylePromptText inputs' {
    InModuleScope TerminalStyles {
        It 'maps <Shape> to <Want>' -ForEach @(
            @{ Shape = 'minimal'; Want = '{LEAF}' }
            @{ Shape = 'path'; Want = '{CWD}' }
            @{ Shape = 'twoline'; Want = '{CWD}${_ts_pX}{NL}' }
            @{ Shape = 'git'; Want = '{LEAF}${_ts_pX}{GITBRANCH}' }
        ) {
            $g = New-StylePromptText -Shape $Shape -Symbol '>' -PathColor '#010203' -SymbolColor '#040506' -Title 'T'
            $g.Shell.Contains($Want) | Should -BeTrue
        }

        It 'follows the symbol with exactly one space' {
            $g = New-StylePromptText -Shape minimal -Symbol '>' -PathColor '#010203' -SymbolColor '#040506' -Title 'T'
            $g.Shell.Contains('${_ts_pSym}>${_ts_pX} ")"') | Should -BeTrue
        }

        It 'rejects an unknown shape' {
            { New-StylePromptText -Shape 'fancy' -Symbol '>' -PathColor '#010203' -SymbolColor '#040506' -Title 'T' } |
                Should -Throw
        }

        It 'rejects a colour that is not #rrggbb' {
            { New-StylePromptText -Shape minimal -Symbol '>' -PathColor 'teal' -SymbolColor '#040506' -Title 'T' } |
                Should -Throw
        }

        It 'rejects a symbol carrying a character either shell would reinterpret (<Bad>)' -ForEach @(
            @{ Bad = '%' }, @{ Bad = '\' }, @{ Bad = '!' }, @{ Bad = '`' }, @{ Bad = '"' }, @{ Bad = '{' }, @{ Bad = ' ' }
        ) {
            { New-StylePromptText -Shape minimal -Symbol $Bad -PathColor '#010203' -SymbolColor '#040506' -Title 'T' } |
                Should -Throw
        }

        It 'rejects a title carrying a control character' {
            { New-StylePromptText -Shape minimal -Symbol '>' -PathColor '#010203' -SymbolColor '#040506' -Title ("a" + [char]7) } |
                Should -Throw
        }

        It 'clears the branch colours when no -BranchColor is given' {
            $g = New-StylePromptText -Shape git -Symbol '>' -PathColor '#010203' -SymbolColor '#040506' -Title 'T'
            $g.Shell | Should -Match "(?m)^_ts_git_open=''$"
            $g.Shell | Should -Match "(?m)^_ts_git_close=''$"
        }
    }
}
