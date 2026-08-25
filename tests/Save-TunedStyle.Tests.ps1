# Pester 5 tests for Save-TunedStyle: materializes a tuned style into the
# user-styles dir (scheme.json/theme.json/profile.ps1/tune.json).
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

Describe 'Save-TunedStyle' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            # Build a fake base style dir with theme.json + profile.ps1.
            $script:baseDir = Join-Path $TestDrive 'base\eva'
            New-Item -ItemType Directory -Path $script:baseDir -Force | Out-Null
            $baseTheme = '{"colorScheme":"eva","opacity":100,"font":{"face":"Cascadia Code","size":11,"weight":"semi-bold"},"backgroundImage":"{{BACKGROUND_IMAGE}}"}'
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'theme.json'), $baseTheme, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:baseDir 'profile.ps1'), '# eva profile', [System.Text.UTF8Encoding]::new($false))
            $script:adjusted = [pscustomobject]@{ name = 'eva'; background = '#000000'; red = '#aa0000' }
        }

        It 'writes the four files with the save name as scheme name and colorScheme' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-night' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness -15 -Saturation 10 -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 12

            $dir = Join-Path $TestDrive 'styles\eva-night'
            Test-Path (Join-Path $dir 'scheme.json')  | Should -BeTrue
            Test-Path (Join-Path $dir 'theme.json')   | Should -BeTrue
            Test-Path (Join-Path $dir 'profile.ps1')  | Should -BeTrue
            Test-Path (Join-Path $dir 'tune.json')    | Should -BeTrue

            $scheme = Get-Content (Join-Path $dir 'scheme.json') -Raw | ConvertFrom-Json
            $scheme.name | Should -Be 'eva-night'

            $theme = Get-Content (Join-Path $dir 'theme.json') -Raw | ConvertFrom-Json
            $theme.colorScheme | Should -Be 'eva-night'
            $theme.opacity     | Should -Be 85
            $theme.font.face   | Should -Be 'JetBrains Mono'
            $theme.font.size   | Should -Be 12
            $theme.font.weight | Should -Be 'semi-bold'   # preserved from base
            $theme.backgroundImage | Should -Be '{{BACKGROUND_IMAGE}}'  # placeholder kept
        }

        It 'round-trips the deltas in tune.json with the base name' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-night' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness -15 -Saturation 10 -Opacity 85 -FontFace 'JetBrains Mono' -FontSize 12
            $tune = Get-Content (Join-Path $TestDrive 'styles\eva-night\tune.json') -Raw | ConvertFrom-Json
            $tune.schemaVersion | Should -Be 1
            $tune.base          | Should -Be 'eva'
            $tune.brightness    | Should -Be -15
            $tune.saturation    | Should -Be 10
            $tune.opacity       | Should -Be 85
            $tune.fontFace      | Should -Be 'JetBrains Mono'
            $tune.fontSize      | Should -Be 12
        }

        It 'overwrite (same name) writes into the base name folder' {
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness 5 -Saturation 0 -Opacity 100 -FontFace 'Consolas' -FontSize 11
            Test-Path (Join-Path $TestDrive 'styles\eva\scheme.json') | Should -BeTrue
            (Get-Content (Join-Path $TestDrive 'styles\eva\scheme.json') -Raw | ConvertFrom-Json).name | Should -Be 'eva'
        }

        It 'does not mutate the caller''s AdjustedScheme object' {
            $input = [pscustomobject]@{ name = 'eva'; background = '#000000' }
            Save-TunedStyle -AdjustedScheme $input -SaveName 'eva-clone' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Consolas' -FontSize 11
            $input.name | Should -Be 'eva'   # unchanged; the saved file got 'eva-clone'
            (Get-Content (Join-Path $TestDrive 'styles\eva-clone\scheme.json') -Raw | ConvertFrom-Json).name | Should -Be 'eva-clone'
        }

        It 'writes theme.json even when the base has no theme.json' {
            Remove-Item (Join-Path $script:baseDir 'theme.json') -Force
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-bare' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness 0 -Saturation 0 -Opacity 90 -FontFace 'Consolas' -FontSize 11
            $theme = Get-Content (Join-Path $TestDrive 'styles\eva-bare\theme.json') -Raw | ConvertFrom-Json
            $theme.colorScheme | Should -Be 'eva-bare'
            $theme.opacity     | Should -Be 90
            $theme.font.face   | Should -Be 'Consolas'
        }

        It 'omits profile.ps1 when the base has none' {
            Remove-Item (Join-Path $script:baseDir 'profile.ps1') -Force
            Save-TunedStyle -AdjustedScheme $script:adjusted -SaveName 'eva-no-profile' `
                -BaseStyleDir $script:baseDir -BaseName 'eva' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Consolas' -FontSize 11
            Test-Path (Join-Path $TestDrive 'styles\eva-no-profile\profile.ps1') | Should -BeFalse
        }
    }
}

Describe 'Save-TunedStyle carries the shell prompt' {
    InModuleScope TerminalStyles {
        It "copies the base style's prompt.sh alongside profile.ps1" {
            # Regression: tuned styles shipped profile.ps1 but not prompt.sh, so
            # a zsh user who tuned anything kept the colors and silently lost the
            # banner and prompt -- with nothing to indicate why.
            $script:TStylesDataRoot = $TestDrive
            $base = Join-Path $TestDrive 'base'
            New-Item -ItemType Directory -Force -Path $base | Out-Null
            foreach ($f in 'scheme.json','theme.json') {
                [System.IO.File]::WriteAllText((Join-Path $base $f), '{}', [System.Text.UTF8Encoding]::new($false))
            }
            [System.IO.File]::WriteAllText((Join-Path $base 'profile.ps1'), '# ps',  [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $base 'prompt.sh'),  '# sh',  [System.Text.UTF8Encoding]::new($false))

            $scheme = [pscustomobject]@{ name = 'base'; background = '#000000' }
            Save-TunedStyle -AdjustedScheme $scheme -SaveName 'tuned' -BaseName 'base' -BaseStyleDir $base `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12

            $dest = Join-Path (Join-Path $TestDrive 'styles') 'tuned'
            Test-Path -LiteralPath (Join-Path $dest 'profile.ps1') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $dest 'prompt.sh')   | Should -BeTrue
        }
    }
}

