# Pester 5 tests for Test-UpdateAvailable (the 24h-throttled update check).
#
# Module-restructure migration: dot-source replaced with Import-Module,
# all test bodies wrapped in InModuleScope TerminalStyles so the mocks
# intercept module-internal calls and Test-UpdateAvailable resolves.
#
# Locks in the throttle invariants from
# docs/superpowers/specs/2026-05-27-update-check-throttle-design.md:
#   - Fresh stamp short-circuits the API call entirely (no IRM invocation).
#   - Stale / missing stamp triggers the API call and writes a fresh stamp.
#   - Corrupt stamp falls through and self-heals (overwritten with valid value).
#   - API failure still writes the stamp -- the bug that motivated the spec
#     was an offline machine retrying the 2s timeout on every invocation.
#   - Update-available returns abbreviated 7-char SHA pair.
#
# And the PowerShell Gallery half, which used to return $null outright -- so a
# Gallery install, the documented way in, was never told a release was out:
#   - a newer stable version on the Gallery returns the version pair;
#   - versions compare as versions, not as text;
#   - the same throttle and stamp rules as the GitHub half.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-UpdateAvailable' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # These are the Bootstrap half: the commit on origin/main against
            # .installed-sha. The Gallery half has its own Describe below.
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            $stampFile = Join-Path $TestDrive '.last-update-check'
            $shaFile   = Join-Path $TestDrive '.installed-sha'
            # -Force is required, not optional: both names start with a dot, and
            # on macOS/Linux a dotfile is hidden -- Remove-Item skips hidden items
            # unless forced. Without it the previous test's throttle stamp would
            # survive into this one and suppress the API call under test.
            Remove-Item $stampFile -Force -ErrorAction SilentlyContinue
            Remove-Item $shaFile   -Force -ErrorAction SilentlyContinue
        }

        It 'returns $null and skips the API when the stamp is fresh (< 24h)' {
            $fresh = (Get-Date).AddMinutes(-30).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $fresh, [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { throw 'API should NOT be called inside the throttle window' }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'fires the API call when the stamp is stale (> 24h)' {
            $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 1
            Test-Path $stampFile | Should -BeTrue
        }

        It 'fires the API call when no stamp file exists' {
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 1
            Test-Path $stampFile | Should -BeTrue
        }

        It 'self-heals on corrupt stamp (unparseable contents)' {
            [System.IO.File]::WriteAllText($stampFile, 'garbage not a date', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            { Test-UpdateAvailable } | Should -Not -Throw

            Should -Invoke Invoke-RestMethod -Times 1
            $written = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false))
            { [datetime]::Parse($written, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } | Should -Not -Throw
        }

        It 'still writes the stamp when the API call fails' {
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { throw 'simulated network failure' }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Test-Path $stampFile | Should -BeTrue
        }

        It 'returns the abbreviated SHA pair when remote SHA differs from installed' {
            $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, '0000000000000000000000000000000000000000', [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = 'abc123def4567aaaaaaaaaaaaaaaaaaaaaaaaaaa' } }

            $result = Test-UpdateAvailable

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -Be '0000000'
            $result.Remote    | Should -Be 'abc123d'
        }
    }
}

