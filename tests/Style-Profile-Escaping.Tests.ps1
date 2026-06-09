# Guard: PowerShell double-quoted strings escape a literal quote with a backtick
# (`") or by doubling (""), NEVER with a backslash (\"). A backslash-escaped quote
# in a bundled profile.ps1 banner/prompt renders the backslash literally and drops
# adjacent characters on BOTH pwsh 7 and Windows PowerShell 5.1 -- e.g.
#   "...${M}\"Through the glass, after hours.\"${W}..."
# renders as  \ Through the glass after hours.\  (mangled, mis-aligned).
# Regression lock for the EXT3-series banner taglines.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Bundled style profile.ps1 escaping' {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $profiles = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
            ForEach-Object { Join-Path $_.FullName 'profile.ps1' } |
            Where-Object { Test-Path -LiteralPath $_ }
    )

    It '<_> uses no backslash-escaped double-quotes' -ForEach $profiles {
        $content = [System.IO.File]::ReadAllText($_, [System.Text.UTF8Encoding]::new($false))
        ($content -match '\\"') |
            Should -BeFalse -Because 'profile.ps1 must escape quotes with a backtick, not a backslash'
    }
}
