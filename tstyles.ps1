# tstyles.ps1 -- TerminalStyles loader + interactive picker.
#
# Dot-sourced from $PROFILE by install.ps1. Provides:
#   * `tstyles` (alias of Invoke-TerminalStyle) -- arrow-key live-preview picker.
#   * Auto-loads the currently selected style's profile.ps1 on shell startup.
#
# All write operations restore on Escape; the original settings.json bytes are
# snapshotted on entry so a cancel is byte-exact.

#Requires -Version 5.1

$script:TStylesModuleRoot = $PSScriptRoot
if (-not $script:TStylesModuleRoot) {
    $script:TStylesModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
function Get-TStylesPlatform {
    # 'Windows' | 'MacOS' | 'Linux'. The automatic $IsWindows/$IsMacOS/$IsLinux
    # variables only exist on PowerShell 6+; Windows PowerShell 5.1 predates
    # them and is Windows by definition, so branch on the major version first.
    # (Referencing $IsWindows under 5.1 would silently yield $null, not $true.)
    if ($PSVersionTable.PSVersion.Major -lt 6) { return 'Windows' }
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'MacOS' }
    return 'Linux'
}

function Get-TStylesDataRoot {
    # Stable per-user data dir. Survives module version upgrades (PSResourceGet
    # installs a new version to a sibling dir; state stays here). For bootstrap-
    # installed Windows users this happens to equal $script:TStylesModuleRoot --
    # backward-compatible by design, which is why Windows keeps %LOCALAPPDATA%
    # verbatim rather than moving to a new cross-platform location.
    #
    # -Platform / -HomeDir are test seams; real callers omit them.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'Windows' {
            # $env:LOCALAPPDATA is the historical location. Fall back to the
            # profile-relative path if the var is somehow unset (bare service
            # accounts, stripped environments) so we never Join-Path a $null.
            $base = $env:LOCALAPPDATA
            if (-not $base) { $base = Join-Path $HomeDir 'AppData\Local' }
            return Join-Path $base 'TerminalStyles'
        }
        'MacOS' {
            return Join-Path (Join-Path $HomeDir 'Library/Application Support') 'TerminalStyles'
        }
        default {
            # XDG Base Directory spec: honour $XDG_DATA_HOME, else ~/.local/share.
            $base = $env:XDG_DATA_HOME
            if (-not $base) { $base = Join-Path (Join-Path $HomeDir '.local') 'share' }
            return Join-Path $base 'TerminalStyles'
        }
    }
}

function Get-TStylesFontDir {
    # Per-user font directory -- the one a font can be dropped into WITHOUT
    # admin/root. Platform differences run deeper than the path:
    #   Windows: copy + an HKCU registry value + a GDI AddFontResource broadcast
    #   macOS:   copy alone is enough; CoreText picks up ~/Library/Fonts live
    #   Linux:   copy alone, though fontconfig may need `fc-cache` to notice
    # Install-Font branches on Get-TStylesPlatform for those extra steps.
    #
    # -Platform / -HomeDir are test seams; real callers omit them.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'Windows' {
            $base = $env:LOCALAPPDATA
            if (-not $base) { $base = Join-Path $HomeDir 'AppData\Local' }
            return Join-Path $base 'Microsoft\Windows\Fonts'
        }
        'MacOS' { return Join-Path (Join-Path $HomeDir 'Library') 'Fonts' }
        default {
            $base = $env:XDG_DATA_HOME
            if (-not $base) { $base = Join-Path (Join-Path $HomeDir '.local') 'share' }
            return Join-Path $base 'fonts'
        }
    }
}

# Terminal detection + capability model. Dot-sourced (not a nested module) so
# it shares $script: scope with everything below -- Get-TerminalCapability reads
# $script:TStylesCapabilityNames, and the adapters need $script:TStylesDataRoot.
. (Join-Path $script:TStylesModuleRoot 'terminals.ps1')

$script:TStylesPlatform = Get-TStylesPlatform
$script:TStylesDataRoot = Get-TStylesDataRoot
if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
}
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

# Profile fields TerminalStyles writes onto a Windows Terminal profile entry.
# Single source of truth shared by Merge-StyleIntoSettings (apply) and
# Reset-StyleDirect (reset), so the two can't drift. Verified as the union of
# keys across all 16 bundled styles/*/theme.json files.
$script:TStylesBgFields    = @('backgroundImage', 'backgroundImageOpacity',
                               'backgroundImageStretchMode', 'backgroundImageAlignment')
$script:TStylesThemeFields = @('colorScheme', 'tabTitle', 'tabColor', 'cursorShape',
                               'useAcrylic', 'opacity', 'experimental.retroTerminalEffect',
                               'font', 'padding') + $script:TStylesBgFields

# === Internals ===

function Find-WTSettingsPath {
    # Prefer the settings.json of the Windows Terminal build hosting THIS session.
    # WT sets $env:WT_SETTINGS_PATH to its live file, so honoring it makes a user
    # on WT Preview (with Stable also installed) edit Preview's file -- not
    # Stable's, which the static list below would otherwise win. Falls back to the
    # candidate list (Stable > Preview > unpackaged) when the env var is absent.
    if ($env:WT_SETTINGS_PATH -and (Test-Path -LiteralPath $env:WT_SETTINGS_PATH)) {
        return $env:WT_SETTINGS_PATH
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-CurrentWTProfileName {
    param($Settings)
    if (-not $env:WT_PROFILE_ID) { return $null }
    $entry = $Settings.profiles.list | Where-Object { $_.guid -eq $env:WT_PROFILE_ID } | Select-Object -First 1
    if ($entry) { return $entry.name }
    return $null
}

function Get-StyleCacheDir {
    # The per-user, WRITABLE cache dir for a style's lazily-fetched background.
    # Single source of truth shared by Get-StyleBundledBackground, Test-StyleResolved,
    # and the picker's prefetch job so the writer and the readers can never drift.
    # The prefetch job runs in a separate runspace without $script: scope, so it
    # re-derives the same path from the data root -- keep this formula in sync
    # with that derivation (Join-Path (Join-Path $DataRoot 'cache') <name>).
    #
    # Nested Join-Path, NOT "cache\$StyleName": the 3-argument Join-Path is
    # PowerShell 6+ only (WinPS 5.1 takes two positional paths), and a literal
    # backslash is not a separator on macOS/Linux -- it would produce a single
    # file named "cache\eva" instead of the cache/eva directory.
    param([Parameter(Mandatory)][string]$StyleName)
    Join-Path (Join-Path $script:TStylesDataRoot 'cache') $StyleName
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

    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch into cache
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $cacheDir "background.$ext"
            try {
                Invoke-WebRequest -Uri $url -OutFile $local -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                    return $local
                } else {
                    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # All extensions failed -- write negative-cache marker in CACHE dir
    try {
        New-Item -ItemType File -Path (Join-Path $cacheDir '.no-background') -Force | Out-Null
    } catch { }
    return $null
}

function Invoke-TerminalStylesStateMigration {
    # Migrates pre-0.2.0 data layout to 0.2.0:
    #   - Cached background.<ext> files move from $ModuleRoot\styles\<name>\
    #     to $DataRoot\cache\<name>\.
    #   - .no-background negative-cache markers move similarly.
    # Idempotent. Skips work if the marker file exists.
    $marker = Join-Path $script:TStylesDataRoot '.migrated-0.2.0'
    if (Test-Path -LiteralPath $marker) { return }

    # Claim the migration immediately (before the move loop) so a second shell
    # importing the module concurrently -- e.g. several WT tabs opened at once --
    # sees the marker and bails instead of racing the same Move-Item calls. The
    # moves are best-effort and self-healing (a background missed here re-fetches
    # into the cache dir on demand), so claiming up front is the safe trade.
    try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) { return }

    foreach ($styleDir in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        $styleName = $styleDir.Name
        $cacheDir = Join-Path (Join-Path $script:TStylesDataRoot 'cache') $styleName

        # Move cached background files
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $src = Join-Path $styleDir.FullName "background.$ext"
            if (Test-Path -LiteralPath $src) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
                }
                $dest = Join-Path $cacheDir "background.$ext"
                try {
                    Move-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                } catch {
                    # Source might be read-only (PSGallery install with stale
                    # bundled file from manual user copy). Acceptable -- the
                    # bundled file stays readable in place.
                }
            }
        }

        # Move negative-cache marker
        $srcMarker = Join-Path $styleDir.FullName '.no-background'
        if (Test-Path -LiteralPath $srcMarker) {
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
            }
            try {
                Move-Item -LiteralPath $srcMarker -Destination (Join-Path $cacheDir '.no-background') -Force -ErrorAction Stop
            } catch { }
        }
    }
    # Marker was already written at the top (claim-before-work); nothing to do here.
}

function Get-TerminalStylesInstallKind {
    # Returns 'Bootstrap' if the module loaded from %LOCALAPPDATA%\TerminalStyles\
    # (the iwr-installer path), else 'PSResourceGet' (PSModulePath-based install).
    # Used by Invoke-TerminalStylesUpdate / Invoke-TerminalStylesUninstall to
    # delegate to the right mechanism, and by Test-UpdateAvailable to skip the
    # SHA-based check entirely for PSResourceGet installs.
    #
    # Note: $script:TStylesModuleRoot is set during module load. For installs
    # made before the dual-root refactor (sub-project C), the variable still
    # has the right value because the init block sets it from $PSScriptRoot.
    $bootstrapDir = Get-TStylesDataRoot
    if ($script:TStylesModuleRoot -eq $bootstrapDir) { return 'Bootstrap' }
    return 'PSResourceGet'
}

function Test-UpdateAvailable {
    # Returns a pscustomobject with short SHAs if a newer commit is available
    # on origin/main, or $null if local already matches / no .installed-sha /
    # we're inside the 24h throttle window / the API call fails.
    #
    # Throttled to <= 1 HTTP request per 24 hours per machine via
    # .last-update-check. The timestamp is rewritten on every attempt
    # (success or failure), so an offline machine doesn't retry the
    # 2s timeout on every single tstyles invocation.
    # PSResourceGet installs update via Update-PSResource, not git. Skip
    # the SHA-based check entirely; the user runs `tstyles update` whenever.
    if ((Get-TerminalStylesInstallKind) -eq 'PSResourceGet') { return $null }

    $shaFile   = Join-Path $script:TStylesDataRoot '.installed-sha'
    $stampFile = Join-Path $script:TStylesDataRoot '.last-update-check'

    # --- Throttle gate ---
    # If the stamp file is present and parses as a datetime less than 24h old,
    # skip everything below. Unparseable / missing -> fall through and the
    # timestamp write at the end will overwrite with a valid value (self-heal).
    if (Test-Path -LiteralPath $stampFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false)).Trim()
            $stamp = [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (((Get-Date) - $stamp).TotalHours -lt 24) { return $null }
        } catch { }
    }

    if (-not (Test-Path -LiteralPath $shaFile)) { return $null }
    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
    if (-not $installed) { return $null }

    $remote = $null
    try {
        $resp = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
            -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
            -TimeoutSec 2 -ErrorAction Stop
        $remote = $resp.sha
    } catch { }

    # --- Throttle write ---
    # Always write the timestamp, even on API failure. Without this, an
    # offline machine would retry the 2s timeout on every invocation.
    try {
        $now = (Get-Date).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::WriteAllText($stampFile, $now, [System.Text.UTF8Encoding]::new($false))
    } catch { }

    if ($remote -and $remote -ne $installed) {
        return [pscustomobject]@{
            Installed = $installed.Substring(0, [Math]::Min(7, $installed.Length))
            Remote    = $remote.Substring(0, [Math]::Min(7, $remote.Length))
        }
    }
    return $null
}

function Show-UpdateNoticeIfAvailable {
    # Prints the one-line yellow update notice if there's a newer commit
    # on origin/main. Called from every non-updating tstyles invocation
    # (picker, direct apply, list, current, random), but Test-UpdateAvailable
    # short-circuits inside the 24h throttle window, so the notice displays
    # at most once per day while an update is pending.
    $pending = Test-UpdateAvailable
    if ($pending) {
        Write-Host ("Update available ({0} -> {1}). Run: tstyles update" -f $pending.Installed, $pending.Remote) -ForegroundColor Yellow
        Write-Host ""
    }
}

