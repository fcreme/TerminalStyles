# Pester 5 tests for Write-CreatorPreview: the creator's live preview goes
# through the same recorded preview session as the picker and the tuner, so
# Esc and a closed tab both put settings.json back byte for byte.
#
# Every fixture lives in $TestDrive: the settings.json written here, the image
# path, the scratch directory, and the data root (which holds the preview
# record and the copy of the original).
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

Describe 'Write-CreatorPreview' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:p = Join-Path $sand 'settings.json'
            $script:original = @(
                '{'
                '  // mine'
                '  "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "Campbell", "font": { "face": "Consolas", "size": 11 } } ] },'
                '  "schemes": [ { "name": "Campbell", "background": "#0C0C0C" } ]'
                '}'
            ) -join "`n"
            [System.IO.File]::WriteAllText($script:p, $script:original, $script:enc)
            $script:originalBytes = [System.IO.File]::ReadAllBytes($script:p)

            $script:img = Join-Path $sand 'picture.png'
            [System.IO.File]::WriteAllBytes($script:img, [byte[]](1, 2, 3))
            $script:scratch = Join-Path $sand 'scratch'
            [void][System.IO.Directory]::CreateDirectory($script:scratch)

            $px = [int[]]@(foreach ($c in 0x0a0a2a, 0xff7a1a, 0x3060d0, 0xe0e0f0) { for ($i = 0; $i -lt 30; $i++) { $c } })
            $script:state = New-CreatorState -Pixels $px -ImagePath $script:img
            $script:session = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By creator -TargetName 'PowerShell'
            $script:write = {
                Write-CreatorPreview -State $script:state -Session $script:session -ScratchDir $script:scratch `
                    -Target 'PowerShell' -OriginalJson $script:session.OriginalText
            }
            $script:profileNow = {
                $o = [System.IO.File]::ReadAllText($script:p) | ConvertFrom-Json
                @($o.profiles.list | Where-Object { $_.name -eq 'PowerShell' })[0]
            }
            $script:bytesNow = { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:p)) }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'one write puts the image, its opacity and the font on the target profile' {
            & $script:write | Should -BeExactly 'written'
            $ps = & $script:profileNow
            $ps.backgroundImage | Should -BeExactly $script:img
            $ps.backgroundImageOpacity | Should -Be 0.35
            $ps.font.face | Should -BeExactly 'Cascadia Code'
        }

        It 'writes scheme.json and theme.json into the scratch dir, under one name' {
            [void](& $script:write)
            $scheme = [System.IO.File]::ReadAllText((Join-Path $script:scratch 'scheme.json')) | ConvertFrom-Json
            $theme = [System.IO.File]::ReadAllText((Join-Path $script:scratch 'theme.json')) | ConvertFrom-Json
            $theme.colorScheme | Should -BeExactly $scheme.name
            $scheme.red | Should -BeExactly $script:state.Scheme.red
            $ps = & $script:profileNow
            $ps.colorScheme | Should -BeExactly $scheme.name
        }

        It 'a later write carries the state as it is now' {
            [void](& $script:write)
            $script:state.ImageOpacity = 0.6
            $script:state.FontFace = 'Menlo'
            & $script:write | Should -BeExactly 'written'
            $ps = & $script:profileNow
            $ps.backgroundImageOpacity | Should -Be 0.6
            $ps.font.face | Should -BeExactly 'Menlo'
        }

        It 'Esc puts settings.json back byte-identical' {
            [void](& $script:write)
            (& $script:bytesNow) | Should -Not -BeExactly ([Convert]::ToBase64String($script:originalBytes))
            [void](Restore-FilePreview -Session $script:session -End)
            (& $script:bytesNow) | Should -BeExactly ([Convert]::ToBase64String($script:originalBytes))
        }

        It 'a closed tab is put back by the next command, as a creator preview' {
            [void](& $script:write)
            $script:session = $null
            $r = Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $script:p
            $r.Status | Should -BeExactly 'restored'
            $r.By | Should -BeExactly 'creator'
            (& $script:bytesNow) | Should -BeExactly ([Convert]::ToBase64String($script:originalBytes))
        }
    }
}

Describe 'Show-FilePreviewResult for the creator' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host {} }

        It 'names the creator, not the picker, for <label>' -ForEach @(
            @{ label = 'a recovered settings.json'; r = @{ Event = 'recover'; Status = 'restored'; Kind = 'WindowsTerminal'; By = 'creator' }; text = 'a tstyles creator that was closed' }
            @{ label = 'a kept copy';               r = @{ Event = 'recover'; Status = 'kept'; Kind = 'WindowsTerminal'; By = 'creator'; Backup = '/x/s.preview-1' }; text = 'as that creator found it' }
            @{ label = 'a merge on Esc';            r = @{ Event = 'restore'; Status = 'merged'; Kind = 'WindowsTerminal'; By = 'creator' }; text = 'while the creator was open' }
            @{ label = 'a file left on Esc';        r = @{ Event = 'restore'; Status = 'left'; Kind = 'WindowsTerminal'; By = 'creator' }; text = 'while the creator was open' }
            @{ label = 'a failed restore';          r = @{ Event = 'restore'; Status = 'failed'; Kind = 'WindowsTerminal'; By = 'creator'; Path = '/x'; Reason = 'locked'; Arm = 'restore' }; text = 'the file the creator found' }
            @{ label = 'a merge on Enter';          r = @{ Event = 'commit'; Status = 'merged'; Kind = 'WindowsTerminal'; By = 'creator'; Style = 'mine' }; text = 'while the creator was open' }
        ) {
            Show-FilePreviewResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { ([string]$Object).Contains($text) }
            Should -Invoke Write-Host -Times 0 -Scope It -ParameterFilter { ([string]$Object).Contains('picker') }
        }
    }
}

Describe 'Show-SettingsRestoreFailure for the creator' {
    InModuleScope TerminalStyles {
        It 'says the creator found the file, not the picker' {
            $out = Show-SettingsRestoreFailure -Reason 'Could not write /x/settings.json: denied' `
                -SettingsPath '/x/settings.json' -By creator 6>&1 | Out-String -Width 500
            $out.Contains('not back as the creator found it') | Should -BeTrue -Because $out
            $out.Contains('picker') | Should -BeFalse
        }
    }
}
