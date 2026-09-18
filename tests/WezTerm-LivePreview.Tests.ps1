# WezTerm adds the files it `require`s to its config reload watch list, so
# rewriting the generated module restyles a RUNNING window. That makes it the one
# terminal off Windows where arrowing through the picker can preview the whole
# style -- background, font, padding, cursor shape, opacity -- and not just the
# palette the OSC retint carries.
#
# Two properties are load-bearing and neither is obvious from reading the picker:
# the preview runs on the input thread and must never reach the network, and Esc
# must put back exactly what was there INCLUDING nothing.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'the picker previews a style on WezTerm without touching the network' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Both halves of the sandbox: the data root for the cache the
            # resolver reads, and -HomeDir for the module path it writes.
            $script:TStylesDataRoot = $TestDrive
            $script:home = Join-Path $TestDrive ('h-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path (Join-Path $script:home '.config/wezterm') -Force | Out-Null
            $script:styleDir = Join-Path $TestDrive 'styles/probe'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
        }

        It 'answers from disk or answers nothing, but never fetches' {
            # The picker previews on every arrow key, and the fetching tier can
            # spend four serial attempts at -TimeoutSec 10 before it concludes
            # anything -- on the thread reading the keystrokes.
            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $script:styleDir -NoFetch | Should -BeNullOrEmpty
            $script:hits | Should -Be 0 -Because 'the preview path runs on the input thread'
        }

        It 'does not fetch through the inheritance hop either' {
            # A tuned style inherits its base's background, and that hop resolves
            # the base -- which would fetch on the thread we just protected.
            $kid = Join-Path $TestDrive 'styles/kid'
            New-Item -ItemType Directory -Path $kid -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'styles/base') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $kid 'tune.json'), '{"base":"base"}',
                [System.Text.UTF8Encoding]::new($false))

            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $kid -NoFetch | Should -BeNullOrEmpty
            $script:hits | Should -Be 0
        }

        It 'still fetches without the switch, or the switch proves nothing' {
            # The control. A -NoFetch test passes just as well against a function
            # that never fetched at all.
            $script:hits = 0
            Set-Item function:script:Invoke-WebRequest { $script:hits++; throw 'network reached' }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Out-Null
            $script:hits | Should -BeGreaterThan 0 -Because 'the default path is the one -NoFetch opts out of'
        }

        It 'writes a module a preview can restore from, and one it can remove' {
            $scheme = [pscustomobject]@{ background = '#101010'; foreground = '#f0f0f0' }
            $path = Get-WezTermModulePath -HomeDir $script:home

            # Case 1: nothing there before. Esc has to leave nothing there after,
            # or a first-ever picker run on a clean machine invents a file.
            [System.IO.File]::Exists($path) | Should -BeFalse
            Write-WezTermStyleModule -StyleName 'probe' -Scheme $scheme -Theme $null `
                -BackgroundImage $null -HomeDir $script:home | Should -Not -Be 'failed'
            [System.IO.File]::Exists($path) | Should -BeTrue
            Remove-Item -LiteralPath $path -Force
            [System.IO.File]::Exists($path) | Should -BeFalse

            # Case 2: something there before. Esc has to put those bytes back
            # exactly -- it is the user's active style, not ours to rewrite.
            $original = [System.Text.Encoding]::UTF8.GetBytes("-- the user's own`n")
            [System.IO.File]::WriteAllBytes($path, $original)
            Write-WezTermStyleModule -StyleName 'probe' -Scheme $scheme -Theme $null `
                -BackgroundImage $null -HomeDir $script:home | Out-Null
            ([System.IO.File]::ReadAllBytes($path) -join ',') | Should -Not -Be ($original -join ',') `
                -Because 'the preview has to actually change something, or there is nothing to restore'
            [System.IO.File]::WriteAllBytes($path, $original)
            ([System.IO.File]::ReadAllBytes($path) -join ',') | Should -Be ($original -join ',')
        }
    }
}

Describe 'the picker wires that preview in' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        }

        It 'previews on the branch that used to do nothing but retint' {
            # Structural because the picker body needs a console and a keypress
            # loop no test can drive -- the same reason Get-PickerViewport and
            # Get-PickerFramePlan were carved out as pure functions.
            $script:picker | Should -Match '& \$previewWezTerm \$i' `
                -Because 'the non-settings-file branch is where a WezTerm preview happens'
        }

        It 'restores on Esc, next to the settings.json restore it mirrors' {
            $script:picker | Should -Match '& \$restoreWezTerm' `
                -Because 'a rejected preview must not outlive the picker'
        }

        It 'asks for the background without fetching' {
            $script:picker | Should -Match 'Get-StyleBundledBackground -StyleDir \$sd -NoFetch' `
                -Because 'the preview runs on the input thread'
        }

        It 'gates the restore on having written, like the settings.json half' {
            # Restoring over a file the picker never touched is not free: it
            # bumps the mtime, and WezTerm is watching.
            $script:picker | Should -Match '\$pickerState\.WezWritten' `
                -Because 'a picker that wrote nothing must restore nothing'
        }
    }
}
