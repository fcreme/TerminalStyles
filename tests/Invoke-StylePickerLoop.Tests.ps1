# Pester 5 tests for Invoke-StylePickerLoop -- the seam-injected picker engine.
# Unit tests drive the loop with scripted keys + recording seams (no real I/O);
# integration tests (Task 2) wire the real settings writers.
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

Describe 'Invoke-StylePickerLoop' {
    InModuleScope TerminalStyles {

        BeforeAll {
            # Build a ReadKey stub from an array. Yields one element per call in
            # order; an element of $null models a momentarily-empty queue (drives
            # the debounce tail). After the array is consumed, returns Escape on
            # every further call so the loop can never hang.
            function New-KeyStub {
                param([object[]]$Keys)
                $state = @{ i = 0 }
                return {
                    if ($state.i -lt $Keys.Count) {
                        $k = $Keys[$state.i]; $state.i++
                        if ($null -eq $k) { return $null }
                        return [pscustomobject]@{ Key = $k }
                    }
                    return [pscustomobject]@{ Key = [ConsoleKey]::Escape }
                }.GetNewClosure()
            }
        }

        Context 'engine unit behavior' {

            It 'Up clamps at index 0 and applies nothing' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $keys = New-KeyStub @([ConsoleKey]::UpArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 0
                $applied.Count | Should -Be 0
            }

            It 'Down clamps at the last index' {
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 2 `
                    -ReadKey $keys -OnPreview { param($i) } -OnRevert { }
                $r.Index | Should -Be 2
                $r.Outcome | Should -Be 'confirmed'
            }

            It 'collapses a key-mash to a single apply at the final index' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow,
                                      [ConsoleKey]::DownArrow, $null, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 5 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 3
                $applied.Count | Should -Be 1
                $applied[0]    | Should -Be 3
            }

            It 'confirms at the start index with no apply when Enter is pressed first' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $reverts = @{ n = 0 }
                $keys = New-KeyStub @([ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 1 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { $reverts.n++ }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 1
                $applied.Count | Should -Be 0
                $reverts.n | Should -Be 0
            }

            It 'Esc cancels: reverts once and applies nothing' {
                $applied = [System.Collections.Generic.List[int]]::new()
                $reverts = @{ n = 0 }
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Escape)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 0 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { $reverts.n++ }
                $r.Outcome     | Should -Be 'cancelled'
                $reverts.n     | Should -Be 1
                $applied.Count | Should -Be 0
            }
        }

        Context 'integration with real settings I/O' {

            BeforeEach {
                # Sandbox the data root. This Context drives the REAL settings
                # I/O, and resolving a style's background derives its cache
                # directory from $script:TStylesDataRoot -- which is the live
                # install unless it is overridden here. Without this the suite
                # wrote cache/beta/.no-background into the developer's own
                # ~/Library/Application Support/TerminalStyles on every run.
                # Same seam-leak shape as the $ZDOTDIR escape: the test
                # sandboxes the files it can see and one resolver reaches past
                # TestDrive into the real environment.
                $script:savedDataRoot = $script:TStylesDataRoot
                $script:TStylesDataRoot = $TestDrive

                # Two fake styles so DownArrow can move 0 -> 1.
                $script:dirA = Join-Path $TestDrive 'styles\alpha'
                $script:dirB = Join-Path $TestDrive 'styles\beta'
                foreach ($d in @($script:dirA, $script:dirB)) {
                    New-Item -ItemType Directory -Path $d -Force | Out-Null
                }
                $enc = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText((Join-Path $script:dirA 'scheme.json'),
                    '{"name":"alpha","background":"#000000","foreground":"#ffffff"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirA 'theme.json'),
                    '{"colorScheme":"alpha"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirB 'scheme.json'),
                    '{"name":"beta","background":"#111111","foreground":"#eeeeee"}', $enc)
                [System.IO.File]::WriteAllText((Join-Path $script:dirB 'theme.json'),
                    '{"colorScheme":"beta"}', $enc)
                $script:styleDirs = @($script:dirA, $script:dirB)

                # Non-ASCII target profile name to lock the UTF-8/no-BOM round-trip.
                $script:target = 'Símbolo del sistema'
                $script:settingsPath = Join-Path $TestDrive 'settings.json'
                # Baseline has no 'schemes' key -- Merge-StyleIntoSettings must create it.
                $original = '{"profiles":{"list":[{"name":"Símbolo del sistema","guid":"{abc}"}]}}'
                [System.IO.File]::WriteAllText($script:settingsPath, $original, $enc)
                # Read back exactly as the picker does (UTF-8, no BOM).
                $script:originalJson = [System.IO.File]::ReadAllText(
                    $script:settingsPath, [System.Text.UTF8Encoding]::new($false))

                # Real seams: a deferred merge+write preview, and a byte-exact revert.
                $script:onPreview = {
                    param($i)
                    $merged = ConvertFrom-WTJson $script:originalJson
                    $merged = Merge-StyleIntoSettings -Settings $merged -StyleDir $script:styleDirs[$i] `
                        -TargetName $script:target -BackgroundImage '' -BackgroundImageProvided $false
                    Write-SettingsAtomic -Path $script:settingsPath -Json ($merged | ConvertTo-Json -Depth 100)
                }
                $script:onRevert = {
                    Write-SettingsAtomic -Path $script:settingsPath -Json $script:originalJson
                }
            }

            AfterEach { $script:TStylesDataRoot = $script:savedDataRoot }

            It 'restores the byte-exact original settings.json on Esc (after a preview)' {
                $originalBytes = [System.IO.File]::ReadAllBytes($script:settingsPath)
                # Down -> (idle drains the preview, reformatting the file) -> Esc.
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, $null, [ConsoleKey]::Escape)
                $r = Invoke-StylePickerLoop -StyleCount 2 -StartIndex 0 `
                    -ReadKey $keys -OnPreview $script:onPreview -OnRevert $script:onRevert
                $r.Outcome | Should -Be 'cancelled'
                $afterBytes = [System.IO.File]::ReadAllBytes($script:settingsPath)
                # Byte-for-byte identical to the pre-picker state.
                (@(Compare-Object $originalBytes $afterBytes -SyncWindow 0).Count) | Should -Be 0
            }

            It 'persists the chosen style on Enter' {
                # Down -> Enter (Enter drains the pending preview for index 1 = beta).
                $keys = New-KeyStub @([ConsoleKey]::DownArrow, [ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 2 -StartIndex 0 `
                    -ReadKey $keys -OnPreview $script:onPreview -OnRevert $script:onRevert
                $r.Outcome | Should -Be 'confirmed'
                $r.Index   | Should -Be 1
                $written = [System.IO.File]::ReadAllText(
                    $script:settingsPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                ($written.profiles.list | Where-Object name -eq $script:target).colorScheme | Should -Be 'beta'
                @($written.schemes | Where-Object { $_.name -eq 'beta' }).Count | Should -Be 1
            }
        }
    }
}
