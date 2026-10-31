# Pester 5 tests for Get-LoginShell: the one reader of $env:SHELL, and the one
# answer to "which shell does this user log in to".
#
# shell-init read $env:SHELL twice, two ways: the writes took anything without
# 'zsh' in its PATH for bash, and the closing line took any leaf that was not
# bash or zsh for a POSIX sh. So pwsh, fish and tcsh were both at once.
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

Describe 'Get-LoginShell' {
    InModuleScope TerminalStyles {
        It "classifies '<shell>' as <kind>" -ForEach @(
            @{ shell = '/bin/zsh';                                kind = 'zsh';   leaf = 'zsh' }
            @{ shell = '/usr/bin/zsh5';                           kind = 'zsh';   leaf = 'zsh5' }
            @{ shell = '/bin/zsh-static';                         kind = 'zsh';   leaf = 'zsh-static' }
            @{ shell = '/bin/rzsh';                               kind = 'zsh';   leaf = 'rzsh' }
            @{ shell = '/opt/homebrew/bin/bash';                  kind = 'bash';  leaf = 'bash' }
            @{ shell = '/opt/zsh-tools/bin/bash';                 kind = 'bash';  leaf = 'bash' }
            @{ shell = '/bin/bash-static';                        kind = 'bash';  leaf = 'bash-static' }
            @{ shell = 'C:\Program Files\Git\usr\bin\bash.exe';   kind = 'bash';  leaf = 'bash' }
            @{ shell = '/bin/sh';                                 kind = 'sh';    leaf = 'sh' }
            @{ shell = '/bin/dash';                               kind = 'sh';    leaf = 'dash' }
            @{ shell = '/bin/ksh93';                              kind = 'sh';    leaf = 'ksh93' }
            @{ shell = '/usr/bin/mksh';                           kind = 'sh';    leaf = 'mksh' }
            @{ shell = '/usr/local/bin/pwsh';                     kind = 'other'; leaf = 'pwsh' }
            @{ shell = '/opt/homebrew/bin/fish';                  kind = 'other'; leaf = 'fish' }
            @{ shell = '/bin/tcsh';                               kind = 'other'; leaf = 'tcsh' }
            @{ shell = '/usr/bin/nu';                             kind = 'other'; leaf = 'nu' }
            @{ shell = '';                                        kind = 'bash';  leaf = '' }
        ) {
            $r = Get-LoginShell -Shell $shell
            $r.Kind | Should -BeExactly $kind
            $r.Name | Should -BeExactly $leaf
        }

        It 'reads $env:SHELL when it is not told which shell' {
            $prev = $env:SHELL
            try {
                $env:SHELL = '/bin/dash'
                (Get-LoginShell).Kind | Should -BeExactly 'sh'
            } finally { $env:SHELL = $prev }
        }
    }
}

Describe 'the login shell has one reader' {
    # Structure, not behaviour, as tests/Get-TerminalKind.Tests.ps1 pins
    # WT_SESSION: every $env:SHELL read in the source, keyed by the function
    # that holds it. A second reader is how the two rules above came about.
    It 'nothing but Get-LoginShell reads $env:SHELL' {
        $root = Split-Path $PSScriptRoot -Parent
        $files = @(
            (Join-Path $root 'tstyles.ps1')
            (Join-Path $root 'terminals.ps1')
            (Join-Path $root 'apply.ps1')
            (Join-Path $root 'install.ps1')
        ) + @(Get-ChildItem -LiteralPath (Join-Path $root 'lib') -Filter '*.ps1' | ForEach-Object { $_.FullName })
        $files.Count | Should -BeGreaterThan 4 -Because 'the scan must have files to read'

        $owners = foreach ($path in $files) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
            @($errors).Count | Should -Be 0 -Because "$path must parse"
            $reads = $ast.FindAll({ param($n)
                ($n -is [System.Management.Automation.Language.VariableExpressionAst] -and
                 $n.VariablePath.IsDriveQualified -and $n.VariablePath.DriveName -eq 'env' -and
                 ($n.VariablePath.UserPath -replace '^[^:]*:', '') -eq 'SHELL') -or
                ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                 $n.Value -ceq 'SHELL')
            }, $true)
            foreach ($read in $reads) {
                $scope = $read.Parent
                while ($scope -and -not ($scope -is [System.Management.Automation.Language.FunctionDefinitionAst])) {
                    $scope = $scope.Parent
                }
                if ($scope) { $scope.Name } else { '<file scope>' }
            }
        }
        (@($owners | Sort-Object -Unique) -join ',') | Should -BeExactly 'Get-LoginShell'
    }
}
