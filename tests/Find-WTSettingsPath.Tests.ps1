# Pester 5 tests: Find-WTSettingsPath returns the settings.json of the Windows
# Terminal build hosting the session -- or $null, after saying why, once.
#
# The test this file replaces checked $env:WT_SETTINGS_PATH, a variable no
# Windows Terminal has ever set, by setting it itself. So it passed while every
# Preview and Canary tab had Stable's settings.json rewritten: the fixed
# Stable-first list decided every time, and nothing on screen said so but the
# path after "Backed up settings to:".
#
# These tests drive the real decision on every leg: -HostExePath stands in for
# the process walk, and -EnvTable for $env:. The paths are built with nested
# two-argument Join-Path from this file's own literals, so the case-sensitive
# Linux leg catches a casing drift between the module and the layout Windows
# Terminal uses.
#
# Each test builds its fixture in a folder of its own: Pester clears TestDrive
# only when a block ends, so a file one test creates is still there for the
# next.
#
# The REAL LOCALAPPDATA points at a decoy holding only Stable's settings.json,
# and the real WT_SETTINGS_PATH, WT_SETTINGS_DIR and TSTYLES_WT_SETTINGS are
# cleared, for each test and put back after it. A finder that ignored both
# parameters -- the one this replaces had no param block, so they landed in
# $args -- therefore fails with exactly the reported path, Stable's, and never
# reads a developer's real file.
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

