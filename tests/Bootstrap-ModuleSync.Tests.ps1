# Pester 5 tests: the functions install.ps1 duplicates from the module must
# stay byte-equivalent to the module's own.
#
# install.ps1 is the bootstrap. It is fetched and piped to `iex` before the
# module exists on disk, so it cannot dot-source the library -- it carries its
# own copy of Get-TStylesPlatform, Get-TStylesDataRoot and
# Get-PowerShellEngineCandidate. All three say "duplicated ... keep in sync" and
# nothing checked that they were.
#
# The reason it matters is not just tidiness. `tstyles update` on a bootstrap
# install runs `Invoke-Expression $installerScript` (lib/update.ps1) -- INSIDE
# the module's scope. So install.ps1's copies do not merely sit beside the
# module's, they REPLACE them for the rest of that session. Anything the module
# does afterwards runs the bootstrap's version.
#
# Found drifted: the module returned [pscustomobject], install.ps1 returned raw
# hashtables. lib/update.ps1's uninstall path does
# `foreach ($exe in (Get-PowerShellEngineCandidate).Exe)` -- member enumeration,
# which the two types do not treat identically across PowerShell versions. So
# `tstyles update` followed by `tstyles uninstall` in one tab ran a different
# function from the same call in a fresh tab.
#
# Comments are excluded from the comparison: the two copies explain themselves
# differently on purpose (one says "duplicated from tstyles.ps1", the other does
# not). Code is what has to match.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    function script:Get-FunctionNames([string]$Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$null, [ref]$null)
        @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object { $_.Name })
    }

    $installFns = script:Get-FunctionNames (Join-Path $repoRoot 'install.ps1')
    $moduleFns  = script:Get-FunctionNames (Join-Path $repoRoot 'tstyles.ps1')
    $script:SharedFns = @($installFns | Where-Object { $moduleFns -contains $_ } | Sort-Object -Unique)
}

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent

    # Enumerated AGAIN here. Pester runs BeforeDiscovery in the discovery scope,
    # so $script:SharedFns is $null by the time an It body executes -- the
    # -ForEach cases above use the discovery copy and are fine, a loop or a count
    # inside an It body is not. This file tripped it on its first run, hours
    # after the same trap was fixed in Lib-Loading.Tests.ps1.
    $installAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $script:repoRoot 'install.ps1'), [ref]$null, [ref]$null)
    $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $script:repoRoot 'tstyles.ps1'), [ref]$null, [ref]$null)
    $nameOf = { param($a) @($a.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Name }) }
    $iNames = & $nameOf $installAst
    $mNames = & $nameOf $moduleAst
    $script:SharedFns = @($iNames | Where-Object { $mNames -contains $_ } | Sort-Object -Unique)

    # Code only: tokens inside the function's extent, minus comments and layout.
    # A regex that stripped '#' to end-of-line would also gut any hex colour or
    # '#' inside a string, which this repo is full of.
    function script:Get-FunctionCode {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$null)
        $fn = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq $Name }, $true))
        if (-not $fn) { return $null }
        $start = $fn[0].Extent.StartOffset
        $end   = $fn[0].Extent.EndOffset
        (($tokens | Where-Object {
            $_.Extent.StartOffset -ge $start -and $_.Extent.EndOffset -le $end -and
            $_.Kind -ne 'Comment' -and $_.Kind -ne 'NewLine' -and $_.Kind -ne 'EndOfInput'
        }) | ForEach-Object { $_.Text }) -join ' '
    }
}

Describe 'install.ps1 duplicates the module faithfully' {

    It 'still duplicates the three it is supposed to' {
        # If this drops to zero the rest of the file silently tests nothing --
        # the exact failure mode this suite has been cleaning up all week.
        @($script:SharedFns).Count | Should -BeGreaterOrEqual 3
        foreach ($n in 'Get-TStylesPlatform', 'Get-TStylesDataRoot', 'Get-PowerShellEngineCandidate') {
            $script:SharedFns | Should -Contain $n
        }
    }

    It '<_> is identical in install.ps1 and tstyles.ps1' -ForEach $script:SharedFns {
        $a = script:Get-FunctionCode -Path (Join-Path $script:repoRoot 'install.ps1')  -Name $_
        $b = script:Get-FunctionCode -Path (Join-Path $script:repoRoot 'tstyles.ps1') -Name $_
        $a | Should -Not -BeNullOrEmpty
        $b | Should -Not -BeNullOrEmpty
        $a | Should -Be $b -Because @"
$_ is duplicated in install.ps1 and must match tstyles.ps1 exactly.
`tstyles update` Invoke-Expressions install.ps1 INSIDE the module's scope, so a
drifted copy replaces the module's version for the rest of that session.
"@
    }

    It 'the engine list is the same shape the module''s consumers expect' {
        # The drift that was actually there. lib/update.ps1's uninstall does
        # `foreach ($exe in (Get-PowerShellEngineCandidate).Exe)`, so whatever
        # install.ps1 leaves behind has to answer member enumeration the same way.
        $TStylesInstallNoRun = $true
        . (Join-Path $script:repoRoot 'install.ps1')
        foreach ($platform in 'Windows', 'MacOS', 'Linux') {
            $engines = @(Get-PowerShellEngineCandidate -Platform $platform)
            @($engines).Count | Should -BeGreaterThan 0
            foreach ($e in $engines) {
                $e | Should -BeOfType [pscustomobject] -Because 'the module returns these, and update overwrites the module''s copy'
            }
            @($engines.Exe)   | Should -Not -BeNullOrEmpty -Because 'uninstall enumerates .Exe over the array'
            @($engines.Exe).Count   | Should -Be @($engines).Count
            @($engines.Label).Count | Should -Be @($engines).Count
        }
    }
}