Describe 'Save-TunedStyle re-tuning a style saved with Overwrite' {
    # Overwrite saves into the user styles dir under the SAME name, so the next
    # `tstyles tune <name>` has $BaseStyleDir == $destDir and every "copy from
    # base to dest" becomes a copy of a file onto itself: Copy-Item threw a red
    # "Cannot overwrite the item with itself" for prompt.sh, and the profile
    # marker accumulated one line per save.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            # The base IS the destination -- exactly what Overwrite produces.
            $script:selfDir = Join-Path (Join-Path $TestDrive 'styles') 'eva-night'
            New-Item -ItemType Directory -Path $script:selfDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:selfDir 'theme.json'),
                '{"colorScheme":"eva-night","opacity":90}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:selfDir 'profile.ps1'),
                '# eva profile', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:selfDir 'prompt.sh'),
                'ts_title "eva"', [System.Text.UTF8Encoding]::new($false))
            $script:adj = [pscustomobject]@{ name = 'eva-night'; background = '#000000' }
        }

        It 'writes no error when the base and the destination are the same dir' {
            # Deliberately NOT `Should -Not -Throw`: Copy-Item onto itself raises
            # a NON-terminating error ("Cannot overwrite the item ... with
            # itself"), so nothing is ever thrown -- the user just gets a red
            # line at save time, after they have already committed to the save.
            # Only the error stream sees it.
            $err = $null
            Save-TunedStyle -AdjustedScheme $script:adj -SaveName 'eva-night' `
                -BaseStyleDir $script:selfDir -BaseName 'eva-night' `
                -Brightness -5 -Saturation 0 -Opacity 90 -FontFace 'Hack' -FontSize 12 `
                -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -BeNullOrEmpty
        }

        It 'keeps the prompt.sh it already had' {
            Save-TunedStyle -AdjustedScheme $script:adj -SaveName 'eva-night' `
                -BaseStyleDir $script:selfDir -BaseName 'eva-night' `
                -Brightness -5 -Saturation 0 -Opacity 90 -FontFace 'Hack' -FontSize 12
            Get-Content (Join-Path $script:selfDir 'prompt.sh') -Raw | Should -Match 'ts_title'
        }

        It 'carries exactly one tuned marker no matter how many times it is saved' {
            # The marker is what makes the profile byte-distinct from the base's,
            # so Get-CurrentStyleName can tell them apart. One is load-bearing;
            # three is just drift that grows the file on every save.
            foreach ($i in 1..3) {
                Save-TunedStyle -AdjustedScheme $script:adj -SaveName 'eva-night' `
                    -BaseStyleDir $script:selfDir -BaseName 'eva-night' `
                    -Brightness -5 -Saturation 0 -Opacity 90 -FontFace 'Hack' -FontSize 12
            }
            $profileText = Get-Content (Join-Path $script:selfDir 'profile.ps1') -Raw
            @([regex]::Matches($profileText, '(?m)^\s*#\s*tstyles-tuned:')).Count | Should -Be 1
            $profileText | Should -Match '# eva profile'
        }

        It 'still marks a normal save-as into a fresh dir' {
            $base = Join-Path $TestDrive 'base2'
            New-Item -ItemType Directory -Path $base -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $base 'profile.ps1'),
                '# base profile', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $base 'prompt.sh'),
                'ts_title "base"', [System.Text.UTF8Encoding]::new($false))

            Save-TunedStyle -AdjustedScheme $script:adj -SaveName 'fresh-name' `
                -BaseStyleDir $base -BaseName 'base2' `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'Hack' -FontSize 12

            $dest = Join-Path (Join-Path $TestDrive 'styles') 'fresh-name'
            $t = Get-Content (Join-Path $dest 'profile.ps1') -Raw
            $t | Should -Match '# tstyles-tuned: fresh-name'
            Test-Path (Join-Path $dest 'prompt.sh') | Should -BeTrue
        }
    }
}
