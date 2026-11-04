# Pester 5 tests: which Windows Terminal profiles get the style's prompt.
#
# Three copies of one check decided it -- the module's apply path, the picker
# and apply.ps1 -- and all three matched only `pwsh.exe` or `powershell.exe`
# somewhere in the commandline. A profile whose commandline is `pwsh` or
# `powershell`, which Windows Terminal runs fine, took the colours and printed
# "Style applied", and never got the style's prompt or banner; apply.ps1 said
# it was "not a PowerShell profile". And the match was anywhere in the line, so
# `cmd.exe /k pwsh.exe` counted as PowerShell.
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

Describe 'Test-WTProfileRunsPowerShell' {
    InModuleScope TerminalStyles {
        It 'accepts <Cmd>' -ForEach @(
            @{ Cmd = 'pwsh' }
            @{ Cmd = 'powershell' }
            @{ Cmd = 'pwsh.exe' }
            @{ Cmd = 'powershell.exe' }
            @{ Cmd = 'PWSH.EXE' }
            @{ Cmd = 'pwsh -NoLogo' }
            @{ Cmd = '  pwsh.exe -NoLogo' }
            @{ Cmd = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo' }
            @{ Cmd = '"C:\Program Files\PowerShell\7\pwsh"' }
            @{ Cmd = 'C:\Program Files\PowerShell\7\pwsh.exe -NoLogo' }
            @{ Cmd = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
            @{ Cmd = 'C:/tools/pwsh/pwsh.exe' }
        ) {
            Test-WTProfileRunsPowerShell -Entry ([pscustomobject]@{ commandline = $Cmd }) | Should -BeTrue
        }

        It 'refuses <Cmd>' -ForEach @(
            @{ Cmd = 'cmd.exe /k pwsh-help' }
            @{ Cmd = 'cmd.exe /k pwsh.exe' }
            @{ Cmd = 'wsl.exe -d Ubuntu' }
            @{ Cmd = 'pwsh-preview' }
            @{ Cmd = 'notpwsh.exe' }
            @{ Cmd = '"C:\tools\pwsh\bash.exe"' }
            @{ Cmd = 'C:\pwsh.exe.d\bash.exe' }
            @{ Cmd = 'ssh.exe host pwsh' }
            @{ Cmd = '' }
        ) {
            Test-WTProfileRunsPowerShell -Entry ([pscustomobject]@{ commandline = $Cmd }) | Should -BeFalse
        }

        It 'accepts the PowerShell Core dynamic profile, which has no commandline' {
            Test-WTProfileRunsPowerShell -Entry ([pscustomobject]@{ source = 'Windows.Terminal.PowershellCore' }) |
                Should -BeTrue
        }

        It 'refuses a profile with neither, and no profile at all' {
            Test-WTProfileRunsPowerShell -Entry ([pscustomobject]@{ name = 'Ubuntu'; source = 'Windows.Terminal.Wsl' }) |
                Should -BeFalse
            Test-WTProfileRunsPowerShell -Entry $null | Should -BeFalse
        }
    }
}

Describe 'every apply path asks Test-WTProfileRunsPowerShell' {
    BeforeAll {
        $script:callsIn = {
            param([string]$Path)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Test-WTProfileRunsPowerShell' }, $true))
        }
    }

    It '<Label> calls it and keeps no copy of the old match' -ForEach @(
        @{ File = 'lib/applystyle.ps1'; Label = 'the module apply path' }
        @{ File = 'tstyles.ps1';        Label = 'the picker' }
        @{ File = 'apply.ps1';          Label = 'apply.ps1' }
    ) {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) $File
        @(& $script:callsIn $path).Count | Should -BeGreaterThan 0
        [System.IO.File]::ReadAllText($path) | Should -Not -Match 'pwsh\\\.exe\\b' `
            -Because 'a second copy of the rule is how the three drifted'
        [System.IO.File]::ReadAllText($path) | Should -Not -Match "-eq 'Windows\.Terminal\.PowershellCore'"
    }
}
