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
