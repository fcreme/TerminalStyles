# A one-time offer to install WezTerm -- the only terminal off Windows that
# animates a background GIF.
#
# Installing a GUI application is the largest thing this tool ever offers to do,
# so the gate is correspondingly strict and every condition is tested on its
# own. The offer is also recorded on a REFUSAL, because an offer that returns
# every run is not an offer.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
}

Describe 'Test-ShouldOfferWezTerm' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:yes = @{
                MarkerPresent = $false; Interactive = $true; Platform = 'MacOS'
                Kind = 'AppleTerminal'; AlreadyInstalled = $false; BrewPresent = $true
            }
        }

        It 'offers when every condition holds' {
            Test-ShouldOfferWezTerm @script:yes | Should -BeTrue
        }

        It 'declines on each condition alone' {
            # One at a time, so a gate that stopped checking one of them cannot
            # hide behind the others.
            $cases = @(
                @{ k = 'MarkerPresent';    v = $true;            why = 'it is asked once, ever' }
                @{ k = 'Interactive';      v = $false;           why = 'a question in a redirect is asked of nobody' }
                @{ k = 'Platform';         v = 'Linux';          why = 'the install route is a Homebrew cask' }
                @{ k = 'Platform';         v = 'Windows';        why = 'Windows Terminal already animates these' }
                @{ k = 'Kind';             v = 'WezTerm';        why = 'they are already running it' }
                @{ k = 'AlreadyInstalled'; v = $true;            why = 'it is already on the machine' }
                @{ k = 'BrewPresent';      v = $false;           why = 'there is nothing to offer without brew' }
            )
            foreach ($c in $cases) {
                $args = $script:yes.Clone()
                $args[$c.k] = $c.v
                Test-ShouldOfferWezTerm @args | Should -BeFalse -Because $c.why
            }
        }
    }
}

