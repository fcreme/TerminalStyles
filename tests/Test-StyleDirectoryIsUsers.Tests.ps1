# Pester 5 tests: "whose style is this?" is ONE rule, and all three commands
# that ask it have to get the same answer.
#
# It used to be three tune.json tests -- install.ps1's styles merge (`tstyles
# update`), Get-UninstallPlan (`tstyles uninstall`) and Get-StyleOrigin
# (`tstyles list` / `tstyles delete`). All three agreed about the tuner's
# "[1] Overwrite" save, which writes tune.json under a bundled name, and all
# three were silent about the other half README.md documents:
#
#   "If you drop in a folder with the same name as a bundled theme (e.g.
#    eva/), your version wins -- useful for tweaking a bundled theme's prompt
#    or palette without forking the repo."
#
# A hand-drop has no tune.json -- nothing but Save-TunedStyle writes one -- and
# on the bootstrap layout the install directory IS the data root, so the shipped
# folder and the user's override are the same path. Measured on the shipped code
# before the fix: `tstyles update` put SHIPPED-SCHEME back over MY-OVERRIDE-
# SCHEME with 0 backups anywhere, and Get-UninstallPlan listed styles/eva for
# deletion one line under "PRESERVE user state ($dataDir contents -- pass
# -DeleteData to wipe)".
#
# The missing evidence is what the install PLACED. Write-InstallManifest now
# records a content fingerprint per style in .installed-styles, and
# Test-StyleDirectoryIsUsers is the one function that reads it.
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

Describe 'Test-StyleDirectoryIsUsers' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # $TestDrive is NOT reset between It blocks.
            $script:root = Join-Path $TestDrive ('own-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:enc  = [System.Text.UTF8Encoding]::new($false)
            $script:eva  = Join-Path $script:root 'styles/eva'
            New-Item -ItemType Directory -Path $script:eva -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:eva 'scheme.json'), '{"name":"eva"}', $script:enc)
            # What the install placed, as the installer would have recorded it.
            $script:shipped = @{ eva = (Get-StyleContentHash -StyleDir $script:eva) }
            $script:shipped.eva | Should -Not -BeNullOrEmpty -Because 'a $null fingerprint would make every case below vacuous'
        }

        It 'says no while the style is still byte-for-byte what the install placed' {
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $script:shipped | Should -BeFalse
        }

        It 'says yes once a shipped file has been edited' {
            [System.IO.File]::WriteAllText((Join-Path $script:eva 'scheme.json'), '{"name":"mine"}', $script:enc)
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $script:shipped | Should -BeTrue
        }

        It 'says yes once a file has been ADDED' {
            # The commonest hand-drop: a bundled style given a prompt.sh or a
            # background.gif it does not ship.
            [System.IO.File]::WriteAllText((Join-Path $script:eva 'prompt.sh'), '# mine', $script:enc)
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $script:shipped | Should -BeTrue
        }

        It 'says yes for a tuner Overwrite save, with or without a record' {
            [System.IO.File]::WriteAllText((Join-Path $script:eva 'tune.json'),
                '{"schemaVersion":1,"base":"eva","brightness":-35}', $script:enc)
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $script:shipped | Should -BeTrue
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $null           | Should -BeTrue
        }

        It 'says no when there is no record at all' {
            # "Cannot say" is not "the user's". Refusing to update a style on no
            # evidence would freeze it at whatever version the user happens to
            # have, silently and permanently -- the worse failure, and the
            # reason install.ps1 copies on this branch.
            [System.IO.File]::WriteAllText((Join-Path $script:eva 'scheme.json'), '{"name":"mine"}', $script:enc)
            Test-StyleDirectoryIsUsers -StyleDir $script:eva -Recorded $null | Should -BeFalse
        }

        It 'says no for a style the record does not claim' {
            # A style under a name of the user's own: not the install's, but not
            # this rule's business either -- the manifest and the roots decide.
            $mine = Join-Path $script:root 'styles/mine'
            New-Item -ItemType Directory -Path $mine -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $mine 'scheme.json'), '{"name":"mine"}', $script:enc)
            Test-StyleDirectoryIsUsers -StyleDir $mine -Recorded $script:shipped | Should -BeFalse
        }
    }
}

