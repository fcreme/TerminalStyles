# Pester 5 tests for Invoke-TerminalStyleCreate (`tstyles create`): its
# guards, its key loop, and its wiring into the dispatcher, help and
# completion.
#
# Everything the command writes is sandboxed: the data root (preview record,
# scratch dir, backup), settings.json and the image are under $TestDrive, and
# $script:TStylesCurrent follows the data root. The console is reached only
# through the creator's two seams, Get-CreatorConsoleRedirection and
# Read-CreatorConsoleKey, so the loop is driven by a scripted key list on every
# platform, CI's redirected streams included. The apply is mocked: these tests
# never apply a style.
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

Describe 'Invoke-TerminalStyleCreate' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedCreateData = $script:TStylesDataRoot
            $script:savedCreateCurrent = $script:TStylesCurrent
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            $script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:enc = [System.Text.UTF8Encoding]::new($false)

            $script:settings = Join-Path $sand 'settings.json'
            $script:original = @(
                '{'
                '  // mine'
                '  "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "Campbell", "font": { "face": "Consolas", "size": 11 } } ] },'
                '  "schemes": [ { "name": "Campbell", "background": "#0C0C0C" } ]'
                '}'
            ) -join "`n"
            [System.IO.File]::WriteAllText($script:settings, $script:original, $script:enc)
            $script:originalB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:settings))
            $script:bytesNow = { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:settings)) }

            $script:img = Join-Path $sand 'picture.png'
            [System.IO.File]::WriteAllBytes($script:img, [byte[]](1, 2, 3))

            # Everything the command says, in order, with a marker for each
            # screen clear, so a test can read one frame.
            $script:out = New-Object System.Collections.Generic.List[string]
            Mock Write-Host { $script:out.Add([string]$Object) }
            Mock Clear-Host { $script:out.Add('<<CLEAR>>') }
            Mock Write-HostOscPacket { $true }
            Mock Start-Sleep {}
            Mock Test-UpdateAvailable { $null }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Find-WTSettingsPath { $script:settings }
            Mock Get-CurrentWTProfileName { 'PowerShell' }
            Mock Get-CreatorConsoleRedirection { [pscustomobject]@{ Input = $false; Output = $false } }
            # The image reader: a fixed palette, so no test depends on decoding.
            Mock Read-ImagePixels {
                foreach ($c in 0x0a0a2a, 0xff7a1a, 0x3060d0, 0xe0e0f0) { for ($i = 0; $i -lt 30; $i++) { $c } }
            }

            # The key list. $null is "no key waiting", which is when the loop
            # draws and runs the debounced preview write. Running out is a
            # failure, never a silent Esc.
            # settings.json as each key was read, so a test can see what the
            # preview had written while the creator was still open.
            $script:keys = New-Object System.Collections.Generic.Queue[object]
            $script:bytesAtKey = New-Object System.Collections.Generic.List[string]
            Mock Read-CreatorConsoleKey {
                if ($script:keys.Count -eq 0) { throw 'the scripted key list ran out' }
                $k = $script:keys.Dequeue()
                if ($null -ne $k) { $script:bytesAtKey.Add((& $script:bytesNow)) }
                $k
            }
            $script:queue = { param([object[]]$Items) foreach ($k in $Items) { $script:keys.Enqueue($k) } }
            # Type the image path, read it, let the preview write, then Enter
            # through steps 1-3 to the name page.
            $script:toNamePage = {
                & $script:queue ([object[]]@($script:img.ToCharArray() | ForEach-Object { [string]$_ }))
                & $script:queue @('Enter', $null, 'Enter', 'Enter', 'Enter', 'Enter')
            }
            $script:typeName = { param([string]$n) & $script:queue ([object[]]@($n.ToCharArray() | ForEach-Object { [string]$_ })) }
            $script:said = { param([string]$Text) @($script:out | Where-Object { $_.Contains($Text) }).Count -gt 0 }
        }
        AfterEach {
            $script:TStylesDataRoot = $script:savedCreateData
            $script:TStylesCurrent = $script:savedCreateCurrent
        }

        Context 'guards' {
            It 'refuses outside Windows Terminal and touches nothing' {
                Mock Get-TerminalKind { 'iTerm2' }
                Mock Find-WTSettingsPath { throw 'must not look for settings.json off Windows Terminal' }
                Mock Write-FilePreview { 'written' }
                Invoke-TerminalStyleCreate
                (& $script:said 'tstyles create needs Windows Terminal for now') | Should -BeTrue
                (& $script:said 'tstyles tune') | Should -BeTrue -Because 'it names what does work there'
                Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
                Should -Invoke Write-FilePreview -Times 0 -Exactly
                Should -Invoke Clear-Host -Times 0 -Exactly
                Should -Invoke Read-CreatorConsoleKey -Times 0 -Exactly
                @(Get-ChildItem -LiteralPath $script:TStylesDataRoot -Force).Count | Should -Be 0
                (& $script:bytesNow) | Should -Be $script:originalB64
            }

            It 'names no terminal it does not know' {
                Mock Get-TerminalKind { 'SomeNewTerm' }
                Mock Find-WTSettingsPath { throw 'must not look for settings.json off Windows Terminal' }
                Invoke-TerminalStyleCreate
                (& $script:said 'tstyles create needs Windows Terminal for now') | Should -BeTrue
                (& $script:said 'this terminal.') | Should -BeFalse
                (& $script:said 'This terminal is') | Should -BeFalse
                # An unknown kind does get OscPalette (Get-TerminalCapability's
                # lowest common denominator), so the tuner is offered there; the
                # test below covers a kind without it.
                (Get-TerminalCapability -Kind 'SomeNewTerm').OscPalette | Should -BeTrue
                (& $script:said 'tstyles tune') | Should -BeTrue
                (& $script:said 'tstyles list') | Should -BeTrue
                Should -Invoke Find-WTSettingsPath -Times 0 -Exactly
            }

            It 'promises live colours only where the terminal takes an OSC palette' {
                Mock Get-TerminalKind { 'Kitty' }
                Mock Get-TerminalCapability { $c = @{}; foreach ($n in $script:TStylesCapabilityNames) { $c[$n] = $false }; $c }
                Invoke-TerminalStyleCreate
                (& $script:said 'This terminal is kitty.') | Should -BeTrue
                (& $script:said 'live') | Should -BeFalse
                (& $script:said 'tstyles tune') | Should -BeFalse
                (& $script:said 'tstyles list') | Should -BeTrue
            }

            It 'refuses when input is redirected, before touching the terminal or settings.json' {
                Mock Get-CreatorConsoleRedirection { [pscustomobject]@{ Input = $true; Output = $false } }
                Mock Write-FilePreview { 'written' }
                Invoke-TerminalStyleCreate
                (& $script:said 'needs an interactive terminal') | Should -BeTrue
                Should -Invoke Write-FilePreview -Times 0 -Exactly
                Should -Invoke Clear-Host -Times 0 -Exactly
                Should -Invoke Read-CreatorConsoleKey -Times 0 -Exactly
                Should -Invoke Test-UpdateAvailable -Times 0 -Exactly -Because 'a run that cannot start pays neither the check nor its throttle'
                @(Get-ChildItem -LiteralPath $script:TStylesDataRoot -Force).Count | Should -Be 0
            }

            It 'refuses when output is redirected' {
                Mock Get-CreatorConsoleRedirection { [pscustomobject]@{ Input = $false; Output = $true } }
                Mock Write-FilePreview { 'written' }
                Invoke-TerminalStyleCreate
                (& $script:said 'needs a terminal to repaint') | Should -BeTrue
                Should -Invoke Write-FilePreview -Times 0 -Exactly
                Should -Invoke Clear-Host -Times 0 -Exactly
            }
        }

        Context 'the key loop' {
            It 'saves, applies from the settings.json it found, and says so' {
                Mock Save-CreatedStyle { [pscustomobject]@{ Status = 'saved'; Path = (Join-Path $script:TStylesDataRoot 'styles\probe'); Reason = $null } }
                $script:atApply = $null
                Mock Apply-StyleDirect { $script:atApply = & $script:bytesNow }
                & $script:toNamePage
                & $script:typeName 'probe'
                & $script:queue @('Enter')
                Invoke-TerminalStyleCreate

                $script:bytesAtKey[$script:bytesAtKey.Count - 1] | Should -Not -Be $script:originalB64 `
                    -Because 'the debounced write ran on the idle after the image was read'
                Should -Invoke Save-CreatedStyle -Times 1 -Exactly -ParameterFilter {
                    $Name -eq 'probe' -and $BackgroundPath -eq $script:img -and $Theme.colorScheme -eq 'probe' -and
                    $Prompt.Profile -and $Prompt.Shell
                }
                Should -Invoke Apply-StyleDirect -Times 1 -Exactly -ParameterFilter { $StyleName -eq 'probe' -and $Target -eq 'PowerShell' }
                $script:atApply | Should -Be $script:originalB64 -Because 'the preview comes out before the apply, so no placeholder scheme is left behind'
                (& $script:said "Created 'probe' and applied it.") | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.create-preview') -PathType Container |
                    Should -BeTrue -Because 'the root is only removed of its own session'
                @(Get-ChildItem -LiteralPath (Join-Path $script:TStylesDataRoot '.create-preview') -Force).Count | Should -Be 0
            }

            It 'keeps the user on the name page when the name is taken, and claims nothing' {
                Mock Apply-StyleDirect {}
                Mock Save-CreatedStyle { $script:out.Add('<<SAVE>>'); [pscustomobject]@{ Status = 'taken'; Path = $null; Reason = "A style named 'probe' already exists." } }
                & $script:toNamePage
                & $script:typeName 'probe'
                & $script:queue @('Enter', $null, 'Escape')
                Invoke-TerminalStyleCreate

                Should -Invoke Save-CreatedStyle -Times 1 -Exactly
                Should -Invoke Apply-StyleDirect -Times 0 -Exactly
                (& $script:said 'and applied it') | Should -BeFalse
                # The frame drawn after the refusal: still step 5, with the reason.
                $at = $script:out.IndexOf('<<SAVE>>')
                $at | Should -BeGreaterThan -1
                $next = $script:out.IndexOf('<<CLEAR>>', $at)
                $next | Should -BeGreaterThan $at
                $end = $script:out.IndexOf('<<CLEAR>>', $next + 1)
                if ($end -lt 0) { $end = $script:out.Count }
                $frame = @($script:out.GetRange($next, $end - $next))
                # Every Write-Host is one entry, so a page handed to Write-Host
                # as one array shows here as one long entry (pwsh 7 joins it
                # with spaces) or as "System.String[]" (5.1 wraps it in its
                # remaining-arguments list). Each page line must be its own.
                $seen = "the frame was:`n" + ($frame -join "`n")
                @($frame | Where-Object { $_ -clike '  tstyles create   Step 5 of 5: *' }).Count | Should -Be 1 -Because $seen
                @($frame | Where-Object { $_ -ceq 'On branch main' }).Count | Should -Be 1 -Because $seen
                @($frame | Where-Object { $_.Contains("A style named 'probe' already exists.") }).Count | Should -Be 1 -Because $seen
                # The session stayed live, so the Esc after it still put the file back.
                (& $script:bytesNow) | Should -Be $script:originalB64
                (& $script:said 'Cancelled. Your terminal is back as it was.') | Should -BeTrue
            }

            It 'does not claim the style was applied when the apply fails' {
                Mock Save-CreatedStyle { [pscustomobject]@{ Status = 'saved'; Path = (Join-Path $script:TStylesDataRoot 'styles\probe'); Reason = $null } }
                Mock Apply-StyleDirect { Write-Error 'apply went wrong' }
                & $script:toNamePage
                & $script:typeName 'probe'
                & $script:queue @('Enter')
                Invoke-TerminalStyleCreate -ErrorAction SilentlyContinue

                (& $script:said 'and applied it') | Should -BeFalse
                (& $script:said "Created 'probe', but it could not be applied") | Should -BeTrue
                (& $script:bytesNow) | Should -Be $script:originalB64
            }

            It 'Esc puts settings.json back byte for byte and removes its scratch session' {
                Mock Apply-StyleDirect {}
                Mock Save-CreatedStyle {}
                & $script:queue ([object[]]@($script:img.ToCharArray() | ForEach-Object { [string]$_ }))
                & $script:queue @('Enter', $null, 'Escape')
                Invoke-TerminalStyleCreate

                $script:bytesAtKey[$script:bytesAtKey.Count - 1] | Should -Not -Be $script:originalB64 `
                    -Because 'the preview must have been written for the Esc to have anything to put back'
                (& $script:bytesNow) | Should -Be $script:originalB64
                (& $script:said 'Cancelled. Your terminal is back as it was.') | Should -BeTrue
                Should -Invoke Save-CreatedStyle -Times 0 -Exactly
                Should -Invoke Apply-StyleDirect -Times 0 -Exactly
                Test-Path -LiteralPath (Join-Path (Join-Path $script:TStylesDataRoot '.create-preview') ("session-{0}" -f $PID)) |
                    Should -BeFalse
            }

            It 'says it is reading the image before the reader runs' {
                Mock Apply-StyleDirect {}
                Mock Save-CreatedStyle {}
                Mock Read-ImagePixels {
                    $script:out.Add('<<READ>>')
                    foreach ($c in 0x0a0a2a, 0xff7a1a, 0x3060d0, 0xe0e0f0) { for ($i = 0; $i -lt 30; $i++) { $c } }
                }
                & $script:queue ([object[]]@($script:img.ToCharArray() | ForEach-Object { [string]$_ }))
                # Enter on the image already read moves on: no second line.
                & $script:queue @('Enter', $null, 'Enter', 'Escape')
                Invoke-TerminalStyleCreate

                $read = $script:out.IndexOf('<<READ>>')
                $read | Should -BeGreaterThan -1
                $said = $script:out.IndexOf('  Reading picture.png...')
                $said | Should -BeGreaterThan -1 -Because ("what was said: " + ($script:out -join ' | '))
                $said | Should -BeLessThan $read
                @($script:out | Where-Object { $_ -ceq '  Reading picture.png...' }).Count | Should -Be 1
                Should -Invoke Read-ImagePixels -Times 1 -Exactly
            }

            It 'sweeps a scratch session a closed creator left, keeps another live one, and removes its own' {
                $root = Join-Path $script:TStylesDataRoot '.create-preview'
                # Another creator still open: a real process, alive for the
                # whole run, other than this one.
                $engine = (Get-Process -Id $PID).Path
                $other = Start-Process -FilePath $engine -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -PassThru
                try {
                    Get-Process -Id $other.Id -ErrorAction Stop | Should -Not -BeNullOrEmpty -Because 'the live session needs a live process'
                    # A PID no process holds, checked rather than assumed.
                    $dead = ((Get-Process | Measure-Object -Property Id -Maximum).Maximum + 7919)
                    while (Get-Process -Id $dead -ErrorAction SilentlyContinue) { $dead++ }
                    $stale = Join-Path $root ("session-{0}" -f $dead)
                    $live = Join-Path $root ("session-{0}" -f $other.Id)
                    $own = Join-Path $root ("session-{0}" -f $PID)
                    $notSession = Join-Path $root 'not-a-session'
                    foreach ($d in $stale, $live, $own, $notSession) {
                        [void][System.IO.Directory]::CreateDirectory((Join-Path $d 'style'))
                        [System.IO.File]::WriteAllText((Join-Path (Join-Path $d 'style') 'scheme.json'), '{}', $script:enc)
                    }
                    Mock Apply-StyleDirect {}
                    Mock Save-CreatedStyle {}
                    & $script:queue @('Escape')
                    Invoke-TerminalStyleCreate

                    Test-Path -LiteralPath $stale | Should -BeFalse -Because 'its process is gone'
                    Test-Path -LiteralPath (Join-Path (Join-Path $live 'style') 'scheme.json') |
                        Should -BeTrue -Because 'a creator open in another tab keeps its scratch session'
                    Test-Path -LiteralPath $notSession | Should -BeTrue -Because 'only session-<PID> folders are the creator''s'
                    Test-Path -LiteralPath $own | Should -BeFalse -Because 'its own session goes on the way out'
                } finally {
                    Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Context 'wiring' {
            It "lists 'create' among the subcommands" {
                $script:TStylesSubcommands | Should -Contain 'create'
            }
            It "routes 'tstyles create' to Invoke-TerminalStyleCreate" {
                Mock Invoke-TerminalStyleCreate {}
                Mock Show-UpdateNoticeIfAvailable {}
                Invoke-TerminalStyle -Arg 'create'
                Should -Invoke Invoke-TerminalStyleCreate -Times 1 -Exactly
            }
            It "refuses 'tstyles create' with arguments (<Tag>), naming its usage and touching nothing" -ForEach @(
                @{ Tag = 'a name'; Splat = @{ SubArg = 'mine' } },
                @{ Tag = '-Target'; Splat = @{ Target = 'PowerShell' } },
                @{ Tag = '-BackgroundImage'; Splat = @{ BackgroundImage = 'C:\pics\a.png' } },
                @{ Tag = '-KeepPrompt'; Splat = @{ KeepPrompt = $true } }) {
                Mock Invoke-TerminalStyleCreate {}
                Mock Show-UpdateNoticeIfAvailable {}
                Invoke-TerminalStyle -Arg 'create' @Splat
                Should -Invoke Invoke-TerminalStyleCreate -Times 0 -Exactly
                @($script:out | Where-Object { $_ -ceq '  tstyles create takes no arguments: run tstyles create, and choose the image, colours, prompt and name on its pages. Nothing was changed.' }).Count |
                    Should -Be 1 -Because ("what was said: " + ($script:out -join ' | '))
                @(Get-ChildItem -LiteralPath $script:TStylesDataRoot -Force).Count | Should -Be 0
                (& $script:bytesNow) | Should -Be $script:originalB64
            }

            It "prints a help topic for 'create'" {
                Invoke-TerminalStyle -Arg 'help' -SubArg 'create'
                (& $script:said 'No help topic') | Should -BeFalse
                (& $script:said 'tstyles create') | Should -BeTrue
                (& $script:said 'Windows Terminal') | Should -BeTrue
            }
            It "lists 'create' in the help overview" {
                Show-TerminalStyleHelp
                @($script:out | Where-Object { $_ -match '^\s+create\s{2,}' }).Count | Should -Be 1
            }
        }
    }
}

Describe 'tstyles create tab completion' {
    It "offers 'create' as a subcommand" {
        # The live module instance, not InModuleScope's: the completer belongs
        # to the instance BeforeAll imported (see TabCompletion-Quoting.Tests.ps1).
        $mod = Get-Module TerminalStyles
        $line = 'tstyles cre'
        $completions = & $mod { param($l) @((TabExpansion2 -inputScript $l -cursorColumn $l.Length).CompletionMatches) } $line
        @($completions | ForEach-Object { $_.CompletionText }) | Should -Contain 'create'
    }
}