function Invoke-TerminalStylesUpdate {
    [CmdletBinding()]
    param([switch]$Force)

    Write-Host ""
    Write-Host "Updating TerminalStyles..." -ForegroundColor Cyan

    switch (Get-TerminalStylesInstallKind) {
        'PSResourceGet' {
            try {
                Update-PSResource -Name TerminalStyles -TrustRepository -ErrorAction Stop
                Write-Host ""
                Write-Host "Update complete. To use the new version in THIS session," -ForegroundColor Yellow
                Write-Host "open a new tab, or run:" -ForegroundColor Yellow
                Write-Host "  Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Cyan
            } catch {
                Write-Host "Update failed: $_" -ForegroundColor Red
                Write-Host "You can retry manually:" -ForegroundColor Yellow
                Write-Host "  Update-PSResource -Name TerminalStyles -TrustRepository" -ForegroundColor Cyan
            }
        }
        'Bootstrap' {
            # Re-run the iwr installer one-liner. Existing behavior, preserved
            # so users who installed via iwr|iex keep updating that way.

            # Cheap check first: if we already have the current main SHA, skip
            # the ~10MB ZIP download entirely. -Force overrides.
            $shaFile = Join-Path $script:TStylesDataRoot '.installed-sha'
            if (-not $Force -and (Test-Path -LiteralPath $shaFile)) {
                try {
                    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
                    $resp = Invoke-RestMethod `
                        -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
                        -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
                        -TimeoutSec 5 -ErrorAction Stop
                    if ($resp.sha -and $resp.sha -eq $installed) {
                        Write-Host "Already up to date ($($installed.Substring(0,7))). Use -Force to reinstall anyway." -ForegroundColor Green
                        return
                    }
                } catch {
                    # Network failure -- fall through to full download.
                }
            }

            # Suppress IWR progress bar (dominant cost on WinPS 5.1).
            $prevProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                $installerScript = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1' -UseBasicParsing).Content
                Invoke-Expression $installerScript
                Write-Host ""
                Write-Host "Update complete. To use the new tstyles code in THIS session," -ForegroundColor Yellow
                Write-Host "open a new pwsh tab, or run:" -ForegroundColor Yellow
                Write-Host "  . `$PROFILE" -ForegroundColor Cyan
            } catch {
                Write-Host "Update failed: $_" -ForegroundColor Red
                Write-Host "You can retry manually:" -ForegroundColor Yellow
                Write-Host "  iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex" -ForegroundColor Cyan
            } finally {
                $ProgressPreference = $prevProgress
            }
        }
    }
}

function Remove-JsonComment {
    # Strip // line comments and /* */ block comments from a JSON/JSONC string,
    # leaving comment-like sequences INSIDE string literals (URLs, globs, paths)
    # intact. Windows Terminal's default settings.json ships with // comments,
    # which Windows PowerShell 5.1's ConvertFrom-Json rejects; this normalizes the
    # text so 5.1 and pwsh 7 parse identically. Round-tripping back through
    # ConvertTo-Json drops comments anyway, so stripping costs no fidelity.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $n) {
            $next = $Text[$i + 1]
            if ($next -eq '/') {
                # Line comment: skip to (but keep) the newline.
                $i += 2
                while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($next -eq '*') {
                # Block comment: skip through the closing */.
                $i += 2
                while ($i -lt $n -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function Remove-JsonTrailingComma {
    # Drop trailing commas (a ',' whose next non-whitespace char is '}' or ']')
    # OUTSIDE string literals. Windows Terminal and hand edits leave these; pwsh 7
    # tolerates them but Windows PowerShell 5.1's ConvertFrom-Json rejects them
    # with "extra trailing ','", crashing every mutating command. Commas inside
    # string values (e.g. "a,b") are preserved. Run AFTER Remove-JsonComment so a
    # comment between the comma and the bracket can't hide the trailing comma.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped  = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)     { $escaped = $false }
            elseif ($c -eq '\')   { $escaped = $true }
            elseif ($c -eq '"')   { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq ',') {
            # Peek past whitespace: a comma immediately preceding } or ] is trailing.
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $n -and ($Text[$j] -eq '}' -or $Text[$j] -eq ']')) {
                $i++   # skip the comma; leave the whitespace/bracket intact
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    $sb.ToString()
}

function ConvertFrom-WTJson {
    # Parse a Windows Terminal settings.json string, tolerating the // and /* */
    # comments and trailing commas WT writes by default. On Windows PowerShell 5.1
    # ConvertFrom-Json rejects both outright, so a fresh WT install (or a hand edit)
    # would otherwise abort every mutating command with a raw parse error. Strips
    # comments first, then trailing commas, then parses; throws one actionable
    # message if the text still isn't valid JSON.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $clean = Remove-JsonComment -Text $Json
    $clean = Remove-JsonTrailingComma -Text $clean
    try {
        $clean | ConvertFrom-Json
    } catch {
        throw ("TerminalStyles: could not parse Windows Terminal settings.json. " +
               "On Windows PowerShell 5.1, JSON comments other than // and /* */ are not supported -- " +
               "open WT Settings and Save once, or remove the offending text. " +
               "Underlying error: $($_.Exception.Message)")
    }
}

function Test-ManagedBackgroundPath {
    # True when a profile's backgroundImage points at a file TerminalStyles put
    # there itself: a bundled styles\<name>\background.* under the module root,
    # or a lazily-fetched copy under the data root's cache\. Anything else --
    # the user's own image, or Windows Terminal keywords like
    # 'desktopWallpaper' -- is theirs, and the merge leaves it alone.
    #
    # This is what lets a bundle-less style clear the PREVIOUS style's
    # background without also clobbering a background the user chose.
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($script:TStylesModuleRoot, $script:TStylesDataRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($r)) { $roots.Add($r) }
    }
    # PSResourceGet installs each version to its own sibling dir
    # (...\Modules\TerminalStyles\<version>\), so a background written by an
    # earlier version sits OUTSIDE the current module root. Treat the whole
    # ...\Modules\TerminalStyles\ tree as ours -- but only when the parent is
    # literally named TerminalStyles, so this can't swallow a neighbouring
    # module's files.
    $parent = Split-Path $script:TStylesModuleRoot -Parent
    if ($parent -and (Split-Path $parent -Leaf) -eq 'TerminalStyles') {
        $roots.Add($parent)
    }

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        try {
            # GetFullPath normalises separators/casing-insensitive comparison and
            # resolves any '..'; it does not require the file to exist. A WT
            # keyword like 'desktopWallpaper' resolves against the CWD and so
            # never lands under one of our roots.
            $full     = [System.IO.Path]::GetFullPath($Path)
            $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') +
                        [System.IO.Path]::DirectorySeparatorChar
        } catch {
            continue   # unparseable path (invalid chars) -- treat as not ours
        }
        # Compare against the root WITH a trailing separator so a sibling like
        # 'TerminalStylesEvil\x.gif' can't match the 'TerminalStyles' root.
        if ($full.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Merge-StyleIntoSettings {
    param(
        $Settings,
        [string]$StyleDir,
        [string]$TargetName,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided
    )

    $scheme = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    # Resolve / validate the target FIRST. A non-existent named profile must not
    # cause us to inject the color scheme -- that would leave an orphan scheme in
    # settings.json that Reset's cleanup can never remove (no profile references
    # it). 'defaults' is created lazily below, only when there's a theme to write.
    $namedEntry = $null
    if ($TargetName -ne 'defaults') {
        $namedEntry = $Settings.profiles.list | Where-Object name -eq $TargetName | Select-Object -First 1
        if (-not $namedEntry) { return $Settings }   # missing named target: leave settings untouched
    }

    if (-not $Settings.PSObject.Properties.Match('schemes').Count) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @()
    }
    $Settings.schemes = @($Settings.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme

    $themePath = Join-Path $StyleDir 'theme.json'
    if (-not (Test-Path -LiteralPath $themePath)) { return $Settings }
    $theme = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $entry = if ($TargetName -eq 'defaults') {
        if (-not $Settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $Settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $Settings.profiles.defaults
    } else {
        $namedEntry
    }
    if (-not $entry) { return $Settings }

    # Resolve effective background:
    #   1. User passed -BackgroundImage <path>  -> use that
    #   2. User passed -BackgroundImage ""      -> strip (remove fields entirely)
    #   3. Style ships a bundled background.*   -> use that
    #   4. Otherwise                            -> leave user's existing bg alone
    $effectiveBg = $BackgroundImage
    $applyBg = $BackgroundImageProvided
    if (-not $applyBg) {
        $bundled = Get-StyleBundledBackground -StyleDir $StyleDir
        if ($bundled) {
            $effectiveBg = $bundled
            $applyBg = $true
        }
    }

    # Three actions for bg fields:
    #   skip   : don't touch them
    #   remove : strip them from the profile (explicit empty path => disable)
    #   apply  : substitute the placeholder and write all bg fields
    #
    # When the new style ships no background, what happens depends on WHOSE
    # background is currently on the profile. One we wrote for the previously
    # applied style gets cleared -- otherwise it bleeds through and the new
    # style is shown behind the old style's GIF. A background the user set
    # themselves is left alone, which is what the skip is for.
    $existingBg = if ($entry.PSObject.Properties.Match('backgroundImage').Count -gt 0) {
        [string]$entry.backgroundImage
    } else { $null }

    $bgAction = if ($applyBg) {
                    if ([string]::IsNullOrEmpty($effectiveBg)) { 'remove' } else { 'apply' }
                }
                elseif (Test-ManagedBackgroundPath -Path $existingBg) { 'remove' }
                else { 'skip' }

    $bgFields = $script:TStylesBgFields
    foreach ($prop in $theme.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($name -in $bgFields) {
            if ($bgAction -eq 'skip') { continue }
            if ($bgAction -eq 'remove') {
                if ($entry.PSObject.Properties.Match($name).Count -gt 0) {
                    $entry.PSObject.Properties.Remove($name)
                }
                continue
            }
            # bgAction = 'apply'
            if ($name -eq 'backgroundImage' -and $value -eq '{{BACKGROUND_IMAGE}}') {
                $value = $effectiveBg
            }
        }

        if ($entry.PSObject.Properties.Match($name).Count -gt 0) {
            $entry.$name = $value
        } else {
            $entry | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }

    return $Settings
}

function Write-SettingsAtomic {
    # Write settings.json durably: serialize to a sibling temp file, then
    # atomically replace the live file. WriteAllText truncates-then-writes, so a
    # crash/kill or a concurrent reader (Windows Terminal watches settings.json
    # and reloads on change) can observe a half-written/empty file. A same-volume
    # rename is atomic on NTFS, so the live file is only ever the old bytes or the
    # complete new bytes -- never a truncated middle. Falls back to a direct copy
    # if Replace/Move is unsupported (e.g. an odd filesystem). UTF-8 no BOM.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    $enc = [System.Text.UTF8Encoding]::new($false)
    $tmp = "$Path.tstmp"
    [System.IO.File]::WriteAllText($tmp, $Json, $enc)
    try {
        if (Test-Path -LiteralPath $Path) {
            # backupFileName = [NullString]::Value: replace without keeping a
            # copy. A bare $null is coerced by PowerShell to '' here, which makes
            # Replace throw "path is empty" on PS7 and silently fall back to the
            # non-atomic in-place write below; [NullString]::Value passes a true
            # null so the atomic same-volume rename actually runs.
            [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        # Best-effort fallback (cross-volume temp, Replace unsupported, etc.).
        [System.IO.File]::WriteAllText($Path, $Json, $enc)
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-SettingsFile {
    param([string]$Path, $Settings)
    # Depth 100 (the JSON max) rather than 32: a deeply-nested user settings.json
    # over depth 32 is silently stringified (corrupted) by ConvertTo-Json --
    # without warning on Windows PowerShell 5.1.
    $json = $Settings | ConvertTo-Json -Depth 100
    Write-SettingsAtomic -Path $Path -Json $json
}

function Get-StyleDir {
    # Resolves a style name to its on-disk directory, checking the user
    # dir first ($DataRoot\styles\<name>\) then the bundled dir
    # ($ModuleRoot\styles\<name>\). Returns $null if neither has a
    # scheme.json for that name. User-wins matches Get-AvailableStyles'
    # union-and-dedup precedence.
    param([Parameter(Mandatory)][string]$StyleName)

    $userDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $StyleName
    if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) { return $userDir }

    $bundledDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $StyleName
    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) { return $bundledDir }

    return $null
}

function Get-AvailableStyles {
    # Returns DirectoryInfo for every styles/<name>/ that has a scheme.json,
    # merged from two locations:
    #   1. $DataRoot\styles\<name>\ -- user dir, persistent across updates
    #   2. $ModuleRoot\styles\<name>\ -- bundled, install-managed
    # User-wins on name collision (matches Get-StyleDir's precedence).
    # Sorted alphabetically by name.
    $userStylesDir    = Join-Path $script:TStylesDataRoot   'styles'
    $bundledStylesDir = Join-Path $script:TStylesModuleRoot 'styles'

    $user = if (Test-Path -LiteralPath $userStylesDir) {
        @(Get-ChildItem -LiteralPath $userStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $bundled = if (Test-Path -LiteralPath $bundledStylesDir) {
        @(Get-ChildItem -LiteralPath $bundledStylesDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'scheme.json')
        })
    } else { @() }

    $userNames = @($user | ForEach-Object Name)
    @(@($user) + @($bundled | Where-Object { $_.Name -notin $userNames })) | Sort-Object Name
}

function Get-CurrentStyleName {
    # Detects which bundled style is currently active by byte-comparing
    # current-style.ps1 against each style's profile.ps1. Returns $null
    # if nothing matches (custom profile, no current style, etc).
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        $current = [System.IO.File]::ReadAllText($script:TStylesCurrent, [System.Text.UTF8Encoding]::new($false))
        foreach ($style in (Get-AvailableStyles)) {
            $sp = Join-Path $style.FullName 'profile.ps1'
            if (-not (Test-Path -LiteralPath $sp)) { continue }
            $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
            if ($current -eq $styleContent) { return $style.Name }
        }
    }

    # Fall back to the recorded style. The byte-compare above can't see a style
    # applied with -KeepPrompt (which deliberately leaves current-style.ps1
    # absent) -- on OSC-driven terminals that would report "no style" while the
    # colors are plainly applied. The record knows regardless of the prompt.
    $record = Get-CurrentStyleRecord
    if ($record -and $record.name) {
        if (Get-StyleDir -StyleName $record.name) { return $record.name }
    }

    return $null
}

function Test-StyleResolved {
    # A style is "resolved" if we know its background state -- either a
    # bundled background.<ext> exists under $StyleDir (module root), or a
    # cached background.<ext>/.no-background exists under $DataRoot\cache\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir, [switch]$NoInherit)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir = Get-StyleCacheDir -StyleName $styleName
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $cacheDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }

    # Tuned styles inherit resolution from their base. -NoInherit suppresses
    # this (used on the recursive base call) so a cyclic tune.json (A->B->A)
    # cannot recurse -- resolution is strictly one hop.
    if (-not $NoInherit) {
        $tuneFile = Join-Path $StyleDir 'tune.json'
        if (Test-Path -LiteralPath $tuneFile) {
            try {
                $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($tune.base) {
                    $baseDir = Get-StyleDir -StyleName $tune.base
                    if ($baseDir -and ($baseDir -ne $StyleDir)) {
                        return (Test-StyleResolved -StyleDir $baseDir -NoInherit)
                    }
                }
            } catch { }
        }
    }
    return $false
}

function Get-SchemeSwatch {
    # Returns a one-line ANSI swatch (up to 5 colored blocks) summarising a
    # theme. Picks slots that actually distinguish themes from each other --
    # background, foreground, cursor accent, and two anchor ANSI hues -- and
    # falls back to other ANSI slots when those duplicate (e.g. sober has
    # cursorColor == foreground, eva has cursorColor == brightRed, which
    # would otherwise show the same color twice). Renders each slot as a
    # background-colored cell so even near-black colors stay visible against
    # the terminal background. Trailing reset.
    param([Parameter(Mandatory)]$Scheme)
    # Primary picks first, then fallbacks in order of theme-distinguishing
    # power. The first 5 unique hex values from this list are rendered.
    $candidates = @(
        $Scheme.background,
        $Scheme.foreground,
        $Scheme.cursorColor,
        $Scheme.brightRed,
        $Scheme.brightCyan,
        $Scheme.selectionBackground,
        $Scheme.brightPurple,
        $Scheme.brightYellow,
        $Scheme.brightGreen,
        $Scheme.brightBlue
    )
    $seen = @{}
    $picks = @()
    foreach ($hex in $candidates) {
        if ($picks.Count -ge 5) { break }
        if (-not $hex) { continue }
        $key = ([string]$hex).TrimStart('#').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $picks += $hex
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($hex in $picks) {
        $h = ([string]$hex).TrimStart('#')
        if ($h.Length -lt 6) { continue }
        $r = [Convert]::ToInt32($h.Substring(0,2), 16)
        $g = [Convert]::ToInt32($h.Substring(2,2), 16)
        $b = [Convert]::ToInt32($h.Substring(4,2), 16)
        [void]$sb.Append([char]27).Append("[48;2;${r};${g};${b}m    ").Append([char]27).Append('[49m ')
    }
    [void]$sb.Append([char]27).Append('[0m')
    return $sb.ToString()
}

function Show-StyleList {
    # `tstyles list` -- print available styles, marking the active one.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $styles = Get-AvailableStyles
    Write-Host ""
    Write-Host "Available styles:" -ForegroundColor Cyan
    foreach ($s in $styles) {
        $marker = if ($s.Name -eq $current) { '*' } else { ' ' }
        $schemePath = Join-Path $s.FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatch = Get-SchemeSwatch -Scheme $scheme
        Write-Host ("  {0} {1,-16}  {2}" -f $marker, $s.Name, $swatch)
    }
    Write-Host ""
    if ($current) {
        Write-Host "$([char]27)[38;2;160;160;160m  (* = currently active)$([char]27)[0m"
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m  (no bundled style currently active)$([char]27)[0m"
    }
    Write-Host ""
}

function Show-CurrentStyle {
    # `tstyles current` -- print the active style name. Interactive callers
    # see name + swatch (visual self-check); piped/redirected callers get
    # just the name on stdout, preserving scriptability for `tstyles current
    # | grep ...` etc.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    if ($current) {
        if ([Console]::IsOutputRedirected) {
            Write-Output $current
        } else {
            $styleDir = Get-StyleDir -StyleName $current
            $schemePath = if ($styleDir) { Join-Path $styleDir 'scheme.json' } else { $null }
            if ($schemePath -and (Test-Path -LiteralPath $schemePath)) {
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                Write-Host ("{0,-16}  {1}" -f $current, (Get-SchemeSwatch -Scheme $scheme))
            } else {
                Write-Host $current
            }
        }
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m(no bundled style currently active)$([char]27)[0m"
    }
}

function Invoke-RandomStyle {
    # `tstyles random` -- pick a random bundled style and apply it.
    # Excludes the currently active one so it actually changes.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $candidates = @(Get-AvailableStyles | Where-Object { $_.Name -ne $current })
    if (-not $candidates) {
        Write-Host "No other styles to switch to." -ForegroundColor Yellow
        return
    }
    $pick = $candidates | Get-Random
    Write-Host ""
    Write-Host "Rolling the dice... -> " -NoNewline
    Write-Host $pick.Name -ForegroundColor Cyan
    Apply-StyleDirect -StyleName $pick.Name
}

function Apply-StyleNonWT {
    # Apply a style on a terminal that is not Windows Terminal.
    #
    # There is no settings.json to merge into, so the work splits in two:
    #   * colors    -- emitted as an OSC packet, which retints the CURRENT tab
    #                  instantly. Recorded in current-style.json so the startup
    #                  block at the bottom of this file can re-emit it into
    #                  every future tab.
    #   * prompt    -- the style's profile.ps1 is copied to current-style.ps1
    #                  and dot-sourced, exactly as on Windows Terminal. That
    #                  file is plain PowerShell + ANSI and is already portable.
    #
    # Fields the host terminal cannot honour (a background image on Terminal.app,
    # a tab accent color anywhere but WT) are reported rather than silently
    # dropped, so the user knows why the style looks plainer than its screenshot.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [switch]$KeepPrompt
    )

    $kind = Get-TerminalKind
    $caps = Get-TerminalCapability -Kind $kind

    $schemePath = Join-Path $StyleDir 'scheme.json'
    if (-not (Test-Path -LiteralPath $schemePath)) {
        Write-Error "Style '$StyleName' has no scheme.json."
        return
    }
    $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $applied = Invoke-TerminalStyleOscApply -Scheme $scheme -Kind $kind
    Set-CurrentStyleRecord -StyleName $StyleName -Kind $kind

    # Prompt/banner: same contract as the Windows Terminal path.
    $styleProfile = Join-Path $StyleDir 'profile.ps1'
    if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
        Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
    } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force
    }

    Write-Host ""
    Write-Host "  Style applied: " -NoNewline
    Write-Host $StyleName -ForegroundColor Green
    Write-Host "  Terminal:      " -NoNewline
    Write-Host (Get-TerminalDisplayName -Kind $kind) -ForegroundColor Cyan

    if (-not $applied) {
        Write-Host ""
        Write-Host "  Note: this terminal did not accept live color changes, so only the prompt was applied." -ForegroundColor Yellow
    }

    # Tell the user which parts of the style this terminal cannot show, once,
    # rather than letting them wonder why it doesn't match the screenshot.
    $unsupported = @()
    $theme = $null
    $themePath = Join-Path $StyleDir 'theme.json'
    if (Test-Path -LiteralPath $themePath) {
        try {
            $theme = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        } catch { $theme = $null }
    }
    if ($theme) {
        if ((Get-StyleBundledBackground -StyleDir $StyleDir) -and -not $caps.BackgroundImage) {
            $unsupported += 'background image'
        }
        if ($theme.PSObject.Properties.Match('tabColor').Count -gt 0 -and -not $caps.TabColor) {
            $unsupported += 'tab color'
        }
    }
    if ($unsupported.Count -gt 0) {
        Write-Host ""
        Write-Host ("  {0} can't show: {1}." -f (Get-TerminalDisplayName -Kind $kind), ($unsupported -join ', ')) -ForegroundColor DarkGray
    }
    Write-Host ""

    # Live reload of the prompt in THIS shell (matches the WT confirm path).
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        . $script:TStylesCurrent
    }
}

function Apply-StyleDirect {
    # Apply a style directly (no picker UI). Used by `tstyles <name>` and
    # `tstyles random`. Mirrors the picker's confirm path -- merge into
    # settings.json, copy profile.ps1 to current-style.ps1, dot-source for
    # live reload.
    #
    # Off Windows Terminal the settings.json half does not exist; Apply-StyleNonWT
    # takes over with the OSC + current-style.json path instead.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided = $false,
        # Apply the visuals but not the style's prompt/banner: clears
        # current-style.ps1 so the user's own prompt stays in control.
        [switch]$KeepPrompt
    )

    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    Show-UpdateNoticeIfAvailable

    # Non-WT hosts have no settings.json; hand off before we go looking for one.
    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        Apply-StyleNonWT -StyleName $StyleName -StyleDir $styleDir -KeepPrompt:$KeepPrompt
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = ConvertFrom-WTJson $originalJson

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile. Pass -Target <name>."
        return
    }

    # Rolling backup: copy the on-disk settings.json to settings.json.bak
    # before any mutation. Single file, overwritten on each direct apply --
    # gives the user a one-line undo without filling LocalState with timestamped
    # backups over time. The picker doesn't need this (Esc reverts in-memory);
    # apply.ps1 keeps its own timestamped audit trail. -ErrorAction Stop so
    # non-terminating errors (permission denied, etc.) enter the catch block
    # rather than silently logging via $Error.
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
        -TargetName $Target -BackgroundImage $BackgroundImage `
        -BackgroundImageProvided $BackgroundImageProvided
    Write-SettingsFile -Path $settingsPath -Settings $settings

    # Detect pwsh target for profile.ps1 install + live reload
    $isPwshTarget = $false
    if ($Target -eq 'defaults') {
        $isPwshTarget = $true
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
        $cmd = "$($entry.commandline)"
        $src = "$($entry.source)"
        if ($src -eq 'Windows.Terminal.PowershellCore' -or
            $cmd -match '(?i)\bpwsh\.exe\b' -or
            $cmd -match '(?i)\bpowershell\.exe\b') {
            $isPwshTarget = $true
        }
    }

    $styleProfile = Join-Path $styleDir 'profile.ps1'
    if ($isPwshTarget) {
        if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
            Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
        } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
            Remove-Item -LiteralPath $script:TStylesCurrent -Force
        }
    }

    Write-Host ""
    Write-Host "  Style applied: " -NoNewline
    Write-Host $StyleName -ForegroundColor Green
    Write-Host ""

    # Live reload (same pattern as the picker's confirm path)
    if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
        . $script:TStylesCurrent
    }
}

function Invoke-TerminalStylesRegister {
    # Adds `Import-Module TerminalStyles -DisableNameChecking` to both
    # PowerShell engines' $PROFILE files, wrapped in the same
    # # ===== TerminalStyles BEGIN ===== / END markers that
    # Invoke-TerminalStylesUninstall knows how to strip.
    #
    # Idempotent: skips an engine whose $PROFILE already has the block.
    # -Force replaces the existing block (strip + re-add).
    #
    # -Targets is an internal/test injection: tests pass a synthetic
    # array of objects with ProfilePath/Exists/HasLoader/Label fields,
    # bypassing the real engine discovery (which Pester 5 can't cleanly
    # mock because it goes through the call-operator `& $cmd.Source`).
    # Real callers never pass -Targets and get the normal discovery.
    [CmdletBinding()]
    param(
        [switch]$Force,
        [object[]]$Targets
    )

    $loaderBegin = '# ===== TerminalStyles BEGIN ====='
    $loaderEnd   = '# ===== TerminalStyles END ====='
    $loaderBody  = @"
$loaderBegin
Import-Module TerminalStyles -DisableNameChecking
$loaderEnd
"@

    if (-not $Targets) {
        # Discover both engines, get $PROFILE per engine
        $shells = @(
            @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
            @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
        )
        $targets = @()
        foreach ($s in $shells) {
            $cmd = Get-Command -Name $s.Exe -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
            if (-not $profilePath) { continue }
            $profilePath = "$profilePath".Trim()
            if (-not $profilePath) { continue }
            $targets += [pscustomobject]@{
                Label       = $s.Label
                ProfilePath = $profilePath
                Exists      = Test-Path -LiteralPath $profilePath
                HasLoader   = $false
            }
        }
    } else {
        $targets = @($Targets)
        # For test-injected targets, ensure required fields exist
        foreach ($t in $targets) {
            if ($null -eq $t.Exists)    { $t | Add-Member -NotePropertyName Exists    -NotePropertyValue (Test-Path -LiteralPath $t.ProfilePath) -Force }
            if ($null -eq $t.HasLoader) { $t | Add-Member -NotePropertyName HasLoader -NotePropertyValue $false -Force }
            if ($null -eq $t.Label)     { $t | Add-Member -NotePropertyName Label     -NotePropertyValue 'PowerShell' -Force }
        }
    }

    if (-not $targets) {
        Write-Host ""
        Write-Host "Neither pwsh.exe nor powershell.exe was found on PATH. Nothing to do." -ForegroundColor Yellow
        return
    }

    # Detect existing loader block per target
    $blockPattern = "(?ms)$([regex]::Escape($loaderBegin)).*?$([regex]::Escape($loaderEnd))\r?\n?"
    foreach ($t in $targets) {
        if ($t.Exists) {
            $content = [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
            $t.HasLoader = ($content -match $blockPattern)
        }
    }

    # Decide what to do per target
    $toWrite = @()
    foreach ($t in $targets) {
        if ($t.HasLoader -and -not $Force) {
            Write-Host "  Already registered in $($t.ProfilePath) (use -Force to replace)" -ForegroundColor Gray
            continue
        }
        $toWrite += $t
    }

    if (-not $toWrite) {
        Write-Host ""
        Write-Host "Nothing to do." -ForegroundColor Yellow
        return
    }

    # Single confirm prompt covering all targets
    Write-Host ""
    Write-Host "Will register the TerminalStyles loader in:" -ForegroundColor Cyan
    foreach ($t in $toWrite) {
        Write-Host "  $($t.Label): $($t.ProfilePath)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "The loader is one line wrapped in BEGIN/END markers:" -ForegroundColor Gray
    Write-Host "  Import-Module TerminalStyles -DisableNameChecking" -ForegroundColor Cyan
    Write-Host ""
    $ans = Read-Host "Continue? [Y/n]"
    if ($ans -match '^(?i)n') {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # Write the block per target (strip first for -Force path)
    foreach ($t in $toWrite) {
        $profileDir = Split-Path -Parent $t.ProfilePath
        if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        $existing = if ($t.Exists) {
            [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
        } else { '' }

        if ($existing -match $blockPattern) {
            $existing = [regex]::Replace($existing, $blockPattern, '')
        }

        $final = ($existing.TrimEnd() + "`r`n`r`n" + $loaderBody + "`r`n").TrimStart()
        [System.IO.File]::WriteAllText($t.ProfilePath, $final, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Registered in $($t.ProfilePath)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "TerminalStyles will auto-load on every new shell tab." -ForegroundColor Cyan
    Write-Host "To verify in this session: Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData    # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
    )

    $dataDir = Get-TStylesDataRoot
    $kind = Get-TerminalStylesInstallKind

    Write-Host ""
    Write-Host "This will uninstall TerminalStyles (detected: $kind):" -ForegroundColor Yellow
    switch ($kind) {
        'PSResourceGet' {
            Write-Host "  - Uninstall-PSResource -Name TerminalStyles" -ForegroundColor Yellow
        }
        'Bootstrap' {
            Write-Host "  - Remove install-managed files from $dataDir" -ForegroundColor Yellow
        }
    }
    Write-Host "  - Strip the loader block from pwsh 7 and Windows PowerShell 5.1 `$PROFILE files" -ForegroundColor Yellow
    if ($DeleteData) {
        Write-Host "  - DELETE the entire $dataDir (user state: active style, cached GIFs, throttle stamp)" -ForegroundColor Red
    } else {
        Write-Host "  - PRESERVE user state ($dataDir contents -- pass -DeleteData to wipe)" -ForegroundColor Gray
    }
    Write-Host "  - Will NOT modify Windows Terminal's settings.json." -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Host "Continue? [y/N]"
    if ($ans -notmatch '^(?i)y') {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # 1. Remove the module / install-managed files
    switch ($kind) {
        'PSResourceGet' {
            try {
                Uninstall-PSResource -Name TerminalStyles -ErrorAction Stop
                Write-Host "  Removed module via Uninstall-PSResource" -ForegroundColor Green
            } catch {
                Write-Host "  Uninstall-PSResource failed: $_" -ForegroundColor Red
            }
        }
        'Bootstrap' {
            $installManagedItems = @(
                'tstyles.ps1', 'apply.ps1', 'install.ps1',
                'TerminalStyles.psd1', 'TerminalStyles.psm1',
                'styles', 'scripts',
                'README.md', 'LICENSE'
            )
            foreach ($item in $installManagedItems) {
                $path = Join-Path $dataDir $item
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  Removed install-managed files from $dataDir" -ForegroundColor Green
        }
    }

    # 2. Strip the loader from both PowerShell engines' $PROFILE
    foreach ($exe in 'pwsh.exe', 'powershell.exe') {
        $cmd = Get-Command -Name $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $profilePath = $profilePath.Trim()
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }

        $content = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
        $newContent = [regex]::Replace($content, '(?ms)# ===== TerminalStyles BEGIN =====.*?# ===== TerminalStyles END =====\r?\n?', '')
        if ($newContent -ne $content) {
            [System.IO.File]::WriteAllText($profilePath, $newContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Removed loader from $profilePath" -ForegroundColor Green
        }
    }

    # 3. Optionally remove user state
    if ($DeleteData) {
        if (Test-Path -LiteralPath $dataDir) {
            Remove-Item -LiteralPath $dataDir -Recurse -Force
            Write-Host "  Removed $dataDir (full wipe via -DeleteData)" -ForegroundColor Green
        }
    } else {
        Write-Host ""
        Write-Host "  User state preserved at $dataDir" -ForegroundColor Gray
        Write-Host "  Pass -DeleteData to remove that too." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    Write-Host "Open a new pwsh tab to confirm the loader is gone." -ForegroundColor Gray
    Write-Host "Your settings.json was NOT modified. If you want a default look back," -ForegroundColor Gray
    Write-Host "restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
    Write-Host ""
}

function Convert-HueToRgb {
    # HSL hue helper. Internal to Convert-HexAdjust.
    param([double]$P, [double]$Q, [double]$T)
    if ($T -lt 0) { $T += 1.0 }
    if ($T -gt 1) { $T -= 1.0 }
    if ($T -lt (1.0/6.0)) { return $P + ($Q - $P) * 6.0 * $T }
    if ($T -lt (1.0/2.0)) { return $Q }
    if ($T -lt (2.0/3.0)) { return $P + ($Q - $P) * ((2.0/3.0) - $T) * 6.0 }
    return $P
}

function Convert-HexAdjust {
    # hex -> RGB -> HSL -> adjust (L additive, S multiplicative) -> RGB -> hex.
    # Brightness/Saturation in -100..+100. Preserves a leading '#'. Lowercase out.
    param(
        [Parameter(Mandatory)][string]$Hex,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $hadHash = $Hex.StartsWith('#')
    $h = $Hex.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($h.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($h.Substring(4,2),16) / 255.0

    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $d = $max - $min
    if ($d -eq 0) {
        $hh = 0.0; $s = 0.0
    } else {
        $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        if     ($max -eq $r) { $hh = (($g - $b) / $d) % 6 }
        elseif ($max -eq $g) { $hh = (($b - $r) / $d) + 2 }
        else                 { $hh = (($r - $g) / $d) + 4 }
        $hh = $hh * 60.0
        if ($hh -lt 0) { $hh += 360.0 }
    }

    $l = [Math]::Max(0.0, [Math]::Min(1.0, $l + ($Brightness / 100.0) * 0.5))
    $s = [Math]::Max(0.0, [Math]::Min(1.0, $s * (1.0 + ($Saturation / 100.0))))

    if ($s -eq 0) {
        $r2 = $l; $g2 = $l; $b2 = $l
    } else {
        $q = if ($l -lt 0.5) { $l * (1.0 + $s) } else { $l + $s - $l * $s }
        $p = 2.0 * $l - $q
        $hk = $hh / 360.0
        $r2 = Convert-HueToRgb -P $p -Q $q -T ($hk + 1.0/3.0)
        $g2 = Convert-HueToRgb -P $p -Q $q -T $hk
        $b2 = Convert-HueToRgb -P $p -Q $q -T ($hk - 1.0/3.0)
    }

    $ri = [int][Math]::Round($r2 * 255.0)
    $gi = [int][Math]::Round($g2 * 255.0)
    $bi = [int][Math]::Round($b2 * 255.0)
    $out = '{0:x2}{1:x2}{2:x2}' -f $ri, $gi, $bi
    if ($hadHash) { return "#$out" } else { return $out }
}

function Get-AdjustedScheme {
    # Returns a NEW scheme object (does not mutate $Scheme) with every hex
    # color slot adjusted by the brightness/saturation deltas in HSL space.
    # Non-color props (name, etc.) pass through. Missing slots skipped;
    # malformed hex passed through unchanged.
    param(
        [Parameter(Mandatory)]$Scheme,
        [int]$Brightness = 0,
        [int]$Saturation = 0
    )
    $slots = @('background','foreground','cursorColor','selectionBackground',
               'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite')
    $out = [pscustomobject]@{}
    foreach ($prop in $Scheme.PSObject.Properties) {
        $name = $prop.Name
        $val  = $prop.Value
        if (($name -in $slots) -and ($val -is [string]) -and ($val -match '^#?[0-9a-fA-F]{6}$')) {
            $val = Convert-HexAdjust -Hex $val -Brightness $Brightness -Saturation $Saturation
        }
        $out | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
    return $out
}

function Get-SchemeOscPacket {
    # Returns a single string of OSC escape sequences that, when written to
    # stdout, instantly retints the terminal's fg/bg/cursor/selection + the
    # 16-color palette to $Scheme -- no settings.json write, no WT reload.
    # Extracted from the picker so the tuner reuses the exact same format.
    param([Parameter(Mandatory)]$Scheme)
    $BEL = [char]7
    $E   = [char]27
    $palette = 'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite'
    $sb = [System.Text.StringBuilder]::new()
    if ($Scheme.foreground)          { [void]$sb.Append("$E]10;$($Scheme.foreground)$BEL") }
    if ($Scheme.background)          { [void]$sb.Append("$E]11;$($Scheme.background)$BEL") }
    if ($Scheme.cursorColor)         { [void]$sb.Append("$E]12;$($Scheme.cursorColor)$BEL") }
    if ($Scheme.selectionBackground) { [void]$sb.Append("$E]17;$($Scheme.selectionBackground)$BEL") }
    for ($p = 0; $p -lt $palette.Count; $p++) {
        $color = $Scheme.($palette[$p])
        if ($color) { [void]$sb.Append("$E]4;${p};${color}$BEL") }
    }
    return $sb.ToString()
}

function Get-OscResetPacket {
    # Returns OSC sequences that RESET the terminal's dynamic colors back to the
    # profile defaults: the full palette (OSC 104, no params) plus foreground
    # (110), background (111), cursor (112), and selection (117). The picker and
    # tuner retint live via Get-SchemeOscPacket; on Esc/cancel those overrides
    # would otherwise persist over the reverted settings.json, so we emit this to
    # hand color control back to Windows Terminal's configured scheme.
    $BEL = [char]7
    $E   = [char]27
    return "$E]104$BEL" + "$E]110$BEL" + "$E]111$BEL" + "$E]112$BEL" + "$E]117$BEL"
}

function Test-MonospaceFont {
    # True when $FamilyName renders as monospace (fixed advance width), detected
    # by measuring a narrow vs wide glyph. Pass a reusable $Graphics for speed
    # when measuring many fonts; omit it and one is created/disposed per call.
    # Any error (font not constructible, measurement fails) -> $false. Curated
    # favorites bypass this check entirely, so they're always offered.
    param(
        [Parameter(Mandatory)][string]$FamilyName,
        $Graphics
    )
    $ownGraphics = $false
    $bmp = $null
    try {
        if (-not $Graphics) {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $bmp = [System.Drawing.Bitmap]::new(1, 1)
            $Graphics = [System.Drawing.Graphics]::FromImage($bmp)
            $ownGraphics = $true
        }
        $font = [System.Drawing.Font]::new($FamilyName, 12.0)
        try {
            # GenericTypographic avoids layout padding, so the widths reflect the
            # glyph advance. Equal narrow/wide advance (within tolerance) = mono.
            $fmt = [System.Drawing.StringFormat]::GenericTypographic
            $wi = $Graphics.MeasureString('i', $font, [int]::MaxValue, $fmt).Width
            $ww = $Graphics.MeasureString('W', $font, [int]::MaxValue, $fmt).Width
            return [Math]::Abs($wi - $ww) -lt 0.5
        } finally {
            $font.Dispose()
        }
    } catch {
        return $false
    } finally {
        if ($ownGraphics) {
            if ($Graphics) { $Graphics.Dispose() }
            if ($bmp)      { $bmp.Dispose() }
        }
    }
}

function Get-MonospaceFontList {
    # Ordered, de-duplicated list of monospace font families to cycle in the
    # tuner: current font first, then installed curated favorites (always
    # trusted), then every OTHER installed monospace font (alphabetical),
    # Consolas fallback. -Installed and -MonospaceNames are test seams; real
    # callers omit them and we enumerate (System.Drawing) + measure
    # (Test-MonospaceFont). Curated favorites never get measured.
    param(
        [string]$Current,
        [string[]]$Installed,
        [string[]]$MonospaceNames
    )
    if (-not $Installed) {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            $Installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
        } catch {
            $Installed = @()
        }
    }

    $allow = @('Cascadia Mono','Cascadia Code','Consolas','JetBrains Mono',
               'Fira Code','Hack','Source Code Pro','DejaVu Sans Mono',
               'Lucida Console','Courier New')
    $favorites = @($allow | Where-Object { $_ -in $Installed })

    # $null means "not provided" -> measure. An explicit empty array (tests, or
    # a host without System.Drawing) means "no monospace beyond favorites".
    if ($null -eq $MonospaceNames) {
        $MonospaceNames = @()
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            $bmp = [System.Drawing.Bitmap]::new(1, 1)
            $g   = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                # Favorites are always offered, so skip measuring them.
                $MonospaceNames = @($Installed |
                    Where-Object { $_ -notin $favorites } |
                    Where-Object { Test-MonospaceFont -FamilyName $_ -Graphics $g })
            } finally {
                $g.Dispose(); $bmp.Dispose()
            }
        } catch {
            $MonospaceNames = @()
        }
    }

    $others = @($MonospaceNames | Where-Object { $_ -notin $favorites } | Sort-Object)
    $list = @($favorites) + @($others)
    if (-not $list) { $list = @('Consolas') }
    if ($Current) {
        $list = @($Current) + @($list | Where-Object { $_ -ne $Current })
    }
    return @($list | Select-Object -Unique)
}

function Get-FontCatalog {
    # Parse the bundled font catalog (fonts.json). Returns the array of font
    # entries, skipping any that lack a required field. Throws on missing file
    # or invalid JSON.
    param([string]$Path = (Join-Path $PSScriptRoot 'fonts.json'))

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Font catalog not found: $Path"
    }
    $json = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    $data = $json | ConvertFrom-Json   # throws on malformed JSON
    # @($data.fonts) is @() in PS7 but @($null) (one null element) in WinPS 5.1 when 'fonts' is absent/null; the per-entry null check below covers both.
    $entries = @($data.fonts)
    $valid = foreach ($e in $entries) {
        if (-not $e) { continue }
        if (-not $e.name -or -not $e.family -or -not $e.url -or -not $e.sha256) { continue }
        $e
    }
    return @($valid)
}

function Test-FontInstalled {
    # True when $Family is among installed font families (case-insensitive).
    # -Installed is a test seam; real callers omit it and we enumerate.
    param(
        [Parameter(Mandatory)][string]$Family,
        [string[]]$Installed
    )
    if (-not $PSBoundParameters.ContainsKey('Installed')) {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            $Installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
        } catch {
            $Installed = @()
        }
    }
    return @($Installed | Where-Object { $_ -and $_.Trim().ToLowerInvariant() -eq $Family.Trim().ToLowerInvariant() }).Count -gt 0
}

function Get-UserFontInstallPlan {
    # Pure: map font files to their per-user install destinations + HKCU registry
    # value names. No filesystem/registry writes happen here.
    param(
        [Parameter(Mandatory)][string[]]$FontFiles,
        [string]$FontsDir = (Get-TStylesFontDir)
    )
    foreach ($f in $FontFiles) {
        $leaf = Split-Path -Leaf $f
        $ext  = [System.IO.Path]::GetExtension($leaf).ToLowerInvariant()
        $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
        $kind = if ($ext -eq '.otf') { 'OpenType' } else { 'TrueType' }
        $dest = [System.IO.Path]::Combine($FontsDir, $leaf)
        [pscustomobject]@{
            Source    = $f
            Dest      = $dest
            ValueName = "$base ($kind)"
            ValueData = $dest
        }
    }
}

function Resolve-FontPackage {
    # Download (or use -DownloadPath), verify SHA-256, and extract the listed
    # font files into the cache. Returns the extracted file paths. Throws on a
    # missing/empty download, a hash mismatch, or a listed file absent from the
    # archive -- never leaves a partially-installed state.
    param(
        [Parameter(Mandatory)]$Font,
        [string]$CacheRoot = (Join-Path $script:TStylesDataRoot 'fonts'),
        [string]$DownloadPath
    )
    $cacheDir = Join-Path $CacheRoot $Font.name

    $archive = $DownloadPath
    if (-not $archive) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        $archive = Join-Path $cacheDir 'download.bin'
        $prev = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Font.url -OutFile $archive -UseBasicParsing -ErrorAction Stop
        } finally { $ProgressPreference = $prev }
    }
    if (-not (Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -eq 0) {
        throw "Font download for '$($Font.name)' was empty or missing."
    }

    $actual = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ("$($Font.sha256)").ToLowerInvariant()) {
        throw "SHA-256 mismatch for '$($Font.name)' (expected $($Font.sha256), got $actual). Refusing to install."
    }

    # Hash gate passed -- safe to create the extract directory now.
    $extractDir = Join-Path $cacheDir 'files'
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    # A direct .ttf/.otf download (no 'files') -- copy it through as-is.
    $ext = [System.IO.Path]::GetExtension($archive).ToLowerInvariant()
    if ((-not $Font.files -or @($Font.files).Count -eq 0) -and ($ext -in '.ttf','.otf','.ttc')) {
        $dest = Join-Path $extractDir (Split-Path -Leaf $Font.url)
        Copy-Item -LiteralPath $archive -Destination $dest -Force
        [string[]]$out = @($dest)
        return ,$out
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    [string[]]$out = @()
    try {
        foreach ($want in @($Font.files)) {
            $norm = $want -replace '\\','/'
            $entry = $zip.Entries | Where-Object { ($_.FullName -replace '\\','/') -eq $norm } | Select-Object -First 1
            if (-not $entry) { throw "Archive for '$($Font.name)' has no entry '$want'." }
            $dest = Join-Path $extractDir (Split-Path -Leaf $norm)
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
            $out += $dest
        }
    } finally {
        $zip.Dispose()
    }
    return ,$out
}

function Install-Font {
    # Install font files for the current user (no admin): copy to the per-user
    # Fonts dir, register under HKCU, then activate in the current session via
    # AddFontResource + a WM_FONTCHANGE broadcast so new processes (and WT on
    # reload) see them. -FontsDir / -RegistryRoot are test seams.
    param(
        [Parameter(Mandatory)][string[]]$FontFiles,
        [string]$FontsDir = (Get-TStylesFontDir),
        [string]$RegistryRoot = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    if (-not (Test-Path -LiteralPath $FontsDir)) {
        New-Item -ItemType Directory -Path $FontsDir -Force | Out-Null
    }

    # Registration is a Windows-only concept. On macOS, CoreText scans
    # ~/Library/Fonts and picks up a dropped file immediately -- no registry, no
    # broadcast. On Linux, fontconfig indexes the dir (fc-cache below nudges it).
    $isWindows = (Get-TStylesPlatform) -eq 'Windows'

    if ($isWindows -and -not (Test-Path -LiteralPath $RegistryRoot)) {
        New-Item -Path $RegistryRoot -Force | Out-Null
    }

    $plan = Get-UserFontInstallPlan -FontFiles $FontFiles -FontsDir $FontsDir
    $count = 0
    foreach ($p in $plan) {
        Copy-Item -LiteralPath $p.Source -Destination $p.Dest -Force
        if ($isWindows) {
            New-ItemProperty -Path $RegistryRoot -Name $p.ValueName -Value $p.ValueData -PropertyType String -Force | Out-Null
        }
        $count++
    }

    if (-not $isWindows) {
        # Best-effort cache refresh for fontconfig (Linux, and macOS setups that
        # have it via Homebrew). Absent on a stock Mac, where it isn't needed.
        if ((Get-TStylesPlatform) -eq 'Linux') {
            try {
                if (Get-Command fc-cache -ErrorAction SilentlyContinue) {
                    & fc-cache -f $FontsDir *> $null
                }
            } catch { }
        }
        return $count
    }

    # Activate in this session (best effort; the file+registry install is the
    # durable part, so failures here are non-fatal).
    try {
        if (-not ('TStylesFontApi' -as [type])) {
            Add-Type -Namespace '' -Name 'TStylesFontApi' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResource(string lpFileName);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam, uint flags, uint timeout, out System.IntPtr result);
'@
        }
        foreach ($p in $plan) { [void][TStylesFontApi]::AddFontResource($p.Dest) }
        $HWND_BROADCAST = [System.IntPtr]0xffff; $WM_FONTCHANGE = 0x001D
        $res = [System.IntPtr]::Zero
        [void][TStylesFontApi]::SendMessageTimeout($HWND_BROADCAST, $WM_FONTCHANGE, [System.IntPtr]::Zero, [System.IntPtr]::Zero, 0, 1000, [ref]$res)
    } catch { }

    return $count
}

function Set-ProfileFont {
    # Set $Family as the font.face on the target Windows Terminal profile (or
    # profiles.defaults). Returns $true if applied, $false if a named target
    # doesn't exist (file left untouched). Uses the atomic settings writer.
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$TargetName,
        [Parameter(Mandatory)][string]$Family
    )
    $json = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = ConvertFrom-WTJson $json

    $entry = $null
    if ($TargetName -eq 'defaults') {
        if (-not $settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $entry = $settings.profiles.defaults
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $TargetName | Select-Object -First 1
        if (-not $entry) { return $false }
    }

    if (-not $entry.PSObject.Properties.Match('font').Count) {
        $entry | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
    }
    if ($entry.font.PSObject.Properties.Match('face').Count) {
        $entry.font.face = $Family
    } else {
        $entry.font | Add-Member -NotePropertyName face -NotePropertyValue $Family -Force
    }

    Write-SettingsAtomic -Path $SettingsPath -Json ($settings | ConvertTo-Json -Depth 100)
    return $true
}

function Show-FontList {
    # List the font catalog with an installed/installable marker. -Catalog and
    # -Installed are test seams; real callers omit them.
    param(
        [object[]]$Catalog,
        [string[]]$Installed
    )
    if (-not $Catalog) { $Catalog = @(Get-FontCatalog) }
    Write-Host ""
    Write-Host "  Available coding fonts ([+] installed, [ ] installable):" -ForegroundColor Cyan
    Write-Host ""
    foreach ($f in $Catalog) {
        $isIn = if ($PSBoundParameters.ContainsKey('Installed')) {
            Test-FontInstalled -Family $f.family -Installed $Installed
        } else {
            Test-FontInstalled -Family $f.family
        }
        $mark = if ($isIn) { '[+]' } else { '[ ]' }
        Write-Host ("   {0} {1,-20} {2}" -f $mark, $f.name, $f.license)
    }
    Write-Host ""
    Write-Host "  Install + apply one with: tstyles font <name>" -ForegroundColor DarkGray
}

function Invoke-TerminalStyleFont {
    # `tstyles font` (list) / `tstyles font <name>` (install if needed + apply).
    param(
        [string]$Name,
        [string]$Target
    )
    if (-not $Name) { Show-FontList; return }

    $catalog = @(Get-FontCatalog)
    $font = $catalog | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $font) {
        Write-Host "Unknown font: '$Name'" -ForegroundColor Yellow
        Write-Host "Available: $(@($catalog | ForEach-Object name) -join ', ')" -ForegroundColor DarkGray
        return
    }

    if (Test-FontInstalled -Family $font.family) {
        Write-Host "'$($font.family)' is already installed." -ForegroundColor Green
    } else {
        Write-Host "Installing '$($font.name)'..." -ForegroundColor Cyan
        try {
            $files = Resolve-FontPackage -Font $font
            $n = Install-Font -FontFiles $files
            Write-Host "  Installed $n file(s) for '$($font.family)'." -ForegroundColor Green
        } catch {
            Write-Host "Font install failed: $_" -ForegroundColor Red
            return
        }
    }

    # Apply to the active profile.
    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) { Write-Host "Could not locate Windows Terminal settings.json." -ForegroundColor Red; return }
    if (-not $Target) {
        $json = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
        $Target = Get-CurrentWTProfileName -Settings (ConvertFrom-WTJson $json)
    }
    if (-not $Target) { Write-Host "Could not detect the current profile; pass -Target '<name>'." -ForegroundColor Yellow; return }

    try { [System.IO.File]::WriteAllText("$settingsPath.bak", [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false)), [System.Text.UTF8Encoding]::new($false)) } catch { }
    if (Set-ProfileFont -SettingsPath $settingsPath -TargetName $Target -Family $font.family) {
        Write-Host "  Applied '$($font.family)' to '$Target'. Open a new tab to see it." -ForegroundColor Green
    } else {
        Write-Host "Profile '$Target' not found in settings.json." -ForegroundColor Yellow
    }
}

function New-TunedThemeObject {
    # Builds the theme.json object for a tuned style: base theme.json (or {})
    # with colorScheme/opacity/font overridden. Preserves font.weight and the
    # backgroundImage placeholder. Shared by Save-TunedStyle and the live
    # preview so the saved result matches what was previewed.
    param(
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$ColorScheme,
        [int]$Opacity,
        [string]$FontFace,
        [int]$FontSize
    )
    $themeSrc = Join-Path $BaseStyleDir 'theme.json'
    $theme = if (Test-Path -LiteralPath $themeSrc) {
        [System.IO.File]::ReadAllText($themeSrc, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } else { [pscustomobject]@{} }

    $theme | Add-Member -NotePropertyName colorScheme -NotePropertyValue $ColorScheme -Force
    $theme | Add-Member -NotePropertyName opacity     -NotePropertyValue $Opacity     -Force

    $font = if ($theme.PSObject.Properties.Match('font').Count) { $theme.font } else { [pscustomobject]@{} }
    $font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
    $font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize -Force
    $theme | Add-Member -NotePropertyName font -NotePropertyValue $font -Force
    return $theme
}

function Save-TunedStyle {
    # Materializes a tuned style into $DataRoot\styles\$SaveName\:
    #   scheme.json (adjusted colors, name = $SaveName)
    #   theme.json  (base theme + colorScheme/opacity/font overrides)
    #   profile.ps1 (copied from base if present)
    #   tune.json   (deltas + base name, for re-tuning)
    param(
        [Parameter(Mandatory)]$AdjustedScheme,
        [Parameter(Mandatory)][string]$SaveName,
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$BaseName,
        [int]$Brightness, [int]$Saturation, [int]$Opacity,
        [string]$FontFace, [int]$FontSize
    )
    $destDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $SaveName
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Clone so the caller's object is not mutated (matches Get-AdjustedScheme's contract).
    $scheme = $AdjustedScheme.PSObject.Copy()
    $scheme | Add-Member -NotePropertyName name -NotePropertyValue $SaveName -Force
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'scheme.json'),
        ($scheme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $theme = New-TunedThemeObject -BaseStyleDir $BaseStyleDir -ColorScheme $SaveName `
        -Opacity $Opacity -FontFace $FontFace -FontSize $FontSize
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'theme.json'),
        ($theme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $profileSrc = Join-Path $BaseStyleDir 'profile.ps1'
    if (Test-Path -LiteralPath $profileSrc) {
        # Append a per-style marker so the materialized profile is byte-distinct
        # from the base's (we copied it verbatim). Without this, Get-CurrentStyleName
        # -- which byte-compares current-style.ps1 against each style's profile.ps1
        # and returns the alphabetically-first match -- would attribute this tuned
        # style to its base. The marker is an inert comment (profile is dot-sourced).
        $profileContent = [System.IO.File]::ReadAllText($profileSrc, [System.Text.UTF8Encoding]::new($false))
        $marker = [Environment]::NewLine + "# tstyles-tuned: $SaveName" + [Environment]::NewLine
        [System.IO.File]::WriteAllText(
            (Join-Path $destDir 'profile.ps1'),
            ($profileContent + $marker),
            [System.Text.UTF8Encoding]::new($false))
    }

    $tune = [pscustomobject]@{
        schemaVersion = 1
        base          = $BaseName
        brightness    = $Brightness
        saturation    = $Saturation
        opacity       = $Opacity
        fontFace      = $FontFace
        fontSize      = $FontSize
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'tune.json'),
        ($tune | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false))

    return $destDir
}

function Get-TunedBaseBackground {
    # If $StyleDir is a tuned style (tune.json with a 'base'), resolve and
    # return the base style's background (with the base's own lazy-fetch).
    # $null if not tuned / base missing / base has no background. Strictly one
    # hop: the base is resolved with -NoInherit, so cyclic tune.json (A->B->A)
    # cannot recurse.
    param([Parameter(Mandatory)][string]$StyleDir)
    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (-not (Test-Path -LiteralPath $tuneFile)) { return $null }
    try {
        $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return $null }
    if (-not $tune.base) { return $null }
    $baseDir = Get-StyleDir -StyleName $tune.base
    if (-not $baseDir -or ($baseDir -eq $StyleDir)) { return $null }
    return Get-StyleBundledBackground -StyleDir $baseDir -NoInherit
}

function Resolve-TuneSeed {
    # Computes the working base style + the initial knob values for `tstyles tune`.
    # Extracted from Invoke-TerminalStyleTune so the seeding rules are unit-testable.
    #
    # Rules:
    #   * A tuned style (tune.json with a base that still resolves) seeds the base
    #     dir + the recorded deltas, so re-deriving never double-applies onto the
    #     already-baked scheme.
    #   * Otherwise (a plain style, OR a tuned style whose recorded base was
    #     deleted/renamed) the working base is the style itself, and opacity/font
    #     seed from that style's OWN theme.json -- so re-tuning preserves the saved
    #     values instead of snapping back to the hardcoded defaults.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir
    )

    $seed = [pscustomobject]@{
        BaseName = $StyleName; BaseDir = $StyleDir
        Brightness = 0; Saturation = 0; Opacity = 100; FontFace = $null; FontSize = 12
    }
    $seededFromTune = $false

    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (Test-Path -LiteralPath $tuneFile) {
        try {
            $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($tune.base) {
                $resolvedBaseDir = Get-StyleDir -StyleName $tune.base
                # Guard against a self-referential base (an Overwrite save writes
                # the baked scheme back onto the base name and records base = that
                # name). Re-seeding the deltas here would re-apply them on top of
                # the already-baked scheme -- color drift on every re-tune. Fall
                # through to own-theme.json seeding (neutral brightness/saturation)
                # instead. Mirrors the self-reference guard in Get-TunedBaseBackground.
                if ($resolvedBaseDir -and $resolvedBaseDir -ne $StyleDir) {
                    $seed.BaseName   = $tune.base
                    $seed.BaseDir    = $resolvedBaseDir
                    $seed.Brightness = [int]$tune.brightness
                    $seed.Saturation = [int]$tune.saturation
                    $seed.Opacity    = [int]$tune.opacity
                    $seed.FontFace   = [string]$tune.fontFace
                    $seed.FontSize   = [int]$tune.fontSize
                    $seededFromTune  = $true
                }
            }
        } catch { }
    }

    # When NOT seeded from a resolvable tune, take opacity/font from the working
    # base's own theme.json (the base for a plain style; the style itself for a
    # tuned style whose base vanished).
    if (-not $seededFromTune) {
        $baseThemePath = Join-Path $seed.BaseDir 'theme.json'
        if (Test-Path -LiteralPath $baseThemePath) {
            try {
                $baseTheme = [System.IO.File]::ReadAllText($baseThemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($baseTheme.PSObject.Properties.Match('opacity').Count) { $seed.Opacity = [int]$baseTheme.opacity }
                if ($baseTheme.PSObject.Properties.Match('font').Count) {
                    if ($baseTheme.font.PSObject.Properties.Match('face').Count) { $seed.FontFace = [string]$baseTheme.font.face }
                    if ($baseTheme.font.PSObject.Properties.Match('size').Count) { $seed.FontSize = [int]$baseTheme.font.size }
                }
            } catch { }
        }
    }

    return $seed
}

function Invoke-TerminalStyleTune {
    # `tstyles tune [name]` -- interactive live tuning of a style's brightness,
    # saturation, opacity, font face, and font size. Colors retint instantly
    # via OSC; opacity/font ride a debounced settings.json write (through a
    # scratch style dir reusing Merge-StyleIntoSettings). Esc reverts byte-
    # exact; Enter prompts Save / Save As into the user-styles dir.
    [CmdletBinding()]
    param([string]$StyleName)

    Show-UpdateNoticeIfAvailable

    # --- Resolve the style (all guards run BEFORE any console interaction) ---
    if (-not $StyleName) {
        $StyleName = Get-CurrentStyleName
        if (-not $StyleName) {
            Write-Error "No active style detected. Try: tstyles tune <name>"
            return
        }
    }
    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    # --- Establish working base scheme + seed knob values ---
    # If this style is itself a tuned style (has tune.json), the working base
    # is its recorded base's PRISTINE scheme, and knobs seed from the deltas
    # (so re-deriving never double-applies onto the baked file). Otherwise the
    # working base is this style's own scheme with neutral knobs.
    $seed = Resolve-TuneSeed -StyleName $StyleName -StyleDir $styleDir
    $baseName   = $seed.BaseName
    $baseDir    = $seed.BaseDir
    $brightness = $seed.Brightness
    $saturation = $seed.Saturation
    $opacity    = $seed.Opacity
    $fontFace   = $seed.FontFace
    $fontSize   = $seed.FontSize

    $baseScheme = [System.IO.File]::ReadAllText((Join-Path $baseDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $fontList = Get-MonospaceFontList -Current $fontFace
    if (-not $fontFace) { $fontFace = $fontList[0] }
    $fontIdx = [Math]::Max(0, [array]::IndexOf($fontList, $fontFace))

    # --- Target WT profile ---
    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $originalSettings = ConvertFrom-WTJson $originalJson
    $target = Get-CurrentWTProfileName -Settings $originalSettings
    if (-not $target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to preview against."
        return
    }
    if (-not $env:WT_SESSION) {
        Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
    }

    # --- Scratch dir for the debounced settings.json preview (reuses Merge) ---
    $scratchDir = Join-Path (Join-Path $script:TStylesDataRoot '.tune-preview') $baseName
    if (-not (Test-Path -LiteralPath $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }

    # Knob model: index 0..4 = brightness, saturation, opacity, font face, size.
    $sel = 0
    $confirmed = $false
    $applied = $false   # set true only after a saved style is applied; gates the revert
    $pendingApply = $false  # the explicit `& $writePreview` below seeds the preview; this gates only knob edits

    $hint  = "$([char]27)[38;2;160;160;160m"
    $reset = "$([char]27)[0m"

    # Recompute the adjusted scheme + cache its OSC packet.
    $adjusted   = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
    $oscPacket  = Get-SchemeOscPacket -Scheme $adjusted

    $writePreview = {
        # Write scratch scheme/theme then merge into settings.json (brings
        # opacity/font/background live). Colors are already shown via OSC.
        $adj = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        $adj | Add-Member -NotePropertyName name -NotePropertyValue $baseScheme.name -Force
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'scheme.json'),
            ($adj | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        $theme = New-TunedThemeObject -BaseStyleDir $baseDir -ColorScheme $baseScheme.name `
            -Opacity $opacity -FontFace $fontFace -FontSize $fontSize
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'theme.json'),
            ($theme | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        # tune.json so background inheritance resolves the base GIF in preview.
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'tune.json'),
            ('{"base":"' + $baseName + '"}'), [System.Text.UTF8Encoding]::new($false))

        $preview = ConvertFrom-WTJson $originalJson
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $scratchDir `
            -TargetName $target -BackgroundImage '' -BackgroundImageProvided $false
        Write-SettingsAtomic -Path $settingsPath -Json ($preview | ConvertTo-Json -Depth 100)
    }

    $bar = {
        param([int]$Value, [int]$Min, [int]$Max)
        $width = 10
        $pos = [int][Math]::Round(($Value - $Min) / [double]($Max - $Min) * ($width - 1))
        $pos = [Math]::Max(0, [Math]::Min($width - 1, $pos))
        $cells = (1..$width | ForEach-Object { if (($_ - 1) -eq $pos) { 'o' } else { '-' } }) -join ''
        return "[$cells]"
    }

    $drawMenu = {
        Clear-Host
        Write-Host ""
        Write-Host "  Tuning " -NoNewline
        Write-Host "'$StyleName'" -ForegroundColor Cyan -NoNewline
        Write-Host "                      base: $baseName" -ForegroundColor DarkGray
        Write-Host "$hint  Up/Down select   Left/Right adjust   R reset color   Enter save   Esc cancel$reset"
        Write-Host ""
        $rows = @(
            @{ Label = 'Brightness'; Display = (& $bar $brightness -100 100); Value = ('{0:+#;-#;0}' -f $brightness) },
            @{ Label = 'Saturation'; Display = (& $bar $saturation -100 100); Value = ('{0:+#;-#;0}' -f $saturation) },
            @{ Label = 'Opacity';    Display = (& $bar $opacity 0 100);       Value = "$opacity%" },
            @{ Label = 'Font face';  Display = "< $fontFace >";                Value = '' },
            @{ Label = 'Font size';  Display = (& $bar $fontSize 6 36);        Value = "$fontSize" }
        )
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $color  = if ($i -eq $sel) { 'Yellow' } else { 'Gray' }
            $prefix = if ($i -eq $sel) { '   > ' } else { '     ' }
            Write-Host ($prefix + ('{0,-12} ' -f $rows[$i].Label) + ('{0,-14} ' -f $rows[$i].Display) + $rows[$i].Value) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  Preview  " -NoNewline
        Write-Host (Get-SchemeSwatch -Scheme $adjusted)
        Write-Host ""
    }

    # On-disk rolling backup before any preview write, so a hard kill mid-tune
    # leaves a recoverable copy (the in-memory $originalJson snapshot dies with
    # the process). Same rolling .bak the direct-apply/reset paths write.
    try { [System.IO.File]::WriteAllText("$settingsPath.bak", $originalJson, [System.Text.UTF8Encoding]::new($false)) } catch { }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle
    $needsRedraw = $true
    try {
        & $writePreview   # initial preview from seeds
        [Console]::Out.Write($oscPacket)

        while (-not $confirmed) {
            if ($needsRedraw) { & $drawMenu; $needsRedraw = $false }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $isColor = ($sel -eq 0 -or $sel -eq 1)
                switch ($key.Key) {
                    'UpArrow'   { if ($sel -gt 0) { $sel-- }; $needsRedraw = $true; continue }
                    'DownArrow' { if ($sel -lt 4) { $sel++ }; $needsRedraw = $true; continue }
                    'LeftArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Max(-100, $brightness - 5) }
                            1 { $saturation = [Math]::Max(-100, $saturation - 5) }
                            2 { $opacity    = [Math]::Max(0,    $opacity - 5) }
                            3 { $fontIdx = ($fontIdx - 1 + $fontList.Count) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Max(6, $fontSize - 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'RightArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Min(100, $brightness + 5) }
                            1 { $saturation = [Math]::Min(100, $saturation + 5) }
                            2 { $opacity    = [Math]::Min(100, $opacity + 5) }
                            3 { $fontIdx = ($fontIdx + 1) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Min(36, $fontSize + 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'R' {
                        $brightness = 0; $saturation = 0
                        $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness 0 -Saturation 0
                        $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                        [Console]::Out.Write($oscPacket)
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'Enter'  { if ($pendingApply) { & $writePreview; $pendingApply = $false }; $confirmed = $true; continue }
                    'Escape' {
                        Write-SettingsAtomic -Path $settingsPath -Json $originalJson
                        # Hand color control back to WT's configured scheme: the
                        # live OSC retint would otherwise linger over the reverted file.
                        [Console]::Out.Write((Get-OscResetPacket))
                        Clear-Host
                        Write-Host "Reverted." -ForegroundColor Yellow
                        return
                    }
                }
                continue
            }

            if ($pendingApply) { $pendingApply = $false; & $writePreview; continue }
            Start-Sleep -Milliseconds 50
        }

        # --- Confirmed: Save / Save As prompt ---
        Clear-Host
        Write-Host ""
        Write-Host "  Save tuned '$StyleName'?" -ForegroundColor Cyan
        Write-Host "    [1] Overwrite '$StyleName'   (shadows the bundled style)"
        Write-Host "    [2] Save as a new name"
        Write-Host ""
        $choice = (Read-Host "  Choose [1/2]").Trim()
        $saveName = $null
        if ($choice -eq '1') {
            $saveName = $StyleName
        } else {
            while (-not $saveName) {
                $candidate = (Read-Host "  New style name").Trim()
                if (-not $candidate) { Write-Host "  Cancelled." -ForegroundColor Gray; break }
                if ($candidate -notmatch '^[A-Za-z0-9._-]+$') {
                    Write-Host "  Use letters, digits, dot, underscore, or hyphen only." -ForegroundColor Yellow
                    continue
                }
                $bundledDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $candidate
                if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) {
                    $warn = (Read-Host "  That shadows bundled '$candidate'. Continue? [y/N]").Trim()
                    if ($warn -notmatch '^(?i)y') { continue }
                }
                $saveName = $candidate
            }
        }

        if (-not $saveName) {
            # Treat an aborted save like a cancel: revert and exit.
            Write-SettingsAtomic -Path $settingsPath -Json $originalJson
            [Console]::Out.Write((Get-OscResetPacket))
            Write-Host "  Reverted (nothing saved)." -ForegroundColor Yellow
            return
        }

        # Bake + persist, then apply the saved style from a clean settings.json
        # so no preview-scheme pollution lingers.
        $finalScheme = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        Save-TunedStyle -AdjustedScheme $finalScheme -SaveName $saveName `
            -BaseStyleDir $baseDir -BaseName $baseName `
            -Brightness $brightness -Saturation $saturation -Opacity $opacity `
            -FontFace $fontFace -FontSize $fontSize | Out-Null

        Write-SettingsAtomic -Path $settingsPath -Json $originalJson
        Apply-StyleDirect -StyleName $saveName -Target $target
        $applied = $true
    } finally {
        [Console]::CursorVisible = $true
        if (-not $applied) {
            # Safety net: restore settings.json + title unless a saved style was
            # applied. Esc / aborted-save already reverted explicitly; this also
            # covers an exception thrown mid-session (the key loop is not tested).
            Write-SettingsAtomic -Path $settingsPath -Json $originalJson
            [Console]::Out.Write((Get-OscResetPacket))
            $Host.UI.RawUI.WindowTitle = $originalTitle
        }
        if (Test-Path -LiteralPath $scratchDir) {
            Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-TerminalStyleHelpData {
    # Single source of truth for `tstyles help`. Ordered command descriptors.
    # Name is the dispatch token AND the `help <Name>` topic key. The picker
    # and `tstyles <style>` are arg-less modes described in the overview
    # preamble (Show-TerminalStyleHelp), not topics here. A drift-guard test
    # asserts every dispatched subcommand has an entry.
    @(
        [pscustomobject]@{
            Name = 'list'; Usage = 'list'; Summary = "List all styles; '*' marks the active one"
            Detail = @("Prints every available style (bundled + your own), one per line,",
                       "with the active style marked by an asterisk.")
            Keys = @(); Examples = @('tstyles list')
        }
        [pscustomobject]@{
            Name = 'current'; Usage = 'current'; Summary = 'Print the active style name'
            Detail = @("Prints just the name of the currently applied style (or nothing",
                       "if none is detected).")
            Keys = @(); Examples = @('tstyles current')
        }
        [pscustomobject]@{
            Name = 'random'; Usage = 'random'; Summary = 'Apply a random style'
            Detail = @("Picks a random style and applies it immediately.")
            Keys = @(); Examples = @('tstyles random')
        }
        [pscustomobject]@{
            Name = 'reset'; Usage = 'reset [-Target <name>]'; Summary = 'Revert a profile to its unstyled default'
            Detail = @("Strips the colors, cursor, font, opacity, and background a style added",
                       "to the target profile, and restores your own prompt. The inverse of",
                       "applying a style. Writes a settings.json.bak first.")
            Keys = @(); Examples = @('tstyles reset', "tstyles reset -Target 'Ubuntu'")
        }
        [pscustomobject]@{
            Name = 'tune'; Usage = 'tune [name]'; Summary = 'Live-tune a style; save as your own'
            Detail = @("Opens an arrow-key editor for the active style (or [name]). Adjusts",
                       "brightness, saturation, opacity, font face, and font size.",
                       "Saved styles land in your user dir and show up in 'tstyles list'.")
            Keys = @('Up/Down      select a knob',
                     'Left/Right   adjust it',
                     'R            reset color',
                     'Enter        save (Overwrite / Save as)',
                     'Esc          revert')
            Examples = @('tstyles tune', 'tstyles tune eva')
        }
        [pscustomobject]@{
            Name = 'font'; Usage = 'font [name]'; Summary = 'Install a coding font and apply it to the active profile'
            Detail = @("With no argument, lists available coding fonts with installed/installable",
                       "markers. With a font name, installs it (if not already present) and",
                       "applies it to the active Windows Terminal profile.")
            Keys = @(); Examples = @('tstyles font', 'tstyles font ''JetBrains Mono''')
        }
        [pscustomobject]@{
            Name = 'register'; Usage = 'register'; Summary = 'Add the loader to your $PROFILE'
            Detail = @("Adds the Import-Module loader to both PowerShell 7 and Windows",
                       "PowerShell 5.1 `$PROFILE files (with a confirm prompt) so tstyles",
                       "loads on every new tab.")
            Keys = @(); Examples = @('tstyles register')
        }
        [pscustomobject]@{
            Name = 'update'; Usage = 'update'; Summary = 'Update to the latest version'
            Detail = @("Updates TerminalStyles. PSGallery installs run Update-PSResource;",
                       "bootstrap installs re-run the installer.")
            Keys = @(); Examples = @('tstyles update')
        }
        [pscustomobject]@{
            Name = 'uninstall'; Usage = 'uninstall'; Summary = 'Remove the module (keeps your styles)'
            Detail = @("Removes the module and strips the `$PROFILE loader. Your saved",
                       "styles and state are preserved unless you pass -DeleteData.")
            Keys = @(); Examples = @('tstyles uninstall', 'tstyles uninstall -DeleteData')
        }
        [pscustomobject]@{
            Name = 'help'; Usage = 'help [command]'; Summary = 'Show all commands, or details for one'
            Detail = @("With no argument, lists every command. With a command name, shows",
                       "detailed help for that command.")
            Keys = @(); Examples = @('tstyles help', 'tstyles help tune')
        }
    )
}

function Show-TerminalStyleHelp {
    # Renders `tstyles help`. No -Command: the overview (USAGE + COMMANDS +
    # EXAMPLES + docs link). With -Command: that command's detail, or a
    # not-found message. Data comes from Get-TerminalStyleHelpData. All ASCII,
    # lightly colorized to match the picker/tuner.
    param([string]$Command)

    $data = Get-TerminalStyleHelpData

    if ($Command) {
        $entry = $data | Where-Object { $_.Name -eq $Command.ToLower() } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "No help topic '$Command'." -ForegroundColor Yellow
            Write-Host ("Topics: " + (($data.Name) -join ', ')) -ForegroundColor DarkGray
            return
        }
        Write-Host ""
        Write-Host ("tstyles " + $entry.Usage) -ForegroundColor Cyan -NoNewline
        Write-Host (" - " + $entry.Summary)
        if ($entry.Detail) {
            Write-Host ""
            foreach ($line in $entry.Detail) { Write-Host ("  " + $line) }
        }
        if ($entry.Keys) {
            Write-Host ""
            Write-Host "KEYS" -ForegroundColor DarkGray
            foreach ($k in $entry.Keys) { Write-Host ("  " + $k) }
        }
        if ($entry.Examples) {
            Write-Host ""
            Write-Host "EXAMPLES" -ForegroundColor DarkGray
            foreach ($e in $entry.Examples) { Write-Host ("  " + $e) }
        }
        Write-Host ""
        return
    }

    # Overview. Module version is best-effort (no disk I/O); omitted if absent.
    $ver = $ExecutionContext.SessionState.Module.Version
    $title = if ($ver) { "tstyles - themed styles for Windows Terminal (v$ver)" }
             else       { "tstyles - themed styles for Windows Terminal" }

    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor DarkGray
    Write-Host "  tstyles [command] [args]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor DarkGray
    Write-Host "  (no command)      Open the interactive picker"
    Write-Host "  <style>           Apply a style by name (umbrella, eva, ...)"
    foreach ($e in $data) {
        Write-Host ("  " + ('{0,-16}' -f $e.Usage) + "  " + $e.Summary)
    }
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor DarkGray
    Write-Host "  tstyles                 # pick interactively"
    Write-Host "  tstyles eva             # apply 'eva'"
    Write-Host "  tstyles tune eva        # tune + save your own"
    Write-Host ""
    Write-Host "More: https://github.com/fcreme/TerminalStyles" -ForegroundColor DarkGray
    Write-Host ""
}

function Test-InWindowsTerminal {
    # True when the current session is hosted by Windows Terminal (which sets
    # WT_SESSION). WT is the only host that renders a style's colors/background,
    # so the themed prompt/banner is loaded only here.
    return [bool]$env:WT_SESSION
}

function Reset-StyleNonWT {
    # `tstyles reset` off Windows Terminal.
    #
    # Nothing was written to a settings file, so there is nothing to strip --
    # the applied colors live entirely in the terminal's dynamic-color state.
    # OSC 104/110/111/112/117 hands that state back to the terminal's own
    # configured profile, which is exactly what "unstyled default" means here.
    $kind = Get-TerminalKind

    [void](Invoke-TerminalStyleOscReset -Kind $kind)
    Clear-CurrentStyleRecord

    # Restore the user's own prompt by removing the style's loader target. The
    # prompt function already installed in THIS session stays until the shell
    # restarts -- same behaviour as the Windows Terminal path.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  Reset " -NoNewline
    Write-Host (Get-TerminalDisplayName -Kind $kind) -ForegroundColor Cyan -NoNewline
    Write-Host " to its unstyled default."
    Write-Host "  Open a new tab to restore your default prompt."
    Write-Host ""
}

function Reset-StyleDirect {
    # `tstyles reset [-Target <name>]` -- revert a WT profile to its unstyled
    # default: strip the fields TerminalStyles writes, remove the now-orphan
    # color scheme, and clear current-style.ps1 (restore the user's prompt).
    # Inverse of Apply-StyleDirect. Writes a rolling .bak first.
    #
    # Off Windows Terminal there is no settings.json to strip: the reset is an
    # OSC 104/110-117 packet that hands color control back to the terminal's own
    # profile, plus dropping the style record and current-style.ps1.
    param([string]$Target)

    Show-UpdateNoticeIfAvailable

    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        Reset-StyleNonWT
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = ConvertFrom-WTJson $originalJson

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to reset. Try: tstyles reset -Target '<name>'"
        return
    }

    # Rolling backup (same safety net as Apply-StyleDirect).
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    # Resolve the profile entry (same resolution as Merge-StyleIntoSettings).
    $entry = if ($Target -eq 'defaults') {
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $settings.profiles.defaults } else { $null }
    } else {
        $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
    }
    if (-not $entry) {
        Write-Host "Profile '$Target' not found in settings.json -- nothing to reset." -ForegroundColor Yellow
        return
    }

    # Capture the scheme name before stripping (for orphan cleanup).
    $schemeName = if ($entry.PSObject.Properties.Match('colorScheme').Count) { $entry.colorScheme } else { $null }

    # Strip every TerminalStyles field that is present on the entry.
    $strippedAny = $false
    foreach ($field in $script:TStylesThemeFields) {
        if ($entry.PSObject.Properties.Match($field).Count) {
            $entry.PSObject.Properties.Remove($field)
            $strippedAny = $true
        }
    }

    # Remove the orphan scheme unless another profile still references it.
    if ($schemeName -and $settings.PSObject.Properties.Match('schemes').Count) {
        $allProfiles = @()
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $allProfiles += $settings.profiles.defaults }
        $allProfiles += @($settings.profiles.list)
        $stillUsed = @($allProfiles | Where-Object {
            $_.PSObject.Properties.Match('colorScheme').Count -and $_.colorScheme -eq $schemeName
        }).Count -gt 0
        if (-not $stillUsed) {
            $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName })
        }
    }

    Write-SettingsFile -Path $settingsPath -Settings $settings

    # Clear the active style's prompt so the user's own prompt returns.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force
    }

    Write-Host ""
    if ($strippedAny) {
        Write-Host "  Reset '$Target' to its unstyled default." -ForegroundColor Green
    } else {
        Write-Host "  '$Target' had no TerminalStyles fields -- already plain." -ForegroundColor Gray
    }
    Write-Host "  Open a new tab to restore your default prompt." -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-StylePickerLoop {
    # The interactive picker's selection loop, with all I/O / rendering / input
    # injected as seams so it can be driven by tests. Owns ONLY the highlight
    # index, the pendingApply debounce, and key dispatch. Returns the outcome:
    #   @{ Outcome = 'confirmed' | 'cancelled'; Index = <int> }
    #
    # Seams:
    #   ReadKey   -> a key object with a .Key ([ConsoleKey]), or $null when the
    #                input queue is momentarily empty (drives the debounce tail).
    #   OnPreview -> & $OnPreview $index : the debounced settings.json write.
    #   OnRevert  -> & $OnRevert         : Esc -- restore original settings (+OSC reset).
    #   OnDraw    -> & $OnDraw $index    : render the menu at $index.
    #   OnRetint  -> & $OnRetint $index  : instant per-keystroke OSC color packet.
    #   OnIdle    -> & $OnIdle           : idle slice (prebuild / sleep).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$StyleCount,
        [int]$StartIndex = 0,
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$OnPreview,
        [Parameter(Mandatory)][scriptblock]$OnRevert,
        [scriptblock]$OnDraw   = {},
        [scriptblock]$OnRetint = {},
        [scriptblock]$OnIdle   = {}
    )

    $idx          = $StartIndex
    $pendingApply = -1
    $needsRedraw  = $true

    while ($true) {
        if ($needsRedraw) {
            & $OnDraw $idx
            $needsRedraw = $false
        }

        $key = & $ReadKey
        if ($null -ne $key) {
            switch ($key.Key) {
                'UpArrow' {
                    if ($idx -gt 0) {
                        $idx--; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'DownArrow' {
                    if ($idx -lt $StyleCount - 1) {
                        $idx++; $needsRedraw = $true; $pendingApply = $idx
                        & $OnRetint $idx
                    }
                }
                'Enter' {
                    if ($pendingApply -ge 0) {
                        & $OnPreview $pendingApply
                        $pendingApply = -1
                    }
                    return @{ Outcome = 'confirmed'; Index = $idx }
                }
                'Escape' {
                    & $OnRevert
                    return @{ Outcome = 'cancelled'; Index = $idx }
                }
            }
            continue
        }

        # Queue empty -- debounce tail: apply the latest pending preview once.
        if ($pendingApply -ge 0) {
            $applyIdx = $pendingApply
            $pendingApply = -1
            & $OnPreview $applyIdx
            continue
        }

        # Truly idle.
        & $OnIdle
    }
}

function Test-ShouldPromptFonts {
    # Pure gate: only prompt on an interactive session that hasn't been prompted.
    param(
        [Parameter(Mandatory)][bool]$MarkerPresent,
        [Parameter(Mandatory)][bool]$Interactive
    )
    return (-not $MarkerPresent) -and $Interactive
}

function Invoke-FontFirstRunPrompt {
    # One-time opt-in: offer to install the recommended font set. Marker-gated so
    # it never repeats; silent in non-interactive sessions.
    $marker = Join-Path $script:TStylesDataRoot '.fonts-prompted'
    $markerPresent = Test-Path -LiteralPath $marker
    if (-not (Test-ShouldPromptFonts -MarkerPresent $markerPresent -Interactive ([Environment]::UserInteractive))) {
        return
    }

    $ans = Read-Host "Install a set of recommended coding fonts now? [y/N]"
    if ($ans -match '^(?i)y') {
        try {
            $catalog = @(Get-FontCatalog)
            foreach ($f in $catalog) {
                if (Test-FontInstalled -Family $f.family) { continue }
                Write-Host "  Installing $($f.name)..." -ForegroundColor Cyan
                try {
                    $files = Resolve-FontPackage -Font $f
                    [void](Install-Font -FontFiles $files)
                } catch {
                    Write-Host "    Skipped $($f.name): $_" -ForegroundColor DarkGray
                }
            }
            Write-Host "Done. Pick fonts anytime with 'tstyles tune' or 'tstyles font'." -ForegroundColor Green
        } catch {
            Write-Host "Font setup failed: $_" -ForegroundColor Red
        }
    }

    # Always record that we've prompted, regardless of the answer.
    try {
        if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($marker, '', [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

# === Public command ===

function Invoke-TerminalStyle {
    [CmdletBinding()]
    param(
        # Positional argument: a subcommand (list / current / random / tune /
        # register / update / uninstall / help), or a bundled style name
        # (umbrella / eva / ...). Use -Target to specify a Windows Terminal
        # profile explicitly; an unrecognized arg prints help.
        [Parameter(Position=0)]
        [string]$Arg,
        # Second positional: a style name for `tstyles tune <name>`. Backward-
        # compatible -- existing single-positional usage binds to $Arg only.
        [Parameter(Position=1)]
        [string]$SubArg,
        # Explicit Windows Terminal profile to apply to (defaults to the
        # current tab's profile via $env:WT_PROFILE_ID).
        [string]$Target,
        [string]$BackgroundImage,
        [switch]$Update,
        # Used with `tstyles update -Force` to skip the same-SHA optimization
        # and force a full reinstall (e.g., after a botched install).
        [switch]$Force,
        # Apply a style's visuals but keep your own prompt (skip the style's
        # prompt/banner). Threaded to Apply-StyleDirect for `tstyles <name>`.
        [switch]$KeepPrompt
    )

    $bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')

    # --- Subcommand dispatch ---
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'font')                 { Invoke-TerminalStyleFont -Name $SubArg -Target $Target; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'reset')                { Reset-StyleDirect -Target $Target; return }
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
    if ($Arg -eq 'help')                 { Show-TerminalStyleHelp -Command $SubArg; return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall;  return }

    # If $Arg matches a bundled style, apply it directly (no picker).
    if ($Arg) {
        $styleMatch = Get-AvailableStyles | Where-Object Name -eq $Arg | Select-Object -First 1
        if ($styleMatch) {
            Apply-StyleDirect -StyleName $Arg -Target $Target `
                -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
                -KeepPrompt:$KeepPrompt
            return
        }
        # Not a subcommand and not a style name: show help instead of silently
        # opening the picker against a (likely bogus) profile name. To target a
        # specific Windows Terminal profile, use the -Target parameter.
        Write-Host "Unknown command or style: '$Arg'" -ForegroundColor Yellow
        Show-TerminalStyleHelp
        Write-Host "To target a Windows Terminal profile, use: tstyles -Target '<name>'" -ForegroundColor DarkGray
        return
    }

    # One-time opt-in font prompt (fires only in interactive sessions, never for
    # subcommands — they all `return` above before reaching this point).
    Invoke-FontFirstRunPrompt

    # Update-notice path runs on every passive invocation (picker included),
    # but Test-UpdateAvailable short-circuits inside the 24h throttle window.
    Show-UpdateNoticeIfAvailable

    # Windows Terminal previews a style by writing settings.json and letting WT
    # reload; every other terminal previews purely through the OSC packet the
    # render loop already emits. So settings.json handling is conditional from
    # here down: $useSettingsFile gates the read, the snapshot, the per-arrow
    # writes, and the Esc revert.
    $termKind        = Get-TerminalKind
    $useSettingsFile = ($termKind -eq 'WindowsTerminal')

    $settingsPath = $null
    if ($useSettingsFile) {
        $settingsPath = Find-WTSettingsPath
        if (-not $settingsPath) {
            Write-Error "Could not locate Windows Terminal settings.json."
            return
        }
    }

    # Enumerate via the shared helper so the picker shows user + tuned styles
    # too (the same union that list/current/random/dispatch/tab-completion use),
    # not just the bundled set.
    $styles = @(Get-AvailableStyles)
    if (-not $styles) {
        Write-Error "No styles found."
        return
    }

    # Snapshot original (byte-exact for revert)
    # MUST be UTF-8 explicit: Get-Content -Raw in Windows PowerShell 5.1
    # defaults to the system ANSI codepage (Windows-1252 on Spanish locale),
    # which mangles non-ASCII profile names (e.g. "Símbolo del sistema").
    # The mangled string then round-trips through ConvertTo-Json + WriteAllText
    # as UTF-8, doubling the byte count of non-ASCII chars on every call.
    $originalJson     = $null
    $originalSettings = $null
    if ($useSettingsFile) {
        $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
        $originalSettings = ConvertFrom-WTJson $originalJson

        if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $originalSettings }
        if (-not $Target) {
            Write-Host "Could not auto-detect the current Windows Terminal profile."
            Write-Host "Available: $((@('defaults') + @($originalSettings.profiles.list.name)) -join ', ')"
            $Target = (Read-Host "Target profile").Trim()
            if (-not $Target) { return }
        }
    }

    # Single choke point for every settings.json write in the picker. Off
    # Windows Terminal this is a no-op, so the loop below reads the same in
    # both worlds instead of repeating the guard at each call site.
    $writeSettings = {
        param([string]$Json)
        if ($useSettingsFile -and $Json) {
            Write-SettingsAtomic -Path $settingsPath -Json $Json
        }
    }

    if (-not (Test-StyledHost -Kind $termKind)) {
        Write-Host "Note: this host doesn't render colors; you'll get the prompt but not the palette." -ForegroundColor Yellow
    } elseif (-not $useSettingsFile) {
        $caps = Get-TerminalCapability -Kind $termKind
        if (-not $caps.BackgroundImage) {
            Write-Host ("Note: {0} renders the palette but not background images." -f (Get-TerminalDisplayName -Kind $termKind)) -ForegroundColor DarkGray
        }
    }

    # Start on the currently active style if we can detect one -- opening
    # the picker should land where the user already is, not at the first
    # alphabetical entry. Falls back to 0 for custom/unrecognized profiles.
    $idx = 0
    $currentName = Get-CurrentStyleName
    if ($currentName) {
        for ($i = 0; $i -lt $styles.Count; $i++) {
            if ($styles[$i].Name -eq $currentName) { $idx = $i; break }
        }
    }
    $confirmed = $false

    # Pre-load each style's color swatch AND the parsed scheme object.
    # Schemes are reused per-arrow to emit OSC color escapes (see the
    # render loop below) so the terminal repaints colors in <5ms, well
    # before the eventual settings.json write triggers Windows Terminal's
    # full reload cycle.
    $swatches = @{}
    $schemes  = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $sp = Join-Path $styles[$i].FullName 'scheme.json'
        $scheme = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $swatches[$i] = Get-SchemeSwatch -Scheme $scheme
        $schemes[$i]  = $scheme
    }

    # Pre-load each style's tabTitle (from theme.json). settings.json's
    # tabTitle isn't honored by Windows Terminal for a tab whose shell has
    # already set $Host.UI.RawUI.WindowTitle (every theme's profile.ps1
    # does), so we have to set WindowTitle explicitly on each arrow change
    # to make the title preview live. Themes without a tabTitle simply
    # leave the current title untouched while highlighted.
    $titles = @{}
    for ($i = 0; $i -lt $styles.Count; $i++) {
        $tp = Join-Path $styles[$i].FullName 'theme.json'
        if (-not (Test-Path -LiteralPath $tp)) { continue }
        try {
            $theme = [System.IO.File]::ReadAllText($tp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($theme.PSObject.Properties.Match('tabTitle').Count -gt 0) {
                $titles[$i] = $theme.tabTitle
            }
        } catch { }
    }

    # Background prefetch: kick off ONE job that downloads any missing GIFs
    # from the gifs branch serially. The picker stays interactive while this
    # runs; by the time the user arrow-keys through a few styles, the rest
    # are usually already cached locally. Worst case: the user reaches a
    # style before its GIF arrives -- the synchronous fetch in
    # Get-StyleBundledBackground handles it (same code path as today).
    $missingPaths = @()
    foreach ($s in $styles) {
        if (-not (Test-StyleResolved -StyleDir $s.FullName)) {
            $missingPaths += $s.FullName
        }
    }
    $prefetchJob = $null
    if ($missingPaths.Count -gt 0) {
        # Prefer Start-ThreadJob if available -- it's ~10x faster to start
        # than Start-Job (pwsh 7 ships it; WinPS 5.1 has it only if the
        # user installed the ThreadJob module). Falls back to Start-Job.
        $jobStarter = if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            'Start-ThreadJob'
        } else {
            'Start-Job'
        }
        $prefetchJob = & $jobStarter -ScriptBlock {
            param($Paths, $DataRoot)
            $ProgressPreference = 'SilentlyContinue'
            foreach ($styleDir in $Paths) {
                $styleName = Split-Path -Leaf $styleDir
                # Write into the per-user CACHE dir -- the same location
                # Get-StyleBundledBackground/Test-StyleResolved read from. The job
                # runs in a separate runspace without $script: scope, so the cache
                # path is re-derived from the $DataRoot passed via -ArgumentList
                # (kept in sync with Get-StyleCacheDir). Writing into $styleDir
                # instead would be a no-op on read-only PSGallery installs and would
                # strand the .no-background marker where no reader looks.
                $cacheDir = Join-Path (Join-Path $DataRoot 'cache') $styleName
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { continue }
                }
                $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
                $success = $false
                foreach ($ext in 'gif','png','jpg','jpeg') {
                    $local = Join-Path $cacheDir "background.$ext"
                    try {
                        Invoke-WebRequest -Uri "$remoteBase.$ext" -OutFile $local `
                            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                            $success = $true
                            break
                        } else {
                            Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
                    }
                }
                if (-not $success) {
                    try { New-Item -ItemType File -Path (Join-Path $cacheDir '.no-background') -Force | Out-Null } catch { }
                }
            }
        } -ArgumentList $missingPaths, $script:TStylesDataRoot
    }

    # Memoization: cache the final JSON string per style index. Only cache
    # AFTER the style is resolved (so we don't pin a JSON that was computed
    # while the GIF was still pending). Arrow-keying back to a previously-
    # visited resolved style writes the cached string straight to disk --
    # skips ConvertFrom-Json + Merge + ConvertTo-Json (~100ms per cycle).
    $mergedCache = @{}

    # On-disk rolling backup before any preview write. The picker reverts in
    # memory on Esc, but a hard kill mid-preview would otherwise leave the
    # last-previewed theme with no recoverable original; this .bak (same one the
    # direct-apply/reset paths roll) is that recovery copy.
    # Crash-recovery copy -- only meaningful when a settings.json exists.
    if ($useSettingsFile) { try { [System.IO.File]::WriteAllText("$settingsPath.bak", $originalJson, [System.Text.UTF8Encoding]::new($false)) } catch { } }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle
    try {
        # Apply first preview before showing the menu. The merge is skipped
        # entirely off Windows Terminal: there is no $originalJson to merge into,
        # and the OSC packet emitted by the render loop is the whole preview.
        if ($useSettingsFile) {
            $preview = ConvertFrom-WTJson $originalJson
            $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$idx].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
            $initialJson = $preview | ConvertTo-Json -Depth 100
            & $writeSettings $initialJson
            if (Test-StyleResolved -StyleDir $styles[$idx].FullName) {
                $mergedCache[$idx] = $initialJson
            }
        } else {
            Write-HostOscPacket -Packet $oscPackets[$idx]
        }
        if ($titles.ContainsKey($idx)) { $Host.UI.RawUI.WindowTitle = $titles[$idx] }

        # Truecolor mid-gray for the picker's secondary text. PowerShell's
        # "DarkGray" maps to each scheme's brightBlack slot, which on
        # low-contrast themes (rain, forest, golden-forest) sits too close
        # to the background to read. A fixed #a0a0a0 stays legible on every
        # background -- dark themes and the light gitbash alike.
        $hintColor  = "$([char]27)[38;2;160;160;160m"
        $resetColor = "$([char]27)[0m"

        # Clear once, then capture the buffer Y of the picker's home row.
        # Subsequent iterations reposition the cursor here and overwrite in
        # place instead of Clear-Host-ing per arrow press -- the per-arrow
        # clear was the source of the visible flicker. The number of lines
        # is constant (header + hint + blank + N styles + blank), so the
        # overwrite covers the previous frame exactly with no leftover
        # characters. \e[K appended to each potentially shrinking line
        # would defend against future content-width changes; not needed
        # today since every row has stable width.
        Clear-Host
        $renderHomeY = [Console]::CursorTop

        # Non-blocking render loop with three responsibilities, in
        # strict priority order:
        #   1. Process pending keypresses -- update $idx, redraw the
        #      menu IMMEDIATELY so the cursor visually moves, but do
        #      NOT apply the theme yet. Set $pendingApply = $idx and
        #      loop back to drain any further keypresses.
        #   2. Apply the pending theme (settings.json write + tab
        #      title) once the keypress queue is empty. Mashed arrows
        #      collapse to a single apply at the final position --
        #      Windows Terminal does one reload instead of N.
        #   3. Prebuild the next uncached resolved theme's merged
        #      JSON during idle slices so future applies are pure
        #      WriteAllText (no parse / merge / serialize).
        #
        # Net effect:
        #   Single tap  -> cursor jumps in ~5ms, theme applies after
        #                  ~50-100ms once the gap is detected.
        #   Mash 5 keys -> cursor moves through all 5 visually, only
        #                  the final position is written to settings.json,
        #                  WT does one reload instead of five.
        # Build pre-serialized OSC color packets, one per theme. Each
        # packet is a single string of ANSI OSC sequences that, when
        # written to stdout, instantly retints the terminal's
        # foreground / background / cursor / selection / 16-color
        # palette to that theme -- no settings.json write, no Windows
        # Terminal reload. The eventual settings.json write (deferred
        # to when the keypress queue drains) still happens and brings
        # the background image, cursor shape, font, etc. into line a
        # few hundred ms later, but the colors have already shifted
        # so the perceived freeze drops to near-zero.
        $oscPackets = @{}
        for ($i = 0; $i -lt $styles.Count; $i++) {
            $oscPackets[$i] = Get-SchemeOscPacket -Scheme $schemes[$i]
        }

        $drawMenu = {
            param($idx)
            [Console]::SetCursorPosition(0, $renderHomeY)
            Write-Host ""
            Write-Host "  Choose a style for " -NoNewline
            Write-Host "'$Target'" -ForegroundColor Cyan
            Write-Host "$hintColor  Up/Down to preview, Enter to keep, Esc to cancel$resetColor"
            Write-Host "$hintColor  Tip: run 'tstyles help' for all commands$resetColor"
            Write-Host ""
            for ($i = 0; $i -lt $styles.Count; $i++) {
                $name = $styles[$i].Name
                $resolved = Test-StyleResolved -StyleDir $styles[$i].FullName
                $color = if ($i -eq $idx) { 'Yellow' } else { 'Gray' }
                $prefix = if ($i -eq $idx) { '   > ' } else { '     ' }
                Write-Host ($prefix + ('{0,-16}  ' -f $name)) -ForegroundColor $color -NoNewline
                if ($resolved) {
                    Write-Host $swatches[$i]
                } else {
                    Write-Host "$hintColor...fetching background$resetColor"
                }
            }
            Write-Host ""
        }

        $applyTheme = {
            param([int]$i)
            # Off Windows Terminal the OSC retint in $onRetint already did the
            # whole preview -- there is no deferred settings.json write to make.
            if (-not $useSettingsFile) {
                if ($titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
                return
            }
            $resolved = Test-StyleResolved -StyleDir $styles[$i].FullName
            if ($resolved -and $mergedCache.ContainsKey($i)) {
                & $writeSettings $mergedCache[$i]
            } else {
                $preview = ConvertFrom-WTJson $originalJson
                $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $styles[$i].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $json = $preview | ConvertTo-Json -Depth 100
                & $writeSettings $json
                if ($resolved) { $mergedCache[$i] = $json }
            }
            if ($titles.ContainsKey($i)) { $Host.UI.RawUI.WindowTitle = $titles[$i] }
        }

        # Per-keystroke instant retint (OSC color packet). The deferred
        # settings.json write is $applyTheme, passed as -OnPreview.
        $onRetint = { param($i) [Console]::Out.Write($oscPackets[$i]) }

        # Esc: restore the byte-exact original settings.json and clear the live
        # OSC retint so the cancelled preview's colors don't linger.
        $onRevert = {
            & $writeSettings $originalJson
            [Console]::Out.Write((Get-OscResetPacket))
        }

        # Idle slice: prebuild the next uncached resolved theme's merged JSON,
        # else sleep briefly. (Verbatim from the old idle branch.)
        $onIdle = {
            $nextPrebuild = -1
            for ($j = 0; $j -lt $styles.Count; $j++) {
                if ($mergedCache.ContainsKey($j)) { continue }
                if (-not (Test-StyleResolved -StyleDir $styles[$j].FullName)) { continue }
                $nextPrebuild = $j
                break
            }
            # Nothing to prebuild when no settings.json is being written.
            if (-not $useSettingsFile) { Start-Sleep -Milliseconds 50; return }
            if ($nextPrebuild -ge 0) {
                $pp = ConvertFrom-WTJson $originalJson
                $pp = Merge-StyleIntoSettings -Settings $pp -StyleDir $styles[$nextPrebuild].FullName -TargetName $Target -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided
                $mergedCache[$nextPrebuild] = $pp | ConvertTo-Json -Depth 100
            } else {
                Start-Sleep -Milliseconds 50
            }
        }

        # Real-console input adapter -- the one seam not under automated test.
        # Contract: the engine's switch dispatches on string key names
        # ('UpArrow'/'DownArrow'/'Enter'/'Escape'); [Console]::ReadKey($true).Key
        # is a [ConsoleKey] that PowerShell's switch matches by string. Preserve
        # that .Key shape if this adapter ever changes.
        $readKey = { if ([Console]::KeyAvailable) { [Console]::ReadKey($true) } else { $null } }

        $result = Invoke-StylePickerLoop -StyleCount $styles.Count -StartIndex $idx `
            -ReadKey $readKey -OnPreview $applyTheme -OnRevert $onRevert `
            -OnDraw $drawMenu -OnRetint $onRetint -OnIdle $onIdle

        if ($result.Outcome -eq 'cancelled') {
            Clear-Host
            Write-Host "Reverted." -ForegroundColor Yellow
            return
        }

        $idx       = $result.Index
        $confirmed = $true

        # Confirmed -- maybe install profile.ps1
        $selectedStyle = $styles[$idx]
        $styleProfile  = Join-Path $selectedStyle.FullName 'profile.ps1'

        # "Is the target a PowerShell profile?" is a Windows Terminal question:
        # it decides whether writing a PowerShell prompt into that WT profile
        # makes sense. Off WT there are no profiles to disambiguate -- this shell
        # IS PowerShell, so the prompt always applies.
        $isPwshTarget = $true
        if ($useSettingsFile) {
            $isPwshTarget = $false
            if ($Target -eq 'defaults') {
                $isPwshTarget = $true
            } else {
                $entry = $originalSettings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
                $cmd = "$($entry.commandline)"
                $src = "$($entry.source)"
                if ($src -eq 'Windows.Terminal.PowershellCore' -or
                    $cmd -match '(?i)\bpwsh\.exe\b' -or
                    $cmd -match '(?i)\bpowershell\.exe\b') {
                    $isPwshTarget = $true
                }
            }
        } else {
            # Record the confirmed style so a new tab comes up in it -- the OSC
            # preview alone would die with this tab.
            Set-CurrentStyleRecord -StyleName $styles[$idx].Name -Kind $termKind
        }

        if ($isPwshTarget) {
            if (Test-Path -LiteralPath $styleProfile) {
                Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
            } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
                Remove-Item -LiteralPath $script:TStylesCurrent -Force
            }
        }

        Clear-Host
        Write-Host ""
        Write-Host "  Style applied: " -NoNewline
        Write-Host $selectedStyle.Name -ForegroundColor Green
        Write-Host ""

        # Live-reload: dot-source the newly active profile so the title,
        # prompt, banner, and PSReadLine colors update in THIS session
        # without requiring the user to open a new tab. Each theme's
        # profile.ps1 uses `function global:prompt` so the binding escapes
        # this function's scope.
        if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
            . $script:TStylesCurrent
        }
    } finally {
        [Console]::CursorVisible = $true
        # Restore the original window title on cancel / exception. The
        # confirm path already had the selected theme's profile.ps1
        # dot-sourced (which sets its own title), so we only restore when
        # the user didn't confirm.
        if (-not $confirmed) {
            $Host.UI.RawUI.WindowTitle = $originalTitle
        }
        # Clean up the background prefetch job. If it's still mid-fetch
        # (user picked quickly), the downloads in progress may be cut off
        # -- the next Get-StyleBundledBackground call will fall back to
        # synchronous fetch for whatever didn't complete.
        if ($prefetchJob) {
            Stop-Job -Job $prefetchJob -ErrorAction SilentlyContinue
            Remove-Job -Job $prefetchJob -Force -ErrorAction SilentlyContinue
        }
    }
}

