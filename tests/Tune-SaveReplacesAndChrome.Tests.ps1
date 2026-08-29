# Pester 5 tests for two defects where the tuner's own output was wrong:
#
#   * The Save-As collision prompt promises "'<name>' already exists and will be
#     REPLACED" and performed a MERGE. Anything the new base did not itself ship
#     survived from the old style, so the replaced style printed the wrong
#     theme's banner and set the wrong prompt.
#   * The tuner's menu painted itself with -ForegroundColor Cyan/Gray/Yellow,
#     which PowerShell maps onto the very palette slots the tuner has just
#     retinted over OSC 4. On the bundled light theme gitbash the rows reach
#     exactly 1.000:1 against the background at Brightness +55 -- the menu
#     becomes invisible while the user is dragging the slider that did it.
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
    $script:repoRoot = $repoRoot
}

Describe 'a Save-As over an existing style really replaces it' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot = Join-Path $TestDrive ('d-' + [guid]::NewGuid().Guid.Substring(0, 8))

            # A base that ships everything.
            $script:rich = Join-Path $TestDrive ('rich-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:rich -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:rich 'theme.json'), '{"opacity":100}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:rich 'profile.ps1'), '# eva profile', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:rich 'prompt.sh'),   '# eva prompt', $script:enc)

            # A base that legitimately ships neither -- README documents both as
            # optional, so this is a normal hand-written style.
            $script:plain = Join-Path $TestDrive ('plain-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:plain -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:plain 'theme.json'), '{"opacity":100}', $script:enc)

            $script:scheme = [pscustomobject]@{ name = 'x'; background = '#000000' }
            $script:dest   = Join-Path $script:TStylesDataRoot 'styles/mytheme'
        }

        It 'drops the old profile.ps1 and prompt.sh when the new base has none' {
            # Save As 'mytheme' from the rich base...
            Save-TunedStyle -AdjustedScheme $script:scheme -SaveName 'mytheme' `
                -BaseStyleDir $script:rich -BaseName 'rich' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12 | Out-Null
            Test-Path -LiteralPath (Join-Path $script:dest 'profile.ps1') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:dest 'prompt.sh')   | Should -BeTrue

            # ...then Save As the SAME name from a base that ships neither.
            Save-TunedStyle -AdjustedScheme $script:scheme -SaveName 'mytheme' `
                -BaseStyleDir $script:plain -BaseName 'plain' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12 | Out-Null

            Test-Path -LiteralPath (Join-Path $script:dest 'profile.ps1') |
                Should -BeFalse -Because 'the prompt said REPLACED, and this profile prints the wrong theme''s banner'
            Test-Path -LiteralPath (Join-Path $script:dest 'prompt.sh') |
                Should -BeFalse -Because 'the prompt said REPLACED, and this sets the wrong zsh/bash prompt'
        }

        It 'still replaces them when the new base has its own' {
            Save-TunedStyle -AdjustedScheme $script:scheme -SaveName 'mytheme' `
                -BaseStyleDir $script:plain -BaseName 'plain' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12 | Out-Null
            Save-TunedStyle -AdjustedScheme $script:scheme -SaveName 'mytheme' `
                -BaseStyleDir $script:rich -BaseName 'rich' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12 | Out-Null

            (Get-Content (Join-Path $script:dest 'prompt.sh') -Raw).Trim() | Should -Be '# eva prompt'
            (Get-Content (Join-Path $script:dest 'profile.ps1') -Raw)      | Should -Match 'eva profile'
        }

        It 'leaves an Overwrite re-tune alone, where base and destination are one directory' {
            # $sameDir: the file being "removed" would be the source itself.
            $selfDir = Join-Path $script:TStylesDataRoot 'styles/self'
            New-Item -ItemType Directory -Path $selfDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $selfDir 'theme.json'), '{"opacity":100}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $selfDir 'prompt.sh'),  '# own prompt', $script:enc)

            Save-TunedStyle -AdjustedScheme $script:scheme -SaveName 'self' `
                -BaseStyleDir $selfDir -BaseName 'self' `
                -Brightness -10 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12 | Out-Null

            (Get-Content (Join-Path $selfDir 'prompt.sh') -Raw).Trim() |
                Should -Be '# own prompt' -Because 'an Overwrite re-tune must keep the prompt it already had'
        }
    }
}

Describe 'the tuner menu stays legible at every brightness' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # NOT the outer $script:repoRoot -- inside InModuleScope, $script:
            # is the MODULE's scope, so the file-level variable is invisible
            # here and Join-Path got $null. The module knows where it lives.
            $script:styleRoot = Join-Path $script:TStylesModuleRoot 'styles'

            function script:Get-RelLuminance([string]$hex) {
                $h = (ConvertTo-NormalHex -Hex $hex).TrimStart('#')
                $c = @(0, 2, 4) | ForEach-Object {
                    $v = [Convert]::ToInt32($h.Substring($_, 2), 16) / 255.0
                    if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) }
                }
                0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]
            }
            function script:Get-ContrastRatio($a, $b) {
                $l1 = script:Get-RelLuminance $a; $l2 = script:Get-RelLuminance $b
                if ($l1 -lt $l2) { $t = $l1; $l1 = $l2; $l2 = $t }
                ($l1 + 0.05) / ($l2 + 0.05)
            }
        }

        It 'does not paint its chrome with the palette slots it is editing' {
            # -ForegroundColor Cyan/DarkGray/Yellow/Gray map to SGR 96/90/93/37,
            # i.e. brightCyan/brightBlack/brightYellow/white -- the slots the
            # tuner retints over OSC 4 on every colour keypress.
            $src   = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $block = [regex]::Match($src, '(?s)\$drawMenu = \{.*?\n    \}').Value
            $block | Should -Not -BeNullOrEmpty
            $block | Should -Not -Match '-ForegroundColor (Cyan|DarkGray|Yellow|Gray)'
            $block | Should -Match '\$ui = & \$chrome \$adjusted'
        }

        It 'holds contrast where the old ConsoleColor chrome fell to 1:1' {
            # gitbash at +55 measured exactly 1.000:1 with the old chrome --
            # white == #ffffff == the background, so the menu vanished.
            $scheme = Get-Content (Join-Path $script:styleRoot 'gitbash/scheme.json') -Raw | ConvertFrom-Json

            foreach ($b in 0, 20, 55, 100) {
                $adj = Get-AdjustedScheme -Scheme $scheme -Brightness $b
                # what the OLD chrome resolved to for a non-selected row
                $old = script:Get-ContrastRatio $adj.background $adj.white
                # what the NEW chrome picks: dark ink on a light background
                $new = script:Get-ContrastRatio $adj.background '#282828'

                $new | Should -BeGreaterThan 4.5 -Because "at brightness $b the menu must stay readable"
                if ($b -ge 55) {
                    $old | Should -BeLessThan 1.1 -Because "this is the regression being fixed (brightness $b)"
                }
            }
        }
    }
}
