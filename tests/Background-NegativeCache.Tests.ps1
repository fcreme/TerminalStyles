# Pester 5 tests for the background negative cache and the 404-vs-unreachable
# distinction behind it.
#
# The bug: Get-StyleBundledBackground wrote a content-free `.no-background`
# marker on ANY fetch failure -- a real 404, a DNS failure, four 10-second
# timeouts, all the same -- and nothing ever deleted it. One apply while offline
# permanently cost that style its background on that machine, and the only
# documented way to clear it was `tstyles uninstall -DeleteData`, which could not
# be invoked at all (the dispatcher had no such parameter).
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

Describe 'Test-HttpNotFound' {
    InModuleScope TerminalStyles {

        It 'recognises a 404 as a definitive answer' {
            $err = [pscustomobject]@{
                Exception = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 404 } }
            }
            Test-HttpNotFound -ErrorRecord $err | Should -BeTrue
        }

        It 'does not treat a transport failure as a 404' {
            # A DNS failure / timeout / offline network has no .Response at all.
            # Conflating the two is what made the negative cache permanent.
            $err = [pscustomobject]@{ Exception = [pscustomobject]@{ Response = $null } }
            Test-HttpNotFound -ErrorRecord $err | Should -BeFalse
        }

        It 'does not treat a server error as a 404' {
            $err = [pscustomobject]@{
                Exception = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 503 } }
            }
            Test-HttpNotFound -ErrorRecord $err | Should -BeFalse
        }

        It 'returns false rather than throwing on a shape it does not recognise' {
            # It runs inside a catch block; throwing here would replace a
            # recoverable fetch failure with an unhandled error.
            Test-HttpNotFound -ErrorRecord $null | Should -BeFalse
            Test-HttpNotFound -ErrorRecord 'not an error record' | Should -BeFalse
        }
    }
}

Describe 'Test-BackgroundProbeSuppressed' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:now = [datetime]::SpecifyKind([datetime]'2026-08-25T12:00:00', [System.DateTimeKind]::Utc)
            function script:Marker {
                param([string]$Kind, [datetime]$At)
                ([pscustomobject]@{ schemaVersion = 1; kind = $Kind; at = $At.ToString('o') } |
                    ConvertTo-Json -Compress)
            }
        }

        It 'suppresses a fresh "absent" result' {
            $m = script:Marker -Kind 'absent' -At $script:now.AddDays(-3)
            Test-BackgroundProbeSuppressed -MarkerText $m -Now $script:now | Should -BeTrue
        }

        It 'lets an "absent" result expire after 30 days' {
            # The gifs branch is updated independently of releases, so a style
            # CAN gain an asset after we recorded that it had none.
            $m = script:Marker -Kind 'absent' -At $script:now.AddDays(-31)
            Test-BackgroundProbeSuppressed -MarkerText $m -Now $script:now | Should -BeFalse
        }

        It 'suppresses an "unreachable" result only briefly' {
            # NOTE: this case is also the canary for the UTC-parsing bug below,
            # but only on a machine whose offset is not zero. It caught a real
            # defect on a UTC+2 dev box and passed clean under TZ=UTC, which is
            # what CI runs -- hence the source-shape test that follows.
            $m = script:Marker -Kind 'unreachable' -At $script:now.AddMinutes(-10)
            Test-BackgroundProbeSuppressed -MarkerText $m -Now $script:now | Should -BeTrue
        }

        It 'parses the stamp as UTC rather than as local time' {
            # [datetime]::TryParse with RoundtripKind consumes the trailing Z but
            # returns Kind=Unspecified, so a later .ToUniversalTime() re-reads a
            # UTC stamp as local and shifts every TTL by the machine's offset --
            # widening or narrowing the window depending on where the user lives,
            # and doing nothing at all at UTC+0. No behavioural assertion can see
            # that on a UTC runner, so pin the shape instead.
            # Matched on the qualified enum form, not the bare word: the comment
            # in the function names RoundtripKind to explain why it is wrong, and
            # ScriptBlock.ToString() includes comments.
            $src = (Get-Command Test-BackgroundProbeSuppressed).ScriptBlock.ToString()
            $src | Should -Match 'DateTimeStyles\]::AdjustToUniversal'
            $src | Should -Match 'DateTimeStyles\]::AssumeUniversal'
            $src | Should -Not -Match 'DateTimeStyles\]::RoundtripKind'
        }

        It 'retries an "unreachable" result after an hour' {
            # Long enough that repeated applies while offline do not each pay
            # four 10-second timeouts; short enough to self-heal on reconnect.
            $m = script:Marker -Kind 'unreachable' -At $script:now.AddHours(-2)
            Test-BackgroundProbeSuppressed -MarkerText $m -Now $script:now | Should -BeFalse
        }

        It 'treats the legacy content-free marker as expired' {
            # This is the upgrade path: every machine poisoned by <= 0.8.5 has an
            # empty marker. Re-probing once replaces it with one that can expire.
            Test-BackgroundProbeSuppressed -MarkerText ''    -Now $script:now | Should -BeFalse
            Test-BackgroundProbeSuppressed -MarkerText '   ' -Now $script:now | Should -BeFalse
        }

        It 'treats a corrupt or partial marker as expired rather than throwing' {
            Test-BackgroundProbeSuppressed -MarkerText '{not json'                 -Now $script:now | Should -BeFalse
            Test-BackgroundProbeSuppressed -MarkerText '{"kind":"absent"}'         -Now $script:now | Should -BeFalse
            Test-BackgroundProbeSuppressed -MarkerText '{"at":"2026-08-25T00:00:00Z"}' -Now $script:now | Should -BeFalse
            Test-BackgroundProbeSuppressed -MarkerText '{"kind":"absent","at":"nonsense"}' -Now $script:now | Should -BeFalse
        }
    }
}

