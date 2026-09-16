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

        It 'names a dot-prefixed child too -- the tuner will create one' {
            # The children come off Get-AvailableStyles, which hid a
            # dot-prefixed directory on Unix (Get-ChildItem without -Force).
            # Test-StyleNameValid accepts a leading dot, so `tstyles tune mine`
            # -> "save as" -> `.wip` makes exactly this style -- and the RED
            # disclosure line, "'<name>' loses the brightness X and saturation Y
            # it was tuned by / nothing else records those values", then left it
            # out of a list the user is entitled to read as complete.
            foreach ($n in 'keeper', '.wip') {
                $c = script:New-Style $script:root $n -Tuned
                [System.IO.File]::WriteAllText((Join-Path $c 'tune.json'),
                    '{"base":"mine","brightness":30,"saturation":25}')
            }

            $plan = Get-StyleDeletePlan -Name 'mine'
            $names = @($plan.Children | ForEach-Object { $_.Name })
            $names | Should -Contain 'keeper'
            $names | Should -Contain '.wip' `
                -Because 'confirming the delete destroys the only record of its deltas'
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

    It 'so are trash and restore, the two halves that read it back' {
        # The trash was write-only: `tstyles delete` printed the folder it had
        # just written and no command in the tool could name it afterwards.
        # Measured on 0.8.27: the dispatcher's own table held neither word, and
        # both `tstyles trash` and `tstyles restore` answered "Unknown command
        # or style" followed by the whole help screen.
        InModuleScope TerminalStyles {
            $script:TStylesSubcommands | Should -Contain 'trash'
            $script:TStylesSubcommands | Should -Contain 'restore'
            # The consequence of being on that list, stated rather than
            # discovered: a style can no longer be called either, because the
            # dispatch arm would win over it.
            Test-StyleNameValid -Name 'trash'   | Should -BeFalse
            Test-StyleNameValid -Name 'restore' | Should -BeFalse
        }
    }

    It 'routes trash and restore before it tries to match a style' {
        $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        foreach ($sub in 'trash', 'restore') {
            $src | Should -Match "\`$Arg -eq '$sub'"
            $src.IndexOf("`$Arg -eq '$sub'") | Should -BeLessThan $src.IndexOf('$styleMatch = Get-AvailableStyles')
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
                $stamp  = (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)
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
                script:New-Trash ("recent-" + (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)) | Out-Null
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
                script:New-Trash ("recent-" + (Get-Date).AddDays(-1).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)) | Out-Null
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

        Context 'a delete that did not happen erases nothing' {
            # The sweep is the one irreversible thing `tstyles delete` does, and
            # it ran FIRST -- before the containment re-proof and before the
            # move. So every ordinary way the move can fail (the folder open in
            # an editor on Windows, a permissions failure, the style removed by
            # hand or by a second terminal between the plan and the keystroke)
            # destroyed the expired trash anyway, printed one red line about the
            # style that was NOT deleted, and said nothing about what it had
            # erased. A failed command reads as a command that did nothing.
            It 'keeps the trash the prompt named when the move fails' {
                $doomed = script:New-Trash 'precious-20200101-000000'
                $plan   = Get-StyleDeletePlan -Name 'mine'
                @($plan.SweepTargets.Name) | Should -Be @('precious-20200101-000000') `
                    -Because 'otherwise the sweep has nothing to erase and this measures nothing'

                # The style removed between the plan and the 'y' -- a second
                # terminal, or a hand `rm`. Move-Item -ErrorAction Stop throws.
                Remove-Item -LiteralPath $plan.Dir -Recurse -Force

                { Move-StyleDirectoryToTrash -Plan $plan } | Should -Throw

                [System.IO.Directory]::Exists($doomed) | Should -BeTrue `
                    -Because 'the delete did not happen, so nothing it was bundled with may happen either'
            }

            It 'tells the user the trash is intact when the delete fails' {
                # The other half: the ERASE lines were on the consent screen, so
                # after a failure the user is entitled to know they did not run.
                $doomed = script:New-Trash 'precious-20200101-000000'
                Mock Move-Item { throw 'Access to the path is denied.' }

                $out = Invoke-TerminalStyleDelete -Name 'mine' -Yes 6>&1 | Out-String

                $out | Should -Match "Could not delete 'mine'"
                $out | Should -Match 'Nothing was erased'
                [System.IO.Directory]::Exists($doomed) | Should -BeTrue
                Get-StyleDir -StyleName 'mine' | Should -Not -BeNullOrEmpty
            }
        }

        Context 'the listing and the sweep cannot drift apart' {
            It 'erases exactly what the prompt named, and nothing else' {
                $doomed  = script:New-Trash 'precious-20200101-000000'
                $spared  = script:New-Trash ("recent-" + (Get-Date).AddDays(-2).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture))

                $plan  = Get-StyleDeletePlan -Name 'mine'
                $named = @($plan.SweepTargets.Name)
                $named | Should -Be @('precious-20200101-000000')

                Move-StyleDirectoryToTrash -Plan $plan

                [System.IO.Directory]::Exists($doomed) | Should -BeFalse -Because 'the prompt named it'
                [System.IO.Directory]::Exists($spared) | Should -BeTrue  -Because 'the prompt did not'
            }
            It 'erases nothing that appeared after the prompt was drawn' {
                # Confirm-Action blocks for as long as the user takes to read
                # the listing. Recomputing the sweep after it re-reads the
                # clock, so a folder at six days and twenty-three hours when
                # the prompt was drawn crosses the window while they decide and
                # is erased having never been named -- this defect one step
                # later. Measured against the first fix: prompt named [], and
                # 'precious' was present before the move and gone after it.
                #
                # A folder that simply was not in the plan is the same thing and
                # needs no clock to construct.
                $plan = Get-StyleDeletePlan -Name 'mine'
                @($plan.SweepTargets).Count | Should -Be 0 -Because 'the trash was empty when the prompt was drawn'

                $late = script:New-Trash 'precious-20200101-000000'

                Move-StyleDirectoryToTrash -Plan $plan

                [System.IO.Directory]::Exists($late) | Should -BeTrue `
                    -Because 'the consent the user gave named it nowhere'
            }
        }
    }
}

# The stamp the delete writes and the stamp the sweep reads must be the same
# calendar.
#
# Get-StyleDeletePlan wrote the trash folder name with `Get-Date -Format`, which
# formats through CurrentCulture and therefore through that culture's DEFAULT
# CALENDAR, while Get-StyleTrashTimestamp reads it back pinned to
# InvariantCulture -- proleptic Gregorian. Only the reader had been pinned.
#
# Under ar-SA (UmAlQura) today stamps as 14480326 and under fa-IR (Persian) as
# 14050617; both parse cleanly as Gregorian years around 580 in the past, so the
# folder was expired the instant it was created. Measured end to end: `tstyles
# delete mine` printed "Kept for 7 days at .../.deleted/mine-14480326-033215",
# and the very next `tstyles delete other` listed it in RED as "deleted over 7
# days ago" and destroyed it. th-TH (ThaiBuddhist) fails the other way, stamping
# 2569 and making the trash unsweepable until 2576.
#
# The name still matched the reader's `-(\d{8})-(\d{6})$` pattern, so the
# "no stamp -- fall back to LastWriteTime" escape hatch never engaged.
#
# The calendar is FORCED rather than taken from the culture's platform default:
# whether ar-SA resolves to UmAlQura depends on ICU vs NLS, and a test that is
# only decisive on some hosts is the kind this suite has been bitten by. This
# way the assertion means the same thing on all four CI legs.
Describe 'the trash stamp is written in the calendar the sweep reads' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            script:New-Style $script:root 'mine' -Tuned | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")

            $script:savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $ci = [cultureinfo]([cultureinfo]::GetCultureInfo('ar-SA').Clone())
            $ci.DateTimeFormat.Calendar = [System.Globalization.UmAlQuraCalendar]::new()
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
        }
        AfterEach {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:savedCulture
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'the forced calendar really is non-Gregorian' {
            # Guards the guard: if this ever stops being true the two assertions
            # below would pass while measuring nothing.
            (Get-Date -Format 'yyyy') | Should -Not -Be (Get-Date).Year.ToString() `
                -Because 'the whole point is a culture whose year differs from the Gregorian one'
        }

        It 'reads a stamp it just wrote back as roughly now' {
            $plan = Get-StyleDeletePlan -Name 'mine'
            $name = Split-Path $plan.TrashPath -Leaf

            $read = Get-StyleTrashTimestamp -Name $name -Fallback ([datetime]'1900-01-01')
            [math]::Abs(((Get-Date) - $read).TotalMinutes) | Should -BeLessThan 5 `
                -Because 'the folder was named seconds ago, in whatever calendar'
        }

        It 'does not list a style deleted seconds ago as past the seven-day window' {
            $plan = Get-StyleDeletePlan -Name 'mine'
            Move-StyleDirectoryToTrash -Plan $plan

            @(Get-StyleTrashSweepTarget).Name | Should -Not -Contain (Split-Path $plan.TrashPath -Leaf) `
                -Because '"Kept for 7 days" was printed about it one statement ago'
        }
    }
}

# The consent screen itemises "RESET the terminal to its unstyled default,
# because '<name>' is active", and then did not reset.
#
# Invoke-TerminalStyleDelete moves the style into .deleted/ and only afterwards
# calls Reset-StyleDirect, whose ownership marker is "does Get-AvailableStyles
# know the profile's colorScheme". .deleted is a SIBLING of styles/, so the one
# style that marker is guaranteed to be true of is the one the move just hid:
# the reset refused, the profile kept colorScheme, opacity, useAcrylic, font and
# any background, and the output contradicted itself four lines apart --
# "Deleted mine." in green, then "Its colorScheme is 'mine', which is not a
# style this tool wrote."
#
# Windows Terminal only: every other terminal returns into Reset-StyleNonWT
# before the marker is consulted, so the OSC reset always fired there.
Describe 'deleting the active style performs the reset the prompt itemised' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedModule  = $script:TStylesModuleRoot
            $script:savedCurrent = $script:TStylesCurrent

            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root
            $script:TStylesCurrent    = Join-Path $script:root 'current-style.ps1'

            script:New-Style $script:root 'eva' | Out-Null
            $script:mineDir = script:New-Style $script:root 'mine' -Tuned
            # WasActive is a byte-compare of current-style.ps1 against each
            # style's profile.ps1, so the style needs one and it has to match.
            [System.IO.File]::WriteAllText((Join-Path $script:mineDir 'profile.ps1'), '# mine prompt')
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# mine prompt')
            [System.IO.File]::WriteAllText((Join-Path $script:root '.installed-files'), "styles/eva`n")

            $script:fakeSettings = Join-Path $script:root 'settings.json'
            $obj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'mine' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PS'; guid = '{x}'; colorScheme = 'mine'; opacity = 80; useAcrylic = $true
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Mock Get-TerminalKind             { 'WindowsTerminal' }
            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-CurrentWTProfileName     { 'PS' }
            Mock Show-UpdateNoticeIfAvailable {}
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesCurrent    = $script:savedCurrent
        }

        It 'strips the profile the style it just deleted was applied to' {
            $plan = Get-StyleDeletePlan -Name 'mine'
            $plan.WasActive | Should -BeTrue -Because 'otherwise the RESET bullet is never printed and this measures nothing'
            $plan.RevealDir | Should -BeNullOrEmpty -Because 'the name GOES; the shadow branch re-applies instead'

            Invoke-TerminalStyleDelete -Name 'mine' -Target 'PS' -Yes 6>&1 | Out-Null

            $after = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $p = $after.profiles.list | Where-Object name -eq 'PS'
            $p.PSObject.Properties.Match('colorScheme').Count | Should -Be 0
            $p.PSObject.Properties.Match('opacity').Count     | Should -Be 0
            $p.PSObject.Properties.Match('useAcrylic').Count  | Should -Be 0
            @($after.schemes | Where-Object name -eq 'mine').Count | Should -Be 0 `
                -Because 'the scheme is an orphan once the style is gone'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse `
                -Because 'the deleted style would otherwise keep loading its prompt in every new shell'
        }

        It 'does not call the style it just deleted one this tool never wrote' {
            $out = Invoke-TerminalStyleDelete -Name 'mine' -Target 'PS' -Yes 6>&1 | Out-String

            $out | Should -Match 'Deleted mine\.'
            $out | Should -Not -Match 'not a style this tool wrote'
            $out | Should -Not -Match 'nothing was changed'
        }
    }
}

