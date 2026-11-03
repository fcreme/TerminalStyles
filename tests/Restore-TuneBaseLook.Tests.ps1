# Pester 5 tests: the tuner's revert runs once, not twice.
#
# THE DEFECT. `tstyles tune <name>` has three ways out that must undo the live
# preview -- Escape, an aborted save, and the finally that catches everything
# else. The first two did it explicitly and then fell into the third, whose only
# gate is $applied, which a cancel never sets. So a cancel reverted TWICE.
# Measured on a pty, with Write-SettingsAtomic wrapped to log and delegate to the
# shipped scriptblock:
#
#   TUNER  (Esc): WRITE len=1390 (preview)
#                 WRITE len=570 sha=97256380A8BF  <- tune.ps1:1502, the Escape branch
#                 WRITE len=570 sha=97256380A8BF  <- tune.ps1:1663, the finally
#   PICKER (Esc): WRITE len=1390 (preview)
#                 WRITE len=570 sha=97256380A8BF  <- once; $pickerState.Reverted
#                                                    short-circuits its finally
#
# and the same doubling in the OSC revert packet (two ESC]104 sequences in the
# tuner's pty transcript, one in the picker's). The end state was right both
# ways; the cost is a second atomic replace of a file the user owns, a second
# mtime bump -- which Windows Terminal watches for and reloads on, so a
# cancelled tune flickered twice -- and a duplicate packet at the terminal. The
# picker's own comment names that cost in as many words: "it bumps the mtime,
# and Windows Terminal watches the file and reloads on the change".
#
# WHY THIS FILE EXISTS AT ALL. The tuner's key loop cannot be driven from a test
# -- it returns at [Console]::IsInputRedirected long before any of this, which
# is why tests/Invoke-TerminalStyleTune.Tests.ps1 says "the interactive key loop
# itself is verified manually". Moving the revert body out of the scriptblock
# and into a named function puts the rule that was missing -- run at most once --
# where a test can reach it. The last Describe pins the wiring the callers own.
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