Describe 'Get-StyleContentHash' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:h = Join-Path $TestDrive ('hash-' + [guid]::NewGuid().Guid.Substring(0, 8))
            $script:enc = [System.Text.UTF8Encoding]::new($false)
        }

        It 'answers $null for a directory that is not there' {
            # Never a hash: "cannot say" must not be able to look like "unchanged".
            Get-StyleContentHash -StyleDir (Join-Path $script:h 'nope') | Should -BeNullOrEmpty
        }

        It 'is the same for two directories with the same contents' {
            foreach ($n in 'a', 'b') {
                New-Item -ItemType Directory -Path (Join-Path $script:h $n) -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $script:h "$n/scheme.json"), '{"x":1}', $script:enc)
                [System.IO.File]::WriteAllText((Join-Path $script:h "$n/prompt.sh"), 'PS1=x', $script:enc)
            }
            (Get-StyleContentHash -StyleDir (Join-Path $script:h 'a')) |
                Should -Be (Get-StyleContentHash -StyleDir (Join-Path $script:h 'b'))
        }

        It 'changes when a file is renamed, not just when bytes change' {
            New-Item -ItemType Directory -Path (Join-Path $script:h 'c') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:h 'c/one.txt'), 'same', $script:enc)
            $before = Get-StyleContentHash -StyleDir (Join-Path $script:h 'c')
            Move-Item -LiteralPath (Join-Path $script:h 'c/one.txt') -Destination (Join-Path $script:h 'c/two.txt')
            (Get-StyleContentHash -StyleDir (Join-Path $script:h 'c')) | Should -Not -Be $before
        }
    }
}

Describe 'the other two doors ask the same question' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    Context 'tstyles uninstall' {
        InModuleScope TerminalStyles {
            BeforeEach {
                $script:dataDir = Join-Path $TestDrive ('un-' + [guid]::NewGuid().Guid.Substring(0, 8))
                $script:enc = [System.Text.UTF8Encoding]::new($false)
                foreach ($n in 'eva', 'lain') {
                    New-Item -ItemType Directory -Path (Join-Path $script:dataDir "styles/$n") -Force | Out-Null
                    [System.IO.File]::WriteAllText((Join-Path $script:dataDir "styles/$n/scheme.json"),
                        "{`"name`":`"$n`"}", $script:enc)
                }
                # The install shipped both, and recorded what it placed.
                [System.IO.File]::WriteAllText((Join-Path $script:dataDir '.installed-files'),
                    "tstyles.ps1`nstyles/eva`nstyles/lain`n", $script:enc)
                $lines = foreach ($n in 'eva', 'lain') {
                    '{0}  {1}' -f (Get-StyleContentHash -StyleDir (Join-Path $script:dataDir "styles/$n")), $n
                }
                [System.IO.File]::WriteAllText((Join-Path $script:dataDir '.installed-styles'),
                    (($lines -join "`n") + "`n"), $script:enc)
            }

            It 'keeps a style the user hand-dropped under a bundled name' {
                # No tune.json anywhere: this is the README override, and it is
                # what the tune.json-only rule could not see.
                [System.IO.File]::WriteAllText((Join-Path $script:dataDir 'styles/eva/scheme.json'),
                    '{"name":"my own eva"}', $script:enc)

                $plan = Get-UninstallPlan -DataDir $script:dataDir
                $plan.Source | Should -Be 'manifest'
                $plan.Items  | Should -Not -Contain 'styles/eva' `
                    -Because 'the consent screen promises to PRESERVE user state'
                $plan.Items  | Should -Contain 'styles/lain' `
                    -Because 'an untouched bundled style is still the install''s to remove'
            }

            It 'still removes a bundled style the user never touched' {
                $plan = Get-UninstallPlan -DataDir $script:dataDir
                $plan.Items | Should -Contain 'styles/eva'
                $plan.Items | Should -Contain 'styles/lain'
            }

            It 'removes its own style record' {
                # .installed-styles is the install's file, so an uninstall that
                # left it behind would leave a "removed" install still asserting
                # what it placed.
                $plan = Get-UninstallPlan -DataDir $script:dataDir
                $plan.Items | Should -Contain '.installed-styles'
                $plan.Items | Should -Contain '.installed-files'
            }
        }
    }

    Context 'tstyles list and tstyles delete' {
        InModuleScope TerminalStyles {
            BeforeEach {
                $script:dataDir = Join-Path $TestDrive ('or-' + [guid]::NewGuid().Guid.Substring(0, 8))
                $script:enc = [System.Text.UTF8Encoding]::new($false)
                $script:evaDir = Join-Path $script:dataDir 'styles/eva'
                New-Item -ItemType Directory -Path $script:evaDir -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'), '{"name":"eva"}', $script:enc)
                $script:shipped = @{ eva = (Get-StyleContentHash -StyleDir $script:evaDir) }
            }

            It 'calls a hand-dropped override yours, not bundled' {
                # Bootstrap layout: one root, so the path proves nothing and the
                # manifest claims eva. `tstyles list` badged it 'bundled' and
                # `tstyles delete eva` refused it, while `tstyles update` was
                # quietly reverting it -- three readers, two different answers.
                [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                    '{"name":"my own eva"}', $script:enc)
                Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir -Claim @('eva') `
                    -RootsAreOne $true -StyleHash $script:shipped | Should -Be 'yours'
            }

            It 'still calls the shipped copy bundled' {
                Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir -Claim @('eva') `
                    -RootsAreOne $true -StyleHash $script:shipped | Should -Be 'bundled'
            }

            It 'still refuses to guess with no manifest' {
                Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir -Claim $null `
                    -RootsAreOne $true -StyleHash $script:shipped | Should -Be 'unknown'
            }
        }
    }
}