Describe 'Invoke-WezTermOfferFirstRun' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = Join-Path $TestDrive ('wz-' + [guid]::NewGuid().Guid.Substring(0, 8))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:marker = Join-Path $script:TStylesDataRoot '.wezterm-offered'

            # The BeforeEach opens every condition of the gate, so a test that
            # does not close one is asked the question -- and with the answer
            # check regressed, that is a real `brew install --cask wezterm` on
            # the macOS CI leg and on a contributor's Mac. This throw stops brew
            # but cannot fail a test, because the offer's own catch swallows it:
            # so every test that is asked and does not answer yes also asserts
            # the call count, and the three that answer yes mock it themselves.
            #
            # What the offer says goes into a list, with .Add(): `+=` inside a
            # mock body assigns a copy local to the mock, which is how a test
            # here once recorded into a variable nothing could read.
            $script:offerSaid = [System.Collections.ArrayList]::new()
            Mock Test-InteractiveConsole { $true }
            Mock Get-TStylesPlatform     { 'MacOS' }
            Mock Get-TerminalKind        { 'AppleTerminal' }
            Mock Test-WezTermInstalled   { $false }
            Mock Get-Command             { [pscustomobject]@{ Name = 'brew' } } -ParameterFilter { $Name -eq 'brew' }
            Mock Read-Host               { 'n' }
            Mock Write-Host              { [void]$script:offerSaid.Add("$Object") }
            Mock Install-WezTermViaBrew  { throw 'a test reached brew install --cask wezterm' }
        }

        It 'names the exact command before asking' {
            # Recorded into the same list as the question, so the order is the
            # assertion.
            Mock Read-Host { [void]$script:offerSaid.Add('READ-HOST ' + $Prompt); 'n' }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null

            $askedAt = -1; $namedAt = -1
            for ($i = 0; $i -lt $script:offerSaid.Count; $i++) {
                $line = [string]$script:offerSaid[$i]
                if ($askedAt -lt 0 -and $line.StartsWith('READ-HOST ', [System.StringComparison]::Ordinal)) { $askedAt = $i }
                if ($namedAt -lt 0 -and $line.Contains('brew install --cask wezterm')) { $namedAt = $i }
            }
            $askedAt | Should -BeGreaterOrEqual 0 -Because 'the question has to be asked for its order to mean anything'
            $namedAt | Should -BeGreaterOrEqual 0 -Because 'the offer has to name the command it would run'
            $namedAt | Should -BeLessThan $askedAt -Because 'the command is named before the question, not after the answer'
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It
            Should -Invoke Install-WezTermViaBrew -Times 0 -Exactly -Scope It
        }

        It 'installs nothing on a no' {
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It `
                -Because 'the gate was open, so the no is what stopped it'
            Should -Invoke Install-WezTermViaBrew -Times 0 -Exactly -Scope It
        }

        It 'installs nothing on a bare Enter, the [y/N] default' {
            Mock Read-Host { '' }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It
            Should -Invoke Install-WezTermViaBrew -Times 0 -Exactly -Scope It `
                -Because 'the capital N is the answer an empty line gives'
        }

        It 'records a refusal, so it is asked once and not every run' {
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Test-Path -LiteralPath $script:marker | Should -BeTrue `
                -Because 'an offer that comes back every run is a nag'

            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly -Scope It `
                -Because 'the second run must not ask again'
            Should -Invoke Install-WezTermViaBrew -Times 0 -Exactly -Scope It
        }

        It 'asks nothing, and records nothing, in a redirected session' {
            Mock Test-InteractiveConsole { $false }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 0 -Exactly -Scope It
            Test-Path -LiteralPath $script:marker | Should -BeFalse `
                -Because 'the one asking is still owed to a real console'
        }

        It 'says nothing at all to someone already in WezTerm' {
            Mock Get-TerminalKind { 'WezTerm' }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 0 -Exactly -Scope It
            $script:offerSaid.Count | Should -Be 0 `
                -Because 'not a line of the offer belongs on the screen of someone already running WezTerm'
        }

        It 'does not take the picker down when the install fails' {
            # The user asked to style their terminal. Whether Homebrew succeeded
            # is not a reason to stop doing that.
            Mock Read-Host { 'y' }
            Mock Install-WezTermViaBrew { throw 'brew exploded' }
            { Invoke-WezTermOfferFirstRun 6>&1 | Out-Null } | Should -Not -Throw
            Should -Invoke Install-WezTermViaBrew -Times 1 -Exactly -Scope It `
                -Because 'the failure path is only exercised if the install was actually attempted'
        }

        It 'says so when brew exits clean but installs nothing' {
            # brew can succeed having done nothing useful. Checking afterwards
            # beats trusting the exit code, and the user gets the command to run
            # by hand rather than a success message and no application.
            Mock Read-Host { 'y' }
            Mock Install-WezTermViaBrew { }
            Mock Test-WezTermInstalled { $false }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Install-WezTermViaBrew -Times 1 -Exactly -Scope It
            $said = $script:offerSaid -join "`n"
            $said.Contains('brew finished but WezTerm is not on this machine. Install it by hand:') |
                Should -BeTrue -Because 'a clean exit that installed nothing has to say so, and how to install it'
            $said.Contains('WezTerm installed.') |
                Should -BeFalse -Because 'there is no WezTerm to claim'
        }

        It 'installs when the answer is yes' {
            Mock Read-Host { 'y' }
            Mock Install-WezTermViaBrew { }
            Mock Test-WezTermInstalled { $false }
            Invoke-WezTermOfferFirstRun 6>&1 | Out-Null
            Should -Invoke Install-WezTermViaBrew -Times 1 -Exactly -Scope It
        }
    }
}

Describe 'the offer is wired in where it can be answered' {
    InModuleScope TerminalStyles {

        It 'runs above the picker, like the welcome and the font prompt' {
            # Below the Clear-Host the question would be wiped before it could
            # be read, and the answer would be given to a screen nobody saw.
            $ast = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $offsets = {
                param($name)
                @($ast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq $name }, $true) | ForEach-Object { $_.Extent.StartOffset })
            }
            $offer = & $offsets 'Invoke-WezTermOfferFirstRun'
            $clear = & $offsets 'Clear-Host'
            @($offer).Count | Should -Be 1
            $offer[0] | Should -BeLessThan ($clear | Measure-Object -Minimum).Minimum
        }
    }
}
