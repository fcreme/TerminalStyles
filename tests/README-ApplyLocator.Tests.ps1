# Pester 5 tests: the wiki's way to find apply.ps1 finds the copy that is
# loaded, as a bootstrap install is.
#
# The snippet asked `Get-Module -ListAvailable`, which lists only PSModulePath.
# A bootstrap install is imported by path and is not on it, so the snippet
# stopped on "Cannot bind argument to parameter 'Path' because it is null" --
# or, on a machine that also had a Gallery install, ran that copy's apply.ps1.
#
# The block is run verbatim, in a child engine, after importing a fake
# bootstrap-shaped module from TestDrive. `pwsh` is shadowed by a function that
# prints the path it was given, so nothing real is run.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe "the wiki's apply.ps1 locator" {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $page = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'docs/wiki/Scripting-and-Recovery.md'),
                                              [System.Text.UTF8Encoding]::new($false))
        $section = [regex]::Match($page, '(?ms)^## Scriptable / non-interactive\s*$(.*?)(?=^##\s|\z)').Groups[1].Value
        $script:block = [regex]::Match($section, '(?ms)^```powershell\s*$(.*?)^```').Groups[1].Value
    }

    It 'finds apply.ps1 in the copy that is loaded, as a bootstrap install is' {
        $script:block | Should -Not -BeNullOrEmpty -Because 'the section must still hold the snippet'

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $mod = Join-Path (Join-Path $TestDrive 'boot') 'TerminalStyles'
        [void][System.IO.Directory]::CreateDirectory($mod)
        [System.IO.File]::WriteAllText((Join-Path $mod 'TerminalStyles.psd1'),
            "@{ ModuleVersion = '0.0.1'; RootModule = 'TerminalStyles.psm1'; FunctionsToExport = @(); CmdletsToExport = @(); VariablesToExport = @(); AliasesToExport = @() }", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $mod 'TerminalStyles.psm1'), '', $utf8)
        $fakeApply = Join-Path $mod 'apply.ps1'
        [System.IO.File]::WriteAllText($fakeApply, '', $utf8)

        $probe = Join-Path $TestDrive 'locator-probe.ps1'
        [System.IO.File]::WriteAllText($probe, (
            "param([string]`$Psd1)`n" +
            "function pwsh { 'TSTYLES-APPLY ' + `$args[1] }`n" +
            "Import-Module `$Psd1 -DisableNameChecking -ErrorAction Stop`n" +
            $script:block), $utf8)

        $names = @('HOME', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'POWERSHELL_TELEMETRY_OPTOUT')
        $saved = @{}
        foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
        $eap = $ErrorActionPreference
        try {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, (Join-Path $TestDrive ('env-' + $n))) }
            [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1')
            # Continue, explicitly: CI prepends 'stop', and on 5.1 a stderr line
            # under 'stop' with 2>&1 is a terminating error here.
            $ErrorActionPreference = 'Continue'
            $out = $null | & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $probe `
                -Psd1 (Join-Path $mod 'TerminalStyles.psd1') 2>&1 | Out-String -Width 500
        } finally {
            $ErrorActionPreference = $eap
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
        }

        $lines = @($out -split "`r?`n" | Where-Object { $_.StartsWith('TSTYLES-APPLY ') })
        $lines.Count | Should -Be 1 -Because $out
        [System.IO.Path]::GetFullPath($lines[0].Substring('TSTYLES-APPLY '.Length).Trim()) |
            Should -Be ([System.IO.Path]::GetFullPath($fakeApply))
    }
}
