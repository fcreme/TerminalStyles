# Pester 5 tests for what "[1] Overwrite" produces and who then owns it.
#
# Saving a tune with Overwrite writes it under a BUNDLED style's name -- that is
# the option's whole purpose. Three things treated the result as install-owned:
# the save prompt called it "(shadows the bundled style)" even when there was no
# bundled original to come back; `tstyles uninstall` removed it, because a
# bundled name is exactly what .installed-files always contains; and
# `tstyles update` copied the shipped files back over it, reverting the tune to
# stock while leaving tune.json behind still claiming the old knob values.
#
# tune.json is what marks such a style as the user's.
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

Describe 'the Overwrite option describes what it is about to do' {
    # These were three source-text assertions, which is why the defect below
    # survived them: the literals and the Test-Path were all present, and both
    # install layouts matched them identically. What differs between the layouts
    # is the ANSWER, so the answer is what is measured now -- Get-TuneOverwriteChoice
    # exists so there is something to measure.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc  = [System.Text.UTF8Encoding]::new($false)
            $script:sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot

            function script:New-Style {
                param([string]$Root, [string]$Name, [switch]$Tuned)
                $d = Join-Path (Join-Path $Root 'styles') $Name
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'),
                    ('{{"name":"{0}","background":"#0a0006"}}' -f $Name), $script:enc)
                if ($Tuned) {
                    [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'),
                        '{"schemaVersion":1,"base":"eva","brightness":-20}', $script:enc)
                }
                return $d
            }
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'does not call an untouched SHIPPED style "yours" on a one-root install' {
            # The bootstrap layout install.sh gives everyone: module root IS data
            # root, so the shipped style already sits where Save-TunedStyle
            # writes. Test-Path alone therefore said "yours" about a style the
            # user had never touched -- and the "(shadows the bundled style)"
            # branch, whose comment promises the original "comes back if the user
            # copy is deleted", is unreachable here: there is no second copy.
            $script:TStylesDataRoot   = $script:sand
            $script:TStylesModuleRoot = $script:sand
            $dir = script:New-Style -Root $script:sand -Name 'eva'
            [System.IO.File]::WriteAllText((Join-Path $script:sand '.installed-files'),
                "tstyles.ps1`nstyles/eva`n", $script:enc)

            $choice = Get-TuneOverwriteChoice -StyleName 'eva' -StyleDir $dir
            $choice.Replaces | Should -BeTrue `
                -Because 'there IS a file where the save is about to write, so the y/N gate must still fire'
            $choice.Note | Should -Not -Match '(?i)your' `
                -Because 'the installer placed this style; the user never saved it'
            $choice.Note | Should -Not -Match '(?i)shadow' `
                -Because 'nothing is shadowed when there is only one styles directory'
            $choice.Note | Should -Match '(?i)bundled'
        }

        It 'says "shadows" only where a bundled original really survives the save' {
            # Split roots (a PSGallery install): the save lands in the data root
            # and the module's copy is untouched, so the original does come back
            # if the user copy is deleted.
            $script:TStylesDataRoot   = Join-Path $script:sand 'data'
            $script:TStylesModuleRoot = Join-Path $script:sand 'module'
            $dir = script:New-Style -Root $script:TStylesModuleRoot -Name 'eva'

            $choice = Get-TuneOverwriteChoice -StyleName 'eva' -StyleDir $dir
            $choice.Replaces | Should -BeFalse `
                -Because 'nothing sits at the destination, so there is nothing to warn about'
            $choice.Note | Should -Match 'shadows the bundled style'
        }

        It 'still calls a style the user saved "yours" -- <case>' -ForEach @(
            @{ case = 'one root, tuned in place'; oneRoot = $true }
            @{ case = 'split roots, a user copy'; oneRoot = $false }
        ) {
            if ($oneRoot) {
                $script:TStylesDataRoot   = $script:sand
                $script:TStylesModuleRoot = $script:sand
                $dir = script:New-Style -Root $script:sand -Name 'eva' -Tuned
                [System.IO.File]::WriteAllText((Join-Path $script:sand '.installed-files'),
                    "tstyles.ps1`nstyles/eva`n", $script:enc)
            } else {
                $script:TStylesDataRoot   = Join-Path $script:sand 'data'
                $script:TStylesModuleRoot = Join-Path $script:sand 'module'
                script:New-Style -Root $script:TStylesModuleRoot -Name 'eva' | Out-Null
                $dir = script:New-Style -Root $script:TStylesDataRoot -Name 'eva'
            }

            $choice = Get-TuneOverwriteChoice -StyleName 'eva' -StyleDir $dir
            $choice.Replaces | Should -BeTrue
            $choice.Note     | Should -Match '(?i)your'
        }

        It 'claims no ownership it cannot prove' {
            # One root and no manifest: Get-StyleOrigin answers 'unknown' on
            # purpose. The gate must still fire -- something is about to be
            # overwritten -- but neither possessive is honest.
            $script:TStylesDataRoot   = $script:sand
            $script:TStylesModuleRoot = $script:sand
            $dir = script:New-Style -Root $script:sand -Name 'eva'

            $choice = Get-TuneOverwriteChoice -StyleName 'eva' -StyleDir $dir
            $choice.Origin   | Should -Be 'unknown'
            $choice.Replaces | Should -BeTrue
            $choice.Note     | Should -Match 'REPLACES'
            $choice.Note     | Should -Not -Match '(?i)(your|bundled)'
        }

        It 'asks before replacing a style that has no bundled original' {
            # The same y/N gate Save-As has applied to the same outcome since
            # 0.8.x. Overwrite had none: it destroyed the style in place, with
            # no backup, one line after claiming the original was safe. Replaces
            # is what the tuner gates that question on, so it is asserted here
            # rather than by matching the Read-Host line.
            $script:TStylesDataRoot   = Join-Path $script:sand 'data'
            $script:TStylesModuleRoot = Join-Path $script:sand 'module'
            $dir = script:New-Style -Root $script:TStylesDataRoot -Name 'mine'

            (Get-TuneOverwriteChoice -StyleName 'mine' -StyleDir $dir).Replaces | Should -BeTrue
            Get-TuneReplaceWarning -Name 'mine' -DestDir $dir -SameStyle |
                Should -Match 'cannot be undone'
        }
    }
}

