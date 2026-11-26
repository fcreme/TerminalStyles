# A style's scheme.json and theme.json have one reader: Read-StyleJson.
#
# It parses them the way Windows Terminal does, comments and trailing commas
# allowed, and it is what the gate in front of every apply asks
# (Get-StyleUnreadableFile). Any other parse of the same files is a second
# rule, and on Windows PowerShell 5.1 a stricter one: ConvertFrom-Json there
# rejects the comment the gate accepted. So a style passed the gate, reached
# settings.json, and then failed in the VS Code writer, `tstyles show`, the
# tuner or the palette re-sent at shell startup -- the half-applied style
# audit #20 was about, by another door.
#
# Walks the AST of every shipped source file. A ConvertFrom-Json or
# ConvertFrom-JsoncText fails the test when its pipeline names 'scheme.json'
# or 'theme.json', or a variable assigned -- directly or through other
# variables -- from an expression that does, unless it is inside Read-StyleJson
# or a function listed below with the reason it is not a reader of a style.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = Split-Path $PSScriptRoot -Parent
    $script:sourceCases = @(
        @{ Name = 'tstyles.ps1'; Path = (Join-Path $root 'tstyles.ps1') }
        @{ Name = 'apply.ps1';   Path = (Join-Path $root 'apply.ps1') }
    ) + @(Get-ChildItem -LiteralPath (Join-Path $root 'lib') -Filter '*.ps1' | Sort-Object Name |
          ForEach-Object { @{ Name = ('lib/' + $_.Name); Path = $_.FullName } })
}

BeforeAll {
    $script:styleFileName = '^(?:scheme|theme)\.json$'
    # Function name -> why its parse is not a second reader of a style.
    $script:notReaders = @{
        'Read-StyleJson' = 'it is the reader'
        # What a SUBMITTED style must be is the catalogue's rule, checked on the
        # contributor's machine; it reads nothing about to be applied.
        'Get-StyleSubmissionProblems' = 'the submission check'
    }

    $script:findStyleParses = {
        param([string]$Path)
        $L = [System.Management.Automation.Language.Parser]
        $ast = $L::ParseFile($Path, [ref]$null, [ref]$null)

        # The function a node belongs to, or '' at script level.
        $scopeOf = {
            param($n)
            $p = $n.Parent
            while ($p -and $p -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $p = $p.Parent }
            if ($p) { $p.Name } else { '' }
        }
        $namesStyleFile = {
            param($n)
            @($n.FindAll({ param($x)
                $x -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $x.Value -match $script:styleFileName }, $true)).Count -gt 0
        }
        $varsIn = {
            param($n)
            @($n.FindAll({ param($x) $x -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
              ForEach-Object { $_.VariablePath.UserPath })
        }

        # Variables holding a path (or the text) of a style file, per function:
        # assigned from an expression naming one, then from those, to a fixpoint.
        # An assignment from Read-StyleJson itself is the reader's answer, not a path.
        $assigns = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
            Where-Object {
                $left = $_.Left
                while ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
                $left -is [System.Management.Automation.Language.VariableExpressionAst]
            })
        $tainted = @{}
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($a in $assigns) {
                $left = $a.Left
                while ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
                $key = (& $scopeOf $a) + '|' + $left.VariablePath.UserPath
                if ($tainted.ContainsKey($key)) { continue }
                $rightText = $a.Right.Extent.Text
                if ($rightText -match '\bRead-StyleJson\b') { continue }
                $scope = & $scopeOf $a
                $fromStyleFile = (& $namesStyleFile $a.Right) -or
                    @(& $varsIn $a.Right | Where-Object { $tainted.ContainsKey($scope + '|' + $_) }).Count -gt 0
                if ($fromStyleFile) { $tainted[$key] = $true; $changed = $true }
            }
        }

        $parses = @($ast.FindAll({ param($x)
            $x -is [System.Management.Automation.Language.CommandAst] -and
            $x.GetCommandName() -in 'ConvertFrom-Json', 'ConvertFrom-JsoncText' }, $true))
        foreach ($c in $parses) {
            $scope = & $scopeOf $c
            if ($script:notReaders.ContainsKey($scope)) { continue }
            $pipe = $c.Parent
            $readsStyleFile = (& $namesStyleFile $pipe) -or
                @(& $varsIn $pipe | Where-Object { $tainted.ContainsKey($scope + '|' + $_) }).Count -gt 0
            if ($readsStyleFile) {
                '{0}:{1} in {2}' -f (Split-Path -Leaf $Path), $c.Extent.StartLineNumber, $(if ($scope) { $scope } else { 'script' })
            }
        }
    }
}

Describe "a style's scheme.json and theme.json have one reader" {
    It '<Name> parses them only through Read-StyleJson' -ForEach $script:sourceCases {
        @(& $script:findStyleParses $Path) | Should -BeNullOrEmpty
    }

    It 'the walk finds a parse of a style file when there is one' {
        # Without this, a walk that matched nothing would pass every file.
        $probe = Join-Path $TestDrive 'probe.ps1'
        [System.IO.File]::WriteAllText($probe, @'
function Get-Probe {
    param($Dir)
    $tp = Join-Path $Dir 'theme.json'
    $raw = [System.IO.File]::ReadAllText($tp)
    $one = $raw | ConvertFrom-Json
    $two = [System.IO.File]::ReadAllText((Join-Path $Dir 'scheme.json')) | ConvertFrom-Json
    $ok  = Read-StyleJson -StyleDir $Dir -FileName 'scheme.json'
    $settings = [System.IO.File]::ReadAllText('settings.json') | ConvertFrom-Json
}
'@)
        @(& $script:findStyleParses $probe) | Should -Be @('probe.ps1:5 in Get-Probe', 'probe.ps1:6 in Get-Probe')
    }
}
