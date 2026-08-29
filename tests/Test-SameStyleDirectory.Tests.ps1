# Pester 5 tests for Test-SameStyleDirectory -- "do these two paths name the
# same directory, as the HOST FILESYSTEM sees it?"
#
# The function's own docstring says it was carved out as a pure function so this
# decision could be tested directly. It never was: the only references anywhere
# in tests/ were source-text assertions that it is CALLED.
#
# It used to infer case sensitivity from the platform NAME -- Ordinal on Linux,
# OrdinalIgnoreCase everywhere else. Case sensitivity is a property of the
# VOLUME. On case-sensitive APFS (chosen at format time), a Windows directory
# flagged with `fsutil file setCaseSensitiveInfo`, or a case-sensitive network
# mount, styles/Retro and styles/retro are two real directories and the function
# answered $true -- so a Save-As differing from its base only in case skipped the
# prompt.sh copy and the new style shipped with no zsh/bash prompt, silently.
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

Describe 'Test-SameStyleDirectory' {
    InModuleScope TerminalStyles {

        Context 'answers that do not depend on the volume' {
            It 'is true for the same path' {
                Test-SameStyleDirectory -A $TestDrive -B $TestDrive | Should -BeTrue
            }
            It 'ignores a trailing separator' {
                $sep = [System.IO.Path]::DirectorySeparatorChar
                Test-SameStyleDirectory -A $TestDrive -B "$TestDrive$sep" | Should -BeTrue
            }
            It 'normalises a traversal that lands back on the same place' {
                $sub = Join-Path $TestDrive 'a'
                New-Item -ItemType Directory -Path $sub -Force | Out-Null
                Test-SameStyleDirectory -A $sub -B (Join-Path $sub '../a') | Should -BeTrue
            }
            It 'is false for genuinely different directories' {
                Test-SameStyleDirectory -A (Join-Path $TestDrive 'x') -B (Join-Path $TestDrive 'y') | Should -BeFalse
            }
            It 'is false for an empty path rather than throwing' {
                Test-SameStyleDirectory -A '' -B $TestDrive | Should -BeFalse
                Test-SameStyleDirectory -A $TestDrive -B '' | Should -BeFalse
            }
        }

        Context 'names differing only in case' {
            BeforeEach {
                $script:lower = Join-Path $TestDrive ('cs-' + [guid]::NewGuid().Guid.Substring(0, 8))
                $script:upper = Join-Path (Split-Path $script:lower -Parent) `
                                          ((Split-Path $script:lower -Leaf).ToUpperInvariant())
            }

            It 'asks the filesystem when the directory actually exists' {
                # The answer is whatever THIS volume does -- the point is that it
                # is measured, not assumed. On a case-insensitive volume (the
                # macOS/Windows default) both spellings reach one directory; on a
                # case-sensitive one they do not.
                New-Item -ItemType Directory -Path $script:lower -Force | Out-Null
                $insensitive = Test-Path -LiteralPath $script:upper

                Test-SameStyleDirectory -A $script:lower -B $script:upper |
                    Should -Be $insensitive -Because 'the volume is the authority, not the platform name'
            }

            It 'does not consult the platform when the volume can answer' {
                New-Item -ItemType Directory -Path $script:lower -Force | Out-Null
                $insensitive = Test-Path -LiteralPath $script:upper
                # Claim to be Linux. On a case-INSENSITIVE volume the old code
                # returned $false here; the probe must still say $true.
                Mock Get-TStylesPlatform { 'Linux' }

                Test-SameStyleDirectory -A $script:lower -B $script:upper | Should -Be $insensitive
            }

            It 'falls back to the platform default when neither spelling exists' {
                # Nothing to probe, so the historical guess is the best available.
                Mock Get-TStylesPlatform { 'Linux' }
                Test-SameStyleDirectory -A $script:lower -B $script:upper | Should -BeFalse

                Mock Get-TStylesPlatform { 'MacOS' }
                Test-SameStyleDirectory -A $script:lower -B $script:upper | Should -BeTrue
            }
        }
    }
}
