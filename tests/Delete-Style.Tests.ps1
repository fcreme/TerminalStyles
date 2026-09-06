# Pester 5 tests: `tstyles delete`, and the ownership question underneath it.
#
# THE PREMISE THAT WAS WRONG. The obvious way to tell a user's style from a
# bundled one is its path -- "is FullName under the data root". On a BOOTSTRAP
# install that is false for every style: install.ps1 sets its install dir to
# Get-TStylesDataRoot, so $ModuleRoot IS $DataRoot and styles/ holds the sixteen
# bundled styles beside the user's own. Measured on a real machine: a
# path-prefix predicate reports all seventeen as the user's. A badge built on it
# mislabels the bundled set; a delete guard built on it offers to delete them.
#
# So ownership is answered per layout, and where there is no evidence the answer
# is 'unknown' and the command refuses. Never claim ownership the tool cannot
# prove.
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

Describe 'Get-StyleOrigin' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        function script:New-Style([string]$Root, [string]$Name, [switch]$Tuned) {
            $d = Join-Path (Join-Path $Root 'styles') $Name
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{"name":"' + $Name + '"}')
            if ($Tuned) { [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'), '{"base":"eva"}') }
            $d
        }

        Context 'bootstrap layout -- one root for bundled and user styles' {
            BeforeEach {
                $script:TStylesDataRoot = $script:root
                $script:TStylesModuleRoot = $script:root
                script:New-Style $script:root 'eva'      | Out-Null
                script:New-Style $script:root 'forest' -Tuned | Out-Null
                script:New-Style $script:root 'mine'   -Tuned | Out-Null
                script:New-Style $script:root 'handmade'      | Out-Null
            }

            It 'reads the install manifest, not the path' {
                [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'),
                    "styles/eva`nstyles/forest`ntstyles.ps1`n")
                $claim = Get-InstalledStyleClaim
                $one   = Test-StylesRootsAreOne
                $one | Should -BeTrue -Because 'this layout is what makes the path useless'

                $o = { param($n) Get-StyleOrigin -Name $n -StyleDir (Join-Path (Join-Path $script:root 'styles') $n) -Claim $claim -RootsAreOne $one }
                & $o 'eva'      | Should -Be 'bundled'
                & $o 'mine'     | Should -Be 'yours'
                & $o 'handmade' | Should -Be 'yours' -Because 'the manifest does not claim it'
                & $o 'forest'   | Should -Be 'yours' -Because 'tune.json makes a shipped style the user''s, as uninstall already decides'
            }

            It 'says unknown rather than guessing when there is no manifest' {
                # The dangerous direction: "no manifest => nothing is claimed =>
                # everything is yours" would badge and offer to delete all
                # sixteen bundled styles.
                $claim = Get-InstalledStyleClaim
                $claim | Should -BeNullOrEmpty
                $one = Test-StylesRootsAreOne

                $o = { param($n) Get-StyleOrigin -Name $n -StyleDir (Join-Path (Join-Path $script:root 'styles') $n) -Claim $claim -RootsAreOne $one }
                & $o 'eva'  | Should -Be 'unknown'
                & $o 'mine' | Should -Be 'yours' -Because 'tune.json is proof regardless of the manifest'
            }

            It 'treats a manifest with no style lines as no manifest' {
                [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "tstyles.ps1`nlib`n")
                Get-InstalledStyleClaim | Should -BeNullOrEmpty `
                    -Because 'an EMPTY claim would mean the installer placed no styles, so every one would read as yours'
            }
        }

        Context 'split layout -- separate module and data roots' {
            BeforeEach {
                $script:mod  = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                $script:user = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                $script:TStylesModuleRoot = $script:mod
                $script:TStylesDataRoot   = $script:user
                script:New-Style $script:mod  'eva'    | Out-Null
                script:New-Style $script:mod  'forest' | Out-Null
                script:New-Style $script:user 'eva' -Tuned | Out-Null
                script:New-Style $script:user 'mine' -Tuned | Out-Null
            }

            It 'calls a user style that shadows a bundled one a shadow' {
                Test-StylesRootsAreOne | Should -BeFalse
                Get-StyleOrigin -Name 'eva' -StyleDir (Get-StyleDir -StyleName 'eva') |
                    Should -Be 'shadow' -Because 'deleting it reveals the bundled original rather than removing the name'
                Get-StyleOrigin -Name 'forest' -StyleDir (Get-StyleDir -StyleName 'forest') | Should -Be 'bundled'
                Get-StyleOrigin -Name 'mine' -StyleDir (Get-StyleDir -StyleName 'mine')     | Should -Be 'yours'
            }
        }
    }
}

Describe 'Get-StyleDeletePlan decides before anything is touched' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = $script:root
            $script:TStylesModuleRoot = $script:root
            script:New-Style $script:root 'eva'  | Out-Null
            script:New-Style $script:root 'mine' -Tuned | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'refuses an empty name without throwing a binding error' {
            # Get-StyleDir's parameter is a Mandatory [string]: an empty name
            # throws a raw .NET binding error rather than returning $null, so
            # the emptiness has to be caught before the resolve.
            # Assigned OUTSIDE the Should -Not -Throw scriptblock: a
            # scriptblock runs in a child scope, so assigning there leaves the
            # outer variable $null and the assertions below inspect nothing.
            { Get-StyleDeletePlan -Name '' } | Should -Not -Throw
            $plan = Get-StyleDeletePlan -Name ''
            $plan.Ok     | Should -BeFalse
            $plan.Reason | Should -Be 'noname'
        }

        It 'refuses a bundled style' {
            $plan = Get-StyleDeletePlan -Name 'eva'
            $plan.Ok     | Should -BeFalse
            $plan.Reason | Should -Be 'bundled'
        }

        It 'refuses a name that resolves nowhere' {
            (Get-StyleDeletePlan -Name 'nope').Reason | Should -Be 'notfound'
        }

        It 'refuses a path pretending to be a name' {
            # Get-StyleDir already rejects these -- `tstyles tune ../styles/eva`
            # once deleted a real style -- so this pins that delete routes
            # through it rather than composing its own path.
            foreach ($bad in '../styles/eva', '..', '.', 'a/b') {
                (Get-StyleDeletePlan -Name $bad).Ok | Should -BeFalse -Because "'$bad' is not a style name"
            }
        }

        It 'plans a real deletion without writing anything' {
            $before = @(Get-ChildItem -LiteralPath (Join-Path $script:root 'styles') -Directory).Count
            $plan = Get-StyleDeletePlan -Name 'mine'
            $plan.Ok        | Should -BeTrue
            $plan.Origin    | Should -Be 'yours'
            $plan.TrashPath | Should -Match '\.deleted'
            @(Get-ChildItem -LiteralPath (Join-Path $script:root 'styles') -Directory).Count |
                Should -Be $before -Because 'planning must not mutate anything'
            Test-Path -LiteralPath (Get-StyleTrashRoot) | Should -BeFalse
        }

        It 'names the styles that lose their adjustments' {
            $child = script:New-Style $script:root 'child' -Tuned
            [System.IO.File]::WriteAllText((Join-Path $child 'tune.json'),
                '{"base":"mine","brightness":-20,"saturation":5}')

            $plan = Get-StyleDeletePlan -Name 'mine'
            @($plan.Children).Count | Should -Be 1
            $plan.Children[0].Name       | Should -Be 'child'
            $plan.Children[0].Brightness | Should -Be -20
            $plan.Children[0].Saturation | Should -Be 5
        }
    }
}

Describe 'deleting moves the style aside rather than erasing it' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = $script:root
            $script:TStylesModuleRoot = $script:root
            $script:TStylesCurrent = Join-Path $script:root 'current-style.ps1'
            script:New-Style $script:root 'eva' | Out-Null
            script:New-Style $script:root 'mine' -Tuned | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")
            Mock Write-Host {}
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'keeps every file, so the delete can be undone by hand' {
            # A move, not Remove-Item -Recurse. That is reversible, it cannot
            # leave a half-removed directory (dropping scheme.json first makes a
            # style invisible to BOTH Get-AvailableStyles and Get-StyleDir while
            # its other files remain), and it moves a symlinked style dir as a
            # link instead of descending into the target.
            Invoke-TerminalStyleDelete -Name 'mine' -Yes

            Get-StyleDir -StyleName 'mine' | Should -BeNullOrEmpty
            $kept = @(Get-ChildItem -LiteralPath (Get-StyleTrashRoot) -Directory)
            $kept.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $kept[0].FullName 'scheme.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $kept[0].FullName 'tune.json')   | Should -BeTrue
        }

        It 'refuses without consent when there is no console' {
            # Confirm-Action refuses rather than assuming when nobody can
            # answer, and delete must go through it like every other
            # destructive command.
            Mock Test-InteractiveConsole { $false }
            Invoke-TerminalStyleDelete -Name 'mine'
            Get-StyleDir -StyleName 'mine' | Should -Not -BeNullOrEmpty `
                -Because 'an unanswered prompt is not consent to delete'
        }

        It 'leaves a bundled style alone even with -Yes' {
            Invoke-TerminalStyleDelete -Name 'eva' -Yes
            Get-StyleDir -StyleName 'eva' | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath (Get-StyleTrashRoot) | Should -BeFalse
        }
    }
}

Describe 'delete is wired into the command surface' {
    It 'is a dispatched subcommand, so a style may no longer be called that' {
        InModuleScope TerminalStyles {
            $script:TStylesSubcommands | Should -Contain 'delete'
            # The completer and the name check read one list, so adding a
            # subcommand necessarily removes it as a style name -- the same
            # hazard `reset` introduced, and the reason they share a list.
            Test-StyleNameValid -Name 'delete' | Should -BeFalse
        }
    }

    It 'Invoke-TerminalStyle routes delete before it tries to match a style' {
        $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        $src | Should -Match "\`$Arg -eq 'delete'"
        $src.IndexOf("`$Arg -eq 'delete'") | Should -BeLessThan $src.IndexOf('$styleMatch = Get-AvailableStyles')
    }
}

Describe 'the SPLIT-root layout is not proof of ownership either' {
    # The file header records the premise that was wrong on a bootstrap install:
    # the path cannot tell a user's style from a bundled one, because both roots
    # are the same directory. The split-root branch was written on the mirror
    # image of that premise -- that when the roots DO differ, the path can be
    # trusted absolutely -- and that is wrong in the case README documents at
    # line 81: a bootstrap and a PSGallery install coexisting.
    #
    # There, the loaded module is the versioned PSGallery directory while the
    # bootstrap's whole tree -- styles/ and its .installed-files manifest --
    # still sits in the data root. Every SHIPPED style then resolves out of the
    # data root and looked exactly like a style the user had made: `tstyles
    # list` badged all sixteen 'yours (shadows bundled)', and `tstyles delete
    # eva` offered to move eva to the trash calling it 'your style'. That is the
    # claim-ownership-on-a-guess failure this function's own docstring forbids.
    #
    # `tstyles uninstall` on the PSGallery side leaves exactly this state, so it
    # is reachable without ever deliberately installing twice.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot

            $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:dataRoot = Join-Path $script:caseRoot 'data'
            $script:modRoot  = Join-Path $script:caseRoot 'mod'
            foreach ($d in @((Join-Path $script:dataRoot 'styles/eva'),
                             (Join-Path $script:modRoot  'styles/eva'))) {
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{}')
            }
            $script:TStylesDataRoot   = $script:dataRoot
            $script:TStylesModuleRoot = $script:modRoot
            $script:evaDir = Join-Path $script:dataRoot 'styles/eva'
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'the roots really are separate in this fixture' {
            Test-StylesRootsAreOne | Should -BeFalse -Because 'otherwise the test exercises the other branch'
        }

        It 'a shipped style the installer admits placing is bundled, not the user''s' {
            [System.IO.File]::WriteAllText((Join-Path $script:dataRoot '.installed-files'), "styles/eva`n")
            Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir |
                Should -Be 'bundled' -Because 'the manifest in that same directory says the installer wrote it'
        }

        It 'a TUNED copy stays the user''s even when the manifest claims the name' {
            # An Overwrite save writes tune.json under a bundled name. 'shadow'
            # already means "yours, shadowing bundled", and that must survive.
            [System.IO.File]::WriteAllText((Join-Path $script:dataRoot '.installed-files'), "styles/eva`n")
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'tune.json'), '{"base":"eva"}')
            Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir |
                Should -Be 'shadow' -Because 'the user overwrote it; the manifest does not get to take it back'
        }

        It 'with no manifest the path still decides, so a plain PSGallery install is unchanged' {
            # Get-InstalledStyleClaim returns $null -- not an empty list -- when
            # it cannot say, which is what keeps the ordinary case on the old
            # path. An empty list here would reclassify nothing but would also
            # mean "the installer placed nothing", which is a different claim.
            Get-InstalledStyleClaim | Should -BeNullOrEmpty
            Get-StyleOrigin -Name 'eva' -StyleDir $script:evaDir |
                Should -Be 'shadow' -Because 'without a manifest the data root holds only what the user made'
        }

        It 'a style the manifest does not name is still the user''s' {
            [System.IO.File]::WriteAllText((Join-Path $script:dataRoot '.installed-files'), "styles/eva`n")
            $mine = Join-Path $script:dataRoot 'styles/mine'
            New-Item -ItemType Directory -Path $mine -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $mine 'scheme.json'), '{}')
            Get-StyleOrigin -Name 'mine' -StyleDir $mine | Should -Be 'yours'
        }
    }
}