# What the consent screen promises a TUNED CHILD of the style being deleted.
#
# The shadow branch printed, in Gray -- the colour this file reserves for what
# is KEPT -- "'<child>' was tuned from this style and re-seeds from the bundled
# one: same brightness/saturation, different colours". That is true only for a
# tune.json with no baseFingerprint, which is the legacy shape: Save-TunedStyle
# has written one into every tune.json since 0.8.18. With a fingerprint the
# revealed bundled style hashes differently, Resolve-TuneSeed takes its
# base-moved branch, and the knobs come back 0/0 -- while the DarkGray footnote
# that exists "for the wording" fires only in the case where the sentence above
# it is already true.
Describe 'the prompt describes what will actually happen to a tuned child' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData    = $script:TStylesDataRoot
            $script:savedModule  = $script:TStylesModuleRoot
            $script:savedCurrent = $script:TStylesCurrent

            $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:dataRoot = Join-Path $script:caseRoot 'data'
            $script:modRoot  = Join-Path $script:caseRoot 'mod'
            $script:TStylesDataRoot   = $script:dataRoot
            $script:TStylesModuleRoot = $script:modRoot
            $script:TStylesCurrent    = Join-Path $script:caseRoot 'current-style.ps1'

            # The bundled style and the user's shadow of it must hash
            # differently, or the fingerprint compare has nothing to notice.
            $script:bundledEva = script:New-Style $script:modRoot  'eva'
            $script:shadowEva  = script:New-Style $script:dataRoot 'eva' -Tuned
            [System.IO.File]::WriteAllText((Join-Path $script:bundledEva 'scheme.json'), '{"name":"eva","background":"#111111"}')
            [System.IO.File]::WriteAllText((Join-Path $script:shadowEva  'scheme.json'), '{"name":"eva","background":"#222222"}')
            $script:childDir = script:New-Style $script:dataRoot 'eva-night'
            [System.IO.File]::WriteAllText((Join-Path $script:childDir 'scheme.json'), '{"name":"eva-night","background":"#333333"}')
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesCurrent    = $script:savedCurrent
        }

        function script:New-ChildTune([bool]$Fingerprinted) {
            $fields = @('"base":"eva"', '"brightness":-35', '"saturation":10')
            if ($Fingerprinted) {
                $fp = Get-StyleSchemeFingerprint -StyleDir $script:shadowEva
                $fp | Should -Not -BeNullOrEmpty
                $fields += ('"baseFingerprint":"' + $fp + '"')
            }
            [System.IO.File]::WriteAllText((Join-Path $script:childDir 'tune.json'),
                ('{' + ($fields -join ',') + '}'))
        }

        It 'the promise matches what the next tune really does -- <Shape>' -ForEach @(
            @{ Shape = 'a tune.json carrying a base fingerprint'; Fingerprinted = $true;  Keeps = $false }
            @{ Shape = 'a legacy tune.json with no fingerprint';  Fingerprinted = $false; Keeps = $true  }
        ) {
            script:New-ChildTune $Fingerprinted

            $plan = Get-StyleDeletePlan -Name 'eva'
            $plan.Origin            | Should -Be 'shadow'
            $plan.RevealDir         | Should -Not -BeNullOrEmpty
            @($plan.Children).Count | Should -Be 1
            $plan.Children[0].Name  | Should -Be 'eva-night'

            $out = Show-StyleDeletePlan -Plan $plan 6>&1 | Out-String

            # The delete itself, then the question the prompt was answering.
            Move-StyleDirectoryToTrash -Plan $plan
            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir (Get-StyleDir -StyleName 'eva-night')

            if ($Keeps) {
                $seed.Brightness | Should -Be -35
                $seed.Saturation | Should -Be 10
                $out | Should -Match 'same brightness/saturation'
                $out | Should -Match 'records no base fingerprint'
            } else {
                $seed.Brightness | Should -Be 0 -Because 'the base it was measured against is not the one the name now resolves to'
                $seed.Saturation | Should -Be 0
                $out | Should -Match "'eva-night' loses the brightness -35 and saturation \+10"
                $out | Should -Not -Match 'records no base fingerprint'
            }

            # Stated once, so a rewording cannot quietly break the pairing: the
            # screen may only promise the adjustments survive when they do.
            if ($out -match 'same brightness/saturation') {
                $seed.Brightness | Should -Be -35
                $seed.Saturation | Should -Be 10
            }

            # And the plan, not the printer, is where that was decided.
            $plan.Children[0].KeepsAdjustments | Should -Be $Keeps
        }
    }
}


