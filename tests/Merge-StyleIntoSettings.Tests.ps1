# Pester 5 tests for Merge-StyleIntoSettings, exercised end-to-end (NOT mocked).
# Covers the scheme+theme merge and the regression guard: a non-existent named
# -Target must NOT inject an orphan color scheme into settings.json (the scheme
# was previously appended before the target profile was resolved).
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

Describe 'Merge-StyleIntoSettings' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:styleDir = Join-Path $TestDrive 'styles\eva'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"eva","background":"#000000","foreground":"#ffffff"}',
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'theme.json'),
                '{"colorScheme":"eva","opacity":90}',
                [System.Text.UTF8Encoding]::new($false))
        }

        It 'applies the scheme + theme to a valid named target' {
            $s = [pscustomobject]@{ profiles = [pscustomobject]@{ list = @([pscustomobject]@{ name = 'PowerShell'; guid = '{x}' }) } }
            $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:styleDir `
                -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            @($out.schemes).Count | Should -Be 1
            $out.schemes[0].name  | Should -Be 'eva'
            $entry = $out.profiles.list | Where-Object name -eq 'PowerShell'
            $entry.colorScheme | Should -Be 'eva'
            $entry.opacity     | Should -Be 90
        }

        It 'does NOT inject an orphan scheme when the named target does not exist' {
            $s = [pscustomobject]@{ profiles = [pscustomobject]@{ list = @([pscustomobject]@{ name = 'PowerShell'; guid = '{x}' }) } }
            $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:styleDir `
                -TargetName 'DoesNotExist' -BackgroundImage '' -BackgroundImageProvided $false 2>$null
            # No 'eva' scheme should have been appended (Where-Object on a $null
            # schemes property yields nothing, so this is 0 whether schemes is
            # absent or merely lacks 'eva').
            @($out.schemes | Where-Object { $_.name -eq 'eva' }).Count | Should -Be 0
            # The real profile is untouched too.
            ($out.profiles.list | Where-Object name -eq 'PowerShell').PSObject.Properties.Match('colorScheme').Count | Should -Be 0
        }

        It 'creates and styles profiles.defaults for the defaults target' {
            $s = [pscustomobject]@{ profiles = [pscustomobject]@{ list = @([pscustomobject]@{ name = 'PowerShell'; guid = '{x}' }) } }
            $out = Merge-StyleIntoSettings -Settings $s -StyleDir $script:styleDir `
                -TargetName 'defaults' -BackgroundImage '' -BackgroundImageProvided $false
            @($out.schemes).Count              | Should -Be 1
            $out.profiles.defaults.colorScheme | Should -Be 'eva'
        }
    }
}
