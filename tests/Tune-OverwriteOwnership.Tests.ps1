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
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
        }

        It 'decides the label from where the style actually lives' {
            # It was the literal "(shadows the bundled style)", unconditionally.
            $script:src | Should -Match 'REPLACES your saved style'
            $script:src | Should -Match 'shadows the bundled style'
            $script:src | Should -Match '\$overwriteReplaces\s*=\s*Test-Path'
        }

        It 'asks before replacing a style that has no bundled original' {
            # The same y/N gate Save-As has applied to the same outcome since
            # 0.8.x. Overwrite had none: it destroyed the style in place, with
            # no backup, one line after claiming the original was safe.
            $script:src | Should -Match 'cannot be undone'
            $block = [regex]::Match($script:src, '(?s)if \(\$choice -eq .1.\) \{.*?\n        \} else \{').Value
            $block | Should -Match "warn -notmatch '\^\(\?i\)y'"
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