# The trash, read back.
#
# `tstyles delete` moves a style to .deleted/<name>-<timestamp> and says so, and
# that scrollback line was the last time the tool ever mentioned it. Nothing
# listed what was in there, nothing said how much of the window was left, and
# nothing put one back -- while the next delete of ANY style erased everything
# past seven days. Measured on 0.8.27 in a sandboxed data root: an entry aged to
# thirty days sat on disk through `tstyles list` and `tstyles current` without a
# word, `tstyles trash` and `tstyles restore` both answered "Unknown command or
# style", and the folder went only when an unrelated `tstyles delete` swept it.
#
# Recovery was documented (`tstyles help delete` said to move the folder back)
# and the store was bounded (every delete sweeps), so what was missing is
# narrower than "no undo": the state was invisible, and the one route back was a
# Move-Item the user had to compose from a path in scrollback.
Describe 'the trash can be read back, and a style put back' {
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

        # Ages are written into the folder NAME, which is where the deletion
        # time lives -- a rename does not touch LastWriteTime, which is why
        # Get-StyleTrashTimestamp reads the name.
        function script:New-TrashAged([string]$Name, [int]$DaysAgo, [switch]$NoScheme) {
            $stamp = (Get-Date).AddDays(-$DaysAgo).ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)
            $d = Join-Path (Get-StyleTrashRoot) "$Name-$stamp"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            if (-not $NoScheme) {
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{"name":"' + $Name + '"}')
            }
            return $d
        }

        Context 'Get-StyleTrashEntry' {
            It 'says what is in there, when it went, and how long it has left' {
                script:New-TrashAged -Name 'fresh'  -DaysAgo 2  | Out-Null
                script:New-TrashAged -Name 'stale'  -DaysAgo 30 | Out-Null

                $rows = @(Get-StyleTrashEntry)
                @($rows | ForEach-Object StyleName) | Should -Be @('fresh', 'stale') `
                    -Because 'newest deletion first, which is the order restore resolves in'

                $fresh = $rows | Where-Object StyleName -eq 'fresh'
                $stale = $rows | Where-Object StyleName -eq 'stale'

                $fresh.Expired  | Should -BeFalse
                $fresh.DaysLeft | Should -Be 5 -Because '7 days minus the 2 it has served'
                $stale.Expired  | Should -BeTrue
                $stale.DaysLeft | Should -BeLessThan 0 `
                    -Because 'the sign is what tells an entry with time left from one living on borrowed time'
            }

            It 'strips the stamp, and keeps digits the style name owns' {
                script:New-TrashAged -Name 'solarized-2024' -DaysAgo 1 | Out-Null
                $row = @(Get-StyleTrashEntry)[0]
                $row.StyleName | Should -Be 'solarized-2024'
                $row.Name      | Should -Match '^solarized-2024-\d{8}-\d{6}$'
            }

            It 'says whether the name is free to restore into' {
                # 'mine' is a live style in this fixture; 'gone' is not.
                script:New-TrashAged -Name 'mine' -DaysAgo 1 | Out-Null
                script:New-TrashAged -Name 'gone' -DaysAgo 1 | Out-Null
                $rows = @(Get-StyleTrashEntry)
                ($rows | Where-Object StyleName -eq 'mine').NameFree | Should -BeFalse
                ($rows | Where-Object StyleName -eq 'gone').NameFree | Should -BeTrue
            }

            It 'reads without erasing, and returns empty when nothing was ever deleted' {
                @(Get-StyleTrashEntry).Count | Should -Be 0
                $d = script:New-TrashAged -Name 'precious' -DaysAgo 99
                Get-StyleTrashEntry | Out-Null
                [System.IO.Directory]::Exists($d) | Should -BeTrue
            }

            It 'decides the window in ONE place: the sweep is a filter over it' {
                # Two answers to "is this past the window" is the shape most of
                # this file's defects take. The listing the user reads and the
                # erasure the next delete performs must not each own a copy.
                script:New-TrashAged -Name 'fresh' -DaysAgo 2  | Out-Null
                script:New-TrashAged -Name 'stale' -DaysAgo 30 | Out-Null

                $expired = @(Get-StyleTrashEntry | Where-Object Expired | ForEach-Object Name)
                $swept   = @(Get-StyleTrashSweepTarget | ForEach-Object Name)
                $swept | Should -Be $expired
                $swept.Count | Should -Be 1 -Because 'otherwise this compares two empty lists'
            }
        }

        Context 'tstyles trash' {
            It 'names an expired entry as what the next delete erases' {
                script:New-TrashAged -Name 'precious' -DaysAgo 30 | Out-Null
                $out = Invoke-TerminalStyle -Arg 'trash' 6>&1 | Out-String

                $out | Should -Match 'precious'
                $out | Should -Match 'EXPIRED'
                $out | Should -Match 'tstyles restore <name>' `
                    -Because 'a listing you cannot act on is the state this command exists to end'
            }

            It 'erases nothing itself' {
                $d = script:New-TrashAged -Name 'precious' -DaysAgo 30
                Invoke-TerminalStyle -Arg 'trash' 6>&1 | Out-Null
                [System.IO.Directory]::Exists($d) | Should -BeTrue `
                    -Because 'the erasure keeps the one consent screen it has, which is the delete plan'
            }

            It 'says so when there is nothing in there' {
                $out = Invoke-TerminalStyle -Arg 'trash' 6>&1 | Out-String
                $out | Should -Match 'trash is empty'
            }
        }

        Context 'tstyles restore' {
            It 'puts the folder back under the plain name, stamp and all removed' {
                $trashed = script:New-TrashAged -Name 'gone' -DaysAgo 2
                $status = Invoke-TerminalStyleRestore -Name 'gone' 6>$null
                $status | Should -Be 'restored'

                Get-StyleDir -StyleName 'gone' | Should -Not -BeNullOrEmpty
                (Get-StyleDir -StyleName 'gone') | Should -Be (Join-Path (Join-Path $script:root 'styles') 'gone')
                [System.IO.Directory]::Exists($trashed) | Should -BeFalse

                # The one thing that would silently produce a style nothing can
                # look up: the stamped name landing under styles/.
                @(Get-ChildItem -LiteralPath (Join-Path $script:root 'styles') -Directory |
                    ForEach-Object Name | Where-Object { $_ -match '-\d{8}-\d{6}$' }) |
                    Should -BeNullOrEmpty
            }

            It 'refuses an occupied name, moves nothing, and returns a status rather than a boolean' {
                # 'mine' is live. The folder standing there is a style the user
                # has since made; nothing consented to spending it.
                $marker = Join-Path (Get-StyleDir -StyleName 'mine') 'marker.txt'
                [System.IO.File]::WriteAllText($marker, 'the live one')
                $trashed = script:New-TrashAged -Name 'mine' -DaysAgo 2

                $status = Invoke-TerminalStyleRestore -Name 'mine' 6>$null

                $status | Should -Be 'taken'
                $status | Should -BeOfType [string] `
                    -Because '"it refused" and "it failed" must not become the same answer'
                [System.IO.File]::ReadAllText($marker) | Should -Be 'the live one'
                [System.IO.Directory]::Exists($trashed) | Should -BeTrue `
                    -Because 'a refusal that moved the folder anyway would be the worst of both'
            }

            It 'answers none for a name that is not in the trash' {
                $status = Invoke-TerminalStyleRestore -Name 'nothing-here' 6>$null
                $status | Should -Be 'none'
            }

            It 'lists the trash when given no name' {
                script:New-TrashAged -Name 'gone' -DaysAgo 1 | Out-Null
                $out = Invoke-TerminalStyleRestore -Name '' 6>&1 | Out-String
                $out | Should -Match 'gone'
                $out | Should -Match 'Deleted styles'
            }

            It 'takes the newest copy when a name was deleted twice' {
                $old = script:New-TrashAged -Name 'twice' -DaysAgo 5
                $new = script:New-TrashAged -Name 'twice' -DaysAgo 1
                [System.IO.File]::WriteAllText((Join-Path $new 'which.txt'), 'newest')

                Invoke-TerminalStyleRestore -Name 'twice' 6>&1 | Out-Null

                $dest = Join-Path (Join-Path $script:root 'styles') 'twice'
                [System.IO.File]::ReadAllText((Join-Path $dest 'which.txt')) | Should -Be 'newest'
                [System.IO.Directory]::Exists($old) | Should -BeTrue `
                    -Because 'the older copy is still in the trash, with its own window'
            }

            It 'says out loud when what it restored is not a style the tool can show' {
                # A folder with no scheme.json restores to something Get-StyleDir
                # cannot resolve. "Restored" and nothing else would be a claim
                # `tstyles list` immediately contradicts.
                script:New-TrashAged -Name 'husk' -DaysAgo 1 -NoScheme | Out-Null
                $out = Invoke-TerminalStyleRestore -Name 'husk' 6>&1 | Out-String
                $out | Should -Match 'Restored husk'
                $out | Should -Match 'no scheme\.json'
            }
        }

        Context 'the delete says how to undo itself' {
            It 'names the restore command on the success line and on the plan' {
                # The route back was documented in `tstyles help delete` and
                # printed nowhere the user was actually standing.
                $out = Invoke-TerminalStyleDelete -Name 'mine' -Yes 6>&1 | Out-String
                $out | Should -Match 'tstyles restore mine' `
                    -Because 'the undo belongs on the screen that performs the thing being undone'
            }

            It 'still tells the truth about what the delete erases' {
                # The line that changed here is the one scoped to THIS style;
                # the ERASE lines above it are a different claim and must survive.
                script:New-TrashAged -Name 'precious' -DaysAgo 30 | Out-Null
                $out = Show-StyleDeletePlan -Plan (Get-StyleDeletePlan -Name 'mine') 6>&1 | Out-String
                $out | Should -Match '- ERASE precious-'
                $out | Should -Match "Nothing of 'mine' is erased"
            }
        }
    }
}

