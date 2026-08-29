# Pester 5 tests for the one rule that keeps a style name from becoming a path.
#
# Regression: `tstyles tune ../styles/eva` deleted styles/eva. The tuner's
# scratch directory is <DataRoot>/.tune-preview/<name> and its finally block
# removes it whole and recursive; `.tune-preview` and `styles` are both
# single-segment children of the data root, so any name reaching up a level
# made the scratch dir and the style dir the same directory. It printed
# "Reverted.", exited 0, and the style was gone. The same name arriving
# through a tuned style's tune.json `base` did it with nothing unusual typed.
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

Describe 'Test-StyleNameValid' {
    InModuleScope TerminalStyles {
        It 'accepts the names styles actually use' {
            foreach ($n in 'eva', 'golden-forest', 'neon-rain', 'my.theme', 'a_b', 'X1') {
                Test-StyleNameValid -Name $n | Should -BeTrue -Because "'$n' is a normal style name"
            }
        }
        It 'rejects anything that is not a single directory segment' {
            foreach ($n in '../styles/eva', '..\styles\eva', 'a/b', 'a\b', '../eva', './eva') {
                Test-StyleNameValid -Name $n | Should -BeFalse -Because "'$n' is a path, not a name"
            }
        }
        It "rejects '.' and '..', which the character class alone admits" {
            # Both match ^[A-Za-z0-9._-]+$ and neither is a name.
            Test-StyleNameValid -Name '.'  | Should -BeFalse
            Test-StyleNameValid -Name '..' | Should -BeFalse
        }
        It 'rejects empty, whitespace and over-long names' {
            Test-StyleNameValid -Name ''             | Should -BeFalse
            Test-StyleNameValid -Name '   '          | Should -BeFalse
            Test-StyleNameValid -Name ('a' * 65)     | Should -BeFalse
            Test-StyleNameValid -Name ('a' * 64)     | Should -BeTrue
        }
    }
}

Describe 'Get-StyleDir refuses a name that is a path' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:victim = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'eva'
            New-Item -ItemType Directory -Path $script:victim -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:victim 'scheme.json'),
                '{"name":"eva","background":"#0a0006"}', [System.Text.UTF8Encoding]::new($false))
        }

        It 'resolves the plain name' {
            Get-StyleDir -StyleName 'eva' | Should -Be $script:victim
        }

        It 'returns $null for a traversing name that WOULD have resolved' {
            # The directory is genuinely reachable that way -- that is the whole
            # problem. Test-Path on the composed path succeeds; Get-StyleDir
            # must still refuse the name.
            $composed = Join-Path (Join-Path $script:TStylesDataRoot 'styles') '../styles/eva'
            Test-Path -LiteralPath (Join-Path $composed 'scheme.json') | Should -BeTrue -Because 'the traversal really does reach the style'
            Get-StyleDir -StyleName '../styles/eva' | Should -BeNullOrEmpty
        }
    }
}

