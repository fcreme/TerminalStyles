# Pester 5 tests for the three plain subcommands and the module-load prompt
# dot-source -- code every user touches daily that had no coverage at all.
#
# Bugs pinned:
#   - `tstyles random` accepted -Target, -KeepPrompt and -NewWindow (they are on
#     the dispatcher's param block) and forwarded none of them, so
#     `tstyles random -KeepPrompt` replaced the prompt it promised to keep.
#   - `tstyles list` read and parsed every style's scheme.json with no guard, so
#     one malformed user-authored style threw mid-loop: a raw .NET exception
#     printed between rows and every style after it was hidden.
#   - a current-style.ps1 that will not parse -- a style profile with a syntax
#     error, a copy interrupted mid-write -- dumped a full ParserError with a
#     caret diagram into EVERY new shell tab. (It did not, as first reported,
#     prevent the module importing: verified under a pty, the import still
#     succeeds. One actionable warning is still better than a parse dump.)
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

Describe 'tstyles random forwards the flags it accepts' {
    InModuleScope TerminalStyles {
        BeforeEach {
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Get-CurrentStyleName { 'eva' }
            Mock Get-AvailableStyles {
                @([pscustomobject]@{ Name = 'forest'; FullName = 'x' })
            }
            Mock Apply-StyleDirect {}
        }

        It 'passes -KeepPrompt through' {
            Invoke-RandomStyle -KeepPrompt
            Should -Invoke Apply-StyleDirect -ParameterFilter { $KeepPrompt } -Times 1 -Exactly
        }

        It 'passes -Target through' {
            Invoke-RandomStyle -Target 'Ubuntu'
            Should -Invoke Apply-StyleDirect -ParameterFilter { $Target -eq 'Ubuntu' } -Times 1 -Exactly
        }

        It 'passes -NewWindow through' {
            Invoke-RandomStyle -NewWindow
            Should -Invoke Apply-StyleDirect -ParameterFilter { $NewWindow } -Times 1 -Exactly
        }

        It 'still excludes the currently active style' {
            Invoke-RandomStyle
            Should -Invoke Apply-StyleDirect -ParameterFilter { $StyleName -eq 'forest' } -Times 1 -Exactly
        }

        It 'says so rather than throwing when there is nothing else to pick' {
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'eva'; FullName = 'x' }) }
            { Invoke-RandomStyle } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'No other styles' }
            Should -Not -Invoke Apply-StyleDirect
        }

        It 'is wired up in the dispatcher with all three' {
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match "Invoke-RandomStyle -Target \`$Target -KeepPrompt:\`$KeepPrompt -NewWindow:\`$NewWindow"
        }
    }
}

Describe 'tstyles list survives a broken style' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesModuleRoot = $TestDrive
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentStyleName { $null }

            function script:New-FakeStyle {
                param([string]$Name, [string]$Scheme)
                $d = Join-Path (Join-Path $TestDrive 'styles') $Name
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), $Scheme,
                    [System.Text.UTF8Encoding]::new($false))
                return [pscustomobject]@{ Name = $Name; FullName = $d }
            }
        }

        It 'still lists the styles after a malformed one' {
            # The whole point: a bad folder costs its own row, not the listing.
            $good1 = script:New-FakeStyle -Name 'aaa' -Scheme '{"name":"aaa","background":"#101010"}'
            $bad   = script:New-FakeStyle -Name 'bbb' -Scheme '{not json at all'
            $good2 = script:New-FakeStyle -Name 'ccc' -Scheme '{"name":"ccc","background":"#202020"}'
            Mock Get-AvailableStyles { @($good1, $bad, $good2) }
            $written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$written.Add("$Object") }

            { Show-StyleList } | Should -Not -Throw
            ($written -join "`n") | Should -Match '\baaa\b'
            ($written -join "`n") | Should -Match '\bccc\b'
        }

        It 'marks the broken one rather than hiding it' {
            $bad = script:New-FakeStyle -Name 'bbb' -Scheme '{not json at all'
            Mock Get-AvailableStyles { @($bad) }
            $written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$written.Add("$Object") }

            Show-StyleList
            ($written -join "`n") | Should -Match 'unreadable scheme\.json'
        }

        It 'survives a style whose scheme.json is missing entirely' {
            $d = Join-Path (Join-Path $TestDrive 'styles') 'ddd'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Mock Get-AvailableStyles { @([pscustomobject]@{ Name = 'ddd'; FullName = $d }) }
            Mock Write-Host {}
            { Show-StyleList } | Should -Not -Throw
        }
    }
}

