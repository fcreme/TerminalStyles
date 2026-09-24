# Until `tstyles show`, the only ways to see a style were to APPLY it, or to
# open the picker and arrow to it. Both change what is applied until you back
# out, and neither answers "what is lain like" from a prompt.
#
# The whole promise of this command is "look without committing", so the thing
# worth testing hardest is that it commits nothing: no settings file, no
# profile, no current-style record, and the terminal put back on every path
# including a failing one.
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

Describe 'Invoke-TerminalStyleShow' {
    InModuleScope TerminalStyles {

        # No $script: sink here. GetNewClosure binds the block to the scope
        # that made it, and under InModuleScope that is the MODULE's -- where
        # a $script: variable the test set is $null. A plain local captured by
        # value works because a List is a reference: the closure and the test
        # see the same object. Same trap the font picker's draw block hit.
        BeforeAll { $script:Osc = "$([char]27)]11;" }

        It 'puts the terminal back, last of all' {
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-TerminalStyleShow -Name 'koholint' -Interactive $true `
                -ReadKey { } -Write { param($l) $painted.Add($l) }.GetNewClosure()
            $packets = @($painted | Where-Object { $_ -match [regex]::Escape($script:Osc) })
            $packets.Count | Should -Be 2 -Because 'one to paint it, one to put it back'
            $painted[-1] | Should -Match ([regex]::Escape($script:Osc)) `
                -Because 'the restore must be the last thing written'
        }

        It 'puts the terminal back even when the preview throws' {
            # The one outcome this command cannot have is leaving someone in a
            # palette they did not choose, with no record of it anywhere.
            $painted = [System.Collections.Generic.List[string]]::new()
            $sink = { param($l) $painted.Add($l) }.GetNewClosure()
            { Invoke-TerminalStyleShow -Name 'koholint' -Interactive $true `
                -ReadKey { throw 'interrupted' } -Write $sink } | Should -Throw
            $painted[-1] | Should -Match ([regex]::Escape($script:Osc))
        }

        It 'paints nothing where no one can end it' {
            # Non-interactive: there is no keypress coming, and painting a
            # terminal nobody is watching and never putting it back is worse
            # than not painting.
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-TerminalStyleShow -Name 'koholint' -Interactive $false `
                -Write { param($l) $painted.Add($l) }.GetNewClosure()
            @($painted | Where-Object { $_ -match [regex]::Escape($script:Osc) }) |
                Should -BeNullOrEmpty
            ($painted -join "`n") | Should -Match 'koholint'
        }

        It 'changes nothing that outlives it' {
            # The load-bearing assertion. Every writer this project has is a
            # candidate for "and then it also did this".
            # Every writer this project has. CLAUDE.md names three config
            # writers -- the Windows Terminal settings merge, the Terminal.app
            # profile, the WezTerm Lua -- and the state on top of them is the
            # current-style record and the shell staging.
            Mock -CommandName Invoke-TerminalStyle -MockWith { }
            Mock -CommandName Set-CurrentStyleRecord -MockWith { }
            Mock -CommandName Clear-CurrentStyleRecord -MockWith { }
            Mock -CommandName Merge-StyleIntoSettings -MockWith { }
            Mock -CommandName New-AppleTerminalProfile -MockWith { }
            Mock -CommandName Sync-ShellRuntime -MockWith { 'ok' }
            Mock -CommandName Set-ShellStyleState -MockWith { 'ok' }
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-TerminalStyleShow -Name 'lain' -Interactive $true -ReadKey { } `
                -Write { param($l) $painted.Add($l) }.GetNewClosure()
            Should -Invoke Invoke-TerminalStyle -Times 0
            Should -Invoke Set-CurrentStyleRecord -Times 0
            Should -Invoke Clear-CurrentStyleRecord -Times 0
            Should -Invoke Merge-StyleIntoSettings -Times 0
            Should -Invoke New-AppleTerminalProfile -Times 0
            Should -Invoke Sync-ShellRuntime -Times 0
            Should -Invoke Set-ShellStyleState -Times 0
        }

        It 'names what it could not find, and what it could have' {
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-TerminalStyleShow -Name 'definitely-not-a-style' -Interactive $true `
                -ReadKey { throw 'must not wait for a key' } `
                -Write { param($l) $painted.Add($l) }.GetNewClosure()
            $out = $painted -join "`n"
            $out | Should -Match "definitely-not-a-style"
            $out | Should -Match 'umbrella' -Because 'a rejection should say what was possible'
        }

        It 'asks for a name rather than guessing one' {
            $painted = [System.Collections.Generic.List[string]]::new()
            Invoke-TerminalStyleShow -Interactive $true -ReadKey { throw 'must not wait' } `
                -Write { param($l) $painted.Add($l) }.GetNewClosure()
            ($painted -join "`n") | Should -Match 'Usage: tstyles show'
        }
    }
}

Describe 'Get-StyleShowLines' {
    InModuleScope TerminalStyles {

        BeforeAll {
            $script:Dir = Get-StyleDir -StyleName 'umbrella'
            $script:Scheme = Get-Content (Join-Path $script:Dir 'scheme.json') -Raw | ConvertFrom-Json
        }

        It 'says what the preview does not cover' {
            # `show` writes nothing, so a background, font and cursor shape are
            # not in what you see -- and on Windows Terminal those are most of
            # a style. Saying so is the difference between a preview and a
            # misrepresentation.
            $lines = Get-StyleShowLines -Name 'umbrella' -Scheme $script:Scheme `
                        -CapabilityNote '  Colours only: no background, font or cursor shape.'
            ($lines -join "`n") | Should -Match 'Colours only'
        }

        It 'shows the description and the quote the picker shows' {
            $lines = Get-StyleShowLines -Name 'umbrella' -Scheme $script:Scheme `
                        -Meta (Get-StyleMeta -StyleDir $script:Dir)
            $out = $lines -join "`n"
            $out | Should -Match 'Resident-Evil'
            $out | Should -Match 'Umbrella Corporation'
        }

        It 'marks the style you are already on' {
            $on  = (Get-StyleShowLines -Name 'umbrella' -Scheme $script:Scheme -IsCurrent $true) -join "`n"
            $off = (Get-StyleShowLines -Name 'umbrella' -Scheme $script:Scheme -IsCurrent $false) -join "`n"
            $on  | Should -Match 'currently applied'
            $off | Should -Not -Match 'currently applied'
        }
    }
}

Describe 'Get-StyleShowSample' {
    InModuleScope TerminalStyles {

        It 'paints the sample in the scheme''s own colours' {
            $scheme = Get-Content (Join-Path (Get-StyleDir -StyleName 'phosphor') 'scheme.json') -Raw | ConvertFrom-Json
            $line = Get-StyleShowSample -Scheme $scheme
            # phosphor's brightGreen is #33ff5e -> rgb(51,255,94)
            $line | Should -Match '38;2;51;255;94'
            $line | Should -Match 'function'
        }

        It 'degrades to plain text for a slot the scheme does not carry' {
            # A hand-authored style is only required to have background and
            # foreground. The sample must not throw on the rest.
            $bare = [pscustomobject]@{ background = '#000000'; foreground = '#ffffff' }
            $line = Get-StyleShowSample -Scheme $bare
            $line | Should -Match 'function'
            $line | Should -Match 'Get-Thing'
        }

        It 'asks the project''s one question about what counts as a colour' {
            # ConvertTo-NormalHex accepts #rgb shorthand. A second opinion here
            # is what froze a shorthand slot in the tuner once.
            $short = [pscustomobject]@{ foreground = '#fff'; brightGreen = '#0f0' }
            $line = Get-StyleShowSample -Scheme $short
            $line | Should -Match '38;2;0;255;0' -Because '#0f0 is a colour'
        }
    }
}