Describe 'a tuned style survives uninstall even under a bundled name' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # $TestDrive is NOT reset between It blocks -- without this, the
            # tune.json written by the first test below leaks into the second
            # and makes it assert the opposite of what it says.
            $script:dataDir = Join-Path $TestDrive 'data'
            if (Test-Path -LiteralPath $script:dataDir) {
                Remove-Item -LiteralPath $script:dataDir -Recurse -Force
            }
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'styles/eva')  -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'styles/lain') -Force | Out-Null
            # The manifest names both, because the install shipped both.
            [System.IO.File]::WriteAllText((Join-Path $script:dataDir '.installed-files'),
                "tstyles.ps1`nstyles/eva`nstyles/lain`n", $script:enc)
        }

        It 'keeps a style the user has tuned in place' {
            [System.IO.File]::WriteAllText((Join-Path $script:dataDir 'styles/eva/tune.json'),
                '{"schemaVersion":1,"base":"eva","brightness":-35}', $script:enc)

            $plan = Get-UninstallPlan -DataDir $script:dataDir
            $plan.Source | Should -Be 'manifest'
            $plan.Items  | Should -Not -Contain 'styles/eva'  -Because 'tune.json marks it as the user''s'
            $plan.Items  | Should -Contain     'styles/lain' -Because 'an untouched bundled style is still the install''s'
        }

        It 'still removes bundled styles the user never tuned' {
            $plan = Get-UninstallPlan -DataDir $script:dataDir
            $plan.Items | Should -Contain 'styles/eva'
            $plan.Items | Should -Contain 'styles/lain'
        }
    }
}

Describe 'an update leaves a tuned style alone' {
    BeforeAll {
        # Sync-InstallTree lives in install.ps1, which is a script, not the
        # module. $TStylesInstallNoRun is the seam that loads its functions
        # WITHOUT running the download/install flow -- without it, dot-sourcing
        # here runs the real installer. Same shape as Sync-InstallTree.Tests.ps1.
        $TStylesInstallNoRun = $true
        . (Join-Path $script:repoRoot 'install.ps1')
    }

    BeforeEach {
        # Same reason as above: $TestDrive persists across It blocks, and the
        # last test here adds a style to the extracted tree.
        $script:enc = [System.Text.UTF8Encoding]::new($false)
        $script:extracted = Join-Path $TestDrive 'extracted'
        $script:install   = Join-Path $TestDrive 'install'
        foreach ($d in $script:extracted, $script:install) {
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
        }
        New-Item -ItemType Directory -Path (Join-Path $script:extracted 'styles/eva')  -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:extracted 'styles/lain') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:install   'styles/eva')  -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:install   'styles/lain') -Force | Out-Null
        # what ships
        [System.IO.File]::WriteAllText((Join-Path $script:extracted 'tstyles.ps1'), 'NEW', $script:enc)
        [System.IO.File]::WriteAllText((Join-Path $script:extracted 'styles/eva/scheme.json'),  '{"name":"eva","background":"#0a0006"}',  $script:enc)
        [System.IO.File]::WriteAllText((Join-Path $script:extracted 'styles/lain/scheme.json'), '{"name":"lain","background":"#001100"}', $script:enc)
        # what is installed: eva tuned in place, lain untouched
        [System.IO.File]::WriteAllText((Join-Path $script:install 'tstyles.ps1'), 'OLD', $script:enc)
        [System.IO.File]::WriteAllText((Join-Path $script:install 'styles/eva/scheme.json'), '{"name":"eva","background":"#440044"}', $script:enc)
        [System.IO.File]::WriteAllText((Join-Path $script:install 'styles/eva/tune.json'),
            '{"schemaVersion":1,"base":"eva","brightness":-35,"saturation":20}', $script:enc)
        [System.IO.File]::WriteAllText((Join-Path $script:install 'styles/lain/scheme.json'), '{"name":"lain","background":"#000000"}', $script:enc)
    }

    It 'does not revert a tuned style to the shipped one' {
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:install
        $eva = Get-Content (Join-Path $script:install 'styles/eva/scheme.json') -Raw | ConvertFrom-Json
        $eva.background | Should -Be '#440044' -Because 'the tune must survive the update'
        Test-Path -LiteralPath (Join-Path $script:install 'styles/eva/tune.json') | Should -BeTrue
    }

    It 'still updates a bundled style the user never tuned' {
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:install
        $lain = Get-Content (Join-Path $script:install 'styles/lain/scheme.json') -Raw | ConvertFrom-Json
        $lain.background | Should -Be '#001100' -Because 'an untouched style must still receive updates'
    }

    It 'still updates everything outside styles/' {
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:install
        (Get-Content (Join-Path $script:install 'tstyles.ps1') -Raw).Trim() | Should -Be 'NEW'
    }

    It 'installs a style that is not there yet' {
        New-Item -ItemType Directory -Path (Join-Path $script:extracted 'styles/halo') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:extracted 'styles/halo/scheme.json'), '{"name":"halo"}', $script:enc)
        Sync-InstallTree -ExtractedRoot $script:extracted -InstallDir $script:install
        Test-Path -LiteralPath (Join-Path $script:install 'styles/halo/scheme.json') | Should -BeTrue
    }
}
