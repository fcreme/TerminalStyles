# Pester 5 tests for `tstyles current`.
#
# THE DEFECT. Show-StyleList wraps its ReadAllText | ConvertFrom-Json |
# Get-SchemeSwatch in a try/catch, with the reason recorded in the code: a
# malformed scheme.json "used to throw here, mid-loop -- so `tstyles list`
# printed a raw .NET exception and then stopped". Show-CurrentStyle, the sibling
# function directly below it, ran the identical three statements with no guard at
# all -- two implementations of one rule, and this was the half that never
# learned it.
#
# It survived because the throwing branch is the one that draws the swatch, and
# that branch only runs when output is NOT redirected. Every CI leg runs
# redirected, so every test took the Write-Output path and never opened the file.
# Reproduced under a real pty on 0.8.28:
#
#   $ script -q /dev/null pwsh-preview -NoProfile -File m4e.ps1
#     IsOutputRedirected : False
#     Get-CurrentStyleName: broken
#     --- Show-CurrentStyle ---
#     THREW: System.ArgumentException :: Conversion from JSON failed with error:
#            Invalid character after parsing property name. Expected ':' but got:
#            j. Path '', line 1, position 6.
#
# while the guarded sibling printed "* broken  (unreadable scheme.json)".
#
# -OutputRedirected is a bound parameter for exactly the reason Apply-StyleNonWT
# has one: the .NET static cannot be mocked, so without a seam the arm that
# carries the bug is unreachable from any test on any leg.
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

Describe 'Show-CurrentStyle' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:said = [System.Collections.ArrayList]::new()

            $script:sDir = Join-Path $TestDrive 'styles/broken'
            New-Item -ItemType Directory -Force -Path $script:sDir | Out-Null

            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentStyleName { 'broken' }
            Mock Get-StyleDir { $script:sDir }
            Mock Write-Host { [void]$script:said.Add("$Object") }

            function script:Set-SchemeText([string]$Text) {
                [System.IO.File]::WriteAllText((Join-Path $script:sDir 'scheme.json'), $Text, $script:enc)
            }
        }

        It 'survives a malformed scheme.json instead of throwing a raw .NET error' {
            script:Set-SchemeText '{"name" johnny}'

            { Show-CurrentStyle -OutputRedirected $false } | Should -Not -Throw `
                -Because 'a read-only command must not throw System.ArgumentException at the user'
        }

        It 'still names the style it was asked about' {
            script:Set-SchemeText '{"name" johnny}'
            Show-CurrentStyle -OutputRedirected $false
            ($script:said -join "`n") | Should -Match 'broken' `
                -Because 'the name is the question the command was asked'
        }

        It 'says the same thing about it that tstyles list does' {
            # One condition must not acquire a second phrasing in the second
            # place that meets it. Both read the marker from the same function.
            script:Set-SchemeText '{"name" johnny}'
            Show-CurrentStyle -OutputRedirected $false
            ($script:said -join "`n") | Should -Match 'unreadable scheme\.json'
            (Get-UnreadableSchemeSwatch) | Should -Match 'unreadable scheme\.json'
        }

        It 'still draws the swatch for a scheme it can read' {
            # The counterweight: the guard must not cost the visual self-check
            # the interactive branch exists for.
            script:Set-SchemeText '{"name":"broken","background":"#0d1a12","foreground":"#e8f0e8"}'
            Show-CurrentStyle -OutputRedirected $false

            $text = $script:said -join "`n"
            $text | Should -Match 'broken'
            $text | Should -Not -Match 'unreadable'
            $text | Should -Match ([regex]::Escape("$([char]27)[")) -Because 'a swatch is escape sequences'
        }

        It 'prints just the name when the style ships no scheme.json' {
            # A file that is not there says nothing about being unreadable.
            Remove-Item -LiteralPath (Join-Path $script:sDir 'scheme.json') -Force -ErrorAction SilentlyContinue
            Show-CurrentStyle -OutputRedirected $false

            $text = $script:said -join "`n"
            $text | Should -Match 'broken'
            $text | Should -Not -Match 'unreadable'
        }

        It 'keeps the redirected branch scriptable, with no swatch and no file read' {
            # `tstyles current | grep ...` must keep getting the bare name on
            # stdout -- and must not be able to throw on the file either.
            script:Set-SchemeText '{"name" johnny}'
            $out = Show-CurrentStyle -OutputRedirected $true | Out-String
            $out.Trim() | Should -Be 'broken'
            @($script:said).Count | Should -Be 0
        }

        It 'reports no active style when there is none' {
            Mock Get-CurrentStyleName { $null }
            Show-CurrentStyle -OutputRedirected $false
            ($script:said -join "`n") | Should -Match 'no bundled style currently active'
        }

        It 'defaults -OutputRedirected to the console, so the seam changes nothing by itself' {
            # The parameter exists to be testable, not to change behaviour: with
            # nothing bound it must still read [Console]::IsOutputRedirected.
            $default = (Get-Command Show-CurrentStyle).Parameters['OutputRedirected'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $default | Should -Not -BeNullOrEmpty
            (Get-Command Show-CurrentStyle).ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'OutputRedirected' } |
                ForEach-Object { $_.DefaultValue.Extent.Text } |
                Should -Be '[Console]::IsOutputRedirected'
        }
    }
}
