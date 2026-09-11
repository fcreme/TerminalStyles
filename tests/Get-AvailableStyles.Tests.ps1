# Pester 5 tests for Get-AvailableStyles: the user+bundled style enumeration
# (user-wins dedup) shared by the picker, list, current, random, and dispatch.
# Guard test -- Get-AvailableStyles already exists; this locks its contract.
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

Describe 'Get-AvailableStyles' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            # Bundled: alpha, beta. User: beta (override), gamma (new).
            foreach ($n in 'alpha','beta') {
                $d = Join-Path $script:TStylesModuleRoot "styles\$n"
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), "{`"name`":`"$n`"}", [System.Text.UTF8Encoding]::new($false))
            }
            foreach ($n in 'beta','gamma') {
                $d = Join-Path $script:TStylesDataRoot "styles\$n"
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), "{`"name`":`"$n`"}", [System.Text.UTF8Encoding]::new($false))
            }
            # A user dir WITHOUT scheme.json must be ignored.
            New-Item -ItemType Directory -Path (Join-Path $script:TStylesDataRoot 'styles\noscheme') -Force | Out-Null
        }

        It 'returns the union of bundled + user styles, sorted by name' {
            (Get-AvailableStyles).Name | Should -Be @('alpha','beta','gamma')
        }
        It 'user style wins on name collision (beta resolves to the user dir)' {
            $beta = Get-AvailableStyles | Where-Object Name -eq 'beta'
            ($beta | Measure-Object).Count | Should -Be 1
            $beta.FullName | Should -BeLike (Join-Path $script:TStylesDataRoot '*beta*')
        }
        It 'ignores directories without a scheme.json' {
            (Get-AvailableStyles).Name | Should -Not -Contain 'noscheme'
        }
        It 'returns objects with Name and FullName (what the picker consumes)' {
            $s = Get-AvailableStyles | Select-Object -First 1
            $s.Name     | Should -Not -BeNullOrEmpty
            $s.FullName | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $s.FullName | Should -BeTrue
        }

        Context 'it admits exactly what Get-StyleDir resolves' {
            # Get-StyleDir is the contract: a name it resolves is one that
            # applies, tunes and deletes. Two classes of style did all three
            # while being absent from every enumeration -- so `tstyles list`
            # showed no row, `tstyles <name>` answered "Unknown command or
            # style", and the delete consent screen, which names the tuned
            # children that lose their deltas off this same call, left them out
            # while destroying their base.
            #
            #   .wip    a dot-prefixed name, hidden from Get-ChildItem on Unix
            #           without -Force. The tuner's own Save-As creates it:
            #           Test-StyleNameValid accepts a leading dot.
            #   dev[1]  a name carrying PowerShell wildcard characters, so the
            #           composed path was a PATTERN to Test-Path and matched
            #           nothing. Hand-dropped, which README invites.
            BeforeEach {
                # [System.IO], not New-Item: the fixture is a pair of names
                # PowerShell's own path handling is the thing that mangles, and
                # the test must not depend on how the provider reads a '['.
                foreach ($n in '.wip', 'dev[1]') {
                    $d = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $n
                    [System.IO.Directory]::CreateDirectory($d) | Out-Null
                    [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'),
                        "{`"name`":`"$n`"}", [System.Text.UTF8Encoding]::new($false))
                }
            }

            It 'lists a style whose name starts with a dot' {
                Get-StyleDir -StyleName '.wip' | Should -Not -BeNullOrEmpty `
                    -Because 'the fixture has to be resolvable or this case measures nothing'
                @((Get-AvailableStyles).Name) | Should -Contain '.wip'
            }

            It 'lists a style whose name contains wildcard characters' {
                Get-StyleDir -StyleName 'dev[1]' | Should -Not -BeNullOrEmpty `
                    -Because 'the fixture has to be resolvable or this case measures nothing'
                @((Get-AvailableStyles).Name) | Should -Contain 'dev[1]'
            }

            It 'names every user directory Get-StyleDir resolves, and no other' {
                # The invariant rather than two spellings of it. Read off the
                # filesystem with [System.IO] on purpose: Get-ChildItem is the
                # half under test, and Test-Path is the half that mangled the
                # bracketed name.
                $stylesDir = Join-Path $script:TStylesDataRoot 'styles'
                $onDisk = @([System.IO.Directory]::GetDirectories($stylesDir) |
                            ForEach-Object { [System.IO.Path]::GetFileName($_) })
                @($onDisk).Count | Should -Be 5 `
                    -Because 'beta, gamma, noscheme, .wip and dev[1] must all be on disk for the loop below to have teeth'

                $listed = @((Get-AvailableStyles).Name)
                foreach ($n in $onDisk) {
                    if (Get-StyleDir -StyleName $n) {
                        $listed | Should -Contain $n -Because "Get-StyleDir resolves '$n', so every listing must show it"
                    } else {
                        $listed | Should -Not -Contain $n -Because "nothing resolves '$n', so listing it would be a name that cannot be applied"
                    }
                }
            }
        }
    }
}
