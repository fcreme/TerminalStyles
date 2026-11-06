# Pester 5 tests: New-PaletteFromPixels builds a readable 21-key scheme from
# made-up pixel arrays (so these run on every platform), and
# Get-SchemeLowContrastSlots reports slots below their contrast bar.
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

Describe 'New-PaletteFromPixels' {
    InModuleScope TerminalStyles {
        BeforeAll {
            function Get-TestHue([string]$Hex) {
                $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16) / 255.0
                $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16) / 255.0
                $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16) / 255.0
                $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b))
                $d = $max - $min
                if ($d -eq 0) { return -1 }
                if ($max -eq $r) { $h = (($g - $b) / $d) % 6 }
                elseif ($max -eq $g) { $h = (($b - $r) / $d) + 2 }
                else { $h = (($r - $g) / $d) + 4 }
                $h *= 60; if ($h -lt 0) { $h += 360 }
                $h
            }
            function Get-HueDistance([double]$A, [double]$B) {
                $d = [Math]::Abs($A - $B) % 360
                if ($d -gt 180) { $d = 360 - $d }
                $d
            }
            function New-Sunset {
                $px = New-Object System.Collections.Generic.List[int]
                $mix = @(0xff7a1a, 0xe8501c, 0xc2306a, 0x8a2f9c, 0x5a2a8a, 0x1a1a4a, 0x0a0a2a, 0xffb347)
                for ($i = 0; $i -lt 3000; $i++) {
                    $m = $mix[$i % 8]
                    $j = ($i * 7) % 13
                    $r = [Math]::Min(255, (($m -shr 16) -band 255) + $j)
                    $g = [Math]::Min(255, (($m -shr 8) -band 255) + $j)
                    $b = [Math]::Min(255, ($m -band 255) + $j)
                    $px.Add(($r -shl 16) -bor ($g -shl 8) -bor $b)
                }
                , $px.ToArray()
            }
            $script:Inputs = @{
                sunset = (New-Sunset)
                grey   = [int[]]@(1..2000 | ForEach-Object { 0x808080 })
                green  = [int[]]@(1..2000 | ForEach-Object { 0x00ff00 })
                dark   = [int[]]@((1..1800 | ForEach-Object { 0x0a0a14 }) + (1..200 | ForEach-Object { 0xe0d0a0 }))
            }
            $script:Roles = [ordered]@{ red = 0; yellow = 60; green = 120; cyan = 180; blue = 240; purple = 300 }
            $script:Keys = 'name background foreground cursorColor selectionBackground black red green yellow blue purple cyan white brightBlack brightRed brightGreen brightYellow brightBlue brightPurple brightCyan brightWhite'.Split(' ')
        }

        It 'builds a valid, readable, hue-correct scheme for <_>' -ForEach @('sunset', 'grey', 'green', 'dark') {
            $s = New-PaletteFromPixels -Pixels $script:Inputs[$_] -Name 'pal-test'
            $s.name | Should -BeExactly 'pal-test'
            @($s.PSObject.Properties.Name).Count | Should -Be 21
            foreach ($k in $script:Keys) {
                if ($k -eq 'name') { continue }
                $s.$k | Should -MatchExactly '^#[0-9a-f]{6}$' -Because $k
            }
            (Get-ContrastRatio $s.foreground $s.background) | Should -BeGreaterOrEqual 7
            @(Get-SchemeUnreadableSlots -Scheme $s).Count | Should -Be 0
            @(Get-SchemeLowContrastSlots -Scheme $s).Count | Should -Be 0
            foreach ($role in $script:Roles.Keys) {
                $bright = 'bright' + $role.Substring(0, 1).ToUpper() + $role.Substring(1)
                (Get-HueDistance (Get-TestHue $s.$role) $script:Roles[$role]) | Should -BeLessOrEqual 30 -Because $role
                (Get-HueDistance (Get-TestHue $s.$bright) $script:Roles[$role]) | Should -BeLessOrEqual 30 -Because $bright
                (Get-RelativeLuminance $s.$bright) | Should -BeGreaterOrEqual (Get-RelativeLuminance $s.$role) -Because $bright
            }
        }

        It 'is deterministic for <_>' -ForEach @('sunset', 'grey') {
            $a = New-PaletteFromPixels -Pixels $script:Inputs[$_] -Name 'x' | ConvertTo-Json
            $b = New-PaletteFromPixels -Pixels $script:Inputs[$_] -Name 'x' | ConvertTo-Json
            $a | Should -BeExactly $b
        }

        It 'takes the background from the darkest cluster of a mostly dark image' {
            $s = New-PaletteFromPixels -Pixels $script:Inputs['dark'] -Name 'x'
            (Get-RelativeLuminance $s.background) | Should -BeLessThan 0.05
            $s.cursorColor | Should -BeExactly $s.foreground
        }

        It 'stays dark for a light image' {
            $s = New-PaletteFromPixels -Pixels ([int[]]@(1..500 | ForEach-Object { 0xf0f0f0 })) -Name 'x'
            (Get-RelativeLuminance $s.background) | Should -BeLessThan 0.05
        }

        It 'finishes ~9000 pixels quickly' {
            $px = [int[]]@(1..9216 | ForEach-Object { (($_ * 2654435761) -band 0xffffff) })
            (Measure-Command { New-PaletteFromPixels -Pixels $px -Name 'x' | Out-Null }).TotalSeconds | Should -BeLessThan 2
        }

        It 'Get-PaletteAccent returns a hex colour from the scheme' {
            $s = New-PaletteFromPixels -Pixels $script:Inputs['sunset'] -Name 'x'
            Get-PaletteAccent -Scheme $s | Should -MatchExactly '^#[0-9a-f]{6}$'
        }
    }
}

Describe 'Get-SchemeLowContrastSlots' {
    InModuleScope TerminalStyles {
        BeforeAll {
            function New-GoodScheme {
                [pscustomobject]@{
                    background = '#000000'; foreground = '#ffffff'; black = '#000000'
                    red = '#ff6666'; green = '#66ff66'; yellow = '#ffff66'; blue = '#8888ff'; purple = '#ff66ff'; cyan = '#66ffff'; white = '#dddddd'
                    brightBlack = '#808080'; brightRed = '#ff8888'; brightGreen = '#88ff88'; brightYellow = '#ffff88'
                    brightBlue = '#aaaaff'; brightPurple = '#ff88ff'; brightCyan = '#88ffff'; brightWhite = '#ffffff'
                }
            }
        }
        It 'reports nothing for a passing scheme' {
            @(Get-SchemeLowContrastSlots -Scheme (New-GoodScheme)).Count | Should -Be 0
        }
        It 'reports red when it equals the background' {
            $s = New-GoodScheme; $s.red = $s.background
            @(Get-SchemeLowContrastSlots -Scheme $s) | Should -Contain 'red'
        }
        It 'never reports black' {
            $s = New-GoodScheme; $s.black = $s.background
            @(Get-SchemeLowContrastSlots -Scheme $s) | Should -Not -Contain 'black'
        }
        It 'holds foreground to 7 and brightBlack to 3' {
            $s = New-GoodScheme; $s.foreground = '#777777'; $s.brightBlack = '#222222'
            $r = @(Get-SchemeLowContrastSlots -Scheme $s)
            $r | Should -Contain 'foreground'
            $r | Should -Contain 'brightBlack'
        }
    }
}
