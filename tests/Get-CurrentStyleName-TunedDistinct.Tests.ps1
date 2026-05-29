# Pester 5 tests: Get-CurrentStyleName correctly distinguishes a Save-As'd
# Run: Invoke-Pester -Path tests
# tuned style from its base after Save-TunedStyle appends a per-style marker.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-CurrentStyleName - tuned style distinctness' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Redirect data root so user styles land under $TestDrive\styles\
            $script:TStylesDataRoot   = $TestDrive
            # Point module root at an empty dir so no bundled styles interfere.
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module-root'
            New-Item -ItemType Directory -Path $script:TStylesModuleRoot -Force | Out-Null
            # current-style.ps1 lives at $DataRoot\current-style.ps1
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            # Create base style 'eva' under the user styles dir.
            $script:evaDir = Join-Path $TestDrive 'styles\eva'
            New-Item -ItemType Directory -Path $script:evaDir -Force | Out-Null
            $scheme = [pscustomobject]@{ name = 'eva'; background = '#1a1a2e'; foreground = '#c7c7c7' }
            [System.IO.File]::WriteAllText(
                (Join-Path $script:evaDir 'scheme.json'),
                ($scheme | ConvertTo-Json -Depth 8),
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText(
                (Join-Path $script:evaDir 'profile.ps1'),
                'function prompt { "eva> " }',
                [System.Text.UTF8Encoding]::new($false))

            # Also create a minimal theme.json so Save-TunedStyle can copy it.
            $baseTheme = '{"colorScheme":"eva","opacity":100,"font":{"face":"Cascadia Code","size":11,"weight":"normal"}}'
            [System.IO.File]::WriteAllText(
                (Join-Path $script:evaDir 'theme.json'),
                $baseTheme,
                [System.Text.UTF8Encoding]::new($false))

            # Save-TunedStyle produces $TestDrive\styles\eva-night\.
            $adjusted = [pscustomobject]@{ name = 'eva'; background = '#0d0d1a'; foreground = '#b0b0b0' }
            Save-TunedStyle -AdjustedScheme $adjusted -SaveName 'eva-night' `
                -BaseStyleDir $script:evaDir -BaseName 'eva' `
                -Brightness -15 -Saturation 5 -Opacity 90 -FontFace 'Cascadia Code' -FontSize 11

            $script:evaNightDir = Join-Path $TestDrive 'styles\eva-night'
        }

        It 'returns eva-night when current-style.ps1 matches eva-night profile (not eva)' {
            # Set current-style.ps1 to the EXACT bytes Save-TunedStyle wrote for eva-night.
            $evaNightProfile = [System.IO.File]::ReadAllText(
                (Join-Path $script:evaNightDir 'profile.ps1'),
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText(
                $script:TStylesCurrent,
                $evaNightProfile,
                [System.Text.UTF8Encoding]::new($false))

            Get-CurrentStyleName | Should -Be 'eva-night'
        }

        It 'returns eva when current-style.ps1 matches the base eva profile' {
            $evaProfile = [System.IO.File]::ReadAllText(
                (Join-Path $script:evaDir 'profile.ps1'),
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText(
                $script:TStylesCurrent,
                $evaProfile,
                [System.Text.UTF8Encoding]::new($false))

            Get-CurrentStyleName | Should -Be 'eva'
        }
    }
}
