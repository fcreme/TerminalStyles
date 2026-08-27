# Pester 5 tests: a style's banner box must be a rectangle.
#
# Found by rendering every banner in a real shell and measuring the visible
# columns. Five of the nine boxed styles were out by 1-3 columns -- always the
# same line, the one with a colour code embedded mid-string, which is exactly
# where hand-counting padding goes wrong. The border closed short or long and
# the box looked broken, on the very first thing a user sees after applying a
# style.
#
# It was wrong in BOTH halves: styles/<name>/prompt.sh for zsh and bash, and
# styles/<name>/profile.ps1 for pwsh, with identical offsets, because the two
# are hand-maintained copies of the same art.
#
# Measured from the rendered output with the escape sequences stripped, not
# from the source: the source contains ${D}, ${W} and friends, and counting
# those is the mistake that produced the bug.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:BannerStyles = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
            Where-Object {
                $p = Join-Path $_.FullName 'prompt.sh'
                (Test-Path -LiteralPath $p) -and
                ((Get-Content -LiteralPath $p -Raw) -match '(?m)^\s*printf.*\+-{6,}')
            } | ForEach-Object { $_.Name })
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent

    # Strip OSC (ESC ] ... BEL) and CSI (ESC [ ... letter), then take the box
    # rows. What is left is what the terminal actually puts on screen.
    function script:Get-BoxWidths {
        param([Parameter(Mandatory)][string]$Text)
        $clean = [regex]::Replace($Text, "`e\][^`a]*`a", '')
        $clean = [regex]::Replace($clean, "`e\[[0-9;]*[A-Za-z]", '')
        @($clean -split "`r?`n" |
            Where-Object { $_ -match '^\s*[+|]' } |
            ForEach-Object { $_.TrimEnd().Length })
    }
}

Describe 'banner boxes are rectangular' {

    It '<_> renders a constant-width box in zsh' -ForEach $script:BannerStyles {
        $sh = Join-Path (Join-Path $script:repoRoot 'styles') $_
        $out = & zsh -f -c "source '$($script:repoRoot)/shell/tstyles.sh' 2>/dev/null; source '$sh/prompt.sh' 2>/dev/null" 2>$null | Out-String
        $widths = @(script:Get-BoxWidths -Text $out)
        @($widths).Count | Should -BeGreaterThan 2 -Because "$_ should have drawn a box"
        @($widths | Sort-Object -Unique).Count | Should -Be 1 `
            -Because "$_'s box rows measured $(($widths | Sort-Object -Unique) -join ', ') columns; a box is a rectangle"
    }

    It '<_> renders the same box in pwsh' -ForEach $script:BannerStyles {
        # The pwsh copy drifted identically, so checking only one half would
        # have left the other broken.
        $ps = Join-Path (Join-Path (Join-Path $script:repoRoot 'styles') $_) 'profile.ps1'
        $out = & pwsh-preview -NoProfile -Command "`$ErrorActionPreference='SilentlyContinue'; & { . '$ps' } 2>`$null" 2>$null | Out-String
        $widths = @(script:Get-BoxWidths -Text $out)
        if (@($widths).Count -le 2) {
            Set-ItResult -Skipped -Because "$_'s profile.ps1 drew no box here"
            return
        }
        @($widths | Sort-Object -Unique).Count | Should -Be 1 `
            -Because "$_'s pwsh box rows measured $(($widths | Sort-Object -Unique) -join ', ') columns"
    }

    It '<_> draws the same width on both halves' -ForEach $script:BannerStyles {
        # zsh and pwsh render hand-maintained copies of one piece of art. If they
        # disagree, one of them has been edited and the other forgotten.
        $dir = Join-Path (Join-Path $script:repoRoot 'styles') $_
        $shOut = & zsh -f -c "source '$($script:repoRoot)/shell/tstyles.sh' 2>/dev/null; source '$dir/prompt.sh' 2>/dev/null" 2>$null | Out-String
        $psOut = & pwsh-preview -NoProfile -Command "`$ErrorActionPreference='SilentlyContinue'; & { . '$dir/profile.ps1' } 2>`$null" 2>$null | Out-String
        $shW = @(script:Get-BoxWidths -Text $shOut | Sort-Object -Unique)
        $psW = @(script:Get-BoxWidths -Text $psOut | Sort-Object -Unique)
        if (@($psW).Count -eq 0) { Set-ItResult -Skipped -Because 'no pwsh box'; return }
        $psW[0] | Should -Be $shW[0] -Because "$_'s two halves must draw the same box"
    }
}
