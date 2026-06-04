# Pester 5 tests for Resolve-TuneSeed: computes the working base style + the
# initial knob values (brightness/saturation/opacity/font) for `tstyles tune`.
# Extracted from Invoke-TerminalStyleTune so the seeding rules are testable.
#
# Regression guard: a tuned style whose recorded base was deleted/renamed must
# re-seed opacity/font from its OWN theme.json, not snap back to hardcoded
# defaults (which silently discarded the saved values on save).
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

Describe 'Resolve-TuneSeed' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesDataRoot 'styles')   -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesModuleRoot 'styles') -Force | Out-Null
            $script:enc = [System.Text.UTF8Encoding]::new($false)
        }

        It 'seeds a plain (non-tuned) style from its own theme.json' {
            $dir = Join-Path $script:TStylesModuleRoot 'styles\plain'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), '{"name":"plain","background":"#101010"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $dir 'theme.json'),  '{"colorScheme":"plain","opacity":80,"font":{"face":"Hack","size":14}}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'plain' -StyleDir $dir
            $seed.BaseName   | Should -Be 'plain'
            $seed.BaseDir    | Should -Be $dir
            $seed.Brightness | Should -Be 0
            $seed.Saturation | Should -Be 0
            $seed.Opacity    | Should -Be 80
            $seed.FontFace   | Should -Be 'Hack'
            $seed.FontSize   | Should -Be 14
        }

        It 'seeds a tuned style from its tune.json deltas + the resolved base dir' {
            $baseDir = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $baseDir 'scheme.json'), '{"name":"eva","background":"#101010"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $baseDir 'theme.json'),  '{"colorScheme":"eva","opacity":100,"font":{"face":"Cascadia Code","size":11}}', $script:enc)

            $tunedDir = Join-Path $script:TStylesDataRoot 'styles\eva-night'
            New-Item -ItemType Directory -Path $tunedDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'scheme.json'), '{"name":"eva-night","background":"#101010"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'theme.json'),  '{"colorScheme":"eva-night","opacity":70,"font":{"face":"JetBrains Mono","size":13}}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'tune.json'),   '{"schemaVersion":1,"base":"eva","brightness":-10,"saturation":5,"opacity":70,"fontFace":"JetBrains Mono","fontSize":13}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $tunedDir
            $seed.BaseName   | Should -Be 'eva'
            $seed.BaseDir    | Should -Be $baseDir
            $seed.Brightness | Should -Be -10
            $seed.Saturation | Should -Be 5
            $seed.Opacity    | Should -Be 70
            $seed.FontFace   | Should -Be 'JetBrains Mono'
            $seed.FontSize   | Should -Be 13
        }

        It 'falls back to its OWN theme.json when the recorded base was deleted' {
            # tune.json points at a base that no longer exists; the style keeps its
            # own baked theme.json. Seeding must use those values, not defaults.
            $tunedDir = Join-Path $script:TStylesDataRoot 'styles\orphan'
            New-Item -ItemType Directory -Path $tunedDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'scheme.json'), '{"name":"orphan","background":"#101010"}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'theme.json'),  '{"colorScheme":"orphan","opacity":55,"font":{"face":"Consolas","size":12}}', $script:enc)
            [System.IO.File]::WriteAllText((Join-Path $tunedDir 'tune.json'),   '{"schemaVersion":1,"base":"ghost","brightness":0,"saturation":0,"opacity":70,"fontFace":"X","fontSize":99}', $script:enc)

            $seed = Resolve-TuneSeed -StyleName 'orphan' -StyleDir $tunedDir
            $seed.BaseName | Should -Be 'orphan'
            $seed.BaseDir  | Should -Be $tunedDir
            $seed.Opacity  | Should -Be 55          # from own theme.json, NOT default 100 or tune's 70
            $seed.FontFace | Should -Be 'Consolas'  # from own theme.json, NOT default/$null
            $seed.FontSize | Should -Be 12
        }
    }
}