Describe 'the tuner leaves the style it was tuning on disk' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:stylesDir = Join-Path $script:TStylesDataRoot 'styles'
            $script:victim    = Join-Path $script:stylesDir 'eva'
            New-Item -ItemType Directory -Path $script:victim -Force | Out-Null
            foreach ($f in 'scheme.json', 'theme.json', 'profile.ps1', 'prompt.sh') {
                [System.IO.File]::WriteAllText((Join-Path $script:victim $f), '{"name":"eva"}', $script:enc)
            }
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Write-Error {}
            Mock Start-Sleep {}
        }

        It 'does not delete styles/eva when asked to tune "../styles/eva"' {
            # Under Pester stdin is redirected, so the tuner now bails at its
            # console guard -- but it used to get all the way to the finally
            # block, whose Remove-Item took the style with it.
            try { Invoke-TerminalStyleTune -StyleName '../styles/eva' } catch { }
            Test-Path -LiteralPath $script:victim | Should -BeTrue -Because 'the tuner must never delete a style directory'
            (Get-ChildItem -LiteralPath $script:victim).Count | Should -Be 4
        }

        It 'does not delete the base named by a tuned style tune.json' {
            $shared = Join-Path $script:stylesDir 'shared'
            New-Item -ItemType Directory -Path $shared -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $shared 'scheme.json'), '{"name":"shared"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $shared 'tune.json'),
                '{"schemaVersion":1,"base":"../styles/eva","brightness":0,"saturation":0,"opacity":100,"fontFace":"Menlo","fontSize":12}', $script:enc)

            try { Invoke-TerminalStyleTune -StyleName 'shared' } catch { }
            Test-Path -LiteralPath $script:victim | Should -BeTrue -Because 'a tune.json base must not reach out of the styles dir'
        }

        It 'keeps its scratch directory inside .tune-preview, keyed per session' {
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            # Not keyed on the style name: two concurrent sessions on the same
            # base shared one scratch dir, and the first to exit deleted it out
            # from under the second, whose next preview write then threw from
            # inside the save path.
            $src | Should -Not -Match "'\.tune-preview'\) \`$baseName"
            $src | Should -Match 'session-\{0\}'
            $src | Should -Match '\$PID'
            # And the recursive delete is proven to target the session dir --
            # the whole session goes, so nothing accumulates under .tune-preview.
            $src | Should -Match 'GetFullPath\(\$scratchSession\)'
            $src | Should -Match 'Remove-Item -LiteralPath \$scratchSession'

            # But the style directory INSIDE the session still carries the base
            # name. Get-StyleBundledBackground keys the background cache on
            # `Split-Path -Leaf $StyleDir`, so a leaf of `session-1234` matched
            # no cache entry and no .no-background marker: every preview fell
            # through to the lazy fetch and tried four Invoke-WebRequest calls
            # for `session-1234.{gif,png,jpg,jpeg}` at 10s each -- up to 40
            # seconds on a blank screen -- then left a permanent cache dir.
            $src | Should -Match '\$scratchDir\s*=\s*Join-Path \$scratchSession \$baseName'
        }
    }
}

Describe 'the name gate rejects paths, not names' {
    InModuleScope TerminalStyles {
        # Regression on the fix itself. The gate was first written as the
        # tuner's create-time rule, ^[A-Za-z0-9._-]+$ -- which rejects spaces
        # and non-ASCII. README's "Adding your own style" puts no constraint on
        # a folder name, and Get-AvailableStyles enumerates directories with no
        # filter, so a style called "My Theme" would still list and still
        # tab-complete, then fail at apply, tune, current, the shell-startup
        # re-emit and background inheritance. That is worse than not existing.

        It 'accepts a hand-authored name the README allows: <name>' -ForEach @(
            @{ name = 'My Theme' }
            @{ name = 'café' }
            @{ name = 'theme (copy)' }
            @{ name = '日本語' }
            @{ name = 'a+b' }
            @{ name = ('x' * 200) }
        ) {
            Test-StyleNameIsSingleSegment -Name $name | Should -BeTrue -Because "'$name' is a legal directory name"
        }

        It 'still rejects anything that is not one segment: <name>' -ForEach @(
            @{ name = '../styles/eva' }
            @{ name = '..\styles\eva' }
            @{ name = 'a/b' }
            @{ name = 'a\b' }
            @{ name = '.' }
            @{ name = '..' }
            @{ name = '' }
            @{ name = '   ' }
        ) {
            Test-StyleNameIsSingleSegment -Name $name | Should -BeFalse -Because "'$name' is a path or not a name"
        }

        It 'resolves a hand-authored style whose name has a space' {
            $script:TStylesDataRoot   = Join-Path $TestDrive ('n-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesModuleRoot = Join-Path $TestDrive ('q-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $dir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'My Theme'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), '{"name":"My Theme"}',
                [System.Text.UTF8Encoding]::new($false))

            Get-StyleDir -StyleName 'My Theme' | Should -Be $dir -Because 'the gate must not break styles that already work'
        }

        It 'keeps the stricter rule for names the tuner CREATES' {
            # Save-As invents a directory, so it can afford to be conservative.
            Test-StyleNameValid -Name 'My Theme'   | Should -BeFalse
            Test-StyleNameValid -Name 'eva-night'  | Should -BeTrue
            Test-StyleNameValid -Name ('a' * 65)   | Should -BeFalse
            Test-StyleNameValid -Name '..'         | Should -BeFalse
        }
    }
}
