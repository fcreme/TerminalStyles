# Pester 5 tests for Get-TuneSavePlan: one decision for what a tuner save does
# to the folder it writes, which the question is rendered from and which
# Save-TunedStyle carries out.
#
# Three places decided it, and none of them was the code the user was asked
# about. The Save-As question was asked only when the folder held a
# scheme.json, and was worded as though the folder were ANOTHER style even when
# it was the one being tuned; the removal fired whenever the destination was not
# the opened style, style or not. So a Save As under the style's own name warned
# "Its background image goes with it" and kept it, and a folder holding a
# background.* but no scheme.json lost it with no question -- through Save As,
# and through [1] Overwrite on a split-root install.
#
# Each case asserts the exact question AND what the save then did, and the
# agreement between the two: every name the plan removes is gone, every other
# file that was there and is neither removed nor written is byte-identical, and
# the question is $null exactly when no file that was there is touched.
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

Describe 'Get-TuneSavePlan: the question names what the save then does' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:enc = [System.Text.UTF8Encoding]::new($false)

            function script:New-Folder {
                param([string]$Path, [hashtable]$Files)
                [void][System.IO.Directory]::CreateDirectory($Path)
                foreach ($k in $Files.Keys) {
                    [System.IO.File]::WriteAllText((Join-Path $Path $k), $Files[$k], $script:enc)
                }
                return $Path
            }
            function script:Snapshot {
                param([string]$Path)
                $h = @{}
                if ([System.IO.Directory]::Exists($Path)) {
                    foreach ($f in [System.IO.Directory]::GetFiles($Path)) {
                        $h[[System.IO.Path]::GetFileName($f)] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f))
                    }
                }
                return $h
            }
            function script:Invoke-PlannedSave {
                param($Plan, [string]$SaveName, [string]$BaseDir, [string]$OpenedDir)
                [void](Save-TunedStyle -Plan $Plan -AdjustedScheme ([pscustomobject]@{ name = 'x'; background = '#000000' }) `
                    -SaveName $SaveName -BaseStyleDir $BaseDir -BaseName (Split-Path -Leaf $BaseDir) -OpenedStyleDir $OpenedDir `
                    -Brightness 5 -Saturation 0 -Opacity 100 -FontFace 'Menlo' -FontSize 12)
            }
            # The agreement between the question and the save.
            function script:Assert-PlanKept {
                param($Plan, [hashtable]$Before, [hashtable]$After, $Question)
                $removes = @($Plan.Removes)
                $writes  = @($Plan.Writes)
                foreach ($n in $removes) { $After.ContainsKey($n) | Should -BeFalse -Because "the plan removes $n" }
                $touched = 0
                foreach ($n in $Before.Keys) {
                    if ($removes -contains $n -or $writes -contains $n) { $touched++; continue }
                    $After[$n] | Should -BeExactly $Before[$n] -Because "$n is neither written nor removed"
                }
                ($null -eq $Question) | Should -Be ($touched -eq 0) -Because 'a question exactly when something that was there is touched'
            }
        }
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = Join-Path $sand 'data'
            $script:TStylesModuleRoot = Join-Path $sand 'module'
            $script:dataStyles   = Join-Path $script:TStylesDataRoot 'styles'
            $script:moduleStyles = Join-Path $script:TStylesModuleRoot 'styles'
            $script:forest = New-Folder (Join-Path $script:dataStyles 'forest') @{
                'scheme.json' = '{"name":"forest","background":"#000000"}'; 'theme.json' = '{"opacity":100}' }
            $script:mine = Join-Path $script:dataStyles 'mine'
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'a) Save As over another style names every image, meta.json and README.md, and takes them' {
            [void](New-Folder $script:mine @{ 'scheme.json' = '{"name":"mine"}'; 'background.gif' = 'G'; 'background.png' = 'P'
                                              'meta.json' = '{"description":"d"}'; 'README.md' = '# mine' })
            $before = Snapshot $script:mine
            $plan = Get-TuneSavePlan -SaveName 'mine' -BaseStyleDir $script:forest -OpenedStyleDir $script:forest
            $q = Get-TuneReplaceWarning -Plan $plan -IncludeShadow

            $q | Should -BeExactly "  'mine' already exists and will be REPLACED. Its background images, meta.json and README.md go with it. Continue? [y/N]"
            Invoke-PlannedSave $plan 'mine' $script:forest $script:forest
            Assert-PlanKept $plan $before (Snapshot $script:mine) $q
            @($plan.Removes).Count | Should -Be 4
        }

        It "b) Save As under the opened style's own name keeps its image, and says only what happens" {
            [void](New-Folder $script:mine @{ 'scheme.json' = '{"name":"mine"}'; 'background.png' = 'P'
                                              'tune.json' = '{"schemaVersion":1,"base":"forest"}' })
            $before = Snapshot $script:mine
            $plan = Get-TuneSavePlan -SaveName 'mine' -BaseStyleDir $script:forest -OpenedStyleDir $script:mine
            $q = Get-TuneReplaceWarning -Plan $plan -IncludeShadow

            $q | Should -BeExactly "  'mine' will be replaced and cannot be undone. Continue? [y/N]"
            Invoke-PlannedSave $plan 'mine' $script:forest $script:mine
            $after = Snapshot $script:mine
            Assert-PlanKept $plan $before $after $q
            $after['background.png'] | Should -BeExactly $before['background.png']
        }

        It 'c) a folder holding only an image is not a style: nothing to ask, nothing removed' {
            [void](New-Folder $script:mine @{ 'background.png' = 'USER-PNG' })
            $before = Snapshot $script:mine
            $plan = Get-TuneSavePlan -SaveName 'mine' -BaseStyleDir $script:forest -OpenedStyleDir $script:forest
            $q = Get-TuneReplaceWarning -Plan $plan -IncludeShadow

            $q | Should -BeNullOrEmpty
            Invoke-PlannedSave $plan 'mine' $script:forest $script:forest
            $after = Snapshot $script:mine
            Assert-PlanKept $plan $before $after $q
            $after.ContainsKey('scheme.json') | Should -BeTrue -Because 'the save must have run'
        }

        It 'd) a half-built folder: asks first, and names the files it overwrites' {
            [void](New-Folder $script:forest @{ 'profile.ps1' = '# forest' })
            [void](New-Folder $script:mine @{ 'theme.json' = '{"opacity":50}'; 'profile.ps1' = '# mine'; 'background.png' = 'P' })
            $before = Snapshot $script:mine
            $plan = Get-TuneSavePlan -SaveName 'mine' -BaseStyleDir $script:forest -OpenedStyleDir $script:forest
            $q = Get-TuneReplaceWarning -Plan $plan -IncludeShadow

            $q | Should -BeExactly "  A folder named 'mine' already holds theme.json and profile.ps1, and saving there overwrites them. Continue? [y/N]"
            Invoke-PlannedSave $plan 'mine' $script:forest $script:forest
            Assert-PlanKept $plan $before (Snapshot $script:mine) $q
        }

        It '[1] Overwrite on split roots leaves a lone image in the data root alone, and asks nothing' {
            $moduleEva = New-Folder (Join-Path $script:moduleStyles 'eva') @{
                'scheme.json' = '{"name":"eva","background":"#000000"}'; 'theme.json' = '{"opacity":100}' }
            $dataEva = New-Folder (Join-Path $script:dataStyles 'eva') @{ 'background.png' = 'LEFTOVER' }
            $before = Snapshot $dataEva

            $choice = Get-TuneOverwriteChoice -StyleName 'eva' -StyleDir $moduleEva -BaseStyleDir $moduleEva
            $choice.Question | Should -BeNullOrEmpty
            $choice.Note | Should -BeExactly '(shadows the bundled style)'
            Invoke-PlannedSave $choice.Plan 'eva' $moduleEva $moduleEva
            Assert-PlanKept $choice.Plan $before (Snapshot $dataEva) $choice.Question
        }

        It 'f) a fresh name that shadows a bundled style asks only on Save As' {
            [void](New-Folder (Join-Path $script:moduleStyles 'eva') @{ 'scheme.json' = '{"name":"eva"}' })
            $plan = Get-TuneSavePlan -SaveName 'eva' -BaseStyleDir $script:forest -OpenedStyleDir $script:forest

            Get-TuneReplaceWarning -Plan $plan -IncludeShadow | Should -BeExactly "  That shadows bundled 'eva'. Continue? [y/N]"
            Get-TuneReplaceWarning -Plan $plan | Should -BeNullOrEmpty -Because '[1] says it in its label'
        }

        It 'says "background image goes" for one image and nothing else' {
            [void](New-Folder $script:mine @{ 'scheme.json' = '{"name":"mine"}'; 'background.png' = 'P' })
            $plan = Get-TuneSavePlan -SaveName 'mine' -BaseStyleDir $script:forest -OpenedStyleDir $script:forest
            Get-TuneReplaceWarning -Plan $plan |
                Should -BeExactly "  'mine' already exists and will be REPLACED. Its background image goes with it. Continue? [y/N]"
        }

        It 'asks Test-SameStyleDirectory whether the base is the destination' {
            # The volume-aware helper, not an inline -eq: on Linux `Eva` and
            # `eva` are two directories.
            $eva = New-Folder (Join-Path $script:dataStyles 'eva') @{ 'scheme.json' = '{"name":"eva"}'; 'prompt.sh' = '# p' }
            @((Get-TuneSavePlan -SaveName 'eva' -BaseStyleDir $eva).Writes) | Should -Not -Contain 'prompt.sh' `
                -Because 'a base that is the destination would be copied onto itself'

            Mock Test-SameStyleDirectory { $false }
            @((Get-TuneSavePlan -SaveName 'eva' -BaseStyleDir $eva).Writes) | Should -Contain 'prompt.sh'
            Should -Invoke Test-SameStyleDirectory -ParameterFilter { $B -eq $eva }
        }
    }
}
