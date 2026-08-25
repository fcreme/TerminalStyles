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

    It 'does not advertise a reporting channel that is turned off' {
        # It named GitHub private vulnerability reporting as the PREFERRED route
        # while the repo has it disabled, sending reporters to a Security tab
        # with no "Report a vulnerability" button. Either enable it and say so,
        # or say plainly that it is off -- but do not point at a missing button.
        if ($script:security -match 'Report a vulnerability') {
            $script:security | Should -Match 'not currently enabled' `
                -Because 'the button does not exist unless private reporting is enabled'
        }
    }

    It 'gives a channel that does exist' {
        $script:security | Should -Match '@'
    }
}
