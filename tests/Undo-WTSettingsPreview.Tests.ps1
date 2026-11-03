# Pester 5 tests for Undo-WTSettingsPreview: taking a preview back out of a
# settings.json that changed after it was written, keeping every other change.
#
# Esc used to write the snapshot back whole, so anything Windows Terminal's
# Settings UI, Settings Sync or another command wrote while the picker or the
# tuner was open was thrown away. Pure: text in, text out.
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

Describe 'Undo-WTSettingsPreview' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = $sand
            $enc = [System.Text.UTF8Encoding]::new($false)
            $script:probe = Join-Path (Join-Path $sand 'styles') 'probe'
            [void][System.IO.Directory]::CreateDirectory($script:probe)
            [System.IO.File]::WriteAllText((Join-Path $script:probe 'scheme.json'), '{"name":"probe","background":"#101010","foreground":"#f0f0f0"}', $enc)
            [System.IO.File]::WriteAllText((Join-Path $script:probe 'theme.json'), '{"colorScheme":"probe","opacity":85,"font":{"face":"Menlo","size":12}}', $enc)
            Mock Get-StyleBundledBackground { $null }
            $script:O = '{"profiles":{"list":[{"guid":"{a}","name":"PowerShell","colorScheme":"Campbell","font":{"face":"Consolas","size":11}}]},"schemes":[{"name":"Campbell","background":"#0C0C0C"}]}'
            $script:P = Get-StylePreviewJson -OriginalJson $script:O -StyleDir $script:probe -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            $script:ps = { param($json) @(($json | ConvertFrom-Json).profiles.list | Where-Object { $_.name -eq 'PowerShell' })[0] }
            $script:withCurrent = {
                param([scriptblock]$Edit)
                $o = $script:P | ConvertFrom-Json
                & $Edit $o
                $o | ConvertTo-Json -Depth 100
            }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'leaves a value changed after the preview, and names it' {
            $c = & $script:withCurrent {
                param($o)
                @($o.profiles.list)[0].opacity = 55
                $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
            }
            $u = Undo-WTSettingsPreview -OriginalJson $script:O -PreviewJson $script:P -CurrentJson $c -TargetName 'PowerShell'
            (@($u.Kept) -join ',') | Should -BeExactly 'opacity'
            $e = & $script:ps $u.Text
            $e.opacity | Should -Be 55
            $e.colorScheme | Should -Be 'Campbell'
            $e.font.face | Should -Be 'Consolas'
            $u.Undone | Should -Contain 'colorScheme'
            $u.Undone | Should -Contain 'font'
            ($u.Text | ConvertFrom-Json).copyOnSelect | Should -BeTrue
        }

        It 'recognises the preview after Windows Terminal re-serialises the file' {
            $c = & $script:withCurrent {
                param($o)
                $e = @($o.profiles.list)[0]
                $names = @($e.PSObject.Properties | ForEach-Object { $_.Name }); [array]::Reverse($names)
                $rev = [ordered]@{}; foreach ($n in $names) { $rev[$n] = $e.$n }
                $o.profiles.list = @([pscustomobject]$rev)
                $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
            }
            # 5.1 writes `"size":  12` with two spaces; pwsh 7 one.
            $c = [regex]::Replace($c, '"size":\s+12', '"size": 12.0')
            $c | Should -Match '12\.0' -Because 'control: the re-serialised number must be in the text'
            ((& $script:ps $c).font | ConvertTo-Json -Compress) |
                Should -Not -BeExactly ((& $script:ps $script:P).font | ConvertTo-Json -Compress) -Because 'control: plain JSON differs'

            $u = Undo-WTSettingsPreview -OriginalJson $script:O -PreviewJson $script:P -CurrentJson $c -TargetName 'PowerShell'
            @($u.Kept).Count | Should -Be 0
            $u.Undone | Should -Contain 'font'
            $u.Undone | Should -Contain 'colorScheme'
            ConvertTo-CanonicalJson (& $script:ps $u.Text) | Should -BeExactly (ConvertTo-CanonicalJson (& $script:ps $script:O))
        }

        It "puts back the base scheme the tuner's scratch preview wrote over" {
            $O2 = '{"profiles":{"list":[{"guid":"{a}","name":"PowerShell","colorScheme":"eva"}]},"schemes":[{"name":"eva","background":"#000000"}]}'
            $scratch = Join-Path $script:TStylesDataRoot 'scratch/eva'
            [void][System.IO.Directory]::CreateDirectory($scratch)
            [System.IO.File]::WriteAllText((Join-Path $scratch 'scheme.json'), '{"name":"eva","background":"#222222"}')
            [System.IO.File]::WriteAllText((Join-Path $scratch 'theme.json'), '{"colorScheme":"eva","opacity":70}')
            $P2 = Get-StylePreviewJson -OriginalJson $O2 -StyleDir $scratch -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            $o = $P2 | ConvertFrom-Json; $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
            $u = Undo-WTSettingsPreview -OriginalJson $O2 -PreviewJson $P2 -CurrentJson ($o | ConvertTo-Json -Depth 100) -TargetName 'PowerShell'
            $t = $u.Text | ConvertFrom-Json
            ConvertTo-CanonicalJson @($t.schemes | Where-Object { $_.name -eq 'eva' })[0] |
                Should -BeExactly (ConvertTo-CanonicalJson @(($O2 | ConvertFrom-Json).schemes)[0])
            @((& $script:ps $u.Text).PSObject.Properties.Match('opacity')).Count | Should -Be 0
            $t.copyOnSelect | Should -BeTrue
            $u.Undone | Should -Contain 'schemes/eva'
        }

        It 'a value already back at the original is neither undone nor kept' {
            $o = $script:O | ConvertFrom-Json; $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
            $u = Undo-WTSettingsPreview -OriginalJson $script:O -PreviewJson $script:P -CurrentJson ($o | ConvertTo-Json -Depth 100) -TargetName 'PowerShell'
            @($u.Undone).Count | Should -Be 0
            @($u.Kept).Count | Should -Be 0
            ($u.Text | ConvertFrom-Json).copyOnSelect | Should -BeTrue
        }
    }
}