Describe 'the containment proof in front of the move and the recursive delete' {
    # THE GAP THIS FILLS. Test-PathIsStyleDirChild is what stands between a
    # composed path and a Move-Item plus a Remove-Item -Recurse -Force, and
    # nothing exercised it: replacing its whole body with `return $true` and
    # running the suite left 1805 of 1805 real tests green. Nothing asserted on
    # Get-StyleDeletePlan's 'outside' Reason either, nor on
    # Move-StyleDirectoryToTrash's 'Refusing to move' throw.
    #
    # It was also the only one of the three guards in this codebase that THREW
    # instead of answering: `-Path ''` and `-Path $null` came back
    # "Cannot bind argument to parameter 'Path' because it is an empty string"
    # from the parameter binder, before a line of the guard ran. Its two
    # siblings, Test-StyleNameIsSingleSegment and Test-StyleNameValid, both
    # carry [AllowEmptyString()][AllowNull()] and both document "never throws".
    #
    # Driven directly rather than through `Get-StyleDeletePlan -Name`: the
    # 'outside' arm is unreachable that way today (Get-StyleOrigin answers
    # 'bundled' first for anything outside the user root, and Get-StyleDir
    # cannot compose a grandchild), so a test aimed at it would be measuring
    # nothing.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedData = $script:TStylesDataRoot
            $script:root      = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = $script:root
            $script:userStyles = Join-Path $script:root 'styles'
            New-Item -ItemType Directory -Path (Join-Path $script:userStyles 'eva') -Force | Out-Null
        }
        AfterEach { $script:TStylesDataRoot = $script:savedData }

        It 'answers an empty or a null path rather than throwing at the binder' {
            # The before-state of both rows is an exception, not $false -- and a
            # guard that throws on the input it exists to reject is not a guard.
            Test-PathIsStyleDirChild -Path ''    | Should -BeFalse
            Test-PathIsStyleDirChild -Path $null | Should -BeFalse
            Test-PathIsStyleDirChild -Path '   ' | Should -BeFalse
        }

        It 'admits a direct child of the styles root and nothing else' {
            $sep   = [System.IO.Path]::DirectorySeparatorChar
            $child = Join-Path $script:userStyles 'eva'

            Test-PathIsStyleDirChild -Path $child          | Should -BeTrue
            Test-PathIsStyleDirChild -Path ($child + $sep) | Should -BeTrue `
                -Because 'a trailing separator does not make it a different directory'

            # The root is not a child of itself: answering $true here would put
            # the whole styles directory in front of the move.
            Test-PathIsStyleDirChild -Path $script:userStyles            | Should -BeFalse
            Test-PathIsStyleDirChild -Path ($script:userStyles + $sep)   | Should -BeFalse

            # Deeper than one segment: the trash sweep and the move both name a
            # style directory, never something inside one.
            Test-PathIsStyleDirChild -Path (Join-Path $child 'nested')   | Should -BeFalse

            # Composed paths that LOOK contained. `tstyles tune ../styles/eva`
            # deleted a real style exactly this way.
            Test-PathIsStyleDirChild -Path (Join-Path $script:userStyles '..' | Join-Path -ChildPath 'eva') |
                Should -BeFalse -Because '<root>/../eva is outside the styles root'
            Test-PathIsStyleDirChild -Path (Join-Path $child '..') |
                Should -BeFalse -Because '<root>/eva/.. is the root itself'
            # ...and one that looks like it escapes and does not: normalised
            # first, then compared, so this really is the direct child.
            Test-PathIsStyleDirChild -Path (Join-Path (Join-Path $script:userStyles '..') 'styles' | Join-Path -ChildPath 'eva') |
                Should -BeTrue

            # A character-prefix SIBLING of the root. StartsWith with no
            # separator boundary admits it -- the same defect the prompt halves
            # had against $HOME, where a sibling rendered as "~Xtra".
            Test-PathIsStyleDirChild -Path (Join-Path ($script:userStyles + 'X') 'eva') |
                Should -BeFalse -Because '<root>X is not <root>'

            # Not a path at all: resolved against the process directory, which
            # is never the sandboxed styles root.
            Test-PathIsStyleDirChild -Path 'eva' | Should -BeFalse
        }

        It 'refuses to move a directory that is not a style directory, and sweeps nothing when it does' {
            # The assertion that would have gone red in the stub run above.
            # Move-StyleDirectoryToTrash re-proves containment at the moment of
            # the move, and the reversible step runs FIRST on purpose: a refused
            # move must not erase expired trash on its way out.
            $outside = Join-Path $script:root 'not-a-style'
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $outside 'keep.txt'), 'the user''s own file')

            $expired = Join-Path (Get-StyleTrashRoot) 'old-20200101-000000'
            New-Item -ItemType Directory -Path $expired -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $expired 'scheme.json'), '{"name":"old"}')

            $plan = [pscustomobject]@{
                Name         = 'not-a-style'
                Dir          = $outside
                TrashPath    = (Join-Path (Get-StyleTrashRoot) 'not-a-style-20260101-000000')
                SweepTargets = @(Get-Item -LiteralPath $expired -Force)
            }

            { Move-StyleDirectoryToTrash -Plan $plan } |
                Should -Throw -ExpectedMessage '*Refusing to move*'

            Test-Path -LiteralPath $outside | Should -BeTrue `
                -Because 'a directory outside the styles root must be left where it is'
            Test-Path -LiteralPath (Join-Path $outside 'keep.txt') | Should -BeTrue
            Test-Path -LiteralPath $expired | Should -BeTrue `
                -Because 'a move that did not happen erases nothing'
        }

        It 'lets a real style directory through' {
            # The other half: the guard must not refuse the case it exists to
            # permit, or the whole command is dead and this file would not
            # notice.
            $mine = Join-Path $script:userStyles 'mine'
            New-Item -ItemType Directory -Path $mine -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $mine 'scheme.json'), '{"name":"mine"}')

            $plan = [pscustomobject]@{
                Name         = 'mine'
                Dir          = $mine
                TrashPath    = (Join-Path (Get-StyleTrashRoot) 'mine-20260101-000000')
                SweepTargets = @()
            }
            Move-StyleDirectoryToTrash -Plan $plan
            Test-Path -LiteralPath $mine | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $plan.TrashPath 'scheme.json') | Should -BeTrue
        }
    }
}
