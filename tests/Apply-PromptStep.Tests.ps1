# Pester 5 tests: apply.ps1's prompt step, run as a script in a child engine.
#
# apply.ps1 carried a fourth hand-written copy of the module's prompt rule, and
# it never got the module's fixes:
#
#   * It counted only the BEGIN marker as a loader, and replaced any other
#     $PROFILE with the style's profile.ps1 -- including one holding the
#     Import-Module line the README tells Gallery users to add.
#   * The $PROFILE it replaced was the RUNNING engine's, so
#     `pwsh -File apply.ps1 -Target 'Windows PowerShell'` replaced PowerShell
#     7's profile and left the one Windows PowerShell tabs load alone.
#   * -KeepPrompt sat on the outer guard, so it -- and a style with no
#     profile.ps1 -- skipped the whole step, and the previous style's
#     current-style.ps1 stayed and loaded in every new tab.
#   * It never wrote the style record, so `tstyles current` named the old style
#     or none.
#
# apply.ps1 now never writes $PROFILE; the prompt goes to current-style.ps1
# through Set-CurrentStylePrompt, as on every module path.
#
# THE HARNESS. apply.ps1's main flow is script-level code, so it runs here as a
# script, under the engine running the suite (powershell.exe on the 5.1 leg).
# Containment, each part of which is load-bearing:
#   * HOME, ZDOTDIR, LOCALAPPDATA and XDG_* point into the case's TestDrive
#     folder, so the child's data root is there on all three platforms.
#   * $global:PROFILE is set by the driver. On Windows $PROFILE comes from the
#     Documents known folder, which no environment variable moves, and the
#     unfixed apply.ps1 writes it.
#   * .migrated-0.2.0 is seeded in the data root, or the child's first load
#     MOVES styles/*/background.* out of this checkout into it.
#   * -SettingsPath and -BackgroundImage '' mean nothing is looked up or fetched.
#   * stdout is captured, so the child is not interactive.
# Every case also asserts a positive result in settings.json: a script that
# never ran exits 0 and leaves $PROFILE unchanged too.
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

    $script:repoRoot  = $repoRoot
    $script:applyPath = Join-Path $repoRoot 'apply.ps1'
    $script:engine    = (Get-Process -Id $PID).Path
    $script:utf8      = [System.Text.UTF8Encoding]::new($false)

    # ASCII only, and every varying value arrives as a parameter: 5.1 reads a
    # BOM-less script in the system codepage.
    $script:driver = Join-Path $TestDrive 'apply-driver.ps1'
    [System.IO.File]::WriteAllText($script:driver, @'
param([string]$ApplyPath, [string]$ProfilePath, [string]$ArgsJson)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$global:TStylesNoAutoLoad = $true
$global:PROFILE = $ProfilePath
$a = [System.IO.File]::ReadAllText($ArgsJson, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$splat = @{}
foreach ($p in $a.PSObject.Properties) { $splat[$p.Name] = $p.Value }
if ($splat.ContainsKey('KeepPrompt')) { $splat['KeepPrompt'] = [bool]$splat['KeepPrompt'] }
& $ApplyPath @splat
'@, $script:utf8)

    $script:envNames = @('HOME', 'ZDOTDIR', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME',
                         'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'POWERSHELL_TELEMETRY_OPTOUT')

    # One apply.ps1 run in its own sandbox. -Seed runs with the data root made
    # and before the child starts.
    $script:runApply = {
        param([string]$Case, [hashtable]$ApplyArgs, [string]$ProfileText, [scriptblock]$Seed)

        $root     = Join-Path $TestDrive $Case
        $caseHome = Join-Path $root 'home'
        [void][System.IO.Directory]::CreateDirectory($caseHome)

        $saved = @{}
        foreach ($n in $script:envNames) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
        try {
            [Environment]::SetEnvironmentVariable('HOME', $caseHome)
            [Environment]::SetEnvironmentVariable('ZDOTDIR', $caseHome)
            [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $root 'localappdata'))
            [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', (Join-Path $root 'xdg-data'))
            [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $root 'xdg-config'))
            [Environment]::SetEnvironmentVariable('XDG_CACHE_HOME', (Join-Path $root 'xdg-cache'))
            [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', (Join-Path $root 'xdg-state'))
            [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1')

            # The module's own rule, asked with the environment pinned and the
            # case's home passed in: $HOME keeps its startup value whatever the
            # environment says, so it must not be what decides the macOS root.
            $dataRoot = InModuleScope TerminalStyles -Parameters @{ H = $caseHome } {
                param($H) Get-TStylesDataRoot -HomeDir $H
            }
            $full = [System.IO.Path]::GetFullPath($dataRoot)
            if (-not $full.StartsWith([System.IO.Path]::GetFullPath($TestDrive), [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "the child's data root would be $full, outside TestDrive"
            }
            [void][System.IO.Directory]::CreateDirectory($dataRoot)
            [System.IO.File]::WriteAllText((Join-Path $dataRoot '.migrated-0.2.0'), '', $script:utf8)

            $profileDir  = Join-Path $root 'profile'
            [void][System.IO.Directory]::CreateDirectory($profileDir)
            $profilePath = Join-Path $profileDir 'Microsoft.PowerShell_profile.ps1'
            [System.IO.File]::WriteAllText($profilePath, $ProfileText, $script:utf8)

            $settingsPath = Join-Path $root 'settings.json'
            $settings = [ordered]@{
                profiles = [ordered]@{
                    defaults = [ordered]@{}
                    list = @(
                        [ordered]@{ guid = '{a}'; name = 'PowerShell'; source = 'Windows.Terminal.PowershellCore' }
                        [ordered]@{ guid = '{b}'; name = 'Windows PowerShell'
                                    commandline = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
                        [ordered]@{ guid = '{c}'; name = 'Bare pwsh'; commandline = 'pwsh -NoLogo' }
                    )
                }
                schemes = @()
            }
            [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $script:utf8)

            if ($Seed) { & $Seed $dataRoot }

            $argsPath = Join-Path $root 'args.json'
            $all = @{ SettingsPath = $settingsPath; BackgroundImage = '' }
            foreach ($k in $ApplyArgs.Keys) { $all[$k] = $ApplyArgs[$k] }
            [System.IO.File]::WriteAllText($argsPath, ($all | ConvertTo-Json), $script:utf8)

            # Continue, explicitly: CI prepends 'stop', and on 5.1 a stderr line
            # under 'stop' with 2>&1 is a terminating error here.
            $eap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $out = $null | & $script:engine -NoProfile -NonInteractive -File $script:driver `
                    -ApplyPath $script:applyPath -ProfilePath $profilePath -ArgsJson $argsPath 2>&1 |
                    Out-String -Width 500
                $code = $LASTEXITCODE
            } finally { $ErrorActionPreference = $eap }

            $after = [System.IO.File]::ReadAllText($settingsPath, $script:utf8) | ConvertFrom-Json
            return [pscustomobject]@{
                Code        = $code
                Out         = $out
                Flat        = ($out -replace '\s+', ' ')
                DataRoot    = $dataRoot
                Current     = Join-Path $dataRoot 'current-style.ps1'
                ProfilePath = $profilePath
                ProfileDir  = $profileDir
                Settings    = $after
            }
        } finally {
            foreach ($n in $script:envNames) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
        }
    }

    $script:schemeOf = {
        param($Run, [string]$Name)
        ($Run.Settings.profiles.list | Where-Object { $_.name -eq $Name }).colorScheme
    }

    # What `tstyles current` answers for the child's data root.
    $script:currentAt = {
        param([string]$DataRoot)
        InModuleScope TerminalStyles -Parameters @{ D = $DataRoot } {
            param($D)
            $savedRoot = $script:TStylesDataRoot; $savedCurrent = $script:TStylesCurrent
            try {
                $script:TStylesDataRoot = $D
                $script:TStylesCurrent  = Join-Path $D 'current-style.ps1'
                Get-CurrentStyleName
            } finally {
                $script:TStylesDataRoot = $savedRoot; $script:TStylesCurrent = $savedCurrent
            }
        }
    }

    $script:handProfile  = "Import-Module TerminalStyles -DisableNameChecking`r`nSet-Alias ll Get-ChildItem`r`n"
    $script:blockProfile = "# ===== TerminalStyles BEGIN =====`r`nImport-Module TerminalStyles -DisableNameChecking`r`n# ===== TerminalStyles END =====`r`n"
    $script:seedEva = {
        param($DataRoot)
        [System.IO.File]::Copy((Join-Path $script:repoRoot 'styles/eva/profile.ps1'), (Join-Path $DataRoot 'current-style.ps1'), $true)
        [System.IO.File]::WriteAllText((Join-Path $DataRoot 'current-style.json'), '{"name":"eva"}', $script:utf8)
    }
}

Describe 'apply.ps1 leaves $PROFILE alone' {
    BeforeAll {
        $script:handRuns = @{}
        foreach ($t in 'PowerShell', 'Windows PowerShell') {
            $script:handRuns[$t] = & $script:runApply -Case ('hand-' + ($t -replace ' ', '')) `
                -ApplyArgs @{ Style = 'sober'; Target = $t } -ProfileText $script:handProfile
        }
    }

    It "keeps a `$PROFILE that imports TerminalStyles by hand byte for byte (-Target '<_>')" -ForEach @('PowerShell', 'Windows PowerShell') {
        $r = $script:handRuns[$_]
        $r.Code | Should -Be 0 -Because $r.Out
        & $script:schemeOf $r $_ | Should -Be 'sober' -Because "the run must have applied the style: $($r.Out)"
        [System.IO.File]::ReadAllText($r.ProfilePath, $script:utf8) | Should -BeExactly $script:handProfile
        @([System.IO.Directory]::GetFiles($r.ProfileDir, '*.bak-*')).Count | Should -Be 0
        [System.IO.File]::Exists($r.Current) | Should -BeTrue -Because 'the prompt goes to current-style.ps1'
        ([System.IO.File]::ReadAllBytes($r.Current) -join ',') |
            Should -BeExactly ([System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot 'styles/sober/profile.ps1')) -join ',')
    }

    It 'says the prompt went to current-style.ps1 and that $PROFILE was not changed' {
        $flat = $script:handRuns['PowerShell'].Flat
        $flat.Contains('Updated current-style.ps1') | Should -BeTrue -Because $flat
        $flat.Contains("'tstyles register'") | Should -BeTrue -Because $flat
        $flat.Contains('Installed profile.ps1 to:') | Should -BeFalse
        $flat.Contains('Backed up existing profile to:') | Should -BeFalse
    }
}

Describe 'apply.ps1 gives the prompt to a profile that runs pwsh without .exe' {
    It "installs the prompt for a commandline of 'pwsh -NoLogo'" {
        # Windows Terminal runs `pwsh` off PATH; the old match wanted
        # `pwsh.exe` and called this profile "not a PowerShell profile".
        $r = & $script:runApply -Case 'bare-pwsh' -ApplyArgs @{ Style = 'sober'; Target = 'Bare pwsh' } `
            -ProfileText $script:handProfile
        $r.Code | Should -Be 0 -Because $r.Out
        & $script:schemeOf $r 'Bare pwsh' | Should -Be 'sober' -Because "the run must have applied the style: $($r.Out)"
        $r.Flat.Contains('is not a PowerShell profile') | Should -BeFalse -Because $r.Flat
        [System.IO.File]::Exists($r.Current) | Should -BeTrue -Because 'the prompt goes to current-style.ps1'
    }
}

Describe 'apply.ps1 leaves no stale prompt and records the style' {

    It "-KeepPrompt removes the previous style's prompt and is reported as the new style" {
        $r = & $script:runApply -Case 'keep-stale' -ApplyArgs @{ Style = 'sober'; Target = 'PowerShell'; KeepPrompt = $true } `
            -ProfileText $script:blockProfile -Seed {
                param($DataRoot)
                & $script:seedEva $DataRoot
                [System.IO.File]::Exists((Join-Path $DataRoot 'current-style.ps1')) | Should -BeTrue -Because 'the fixture must plant the stale prompt'
            }
        $r.Code | Should -Be 0 -Because $r.Out
        & $script:schemeOf $r 'PowerShell' | Should -Be 'sober' -Because $r.Out
        [System.IO.File]::Exists($r.Current) | Should -BeFalse -Because "-KeepPrompt's contract is ABSENT, not stale"
        & $script:currentAt $r.DataRoot | Should -Be 'sober' -Because 'that is what tstyles current prints'
        [System.IO.File]::ReadAllText($r.ProfilePath, $script:utf8) | Should -BeExactly $script:blockProfile
        $r.Flat.Contains('Removed current-style.ps1') | Should -BeTrue -Because $r.Flat
    }

    It "a style that ships no profile.ps1 removes the previous style's prompt" {
        $r = & $script:runApply -Case 'no-prompt' -ApplyArgs @{ Style = 'plain'; Target = 'PowerShell' } `
            -ProfileText $script:blockProfile -Seed {
                param($DataRoot)
                & $script:seedEva $DataRoot
                $plain = Join-Path (Join-Path $DataRoot 'styles') 'plain'
                [void][System.IO.Directory]::CreateDirectory($plain)
                [System.IO.File]::WriteAllText((Join-Path $plain 'scheme.json'),
                    '{"name":"plain","background":"#101010","foreground":"#f0f0f0"}', $script:utf8)
                [System.IO.File]::WriteAllText((Join-Path $plain 'theme.json'), '{"colorScheme":"plain"}', $script:utf8)
            }
        $r.Code | Should -Be 0 -Because $r.Out
        & $script:schemeOf $r 'PowerShell' | Should -Be 'plain' -Because $r.Out
        [System.IO.File]::Exists($r.Current) | Should -BeFalse
        & $script:currentAt $r.DataRoot | Should -Be 'plain'
    }

    It 'a first -KeepPrompt apply is reported by tstyles current' {
        $r = & $script:runApply -Case 'keep-first' -ApplyArgs @{ Style = 'sober'; Target = 'PowerShell'; KeepPrompt = $true } `
            -ProfileText $script:blockProfile
        $r.Code | Should -Be 0 -Because $r.Out
        & $script:schemeOf $r 'PowerShell' | Should -Be 'sober' -Because $r.Out
        [System.IO.File]::Exists($r.Current) | Should -BeFalse
        & $script:currentAt $r.DataRoot | Should -Be 'sober' -Because 'apply.ps1 must write the record'
    }
}