Set-Alias -Name tstyles -Value Invoke-TerminalStyle -Force

# Tab completion: complete the positional Arg with subcommands + style names.
# Applies to both the function and the tstyles alias (PowerShell extends
# argument completers across aliases automatically).
Register-ArgumentCompleter -CommandName Invoke-TerminalStyle -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $subcommands = @('font', 'help', 'list', 'current', 'random', 'register', 'reset', 'tune', 'update', 'uninstall')
    # Get-AvailableStyles already unions $DataRoot\styles\ + $ModuleRoot\styles\
    # with user-wins dedup -- single source of truth for what `tstyles <name>`
    # can target.
    $styleNames = @(Get-AvailableStyles | ForEach-Object Name)
    $all = @($subcommands + $styleNames | Sort-Object -Unique)
    $all | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# One-time data-layout migration for users upgrading from pre-0.2.0.
# Idempotent; gated by a marker file.
Invoke-TerminalStylesStateMigration

# === Auto-load the currently selected style at shell startup ===
# Gated on Test-StyledHost rather than Test-InWindowsTerminal: hosts that cannot
# render a style (a plain pipe, a dumb console) would show a half-themed look --
# banner and prompt glyphs with none of the colors. Every terminal that CAN take
# an OSC palette or a written config qualifies. Module functions import
# regardless of the gate.
if (Test-StyledHost) {

    # Windows Terminal reads its colors from settings.json, which the apply
    # already wrote, so the palette is live before this shell even starts.
    # OSC-driven terminals have no such persistence: the escape sequences only
    # ever touched the tab they were emitted into. Re-emit them here so a new
    # tab/window/split comes up in the applied style instead of the terminal's
    # own default.
    #
    # Skipped on WT to avoid fighting its own scheme, and skipped when the
    # terminal can persist a real config AND we wrote one (that path handles
    # itself). Failures are swallowed inside Write-HostOscPacket -- a missing
    # color is never worth blocking a shell from starting.
    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        try {
            $record = Get-CurrentStyleRecord
            if ($record -and $record.name) {
                $styleDir = Get-StyleDir -StyleName $record.name
                if ($styleDir) {
                    $schemePath = Join-Path $styleDir 'scheme.json'
                    if (Test-Path -LiteralPath $schemePath) {
                        $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                        [void](Invoke-TerminalStyleOscApply -Scheme $scheme)
                    }
                }
            }
        } catch { }
    }

    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        . $script:TStylesCurrent
    }
}
