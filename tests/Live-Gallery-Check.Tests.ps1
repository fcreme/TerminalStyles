# Pester 5 tests for scripts/live-gallery-check.ps1, the driver behind
# .github/workflows/live-gallery.yml.
#
# That script installs TerminalStyles from the PowerShell Gallery, updates it,
# and then uninstalls it FOR REAL with -Yes. That is the point on a throwaway
# GitHub-hosted runner, and on anyone's own machine it would remove their
# install -- every version. So these tests never run it. They dot-source it for
# its functions, which is all it does when dot-sourced, and pin two things:
# the guard that keeps it off every machine but a GitHub-hosted runner, and the
# verdicts, so that a check meant to catch a broken release cannot pass by
# comparing nothing.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/live-gallery-check.ps1')
}

Describe 'live-gallery-check.ps1: where it runs' {
    It 'runs only on a GitHub-hosted runner' {
        Test-GitHubHostedRunner -GitHubActions '' -RunnerEnvironment '' | Should -BeFalse
        Test-GitHubHostedRunner -GitHubActions '' -RunnerEnvironment 'github-hosted' | Should -BeFalse
        Test-GitHubHostedRunner -GitHubActions 'true' -RunnerEnvironment 'self-hosted' |
            Should -BeFalse -Because 'GITHUB_ACTIONS is set on a self-hosted runner too, and that is somebody''s machine'
        Test-GitHubHostedRunner -GitHubActions 'true' -RunnerEnvironment 'github-hosted' | Should -BeTrue
    }

    It 'refuses before it sets up, asks the Gallery anything, or installs' {
        # Every step with a side effect goes through one of these four, so
        # throwing mocks also keep a broken guard from doing anything here.
        Mock Test-GitHubHostedRunner { $false }
        Mock Initialize-GalleryClient { throw 'set up a Gallery client' }
        Mock Get-PublishedVersion { throw 'asked the Gallery for its versions' }
        Mock Wait-GalleryNewest { throw 'polled the Gallery feed' }
        Mock Invoke-Phase { throw 'started a step' }

        $code = Invoke-LiveGalleryCheck 6>$null
        $code | Should -Be 2 -Because 'one exit code, and nothing else on the pipeline'
        Should -Invoke Test-GitHubHostedRunner -Times 1 -Exactly
        Should -Invoke Initialize-GalleryClient -Times 0 -Exactly
        Should -Invoke Get-PublishedVersion -Times 0 -Exactly
        Should -Invoke Wait-GalleryNewest -Times 0 -Exactly
        Should -Invoke Invoke-Phase -Times 0 -Exactly
    }
}

Describe 'live-gallery-check.ps1: which release it starts from' {
    It 'takes the newest release before the one under test, compared as versions' {
        # As text, 0.9.10 sorts before 0.9.9.
        Select-StartVersion -Published @('0.8.48', '0.9.9', '0.9.11', '0.9.10') -Newest '0.9.11' |
            Should -Be '0.9.10'
    }

    It 'answers nothing when no release came before' {
        Select-StartVersion -Published @('0.9.2') -Newest '0.9.2' | Should -BeNullOrEmpty
    }
}

Describe 'live-gallery-check.ps1: what passes' {
    Context 'the update notice' {
        It 'passes when the installed version is told of the newest' {
            $r = [pscustomobject]@{ Installed = '0.9.1'; Remote = '0.9.2' }
            Get-NoticeVerdict -Result $r -From '0.9.1' -Newest '0.9.2' | Should -BeNullOrEmpty
        }

        It 'fails when nothing is offered -- what 0.9.0 does for every Gallery install' {
            $r = [pscustomobject]@{ Installed = ''; Remote = '' }
            Get-NoticeVerdict -Result $r -From '0.9.0' -Newest '0.9.2' | Should -Match 'no update notice'
            Get-NoticeVerdict -Result $null -From '0.9.0' -Newest '0.9.2' | Should -Match 'no update notice'
        }

        It 'fails when the check leaves the session''s TLS setting changed' {
            $r = [pscustomobject]@{ Installed = '0.9.1'; Remote = '0.9.2' }
            Get-NoticeVerdict -Result $r -From '0.9.1' -Newest '0.9.2' -ProtocolBefore 'Tls' -ProtocolAfter 'Tls, Tls12' |
                Should -Match 'SecurityProtocol'
        }
    }

    Context 'tstyles update' {
        It 'passes when it reports the update and both versions are on disk' {
            Get-UpdateVerdict -Output "  Updated 0.9.1 -> 0.9.2`n" -From '0.9.1' -Newest '0.9.2' -Versions @('0.9.2', '0.9.1') |
                Should -BeNullOrEmpty
        }

        It 'does not take "Already the latest" for an update' {
            Get-UpdateVerdict -Output '  Already the latest (0.9.1). Nothing to do.' -From '0.9.1' -Newest '0.9.2' -Versions @('0.9.1') |
                Should -Match 'did not report'
        }

        It 'does not take the report''s word for what is on disk' {
            Get-UpdateVerdict -Output '  Updated 0.9.1 -> 0.9.2' -From '0.9.1' -Newest '0.9.2' -Versions @('0.9.1') |
                Should -Match 'installed now'
        }
    }

    Context 'tstyles uninstall' {
        It 'passes "TerminalStyles uninstalled." with no copy left' {
            $out = "  Removed module via Uninstall-Module`r`nTerminalStyles uninstalled.`r`nOpen a new pwsh tab to confirm the loader is gone.`r`n"
            Get-UninstallVerdict -Output $out -CopiesLeft @() | Should -BeNullOrEmpty
        }

        It 'calls out "uninstalled." printed over a copy still installed -- what 0.9.1 did on 5.1' {
            $out = "  Uninstall-PSResource reported an error: The term 'Uninstall-PSResource' is not recognized`nTerminalStyles uninstalled.`n"
            Get-UninstallVerdict -Output $out -CopiesLeft @('C:\Users\me\Documents\WindowsPowerShell\Modules\TerminalStyles\0.9.1') |
                Should -Match 'signed off'
        }

        It 'fails a truthful sign-off that still leaves a copy' {
            $out = "TerminalStyles is NOT fully uninstalled. Still in place:`n  C:\x\TerminalStyles\0.9.1`n"
            Get-UninstallVerdict -Output $out -CopiesLeft @('C:\x\TerminalStyles\0.9.1') | Should -Match 'still installed'
        }

        It 'does not take "uninstalled, EXCEPT" for the sign-off' {
            $out = "TerminalStyles uninstalled, EXCEPT the loader block in:`n  C:\x\profile.ps1`n"
            Get-UninstallVerdict -Output $out -CopiesLeft @() | Should -Match 'did not sign off'
        }
    }
}
