# Pester 5 tests: the "don't run main" guards survive Set-StrictMode.
#
# scripts/demo.ps1, install.ps1 and apply.ps1 each end on
# `if (-not $TStyles<X>NoRun) { ...main... }`, so tests can dot-source them for
# their functions. Only the tests ever set that variable. In a normal run it does
# not exist, and under Set-StrictMode -Version Latest, reading a variable that
# does not exist is an error. demo.ps1 sets strict mode itself, so every mode
# but -Restore died on its last statement with "The variable
# '$TStylesDemoNoRun' cannot be retrieved because it has not been set" (#129).
# install.ps1 and apply.ps1 do not set it, but install.ps1 runs through
# `iwr | iex` in the user's own session, so a profile that turns strict mode
# on hit the same wall.
#
# Running any of these scripts for real is not an option here (the demo parks
# the real styles and runs `tstyles reset`; the installer installs). So each
# case takes the guard's own condition out of the file and evaluates it in a
# fresh runspace, under strict mode, with the variable unset: the exact
# statement that threw, in the exact state a normal run is in.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'NoRun guards under Set-StrictMode -Version Latest' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent

        function script:Get-GuardCondition {
            # The condition of the top-level `if` that names $VarName, however it
            # reads it ($Var, or Get-Variable -Name Var).
            param([string]$Path, [string]$VarName)
            $src = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$null)
            $ifs = @($ast.EndBlock.Statements | Where-Object {
                $_ -is [System.Management.Automation.Language.IfStatementAst] -and
                $_.Clauses[0].Item1.Extent.Text -cmatch "\b$([regex]::Escape($VarName))\b"
            })
            @($ifs).Count | Should -Be 1 -Because "$Path has one top-level guard on `$$VarName"
            return $ifs[0].Clauses[0].Item1.Extent.Text
        }

        function script:Invoke-InCleanRunspace {
            # A runspace of its own, so no variable from this test's scopes can
            # stand in for the one a normal run does not have.
            param([string]$Script)
            $ps = [powershell]::Create()
            try {
                $out = $ps.AddScript($Script).Invoke()
                [pscustomobject]@{
                    Output = @($out)
                    Errors = @($ps.Streams.Error | ForEach-Object { $_.ToString() })
                }
            } finally { $ps.Dispose() }
        }
    }

    It '<File> runs main when $<Var> is not set' -ForEach @(
        @{ File = 'scripts/demo.ps1'; Var = 'TStylesDemoNoRun' }
        @{ File = 'install.ps1';      Var = 'TStylesInstallNoRun' }
        @{ File = 'apply.ps1';        Var = 'TStylesApplyNoRun' }
    ) {
        $cond = Get-GuardCondition -Path (Join-Path $script:repoRoot $File) -VarName $Var
        $r = Invoke-InCleanRunspace "Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; [bool]($cond)"
        $r.Errors | Should -BeNullOrEmpty -Because 'reading an unset variable under strict mode is an error'
        $r.Output | Should -Be @($true) -Because 'a normal run sets nothing, so main must run'
    }

    It '<File> skips main when $<Var> is $true' -ForEach @(
        @{ File = 'scripts/demo.ps1'; Var = 'TStylesDemoNoRun' }
        @{ File = 'install.ps1';      Var = 'TStylesInstallNoRun' }
        @{ File = 'apply.ps1';        Var = 'TStylesApplyNoRun' }
    ) {
        # The counterweight: the tests that dot-source these files still get
        # their functions without the side effects.
        $cond = Get-GuardCondition -Path (Join-Path $script:repoRoot $File) -VarName $Var
        $r = Invoke-InCleanRunspace "Set-StrictMode -Version Latest; `$$Var = `$true; [bool]($cond)"
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Be @($false)
    }
}