Describe 'Test-UpdateAvailable on a PowerShell Gallery install' {
    # This half returned $null outright, on the reasoning that a Gallery copy is
    # updated by Update-PSResource whenever the user runs `tstyles update`. But
    # the notice is how they learn there is anything to run it for: 0.9.0 was
    # published and no Gallery install said a word about it. What
    # `tstyles update` installs there is the Gallery's newest stable version,
    # so that is what the check asks for.
    InModuleScope TerminalStyles {
        BeforeAll {
            # Trimmed from the Gallery's real answer of 2026-10-12: the feed and
            # entry envelopes as sent, and the properties a reader could reach
            # for. The typed ones keep their m:type on purpose -- through the
            # XML adapter a property with an attribute comes back as the
            # element, not as its text.
            $script:galleryFeed = @'
<?xml version="1.0" encoding="utf-8"?>
<feed xml:base="https://www.powershellgallery.com/api/v2" xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
  <m:count>1</m:count>
  <id>http://schemas.datacontract.org/2004/07/</id>
  <title />
  <updated>2026-10-12T04:18:17Z</updated>
  <link rel="self" href="https://www.powershellgallery.com/api/v2/Packages" />
  <entry>
    <id>https://www.powershellgallery.com/api/v2/Packages(Id='TerminalStyles',Version='@VERSION@')</id>
    <category term="NuGetGallery.OData.V2FeedPackage" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
    <title type="text">TerminalStyles</title>
    <updated>2026-10-12T01:25:14Z</updated>
    <author><name>Felipe Cremerius</name></author>
    <content type="application/zip" src="https://www.powershellgallery.com/api/v2/package/TerminalStyles/@VERSION@" />
    <m:properties>
      <d:Id>TerminalStyles</d:Id>
      <d:Version>@VERSION@</d:Version>
      <d:NormalizedVersion>@VERSION@</d:NormalizedVersion>
      <d:Authors>Felipe Cremerius</d:Authors>
      <d:IsLatestVersion m:type="Edm.Boolean">true</d:IsLatestVersion>
      <d:IsAbsoluteLatestVersion m:type="Edm.Boolean">true</d:IsAbsoluteLatestVersion>
      <d:IsPrerelease m:type="Edm.Boolean">false</d:IsPrerelease>
      <d:Published m:type="Edm.DateTime">2026-10-12T01:25:14</d:Published>
      <d:PowerShellVersion>5.1</d:PowerShellVersion>
      <d:ItemType>Module</d:ItemType>
    </m:properties>
  </entry>
</feed>
'@

            # What Invoke-RestMethod hands back for an Atom feed: its <entry>
            # elements, not the document.
            function New-GalleryEntry([string]$Version, [string]$Feed = $script:galleryFeed) {
                ([xml]$Feed.Replace('@VERSION@', $Version)).feed.entry
            }
        }

        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            Mock Get-TerminalStylesInstallKind { 'PSResourceGet' }
            $stampFile = Join-Path $TestDrive '.last-update-check'
            Remove-Item $stampFile -Force -ErrorAction SilentlyContinue
        }

        It 'names both versions when the Gallery has a newer one' {
            Mock Get-NewestInstalledVersion { '0.8.48' }
            $entry = New-GalleryEntry -Version '0.9.0'
            Mock Invoke-RestMethod { $entry }

            $result = Test-UpdateAvailable

            $result.Installed | Should -Be '0.8.48'
            $result.Remote    | Should -Be '0.9.0'
        }

        It 'asks the Gallery for its newest stable TerminalStyles, and waits two seconds at most' {
            Mock Get-NewestInstalledVersion { '0.8.48' }
            $entry = New-GalleryEntry -Version '0.9.0'
            Mock Invoke-RestMethod { $entry }

            Test-UpdateAvailable | Out-Null

            # The quotes around the id are load-bearing: measured, the same
            # query without them answers with an empty feed, which would read
            # as "nothing newer" for good. IsLatestVersion rather than
            # IsAbsoluteLatestVersion, because Update-PSResource skips
            # prereleases. And a timeout, because this runs inside an ordinary
            # command and Invoke-RestMethod's own default is 100 seconds.
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                "$Uri" -match "^https://www\.powershellgallery\.com/api/v2/FindPackagesById\(\)\?id=('|%27)TerminalStyles('|%27)&" -and
                "$Uri" -match '[?&]\$filter=IsLatestVersion(&|$)' -and
                $TimeoutSec -eq 2
            }
        }

        It 'says nothing when the newest installed version is the Gallery''s latest' {
            Mock Get-NewestInstalledVersion { '0.9.0' }
            $entry = New-GalleryEntry -Version '0.9.0'
            Mock Invoke-RestMethod { $entry }

            Test-UpdateAvailable | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            [System.IO.File]::Exists($stampFile) | Should -BeTrue `
                -Because 'a check that found nothing has still spent the day'
        }

        It 'does not offer an older version whose text sorts higher' {
            # As text '0.9.9' sorts after '0.9.10'; as a version it is older.
            Mock Get-NewestInstalledVersion { '0.9.10' }
            $entry = New-GalleryEntry -Version '0.9.9'
            Mock Invoke-RestMethod { $entry }

            Test-UpdateAvailable | Should -BeNullOrEmpty
        }

        It 'offers a newer version whose text sorts lower' {
            Mock Get-NewestInstalledVersion { '0.9.9' }
            $entry = New-GalleryEntry -Version '0.9.10'
            Mock Invoke-RestMethod { $entry }

            (Test-UpdateAvailable).Remote | Should -Be '0.9.10'
        }

        It 'stays quiet when the Gallery cannot be reached, and still spends the day''s check' {
            Mock Get-NewestInstalledVersion { '0.8.48' }
            Mock Invoke-RestMethod { throw 'simulated network failure' }

            Test-UpdateAvailable | Should -BeNullOrEmpty
            [System.IO.File]::Exists($stampFile) | Should -BeTrue `
                -Because 'an offline machine must not pay the timeout on every command'
        }

        It 'makes no request, and reads no module path, inside the 24h window' {
            $fresh = (Get-Date).AddMinutes(-30).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $fresh, [System.Text.UTF8Encoding]::new($false))
            Mock Get-NewestInstalledVersion { '0.8.48' }
            Mock Invoke-RestMethod { throw 'the Gallery must not be asked inside the throttle window' }

            Test-UpdateAvailable | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 0
            Should -Invoke Get-NewestInstalledVersion -Times 0
        }

        It 'asks nothing when no installed copy can be found' {
            # A source checkout imported by path, or a test run: nothing on the
            # module path to compare against. The bootstrap half answers a
            # missing .installed-sha the same way.
            Mock Get-NewestInstalledVersion { $null }
            Mock Invoke-RestMethod { throw 'with nothing to compare there is nothing to ask' }

            Test-UpdateAvailable | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'reads the version when the feed types it too' {
            # Version carries no m:type today, so the adapter hands back its
            # text. IsLatestVersion, beside it, does -- and comes back as an
            # element. Should Version ever gain one, the check must not go
            # quiet for good.
            Mock Get-NewestInstalledVersion { '0.8.48' }
            $typed = $script:galleryFeed.Replace('<d:Version>', '<d:Version m:type="Edm.String">')
            $entry = New-GalleryEntry -Version '0.9.0' -Feed $typed
            Mock Invoke-RestMethod { $entry }

            (Test-UpdateAvailable).Remote | Should -Be '0.9.0'
        }

        It 'says nothing when the Gallery answers with <Case>' -ForEach @(
            # A captive portal (hotel or airport Wi-Fi) answers 200 with its
            # own HTML, which Invoke-RestMethod returns as a string.
            @{ Case = 'a captive portal''s HTML page'; Body = '<!DOCTYPE html><html><body>Sign in to continue</body></html>' }
            # No entries: Invoke-RestMethod emits nothing at all.
            @{ Case = 'an empty feed'; Body = @() }
        ) {
            Mock Get-NewestInstalledVersion { '0.8.48' }
            Mock Invoke-RestMethod { $Body }

            Test-UpdateAvailable | Should -BeNullOrEmpty
        }

        It 'prints the notice with both versions' {
            # The user-visible end of all of the above, and the line that was
            # missing.
            Mock Get-NewestInstalledVersion { '0.8.48' }
            $entry = New-GalleryEntry -Version '0.9.0'
            Mock Invoke-RestMethod { $entry }

            $out = Show-UpdateNoticeIfAvailable 6>&1 | Out-String -Width 500

            $out | Should -Match 'Update available.*0\.8\.48 -> 0\.9\.0.*tstyles update'
        }
    }
}