Describe 'a broken current-style.ps1 does not dump a parser error into every tab' {

    It 'the module-load dot-source is guarded' {
        # Verified under a pty: unguarded, a style profile with a syntax error
        # printed a full ParserError with a caret diagram on every new shell tab.
        # The import itself still succeeded -- this was never the brick it was
        # first reported as -- but a parse dump per tab is its own problem.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $src = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tstyles.ps1'),
            [System.Text.UTF8Encoding]::new($false))
        # The final dot-source, inside the shell-startup auto-load block.
        $tail = $src.Substring($src.LastIndexOf('$TStylesNoAutoLoad'))
        $tail | Should -Match 'try\s*\{\s*\.\s*\$script:TStylesCurrent'
        $tail | Should -Match 'Write-Warning'
    }

    It 'the warning names a way out' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $src = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tstyles.ps1'),
            [System.Text.UTF8Encoding]::new($false))
        $tail = $src.Substring($src.LastIndexOf('$TStylesNoAutoLoad'))
        $tail | Should -Match "tstyles reset"
    }
}

Describe 'tstyles reset honours a profile name given positionally' {
    InModuleScope TerminalStyles {

        It 'passes the positional name through as the target' {
            # `tstyles reset Ubuntu` puts "Ubuntu" in $SubArg, the second
            # positional. The dispatcher read only -Target, so the name was
            # silently ignored and the AUTO-DETECTED profile was reset instead --
            # the wrong profile, reported as a success.
            Mock Reset-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'reset' -SubArg 'Ubuntu'
            Should -Invoke Reset-StyleDirect -ParameterFilter { $Target -eq 'Ubuntu' } -Times 1 -Exactly
        }

        It 'lets an explicit -Target win over the positional' {
            Mock Reset-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'reset' -SubArg 'Ubuntu' -Target 'PowerShell'
            Should -Invoke Reset-StyleDirect -ParameterFilter { $Target -eq 'PowerShell' } -Times 1 -Exactly
        }

        It 'still auto-detects when neither is given' {
            Mock Reset-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'reset'
            Should -Invoke Reset-StyleDirect -ParameterFilter { -not $Target } -Times 1 -Exactly
        }
    }
}

Describe 'every dispatched subcommand is discoverable' {
    InModuleScope TerminalStyles {

        It "offers 'ls' in tab-completion, since it is dispatched" {
            # `ls` has been an accepted alias for `list` while being absent from
            # the completer -- so it worked only if you already knew it existed.
            #
            # The completer list is registered at TOP LEVEL, after
            # Invoke-TerminalStyle ends, so it is not in that function's
            # scriptblock. Read the file.
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $file = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tstyles.ps1'),
                [System.Text.UTF8Encoding]::new($false))
            (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() | Should -Match "\`$Arg -eq 'ls'"
            $completer = [regex]::Match($file, '(?s)\$subcommands = @\((.*?)\)').Value
            $completer | Should -Not -BeNullOrEmpty
            $completer | Should -Match "'ls'"
        }
    }
}

Describe 'the font download is bounded' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Put the module root back. An earlier Describe in this file points
            # $script:TStylesModuleRoot at its TestDrive, and that assignment
            # persists across Describe blocks -- so Get-FontCatalog went looking
            # for fonts.json under a temp directory. Only one test file in the
            # suite saves and restores these; the rest rely on the next file's
            # Import-Module -Force, which does not help within a file.
            $script:TStylesModuleRoot = Split-Path $PSScriptRoot -Parent
        }

        It 'passes a timeout, like every other fetch in the project' {
            $src = (Get-Command Resolve-FontPackage).ScriptBlock.ToString()
            $src | Should -Match '-TimeoutSec \d+'
        }

        It 'decides the direct-font case from the URL, not the local filename' {
            # Downloads always land in 'download.bin', so taking the extension
            # from the local path made the direct .ttf/.otf branch unreachable
            # for anything actually fetched. Every catalogue entry today is a
            # .zip, so nothing was broken -- it was waiting for the first font
            # published as a bare .ttf.
            $src = (Get-Command Resolve-FontPackage).ScriptBlock.ToString()
            $src | Should -Match '\$extSource'
            $src | Should -Not -Match 'GetExtension\(\$archive\)'
        }

        It 'still resolves a .zip catalogue entry to its listed files' {
            # The change must not have cost the path all six shipped fonts use.
            $catalog = @(Get-FontCatalog)
            $catalog.Count | Should -BeGreaterThan 0
            foreach ($f in $catalog) {
                "$($f.url)" | Should -Match '\.zip$'
                @($f.files).Count | Should -BeGreaterThan 0
            }
        }
    }
}
