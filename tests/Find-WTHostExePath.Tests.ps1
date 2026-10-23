# Pester 5 tests: Find-WTHostExePath walks up from the session's process to the
# WindowsTerminal.exe it runs under, and stops wherever the answer stops being
# trustworthy.
#
# The walker runs over fake process records. Get-ProcessRecord -- its only
# reader of the process table -- is mocked, so no test here reads a real
# process tree, the loop that ships is the loop under test, and its lookups can
# be counted. The counts are what pin the cycle stop and the depth stop: both
# end in $null either way, but a walk that only stopped at the depth cap would
# make 32 lookups to get there.
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

Describe 'Find-WTHostExePath' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # One process as Get-ProcessRecord returns it. Start times are UTC,
            # as the reader normalises them.
            $script:proc = {
                param([int]$ParentId, [string]$Name, $Path, [int]$Hour, [int]$Minute)
                [pscustomobject]@{
                    ParentId = $ParentId
                    Name     = $Name
                    Path     = $Path
                    Started  = [datetime]::new(2026, 10, 21, $Hour, $Minute, 0, [System.DateTimeKind]::Utc)
                }
            }
            $script:wtExe   = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminalPreview_1.23.2702.0_x64__8wekyb3d8bbwe\WindowsTerminal.exe'
            $script:pwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
            $script:bashExe = 'C:\Program Files\Git\usr\bin\bash.exe'

            # A shell started straight from a tab, under a WT started from Explorer.
            $script:tabTable = {
                @{
                    100 = & $script:proc 50 'pwsh.exe' $script:pwshExe 9 5
                    50  = & $script:proc 7 'WindowsTerminal.exe' $script:wtExe 9 0
                    7   = & $script:proc 1 'explorer.exe' 'C:\Windows\explorer.exe' 8 0
                }
            }
        }

        BeforeEach {
            $script:procs = @{}
            Mock Get-ProcessRecord { $script:procs[$Id] }
        }

        It 'returns the WindowsTerminal.exe the shell is a child of' {
            $script:procs = & $script:tabTable
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -Be $script:wtExe
            Should -Invoke Get-ProcessRecord -Times 2 -Exactly
        }

        It 'climbs through shells started inside the tab' {
            # The bash levels stand for Git Bash's launcher and its fork stubs;
            # each is older than its child.
            $script:procs = @{
                100 = & $script:proc 90 'pwsh.exe' $script:pwshExe 9 9
                90  = & $script:proc 80 'bash.exe' $script:bashExe 9 8
                80  = & $script:proc 70 'bash.exe' $script:bashExe 9 7
                70  = & $script:proc 50 'bash.exe' $script:bashExe 9 6
                50  = & $script:proc 7 'WindowsTerminal.exe' $script:wtExe 9 0
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -Be $script:wtExe
            Should -Invoke Get-ProcessRecord -Times 5 -Exactly
        }

        It 'stops at a parent created after its child (a reused ID)' {
            # The shell's real parent exited and Windows handed its ID to a
            # Windows Terminal started later. Without the start-time check this
            # walk returns that terminal's path.
            $script:procs = @{
                100 = & $script:proc 50 'pwsh.exe' $script:pwshExe 9 5
                50  = & $script:proc 7 'WindowsTerminal.exe' $script:wtExe 10 0
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -BeNullOrEmpty
        }

        It 'returns nothing when no Windows Terminal is above the shell' {
            $script:procs = @{
                100 = & $script:proc 90 'pwsh.exe' $script:pwshExe 9 5
                90  = & $script:proc 4 'Code.exe' 'C:\Program Files\Microsoft VS Code\Code.exe' 9 0
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -BeNullOrEmpty
            Should -Invoke Get-ProcessRecord -Times 2 -Exactly -Because 'PID 4, the System process, is never looked up'
        }

        It 'stops on a cycle at the first ID it has already seen' {
            $script:procs = @{
                100 = & $script:proc 90 'pwsh.exe' $script:pwshExe 9 0
                90  = & $script:proc 100 'bash.exe' $script:bashExe 9 0
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -BeNullOrEmpty
            Should -Invoke Get-ProcessRecord -Times 2 -Exactly
        }

        It 'gives up after 32 levels' {
            # 40 distinct processes, each the child of the next and younger than
            # it, with no terminal at the top.
            $script:procs = @{}
            for ($i = 0; $i -lt 40; $i++) {
                $rec = & $script:proc (1001 + $i) 'bash.exe' $script:bashExe 12 0
                $rec.Started = $rec.Started.AddMinutes(-$i)
                $script:procs[1000 + $i] = $rec
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 1000 | Should -BeNullOrEmpty
            Should -Invoke Get-ProcessRecord -Times 32 -Exactly
        }

        It "returns nothing when the host's path cannot be read" {
            $script:procs = @{
                100 = & $script:proc 50 'pwsh.exe' $script:pwshExe 9 5
                50  = & $script:proc 7 'WindowsTerminal.exe' $null 9 0
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -BeNullOrEmpty
        }

        It 'returns nothing when a parent cannot be looked up' {
            # As for a parent that has exited: the reader returns $null.
            $script:procs = @{
                100 = & $script:proc 90 'pwsh.exe' $script:pwshExe 9 5
            }
            Find-WTHostExePath -Platform 'Windows' -StartId 100 | Should -BeNullOrEmpty
            Should -Invoke Get-ProcessRecord -Times 2 -Exactly
        }

        It 'off Windows it looks nothing up' {
            # The same table that returns the path above, so this measures the
            # guard rather than the table.
            $script:procs = & $script:tabTable
            Find-WTHostExePath -Platform 'Linux' -StartId 100 | Should -BeNullOrEmpty
            Should -Invoke Get-ProcessRecord -Times 0 -Exactly
        }

        It 'with no -Platform it asks Get-TStylesPlatform' {
            # Not $IsWindows, which is $null on Windows PowerShell 5.1. Mocked to
            # Windows, the walk runs on the macOS and Linux legs too.
            Mock Get-TStylesPlatform { 'Windows' }
            $script:procs = & $script:tabTable
            Find-WTHostExePath -StartId 100 | Should -Be $script:wtExe
            Should -Invoke Get-TStylesPlatform -Times 1 -Exactly
        }
    }
}
