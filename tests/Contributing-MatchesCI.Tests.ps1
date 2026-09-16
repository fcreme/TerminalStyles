# Pester 5 tests: CONTRIBUTING.md must document what CI actually enforces.
#
# The bug these prevent: CONTRIBUTING described a theme folder as four files and
# never mentioned prompt.sh, while tests/Shell-Prompt.Tests.ps1 walks every
# directory under styles/ and asserts each one HAS a prompt.sh beside its
# profile.ps1. All sixteen bundled themes ship one, so the gap was invisible to
# the maintainer and hit only newcomers -- following the contributing guide
# exactly turned the Linux and macOS legs red on a first PR, which is the worst
# possible first experience of a project.
#
# Docs drift silently because nothing executes them. These assertions are the
# link between the two files.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Imported explicitly, like every other file here. Without it, the
# InModuleScope blocks below bind to whatever TerminalStyles the session happens
# to have auto-loaded -- on a developer machine that is the INSTALLED module,
# which is a different (older) version of the code this suite is testing: the
# help data it answered with was missing a topic the repo has had for releases.
# In CI it only worked because an alphabetically earlier file had imported it.
BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    $script:repoRoot     = Split-Path $PSScriptRoot -Parent
    # Explicit, like every other file in the suite. The cache-directory It below
    # runs InModuleScope, and this file used to reach the module only as a side
    # effect of a `Get-Command Invoke-TerminalStyle` in the picker-backup guard
    # -- which auto-imports whatever TerminalStyles is INSTALLED on the machine
    # (the PSGallery copy under ~/.local/share/powershell/Modules), not the one
    # in this checkout. Measuring the repo means importing the repo.
    Import-Module (Join-Path $script:repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:contributing = [System.IO.File]::ReadAllText(
        (Join-Path $script:repoRoot 'CONTRIBUTING.md'), [System.Text.UTF8Encoding]::new($false))
    $script:security     = [System.IO.File]::ReadAllText(
        (Join-Path $script:repoRoot 'SECURITY.md'), [System.Text.UTF8Encoding]::new($false))
}

Describe 'CONTRIBUTING.md documents the files CI requires' {

    It 'mentions prompt.sh' {
        $script:contributing | Should -Match 'prompt\.sh'
    }

    It 'lists prompt.sh in the theme folder layout' {
        # The fenced tree near the top is what a contributor copies.
        $tree = [regex]::Match($script:contributing, '(?s)```\s*\nstyles/<name>/.*?```').Value
        $tree | Should -Not -BeNullOrEmpty -Because 'the styles/<name>/ tree should still be there'
        $tree | Should -Match 'prompt\.sh'
        $tree | Should -Match 'scheme\.json'
    }

    It 'lists prompt.sh in the submission checklist too' {
        # A contributor who skims to the flow and copies the parenthesised list
        # must get the same answer as one who read the tree.
        $flow = [regex]::Match($script:contributing,
            '(?s)\*\*Code on `main`:\*\*.*?open\s*\n?\s*a PR against `main`\.').Value
        $flow | Should -Not -BeNullOrEmpty
        $flow | Should -Match 'prompt\.sh'
    }

    It 'points at a real example to copy' {
        foreach ($m in [regex]::Matches($script:contributing, 'styles/([a-z0-9-]+)/prompt\.sh')) {
            $name = $m.Groups[1].Value
            Test-Path -LiteralPath (Join-Path $script:repoRoot "styles/$name/prompt.sh") |
                Should -BeTrue -Because "CONTRIBUTING points at styles/$name/prompt.sh"
        }
    }

    It 'the requirement it documents is the one the suite enforces' {
        # If someone ever relaxes Shell-Prompt.Tests.ps1, this fails and the doc
        # gets revisited rather than silently becoming wrong in the other
        # direction.
        $shellPrompt = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'tests/Shell-Prompt.Tests.ps1'), [System.Text.UTF8Encoding]::new($false))
        $shellPrompt | Should -Match "has a prompt\.sh alongside its profile\.ps1"
    }
}

