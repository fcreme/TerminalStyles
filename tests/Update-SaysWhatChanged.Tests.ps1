# `tstyles update` used to print "Update complete" whether it had updated or
# not. Update-PSResource is a no-op when the newest version is already
# installed and says nothing either way, so running the command on the latest
# version reported success for work it had not done.
#
# The Bootstrap arm of the same command already got this right -- "Already up to
# date (abc1234)" -- so one command answered "did anything happen?" two
# different ways depending on how you installed it.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Get-UpdateOutcome' {
    InModuleScope TerminalStyles {

        It 'calls a higher version an update' {
            Get-UpdateOutcome -Before '0.8.30' -After '0.8.32' | Should -Be 'updated'
            Get-UpdateOutcome -Before '0.8.9'  -After '0.8.10' | Should -Be 'updated' `
                -Because 'version order is not string order'
        }

        It 'calls the same version current' {
            Get-UpdateOutcome -Before '0.8.32' -After '0.8.32' | Should -Be 'current'
        }

        It 'refuses to guess when either side is unreadable' {
            # 'unknown' is a real answer, not a failure. Claiming either outcome
            # would be reporting something the command did not establish.
            foreach ($c in @(@($null,'0.8.32'), @('0.8.32',$null), @('','0.8.32'),
                             @('not-a-version','0.8.32'), @('0.8.32','not-a-version'))) {
                Get-UpdateOutcome -Before $c[0] -After $c[1] | Should -Be 'unknown'
            }
        }

        It 'does not call a downgrade an update' {
            # Not a state the gallery produces, but a pinned or side-loaded copy
            # can, and "Updated 0.8.32 -> 0.8.30" would be false.
            Get-UpdateOutcome -Before '0.8.32' -After '0.8.30' | Should -Be 'unknown'
        }
    }
}

Describe 'Get-SentenceSummary' {
    InModuleScope TerminalStyles {

        It 'keeps a short note whole' {
            Get-SentenceSummary -Notes 'One short line.' | Should -Be 'One short line.'
        }

        It 'does not treat a version number as three sentences' {
            # The first attempt split "v0.8.32" on its dots and opened the
            # summary with "v0. 8. 32:". A terminator only ends a sentence when
            # a space or the end of the string follows it.
            $n = 'v0.8.32: two things restored. And a second sentence that pushes this well past the cap so a cut is actually required here.'
            $s = Get-SentenceSummary -Notes $n -MaxLength 60
            $s | Should -BeLike 'v0.8.32: two things restored.*'
            $s | Should -Not -Match 'v0\. 8\. 32'
        }

        It 'keeps the opening, not some later fragment' {
            # Matches are not contiguous from the start, so gluing their values
            # together dropped whatever the engine skipped -- the version prefix
            # came out as "32: two things restored". Slicing the original string
            # at an index cannot do that.
            $n = 'v0.8.32: two things restored. Another sentence follows it here to force a cut.'
            (Get-SentenceSummary -Notes $n -MaxLength 40) | Should -BeLike 'v0.8.32:*'
        }

        It 'cuts at a sentence end, not mid-clause' {
            $n = 'First sentence here. Second sentence here. Third sentence here.'
            $s = Get-SentenceSummary -Notes $n -MaxLength 45
            $s | Should -Match '\.$'
            $s.Length | Should -BeLessOrEqual 45
        }

        It 'marks a hard cut when there is no sentence end to use' {
            $s = Get-SentenceSummary -Notes ('x' * 400) -MaxLength 50
            $s.Length | Should -BeLessOrEqual 50
            $s | Should -BeLike "*$([char]0x2026)"
        }

        It 'answers empty for nothing' {
            Get-SentenceSummary -Notes ''    | Should -BeNullOrEmpty
            Get-SentenceSummary -Notes $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'tstyles update reports what really happened' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # Windows PowerShell 5.1 ships no PSResourceGet, so Update-PSResource
            # does not exist there -- and Pester cannot mock a command that is
            # absent, which failed this whole block with CommandNotFoundException
            # on that leg while passing on the other three.
            #
            # Skipping it there would leave the arm untested on the engine this
            # project is most often surprised by, and the arm IS reachable on
            # 5.1: PSResourceGet can be installed alongside, and
            # Get-TerminalStylesInstallKind would then choose it. So a stub is
            # defined in the module's own scope for Mock to attach to. It is
            # never invoked for real -- every It below mocks it, and the
            # install-kind check that reaches it is mocked too.
            if (-not (Get-Command Update-PSResource -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Update-PSResource {
                    param([string]$Name, [switch]$TrustRepository)
                }
            }
        }

        BeforeEach {
            Mock Get-TerminalStylesInstallKind { 'PSResourceGet' }
            Mock Update-PSResource { }
            # Longer than the 220-char default cap, or "trimmed" tests nothing --
            # and ending in a marker that can only appear if nothing was cut.
            Mock Get-InstalledReleaseNotes { 'v0.8.32: two WezTerm compositions restored, and a steadier picker. ' +
                ('More detail follows in a second sentence, and a third, and a fourth, each adding enough ' +
                 'length that the summary has to stop before reaching them. ') * 3 +
                'UNCUT-TAIL-MARKER.' }
        }

        It 'says nothing to do when the version did not move' {
            # The regression. This arm printed "Update complete" here.
            Mock Get-NewestInstalledVersion { '0.8.32' }
            $out = Invoke-TerminalStylesUpdate 6>&1 | Out-String
            $out | Should -Match 'Already the latest \(0\.8\.32\)'
            $out | Should -Not -Match 'Update complete' `
                -Because 'nothing was updated, so saying so is the defect this fixes'
        }

        It 'names both versions when it did move' {
            $script:calls = 0
            Mock Get-NewestInstalledVersion { $script:calls++; if ($script:calls -eq 1) { '0.8.30' } else { '0.8.32' } }
            $out = Invoke-TerminalStylesUpdate 6>&1 | Out-String
            $out | Should -Match 'Updated 0\.8\.30 -> 0\.8\.32'
            $out | Should -Match 'Import-Module TerminalStyles -Force' -Because 'the session still holds the old one'
        }

        It 'shows what is new, trimmed' {
            $script:calls = 0
            Mock Get-NewestInstalledVersion { $script:calls++; if ($script:calls -eq 1) { '0.8.30' } else { '0.8.32' } }
            $out = Invoke-TerminalStylesUpdate 6>&1 | Out-String
            $out | Should -Match 'two WezTerm compositions restored' `
                -Because 'the opening is the part worth showing'
            $out | Should -Not -Match 'UNCUT-TAIL-MARKER' `
                -Because 'the release note is a gallery listing, not terminal output'
        }

        It 'admits it when the version cannot be read' {
            Mock Get-NewestInstalledVersion { $null }
            $out = Invoke-TerminalStylesUpdate 6>&1 | Out-String
            $out | Should -Match 'cannot say'
            $out | Should -Not -Match 'Already the latest'
            $out | Should -Not -Match 'Updated .* ->'
        }

        It 'answers empty for a version that is not installed' {
            # Driven, not matched in the source: the real function is reached
            # here rather than the mock the other Its in this block install.
            InModuleScope TerminalStyles {
                Get-InstalledReleaseNotes -Version '99.99.99' | Should -BeNullOrEmpty
                { Get-InstalledReleaseNotes -Version 'nonsense' } | Should -Not -Throw
            }
        }
    }
}
