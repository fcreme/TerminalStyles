# Pester 5 tests: every settings.json writer puts back a preview a closed picker
# or tuner left before it reads the file or rolls its .bak; the WezTerm apply and
# reset drop a picker's record before they write the module.
#
# A closed tab left the picker's preview in settings.json with nothing on disk
# naming it, and the next `tstyles <name>` rolled settings.json.bak over the
# user's only copy with that preview. `tstyles reset` then stripped the
# preview's style off a profile the user had styled by hand.
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

Describe 'a settings.json writer after a closed picker' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:saved = @{ M = $script:TStylesModuleRoot; D = $script:TStylesDataRoot; C = $script:TStylesCurrent }
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            [void][System.IO.Directory]::CreateDirectory($sand)
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:TStylesCurrent  = Join-Path $script:TStylesDataRoot 'current-style.ps1'
            $enc = [System.Text.UTF8Encoding]::new($false)
            $probe = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'probe'
            [void][System.IO.Directory]::CreateDirectory($probe)
            [System.IO.File]::WriteAllText((Join-Path $probe 'scheme.json'), '{"name":"probe","background":"#101010","foreground":"#f0f0f0"}', $enc)
            [System.IO.File]::WriteAllText((Join-Path $probe 'theme.json'), '{"colorScheme":"probe","opacity":85}', $enc)

            $script:p = Join-Path $sand 'settings.json'
            $script:pre = @('{', '  // mine', '  "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "Campbell" } ] }', '}') -join "`n"
            [System.IO.File]::WriteAllText($script:p, $script:pre, $enc)

            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Find-WTSettingsPath { $script:p }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName { 'PowerShell' }
            Mock Get-StyleBundledBackground { $null }
            Mock Test-InteractiveConsole { $false }
            Mock Write-Host {}

            # A picker that previewed 'probe' and was closed: no Esc, no finally.
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            $json = Get-StylePreviewJson -OriginalJson $s.OriginalText -StyleDir $probe -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            Write-FilePreview -Session $s -Text $json | Should -Be 'written'
            $script:record = (Get-FilePreviewRecordPath -Kind WindowsTerminal -Path $script:p).Record
            [System.IO.File]::Exists("$script:p.bak") | Should -BeFalse -Because 'control: no .bak before the call'
        }
        AfterEach {
            $script:TStylesModuleRoot = $script:saved.M; $script:TStylesDataRoot = $script:saved.D; $script:TStylesCurrent = $script:saved.C
        }

        It 'an apply backs up the file the picker found, not its preview' {
            Apply-StyleDirect -StyleName 'probe' -Target 'PowerShell'
            [System.IO.File]::ReadAllText("$script:p.bak") | Should -BeExactly $script:pre
            [System.IO.File]::Exists($script:record) | Should -BeFalse
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { ([string]$Object).Contains('was put back first') }
        }

        It 'tstyles reset leaves a profile it never styled alone' {
            Reset-StyleDirect -Target 'PowerShell'
            [System.IO.File]::ReadAllText($script:p) | Should -BeExactly $script:pre
            Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains('carries no TerminalStyles style') }
            [System.IO.File]::Exists("$script:p.bak") | Should -BeFalse
        }

        It 'tstyles font backs up the file the picker found' {
            Mock Test-FontInstalled { $true }
            Mock Get-FontCatalog { @([pscustomobject]@{ name = 'Probe Mono'; family = 'Probe Mono'; nerd = $false }) }
            Invoke-TerminalStyleFont -Name 'Probe Mono' -Target 'PowerShell'
            [System.IO.File]::ReadAllText("$script:p.bak") | Should -BeExactly $script:pre
            (((ConvertFrom-JsoncText ([System.IO.File]::ReadAllText($script:p))).profiles.list | Where-Object name -eq 'PowerShell').font.face) |
                Should -Be 'Probe Mono'
            [System.IO.File]::Exists($script:record) | Should -BeFalse
        }
    }
}

Describe 'the WezTerm apply and reset own the module from the moment they write it' {
    # A preview can be byte-identical to an explicit apply (most bundled styles
    # share a font and padding), so the write may change nothing -- and a record
    # that survived it would let the next picker's recovery, or a live picker's
    # Esc, put the old module back over the apply.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:home2 = Join-Path $sand 'h'
            $script:module = Get-WezTermModulePath -HomeDir $script:home2
            Mock Get-WezTermModulePath { $script:module }
            Mock Get-StyleBundledBackground { $null }
            Mock Write-Host {}
            $script:read = {
                param($Name)
                $d = Get-StyleDir -StyleName $Name
                @{ Dir = $d
                   Scheme = ([System.IO.File]::ReadAllText((Join-Path $d 'scheme.json')) | ConvertFrom-Json)
                   Theme = ([System.IO.File]::ReadAllText((Join-Path $d 'theme.json')) | ConvertFrom-Json) }
            }
            $sober = & $script:read 'sober'
            Write-WezTermModuleText -Path $script:module -Text (Get-WezTermStyleLua -StyleName 'sober' -Scheme $sober.Scheme -Theme $sober.Theme -BackgroundImage $null) | Should -Be 'written'
            # A picker previews tombraider, under its own layout so the preview
            # is byte-identical to the apply below.
            $tr = & $script:read 'tombraider'
            $script:session = New-FilePreviewSession -Kind WezTerm -Path $script:module -By picker
            Write-FilePreview -Session $script:session -Text (Get-WezTermStyleLua -StyleName 'tombraider' -Scheme $tr.Scheme -Theme $tr.Theme -BackgroundImage $null) |
                Should -Be 'written'
            $script:tr = $tr
            $script:record = (Get-FilePreviewRecordPath -Kind WezTerm -Path $script:module).Record
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'an apply drops the record, so a later recovery does not undo it' {
            Publish-StyleWezTermConfig -StyleName 'tombraider' -StyleDir $script:tr.Dir -Scheme $script:tr.Scheme -Theme $script:tr.Theme -Kind 'WezTerm' | Out-Null
            $applied = [System.IO.File]::ReadAllText($script:module)
            [System.IO.File]::Exists($script:record) | Should -BeFalse
            (Restore-AbandonedFilePreview -Kind WezTerm -Path $script:module).Status | Should -Be 'none'
            [System.IO.File]::ReadAllText($script:module) | Should -BeExactly $applied
        }

        It "an apply in another tab is left by the open picker's Esc" {
            Publish-StyleWezTermConfig -StyleName 'tombraider' -StyleDir $script:tr.Dir -Scheme $script:tr.Scheme -Theme $script:tr.Theme -Kind 'WezTerm' | Out-Null
            $applied = [System.IO.File]::ReadAllText($script:module)
            (Restore-FilePreview -Session $script:session -End).Status | Should -Be 'left'
            [System.IO.File]::ReadAllText($script:module) | Should -BeExactly $applied
        }

        It 'a reset drops the record too' {
            Mock Get-TerminalKind { 'WezTerm' }
            Reset-StyleNonWT -Kind 'WezTerm' | Out-Null
            [System.IO.File]::Exists($script:record) | Should -BeFalse
        }
    }
}
