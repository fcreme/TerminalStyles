# Pester 5 tests for Test-MonospaceFont. Glyph-width measurement depends on the
# real font subsystem, so the positive/negative cases skip when the reference
# font isn't installed; the non-existent-font case is hermetic (try/catch path).
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

Describe 'Test-MonospaceFont' {
    InModuleScope TerminalStyles {
        It 'detects a known monospace font (Consolas) as monospace' {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $installed = @()
            try { $installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name } catch {}
            if ('Consolas' -notin $installed) { Set-ItResult -Skipped -Because 'Consolas not installed'; return }
            Test-MonospaceFont -FamilyName 'Consolas' | Should -BeTrue
        }
        It 'detects a known proportional font (Arial) as not monospace' {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $installed = @()
            try { $installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name } catch {}
            if ('Arial' -notin $installed) { Set-ItResult -Skipped -Because 'Arial not installed'; return }
            Test-MonospaceFont -FamilyName 'Arial' | Should -BeFalse
        }
        It 'returns $false for a non-existent font family without throwing' {
            Test-MonospaceFont -FamilyName 'No Such Font ZZZ 123' | Should -BeFalse
        }
    }
}
