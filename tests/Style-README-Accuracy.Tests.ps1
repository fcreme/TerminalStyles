# Pester 5 tests: a style's README must describe the style it ships beside.
#
# The 16 bundled styles are the part of this project a reader judges it by, and
# their READMEs are the one thing here that nothing executed. Three claims were
# false and had been for their whole life:
#
#   - kitty and golden-forest both said "No profile.ps1 -- purely visual" while
#     shipping one that sets the window title, replaces function global:prompt,
#     and rewrites PSReadLine's colors. Someone reading that would have no idea
#     why their prompt changed, or that -KeepPrompt is the flag for it.
#   - gitbash documented "#A6A000 yellows" against a scheme whose yellow is
#     #9B961D. Every other hex in that same sentence is a verbatim scheme value,
#     so the one wrong one reads exactly as authoritative as the five right ones.
#
# Both are checkable, so they are checked here rather than by proofreading.
#
# The `## Includes` rule is SYMMETRIC, and for a while only one half of it was
# implemented: the section was required to name every file the style ships, and
# nothing stopped it naming one the style does not. An It called "does not deny
# a file it ships, or claim one it does not" carried its single Should inside
# `if ($onDisk)`, so the second clause of its own name was unfalsifiable.
# Measured against a synthetic style shipping scheme.json alone whose Includes
# list named theme.json and prompt.sh: green on all three Its.
#
# Which files that actually left uncovered is worth stating, because it is not
# the obvious one. `prompt.sh` was already covered -- tests/Shell-Prompt.Tests.ps1
# requires one beside every scheme.json, which CONTRIBUTING.md makes mandatory --
# and `scheme.json` is mandatory too. The genuinely uncovered claims were
# `theme.json` and `profile.ps1`, both optional, so no other test requires them.
#
# The rule is scoped to the `## Includes` section rather than to the whole
# README, because that is where this project has already decided that naming a
# file IS a claim. Prose like "its colours come from scheme.json" names a file
# without claiming to ship one, so a whole-README rule would fail honest READMEs.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:StyleCases = foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'README.md'))) { continue }
        @{ Name = $dir.Name; Dir = $dir.FullName }
    }
}

