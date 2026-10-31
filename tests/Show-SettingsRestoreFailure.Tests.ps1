# Pester 5 tests for Show-SettingsRestoreFailure: what the picker and the tuner
# print, in place of "Reverted.", when settings.json could not be put back --
# and the shape pins that make both of them print it.
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

Describe 'Show-SettingsRestoreFailure' {
    InModuleScope TerminalStyles {
        It 'names the reason, and the command that puts the .bak back, when the backup was taken' {
            $path = "C:\it's\settings.json"
            $out = Show-SettingsRestoreFailure -Reason "Could not write C:\it's\settings.json: denied" `
                -SettingsPath $path -By tuner -BackupTaken 6>&1 | Out-String -Width 500

            $out.Contains("Could not write C:\it's\settings.json: denied") | Should -BeTrue -Because $out
            $out.Contains("Copy-Item -LiteralPath 'C:\it''s\settings.json.bak' -Destination 'C:\it''s\settings.json' -Force") |
                Should -BeTrue -Because "the quote is doubled so the line pastes as it is: $out"
            $out.Contains('tuner') | Should -BeTrue
            $out.Contains('Reverted') | Should -BeFalse
        }

        It 'does not point at a .bak it could not take' {
            $out = Show-SettingsRestoreFailure -Reason 'Could not write /x/settings.json: denied' `
                -SettingsPath '/x/settings.json' -By picker 6>&1 | Out-String -Width 500

            $out.Contains('Could not write /x/settings.json: denied') | Should -BeTrue
            $out.Contains('could not be taken') | Should -BeTrue -Because $out
            $out.Contains('picker') | Should -BeTrue
            $out.Contains('Copy-Item') | Should -BeFalse
        }

        It 'says the file could not be checked when the tuner could not read it back' {
            $out = Show-SettingsRestoreFailure -Reason 'Could not write /x/settings.json: denied' `
                -SettingsPath '/x/settings.json' -By tuner -BackupTaken -Unchecked 6>&1 | Out-String -Width 500

            $out.Contains('could not be read back') | Should -BeTrue -Because $out
            $out.Contains('is not back') | Should -BeFalse
        }
    }
}

Describe 'the picker and the tuner report a failed put-back' {
    # Shape pins: both bodies need a console. They say which expressions carry
    # the decision, not what the text of the function is.
    BeforeAll {
        $script:pickerAst = InModuleScope TerminalStyles { (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast }
        $script:tunerAst  = InModuleScope TerminalStyles { (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast }
        $script:callsTo = {
            param($Ast, [string]$Name)
            @($Ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name }, $true))
        }
    }

    It "catches the picker's put-back inside the revert, so the rest of the revert still runs" {
        $assign = @($script:pickerAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$restoreOriginalLook' }, $true))
        $assign.Count | Should -Be 1
        $put = @($assign[0].Right.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.CommandElements[0].VariablePath.UserPath -eq 'restoreOriginalSettings' }, $true))
        $put.Count | Should -Be 1
        $p = $put[0].Parent; $guarded = $false
        while ($p -and $p -ne $assign[0]) {
            if ($p -is [System.Management.Automation.Language.TryStatementAst]) { $guarded = $true; break }
            $p = $p.Parent
        }
        $guarded | Should -BeTrue -Because 'a throw there skipped the WezTerm and VS Code restores and the revert packet'
    }

    It 'the picker prints it on Esc and in its finally' {
        @(& $script:callsTo $script:pickerAst 'Show-SettingsRestoreFailure').Count | Should -BeGreaterOrEqual 2
    }

    It 'the tuner prints it on Esc, the aborted save and its finally' {
        @(& $script:callsTo $script:tunerAst 'Show-SettingsRestoreFailure').Count | Should -BeGreaterOrEqual 3
    }
}
