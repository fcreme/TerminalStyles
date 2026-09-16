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
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:tuneState = @{ Reverted = $false }
            $script:opened    = [pscustomobject]@{
                background = '#0a0006'; foreground = '#ffe8e8'; cursorColor = '#ff3d5a'
            }
            # A path under $TestDrive even though the write is mocked: if the
            # mock is ever dropped, this fails loudly in a sandbox instead of
            # quietly rewriting something real.
            $script:settingsPath = Join-Path $TestDrive 'settings.json'
        }

        It 'restores settings.json and the palette once, however many exits ask' {
            Mock Write-SettingsAtomic {}
            Mock Write-HostOscPacket { $true }

            # Escape, then the finally behind it -- the sequence a cancel runs.
            $first = Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile `
                -SettingsPath $script:settingsPath -OriginalJson '{ "x": 1 }' -OpenedScheme $script:opened
            $second = Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile `
                -SettingsPath $script:settingsPath -OriginalJson '{ "x": 1 }' -OpenedScheme $script:opened

            # The counts first: they are the defect, and an assertion that
            # throws earlier would hide them.
            Should -Invoke Write-SettingsAtomic -Times 1 -Exactly `
                -Because "a second byte-identical write bumps the mtime of a file the user owns, and Windows Terminal reloads on it"
            Should -Invoke Write-HostOscPacket  -Times 1 -Exactly `
                -Because 'the terminal was already handed its colours back'

            $first  | Should -Be 'reverted'
            $second | Should -Be 'already' `
                -Because 'there was nothing left to put back, and saying so is not the same as doing it again'
        }

        It 'records that it ran on the state the caller passed in' {
            # The flag has to live in the CALLER's hashtable: the tuner invokes
            # this from inside scriptblocks, and a plain variable assigned there
            # lands in the scriptblock's own child scope and is never seen again
            # -- which is the same reason the picker keeps $pickerState.
            Mock Write-SettingsAtomic {}
            Mock Write-HostOscPacket { $true }

            $script:tuneState.Reverted | Should -BeFalse
            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile `
                -SettingsPath $script:settingsPath -OriginalJson '{}' -OpenedScheme $script:opened | Out-Null
            $script:tuneState.Reverted | Should -BeTrue
        }

        It 'writes no settings.json off Windows Terminal, and still reverts the palette' {
            # There is no settings.json to restore there; the OSC packet is the
            # whole revert.
            Mock Write-SettingsAtomic { throw 'there is no settings.json to write off Windows Terminal' }
            Mock Write-HostOscPacket { $true }

            Restore-TuneBaseLook -State $script:tuneState -SettingsPath $null -OriginalJson $null `
                -OpenedScheme $script:opened | Should -Be 'reverted'
            Should -Invoke Write-SettingsAtomic -Times 0 -Exactly
            Should -Invoke Write-HostOscPacket  -Times 1 -Exactly
        }

        It 'a fresh session reverts again -- the flag is per session, not global' {
            Mock Write-SettingsAtomic {}
            Mock Write-HostOscPacket { $true }

            Restore-TuneBaseLook -State $script:tuneState -UseSettingsFile `
                -SettingsPath $script:settingsPath -OriginalJson '{}' -OpenedScheme $script:opened | Out-Null
            Restore-TuneBaseLook -State @{ Reverted = $false } -UseSettingsFile `
                -SettingsPath $script:settingsPath -OriginalJson '{}' -OpenedScheme $script:opened |
                Should -Be 'reverted'
            Should -Invoke Write-SettingsAtomic -Times 2 -Exactly
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
}
