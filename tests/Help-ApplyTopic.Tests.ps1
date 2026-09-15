# Pester 5 tests: `tstyles <style>` -- the command this tool exists for -- is
# documented, and every flag the apply path accepts is named somewhere in the
# help.
#
# THE DEFECT THIS EXISTS FOR. `tstyles help` had a topic for all fourteen
# subcommands and none for applying a style. Measured on 0.8.27, rendering the
# overview plus every topic detail and regexing the flags back out:
#
#   topics = list, current, random, reset, tune, delete, font, register,
#            shell-init, shell-remove, update, profiles, uninstall, help
#   an 'apply' / '<style>' topic = False
#   > tstyles help apply
#   No help topic 'apply'.
#   flags mentioned anywhere in the rendered help: -Clean -DeleteData
#                                                  -NewWindow -Target
#   -KeepPrompt      in help text = False
#   -BackgroundImage in help text = False
#
# while the arm that applies a style forwards four of Invoke-TerminalStyle's
# parameters:
#
#   Apply-StyleDirect -StyleName $Arg -Target $Target `
#       -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
#       -KeepPrompt:$KeepPrompt -NewWindow:$NewWindow
#
# So -KeepPrompt -- the flag for every Oh My Posh and Starship user, and the one
# thing standing between a style and their own prompt -- could only be found by
# reading the source, and -BackgroundImage "" (the only way to turn a background
# OFF) was documented nowhere at all.
#
# The drift guard in tests/Get-TerminalStyleHelpData.Tests.ps1 could not see
# this: it compares topic names against $script:TStylesSubcommands in both
# directions and never looks at a parameter. `tstyles <style>` is not a
# subcommand -- the dispatcher falls through every arm and matches a style name
# -- so a mode with no dispatch token was invisible to a guard built on tokens.
#
# The second test below is the one that stops it recurring: it takes the
# forwarded parameters from the AST of the arm itself, so a flag added there
# without a line of help fails the build. A hand-typed list here would just be
# the third copy, and would drift the same way.
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

Describe 'the command tstyles is for is in its own help' {
    InModuleScope TerminalStyles {
        BeforeAll {
            # Everything `tstyles help` can print: the overview plus every
            # topic's detail. Rendered, not read off the data structure -- a
            # Detail line that never reaches the screen is not help.
            # -Width, so a flag name cannot be folded across a line by a
            # narrow console and read as absent.
            $rendered = (Show-TerminalStyleHelp 6>&1 | Out-String -Width 500)
            foreach ($topic in (Get-TerminalStyleHelpData).Name) {
                $rendered += (Show-TerminalStyleHelp -Command $topic 6>&1 | Out-String -Width 500)
            }
            $script:RenderedHelp = $rendered
        }

        It 'answers `tstyles help apply`' {
            $out = Show-TerminalStyleHelp -Command 'apply' 6>&1 | Out-String
            $out | Should -Not -Match 'No help topic' `
                -Because 'the tool''s primary command must be reachable from its own help'
            $out | Should -Match '<style>'
            $out | Should -Match 'EXAMPLES'
        }

        It 'names every parameter the style-apply arm forwards' {
            # From the AST of the dispatcher, not a list typed here.
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $repoRoot 'tstyles.ps1'), [ref]$null, [ref]$errors)
            @($errors).Count | Should -Be 0 -Because 'tstyles.ps1 must parse'

            $fn = @($ast.FindAll({ param($n)
                ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
                ($n.Name -eq 'Invoke-TerminalStyle') }, $true)) | Select-Object -First 1
            $fn | Should -Not -BeNullOrEmpty -Because 'the dispatcher must be found'

            $declared = @($fn.Body.ParamBlock.Parameters |
                          ForEach-Object { $_.Name.VariablePath.UserPath })
            $declared | Should -Contain 'KeepPrompt' -Because 'the flag exists, whatever the help says'

            $calls = @($fn.FindAll({ param($n)
                ($n -is [System.Management.Automation.Language.CommandAst]) -and
                ($n.GetCommandName() -eq 'Apply-StyleDirect') }, $true))
            @($calls).Count | Should -BeGreaterThan 0 -Because 'an empty list would assert nothing'

            # Every variable handed to that call that is also one of this
            # command's own parameters. $bgProvided and the like are locals and
            # drop out on their own.
            #
            # $Arg and $SubArg are the two POSITIONALS, and the help documents
            # them as `<style>` rather than by parameter name -- that is what
            # `tstyles eva` is. Asserted rather than assumed, just below.
            $positional = @('Arg', 'SubArg')
            $forwarded = @($calls |
                ForEach-Object {
                    $_.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
                } |
                ForEach-Object { $_.VariablePath.UserPath } |
                Sort-Object -Unique |
                Where-Object { $_ -in $declared } |
                Where-Object { $_ -notin $positional })

            @($forwarded).Count | Should -BeGreaterThan 2 `
                -Because 'the apply path forwards -Target, -BackgroundImage, -KeepPrompt and -NewWindow'

            foreach ($flag in $forwarded) {
                $script:RenderedHelp | Should -Match ([regex]::Escape("-$flag")) `
                    -Because "`tstyles <style> -$flag` works, so the help has to say so"
            }

            $script:RenderedHelp | Should -Match '<style>' `
                -Because 'the positional the other two parameters carry is documented by shape'
        }

        It 'names the two flags that were documented nowhere' {
            # Spelled out because they are the measurement: both were False on
            # 0.8.27, and -BackgroundImage '' is the only way to turn a
            # background off -- a thing nothing else in the tool says.
            $script:RenderedHelp | Should -Match '-KeepPrompt'
            $script:RenderedHelp | Should -Match '-BackgroundImage'
        }

        It 'puts the apply line in the overview COMMANDS block' {
            # The line a user actually reads. It used to be a literal typed
            # beside the loop that prints every other command, which is how the
            # primary command ended up listed but undocumented.
            $out = (Show-TerminalStyleHelp 6>&1 | Out-String -Width 500)
            $line = ($out -split "`r?`n" | Where-Object { $_ -match '^\s+<style>' } | Select-Object -First 1)
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match '-KeepPrompt'
        }
    }
}
