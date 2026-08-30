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

        It 'keeps every chrome role legible across every style and every brightness' {
            # The real test, driving the SHIPPED $chrome. What this replaced
            # compared the background against a hardcoded '#282828' -- a colour
            # $chrome never returns -- and sampled only brightness 0/20/55/100
            # on gitbash, all of which are positive, where that style's
            # background stays #ffffff and the light branch is always taken. So
            # the entire other branch was untested, and the menu could (and did)
            # go invisible in the middle of the luminance range with this test
            # green: gitbash at -55 gives a #b9b9b9 background where the row the
            # user is dragging measured 1.35:1, and forest +95, rain +85 and
            # snowday +95 all reached exactly 1.00:1.
            $ast = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast
            $assign = $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$chrome' }, $true) | Select-Object -First 1
            $assign | Should -Not -BeNullOrEmpty -Because 'the tuner must still derive its chrome'
            $sbAst = $assign.Right.Find({ param($n)
                $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)
            $chrome = [scriptblock]::Create($sbAst.ScriptBlock.Extent.Text.Trim('{', '}'))

            # Two assertions per role, because a single fixed floor is the
            # wrong shape here. Contrast against a MID-luminance background is
            # physically capped: at the crossover (L ~= 0.18) the best any
            # colour can do is about 4.6:1, so demanding 6.5 there would fail
            # on correct code. What can be demanded is (a) always readable, and
            # (b) the fit gets close to whatever the background actually allows.
            $hardFloor = @{ Title = 4.0; Sel = 4.0; Row = 4.0; Dim = 3.5; Warn = 4.0 }
            $wanted    = @{ Title = 7.0; Sel = 7.0; Row = 6.0; Dim = 4.5; Warn = 6.0 }

            $styles = @(Get-ChildItem -LiteralPath $script:styleRoot -Directory)
            $styles.Count | Should -BeGreaterThan 10 -Because 'the sweep must cover the bundled set'

            $worst = 99.0; $worstAt = ''
            $checked = 0
            foreach ($st in $styles) {
                $schemePath = Join-Path $st.FullName 'scheme.json'
                if (-not (Test-Path -LiteralPath $schemePath)) { continue }
                $scheme = Get-Content $schemePath -Raw | ConvertFrom-Json
                foreach ($b in -100, -75, -55, -40, -20, 0, 20, 40, 55, 75, 95, 100) {
                    $adj = Get-AdjustedScheme -Scheme $scheme -Brightness $b
                    $ui  = & $chrome $adj
                    foreach ($role in $wanted.Keys) {
                        $m = [regex]::Match([string]$ui.$role, '38;2;(\d+);(\d+);(\d+)')
                        $m.Success | Should -BeTrue -Because "$role must be truecolor, not a ConsoleColor"
                        $fg = '#{0:x2}{1:x2}{2:x2}' -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value
                        $r  = script:Get-ContrastRatio $adj.background $fg

                        # The ceiling this background allows against ANY colour.
                        $bl   = script:Get-RelLuminance $adj.background
                        $ceil = [Math]::Max(1.05 / ($bl + 0.05), ($bl + 0.05) / 0.05)
                        $goal = [Math]::Min($wanted[$role], $ceil * 0.9)

                        $checked++
                        if ($r -lt $worst) { $worst = $r; $worstAt = "$($st.Name) b=$b $role" }
                        $r | Should -BeGreaterThan $hardFloor[$role] `
                            -Because "$($st.Name) at brightness $b must keep $role readable (got $([Math]::Round($r,2)):1)"
                        $r | Should -BeGreaterThan $goal `
                            -Because "$($st.Name) at brightness ${b}: $role should use the headroom this background allows (ceiling $([Math]::Round($ceil,1)):1, got $([Math]::Round($r,2)):1)"
                    }
                }
            }
            # Anti-vacuity floor. The first version of this test iterated
            # `$floors.Keys` after that variable had been renamed away, so the
            # loop body never ran and the whole thing passed against the very
            # chrome it was written to reject.
            $checked | Should -BeGreaterThan 500 -Because 'the sweep must actually have measured something'
            Write-Verbose "worst chrome contrast: $([Math]::Round($worst,2)):1 at $worstAt" -Verbose:$false
        }

        It 'paints the SAVE prompt with the same fitted chrome, not ConsoleColors' {
            # The 0.8.18 fix stopped at $drawMenu. The save screen is drawn while
            # the OSC retint is still live -- the palette is restored later, in
            # $restoreBaseLook -- so -ForegroundColor Cyan/Gray there wrote
            # brightCyan and white onto slots the tuner had just retinted. On
            # gitbash at +55 the heading measured 1.25:1 and "Cancelled." exactly
            # 1.000:1, on the one screen where a destructive prompt must be read.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $idx = $src.IndexOf('Save tuned')
            $idx | Should -BeGreaterThan 0
            $tail = $src.Substring($idx)

            $tail | Should -Match '\$saveUi' -Because 'the save screen must use the fitted chrome'
            $tail | Should -Not -Match '-ForegroundColor (Cyan|Gray|DarkGray|White)' `
                -Because 'those map onto palette slots the tuner has just retinted'
        }
    }
}
