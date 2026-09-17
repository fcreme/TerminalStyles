# Pester 5 tests: a -Target name the tool OFFERS is a name the tool explains.
#
# THE DEFECT. Get-WTProfileShape puts 'defaults' first in .Available;
# Get-WTTargetNotFoundMessage prints that list verbatim ("Available: defaults,
# PowerShell, Ubuntu"), and apply.ps1 builds its "Which Windows Terminal profile
# to apply this style to?" menu from the same list. So the tool teaches the user
# the name. Nothing then explained it: measured on 0.8.28, the literal string
# 'defaults' occurred 0 times in README.md, 0 times in lib/help.ps1 and 0 times
# in docs/index.html, while `tstyles help` mentioned -Target only as "Windows
# Terminal profile to apply to, instead of the tab's own" plus one
# `-Target 'Ubuntu'` example.
#
# It is not an ordinary profile name. profiles.defaults is inherited by every
# profile that does not set a field itself, so a style applied there restyles
# all of them -- and 0.8.26's CHANGELOG records the surprising half deliberately
# ("clearing it strips the image from every profile inheriting it") in a file
# the user does not read. A listing that bounds itself is read as complete;
# this one put a fleet-wide target next to per-profile ones with nothing to tell
# them apart.
#
# Generalised rather than spelled: any name the resolver offers that is NOT one
# of the user's own profiles is a name this tool invented, and has to be
# explained in both places a user looks.
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

    $script:readme = [System.IO.File]::ReadAllText(
        (Join-Path $repoRoot 'README.md'), [System.Text.UTF8Encoding]::new($false))

    # Everything `tstyles help` can print, rendered rather than read off the
    # data structure: a Detail line that never reaches the screen is not help.
    $script:help = InModuleScope TerminalStyles {
        $rendered = (Show-TerminalStyleHelp 6>&1 | Out-String -Width 500)
        foreach ($topic in (Get-TerminalStyleHelpData).Name) {
            $rendered += (Show-TerminalStyleHelp -Command $topic 6>&1 | Out-String -Width 500)
        }
        $rendered
    }

    # The names the tool itself offers, for a settings.json shaped like a real
    # one. Asked of the resolver, never typed here.
    $script:offer = InModuleScope TerminalStyles {
        $settings = [pscustomobject]@{
            profiles = [pscustomobject]@{
                defaults = [pscustomobject]@{}
                list     = @(
                    [pscustomobject]@{ name = 'PowerShell'; guid = '{a}' },
                    [pscustomobject]@{ name = 'Ubuntu';     guid = '{b}' }
                )
            }
        }
        $shape = Get-WTProfileShape -Settings $settings
        [pscustomobject]@{
            Available = @($shape.Available)
            Own       = @($shape.List | ForEach-Object { $_.name })
            NotFound  = (Get-WTTargetNotFoundMessage -ResolvedTarget (
                            Resolve-WTProfileTarget -Settings $settings -TargetName 'PowerShel') `
                         -TargetName 'PowerShel')
            DefaultsResolves = (Resolve-WTProfileTarget -Settings $settings -TargetName 'defaults').Ok
        }
    }
}

Describe 'a -Target name the tool offers' {
    It 'is offered, and accepted, before anything is asked of the docs' {
        # The premise. Without it the two cases below would be demanding
        # documentation for a name the tool never mentions.
        $script:offer.Available   | Should -Contain 'defaults'
        $script:offer.Available[0] | Should -Be 'defaults' -Because 'it is the first thing the list offers'
        $script:offer.NotFound    | Should -Match 'defaults' -Because 'the not-found message prints that list verbatim'
        $script:offer.DefaultsResolves | Should -BeTrue -Because 'it is a name the resolver really accepts'
    }

    It 'is explained in `tstyles help`' {
        # Every offered name that is not one of the user's own profiles is one
        # this tool invented; a user has no other way to learn what it does.
        $invented = @($script:offer.Available | Where-Object { $_ -notin $script:offer.Own })
        @($invented).Count | Should -BeGreaterThan 0 `
            -Because 'if nothing is invented, this test is measuring nothing'
        foreach ($name in $invented) {
            $script:help | Should -Match ([regex]::Escape($name)) `
                -Because "the tool offers -Target $name, so its own help has to say what that does"
        }
        # Not just the word: what makes it different from a profile name.
        $script:help | Should -Match '(?i)profiles\.defaults'
        $script:help | Should -Match '(?i)inherit'
    }

    It 'is explained in the README' {
        $invented = @($script:offer.Available | Where-Object { $_ -notin $script:offer.Own })
        foreach ($name in $invented) {
            $script:readme | Should -Match ([regex]::Escape($name)) `
                -Because "a reader who saw `"Available: $($script:offer.Available -join ', ')`" has to be able to look it up"
        }
        $script:readme | Should -Match '(?i)profiles\.defaults'
        # Beside -Target, not in some unrelated paragraph.
        $script:readme | Should -Match '(?ms)-Target.{0,2000}defaults'
    }
}