Describe 'Restore-TuneBaseLook' {
    # The put-back is the preview session's (lib/previewsession.ps1): driven
    # here against a real settings.json in $TestDrive, with the data root there
    # too, so the record and copy the session keeps stay in the sandbox.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:tuneState = @{ Reverted = $false }
            $script:opened    = [pscustomobject]@{
                background = '#0a0006'; foreground = '#ffe8e8'; cursorColor = '#ff3d5a'
            }
            $script:settingsPath = Join-Path $sand 'settings.json'
            $script:original = '{ "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "Campbell" } ] } }'
            [System.IO.File]::WriteAllText($script:settingsPath, $script:original, [System.Text.UTF8Encoding]::new($false))
            $script:preview = '{ "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "eva", "opacity": 70 } ] } }'
            $script:newSession = {
                $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:settingsPath -By tuner -TargetName 'PowerShell'
                Write-FilePreview -Session $s -Text $script:preview | Should -Be 'written'
                $s
            }
            Mock Write-HostOscPacket { $true }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'restores settings.json and the palette once, however many exits ask' {
            $s = & $script:newSession
            $first  = Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $script:opened
            $t = [System.IO.File]::GetLastWriteTimeUtc($script:settingsPath)
            $second = Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $script:opened

            [System.IO.File]::GetLastWriteTimeUtc($script:settingsPath) | Should -Be $t `
                -Because 'a second write bumps the mtime of a file the user owns, and Windows Terminal reloads on it'
            Should -Invoke Write-HostOscPacket -Times 1 -Exactly -Because 'the terminal was already handed its colours back'
            $first  | Should -Be 'reverted'
            $second | Should -Be 'already'
            [System.IO.File]::ReadAllText($script:settingsPath) | Should -BeExactly $script:original
        }

        It 'records that it ran on the state the caller passed in' {
            $s = & $script:newSession
            $script:tuneState.Reverted | Should -BeFalse
            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $script:opened | Out-Null
            $script:tuneState.Reverted | Should -BeTrue
        }

        It 'writes no settings.json off Windows Terminal, and still reverts the palette' {
            Mock Write-SettingsAtomic { throw 'there is no settings.json to write off Windows Terminal' }
            Restore-TuneBaseLook -State $script:tuneState -Session $null -OpenedScheme $script:opened | Should -Be 'reverted'
            Should -Invoke Write-SettingsAtomic -Times 0 -Exactly
            Should -Invoke Write-HostOscPacket  -Times 1 -Exactly
        }

        It 'a fresh session reverts again -- the flag is per session, not global' {
            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session (& $script:newSession) -OpenedScheme $script:opened | Out-Null
            Restore-TuneBaseLook -State @{ Reverted = $false } -UseSettingsFile -Session (& $script:newSession) -OpenedScheme $script:opened |
                Should -Be 'reverted'
            Should -Invoke Write-HostOscPacket -Times 2 -Exactly
            [System.IO.File]::ReadAllText($script:settingsPath) | Should -BeExactly $script:original
        }

        It 'keeps an edit made while the tuner was open, and still hands the palette back, once' {
            $s = & $script:newSession
            $o = [System.IO.File]::ReadAllText($script:settingsPath) | ConvertFrom-Json
            $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
            [System.IO.File]::WriteAllText($script:settingsPath, ($o | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $null | Should -Be 'reverted'
            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $null | Should -Be 'already'
            $after = [System.IO.File]::ReadAllText($script:settingsPath) | ConvertFrom-Json
            $after.copyOnSelect | Should -BeTrue
            @($after.profiles.list)[0].colorScheme | Should -Be 'Campbell'
            $script:tuneState.SettingsRestore.Status | Should -Be 'merged'
            Should -Invoke Write-HostOscPacket -Times 1 -Exactly
        }

        It 'a settings.json that never took a preview is not touched, and not a failure' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:settingsPath -By tuner
            $t = [System.IO.File]::GetLastWriteTimeUtc($script:settingsPath)
            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $script:opened | Should -Be 'reverted'
            $script:tuneState.SettingsRestoreError | Should -BeNullOrEmpty
            [System.IO.File]::GetLastWriteTimeUtc($script:settingsPath) | Should -Be $t
        }

        It 'finishes the revert, and answers failed, when the put-back cannot be written' {
            $s = & $script:newSession
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw "Could not write ${Path}: denied" } -ParameterFilter { $Path -eq $script:settingsPath }

            $r = Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile -Session $s -OpenedScheme $script:opened
            $r | Should -Be 'failed'
            Should -Invoke Write-HostOscPacket -Times 1 -Exactly -Because 'the palette goes back whatever the file did'
            $script:tuneState.Reverted | Should -BeTrue
            ([string]$script:tuneState.SettingsRestoreError) | Should -Match 'denied'
            [System.IO.File]::ReadAllText($script:settingsPath) | Should -BeExactly $script:preview
        }
    }
}

Describe 'the tuner routes all three exits through it' {
    # The wiring half, which no test can drive: the key loop needs a console.
    # An AST shape assertion, like the ones tests/Picker-NonWT.Tests.ps1 and
    # tests/Get-RevertOscPacket.Tests.ps1 document for the same reason -- it
    # says nothing about the text of the function, only about which expressions
    # carry the decision.
    BeforeAll {
        $script:tunerAst = InModuleScope TerminalStyles {
            (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast
        }
    }

    It 'builds the revert in exactly one place' {
        $calls = @($script:tunerAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Restore-TuneBaseLook' }, $true))
        @($calls).Count | Should -Be 1 `
            -Because 'a second call site would carry a second state hashtable and lose the flag again'
    }

    It 'and every exit path invokes that one scriptblock' {
        # Escape, the aborted save, and the finally.
        $invocations = @($script:tunerAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and
            $n.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.CommandElements[0].VariablePath.UserPath -eq 'restoreBaseLook' }, $true))
        @($invocations).Count | Should -BeGreaterThan 2 `
            -Because 'Esc, an aborted save and the finally all have to undo the preview'
    }

    It 'reads what the revert answered on every exit, and guards the one in its finally' {
        $A = [System.Management.Automation.Language.Ast]
        $invocations = @($script:tunerAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and
            $n.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.CommandElements[0].VariablePath.UserPath -eq 'restoreBaseLook' }, $true))
        @($invocations).Count | Should -BeGreaterOrEqual 3 -Because 'a loop over none would pass'

        $inFinally = @()
        foreach ($c in $invocations) {
            # The status is read: the pipeline is the right-hand side of an
            # assignment, so nothing leaks to the command's output either.
            $c.Parent.Parent | Should -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst]) `
                -Because "every exit has to know whether the file went back ($($c.Extent.Text) at line $($c.Extent.StartLineNumber))"

            $p = $c.Parent; $tryOuter = $null; $tryInner = $null
            while ($p) {
                if ($p -is [System.Management.Automation.Language.TryStatementAst]) {
                    if ($p.Finally -and $c.Extent.StartOffset -ge $p.Finally.Extent.StartOffset -and
                        $c.Extent.EndOffset -le $p.Finally.Extent.EndOffset) { $tryOuter = $p; break }
                    if (-not $tryInner) { $tryInner = $p }
                }
                $p = $p.Parent
            }
            if ($tryOuter) { $inFinally += [pscustomobject]@{ Call = $c; Outer = $tryOuter; Guard = $tryInner } }
        }
        $inFinally.Count | Should -Be 1 -Because 'one call is the safety net in the finally'
        $inFinally[0].Guard | Should -Not -BeNullOrEmpty -Because 'a throw there would skip the title and the scratch cleanup'

        $title = @($inFinally[0].Outer.Finally.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Test-ShouldRestoreWindowTitle' }, $true))
        $title.Count | Should -Be 1
        $title[0].Extent.StartOffset | Should -BeLessThan $inFinally[0].Call.Extent.StartOffset `
            -Because 'the title goes back first, as in the picker'
    }
}
