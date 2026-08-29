# Pester 5 tests: a destructive command must REFUSE, not assume, when nobody
# can answer its confirmation prompt.
#
# THE MECHANISM, because it is not what anyone assumed. Read-Host at EOF does
# not return $null -- it returns AutomationNull, which PowerShell treats as an
# EMPTY COLLECTION in a binary operator. Measured:
#
#     $ans -notmatch '^(?i)y'   ->  System.Object[] {}  ->  falsy
#     $ans -match    '^(?i)n'   ->  System.Object[] {}  ->  falsy
#     "$ans" -notmatch '^(?i)y' ->  $true               (the cast fixes it)
#
# So BOTH prompt polarities took the act branch. A "[y/N]" prompt looks like it
# fails safe and does not. `tstyles uninstall < /dev/null` ran a complete
# uninstall unattended; with -DeleteData it would have removed the data root
# including the user's own authored and tuned styles.
#
# Note for anyone extending this file: `Mock Read-Host { $null }` does NOT
# reproduce the bug -- a real $null behaves correctly. `Mock Read-Host { }`
# does, because an empty scriptblock yields AutomationNull.
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

Describe 'Test-InteractiveConsole' {
    InModuleScope TerminalStyles {
        # Driven entirely through its seams, so these cases are identical on a
        # developer's attached terminal and on all four CI legs. The .NET
        # statics behind the defaults cannot be mocked, which is exactly why
        # this predicate exists as a function.
        It 'is true only with a console on both ends: <case>' -ForEach @(
            @{ case = 'console both ends'; ui = $true;  inR = $false; outR = $false; want = $true }
            @{ case = 'stdin redirected';  ui = $true;  inR = $true;  outR = $false; want = $false }
            @{ case = 'stdout redirected'; ui = $true;  inR = $false; outR = $true;  want = $false }
            @{ case = 'both redirected';   ui = $true;  inR = $true;  outR = $true;  want = $false }
            @{ case = 'no user session';   ui = $false; inR = $false; outR = $false; want = $false }
        ) {
            Test-InteractiveConsole -UserInteractive $ui -InputRedirected $inR -OutputRedirected $outR |
                Should -Be $want
        }

        It 'counts a redirected STDOUT, which UserInteractive alone never did' {
            # install.ps1 guarded on [Environment]::UserInteractive, which is
            # $true on .NET Core/Unix always and $true in any Windows console
            # process regardless of redirection -- so it never fired for the
            # case it was written for.
            Test-InteractiveConsole -UserInteractive $true -InputRedirected $false -OutputRedirected $true |
                Should -BeFalse -Because 'a question printed into a capture file cannot be answered'
        }
    }
}