Describe 'SECURITY.md tracks the shipped version' {

    It 'names the current minor series as supported' {
        $manifest = Import-PowerShellDataFile (Join-Path $script:repoRoot 'TerminalStyles.psd1')
        $v = [version]$manifest.ModuleVersion
        $series = "$($v.Major).$($v.Minor).x"
        $script:security | Should -Match ([regex]::Escape($series))
    }

    It 'is internally consistent about the reporting channel' {
        # This document once named GitHub private vulnerability reporting as the
        # PREFERRED route while the repository had it disabled, sending reporters
        # to a Security tab with no such button. Private reporting is enabled
        # now, so pointing at the button is correct -- but the doc must not do
        # both: claim the button exists AND say the feature is off.
        $claimsButton  = $script:security -match 'Report a vulnerability'
        $claimsDisabled = $script:security -match 'not currently enabled'
        ($claimsButton -and $claimsDisabled) | Should -BeFalse `
            -Because 'the doc cannot both offer the button and say it is unavailable'
    }

    It 'gives a channel that does exist' {
        $script:security | Should -Match '@'
    }
}

Describe 'README claims that the code can settle' {
    # Prose drifts from code silently because nothing executes it. These are the
    # README statements a reader would act on, each pinned to the thing that
    # makes it true or false.
    BeforeAll {
        $script:readme = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'README.md'),
            [System.Text.UTF8Encoding]::new($false))
    }

    It 'does not claim the picker skips the rolling backup' {
        # The picker writes one before its first preview -- Invoke-TerminalStyle
        # calls Save-SettingsBackup, which copies settings.json to "<path>.bak".
        # The README said the opposite, which would have talked someone out of a
        # recovery path that exists.
        #
        # This assertion used to sit behind `if ($src -match '\$settingsPath\.bak')`
        # -- a probe of Invoke-TerminalStyle's OWN SOURCE TEXT. The picker's
        # backup moved into Save-SettingsBackup (lib/wtsettings.ps1), the probe
        # went False, and the It ran zero assertions while still reporting
        # green: fed the exact regression it guards ("Opening the picker
        # doesn't write a `.bak`, so there is no way back.") it passed. A
        # source-text probe cannot survive the refactors it is meant to outlive,
        # and there is no state in which this claim should go unchecked -- the
        # picker's backup is pinned behaviourally by
        # tests/Backup-BeforeValidation.Tests.ps1 -- so it is asserted
        # unconditionally now.
        #
        # Anchored to the `### Recovering` section the neighbouring It already
        # extracts, so the two bound the same sentences from both sides: that
        # one requires the section to NAME the picker among the writers, this
        # one requires it not to deny that it writes.
        $section = ([regex]::Match($script:readme, '(?ms)^### Recovering.*?(?=^#{2,3} )')).Value
        $section | Should -Not -BeNullOrEmpty -Because 'the recovery recipe is what this test is about'
        $section | Should -Match '(?i)picker' `
            -Because 'a section that never mentions the picker would make the check below vacuous'
        $section | Should -Not -Match '(?i)picker[^.]{0,80}\b(does not|doesn''t|never|skips)\b' `
            -Because 'the picker rolls settings.json.bak before its first preview'
    }

    It 'names every command that spends the rolling backup' {
        # The recovery recipe is a claim the user acts on with Copy-Item, and it
        # listed two of the five writers. `tstyles font` and `tstyles tune` roll
        # the same single .bak, so after either one "restore the last-known-good
        # state" restores the file from after the apply, not before it -- and
        # `tstyles reset` is no way back, since it removes what a style ADDED and
        # cannot return what the style overwrote.
        #
        # Derived from the AST rather than from a list, so a sixth writer fails
        # here until the section admits it.
        $commandFor = @{
            'Invoke-TerminalStyle'     = 'picker'          # tstyles with no arg
            'Invoke-TerminalStyleTune' = 'tstyles tune'
            'Invoke-TerminalStyleFont' = 'tstyles font'
            'Apply-StyleDirect'        = 'tstyles <name>'
            'Reset-StyleDirect'        = 'tstyles reset'
        }

        $repoRoot = Split-Path $PSScriptRoot -Parent
        $files = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
            Where-Object { $_.FullName -notmatch '[\\/](tests|out)[\\/]' }

        $writers = @()
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $calls = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Save-SettingsBackup' }, $true))
            foreach ($c in $calls) {
                $fn = $c.Parent
                while ($fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                if ($fn -and $fn.Name -ne 'Save-SettingsBackup') { $writers += $fn.Name }
            }
        }
        $writers = @($writers | Sort-Object -Unique)
        $writers.Count | Should -BeGreaterThan 2 -Because 'the scan must actually be finding the writers'

        @($writers | Where-Object { -not $commandFor.ContainsKey($_) }) -join ', ' |
            Should -BeNullOrEmpty -Because 'a new writer of the single rolling .bak needs a name in the README recipe'

        $section = ([regex]::Match($script:readme, '(?ms)^### Recovering.*?(?=^#{2,3} )')).Value
        $section | Should -Not -BeNullOrEmpty -Because 'the recovery recipe is what this test is about'
        foreach ($w in $writers) {
            $section | Should -BeLike "*$($commandFor[$w])*" `
                -Because "$w rolls the one .bak the recipe tells the user to restore"
        }
    }

    It 'does not tell a -KeepPrompt user their style goes unreported' {
        # README said a -KeepPrompt apply "isn't reported by `tstyles current` /
        # the `*` in `tstyles list`, because active-style detection is
        # prompt-based". The premise is true -- current-style.ps1 really is left
        # absent -- and the conclusion is false: Get-CurrentStyleName falls back
        # to the record every apply writes, and the comment beside that fallback
        # names -KeepPrompt as the case it exists for. The claim would talk an Oh
        # My Posh or Starship user out of four things that work.
        $detected = InModuleScope TerminalStyles {
            # Saved and put back: these are MODULE-scope variables, so a sandbox
            # left in place here would follow the module into every test file
            # that runs after this one.
            $savedData   = $script:TStylesDataRoot
            $savedModule = $script:TStylesModuleRoot
            $savedCurrent = $script:TStylesCurrent
            try {
                $script:TStylesDataRoot   = Join-Path $TestDrive ('kp-' + [guid]::NewGuid().ToString('n'))
                $script:TStylesModuleRoot = $script:TStylesDataRoot
                # Computed from the data root at module load, so it moves too.
                $script:TStylesCurrent    = Join-Path $script:TStylesDataRoot 'current-style.ps1'

                $dir = Join-Path $script:TStylesDataRoot 'styles/mine'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $enc = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'),
                    '{"name":"mine","background":"#101010","foreground":"#f0f0f0"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $dir 'profile.ps1'), '# my prompt', $enc)

                Mock Get-TerminalKind           { 'AppleTerminal' }
                Mock Write-HostOscPacket        { }
                Mock Write-Host                 { }
                Mock Get-StyleBundledBackground { $null }   # keeps this off the network

                Apply-StyleNonWT -StyleName 'mine' -StyleDir $dir -KeepPrompt

                [pscustomobject]@{
                    Name            = (Get-CurrentStyleName)
                    PromptInstalled = (Test-Path -LiteralPath $script:TStylesCurrent)
                }
            } finally {
                $script:TStylesDataRoot   = $savedData
                $script:TStylesModuleRoot = $savedModule
                $script:TStylesCurrent    = $savedCurrent
            }
        }

        $detected.PromptInstalled | Should -BeFalse `
            -Because 'this is the README''s own premise: -KeepPrompt installs no prompt file'
        $detected.Name | Should -Be 'mine' `
            -Because 'and the style is still reported, off the record rather than off the prompt'

        $script:readme | Should -Not -Match "(?i)apply (isn't|is not) reported" `
            -Because 'tstyles current, tstyles list, the picker and tstyles tune all find it'
    }

    It 'does not offer a settings.json.bak where the reset writes no file' {
        # The help topic has said this since 0.8.21 ("Elsewhere there is no
        # settings.json to strip... nothing to back up and no .bak is written")
        # and tests/Show-TerminalStyleHelp.Tests.ps1 pins that half. The README
        # sentence was never revisited, so it offered a safety net that does not
        # exist off Windows Terminal.
        #
        # Guarded on the measured fact, so it dissolves on its own if a non-WT
        # backup is ever added.
        $created = InModuleScope TerminalStyles {
            $savedData    = $script:TStylesDataRoot
            $savedModule  = $script:TStylesModuleRoot
            $savedCurrent = $script:TStylesCurrent
            try {
                $root = Join-Path $TestDrive ('rs-' + [guid]::NewGuid().ToString('n'))
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                $script:TStylesDataRoot   = $root
                $script:TStylesModuleRoot = $root
                $script:TStylesCurrent    = Join-Path $root 'current-style.ps1'

                Mock Get-TerminalKind    { 'AppleTerminal' }
                Mock Write-HostOscPacket { }
                Mock Write-Host          { }

                Reset-StyleNonWT

                @(Get-ChildItem -LiteralPath $root -Recurse -Force -File | ForEach-Object { $_.Name })
            } finally {
                $script:TStylesDataRoot   = $savedData
                $script:TStylesModuleRoot = $savedModule
                $script:TStylesCurrent    = $savedCurrent
            }
        }
        @($created) | Should -BeNullOrEmpty -Because 'the non-WT reset is an escape sequence; it writes nothing'

        $section = ([regex]::Match($script:readme, '(?ms)^### Resetting a profile.*?(?=^#{2,3} )')).Value
        $section | Should -Not -BeNullOrEmpty -Because 'the section this test is about must still exist'
        if ($section -match 'settings\.json\.bak') {
            # NOT '(?i)windows terminal' among the alternatives, however natural
            # it looks: the section opens "return a profile to Windows Terminal's
            # plain default", so that clause is present in the defective text too
            # and the assertion would pass while measuring nothing. What has to
            # be there is the OTHER half -- what happens everywhere else.
            $section | Should -Match '(?i)(elsewhere|outside|other terminals?|nothing to back up|no `?\.bak)' `
                -Because 'off Windows Terminal there is no settings.json and no .bak is written'
        }
    }

    It 'names every subcommand in the one consolidated command reference' {
        # The `### Subcommands` fence is the only place in the README that lists
        # the commands, and it went two behind: shell-init and shell-remove had
        # help topics, dispatched, and appeared only 270 lines further down, in a
        # section about zsh and bash. Parsed from the shipped file and compared
        # with the live module, so it fails on a real documentation defect and
        # survives any refactor that keeps the two in agreement.
        $fence = [regex]::Match($script:readme, '(?ms)^### Subcommands\s*\r?\n```powershell\r?\n(.*?)```')
        $fence.Success | Should -BeTrue -Because 'the block this test is about must still exist'

        $named = @($fence.Groups[1].Value -split "`n" |
                   ForEach-Object { if ($_ -match '^tstyles\s+([A-Za-z0-9-]+)') { $Matches[1] } })
        $named.Count | Should -BeGreaterThan 5 -Because 'a fence that parsed to nothing would pass silently'

        # From the help data, not from $script:TStylesSubcommands: the dispatcher
        # list carries the `ls` alias, which is not a topic and wants no README
        # line. Get-TerminalStyleHelpData.Tests.ps1 filters it for the same reason.
        $topics = InModuleScope TerminalStyles {
            @(Get-TerminalStyleHelpData | ForEach-Object { $_.Name })
        }
        @($topics | Where-Object { $named -notcontains $_ }) -join ', ' |
            Should -BeNullOrEmpty -Because 'a command with a help topic belongs in the README command list'

        # The other direction, and NOT "every token is a subcommand": the first
        # line of the block is `tstyles umbrella`, a STYLE name, and one line is
        # a flag variant. What must hold is that every token names something.
        $styleNames = InModuleScope TerminalStyles {
            @(Get-AvailableStyles | ForEach-Object { $_.Name })
        }
        foreach ($t in ($named | Sort-Object -Unique)) {
            ($topics -contains $t -or $styleNames -contains $t) |
                Should -BeTrue -Because "'tstyles $t' must name something that exists"
        }
    }

    It 'points at the cache directory the code actually uses' {
        # Get-StyleCacheDir puts fetched backgrounds under <DataRoot>/cache/<name>.
        # The README pointed at the pre-0.2.0 styles/<name> location, so anyone
        # looking for their cache -- or trying to clear it -- looked in the wrong
        # place.
        $leaf = InModuleScope TerminalStyles {
            Split-Path (Split-Path (Get-StyleCacheDir -StyleName 'eva') -Parent) -Leaf
        }
        $leaf | Should -Be 'cache'
        $script:readme | Should -Match 'TerminalStyles\\cache\\<name>'
    }

    It 'does not describe background images as committed binaries' {
        # .gitignore blocks them and tests/No-Committed-Backgrounds.Tests.ps1
        # fails the build if one becomes tracked.
        $gitignore = [System.IO.File]::ReadAllText(
            (Join-Path (Split-Path $PSScriptRoot -Parent) '.gitignore'),
            [System.Text.UTF8Encoding]::new($false))
        $gitignore | Should -Match 'background'
        $script:readme | Should -Not -Match 'Bundled GIFs are committed binaries'
    }
}

Describe 'CHANGELOG dates match the tags they describe' {

    It '<_> is dated as its tag was' -ForEach @('0.8.2', '0.8.3', '0.8.4') {
        $repoRoot = Split-Path $PSScriptRoot -Parent

        # Ask git whether the tag EXISTS before asking about its date. CI checks
        # out with actions/checkout@v4 at fetch-depth 1, which brings no tags at
        # all, and `git log v0.8.2` on a missing ref does not fail the same way
        # on Windows PowerShell 5.1 as it does elsewhere -- it left a non-empty
        # value that then compared unequal, so this failed on one leg and passed
        # on three. `git tag -l` is unambiguous everywhere.
        $hasTag = @(& git -C $repoRoot tag -l "v$_" 2>$null) -contains "v$_"
        if (-not $hasTag) {
            Set-ItResult -Skipped -Because "tag v$_ is not in this checkout (CI clones without tags)"
            return
        }
        $tagDate = (& git -C $repoRoot log -1 --format=%ad --date=short "v$_" 2>$null) | Select-Object -First 1
        if (-not $tagDate) { Set-ItResult -Skipped -Because "could not read the date of v$_"; return }
        $changelog = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'CHANGELOG.md'), [System.Text.UTF8Encoding]::new($false))
        $m = [regex]::Match($changelog, "## \[$([regex]::Escape($_))\] - (\d{4}-\d{2}-\d{2})")
        $m.Success | Should -BeTrue -Because "$_ should have a dated heading"
        $m.Groups[1].Value | Should -Be $tagDate
    }
}
