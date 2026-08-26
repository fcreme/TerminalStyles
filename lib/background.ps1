# background.ps1 -- resolving a style's background image, and remembering when
# there isn't one.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Resolution is three tiers plus one inheritance hop: a file bundled beside the
# style, the per-user cache, a tuned style's base, then a lazy fetch from the
# gifs branch. The fetch downloads to a .part and renames, because a file
# sitting at the cache path is treated as a complete entry by every reader and
# nothing revalidates it.
#
# The negative cache is dated, and deliberately so: a 404 means the asset is
# genuinely absent and is worth remembering for a month, while an unreachable
# network means nothing and is remembered for an hour.

function Test-HttpNotFound {
    # Did this web error mean "the server answered, and the file is not there"
    # (404) as opposed to "I could not reach the server" (DNS failure, timeout,
    # offline, proxy, 5xx)?
    #
    # The distinction is the whole point of the negative cache: an absent asset
    # is a stable fact worth remembering, an unreachable network is not.
    # Both engines surface it the same way -- a 404 carries a .Response with a
    # StatusCode, a transport failure has no .Response at all (verified on
    # pwsh 7's HttpResponseException/HttpRequestException and 5.1's WebException,
    # whose .Response is null for NameResolutionFailure).
    param($ErrorRecord)
    try {
        $response = $ErrorRecord.Exception.Response
        if (-not $response) { return $false }
        return ([int]$response.StatusCode -eq 404)
    } catch { return $false }
}

function Test-BackgroundProbeSuppressed {
    # Should we skip the lazy fetch because a previous probe already answered?
    # Pure, so the expiry rules are testable without touching the network.
    #
    # Two lifetimes, because the two answers are worth different amounts:
    #   absent      -- every extension 404'd. A stable fact, but not permanent:
    #                  the gifs branch is updated independently of releases, so
    #                  a style CAN gain an asset later. Re-probe monthly.
    #   unreachable -- the network failed. Worth remembering only long enough to
    #                  stop every apply in the next hour paying four 10-second
    #                  timeouts; then retry.
    #
    # An empty or unparseable marker is treated as EXPIRED. Releases up to 0.8.5
    # wrote a content-free marker on ANY failure and deleted it never, so one
    # apply while offline cost that style its background permanently. Returning
    # $false here re-probes once and replaces it with a marker that can expire.
    param([string]$MarkerText, [datetime]$Now = [datetime]::UtcNow)

    if ([string]::IsNullOrWhiteSpace($MarkerText)) { return $false }
    try { $marker = $MarkerText | ConvertFrom-Json } catch { return $false }
    if (-not $marker -or -not $marker.kind -or -not $marker.at) { return $false }

    # AdjustToUniversal + AssumeUniversal, NOT RoundtripKind: TryParse with
    # RoundtripKind consumes the trailing Z but hands back Kind=Unspecified, so
    # a later .ToUniversalTime() re-reads a UTC stamp as local and shifts it by
    # the machine's offset. That silently widened or narrowed every TTL by hours
    # depending on where the user lives. The marker is always written as UTC.
    $at = [datetime]::MinValue
    $parseStyles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                   [System.Globalization.DateTimeStyles]::AssumeUniversal
    if (-not [datetime]::TryParse($marker.at, [cultureinfo]::InvariantCulture,
            $parseStyles, [ref]$at)) { return $false }

    $ttl = if ($marker.kind -eq 'absent') { [timespan]::FromDays(30) } else { [timespan]::FromHours(1) }
    return (($Now.ToUniversalTime() - $at) -lt $ttl)
}

function Get-StyleBundledBackground {
    # Three-tier resolution:
    #   1. Bundled file under $StyleDir (module root, read-only-ish on PSGallery)
    #   2. Cached file under $DataRoot\cache\<name>\ (writable, persistent)
    #   3. Lazy-fetch from gifs branch -> write to $DataRoot\cache\<name>\
    #
    # The negative-cache marker (.no-background) lives in the cache dir, never
    # in the bundled dir, so we can write it on PSGallery installs.
    param([Parameter(Mandatory)][string]$StyleDir, [switch]$NoInherit)

    # 1. Bundled (under module root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $bundled = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }

    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir  = Get-StyleCacheDir -StyleName $styleName

    # 2. Cached (under data root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $cached = Join-Path $cacheDir "background.$ext"
        if (Test-Path -LiteralPath $cached) { return $cached }
    }
    # 2b. Inheritance: a tuned style inherits its base's background. For a
    # non-tuned style this returns $null instantly (no tune.json), so the
    # normal path is unaffected. -NoInherit suppresses this (used when
    # resolving a base, so inheritance is strictly one hop -- no cycles).
    if (-not $NoInherit) {
        $inherited = Get-TunedBaseBackground -StyleDir $StyleDir
        if ($inherited) { return $inherited }
    }

    $markerPath = Join-Path $cacheDir '.no-background'
    if (Test-Path -LiteralPath $markerPath) {
        $markerText = ''
        try {
            $markerText = [System.IO.File]::ReadAllText($markerPath, [System.Text.UTF8Encoding]::new($false))
        } catch { $markerText = '' }
        if (Test-BackgroundProbeSuppressed -MarkerText $markerText) { return $null }
    }

    # 3. Lazy-fetch into cache
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    # Did the server actually answer "not there" every time? One unreachable
    # attempt is enough to make the whole result inconclusive.
    $definitelyAbsent = $true
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $cacheDir "background.$ext"
            # Same .part-then-rename as the picker's prefetch job, for the same
            # reason: a file at $local is treated as a complete cache entry by
            # every reader and nothing revalidates it. The catch below cleans up
            # after a network error, but a Ctrl+C or a killed process never
            # reaches it -- and that would strand a truncated image as this
            # style's background for good.
            $part = "$local.part"
            try {
                Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $part -ErrorAction SilentlyContinue).Length -gt 0) {
                    Move-Item -LiteralPath $part -Destination $local -Force
                    return $local
                } else {
                    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
                if (-not (Test-HttpNotFound -ErrorRecord $_)) { $definitelyAbsent = $false }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # Nothing fetched. Record WHY, so the marker can expire on the right clock:
    # a real 404 is worth remembering for a month, an unreachable network for an
    # hour. Writing an undated marker on any failure -- what releases up to 0.8.5
    # did -- meant a single apply while offline cost that style its background
    # for good, and the only documented way to clear it was `tstyles uninstall
    # -DeleteData`, which could not be invoked at all.
    try {
        $marker = [pscustomobject]@{
            schemaVersion = 1
            kind          = if ($definitelyAbsent) { 'absent' } else { 'unreachable' }
            at            = [datetime]::UtcNow.ToString('o')
        }
        [System.IO.File]::WriteAllText((Join-Path $cacheDir '.no-background'),
            ($marker | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    } catch { }
    return $null
}