Describe 'Confirm-Action' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host {} }

        It 'refuses without even asking when there is no console' {
            Mock Test-InteractiveConsole { $false }
            Mock Read-Host { throw 'must not prompt when nobody can answer' }

            Confirm-Action -Question 'Continue? [y/N]' | Should -BeFalse
            Should -Not -Invoke Read-Host
        }

        It 'says why it refused, and how to proceed on purpose' {
            Mock Test-InteractiveConsole { $false }
            Confirm-Action -Question 'Continue? [y/N]' -Consequence 'deletes everything' | Out-Null

            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'Refusing to continue' }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match '-Yes' }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'deletes everything' }
        }

        It '-Yes proceeds without a console and without prompting' {
            Mock Test-InteractiveConsole { $false }
            Mock Read-Host { throw 'must not prompt when consent was pre-granted' }

            Confirm-Action -Question 'Continue? [y/N]' -Yes | Should -BeTrue
            Should -Not -Invoke Read-Host
        }

        It 'treats an EOF answer as NO even if the console guard is bypassed' {
            # The belt to the guard's braces. An empty scriptblock returns
            # AutomationNull, which is what Read-Host really yields at EOF --
            # `Mock Read-Host { $null }` would NOT reproduce this.
            Mock Test-InteractiveConsole { $true }
            Mock Read-Host { }

            Confirm-Action -Question 'Continue? [y/N]' | Should -BeFalse `
                -Because 'an unanswered question is not consent, whichever way the prompt is worded'
        }

        It 'answers <answer> as <expected>' -ForEach @(
            @{ answer = 'y';   expected = $true }
            @{ answer = 'Y';   expected = $true }
            @{ answer = 'yes'; expected = $true }
            @{ answer = 'n';   expected = $false }
            @{ answer = 'N';   expected = $false }
            @{ answer = '';    expected = $false }
            @{ answer = ' ';   expected = $false }
        ) {
            Mock Test-InteractiveConsole { $true }
            Mock Read-Host { $answer }.GetNewClosure()
            Confirm-Action -Question 'Continue? [y/N]' | Should -Be $expected
        }
    }
}

Describe 'the destructive commands route their consent through the gate' {
    InModuleScope TerminalStyles {

        It 'uninstall refuses when nobody can answer, and destroys nothing' {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'styles/mine') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $root 'styles/mine/tune.json'), '{"base":"eva"}')
            [System.IO.File]::WriteAllText((Join-Path $root '.installed-files'), "styles/mine`n")

            Mock Test-InteractiveConsole { $false }
            Mock Write-Host {}
            # Anything that would actually destroy something fails the test.
            Mock Remove-Item { throw 'uninstall must not remove anything without consent' }
            # Only where it exists. Uninstall-PSResource ships with
            # PSResourceGet, which is pwsh 7+; on Windows PowerShell 5.1 Pester's
            # Mock itself throws CommandNotFoundException, so an unconditional
            # mock fails the test on the one engine it was meant to protect.
            # Remove-Item above is the assertion that matters either way.
            if (Get-Command Uninstall-PSResource -ErrorAction SilentlyContinue) {
                Mock Uninstall-PSResource { throw 'uninstall must not touch the module without consent' }
            }

            $saved = $script:TStylesDataRoot
            try {
                $script:TStylesDataRoot = $root
                { Invoke-TerminalStylesUninstall } | Should -Not -Throw
            } finally { $script:TStylesDataRoot = $saved }

            Should -Not -Invoke Remove-Item
            Test-Path -LiteralPath (Join-Path $root 'styles/mine/tune.json') | Should -BeTrue `
                -Because "a user's tuned style must survive a command nobody confirmed"
        }

        It 'register refuses when nobody can answer, and writes no profile' {
            $prof = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
            [System.IO.File]::WriteAllText($prof, "# my own profile`n")

            Mock Test-InteractiveConsole { $false }
            Mock Write-Host {}

            $target = [pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $prof; Exists = $true; HasLoader = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target)

            [System.IO.File]::ReadAllText($prof) | Should -Be "# my own profile`n" `
                -Because 'the loader must not be written into a profile nobody agreed to change'
        }

        It 'register still writes when consent is pre-granted' {
            # The other direction: refusing must not break automation that means it.
            $prof = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
            [System.IO.File]::WriteAllText($prof, "# my own profile`n")

            Mock Test-InteractiveConsole { $false }
            Mock Write-Host {}

            $target = [pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $prof; Exists = $true; HasLoader = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            [System.IO.File]::ReadAllText($prof) | Should -Match 'TerminalStyles BEGIN'
        }
    }
}

Describe 'no consent prompt is left hand-rolled' {
    # The lint that keeps the class closed. The project wrote this idea four
    # different ways and one of them was wrong; a fifth spelling appearing in a
    # future edit is exactly how that happens again.
    It 'no Read-Host result is compared without being cast first' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $files = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
            Where-Object { $_.FullName -notmatch '[\\/](tests|out|docs)[\\/]' }

        $files.Count | Should -BeGreaterThan 5 -Because 'the scan must actually be scanning something'

        $offenders = @()
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            # Variables assigned from a BARE Read-Host -- the right-hand side is
            # the command itself, so the value is whatever Read-Host returned,
            # AutomationNull included.
            #
            # Deliberately NOT a text match on "Read-Host": that also catches
            # `$a = "$(Read-Host ...)"`, which is the FIX. Keying on the AST
            # shape distinguishes the raw command from an already-cast one, so
            # the lint cannot flag correct code and push someone into
            # suppressing it.
            $assigned = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Right -is [System.Management.Automation.Language.PipelineAst] -and
                $n.Right.PipelineElements.Count -eq 1 -and
                $n.Right.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst] -and
                "$($n.Right.PipelineElements[0].GetCommandName())" -eq 'Read-Host' }, $true) |
                ForEach-Object { "$($_.Left.Extent.Text)".TrimStart('$') })

            foreach ($v in ($assigned | Sort-Object -Unique)) {
                # ...compared with -match/-notmatch without a surrounding cast.
                $bad = @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                    $n.Operator -in @('Imatch', 'Inotmatch', 'Cmatch', 'Cnotmatch') -and
                    "$($n.Left.Extent.Text)" -eq "`$$v" }, $true))
                foreach ($b in $bad) {
                    $offenders += "$($f.Name):$($b.Extent.StartLineNumber)  $($b.Extent.Text)"
                }
            }
        }

        $offenders -join "`n" | Should -BeNullOrEmpty -Because @'
a Read-Host result compared bare is falsy in BOTH directions at EOF, so the
prompt acts instead of cancelling. Cast it ("$ans" -match ...) or route the
question through Confirm-Action.
'@
    }
}