# The trash sweep's clock. `tstyles delete` prints "Kept for 7 days at ..." and
# `tstyles delete` with no name repeats it, but the sweep asked
# $old.LastWriteTime how old a trashed style was. Move-Item renames within the
# data root and a rename does not touch a directory's LastWriteTime, so that
# value is when the style was last EDITED. A style tuned once and left alone for
# a month landed in the trash already a month past the cutoff and the next
# delete swept it -- the promised week spent before the user could act on it,
# and shortest for exactly the styles they were least likely to have a copy of.
Describe 'the trash sweep measures time since deletion, not since the style was edited' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            script:New-Style $script:root 'eva'  | Out-Null
            script:New-Style $script:root 'mine' -Tuned | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        Context 'Get-StyleTrashTimestamp' {
            It 'reads the deletion time out of the trash folder name' {
                Get-StyleTrashTimestamp -Name 'mine-20260401-131415' -Fallback (Get-Date).AddDays(-30) |
                    Should -Be ([datetime]::new(2026, 4, 1, 13, 14, 15))
            }

            It 'reads the stamp this tool appended, not digits inside the style name' {
                # A user may name a style 'solarized-2024'. The pattern is
                # anchored at the end, so the trailing stamp is the one read.
                Get-StyleTrashTimestamp -Name 'solarized-2024-20260401-131415' -Fallback (Get-Date) |
                    Should -Be ([datetime]::new(2026, 4, 1, 13, 14, 15))
            }

            It 'falls back for a name carrying no stamp' {
                # Trash written before this existed, or a folder some other hand
                # put there. Falling back is the previous behaviour; returning
                # something far-future would make it unsweepable forever.
                $fb = [datetime]::new(2020, 1, 2, 3, 4, 5)
                Get-StyleTrashTimestamp -Name 'no-stamp-here' -Fallback $fb | Should -Be $fb
            }

            It 'falls back when the stamp is the right shape but not a real date' {
                $fb = [datetime]::new(2020, 1, 2, 3, 4, 5)
                Get-StyleTrashTimestamp -Name 'x-20261345-996655' -Fallback $fb | Should -Be $fb
            }
        }

        Context 'the sweep itself' {
            It 'keeps a style deleted seconds ago that had not been edited in a month' {
                # The regression. Ages the style the way an untouched tuned
                # style really is, then deletes it and runs the sweep by
                # deleting a second one.
                $aged = Get-StyleDir -StyleName 'mine'
                (Get-Item -LiteralPath $aged).LastWriteTime = (Get-Date).AddDays(-30)

                $plan = Get-StyleDeletePlan -Name 'mine'
                $plan.Ok | Should -BeTrue
                Move-StyleDirectoryToTrash -Plan $plan
                Test-Path -LiteralPath $plan.TrashPath | Should -BeTrue

                script:New-Style $script:root 'second' -Tuned | Out-Null
                Move-StyleDirectoryToTrash -Plan (Get-StyleDeletePlan -Name 'second')

                Test-Path -LiteralPath $plan.TrashPath |
                    Should -BeTrue -Because 'it was deleted seconds ago, whatever its LastWriteTime says'
            }

            It 'sweeps trash whose stamp really is past the window' {
                # The other direction: this folder was created just now, so its
                # LastWriteTime is fresh and the old clock would have kept it.
                # The stamp is what makes it old.
                $trashRoot = Get-StyleTrashRoot
                $ancient = Join-Path $trashRoot 'ancient-20200101-000000'
                New-Item -ItemType Directory -Path $ancient -Force | Out-Null

                Move-StyleDirectoryToTrash -Plan (Get-StyleDeletePlan -Name 'mine')

                Test-Path -LiteralPath $ancient |
                    Should -BeFalse -Because 'its name says it was deleted in 2020'
            }

            It 'keeps trash inside the window' {
                $trashRoot = Get-StyleTrashRoot
                $stamp  = (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss')
                $recent = Join-Path $trashRoot "recent-$stamp"
                New-Item -ItemType Directory -Path $recent -Force | Out-Null

                Move-StyleDirectoryToTrash -Plan (Get-StyleDeletePlan -Name 'mine')

                Test-Path -LiteralPath $recent | Should -BeTrue -Because '2 days is inside the 7-day window'
            }
        }
    }
}

