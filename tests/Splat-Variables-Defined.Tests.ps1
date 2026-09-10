# Pester 5 tests: every splatted variable must be assigned in the function that
# splats it.
#
# THE DEFECT THIS EXISTS FOR. `$wezSplat = @{}` and its ContainsKey line were
# lost resolving a merge in Invoke-TerminalStylesUninstall, while both USES of
# `@wezSplat` survived. PowerShell does not object to splatting a variable that
# does not exist, and it does not pass "no arguments" either:
#
#     function Probe { param([string]$HomeDir) ... }
#     Probe @neverDefined   ->   bound=True   value=[]
#
# It binds the FIRST POSITIONAL PARAMETER to an empty string, and
# $PSBoundParameters.ContainsKey('HomeDir') reports TRUE. That is the exact
# guard this codebase uses everywhere to tell "the caller asked for a sandbox"
# from "use the live $HOME" -- so a lost splat variable does not disable the
# seam, it reports a sandbox that was never requested, with an empty path. It
# fails unsafe.
#
# Here it happened to throw on Join-Path, which is why five tests went red
# rather than something silently resolving against the wrong home. That was
# luck, not design.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:sourceFiles = @(
        (Join-Path $script:repoRoot 'tstyles.ps1')
        (Join-Path $script:repoRoot 'terminals.ps1')
        (Join-Path $script:repoRoot 'apply.ps1')
        (Join-Path $script:repoRoot 'install.ps1')
    ) + @(Get-ChildItem -Path (Join-Path $script:repoRoot 'lib') -Filter '*.ps1' |
          ForEach-Object { $_.FullName })
}

Describe 'every splatted variable is assigned before it is splatted' {
    It '<_> splats nothing it does not define' -ForEach $script:sourceFiles {
        $path = $_
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0 -Because "$path must parse"

        # Every function, plus the file's top level as one more scope.
        $scopes = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $scopes += $ast

        $bad = @()
        foreach ($scope in $scopes) {
            $name = if ($scope -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $scope.Name
            } else { '<file scope>' }

            # Splatted usages: a VariableExpressionAst with Splatted = $true.
            $splatted = @($scope.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Splatted }, $true))
            if (-not $splatted) { continue }

            # Anything assigned anywhere in the same scope counts, however it
            # was assigned -- '=', a foreach variable, or a param() default.
            $assigned = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($a in $scope.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    [void]$assigned.Add($a.Left.VariablePath.UserPath)
                }
            }
            foreach ($p in $scope.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
                [void]$assigned.Add($p.Name.VariablePath.UserPath)
            }
            foreach ($f in $scope.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
                [void]$assigned.Add($f.Variable.VariablePath.UserPath)
            }

            foreach ($s in $splatted) {
                $v = $s.VariablePath.UserPath
                if ($v -match '^(args|PSBoundParameters|null)$') { continue }
                if ($assigned.Contains($v)) { continue }
                $bad += "$name splats `@$v, which nothing in it assigns"
            }
        }

        $bad -join "`n" | Should -BeNullOrEmpty -Because @'
splatting an undefined variable binds the first positional parameter to an
empty string AND reports it as bound, so a lost splat definition silently
turns a "no sandbox requested" call into a "sandbox at the empty path" one
'@
    }
}