Describe 'bundled style READMEs describe what they ship' {

    BeforeAll {
        # One rule, one implementation, and it takes a DIRECTORY. The per-style
        # Its below are built from <repoRoot>/styles at discovery, so a
        # deliberately-wrong style cannot be committed there to prove the rule
        # bites -- it would turn the real suite red. Lifting the check into a
        # helper lets the fixture live in $TestDrive instead, and keeps the
        # assertion behavioural: it runs against generated files, not against
        # any function's source text.
        #
        # Missing     = ships it, the Includes list does not name it.
        # Overclaimed = the Includes list names it, the style does not ship it.
        function script:Get-StyleIncludesReport {
            param([Parameter(Mandatory)][string]$Dir)

            $report = [pscustomobject]@{
                HasSection = $false; Section = ''; Missing = @(); Overclaimed = @()
            }
            $readmePath = Join-Path $Dir 'README.md'
            if (-not (Test-Path -LiteralPath $readmePath)) { return $report }
            $readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.UTF8Encoding]::new($false))
            if (-not [regex]::IsMatch($readme, '(?m)^##\s+Includes\s*$')) { return $report }

            $report.HasSection = $true
            $report.Section = [regex]::Match($readme, '(?ms)^##\s+Includes\s*$(.*?)(?=^##\s|\z)').Groups[1].Value

            foreach ($file in 'scheme.json', 'theme.json', 'profile.ps1', 'prompt.sh') {
                $escaped = [regex]::Escape($file)
                $named   = [regex]::IsMatch($report.Section, $escaped)
                # Naming a file to DENY it is not claiming it: "No `theme.json`"
                # is the phrasing these READMEs use, and it is exactly what the
                # denial check in the It above measures. Same pattern here, so
                # the two halves cannot disagree about what a denial looks like.
                $denied  = [regex]::IsMatch($report.Section, ("(?i)\bno\s+``?" + $escaped + "``?"))
                if (Test-Path -LiteralPath (Join-Path $Dir $file)) {
                    if (-not $named) { $report.Missing = @($report.Missing) + $file }
                } elseif ($named -and -not $denied) {
                    $report.Overclaimed = @($report.Overclaimed) + $file
                }
            }
            return $report
        }
    }

    It '<Name> does not deny a file it ships' -ForEach $script:StyleCases {
        # Named for what it measures, which is one direction: a README must not
        # say "No `profile.ps1`" while shipping one. The other direction --
        # claiming a file that is not there -- is the Includes It below, scoped
        # to the section where a file list is a claim. This It used to carry
        # both clauses in its name and only this one in its body.
        $readme = [System.IO.File]::ReadAllText(
            (Join-Path $Dir 'README.md'), [System.Text.UTF8Encoding]::new($false))

        foreach ($file in 'profile.ps1', 'prompt.sh', 'scheme.json', 'theme.json') {
            $onDisk = Test-Path -LiteralPath (Join-Path $Dir $file)
            $escaped = [regex]::Escape($file)
            # "No `profile.ps1`" and friends -- the shape both false claims took.
            $denied = $readme -match ("(?i)\bno\s+``?" + $escaped + "``?")
            if ($onDisk) {
                $denied | Should -BeFalse `
                    -Because "$Name ships $file, so its README must not say it has none"
            }
        }
    }

    It '<Name>''s Includes list is what it ships, both ways' -ForEach $script:StyleCases {
        # Scoped to READMEs that HAVE an "## Includes" section, on purpose. Eight
        # of the sixteen are short prose descriptions that enumerate nothing --
        # they make no claim about the file list, so there is nothing there to be
        # wrong, and requiring one would invent a rule CONTRIBUTING never states.
        #
        # The other eight do enumerate, and that is a claim in both directions.
        # kitty's and golden-forest's lists ran scheme.json, theme.json, and then
        # "No profile.ps1 -- purely visual" while shipping a profile.ps1 that
        # rebinds global:prompt. Someone whose prompt changed had that paragraph
        # to read. The mirror image -- a list naming a theme.json or a profile.ps1
        # the folder does not contain -- sends a reader looking for a file that
        # was never there, and both of those are optional per CONTRIBUTING, so
        # nothing else in the suite would catch it.
        $r = script:Get-StyleIncludesReport -Dir $Dir
        if (-not $r.HasSection) {
            Set-ItResult -Skipped -Because "$Name's README enumerates nothing, so it claims nothing"
            return
        }
        $r.Section | Should -Not -BeNullOrEmpty

        ($r.Missing -join ', ') | Should -BeNullOrEmpty `
            -Because "$Name ships those, and its README lists what it ships"
        ($r.Overclaimed -join ', ') | Should -BeNullOrEmpty `
            -Because "$Name's README lists those and the folder does not contain them"
    }

    Context 'the Includes rule, against fixtures the styles tree cannot hold' {
        # A style deliberately in breach cannot be committed under styles/ -- the
        # cases above walk that directory -- so the rule is driven over generated
        # folders instead. Before the symmetric half existed, the first of these
        # was reported clean.
        BeforeAll {
            function script:New-FixtureStyle {
                param([string[]]$Ships, [string]$Readme)
                $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                foreach ($f in $Ships) {
                    [System.IO.File]::WriteAllText((Join-Path $dir $f), '{}',
                        [System.Text.UTF8Encoding]::new($false))
                }
                [System.IO.File]::WriteAllText((Join-Path $dir 'README.md'), $Readme,
                    [System.Text.UTF8Encoding]::new($false))
                return $dir
            }
        }

        It 'reports a file the Includes list names and the folder does not hold' {
            $dir = script:New-FixtureStyle -Ships @('scheme.json', 'prompt.sh') -Readme @'
# liar

## Includes

- `scheme.json` -- the palette
- `theme.json` -- profile overrides
- `prompt.sh` -- the shell prompt
'@
            $r = script:Get-StyleIncludesReport -Dir $dir
            $r.HasSection | Should -BeTrue
            @($r.Overclaimed) | Should -Be @('theme.json') `
                -Because 'the list names theme.json and the folder has none'
            @($r.Missing).Count | Should -Be 0 -Because 'both files it ships are listed'
        }

        It 'still reports a file it ships that the list leaves out' {
            # The direction that already worked, driven through the same helper
            # so the two cannot be implemented differently.
            $dir = script:New-FixtureStyle -Ships @('scheme.json', 'prompt.sh') -Readme @'
# quiet

## Includes

- `scheme.json` -- the palette
'@
            $r = script:Get-StyleIncludesReport -Dir $dir
            @($r.Missing) | Should -Be @('prompt.sh')
            @($r.Overclaimed).Count | Should -Be 0
        }

        It 'does not call a denial a claim' {
            # "No `theme.json`" names the file in order to say it is absent.
            # That is the phrasing the bundled READMEs use, and it must stay
            # legal or this rule would fail the styles it was written from.
            $dir = script:New-FixtureStyle -Ships @('scheme.json', 'prompt.sh') -Readme @'
# honest

## Includes

- `scheme.json` -- the palette
- `prompt.sh` -- the shell prompt
- No `theme.json`, no `profile.ps1` -- purely visual
'@
            $r = script:Get-StyleIncludesReport -Dir $dir
            @($r.Overclaimed).Count | Should -Be 0
            @($r.Missing).Count     | Should -Be 0
        }

        It 'says nothing about a README that enumerates nothing' {
            $dir = script:New-FixtureStyle -Ships @('scheme.json') -Readme @'
# prose

A dark theme. Its colours come from `scheme.json`, and a `prompt.sh` is the
sort of thing another style might add.
'@
            $r = script:Get-StyleIncludesReport -Dir $dir
            $r.HasSection | Should -BeFalse `
                -Because 'prose naming a file is not a file list, and this rule only reads the list'
            @($r.Overclaimed).Count | Should -Be 0
        }
    }

    It '<Name> quotes no colour it does not actually use' -ForEach $script:StyleCases {
        $schemePath = Join-Path $Dir 'scheme.json'
        if (-not (Test-Path -LiteralPath $schemePath)) {
            Set-ItResult -Skipped -Because "$Name ships no scheme.json"
            return
        }
        $scheme = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
        $inScheme = @($scheme.PSObject.Properties |
            Where-Object { $_.Value -is [string] -and $_.Value -like '#*' } |
            ForEach-Object { $_.Value.ToLowerInvariant() })

        $readme = [System.IO.File]::ReadAllText(
            (Join-Path $Dir 'README.md'), [System.Text.UTF8Encoding]::new($false))
        foreach ($m in [regex]::Matches($readme, '#[0-9A-Fa-f]{6}\b')) {
            $inScheme | Should -Contain $m.Value.ToLowerInvariant() `
                -Because "$Name's README quotes $($m.Value), which is in no slot of its scheme.json"
        }
    }
}
