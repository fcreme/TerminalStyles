# A cached background was returned unconditionally and never revalidated, so
# replacing an image on the gifs branch reached exactly the people who had
# never applied that style. Anyone who had was pinned to whatever they
# downloaded the first time, for good.
#
# The NEGATIVE cache right beside it already had two carefully-reasoned
# lifetimes, with a comment saying why: "the gifs branch is updated
# independently of releases, so a style CAN gain an asset later." Every word of
# that applies to a style whose asset CHANGED. Only the 404 path got it.
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

Describe 'Test-BackgroundRefreshDue' {
    InModuleScope TerminalStyles {

        BeforeAll { $script:Now = [datetime]::Parse('2026-09-21T12:00:00Z').ToUniversalTime() }

        It 'checks a background it has never checked' {
            Test-BackgroundRefreshDue -MarkerText '' -Now $script:Now | Should -BeTrue
            Test-BackgroundRefreshDue -MarkerText $null -Now $script:Now | Should -BeTrue
        }

        It 'treats a marker it cannot read as due' {
            # A marker this tool cannot parse must never be the reason it stops
            # checking -- that is how releases up to 0.8.5 lost backgrounds to a
            # content-free file that never expired.
            foreach ($junk in 'not json', '{}', '{"kind":"checked"}', '{"at":"2026-09-20T00:00:00Z"}', '{"kind":"checked","at":"banana"}') {
                Test-BackgroundRefreshDue -MarkerText $junk -Now $script:Now |
                    Should -BeTrue -Because "'$junk' says nothing usable"
            }
        }

        It 'leaves a freshly checked asset alone' {
            $m = '{"kind":"checked","at":"2026-09-20T12:00:00Z"}'   # a day old
            Test-BackgroundRefreshDue -MarkerText $m -Now $script:Now | Should -BeFalse
        }

        It 'rechecks a fortnight later' {
            # Now is 2026-09-21T12:00Z, so these are 14d1h old and 12d23h old.
            Test-BackgroundRefreshDue -MarkerText '{"kind":"checked","at":"2026-09-07T11:00:00Z"}' -Now $script:Now |
                Should -BeTrue
            Test-BackgroundRefreshDue -MarkerText '{"kind":"checked","at":"2026-09-08T13:00:00Z"}' -Now $script:Now |
                Should -BeFalse
        }

        It 'retries an unreachable check within the hour, not the fortnight' {
            # A spell offline must not pin the image for two weeks, and must not
            # make every apply pay a timeout either.
            Test-BackgroundRefreshDue -MarkerText '{"kind":"unreachable","at":"2026-09-21T11:50:00Z"}' -Now $script:Now |
                Should -BeFalse
            Test-BackgroundRefreshDue -MarkerText '{"kind":"unreachable","at":"2026-09-21T10:30:00Z"}' -Now $script:Now |
                Should -BeTrue
        }

        It 'reads the stamp as UTC rather than shifting it by the local offset' {
            # RoundtripKind consumes the trailing Z and hands back
            # Kind=Unspecified, which silently widens or narrows every TTL by
            # the machine's offset. The negative cache was fixed for this once.
            $m = '{"kind":"checked","at":"2026-09-21T11:00:00Z"}'
            Test-BackgroundRefreshDue -MarkerText $m -Now $script:Now | Should -BeFalse
        }
    }
}

Describe 'Test-BackgroundChanged' {
    InModuleScope TerminalStyles {

        It 'trusts an etag over a length' {
            # Two different images can share a byte count; an etag is the server
            # saying what it has.
            Test-BackgroundChanged -LocalEtag '"a"' -RemoteEtag '"b"' -LocalLength 100 -RemoteLength 100 |
                Should -BeTrue
            Test-BackgroundChanged -LocalEtag '"a"' -RemoteEtag '"a"' -LocalLength 100 -RemoteLength 900 |
                Should -BeFalse
        }

        It 'falls back to the length when there is no etag' {
            Test-BackgroundChanged -LocalLength 2896327 -RemoteLength 3787104 | Should -BeTrue
            Test-BackgroundChanged -LocalLength 2896327 -RemoteLength 2896327 | Should -BeFalse
        }

        It 'keeps what it has when there is nothing to compare' {
            # A wrong "changed" costs a download of an image the user already
            # has -- every time, forever, because nothing would ever match.
            Test-BackgroundChanged -LocalEtag '' -RemoteEtag '' -LocalLength 0 -RemoteLength 0 |
                Should -BeFalse
            Test-BackgroundChanged -LocalLength 500 -RemoteLength 0 | Should -BeFalse
        }
    }
}

