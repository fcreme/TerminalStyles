# Pester 5 tests for four tuner defects that each produced a wrong result
# quietly, with the tuner reporting success:
#
#   * New-TunedThemeObject handed back $null for a base theme.json it could not
#     parse, and ConvertTo-Json wrote that out as the literal `null`.
#   * Resolve-TuneSeed swapped BaseName/BaseDir to the base BEFORE the [int]
#     casts that can throw, so a corrupt tune.json silently moved the tuner onto
#     a different style.
#   * Esc restored the working BASE's colours rather than the style the user
#     opened the tuner on, which are different files for a tuned style.
#   * A tuned style re-applied its deltas against a base that had since been
#     re-baked, doubling the tune -- silently, and compounding each round.
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

Describe 'New-TunedThemeObject survives an unusable base theme.json' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:baseDir = Join-Path $TestDrive ('base-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:baseDir -Force | Out-Null
        }

        # Each of these used to yield $null, which ConvertTo-Json serialises as
        # the four characters `null` -- a saved style with no colorScheme, no
        # opacity and no font, reported as applied.
        It "still writes the knobs when the base theme.json is <label>" -ForEach @(
            @{ label = 'empty';          content = '' }
            @{ label = 'whitespace';     content = "   `n " }
            @{ label = 'truncated';      content = '{"colorScheme":"eva",' }
            @{ label = 'a bare scalar';  content = '42' }
            @{ label = 'a bare string';  content = '"hello"' }
            @{ label = 'a JSON array';   content = '[1,2,3]' }
        ) {
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'theme.json'), $content, $script:enc)

            $theme = New-TunedThemeObject -BaseStyleDir $script:baseDir -ColorScheme 'eva-night' `
                -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 14

            $theme            | Should -Not -BeNullOrEmpty
            $theme.colorScheme | Should -Be 'eva-night'
            $theme.opacity     | Should -Be 85
            $theme.font.face   | Should -Be 'JetBrains Mono'
            $theme.font.size   | Should -Be 14
            ($theme | ConvertTo-Json -Depth 16) | Should -Not -Be 'null'
        }

        It 'still preserves a readable base theme.json' {
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'theme.json'),
                '{"colorScheme":"eva","opacity":100,"font":{"face":"Menlo","size":11,"weight":"semi-bold"},"backgroundImage":"{{BACKGROUND_IMAGE}}"}',
                $script:enc)

            $theme = New-TunedThemeObject -BaseStyleDir $script:baseDir -ColorScheme 'eva-night' `
                -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 14

            $theme.font.weight     | Should -Be 'semi-bold'      -Because 'the base carries it and the tuner does not set it'
            $theme.backgroundImage | Should -Be '{{BACKGROUND_IMAGE}}'
            $theme.colorScheme     | Should -Be 'eva-night'
        }
    }
}

Describe 'Resolve-TuneSeed commits all-or-nothing' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot   = Join-Path $TestDrive ('data-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesModuleRoot = Join-Path $TestDrive ('mod-'  + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:styles = Join-Path $script:TStylesDataRoot 'styles'

            # A base, and a tuned style pointing at it.
            $script:evaDir = Join-Path $script:styles 'eva'
            New-Item -ItemType Directory -Path $script:evaDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'), '{"name":"eva"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'theme.json'),
                '{"opacity":100,"font":{"face":"Menlo","size":11}}', $script:enc)

            $script:nightDir = Join-Path $script:styles 'eva-night'
            New-Item -ItemType Directory -Path $script:nightDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'scheme.json'), '{"name":"eva-night"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'theme.json'),
                '{"opacity":75,"font":{"face":"JetBrains Mono","size":14}}', $script:enc)
        }

        It 'seeds from a well-formed tune.json' {
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'tune.json'),
                '{"schemaVersion":1,"base":"eva","brightness":-35,"saturation":20,"opacity":75,"fontFace":"JetBrains Mono","fontSize":14}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $seed.BaseName   | Should -Be 'eva'
            $seed.BaseDir    | Should -Be $script:evaDir
            $seed.Brightness | Should -Be -35
        }

        It 'does not half-apply a tune.json whose numbers are not numbers' {
            # The failing cast is on brightness, which used to be assigned AFTER
            # BaseName and BaseDir. The catch swallowed the throw, the fallback
            # ran, and the tuner opened on eva -- the base -- with neutral knobs.
            # Saving then re-baked eva-night as a copy of eva.
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'tune.json'),
                '{"schemaVersion":1,"base":"eva","brightness":"not-a-number","saturation":20,"opacity":75,"fontFace":"JetBrains Mono","fontSize":14}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir

            $seed.BaseName | Should -Be 'eva-night' -Because 'a corrupt tune.json must not move the tuner onto another style'
            $seed.BaseDir  | Should -Be $script:nightDir
            # ...and the fallback then seeds from the style's OWN theme.json.
            $seed.Opacity  | Should -Be 75
            $seed.FontFace | Should -Be 'JetBrains Mono'
            $seed.FontSize | Should -Be 14
            $seed.Brightness | Should -Be 0
        }

        It 'falls back cleanly when tune.json is not JSON at all' {
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'tune.json'), 'not json {{{', $script:enc)
            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $seed.BaseName | Should -Be 'eva-night'
            $seed.BaseDir  | Should -Be $script:nightDir
            $seed.Opacity  | Should -Be 75
        }
    }
}

