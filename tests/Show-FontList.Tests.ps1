#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Show-FontList' {
    InModuleScope TerminalStyles {
        It 'marks installed fonts with [+] and installable with [ ]' {
            $cat = @(
                [pscustomobject]@{ name='JetBrains Mono'; family='JetBrains Mono'; license='OFL-1.1' },
                [pscustomobject]@{ name='Fira Code';     family='Fira Code';     license='OFL-1.1' }
            )
            $out = Show-FontList -Catalog $cat -Installed @('JetBrains Mono') 6>&1 | Out-String
            $out | Should -Match '\[\+\]\s+JetBrains Mono'
            $out | Should -Match '\[ \]\s+Fira Code'
        }

        It 'enumerates the installed fonts ONCE, not once per catalogue entry' {
            # Test-FontInstalled enumerates for itself when -Installed is
            # absent, and this function used to call it bare in the loop. Off
            # Windows that enumeration is a recursive walk of every font
            # directory on the machine; on Windows it is a new
            # InstalledFontCollection. Either way the cost was multiplied by
            # the size of the catalogue, so adding a font slowed the listing
            # down for everyone.
            #
            # Asserted on the call count rather than a stopwatch: the timing is
            # what makes it worth fixing, but a duration threshold in a test is
            # a flake waiting for a loaded CI runner.
            Mock Get-InstalledFontFamily { @('JetBrains Mono') }

            $cat = @(
                [pscustomobject]@{ name='JetBrains Mono';  family='JetBrains Mono';  license='OFL-1.1' },
                [pscustomobject]@{ name='Fira Code';       family='Fira Code';       license='OFL-1.1' },
                [pscustomobject]@{ name='Hack';            family='Hack';            license='MIT' },
                [pscustomobject]@{ name='Source Code Pro'; family='Source Code Pro'; license='OFL-1.1' }
            )
            $out = Show-FontList -Catalog $cat 6>&1 | Out-String

            Should -Invoke Get-InstalledFontFamily -Times 1 -Exactly `
                -Because 'one pass answers the whole list'
            # And it still answers correctly off the single pass.
            $out | Should -Match '\[\+\]\s+JetBrains Mono'
            $out | Should -Match '\[ \]\s+Hack'
        }
    }
}
