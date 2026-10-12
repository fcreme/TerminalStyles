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
            # The same for Update-Module, the fallback where PSResourceGet is
            # absent. PowerShellGet ships it on every engine CI runs, but a
            # missing command would fail the whole block, as above.
            if (-not (Get-Command Update-Module -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Update-Module {
                    param([string]$Name, [switch]$Force)
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

        It 'updates with Update-Module where PSResourceGet is not installed' {
            # Windows PowerShell 5.1 ships PowerShellGet but not PSResourceGet,
            # and the Gallery's own page leads with Install-Module. A copy
            # installed that way could only fail here -- "The term
            # 'Update-PSResource' is not recognized" -- and the update notice
            # now sends every Gallery install to this command.
            Mock Update-Module { }
            $script:calls = 0
            Mock Get-NewestInstalledVersion { $script:calls++; if ($script:calls -eq 1) { '0.8.30' } else { '0.8.32' } }

            $out = Invoke-TerminalStylesUpdate -HasPSResourceGet:$false 6>&1 | Out-String

            Should -Invoke Update-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'TerminalStyles' }
            Should -Invoke Update-PSResource -Times 0
            $out | Should -Match 'Updated 0\.8\.30 -> 0\.8\.32'
        }

        It 'answers PSGallery''s trust prompt, so a declined install cannot pass for "Already the latest"' {
            # Update-Module has no -TrustRepository, and PSGallery is untrusted
            # unless the user said otherwise, so it asks -- and its default is
            # No. A No is reported as a warning with nothing installed:
            # -ErrorAction Stop does not fire, the version does not move, and
            # this arm would print "Already the latest" over an update that
            # never happened. -Force is the answer -TrustRepository gives
            # Update-PSResource.
            Mock Update-Module { }
            Mock Get-NewestInstalledVersion { '0.8.30' }

            Invoke-TerminalStylesUpdate -HasPSResourceGet:$false 6>&1 | Out-Null

            Should -Invoke Update-Module -Times 1 -Exactly -ParameterFilter { $Force }
        }

        It 'names the command it used when that fails' {
            Mock Update-Module { throw 'simulated failure' }
            Mock Get-NewestInstalledVersion { '0.8.30' }

            $out = Invoke-TerminalStylesUpdate -HasPSResourceGet:$false 6>&1 | Out-String

            $out | Should -Match 'Update failed'
            $out | Should -Match 'Update-Module -Name TerminalStyles -Force'
            $out | Should -Not -Match 'Update-PSResource' `
                -Because 'the retry hint has to name a command this engine has'
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

Describe 'tstyles update on Windows PowerShell 5.1' {
    # The update check allows TLS 1.2 for its own request, so on a session
    # whose default leaves it out the notice now appears -- and sends the user
    # here, where every request needs TLS 1.2 just as much: the Gallery behind
    # Update-PSResource or Update-Module, and api.github.com and
    # raw.githubusercontent.com behind a bootstrap re-install.
    InModuleScope TerminalStyles {
        BeforeAll {
            if (-not (Get-Command Update-PSResource -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Update-PSResource {
                    param([string]$Name, [switch]$TrustRepository)
                }
            }
        }
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            Mock Write-Host { }
            $script:prevTls = [Net.ServicePointManager]::SecurityProtocol
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
        }
        AfterEach {
            [Net.ServicePointManager]::SecurityProtocol = $script:prevTls
        }

        It 'allows TLS 1.2 while a Gallery copy updates, and puts the setting back after' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
            Mock Get-TerminalStylesInstallKind { 'PSResourceGet' }
            Mock Get-NewestInstalledVersion { '0.8.32' }
            $seen = @{}
            Mock Update-PSResource { $seen.Protocol = [Net.ServicePointManager]::SecurityProtocol }

            Invoke-TerminalStylesUpdate

            Should -Invoke Update-PSResource -Times 1 -Exactly
            ($seen.Protocol -band [Net.SecurityProtocolType]::Tls12) | Should -Be ([Net.SecurityProtocolType]::Tls12)
            [Net.ServicePointManager]::SecurityProtocol | Should -Be ([Net.SecurityProtocolType]::Tls) `
                -Because 'the command leaves the session''s setting as it found it'
        }

        It 'allows TLS 1.2 while a bootstrap copy re-installs, and puts the setting back after' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            [System.IO.File]::WriteAllText((Join-Path $TestDrive '.installed-sha'), ('1' * 40), [System.Text.UTF8Encoding]::new($false))
            $seen = @{}
            Mock Invoke-RestMethod { $seen.Rest = [Net.ServicePointManager]::SecurityProtocol; [pscustomobject]@{ sha = ('2' * 40) } }
            Mock Invoke-WebRequest { $seen.Web = [Net.ServicePointManager]::SecurityProtocol; [pscustomobject]@{ Content = '$null' } }
            # Never the real installer, whatever becomes of the mock above.
            Mock Invoke-Expression { }

            Invoke-TerminalStylesUpdate

            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            ($seen.Rest -band [Net.SecurityProtocolType]::Tls12) | Should -Be ([Net.SecurityProtocolType]::Tls12) `
                -Because 'the up-to-date check asks api.github.com'
            ($seen.Web -band [Net.SecurityProtocolType]::Tls12) | Should -Be ([Net.SecurityProtocolType]::Tls12) `
                -Because 'the installer comes from raw.githubusercontent.com'
            [Net.ServicePointManager]::SecurityProtocol | Should -Be ([Net.SecurityProtocolType]::Tls)
        }
    }
}
