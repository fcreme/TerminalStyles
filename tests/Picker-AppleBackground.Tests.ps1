# Pester 5 tests: the picker must deliver a style's background image on
# Terminal.app, the same as `tstyles <name>` does.
#
# The bug: on Terminal.app, `tstyles` + arrow + Enter applied colors and prompt,
# printed "Style applied: eva", and stopped. No profile written under
# <data-root>/profiles/, no mention that the style ships a background, no hint
# about how to see it. `tstyles eva` on the same terminal wrote the profile and
# said "This style ships a background image ... tstyles eva -NewWindow".
#
# -NewWindow made it worse: it is declared on Invoke-TerminalStyle's param block
# and was read only by the two apply paths, so `tstyles -NewWindow` was accepted
# without error and did nothing at all. CHANGELOG records the identical defect
# already fixed for `tstyles random`; the picker was the last place it survived.
#
# The picker branch's own comment claimed it staged state "exactly as
# Apply-StyleNonWT does" while omitting half of it, which is why the shape
# assertion at the bottom is against Apply-StyleNonWT rather than a literal.
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

Describe 'Publish-StyleBackgroundProfile' {
    # Tested directly rather than through the picker: the picker's non-WT branch
    # needs a real console and blocks on input, which is exactly why this half of
    # it went uncovered long enough to diverge from Apply-StyleNonWT.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock Get-StyleBundledBackground { '/tmp/does-not-matter.gif' }
            Mock New-AppleTerminalProfile { '/tmp/generated.terminal' }
            Mock Start-Process {}
        }

        It 'writes the profile on Terminal.app' {
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            Should -Invoke New-AppleTerminalProfile -Times 1 -Exactly
        }

        It 'tells the user how to see it when -NewWindow was not given' {
            # The whole point of writing it either way: the image cannot reach
            # the window the user is already in.
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            $out = $script:written -join "`n"
            $out | Should -Match 'ships a background image'
            $out | Should -Match 'tstyles eva -NewWindow'
        }

        It 'names the style the user actually picked in the hint' {
            Publish-StyleBackgroundProfile -StyleName 'tombraider' -StyleDir '/tmp/tr' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            ($script:written -join "`n") | Should -Match 'tstyles tombraider -NewWindow'
        }

        It 'opens the window instead of hinting when -NewWindow was given' {
            # Open-AppleTerminalProfile exists as a seam precisely so this test
            # does not shell out to `open` on the runner.
            Mock Open-AppleTerminalProfile {}
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' -NewWindow | Out-Null
            $out = $script:written -join "`n"
            $out | Should -Match 'Opening a new window'
            $out | Should -Not -Match 'ships a background image'
            Should -Invoke Open-AppleTerminalProfile -ParameterFilter {
                $Path -eq '/tmp/generated.terminal'
            } -Times 1 -Exactly
        }

        It 'reports a failure to open rather than throwing out of the apply' {
            Mock Open-AppleTerminalProfile { throw 'no such file' }
            { Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' -NewWindow } |
                Should -Not -Throw
            ($script:written -join "`n") | Should -Match 'Could not open the profile'
        }

        It 'does nothing on a terminal that cannot carry a background at all' {
            # VSCode reports BackgroundImage = $false. Writing a Terminal.app
            # profile there would be meaningless, and the fetch behind it is up
            # to four serial 10-second HTTP attempts.
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'VSCode' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
            Should -Not -Invoke Get-StyleBundledBackground
            @($script:written).Count | Should -Be 0
        }

        It 'does nothing on Windows Terminal, which carries its own background' {
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'WindowsTerminal' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
        }

        It 'stays quiet for a style that ships no background' {
            Mock Get-StyleBundledBackground { $null }
            Publish-StyleBackgroundProfile -StyleName 'sober' -StyleDir '/tmp/sober' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            Should -Not -Invoke New-AppleTerminalProfile
            @($script:written).Count | Should -Be 0
        }

        It 'says nothing when the profile could not be written' {
            # A hint pointing at a profile that does not exist is worse than
            # silence.
            Mock New-AppleTerminalProfile { $null }
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null
            @($script:written).Count | Should -Be 0
        }
    }
}