Describe 'the update check on Windows PowerShell 5.1' {
    # Both hosts the check asks -- api.github.com and the Gallery -- refuse
    # anything older than TLS 1.2, and on .NET Framework the default
    # SecurityProtocol can leave it out: install.ps1 and the CI workflow both
    # add it for that reason. Without it the request fails into the check's
    # silent catch, and the notice never appears.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesDataRoot = $TestDrive
            Remove-Item (Join-Path $TestDrive '.last-update-check') -Force -ErrorAction SilentlyContinue
            [System.IO.File]::WriteAllText((Join-Path $TestDrive '.installed-sha'), ('a' * 40), [System.Text.UTF8Encoding]::new($false))
            Mock Get-NewestInstalledVersion { '0.8.48' }
            $script:prevTls = [Net.ServicePointManager]::SecurityProtocol
        }
        AfterEach {
            [Net.ServicePointManager]::SecurityProtocol = $script:prevTls
        }

        It 'allows TLS 1.2 for the <Kind> request, and puts the setting back after' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') -ForEach @(
            @{ Kind = 'PSResourceGet' }
            @{ Kind = 'Bootstrap' }
        ) {
            Mock Get-TerminalStylesInstallKind { $Kind }
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
            $seen = @{}
            Mock Invoke-RestMethod { $seen.Protocol = [Net.ServicePointManager]::SecurityProtocol }

            Test-UpdateAvailable | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            ($seen.Protocol -band [Net.SecurityProtocolType]::Tls12) | Should -Be ([Net.SecurityProtocolType]::Tls12) `
                -Because 'the request has to be able to offer TLS 1.2'
            [Net.ServicePointManager]::SecurityProtocol | Should -Be ([Net.SecurityProtocolType]::Tls) `
                -Because 'a tstyles command leaves the session''s setting as it found it'
        }
    }
}