Describe 'Get-StyleBundledBackground records WHY it found nothing' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            $script:styleDir = Join-Path $TestDrive 'styles/probefake'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"probefake"}', [System.Text.UTF8Encoding]::new($false))

            # TestDrive survives between It blocks in the same Describe, so the
            # marker one case writes is still standing -- and still fresh -- when
            # the next runs, which short-circuits its fetch before the mocks can
            # do anything. Clear the cache so each case probes from nothing.
            $script:cacheDir = Get-StyleCacheDir -StyleName 'probefake'
            if (Test-Path -LiteralPath $script:cacheDir) {
                Remove-Item -LiteralPath $script:cacheDir -Recurse -Force
            }
        }

        It 'marks a genuine 404 as "absent"' {
            Mock Invoke-WebRequest {
                $ex = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 404 } }
                throw ([System.Management.Automation.ErrorRecord]::new(
                    [Exception]::new('404'), 'x', 'ObjectNotFound', $ex))
            }
            # The thrown record's .Exception is a plain Exception, so route the
            # decision through the seam instead: 404 => definitely absent.
            Mock Test-HttpNotFound { $true }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            $marker = Join-Path (Get-StyleCacheDir -StyleName 'probefake') '.no-background'
            Test-Path -LiteralPath $marker | Should -BeTrue
            (Get-Content $marker -Raw | ConvertFrom-Json).kind | Should -Be 'absent'
        }

        It 'marks an unreachable network as "unreachable", not "absent"' {
            Mock Invoke-WebRequest { throw 'no such host' }
            Mock Test-HttpNotFound { $false }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            $marker = Join-Path (Get-StyleCacheDir -StyleName 'probefake') '.no-background'
            (Get-Content $marker -Raw | ConvertFrom-Json).kind | Should -Be 'unreachable'
        }

        It 'is inconclusive if even ONE extension could not be reached' {
            # Three clean 404s and one timeout is not proof of absence.
            $script:call = 0
            Mock Invoke-WebRequest { throw 'boom' }
            Mock Test-HttpNotFound { $script:call++; return ($script:call -lt 4) }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            $marker = Join-Path (Get-StyleCacheDir -StyleName 'probefake') '.no-background'
            (Get-Content $marker -Raw | ConvertFrom-Json).kind | Should -Be 'unreachable'
        }

        It 'does not go near the network while a fresh marker stands' {
            $cache = Get-StyleCacheDir -StyleName 'probefake'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $cache '.no-background'),
                ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } |
                    ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false))
            Mock Invoke-WebRequest { throw 'the fetch must not run while a fresh marker stands' }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 're-probes when the standing marker is the legacy empty one' {
            $cache = Get-StyleCacheDir -StyleName 'probefake'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $cache '.no-background') -Force | Out-Null
            Mock Invoke-WebRequest { throw 'boom' }
            Mock Test-HttpNotFound { $true }

            Get-StyleBundledBackground -StyleDir $script:styleDir | Should -BeNullOrEmpty
            Should -Invoke Invoke-WebRequest -Times 4 -Exactly   # one per extension
            (Get-Content (Join-Path $cache '.no-background') -Raw | ConvertFrom-Json).kind |
                Should -Be 'absent'
        }
    }
}

Describe 'tstyles uninstall -DeleteData is reachable' {

    It 'is accepted by the exported command' {
        # It was documented in the help data and three times in the README while
        # the dispatcher's param block had no such switch, so PowerShell rejected
        # it outright -- and it is the only documented way to clear a poisoned
        # background cache.
        (Get-Command Invoke-TerminalStyle).Parameters.Keys | Should -Contain 'DeleteData'
    }

    It 'is threaded through to the uninstall implementation' {
        $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString()
        $fn | Should -Match 'Invoke-TerminalStylesUninstall\s+-DeleteData:\$DeleteData'
    }
}

Describe 'a fetch cannot leave a truncated cache entry' {
    InModuleScope TerminalStyles {

        It 'the synchronous fetch downloads to a .part and renames' {
            # Every reader treats a file at the cache path as a complete entry
            # and nothing revalidates it, so a partial write is permanent. The
            # catch cleans up after a network error, but a Ctrl+C or killed
            # process never reaches it. Matches the picker prefetch's approach.
            $src = (Get-Command Get-StyleBundledBackground).ScriptBlock.ToString()
            # Prefix only -- see the note in Picker-ShellStateStaging: the
            # synchronous and prefetch writers must NOT share a temp name.
            $src | Should -Match '\$part = "\$local\.part'
            $src | Should -Match '-OutFile \$part'
            $src | Should -Match 'Move-Item -LiteralPath \$part -Destination \$local -Force'
        }

        It 'never writes the download straight to the cache path' {
            $src = (Get-Command Get-StyleBundledBackground).ScriptBlock.ToString()
            $src | Should -Not -Match '-OutFile \$local\b'
        }

        It 'still returns the final path, not the .part' {
            $src = (Get-Command Get-StyleBundledBackground).ScriptBlock.ToString()
            $src | Should -Match 'return \$local'
            $src | Should -Not -Match 'return \$part'
        }
    }
}