Describe 'Find-WTSettingsPath' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedEnv = @{}
            foreach ($n in 'LOCALAPPDATA', 'WT_SETTINGS_PATH', 'WT_SETTINGS_DIR', 'TSTYLES_WT_SETTINGS') {
                $script:savedEnv[$n] = [System.Environment]::GetEnvironmentVariable($n)
            }

            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))

            # Writes a BOM-less '{}', creating the folder first.
            $script:new = {
                param([string]$Path)
                $dir = Split-Path -Parent $Path
                if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
                [System.IO.File]::WriteAllText($Path, '{}', [System.Text.UTF8Encoding]::new($false))
            }

            $decoy = Join-Path $script:root 'decoy'
            & $script:new (Join-Path (Join-Path (Join-Path (Join-Path $decoy 'Packages') 'Microsoft.WindowsTerminal_8wekyb3d8bbwe') 'LocalState') 'settings.json')
            $env:LOCALAPPDATA = $decoy
            foreach ($n in 'WT_SETTINGS_PATH', 'WT_SETTINGS_DIR', 'TSTYLES_WT_SETTINGS') {
                Remove-Item -LiteralPath "Env:\$n" -ErrorAction SilentlyContinue
            }

            # The LOCALAPPDATA each test hands the finder, and the files under it,
            # none of which exists until a test writes it.
            $script:lad = Join-Path $script:root 'lad'
            $packages = Join-Path $script:lad 'Packages'
            $script:stable  = Join-Path (Join-Path (Join-Path $packages 'Microsoft.WindowsTerminal_8wekyb3d8bbwe') 'LocalState') 'settings.json'
            $script:preview = Join-Path (Join-Path (Join-Path $packages 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe') 'LocalState') 'settings.json'
            $script:canary  = Join-Path (Join-Path (Join-Path $packages 'Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe') 'LocalState') 'settings.json'
            $script:unpackaged = Join-Path (Join-Path (Join-Path $script:lad 'Microsoft') 'Windows Terminal') 'settings.json'

            # Where the Store installs each build. The exe itself need not exist:
            # the finder only reads the path's folders.
            $apps = Join-Path $script:root 'WindowsApps'
            $script:previewExe = Join-Path (Join-Path $apps 'Microsoft.WindowsTerminalPreview_1.23.2702.0_x64__8wekyb3d8bbwe') 'WindowsTerminal.exe'
            $script:canaryExe  = Join-Path (Join-Path $apps 'Microsoft.WindowsTerminalCanary_1.24.2812.0_x64__8wekyb3d8bbwe') 'WindowsTerminal.exe'

            $script:t = @{ LOCALAPPDATA = $script:lad }
        }

        AfterEach {
            foreach ($n in @($script:savedEnv.Keys)) {
                if ($null -eq $script:savedEnv[$n]) {
                    Remove-Item -LiteralPath "Env:\$n" -ErrorAction SilentlyContinue
                } else {
                    Set-Item -LiteralPath "Env:\$n" -Value $script:savedEnv[$n]
                }
            }
        }

        Context 'which file' {
            BeforeEach {
                Mock Write-Error {}
            }

            It "a Preview tab gets Preview's settings.json, though Stable's exists" {
                & $script:new $script:stable
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:previewExe | Should -Be $script:preview
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It "a Canary tab gets Canary's, a build the old list never had" {
                & $script:new $script:stable
                & $script:new $script:canary
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:canaryExe | Should -Be $script:canary
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'a portable build gets the settings folder beside its exe' {
                $pd = Join-Path $script:root 'wt-portable'
                $portable = Join-Path (Join-Path $pd 'settings') 'settings.json'
                & $script:new $portable
                [System.IO.File]::WriteAllText((Join-Path $pd '.portable'), '', [System.Text.UTF8Encoding]::new($false))
                & $script:new $script:stable
                Find-WTSettingsPath -EnvTable $script:t -HostExePath (Join-Path $pd 'WindowsTerminal.exe') |
                    Should -Be $portable
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'a portable build needs no LOCALAPPDATA' {
                $pd = Join-Path $script:root 'wt-portable'
                $portable = Join-Path (Join-Path $pd 'settings') 'settings.json'
                & $script:new $portable
                [System.IO.File]::WriteAllText((Join-Path $pd '.portable'), '', [System.Text.UTF8Encoding]::new($false))
                Find-WTSettingsPath -EnvTable @{} -HostExePath (Join-Path $pd 'WindowsTerminal.exe') |
                    Should -Be $portable
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It "an unpackaged build gets the shared unpackaged folder, not Stable's" {
                $exe = Join-Path (Join-Path $script:root 'terminal-1.23.2702.0') 'WindowsTerminal.exe'
                & $script:new $script:stable
                & $script:new $script:unpackaged
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $exe | Should -Be $script:unpackaged
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'a package-shaped folder outside WindowsApps is not a package' {
                # An extracted copy can sit in a folder named like a package; only
                # a folder under WindowsApps is the Store build whose file lives
                # in that package's LocalState.
                $exe = Join-Path (Join-Path (Join-Path $script:root 'extracted') 'Microsoft.WindowsTerminalPreview_1.23.2702.0_x64__8wekyb3d8bbwe') 'WindowsTerminal.exe'
                & $script:new $script:preview
                & $script:new $script:unpackaged
                $result = Find-WTSettingsPath -EnvTable $script:t -HostExePath $exe
                $result | Should -Be $script:unpackaged
                $result | Should -Not -Be $script:preview
            }

            It "refuses, naming the path, when the hosting build has no settings.json -- and never takes another build's" {
                & $script:new $script:stable
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:canaryExe | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains($script:canary) -and
                    ([string]$Message).Contains($script:canaryExe) -and
                    ([string]$Message).Contains('found none there')
                }
            }

            It '...and WT_SETTINGS_DIR naming another build does not change that' {
                # Read only when the process tree names no host. Read after the
                # host's file was found missing, it would hand this Canary tab
                # Stable's file -- the defect, through another door.
                & $script:new $script:stable
                $script:t.WT_SETTINGS_DIR = Split-Path -Parent $script:stable
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:canaryExe | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains($script:canary) -and
                    ([string]$Message).Contains($script:canaryExe)
                }
            }

            It 'the process tree wins over WT_SETTINGS_DIR' {
                # A tab can inherit another build's WT_SETTINGS_DIR, so when the
                # two disagree the tree is right.
                & $script:new $script:stable
                & $script:new $script:preview
                $script:t.WT_SETTINGS_DIR = Split-Path -Parent $script:stable
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:previewExe | Should -Be $script:preview
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'takes WT_SETTINGS_DIR when the process tree cannot say' {
                & $script:new $script:stable
                & $script:new $script:preview
                $script:t.WT_SETTINGS_DIR = Split-Path -Parent $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath '' | Should -Be $script:preview
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'refuses and lists every candidate when the host cannot be told and two builds have one' {
                # Outside a tab: the way forward is a tab of the build you mean,
                # or naming the file -- -SettingsPath being how apply.ps1 does it.
                Mock Get-TerminalKind { 'Unknown' }
                & $script:new $script:stable
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath '' | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains($script:stable) -and
                    ([string]$Message).Contains($script:preview) -and
                    ([string]$Message).Contains('Open a new tab in the Windows Terminal you want styled') -and
                    ([string]$Message).Contains('-SettingsPath')
                }
            }

            It "...and inside a Windows Terminal tab says the tab's process could not be traced" {
                # Whether this is a tab is Get-TerminalKind's answer, asked of the
                # same -EnvTable: the finder reads no terminal marker itself.
                Mock Get-TerminalKind { 'WindowsTerminal' }
                & $script:new $script:stable
                & $script:new $script:preview
                $script:t.WT_SESSION = 'x'
                Find-WTSettingsPath -EnvTable $script:t -HostExePath '' | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains($script:stable) -and
                    ([string]$Message).Contains($script:preview) -and
                    ([string]$Message).Contains('does not lead back to a running WindowsTerminal.exe') -and
                    -not ([string]$Message).Contains('Open a new tab')
                }
                Should -Invoke Get-TerminalKind -Times 1 -Exactly -ParameterFilter {
                    $null -ne $EnvTable -and $EnvTable['WT_SESSION'] -eq 'x'
                }
            }

            It 'takes the only settings.json there is when the host cannot be told' {
                & $script:new $script:canary
                Find-WTSettingsPath -EnvTable $script:t -HostExePath '' | Should -Be $script:canary
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'says it could not locate one when there is none' {
                [void][System.IO.Directory]::CreateDirectory($script:lad)
                Find-WTSettingsPath -EnvTable $script:t -HostExePath '' | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    $Message -ceq 'Could not locate Windows Terminal settings.json.'
                }
            }

            It 'refuses, rather than throws, under a packaged host when LOCALAPPDATA is unset' {
                { $script:r = Find-WTSettingsPath -EnvTable @{} -HostExePath $script:previewExe } | Should -Not -Throw
                $script:r | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains('LOCALAPPDATA is not set') -and
                    ([string]$Message).Contains($script:previewExe)
                }
            }

            It 'with no LOCALAPPDATA and no host, says it could not locate one' {
                # What WSL looks like: no LOCALAPPDATA, and no Windows process tree.
                { $script:r = Find-WTSettingsPath -EnvTable @{} -HostExePath '' } | Should -Not -Throw
                $script:r | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    $Message -ceq 'Could not locate Windows Terminal settings.json.'
                }
            }

            It 'does not read WT_SETTINGS_PATH, which no Windows Terminal sets' {
                $other = Join-Path $script:root 'other.json'
                & $script:new $other
                $env:WT_SETTINGS_PATH = $other
                $script:t.WT_SETTINGS_PATH = $other
                & $script:new $script:stable
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:previewExe | Should -Be $script:preview
            }

            It 'TSTYLES_WT_SETTINGS names the file outright, over the detected host' {
                $chosen = Join-Path $script:root 'chosen.json'
                & $script:new $chosen
                $script:t.TSTYLES_WT_SETTINGS = $chosen
                & $script:new $script:stable
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:previewExe |
                    Should -Be (Convert-Path -LiteralPath $chosen)
                Should -Invoke Write-Error -Times 0 -Exactly
            }

            It 'refuses a TSTYLES_WT_SETTINGS that is not a file instead of guessing' {
                $missing = Join-Path $script:root 'missing.json'
                $script:t.TSTYLES_WT_SETTINGS = $missing
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t -HostExePath $script:previewExe | Should -BeNullOrEmpty
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    ([string]$Message).Contains('TSTYLES_WT_SETTINGS') -and
                    ([string]$Message).Contains($missing)
                }
            }

            It 'with no -HostExePath it asks the process tree' {
                # The platform guard is inside the walker, so mocking it controls
                # the host on all four legs.
                Mock Find-WTHostExePath { $script:previewExe }
                & $script:new $script:stable
                & $script:new $script:preview
                Find-WTSettingsPath -EnvTable $script:t | Should -Be $script:preview
                Should -Invoke Find-WTHostExePath -Times 1 -Exactly
            }

            It 'a bound -HostExePath, even an empty one, replaces the walk' {
                # Decided by binding, not by value: this is what keeps every ''
                # case above off a developer's real process tree.
                Mock Find-WTHostExePath { throw 'a bound -HostExePath must replace the walk' }
                [void][System.IO.Directory]::CreateDirectory($script:lad)
                { Find-WTSettingsPath -EnvTable $script:t -HostExePath '' } | Should -Not -Throw
                Should -Invoke Find-WTHostExePath -Times 0 -Exactly
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    $Message -ceq 'Could not locate Windows Terminal settings.json.'
                }
            }
        }

        Context 'under ErrorAction Stop' {
            It 'under ErrorAction Stop, as apply.ps1 runs it, the refusal ends the command' {
                # apply.ps1 sets $ErrorActionPreference = 'Stop', so the finder's
                # Write-Error is what stops it, before a null path reaches
                # Test-Path.
                [void][System.IO.Directory]::CreateDirectory($script:lad)
                { Find-WTSettingsPath -EnvTable @{ LOCALAPPDATA = $script:lad } -HostExePath '' -ErrorAction Stop } |
                    Should -Throw -ExpectedMessage 'Could not locate Windows Terminal settings.json.'
            }
        }
    }
}