Describe 'both apply paths deliver the background' {
    InModuleScope TerminalStyles {

        It 'Apply-StyleNonWT goes through the shared helper' {
            (Get-Command Apply-StyleNonWT).ScriptBlock.ToString() |
                Should -Match 'Publish-StyleBackgroundProfile' `
                -Because 'it is the reference path; the picker mirrors it'
        }

        It 'the picker''s non-WT commit does the same, and honours -NewWindow' {
            # Asked of the AST so the assertion is about a real call with a real
            # argument, not about a string appearing somewhere in the function.
            $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $calls = @($fn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Publish-StyleBackgroundProfile' }, $true))
            @($calls).Count | Should -Be 1 `
                -Because 'the picker must write the profile exactly as tstyles <name> does'
            $calls[0].Extent.Text | Should -Match '-NewWindow:\$NewWindow' `
                -Because '`tstyles -NewWindow` was accepted in silence and did nothing'
        }

        It '-NewWindow reaches every path that declares it' {
            # The flag is on Invoke-TerminalStyle's param block, so every branch
            # that applies a style owes the user an answer for it. random was
            # fixed once, direct-apply was always right, the picker was not.
            $src = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
            $src | Should -Match 'Invoke-RandomStyle[\s\S]{0,300}?-NewWindow:\$NewWindow'
            $src | Should -Match 'Apply-StyleDirect[\s\S]{0,300}?-NewWindow:\$NewWindow'
            $src | Should -Match 'Publish-StyleBackgroundProfile[\s\S]{0,300}?-NewWindow:\$NewWindow'
        }
    }
}

# The notice must describe BOTH halves of the limit.
#
# It exists so a plain result is never a mystery, and it explained only WHERE
# the image appears -- never that it will not move. Every bundled background is
# an animated GIF, so "This style ships a background image ... to get it: tstyles
# <name> -NewWindow" read as a promise of the GIF. ConvertTo-AppleTerminalBackground
# then hands Terminal.app the first frame, because a profile pointing at a GIF
# renders blank with no error.
#
# Reported by a user who applied a style, ran -NewWindow as instructed, and
# asked why they had a PNG. The README says it (line 449); no runtime message
# anywhere did -- a grep of every Write-Host in lib/, tstyles.ps1 and
# terminals.ps1 found nothing about still-vs-animated.
Describe 'the background notice says it will not animate' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock New-AppleTerminalProfile { '/tmp/generated.terminal' }
            Mock Open-AppleTerminalProfile {}
        }

        It 'warns about the still frame in the hint' {
            Mock Get-StyleBundledBackground { '/tmp/eva/background.gif' }
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null

            $out = $script:written -join "`n"
            $out | Should -Match 'first frame'
            $out | Should -Match 'not the animation'
            $out | Should -Match 'ships a background image' -Because 'the original half must survive'
        }

        It 'warns about it on the -NewWindow path too' {
            # The path that actually opens the window is the one where the user
            # is about to look straight at a still image.
            Mock Get-StyleBundledBackground { '/tmp/eva/background.gif' }
            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir '/tmp/eva' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' `
                -NewWindow | Out-Null

            ($script:written -join "`n") | Should -Match "first frame"
        }

        It 'says nothing about animation for a style shipping a still image' {
            # A PNG loses nothing to Terminal.app, and claiming it does would be
            # this same defect pointed the other way.
            Mock Get-StyleBundledBackground { '/tmp/plain/background.png' }
            Publish-StyleBackgroundProfile -StyleName 'plain' -StyleDir '/tmp/plain' `
                -Scheme ([pscustomobject]@{ background = '#000000' }) -Kind 'AppleTerminal' | Out-Null

            $out = $script:written -join "`n"
            $out | Should -Not -Match 'first frame'
            $out | Should -Match 'ships a background image' -Because 'the new-window half still applies'
        }

        It 'matches what ConvertTo-AppleTerminalBackground actually converts' {
            # The notice and the conversion must agree on what counts as
            # animated, or one of them is lying. Both key on the .gif extension.
            $png = Join-Path $TestDrive 'b.png'
            [System.IO.File]::WriteAllText($png, 'x')
            ConvertTo-AppleTerminalBackground -Path $png | Should -Be $png `
                -Because 'a non-GIF is passed through untouched, so no frame is dropped'
        }
    }
}

# -NewWindow is an ACTION, and it performed none of it in silence.
#
# THE DEFECT. Publish-StyleBackgroundProfile bailed at
# `if (-not $bundledBg) { return $null }` with no output at all. The $null it
# read collapses three states Get-StyleBundledBackground can tell apart and does
# not report: the style genuinely ships no asset (marker kind 'absent'), the
# network could not be reached (kind 'unreachable'), and no marker at all.
#
# Nothing else covered for it. The apply's "<terminal> can't show: background
# image" notice is gated on `-not $caps.BackgroundImage`, and Terminal.app is the
# one terminal that CLAIMS BackgroundImage -- so on exactly this path that notice
# is suppressed by design. Measured on 0.8.28 with a fresh 'unreachable' marker
# in the cache:
#
#   returned                              : (null)
#   characters written to any stream      : 0
#   Open-AppleTerminalProfile invocations : 0
#
# and the whole command printed "Style applied: eva / Terminal: Terminal.app /
# Terminal.app can't show: tab color." -- no window, and not one word about the
# background, from the flag whose entire purpose is the background. It needs no
# stale marker either: the first apply of any style made offline takes the same
# path, and no bundled style ships a background.* on main.
Describe 'Publish-StyleBackgroundProfile -NewWindow when there is no image' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Data root sandboxed: Get-StyleCacheDir derives from it, and this
            # writes marker files. The style dir is sandboxed too, so the tiers
            # above the marker (a bundled background.*, a cached one, a tuned
            # style's base) are all genuinely empty.
            $script:TStylesDataRoot = $TestDrive
            $script:styleDir = Join-Path $TestDrive 'styles/eva'
            # Torn down explicitly, not trusted to $TestDrive: a marker or a
            # background.gif left by the previous test would decide this one's
            # answer, and the test that reads "no marker at all" would silently
            # be measuring the marker before it.
            foreach ($stale in @($script:styleDir, (Get-StyleCacheDir -StyleName 'eva'))) {
                if (Test-Path -LiteralPath $stale) {
                    Remove-Item -LiteralPath $stale -Recurse -Force
                }
            }
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null

            $script:written = [System.Collections.ArrayList]::new()
            Mock Write-Host { [void]$script:written.Add("$Object") }
            Mock New-AppleTerminalProfile { '/tmp/generated.terminal' }
            Mock Open-AppleTerminalProfile {}
            # A tripwire, not a stub: if the marker stops suppressing the probe
            # these tests must fail loudly rather than quietly reach the network
            # on a CI runner.
            Mock Invoke-WebRequest { throw 'the negative-cache marker must suppress the probe' }

            function script:Set-BackgroundMarker {
                param([Parameter(Mandatory)][string]$Kind)
                $cacheDir = Get-StyleCacheDir -StyleName 'eva'
                New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
                $marker = [pscustomobject]@{
                    schemaVersion = 1
                    kind          = $Kind
                    at            = [datetime]::UtcNow.ToString('o')
                }
                [System.IO.File]::WriteAllText((Join-Path $cacheDir '.no-background'),
                    ($marker | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
            }

            function script:Invoke-NewWindow {
                Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir $script:styleDir `
                    -Scheme ([pscustomobject]@{ background = '#000000' }) `
                    -Kind 'AppleTerminal' -NewWindow | Out-Null
                return ($script:written -join "`n")
            }
        }

        It 'says the image could not be downloaded when the network was unreachable' {
            script:Set-BackgroundMarker -Kind 'unreachable'

            $out = script:Invoke-NewWindow

            $out | Should -Not -BeNullOrEmpty `
                -Because '-NewWindow opened no window and said nothing at all'
            $out | Should -Match 'download'
            $out | Should -Match 'background image'
            $out | Should -Match 'tstyles eva -NewWindow' -Because 'it is worth retrying'
            Should -Not -Invoke Open-AppleTerminalProfile
        }

        It 'says the style ships none when the asset is genuinely absent' {
            script:Set-BackgroundMarker -Kind 'absent'

            $out = script:Invoke-NewWindow

            $out | Should -Not -BeNullOrEmpty
            $out | Should -Match 'ships no background image'
            Should -Not -Invoke Open-AppleTerminalProfile
        }

        It 'does not give the two states the same sentence' {
            # The point of reading the marker's kind at all. A single blanket
            # message would satisfy both tests above and tell a user with no
            # network to stop waiting for a style that has an image -- or send a
            # user whose style ships none back online for nothing.
            script:Set-BackgroundMarker -Kind 'absent'
            $absent = script:Invoke-NewWindow

            $script:written.Clear()
            script:Set-BackgroundMarker -Kind 'unreachable'
            $unreachable = script:Invoke-NewWindow

            $absent      | Should -Not -BeNullOrEmpty
            $unreachable | Should -Not -BeNullOrEmpty
            $unreachable | Should -Not -Be $absent
            $absent      | Should -Not -Match 'download'
        }

        It 'says something a third time when there is no marker to read' {
            # Neither answer is known: the cache dir could not be created or
            # written. Still an action that did not happen, so still a sentence.
            Mock Get-StyleBundledBackground { $null }

            $out = script:Invoke-NewWindow

            $out | Should -Not -BeNullOrEmpty
            $out | Should -Match 'Could not resolve'
            Should -Not -Invoke Open-AppleTerminalProfile
        }

        It 'stays silent about all of it when -NewWindow was not asked for' {
            # The boundary. Without the flag nothing was requested, and a style
            # with no image has nothing to announce -- the same reason the hint
            # is not printed either.
            script:Set-BackgroundMarker -Kind 'unreachable'

            Publish-StyleBackgroundProfile -StyleName 'eva' -StyleDir $script:styleDir `
                -Scheme ([pscustomobject]@{ background = '#000000' }) `
                -Kind 'AppleTerminal' | Out-Null

            @($script:written).Count | Should -Be 0
        }

        It 'speaks when the profile itself could not be written' {
            # The same promise one line further down, silent in the same way: the
            # image resolved, New-AppleTerminalProfile returned $null, and
            # -NewWindow opened nothing without a word.
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'background.gif'), 'GIF89a')
            Mock New-AppleTerminalProfile { $null }

            $out = script:Invoke-NewWindow

            $out | Should -Match 'Could not write'
            $out | Should -Match 'no new window was opened'
            Should -Not -Invoke Open-AppleTerminalProfile
        }

        It 'still opens the window when there IS an image' {
            # The counterweight: none of the new sentences may replace the thing
            # the flag is for.
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'background.gif'), 'GIF89a')

            $out = script:Invoke-NewWindow

            $out | Should -Match 'Opening a new window'
            $out | Should -Not -Match 'Could not'
            $out | Should -Not -Match 'ships no background image'
            Should -Invoke Open-AppleTerminalProfile -Times 1 -Exactly
        }
    }
}

# Get-StyleBackgroundAbsence is the reader that makes those three sentences
# possible: the kind was written into the marker and then thrown away at
# Get-StyleBundledBackground's return, which is how "no image" and "no network"
# became the same answer.
Describe 'Get-StyleBackgroundAbsence' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:styleDir = Join-Path $TestDrive 'styles/probe'
            New-Item -ItemType Directory -Force -Path $script:styleDir | Out-Null
            $script:cacheDir = Get-StyleCacheDir -StyleName 'probe'
            if (Test-Path -LiteralPath $script:cacheDir) {
                Remove-Item -LiteralPath $script:cacheDir -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $script:cacheDir | Out-Null

            function script:Write-Marker {
                param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
                [System.IO.File]::WriteAllText((Join-Path $script:cacheDir '.no-background'),
                    $Text, [System.Text.UTF8Encoding]::new($false))
            }
        }

        It 'reads <_> back off the marker' -ForEach @('absent', 'unreachable') {
            script:Write-Marker -Text ("{{`"schemaVersion`":1,`"kind`":`"{0}`",`"at`":`"{1}`"}}" -f
                $_, [datetime]::UtcNow.ToString('o'))
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be $_
        }

        It 'answers unknown when there is no marker at all' {
            Remove-Item -LiteralPath (Join-Path $script:cacheDir '.no-background') -Force -ErrorAction SilentlyContinue
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be 'unknown'
        }

        It 'answers unknown for the content-free marker releases up to 0.8.5 wrote' {
            # Inventing a reason from a marker that carries none would put a
            # sentence on screen that no measurement backs.
            script:Write-Marker -Text ''
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be 'unknown'
        }

        It 'answers unknown for a marker that is not JSON' {
            script:Write-Marker -Text '{not json at all'
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be 'unknown'
        }

        It 'answers unknown for a kind it does not recognise' {
            script:Write-Marker -Text '{"schemaVersion":1,"kind":"someday","at":"2026-01-01T00:00:00.0000000Z"}'
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be 'unknown'
        }

        It 'never touches the network' {
            Mock Invoke-WebRequest { throw 'this is a cache reading, not a probe' }
            script:Write-Marker -Text '{"schemaVersion":1,"kind":"absent","at":"2026-01-01T00:00:00.0000000Z"}'
            { Get-StyleBackgroundAbsence -StyleDir $script:styleDir } | Should -Not -Throw
            Should -Not -Invoke Invoke-WebRequest
        }

        It 'agrees with the kind Get-StyleBundledBackground actually writes' {
            # Driven through the shipped resolver rather than a hand-written
            # marker: a reader that agrees only with the fixture is not a reader.
            # A transport failure with no .Response is "not a 404", which is what
            # makes the result inconclusive.
            Remove-Item -LiteralPath (Join-Path $script:cacheDir '.no-background') -Force -ErrorAction SilentlyContinue
            Mock Invoke-WebRequest { throw [System.Net.WebException]::new('offline') }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            Get-StyleBackgroundAbsence -StyleDir $script:styleDir | Should -Be 'unreachable'
        }
    }
}