Describe 'Update-CachedBackground' {
    InModuleScope TerminalStyles {

        BeforeEach {
            $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("bgref-" + [Guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
            $script:Img = Join-Path $script:Dir 'background.gif'
            [System.IO.File]::WriteAllBytes($script:Img, (1..100 | ForEach-Object { [byte]7 }))
            $script:Marker = Join-Path $script:Dir '.background-checked'
            $script:Now = [datetime]::Parse('2026-09-21T12:00:00Z').ToUniversalTime()
            $script:Calls = [System.Collections.Generic.List[string]]::new()
        }
        AfterEach {
            if (Test-Path -LiteralPath $script:Dir) {
                Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'does not touch the network when the check is not due' {
            [System.IO.File]::WriteAllText($script:Marker, '{"kind":"checked","at":"2026-09-21T11:00:00Z"}')
            $web = { param($u,$m,$o) $script:Calls.Add("$m"); throw 'should not be called' }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            $r | Should -Be $script:Img
            $script:Calls | Should -BeNullOrEmpty
        }

        It 'downloads a replacement when the server has a different one' {
            $web = {
                param($u, $m, $o)
                $script:Calls.Add("$m")
                if ($m -eq 'Head') {
                    return [pscustomobject]@{ Headers = @{ 'Content-Length' = '4242'; 'ETag' = '"new"' } }
                }
                [System.IO.File]::WriteAllBytes($o, (1..4242 | ForEach-Object { [byte]9 }))
            }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            $r | Should -Be $script:Img
            (Get-Item $script:Img).Length | Should -Be 4242 -Because 'the new image replaced the old'
            $script:Calls | Should -Be @('Head', 'Get')
            (Get-Content $script:Marker -Raw) | Should -Match 'checked'
        }

        It 'downloads nothing when the server has the same one' {
            $web = {
                param($u, $m, $o)
                $script:Calls.Add("$m")
                [pscustomobject]@{ Headers = @{ 'Content-Length' = '100' } }
            }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            $r | Should -Be $script:Img
            (Get-Item $script:Img).Length | Should -Be 100
            $script:Calls | Should -Be @('Head') -Because 'a matching length settles it'
        }

        It 'keeps the image it has when the network fails' {
            # Losing a background to a flaky connection would be a worse bug
            # than the staleness this fixes.
            $web = { param($u,$m,$o) $script:Calls.Add("$m"); throw 'no route to host' }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            $r | Should -Be $script:Img
            (Get-Item $script:Img).Length | Should -Be 100
            (Get-Content $script:Marker -Raw) | Should -Match 'unreachable'
        }

        It 'keeps the image it has when the replacement download fails midway' {
            $web = {
                param($u, $m, $o)
                if ($m -eq 'Head') { return [pscustomobject]@{ Headers = @{ 'Content-Length' = '4242' } } }
                throw 'connection reset'
            }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            # The RETURN value, not just the file. An earlier version of this
            # test checked only that the bytes on disk survived, so a build that
            # answered $null here -- handing the caller "no background" while a
            # perfectly good one sat next to it -- passed.
            $r | Should -Be $script:Img
            (Get-Item $script:Img).Length | Should -Be 100 -Because 'the old image is still the good one'
            (Get-Content $script:Marker -Raw) | Should -Match 'unreachable'
            (Get-ChildItem $script:Dir -Filter '*.part-refresh') | Should -BeNullOrEmpty -Because 'the temp is cleaned up'
        }

        It 'leaves no half-written image where a reader would find it' {
            $web = {
                param($u, $m, $o)
                if ($m -eq 'Head') { return [pscustomobject]@{ Headers = @{ 'Content-Length' = '4242' } } }
                [System.IO.File]::WriteAllBytes($o, @())      # answered with nothing
            }
            $r = Update-CachedBackground -CachePath $script:Img -StyleName 'umbrella' `
                    -CacheDir $script:Dir -WebRequest $web -Now $script:Now
            $r | Should -Be $script:Img
            (Get-Item $script:Img).Length | Should -Be 100
        }
    }
}

Describe 'Get-StyleBundledBackground' {
    InModuleScope TerminalStyles {

        BeforeEach {
            $script:Sty = Join-Path ([System.IO.Path]::GetTempPath()) ("bgsty-" + [Guid]::NewGuid())
            $script:Cch = Join-Path ([System.IO.Path]::GetTempPath()) ("bgcch-" + [Guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:Sty -Force | Out-Null
            New-Item -ItemType Directory -Path $script:Cch -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $script:Cch 'background.gif'), (1..10 | ForEach-Object { [byte]1 }))
            Mock -CommandName Get-StyleCacheDir -MockWith { $script:Cch }
            Mock -CommandName Update-CachedBackground -MockWith { $CachePath }
        }
        AfterEach {
            foreach ($d in $script:Sty, $script:Cch) {
                if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        It 'revalidates a cached background' {
            # The behaviour, not the source text: a build that went back to
            # returning the cached file unconditionally was caught only by a
            # regex against lib/background.ps1, which is not a test of anything
            # running.
            $r = Get-StyleBundledBackground -StyleDir $script:Sty
            $r | Should -Be (Join-Path $script:Cch 'background.gif')
            Should -Invoke Update-CachedBackground -Times 1 -Exactly
        }

        It 'never revalidates on the thread the picker uses' {
            # -NoFetch exists because the picker calls this on every arrow key
            # and tier 3 can spend four ten-second timeouts. A refresh check
            # there would reintroduce exactly the stall it was added to prevent.
            $r = Get-StyleBundledBackground -StyleDir $script:Sty -NoFetch
            $r | Should -Be (Join-Path $script:Cch 'background.gif')
            Should -Invoke Update-CachedBackground -Times 0 -Exactly
        }
    }
}
