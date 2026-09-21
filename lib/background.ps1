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

function Get-StyleBackgroundAbsence {
    <#
    .SYNOPSIS
    WHY this style has no background image: 'absent', 'unreachable' or 'unknown'.

    .DESCRIPTION
    Get-StyleBundledBackground already draws the distinction -- it is the whole
    reason the marker carries a `kind` and two different TTLs -- and then throws
    it away at the return, handing every caller one undifferentiated $null. So a
    style that genuinely ships no image and a style whose image could not be
    downloaded were the same answer, and `tstyles <style> -NewWindow` on
    Terminal.app returned in silence for both: no window, and not one word about
    the background, on the one command whose entire purpose is the background.

    Three answers rather than a boolean, for the reason Unregister-ShellLoader
    returns four:

      absent       every extension answered 404. The style ships no image.
      unreachable  the network did not answer. Nothing is known about the image.
      unknown      no marker to read -- the cache dir could not be created or
                   written, or nobody has probed yet.

    Read AFTER Get-StyleBundledBackground returns $null: that call either wrote
    a fresh marker or was suppressed by an unexpired one, so the marker on disk
    is the reason for the $null the caller is holding. Asked on its own it is a
    cache reading, not a probe -- it never touches the network.
    #>
    param([Parameter(Mandatory)][string]$StyleDir)

    $cacheDir = Get-StyleCacheDir -StyleName (Split-Path -Leaf $StyleDir)
    $markerPath = Join-Path $cacheDir '.no-background'
    if (-not (Test-Path -LiteralPath $markerPath)) { return 'unknown' }

    $markerText = ''
    try {
        $markerText = [System.IO.File]::ReadAllText($markerPath, [System.Text.UTF8Encoding]::new($false))
    } catch { return 'unknown' }

    # An unparseable marker is 'unknown' for the same reason
    # Test-BackgroundProbeSuppressed calls it expired: the content-free markers
    # releases up to 0.8.5 wrote say nothing, and inventing a reason from one
    # would put a sentence on screen that no measurement backs.
    $marker = $null
    try { $marker = $markerText | ConvertFrom-Json } catch { return 'unknown' }
    if (-not $marker -or -not $marker.kind) { return 'unknown' }
    switch ("$($marker.kind)") {
        'absent'      { return 'absent' }
        'unreachable' { return 'unreachable' }
        default       { return 'unknown' }
    }
}

function Test-BackgroundRefreshDue {
    <#
    .SYNOPSIS
    Is it time to re-check a background this machine already has?

    .DESCRIPTION
    The negative cache below was given two carefully-reasoned lifetimes because
    "the gifs branch is updated independently of releases, so a style CAN gain
    an asset later". Every word of that applies to a style whose asset CHANGED,
    and only the 404 path got it: a cached file was returned unconditionally and
    never revalidated, so replacing an image on the gifs branch reached exactly
    the people who had never applied that style. Anyone who had was pinned to
    whatever they downloaded the first time, for good.

    Same marker shape as the negative cache, and the same rule that an empty or
    unparseable marker means "check now" -- a marker this tool cannot read must
    never be the reason it stops checking.

      checked      the asset was compared against the server. Two weeks: the
                   branch changes rarely, and the check costs a round trip on
                   an interactive apply.
      unreachable  the check failed. An hour, so a spell offline does not make
                   every apply pay a timeout, and does not pin the image either.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$MarkerText, [datetime]$Now = [datetime]::UtcNow)

    if ([string]::IsNullOrWhiteSpace($MarkerText)) { return $true }
    try { $marker = $MarkerText | ConvertFrom-Json } catch { return $true }
    if (-not $marker -or -not $marker.kind -or -not $marker.at) { return $true }

    # Parsed exactly the way Test-BackgroundProbeSuppressed parses its stamp --
    # RoundtripKind consumes the trailing Z but hands back Kind=Unspecified, so
    # a later ToUniversalTime shifts a UTC stamp by the machine's offset.
    $at = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
              [System.Globalization.DateTimeStyles]::AssumeUniversal
    if (-not [datetime]::TryParse($marker.at, [System.Globalization.CultureInfo]::InvariantCulture,
                                  $styles, [ref]$at)) { return $true }

    $age = $Now - $at
    switch ($marker.kind) {
        'checked'     { return ($age.TotalDays -ge 14) }
        'unreachable' { return ($age.TotalHours -ge 1) }
        default       { return $true }
    }
}

function Test-BackgroundChanged {
    <#
    .SYNOPSIS
    Does the server's copy differ from the one on disk?

    .DESCRIPTION
    Pure, so the comparison can be tested without a network. Conservative in
    ONE direction on purpose: when there is nothing to compare -- no etag, no
    length -- it answers $false and keeps what is already there. A wrong "yes"
    costs a download of an image the user already has; a wrong "no" is just the
    bug this whole function exists to fix, so neither is free, but only one of
    them can loop.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$LocalEtag,
        [AllowNull()][string]$RemoteEtag,
        [long]$LocalLength = 0,
        [long]$RemoteLength = 0
    )

    # An etag is the server telling us what it has. Trust it over a length,
    # which two different images can share.
    if ($RemoteEtag -and $LocalEtag) { return ($RemoteEtag -ne $LocalEtag) }
    if ($RemoteLength -gt 0 -and $LocalLength -gt 0) { return ($RemoteLength -ne $LocalLength) }
    return $false
}

