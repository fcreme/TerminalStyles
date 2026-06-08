# Legibility guard: every chromatic ANSI color in a bundled scheme.json must
# stay readable against that scheme's own background. Colored text below ~3:1
# reads as muddy syntax highlighting in the prompt. WCAG 1.4.11 puts the floor
# for non-body / accent color at 3:1, which is the right bar for terminal token
# colors (they are short identifiers, not paragraphs).
#
# Scope note: black / white (and their bright variants) are deliberately NOT
# checked -- they are the achromatic ends that blend into the background by
# design (e.g. gitbash is a light theme where white text is never used).
#
# Documented exceptions live in $allow below.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Bundled scheme color contrast' {
    BeforeDiscovery {
        $repoRoot  = Split-Path $PSScriptRoot -Parent
        $chromatic = 'red','green','yellow','blue','purple','cyan',
                     'brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan'

        # (theme/key) pairs intentionally allowed below the 3:1 floor.
        #   umbrella/red -- the theme's signature "blood red" (#b41e1e), used for
        #   the banner, prompt scaffolding and cursor. It sits at 2.99:1, within
        #   rounding of the floor; lifting it would shift the whole theme's
        #   identity for an imperceptible contrast gain.
        $allow = @{ 'umbrella/red' = $true }

        $cases = foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory) {
            $schemePath = Join-Path $dir.FullName 'scheme.json'
            if (-not (Test-Path -LiteralPath $schemePath)) { continue }
            $scheme = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
            foreach ($key in $chromatic) {
                if (-not $scheme.$key) { continue }
                if ($allow.ContainsKey("$($dir.Name)/$key")) { continue }
                @{ Theme = $dir.Name; Key = $key; Color = [string]$scheme.$key; Background = [string]$scheme.background }
            }
        }
    }

    It '<Theme>/<Key> (<Color>) is >=3:1 against <Background>' -ForEach $cases {
        function Get-RelativeLuminance([string]$hex) {
            $h = $hex.TrimStart('#')
            $chan = 0, 2, 4 | ForEach-Object {
                $v = [Convert]::ToInt32($h.Substring($_, 2), 16) / 255
                if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) }
            }
            0.2126 * $chan[0] + 0.7152 * $chan[1] + 0.0722 * $chan[2]
        }

        $lColor = Get-RelativeLuminance $Color
        $lBg    = Get-RelativeLuminance $Background
        $hi     = [math]::Max($lColor, $lBg)
        $lo     = [math]::Min($lColor, $lBg)
        $ratio  = ($hi + 0.05) / ($lo + 0.05)

        $ratio | Should -BeGreaterThan 3.0 -Because "$Theme/$Key ($Color) must stay readable on $Background"
    }
}
