# Pester 5 tests: the picker's and the tuner's previews go through the preview
# session, and every settings.json writer looks for a closed session's preview
# before it reads the file.
#
# Structural, because the picker's and the tuner's key loops need a console no
# test can give them (see tests/Picker-ShellStateStaging.Tests.ps1). Everything
# these pin is driven behaviourally in tests/FilePreviewSession.Tests.ps1 and
# tests/Preview-Recovery-Writers.Tests.ps1; this says the code paths reach it.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:WriterCases = @(
        @{ Name = 'Invoke-TerminalStyle';     Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'New-FilePreviewSession' }
        @{ Name = 'Invoke-TerminalStyle';     Kind = 'WezTerm';         After = 'Get-WezTermModulePath'; Before = 'New-FilePreviewSession' }
        @{ Name = 'Invoke-TerminalStyleTune'; Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'New-FilePreviewSession' }
        @{ Name = 'Apply-StyleDirect';        Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'Save-SettingsBackup' }
        @{ Name = 'Reset-StyleDirect';        Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'ReadAllText' }
        @{ Name = 'Invoke-TerminalStyleFont'; Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'Save-SettingsBackup' }
        @{ Name = 'apply.ps1';                Kind = 'WindowsTerminal'; After = 'Find-WTSettingsPath';   Before = 'ReadAllText' }
    )
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:astOf = {
        param([string]$Name)
        if ($Name -eq 'apply.ps1') {
            return [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'apply.ps1'), [ref]$null, [ref]$null)
        }
        InModuleScope TerminalStyles -Parameters @{ N = $Name } { param($N) (Get-Command $N).ScriptBlock.Ast }
    }
    $script:commands = {
        param($Ast, [string]$Command)
        @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Command }, $true))
    }
}

Describe 'no picker or tuner write goes around the session' {
    It '<_> holds no direct Write-SettingsAtomic or WriteAllBytes' -ForEach @('Invoke-TerminalStyle', 'Invoke-TerminalStyleTune', 'Restore-TuneBaseLook') {
        $ast = & $script:astOf $_
        (& $script:commands $ast 'Write-SettingsAtomic').Count | Should -Be 0
        @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($n.Member)" -eq 'WriteAllBytes' }, $true)).Count |
            Should -Be 0
    }

    It 'the query can find one, in Write-FilePreview' {
        (& $script:commands (& $script:astOf 'Write-FilePreview') 'Write-SettingsAtomic').Count | Should -BeGreaterThan 0
    }
}

Describe 'every writer looks for a closed session first' {
    It '<Name> recovers <Kind> once, after <After> and before <Before>' -ForEach $script:WriterCases {
        $ast = & $script:astOf $Name
        $rec = @(& $script:commands $ast 'Restore-AbandonedFilePreview' | Where-Object {
            $_.Extent.Text -match ('-Kind\s+' + $Kind + '\b') })
        $rec.Count | Should -Be 1
        $at = $rec[0].Extent.StartOffset

        $after = @(& $script:commands $ast $After)
        $after.Count | Should -BeGreaterThan 0
        $after[0].Extent.StartOffset | Should -BeLessThan $at

        if ($Before -eq 'ReadAllText') {
            $reads = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($n.Member)" -eq 'ReadAllText' }, $true))
        } else {
            $reads = @(& $script:commands $ast $Before | Where-Object { $Before -ne 'New-FilePreviewSession' -or $_.Extent.Text -match ('-Kind\s+' + $Kind + '\b') })
        }
        $reads.Count | Should -BeGreaterThan 0
        $at | Should -BeLessThan (@($reads | ForEach-Object { $_.Extent.StartOffset } | Sort-Object)[0])
    }
}