function Get-BackgroundFileIn {
    # The background image sitting DIRECTLY in one directory, or $null.
    #
    # One place knows the extensions and their priority (.gif > .png > .jpg >
    # .jpeg, the order README documents for the gifs branch), because two
    # places answering the same question is how the tuner came to remove the
    # artefacts it owns while leaving behind the one file that outranks them
    # all: Save-TunedStyle replaced a style's profile.ps1 and prompt.sh and
    # kept its background.png, so a style the user had just been told was
    # REPLACED went on painting the replaced style's wallpaper. The removal
    # list and the resolution list are now the same list.
    param([Parameter(Mandatory)][string]$Directory)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $Directory "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Update-CachedBackground {
    <#
    .SYNOPSIS
    Re-check a cached background against the gifs branch, and replace it if the
    server has a different one. Returns the path to use either way.

    .DESCRIPTION
    Never answers $null and never leaves the caller worse off: every failure
    path returns the file that was already there. The whole point is that a
    cached image stops being permanent, not that it becomes fragile -- losing a
    background to a flaky network would be a worse bug than the one this fixes.

    Throttled by a dated marker so an apply pays a round trip about twice a
    month rather than every time, and the HEAD gets a SHORT timeout: unlike the
    first fetch, there is already a perfectly good image on disk, so there is
    nothing worth waiting ten seconds for.

    -WebRequest is a test seam. Real callers omit it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$CacheDir,
        [scriptblock]$WebRequest,
        [datetime]$Now = [datetime]::UtcNow
    )

    $markerPath = Join-Path $CacheDir '.background-checked'
    $markerText = ''
    if (Test-Path -LiteralPath $markerPath) {
        try {
            $markerText = [System.IO.File]::ReadAllText($markerPath, [System.Text.UTF8Encoding]::new($false))
        } catch { $markerText = '' }
    }
    if (-not (Test-BackgroundRefreshDue -MarkerText $markerText -Now $Now)) { return $CachePath }

    $ext = [System.IO.Path]::GetExtension($CachePath).TrimStart('.')
    $url = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$StyleName.$ext"
    if (-not $WebRequest) {
        $WebRequest = {
            param($Uri, $Method, $OutFile)
            if ($OutFile) {
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            } else {
                Invoke-WebRequest -Uri $Uri -Method $Method -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            }
        }
    }

    $stamp = {
        param([string]$Kind, [string]$Etag)
        try {
            if (-not (Test-Path -LiteralPath $CacheDir)) {
                New-Item -ItemType Directory -Path $CacheDir -Force -ErrorAction Stop | Out-Null
            }
            $body = @{ kind = $Kind; at = $Now.ToString('o') }
            if ($Etag) { $body.etag = $Etag }
            [System.IO.File]::WriteAllText($markerPath, ($body | ConvertTo-Json -Compress),
                                           [System.Text.UTF8Encoding]::new($false))
        } catch { }
    }

    $localLength = 0
    try { $localLength = (Get-Item -LiteralPath $CachePath -ErrorAction Stop).Length } catch { }
    $localEtag = ''
    if ($markerText) {
        try { $localEtag = "$(($markerText | ConvertFrom-Json).etag)" } catch { }
    }

    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $head = & $WebRequest $url 'Head' $null
        $remoteEtag = ''
        $remoteLength = 0
        if ($head -and $head.Headers) {
            # Header values arrive as a string on 5.1 and a string[] on 7.
            $raw = $head.Headers['ETag']
            if ($raw) { $remoteEtag = "$(@($raw)[0])" }
            $len = $head.Headers['Content-Length']
            if ($len) { [void][long]::TryParse("$(@($len)[0])", [ref]$remoteLength) }
        }

        if (-not (Test-BackgroundChanged -LocalEtag $localEtag -RemoteEtag $remoteEtag `
                    -LocalLength $localLength -RemoteLength $remoteLength)) {
            & $stamp 'checked' $remoteEtag
            return $CachePath
        }

        # Same .part-then-rename as the first fetch, for the same reason: a file
        # at the cache path is treated as complete by every reader, so a
        # half-written replacement would become this style's background.
        $part = "$CachePath.part-refresh"
        try {
            & $WebRequest $url 'Get' $part
            $got = Get-Item -LiteralPath $part -ErrorAction SilentlyContinue
            if ($got -and $got.Length -gt 0) {
                Move-Item -LiteralPath $part -Destination $CachePath -Force
                & $stamp 'checked' $remoteEtag
                return $CachePath
            }
            # Answered, but with nothing in it. Keep what we have.
            if ($got) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            & $stamp 'checked' $localEtag
            return $CachePath
        } catch {
            if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            & $stamp 'unreachable' $localEtag
            return $CachePath
        }
    } catch {
        & $stamp 'unreachable' $localEtag
        return $CachePath
    } finally {
        $ProgressPreference = $prevProgress
    }
}

function Get-StyleBundledBackground {
    # Three-tier resolution:
    #   1. Bundled file under $StyleDir (module root, read-only-ish on PSGallery)
    #   2. Cached file under $DataRoot\cache\<name>\ (writable, persistent)
    #   3. Lazy-fetch from gifs branch -> write to $DataRoot\cache\<name>\
    #
    # The negative-cache marker (.no-background) lives in the cache dir, never
    # in the bundled dir, so we can write it on PSGallery installs.
    #
    # -NoFetch stops at tier 2: answer from disk, or answer $null, but never
    # reach for the network. It exists for callers on an interactive thread --
    # the picker previews a style on every arrow key, and tier 3 can spend four
    # serial attempts at -TimeoutSec 10 before it concludes anything. Gating such
    # a caller on Test-StyleResolved instead would hold only while that predicate
    # and this function agree about an expired marker: a second implementation of
    # one rule, which is the drift this repo keeps paying for. A switch cannot
    # drift. It is threaded through the inheritance hop too, or a tuned style
    # would fetch its base's background on the thread we just protected.
    param(
        [Parameter(Mandatory)][string]$StyleDir,
        [switch]$NoInherit,
        [switch]$NoFetch
    )

    # 1. Bundled (under module root)
    $bundled = Get-BackgroundFileIn -Directory $StyleDir
    if ($bundled) { return $bundled }

    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir  = Get-StyleCacheDir -StyleName $styleName

    # 2. Cached (under data root)
    $cached = Get-BackgroundFileIn -Directory $cacheDir
    if ($cached) {
        # Revalidated, but only where reaching for the network is allowed at
        # all. -NoFetch exists because the picker calls this on every arrow key
        # and tier 3 can spend four ten-second timeouts; a refresh check on that
        # thread would reintroduce exactly the stall that switch was added to
        # prevent. So an interactive preview keeps using what is on disk, and
        # the apply that follows is what picks up a changed asset.
        if (-not $NoFetch) {
            $cached = Update-CachedBackground -CachePath $cached -StyleName $styleName -CacheDir $cacheDir
        }
        return $cached
    }
    # 2b. Inheritance: a tuned style inherits its base's background. For a
    # non-tuned style this returns $null instantly (no tune.json), so the
    # normal path is unaffected. -NoInherit suppresses this (used when
    # resolving a base, so inheritance is strictly one hop -- no cycles).
    if (-not $NoInherit) {
        $inherited = Get-TunedBaseBackground -StyleDir $StyleDir -NoFetch:$NoFetch
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
    if ($NoFetch) { return $null }
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
            # Per-writer temp name. This used to be a bare "$local.part", and
            # the picker's prefetch job derives its temp from the same cache
            # dir -- so on a first run the two raced on ONE path. The loser's
            # .part vanished mid-flight, Get-Item returned $null, and
            # `$null.Length -gt 0` took the "server sent an empty file" branch
            # instead of the catch -- so this call reported no background for a
            # style that has one. Measured: 3 of 4 consecutive picker runs lost
            # the race.
            #
            # Scope of the damage, precisely, because it is easy to overstate:
            # when the loser lost because the WINNER renamed the image into
            # place, the bogus 'absent' marker is never read again -- the cached
            # -file check at the top of this function returns first. The cost is
            # that ONE call: a preview or apply that writes a WT profile with no
            # backgroundImage, which persists in settings.json until the next
            # apply. The 30-day marker only bites in the other ordering, where
            # the sibling's catch unlinks an in-flight temp and no image lands
            # at all.
            #
            # Deterministic rather than a GUID, so a killed process leaves at
            # most one stale temp per writer per extension, which the next run
            # overwrites -- GUIDs would accumulate in the cache dir forever.
            $part = "$local.part-sync"
            try {
                Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                $got = Get-Item -LiteralPath $part -ErrorAction SilentlyContinue
                if ($null -eq $got) {
                    # The temp is GONE, not empty. The request succeeded, so
                    # the server did not say "not there" -- something removed
                    # the file underneath us. That is inconclusive, and the
                    # distinction is the whole point of $definitelyAbsent:
                    # calling it absent buys a 30-DAY marker for a style that
                    # may well have a background.
                    #
                    # It used to fall into the else below, because
                    # `$null.Length -gt 0` is simply false -- so a lost race
                    # was recorded as a definite absence.
                    $definitelyAbsent = $false
                } elseif ($got.Length -gt 0) {
                    Move-Item -LiteralPath $part -Destination $local -Force
                    return $local
                } else {
                    # A real zero-byte response. The server answered; there is
                    # just nothing in it.
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
