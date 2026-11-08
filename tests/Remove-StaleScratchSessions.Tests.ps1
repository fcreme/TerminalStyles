# Pester 5 tests for the sweep both live previews share: the creator's
# .create-preview and the tuner's .tune-preview each hold one session-<PID>
# per running preview, removed by a finally block a closed tab never reaches.
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

Describe 'Remove-StaleScratchSessions' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
        }

        It 'removes a dead session, keeps a live one, its own, and anything else' {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $engine = (Get-Process -Id $PID).Path
            $other = Start-Process -FilePath $engine -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -PassThru
            try {
                Get-Process -Id $other.Id -ErrorAction Stop | Should -Not -BeNullOrEmpty -Because 'the live session needs a live process'
                # A PID no process holds, checked rather than assumed.
                $dead = ((Get-Process | Measure-Object -Property Id -Maximum).Maximum + 7919)
                while (Get-Process -Id $dead -ErrorAction SilentlyContinue) { $dead++ }
                $stale = Join-Path $root ("session-{0}" -f $dead)
                $live = Join-Path $root ("session-{0}" -f $other.Id)
                $own = Join-Path $root ("session-{0}" -f $PID)
                $notSession = Join-Path $root 'not-a-session'
                foreach ($d in $stale, $live, $own, $notSession) {
                    [void][System.IO.Directory]::CreateDirectory((Join-Path $d 'eva'))
                    [System.IO.File]::WriteAllText((Join-Path (Join-Path $d 'eva') 'scheme.json'), '{}', $script:enc)
                }

                Remove-StaleScratchSessions -Root $root

                [System.IO.Directory]::Exists($stale) | Should -BeFalse -Because 'its process is gone'
                [System.IO.File]::Exists((Join-Path (Join-Path $live 'eva') 'scheme.json')) |
                    Should -BeTrue -Because 'a preview open in another tab keeps its session'
                [System.IO.Directory]::Exists($own) | Should -BeTrue -Because 'its own session is its finally block''s to remove'
                [System.IO.Directory]::Exists($notSession) | Should -BeTrue -Because 'only session-<PID> folders are a preview''s'
            } finally {
                Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue
            }
        }

        It 'does nothing, and does not throw, when the root does not exist' {
            $root = Join-Path $TestDrive 'never-made'
            { Remove-StaleScratchSessions -Root $root } | Should -Not -Throw
            [System.IO.Directory]::Exists($root) | Should -BeFalse
        }

        It 'is called by the tuner on .tune-preview before it makes its own session' {
            # The tuner past its console guards is a live session no test can
            # drive (see Invoke-TerminalStyleTune.Tests.ps1), so this reads the
            # AST: the call, its root, and that it comes before the session
            # directory is named. The creator's call is measured end to end in
            # Invoke-TerminalStyleCreate.Tests.ps1.
            $ast = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.Ast
            $calls = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Remove-StaleScratchSessions' }, $true))
            $calls.Count | Should -Be 1
            $calls[0].Extent.Text | Should -BeExactly 'Remove-StaleScratchSessions -Root $scratchRoot'
            $rootAssign = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$scratchRoot' }, $true))
            $rootAssign.Count | Should -Be 1
            $rootAssign[0].Right.Extent.Text | Should -BeExactly "Join-Path `$script:TStylesDataRoot '.tune-preview'"
            $sessionAssign = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq '$scratchSession' }, $true))
            $sessionAssign.Count | Should -Be 1
            $calls[0].Extent.StartOffset | Should -BeLessThan $sessionAssign[0].Extent.StartOffset
        }
    }
}
