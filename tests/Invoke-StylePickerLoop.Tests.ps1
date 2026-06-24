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
                $keys = New-KeyStub @([ConsoleKey]::Enter)
                $r = Invoke-StylePickerLoop -StyleCount 3 -StartIndex 1 `
                    -ReadKey $keys `
                    -OnPreview { param($i) $applied.Add($i) } `
                    -OnRevert  { }
                $r.Outcome     | Should -Be 'confirmed'
                $r.Index       | Should -Be 1
                $applied.Count | Should -Be 0
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
    }
}
