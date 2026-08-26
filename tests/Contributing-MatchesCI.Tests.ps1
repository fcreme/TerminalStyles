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

BeforeAll {
    $script:repoRoot     = Split-Path $PSScriptRoot -Parent
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
        # It writes one before its first preview -- Invoke-TerminalStyle does
        # WriteAllText to "$settingsPath.bak". The README said the opposite,
        # which would have talked someone out of a recovery path that exists.
        $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        $writesBak = $src -match '\$settingsPath\.bak'
        if ($writesBak) {
            $script:readme | Should -Not -Match "picker.*doesn't write a ``\.bak``"
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
        $tagDate = (& git -C $repoRoot log -1 --format=%ad --date=short "v$_" 2>$null)
        if (-not $tagDate) { Set-ItResult -Skipped -Because "tag v$_ is not present"; return }
        $changelog = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'CHANGELOG.md'), [System.Text.UTF8Encoding]::new($false))
        $m = [regex]::Match($changelog, "## \[$([regex]::Escape($_))\] - (\d{4}-\d{2}-\d{2})")
        $m.Success | Should -BeTrue -Because "$_ should have a dated heading"
        $m.Groups[1].Value | Should -Be $tagDate
    }
}