Describe 'Esc restores the style the tuner was opened on' {
    InModuleScope TerminalStyles {
        It 'reads the opened style, not the working base' {
            # For a tuned style these are different files: tuning 'eva-night'
            # resolves base 'eva' as the working base because that is what the
            # deltas are measured from. Restoring the base repainted the
            # terminal as eva and reported "Reverted.", leaving the user on a
            # style they had never chosen and did not have when they started.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match '\$openedScheme\s*=\s*if \(\$styleDir -eq \$baseDir\)'
            $block = [regex]::Match($src, '(?s)\$restoreBaseLook = \{.*?\n    \}').Value
            $block | Should -Match '\$openedScheme'
            $block | Should -Not -Match 'Scheme \$baseScheme'
        }
    }
}

Describe 'a tuned style does not double-apply when its base is re-baked' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot   = Join-Path $TestDrive ('d-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesModuleRoot = Join-Path $TestDrive ('m-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:styles = Join-Path $script:TStylesDataRoot 'styles'

            $script:evaDir = Join-Path $script:styles 'eva'
            New-Item -ItemType Directory -Path $script:evaDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                '{"name":"eva","background":"#0a0006","foreground":"#cfd0d4"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'theme.json'),
                '{"opacity":100,"font":{"face":"Menlo","size":11}}', $script:enc)
        }

        It 'records what the deltas were measured against' {
            $adj = [pscustomobject]@{ name = 'eva'; background = '#050003' }
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $script:evaDir -BaseName 'eva' `
                -Brightness -35 -Saturation 20 -Opacity 75 -FontFace 'Menlo' -FontSize 11 | Out-Null

            $tune = Get-Content (Join-Path $script:styles 'eva-night/tune.json') -Raw | ConvertFrom-Json
            $tune.baseFingerprint | Should -Not -BeNullOrEmpty
            $tune.baseFingerprint | Should -Be (Get-StyleSchemeFingerprint -StyleDir $script:evaDir)
        }

        It 'still seeds the deltas while the base is unchanged' {
            $adj = [pscustomobject]@{ name = 'eva'; background = '#050003' }
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $script:evaDir -BaseName 'eva' `
                -Brightness -35 -Saturation 20 -Opacity 75 -FontFace 'Menlo' -FontSize 11 | Out-Null

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir (Join-Path $script:styles 'eva-night')
            $seed.BaseName    | Should -Be 'eva'
            $seed.Brightness  | Should -Be -35
            $seed.BaseChanged | Should -BeFalse
        }

        It 'declines to re-apply them once the base has been re-baked' {
            # The Overwrite path: the base's own scheme.json is rewritten with
            # its tune baked in. eva-night's -35 was measured against the OLD
            # file, so seeding it against the new one previews at -55 and saving
            # bakes the drift in -- compounding on every round.
            $adj = [pscustomobject]@{ name = 'eva'; background = '#050003' }
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $script:evaDir -BaseName 'eva' `
                -Brightness -35 -Saturation 20 -Opacity 75 -FontFace 'Menlo' -FontSize 11 | Out-Null

            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                '{"name":"eva","background":"#060004","foreground":"#a6a7aa"}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir (Join-Path $script:styles 'eva-night')
            $seed.BaseChanged | Should -BeTrue
            $seed.Brightness  | Should -Be 0  -Because 'the deltas no longer describe a distance from this base'
            $seed.Saturation  | Should -Be 0
            $seed.BaseName    | Should -Be 'eva-night' -Because 'seeding falls back to the style itself'
            # ...but the NOTICE has to name the base that actually moved. Using
            # BaseName there produced "'eva-night' has changed since this style
            # was tuned" while the user was tuning eva-night.
            $seed.ChangedBaseName | Should -Be 'eva' -Because 'the notice must name the base, not the style'
            $seed.Opacity     | Should -Be 75 -Because 'opacity/font still come from the style''s own theme.json'
        }

        It 'keeps seeding a tune.json written before fingerprints existed' {
            # Missing means "unknown", not "changed" -- an existing tuned style
            # must not lose its knobs just because it predates this field.
            $nightDir = Join-Path $script:styles 'eva-old'
            New-Item -ItemType Directory -Path $nightDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $nightDir 'scheme.json'), '{"name":"eva-old"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $nightDir 'tune.json'),
                '{"schemaVersion":1,"base":"eva","brightness":-35,"saturation":20,"opacity":75,"fontFace":"Menlo","fontSize":11}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-old' -StyleDir $nightDir
            $seed.BaseName    | Should -Be 'eva'
            $seed.Brightness  | Should -Be -35
            $seed.BaseChanged | Should -BeFalse
        }

        It 'tells the user why the knobs came up neutral' {
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match '\$baseChanged = \$seed\.BaseChanged'
            $src | Should -Match 'has changed since this style was tuned'
        }
    }
}

Describe 'the base-changed notice does not cry wolf' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot   = Join-Path $TestDrive ('od-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesModuleRoot = Join-Path $TestDrive ('om-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:bundled = Join-Path $script:TStylesModuleRoot 'styles/eva'
            New-Item -ItemType Directory -Path $script:bundled -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:bundled 'scheme.json'),
                '{"name":"eva","background":"#0a0006"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:bundled 'theme.json'),
                '{"opacity":100,"font":{"face":"Menlo","size":11}}', $script:enc)
        }

        It 'stays quiet when a style is re-tuned after an Overwrite save' {
            # Overwrite records the fingerprint of the BUNDLED copy it baked
            # from, then resolves user-first to its own baked result -- so the
            # comparison always differs. Firing there told the user a style had
            # changed under itself, on the first re-tune of every overwrite
            # save. The self-reference guard already handles this case.
            Save-TunedStyle -AdjustedScheme ([pscustomobject]@{ name = 'eva'; background = '#060004' }) `
                -SaveName 'eva' -BaseStyleDir $script:bundled -BaseName 'eva' `
                -Brightness -20 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 11 | Out-Null

            $userEva = Join-Path $script:TStylesDataRoot 'styles/eva'
            $seed = Resolve-TuneSeed -StyleName 'eva' -StyleDir $userEva
            $seed.BaseChanged     | Should -BeFalse -Because 'nothing changed under this style; it IS the style'
            $seed.ChangedBaseName | Should -BeNullOrEmpty
        }

        It 'stays quiet when the base cannot be read, rather than dropping the deltas' {
            # Get-StyleSchemeFingerprint returns $null on a read failure -- a
            # lock, a permission denial, an antivirus hold. Reading that as
            # "changed" discarded the user's brightness/saturation and, on save,
            # rewrote tune.json with the style as its own base: lineage gone.
            Mock Get-StyleSchemeFingerprint { $null } -ParameterFilter { $StyleDir -eq $script:bundled }

            $night = Join-Path $script:TStylesDataRoot 'styles/eva-night'
            New-Item -ItemType Directory -Path $night -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $night 'scheme.json'), '{"name":"eva-night"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $night 'tune.json'),
                '{"schemaVersion":1,"base":"eva","baseFingerprint":"deadbeef","brightness":-35,"saturation":20,"opacity":75,"fontFace":"Menlo","fontSize":11}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $night
            $seed.BaseChanged | Should -BeFalse -Because 'unreadable is unknown, not changed'
            $seed.Brightness  | Should -Be -35  -Because 'the deltas must survive a transient read failure'
        }
    }
}

Describe 'a partial tune.json does not zero the knobs' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:TStylesDataRoot   = Join-Path $TestDrive ('p-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:TStylesModuleRoot = Join-Path $TestDrive ('r-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:styles = Join-Path $script:TStylesDataRoot 'styles'
            $eva = Join-Path $script:styles 'eva'
            New-Item -ItemType Directory -Path $eva -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $eva 'scheme.json'), '{"name":"eva"}', $script:enc)

            $script:mine = Join-Path $script:styles 'mine'
            New-Item -ItemType Directory -Path $script:mine -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:mine 'scheme.json'), '{"name":"mine"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $script:mine 'theme.json'),
                '{"colorScheme":"mine","opacity":85,"font":{"face":"Menlo","size":14}}', $script:enc)
        }

        # `{"base":"eva"}` is a shape the project itself writes (the live preview
        # writes exactly that) and treats as valid. [int]$null is 0, so it seeded
        # Opacity 0 and FontSize 0 -- and a straight Enter save put opacity 0
        # (fully transparent) and font size 0 onto the Windows Terminal profile.
        It 'keeps the style''s own opacity and font when tune.json omits them: <label>' -ForEach @(
            @{ label = 'base only';       json = '{"base":"eva"}' }
            @{ label = 'explicit nulls';  json = '{"base":"eva","opacity":null,"fontSize":null,"fontFace":null}' }
            @{ label = 'deltas only';     json = '{"base":"eva","brightness":-20,"saturation":10}' }
        ) {
            [System.IO.File]::WriteAllText((Join-Path $script:mine 'tune.json'), $json, $script:enc)
            $seed = Resolve-TuneSeed -StyleName 'mine' -StyleDir $script:mine

            $seed.Opacity  | Should -Be 85     -Because 'the style declares 85 and tune.json says nothing'
            $seed.FontSize | Should -Be 14
            $seed.FontFace | Should -Be 'Menlo'
            $seed.Opacity  | Should -Not -Be 0 -Because 'opacity 0 is a fully transparent window'
        }

        It 'still honours the values tune.json DOES carry' {
            [System.IO.File]::WriteAllText((Join-Path $script:mine 'tune.json'),
                '{"base":"eva","brightness":-20,"saturation":10,"opacity":60,"fontFace":"Hack","fontSize":18}', $script:enc)
            $seed = Resolve-TuneSeed -StyleName 'mine' -StyleDir $script:mine
            $seed.Brightness | Should -Be -20
            $seed.Opacity    | Should -Be 60
            $seed.FontFace   | Should -Be 'Hack'
            $seed.FontSize   | Should -Be 18
        }

        It 'accepts a legitimately recorded opacity of 0' {
            # 0 is a real value when the user actually chose it; only ABSENCE
            # must fall back.
            [System.IO.File]::WriteAllText((Join-Path $script:mine 'tune.json'),
                '{"base":"eva","opacity":0}', $script:enc)
            (Resolve-TuneSeed -StyleName 'mine' -StyleDir $script:mine).Opacity | Should -Be 0
        }
    }
}

Describe 'the one-hop guards compare paths the way the filesystem does' {
    InModuleScope TerminalStyles {
        It 'uses Test-SameStyleDirectory rather than -eq/-ne' {
            # PowerShell's operators are case-insensitive everywhere, so on a
            # case-sensitive volume styles/eva and styles/Eva are two
            # directories that -ne collapses into one -- and the guard then
            # fires when it should not. The helper exists for exactly this and
            # was called from Save-TunedStyle alone.
            $seedSrc = (Get-Command Resolve-TuneSeed).ScriptBlock.ToString()
            $seedSrc | Should -Match 'Test-SameStyleDirectory -A \$resolvedBaseDir -B \$StyleDir'
            $seedSrc | Should -Not -Match '\$resolvedBaseDir -ne \$StyleDir'

            $bgSrc = (Get-Command Get-TunedBaseBackground).ScriptBlock.ToString()
            $bgSrc | Should -Match 'Test-SameStyleDirectory'
            $bgSrc | Should -Not -Match '\$baseDir -eq \$StyleDir'

            $resSrc = (Get-Command Test-StyleResolved).ScriptBlock.ToString()
            $resSrc | Should -Match 'Test-SameStyleDirectory'
            $resSrc | Should -Not -Match '\$baseDir -ne \$StyleDir'
        }
    }
}
