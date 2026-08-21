# Pester 5 tests for the platform-aware font enumeration.
#
# The Windows path goes through GDI+ (System.Drawing). Off Windows that library
# is unavailable -- System.Drawing.Common is Windows-only from .NET 6 on, and
# constructing an InstalledFontCollection throws a PInvokeGdiPlus type-initializer
# error. The old code caught that and returned an empty list, so every font
# silently read as "not installed". These pin the replacement.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-FontComparisonKey' {
    InModuleScope TerminalStyles {
        It 'reduces a display name and a filename stem to the same key' {
            # This equivalence is what lets a directory scan recognize a family
            # without parsing the font's internal name table.
            (Get-FontComparisonKey -Name 'JetBrains Mono') |
                Should -Be (Get-FontComparisonKey -Name 'JetBrainsMono')
        }
        It 'is case-insensitive' {
            (Get-FontComparisonKey -Name 'FIRA CODE') | Should -Be (Get-FontComparisonKey -Name 'Fira Code')
        }
        It 'drops punctuation' {
            (Get-FontComparisonKey -Name 'IBM Plex-Mono') | Should -Be 'ibmplexmono'
        }
        It 'returns empty for a name with no alphanumerics' {
            (Get-FontComparisonKey -Name '  --  ') | Should -Be ''
        }
    }
}

Describe 'Get-InstalledFontFamily (directory scan)' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fontDir = Join-Path $TestDrive 'Fonts'
            New-Item -ItemType Directory -Force -Path $script:fontDir | Out-Null
            foreach ($n in @('JetBrainsMono-Regular.ttf', 'FiraCode-Bold.otf',
                             'Menlo.ttc', 'Arial.ttf', 'notes.txt')) {
                [System.IO.File]::WriteAllText((Join-Path $script:fontDir $n), 'x')
            }
        }

        It 'recovers family names from font filenames' {
            $f = Get-InstalledFontFamily -Platform 'MacOS' -SearchPath @($script:fontDir)
            $f | Should -Contain 'JetBrains Mono'
            $f | Should -Contain 'Fira Code'
            $f | Should -Contain 'Menlo'
        }

        It 'ignores non-font files' {
            $f = Get-InstalledFontFamily -Platform 'MacOS' -SearchPath @($script:fontDir)
            $f | Should -Not -Contain 'notes'
        }

        It 'strips the style suffix so weights collapse into one family' {
            # JetBrainsMono-Regular.ttf and JetBrainsMono-Bold.ttf are one family.
            [System.IO.File]::WriteAllText((Join-Path $script:fontDir 'JetBrainsMono-Bold.ttf'), 'x')
            $f = @(Get-InstalledFontFamily -Platform 'MacOS' -SearchPath @($script:fontDir))
            @($f | Where-Object { $_ -eq 'JetBrains Mono' }).Count | Should -Be 1
        }

        It 'returns an empty list for a directory that does not exist' {
            Get-InstalledFontFamily -Platform 'MacOS' -SearchPath @((Join-Path $TestDrive 'nope')) |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-FontInstalled against a scanned list' {
    InModuleScope TerminalStyles {
        It 'matches a family whose filename differs only by spacing' {
            # The regression this guards: exact string comparison against a
            # filename-derived name reported every font as missing off Windows.
            Test-FontInstalled -Family 'JetBrains Mono' -Installed @('JetBrainsMono') | Should -BeTrue
        }
        It 'still matches an exact display name' {
            Test-FontInstalled -Family 'Fira Code' -Installed @('Fira Code') | Should -BeTrue
        }
        It 'does not match a different family' {
            Test-FontInstalled -Family 'Fira Code' -Installed @('Source Code Pro') | Should -BeFalse
        }
        It 'does not match on an empty family name' {
            Test-FontInstalled -Family '  ' -Installed @('Fira Code') | Should -BeFalse
        }
    }
}

Describe 'Get-FontSearchPath' {
    InModuleScope TerminalStyles {
        It 'puts the user font dir first on macOS' {
            # User-installed fonts should win over system ones of the same name.
            $paths = @(Get-FontSearchPath -Platform 'MacOS' -HomeDir '/Users/x')
            $paths[0] | Should -Be (Join-Path (Join-Path '/Users/x' 'Library') 'Fonts')
        }
        It 'includes the macOS system font dirs' {
            $paths = @(Get-FontSearchPath -Platform 'MacOS' -HomeDir '/Users/x')
            $paths | Should -Contain '/System/Library/Fonts'
        }
    }
}

Describe 'Get-MonospaceFontList off Windows' {
    InModuleScope TerminalStyles {
        It 'offers the macOS system monospace families when they are installed' {
            $list = Get-MonospaceFontList -Installed @('Menlo','Monaco','Arial') -MonospaceNames @()
            if ((Get-TStylesPlatform) -eq 'MacOS') {
                $list | Should -Contain 'Menlo'
                $list | Should -Contain 'Monaco'
                # A proportional face must never be offered as a terminal font.
                $list | Should -Not -Contain 'Arial'
            }
        }
    }
}