# What the delete prompt discloses about the sweep.
#
# Show-StyleDeletePlan itemises everything that is about to happen and ended on
# "Nothing is erased: move the folder back to undo." Confirming it runs the
# sweep, which is a recursive Remove-Item over every trashed style past the
# window -- so pressing y on that promise permanently destroyed a style the user
# had deleted earlier and could still have recovered. Measured before the fix:
# 'precious-20200101-000000' present before, gone after, with the prompt saying
# nothing would be erased.
#
# Bounded trash is the point of the feature. Not saying so, on the one screen
# that exists to say so, was the defect.
Describe 'the delete prompt discloses what confirming it will erase' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            script:New-Style $script:root 'eva'  | Out-Null
            script:New-Style $script:root 'mine' -Tuned | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        function script:New-Trash([string]$Name) {
            $d = Join-Path (Get-StyleTrashRoot) $Name
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{}')
            $d
        }

        Context 'Get-StyleTrashSweepTarget' {
            It 'names a trashed style past the window' {
                script:New-Trash 'precious-20200101-000000' | Out-Null
                @(Get-StyleTrashSweepTarget).Name | Should -Be @('precious-20200101-000000')
            }

            It 'does not name one inside the window' {
                script:New-Trash ("recent-" + (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss')) | Out-Null
                @(Get-StyleTrashSweepTarget).Count | Should -Be 0
            }

            It 'returns empty when nothing has ever been deleted' {
                Test-Path -LiteralPath (Get-StyleTrashRoot) | Should -BeFalse
                @(Get-StyleTrashSweepTarget).Count | Should -Be 0
            }

            It 'reads without erasing -- it runs before consent' {
                $d = script:New-Trash 'precious-20200101-000000'
                Get-StyleTrashSweepTarget | Out-Null
                [System.IO.Directory]::Exists($d) | Should -BeTrue
            }
        }

        Context 'the listing' {
            It 'names the trashed style that confirming will erase' {
                script:New-Trash 'precious-20200101-000000' | Out-Null
                $out = Show-StyleDeletePlan -Plan (Get-StyleDeletePlan -Name 'mine') 6>&1 | Out-String

                $out | Should -Match 'ERASE precious-20200101-000000' `
                    -Because 'it does not come back, so it belongs on the list'
            }

            It 'scopes the undo promise to the style being deleted' {
                script:New-Trash 'precious-20200101-000000' | Out-Null
                $out = Show-StyleDeletePlan -Plan (Get-StyleDeletePlan -Name 'mine') 6>&1 | Out-String

                $out | Should -Match "Nothing of 'mine' is erased"
                $out | Should -Not -Match '  - Nothing is erased' `
                    -Because 'unqualified, it contradicts the ERASE line directly above it'
            }

            It 'says nothing about erasing when the trash holds nothing expired' {
                script:New-Trash ("recent-" + (Get-Date).AddDays(-1).ToString('yyyyMMdd-HHmmss')) | Out-Null
                $out = Show-StyleDeletePlan -Plan (Get-StyleDeletePlan -Name 'mine') 6>&1 | Out-String
                # '- ERASE ', not 'ERASE': -Match is case-INSENSITIVE, so the
                # bare word also matched "is erased" in the undo line below and
                # failed on output that was correct.
                $out | Should -Not -Match '- ERASE '
            }

            It 'planning still writes nothing, including the trash' {
                $d = script:New-Trash 'precious-20200101-000000'
                Get-StyleDeletePlan -Name 'mine' | Out-Null
                [System.IO.Directory]::Exists($d) | Should -BeTrue
            }
        }

        Context 'the listing and the sweep cannot drift apart' {
            It 'erases exactly what the prompt named, and nothing else' {
                $doomed  = script:New-Trash 'precious-20200101-000000'
                $spared  = script:New-Trash ("recent-" + (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss'))

                $plan  = Get-StyleDeletePlan -Name 'mine'
                $named = @($plan.SweepTargets.Name)
                $named | Should -Be @('precious-20200101-000000')

                Move-StyleDirectoryToTrash -Plan $plan

                [System.IO.Directory]::Exists($doomed) | Should -BeFalse -Because 'the prompt named it'
                [System.IO.Directory]::Exists($spared) | Should -BeTrue  -Because 'the prompt did not'
            }
        }
    }
}
