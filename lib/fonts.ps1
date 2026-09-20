# fonts.ps1 -- the coding-font catalogue: detection, download, install, apply.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Two halves that look alike and are not. DETECTING what is installed
# (Get-InstalledFontFamily, Test-MonospaceFont, Get-MonospaceFontList) is
# platform-split, because System.Drawing's glyph measurement is GDI+ and so
# Windows-only; off Windows the list is the curated set plus anything whose
# name says "mono". INSTALLING (Resolve-FontPackage, Install-Font) is a
# SHA-256-gated download into a per-user directory that needs no administrator
# rights on any platform.

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
        $Installed = Get-InstalledFontFamily
    }

    $platform = Get-TStylesPlatform

    # Curated favorites, always offered when present and never measured.
    # Extended off Windows with the monospace families those systems ship, so
    # the tuner has something to cycle on a Mac that has none of the Windows
    # fonts installed.
    $allow = @('Cascadia Mono','Cascadia Code','Consolas','JetBrains Mono',
               'Fira Code','Hack','Source Code Pro','DejaVu Sans Mono',
               'Lucida Console','Courier New')
    if ($platform -eq 'MacOS') {
        $allow += @('SF Mono','Menlo','Monaco','Andale Mono','PT Mono','Courier')
    } elseif ($platform -eq 'Linux') {
        $allow += @('Liberation Mono','Ubuntu Mono','Noto Sans Mono','FreeMono')
    }
    $installedKeys = @{}
    foreach ($i in $Installed) {
        if ($i) { $installedKeys[(Get-FontComparisonKey -Name $i)] = $i }
    }
    # Match on the normalized key: off Windows the installed names come from
    # filenames, so "PT Mono" may have been recovered as "PTMono".
    $favorites = @($allow | Where-Object { $installedKeys.ContainsKey((Get-FontComparisonKey -Name $_)) })

    # $null means "not provided" -> work it out. An explicit empty array (tests)
    # means "no monospace beyond favorites".
    if ($null -eq $MonospaceNames) {
        $MonospaceNames = @()
        if ($platform -eq 'Windows') {
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
        } else {
            # No glyph measurement off Windows: Test-MonospaceFont needs GDI+,
            # which System.Drawing.Common no longer provides there. Rather than
            # offer all 369 installed families and let the user find the fixed-
            # width ones by trial, offer the curated set plus anything whose
            # name says it is monospace -- the near-universal convention for a
            # coding font. A mono font named otherwise is missed, which is a
            # smaller cost than filling the tuner with proportional faces.
            # Two sources, unioned. The name pattern is a heuristic and misses
            # every monospace family not named for it -- Iosevka, Cousine,
            # Inconsolata, Terminus, Hasklig, Anonymous Pro, PragmataPro,
            # MonoLisa. The second source is not a heuristic at all:
            # $script:TStylesKnownFontNames is a hand-curated table of monospace
            # families, and Get-InstalledFontFamily has already resolved
            # installed filenames onto those canonical names -- so a hit there
            # is known-good with no glyph measurement needed. MonoLisa, Iosevka
            # and Cousine were the sharp case: the module went out of its way to
            # canonicalise them and then the font knob discarded them, while
            # README promised "every monospace font installed on your machine".
            $known = @($Installed | Where-Object {
                $_ -and $script:TStylesKnownFontNames.ContainsValue($_)
            })
            $byName = @($Installed | Where-Object {
                $_ -and $_ -match '(?i)\b(mono|mononoki|code)\b'
            })
            $MonospaceNames = @($known + $byName | Where-Object { $_ -notin $favorites } | Sort-Object -Unique)
        }
    }

    $others = @($MonospaceNames | Where-Object { $_ -notin $favorites } | Sort-Object)
    $list = @($favorites) + @($others)
    if (-not $list) {
        # Last resort differs by platform: Consolas does not exist on a Mac.
        $list = switch ($platform) {
            'MacOS' { @('Menlo') }
            'Linux' { @('DejaVu Sans Mono') }
            default { @('Consolas') }
        }
    }
    if ($Current) {
        $list = @($Current) + @($list | Where-Object { $_ -ne $Current })
    }
    # The leading comma matters. `return @(...)` still writes the array to the
    # output stream, and PowerShell UNROLLS an array on the way out -- so a
    # machine with exactly one monospace font handed the caller a [string], and
    # the tuner's font-face knob then indexed into it per CHARACTER: the knob
    # read "M", then "e", then "n", and saved a one-letter font face. `,@(...)`
    # emits the array as a single object, so every call site gets an array.
    return ,@($list | Select-Object -Unique)
}

function Get-FontCatalog {
    # Parse the bundled font catalog (fonts.json). Returns the array of font
    # entries, skipping any that lack a required field. Throws on missing file
    # or invalid JSON.
    # $script:TStylesModuleRoot, NOT $PSScriptRoot: this function used to live in
    # tstyles.ps1 at the module root, where the two were the same. From lib/ they
    # are not, and $PSScriptRoot would look for lib/fonts.json.
    param([string]$Path = (Join-Path $script:TStylesModuleRoot 'fonts.json'))

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

function Get-FontSearchPath {
    # Directories a font can be installed into for the current user, most
    # specific first. -Platform / -HomeDir are test seams.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'MacOS' {
            @(
                (Join-Path (Join-Path $HomeDir 'Library') 'Fonts')
                '/Library/Fonts'
                '/System/Library/Fonts'
                '/System/Library/Fonts/Supplemental'
            )
        }
        'Linux' {
            $xdg = $env:XDG_DATA_HOME
            if (-not $xdg) { $xdg = Join-Path (Join-Path $HomeDir '.local') 'share' }
            @(
                (Join-Path $xdg 'fonts')
                (Join-Path $HomeDir '.fonts')
                '/usr/local/share/fonts'
                '/usr/share/fonts'
            )
        }
        default { @((Get-TStylesFontDir -Platform $Platform -HomeDir $HomeDir)) }
    }
}

function Get-FontComparisonKey {
    # Normalize a family name or font filename to a comparison key: lowercase,
    # letters and digits only. "JetBrains Mono" and "JetBrainsMono-Regular"
    # both reduce to a key one can prefix-match, which is what lets the
    # directory scan below recognize a family without parsing the font's
    # internal name table.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    return ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

function Get-InstalledFontFamily {
    # Installed font family names.
    #
    # Windows enumerates through GDI+. Everywhere else that is not available:
    # System.Drawing.Common is Windows-only from .NET 6 onward, and constructing
    # an InstalledFontCollection on macOS throws a PInvokeGdiPlus type-initializer
    # error. The previous code caught that and fell back to an empty list, so
    # every font silently reported as "not installed" -- `tstyles font` showed
    # the whole catalogue as installable even right after installing one.
    #
    # The fallback scans the font directories and derives family names from
    # filenames. That cannot recover a family whose file is named unlike its
    # family (Apple's SFNSMono.ttf is "SF Mono"), which is why the curated
    # catalogue is matched by normalized key rather than by exact display name.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string[]]$SearchPath
    )
    if ($Platform -eq 'Windows') {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        try {
            return @([System.Drawing.Text.InstalledFontCollection]::new().Families.Name)
        } catch {
            return @()
        }
    }

    if (-not $SearchPath) { $SearchPath = Get-FontSearchPath -Platform $Platform }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $SearchPath) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        try {
            $files = Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '(?i)^\.(ttf|otf|ttc|otc)$' }
        } catch { continue }
        foreach ($f in $files) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            # Drop a trailing style suffix: "JetBrainsMono-Regular" -> "JetBrainsMono".
            $base = $base -replace '-(Regular|Italic|Bold|BoldItalic|Light|Medium|SemiBold|ExtraBold|Thin|Black|Oblique)$', ''

            # Prefer the family's real name when we know it. A filename cannot
            # be split back into words unambiguously -- "JetBrainsMono" is just
            # as readable as "Jet Brains Mono" to a splitter -- so canonicalize
            # against the names we do know before falling back to guessing.
            $key = Get-FontComparisonKey -Name $base
            if ($script:TStylesKnownFontNames.ContainsKey($key)) {
                $names.Add($script:TStylesKnownFontNames[$key])
                continue
            }
            # Unknown family: split camel case, which is right more often than
            # not for font filenames, and only affects how the name is displayed.
            $display = ($base -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ').Trim()
            if ($display) { $names.Add($display) }
        }
    }
    return @($names | Sort-Object -Unique)
}

function Test-FontInstalled {
    # True when $Family is among installed font families.
    # -Installed is a test seam; real callers omit it and we enumerate.
    param(
        [Parameter(Mandatory)][string]$Family,
        [string[]]$Installed
    )
    if (-not $PSBoundParameters.ContainsKey('Installed')) {
        $Installed = Get-InstalledFontFamily
    }
    # Compare on the normalized key, not the raw string: off Windows the
    # "installed" names come from filenames, so "JetBrains Mono" has to match
    # a family recovered as "JetBrains Mono" from JetBrainsMono-Regular.ttf --
    # equal only once spaces and case are taken out.
    $want = Get-FontComparisonKey -Name $Family
    if (-not $want) { return $false }
    return @($Installed | Where-Object { $_ -and (Get-FontComparisonKey -Name $_) -eq $want }).Count -gt 0
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
            # -TimeoutSec, like every other fetch in the project. A font
            # archive is a few megabytes over a CDN; 120s is generous and still
            # bounded, where unbounded means a stalled connection hangs
            # `tstyles font` with no way to tell it from a slow link.
            Invoke-WebRequest -Uri $Font.url -OutFile $archive -UseBasicParsing `
                -TimeoutSec 120 -ErrorAction Stop
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
    #
    # Keyed off the URL, not the local file. Downloads always land in
    # 'download.bin', so taking the extension from $archive made this branch
    # unreachable for anything fetched -- it could only ever fire for a caller
    # that passed -DownloadPath, i.e. the tests. Every catalogue entry today is
    # a .zip with a 'files' list, so nothing was broken; it was waiting for the
    # first person to add a font published as a bare .ttf.
    #
    # The URL minus any ?query or #fragment, used for BOTH the extension test
    # and the name the file is written under. Stripping it for one and not the
    # other is how a name like 'Font.ttf?raw=1' reached the disk: the branch
    # fired, and then the installed file had no font extension at all, so
    # Get-InstalledFontFamily's filter never saw it again -- `tstyles font`
    # reported the install as successful and the font as still missing, and
    # re-downloaded it on every run. On Windows it does not even get that far:
    # '?' is not a legal filename character, so the copy throws. A '#' was the
    # mirror image -- it stayed in the extension, so the branch did not fire at
    # all and a bare .ttf went to ZipFile::OpenRead instead.
    #
    # $DownloadPath is a local path, never a URL: it is not stripped, since
    # both characters are legal in a filename.
    $urlPath   = ("$($Font.url)" -split '[?#]')[0]
    $extSource = if ($DownloadPath) { $DownloadPath } else { $urlPath }
    $ext = [System.IO.Path]::GetExtension($extSource).ToLowerInvariant()
    if ((-not $Font.files -or @($Font.files).Count -eq 0) -and ($ext -in '.ttf','.otf','.ttc')) {
        $dest = Join-Path $extractDir (Split-Path -Leaf $urlPath)
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
        # Same guard, same reason, as the merge's lazy creation: Add-Member has
        # nothing to add `defaults` to unless `profiles` is an object, and on
        # the legacy flat-array form it silently grafts the block onto every
        # profile instead. $false is the answer this function already has for "a
        # target that is not there", and it leaves settings.json untouched.
        if (-not (Get-WTProfileShape -Settings $settings).HasDefaultsSlot) { return $false }
        if (-not $settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $entry = $settings.profiles.defaults
    } else {
        # Shared resolver: with two profiles of the same name, first-match put
        # the font on whichever came first in the list rather than the one the
        # session is running in.
        $entry = (Resolve-WTProfileTarget -Settings $settings -TargetName $TargetName).Entry
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

function Test-FontCommandCanApply {
    <#
    .SYNOPSIS
    Can `tstyles font <name>` write a font for this terminal?

    .DESCRIPTION
    NOT (Get-TerminalCapability).Font, which answers a different question and
    has answered it for two terminals since 0.8.24. That flag means "a STYLE
    APPLY writes this terminal's font": WezTerm's arm turns it on because
    Get-WezTermStyleLua emits `config.font` from the style's theme.json. This
    command has no such route -- the only font writer it can reach is
    Set-ProfileFont, which knows Windows Terminal's settings.json and nothing
    else -- so reading the capability here made the gate below fall through on
    WezTerm and print "Could not locate Windows Terminal settings.json" in red,
    on a Mac, after an install that had just succeeded. That red line is the
    exact outcome the gate exists to prevent.

    So: one predicate, named for the question the command asks, next to the
    writer that answers it. Add an arm here when a second terminal gains one.
    #>
    [CmdletBinding()]
    param([string]$Kind = (Get-TerminalKind))
    return ($Kind -eq 'WindowsTerminal')
}

function Get-FontOwner {
    <#
    .SYNOPSIS
    Who decides this terminal's font: this command, a style apply, or the
    terminal itself.

    .DESCRIPTION
    THREE answers, not two, which is what the messages here used to get wrong.
    `tstyles font` asked only "can I write it?" and said "this terminal takes
    its font from its own settings" for every no -- true for Terminal.app,
    iTerm2, Ghostty, kitty and Alacritty, and FALSE for WezTerm since 0.8.29,
    where the generated Lua module sets `config.font` from the applied style.

    On WezTerm that made the advice actively wrong rather than merely vague: a
    user who followed "choose it there once installed" and set `config.font` in
    their own wezterm.lua had it overridden by the next style apply. Measured --
    with JetBrains Mono set in wezterm.lua ahead of the require, `wezterm
    ls-fonts` reports the style's Cascadia Code as the primary and demotes
    JetBrains Mono to a fallback.

    One predicate so the list footer and the post-install line cannot answer it
    differently; they did, and that is how the contradiction survived.
    #>
    [CmdletBinding()]
    param([string]$Kind = (Get-TerminalKind))

    if (Test-FontCommandCanApply -Kind $Kind)     { return 'command' }
    if ((Get-TerminalCapability -Kind $Kind).Font) { return 'style'  }
    return 'terminal'
}

function Show-FontList {
    # List the font catalog with an installed/installable marker. -Catalog and
    # -Installed are test seams; real callers omit them.
    param(
        [object[]]$Catalog,
        [string[]]$Installed
    )
    if (-not $Catalog) { $Catalog = @(Get-FontCatalog) }

    # One enumeration for the whole list. Test-FontInstalled enumerates for
    # itself when -Installed is absent, so calling it bare per entry walked
    # every font directory once PER CATALOGUE ENTRY -- and off Windows that
    # walk is recursive over ~/Library/Fonts, /Library/Fonts and both
    # /System/Library/Fonts trees (672 files on the machine this was measured
    # on, six times over: 378ms against 113ms for one shared pass). On Windows
    # it is a fresh InstalledFontCollection each time. The cost is linear in
    # the catalogue, so every font added made `tstyles font` slower for
    # everyone. The -Installed seam existed for exactly this and the one real
    # caller was not using it.
    if (-not $PSBoundParameters.ContainsKey('Installed')) {
        $Installed = Get-InstalledFontFamily
    }

    Write-Host ""
    Write-Host "  Available coding fonts ([+] installed, [ ] installable):" -ForegroundColor Cyan
    Write-Host ""
    # The same treatment `tstyles list` gets, for the same reason: a name and a
    # licence say nothing about what anyone is choosing between. Ligatures, the
    # shape of the zero and the x-height are the differences people pick on.
    $listWidth = Get-ConsoleWidth
    $fontHint  = Get-HintEscape
    foreach ($f in $Catalog) {
        $isIn = Test-FontInstalled -Family $f.family -Installed $Installed
        $mark = if ($isIn) { '[+]' } else { '[ ]' }
        # 3 indent + 3 marker + 1 + 20 name column + 1 + the licence text.
        $used = 28 + "$($f.license)".Length
        $desc = Get-ListRowDescription -Width $listWidth -Used $used `
                    -Description $f.description -HintEscape $fontHint
        Write-Host (("   {0} {1,-20} {2}" -f $mark, $f.name, $f.license) + $desc)
    }
    Write-Host ""
    # "Install + apply" is a promise only Windows Terminal keeps. Everywhere
    # else `tstyles font <name>` installs and then says, correctly, that the
    # terminal takes its font from its own settings -- so the shortest
    # description of the command contradicted the command itself.
    $listKind = Get-TerminalKind
    $listName = Get-TerminalDisplayName -Kind $listKind
    switch (Get-FontOwner -Kind $listKind) {
        'command' {
            Write-Host "  Install + apply one with: tstyles font <name>" -ForegroundColor DarkGray
        }
        'style' {
            Write-Host "  Install one with: tstyles font <name>" -ForegroundColor DarkGray
            Write-Host ("  The applied style sets {0}'s font, so one chosen in its own config is" -f $listName) -ForegroundColor DarkGray
            Write-Host "  overridden on the next apply. tstyles tune saves a font into a style." -ForegroundColor DarkGray
        }
        default {
            Write-Host "  Install one with: tstyles font <name>" -ForegroundColor DarkGray
            Write-Host ("  {0} takes its font from its own settings, so choose it there once installed." -f
                        $listName) -ForegroundColor DarkGray
        }
    }
}

function Get-FontPickerFooter {
    <#
    .SYNOPSIS
    What Enter will actually do, for the terminal this is running in.

    .DESCRIPTION
    One line, and it has to be true on all three answers Get-FontOwner gives.
    "Install + apply" is a promise only Windows Terminal keeps; saying it in a
    picker running on Terminal.app would be the same contradiction the list
    footer already had to be fixed for, except harder to miss, because here it
    sits directly above the key that is supposed to do it.
    #>
    [CmdletBinding()]
    param([string]$Owner, [string]$TerminalName)

    # ALWAYS two lines, blank-padded, for the same reason the scroll indicators
    # are always emitted: the frame is overwritten in place and a footer that
    # was two rows for one terminal and one for another would strand a row.
    #
    # Two SHORT lines rather than one long one, because the trimming that keeps
    # a row inside the window cuts at a sentence -- and here the first sentence
    # is the least informative part. On an 80-column terminal the single-line
    # version came out as "Enter installs it." and dropped the entire point.
    switch ($Owner) {
        'command' { @("Enter installs it and sets it as $TerminalName's font.", '') }
        'style'   { @("Enter installs it. The applied style sets $TerminalName's font.",
                      'tstyles tune <style> keeps a font with a style.') }
        default   { @("Enter installs it. $TerminalName takes its font from its own",
                      'settings, so choose it there once installed.') }
    }
}

# Rows the font frame spends on anything that is not a font: a leading blank,
# the header, the hint line, a blank, both scroll indicators, a blank, the
# description, the licence-and-state line, a blank, the footer's two lines,
# and one spare
# so the shell prompt has somewhere to land. Every row painted has to be bought
# here or the menu runs off the bottom -- and both indicators are ALWAYS
# emitted, blank when there is nothing to report, because the frame is
# overwritten in place and a row that comes and goes strands the taller frame's
# last line on screen.
$script:FontFrameChrome = 13

function Get-FontPickerFrame {
    <#
    .SYNOPSIS
    Every line of the font picker's frame, for one highlight position.

    .DESCRIPTION
    Pure -- it returns strings and paints nothing -- because the property that
    matters here cannot be eyeballed: the frame is overwritten in place at a
    fixed origin, so it must be the SAME NUMBER OF ROWS on every redraw. A
    description one line longer for one font would strand the previous frame's
    last row on screen and smear from there until the picker exits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [string[]]$Installed = @(),
        [Parameter(Mandatory)][int]$Index,
        [int]$WindowHeight = 24,
        [int]$Width = 100,
        [string]$Owner = 'terminal',
        [string]$TerminalName = 'This terminal',
        [string]$HintEscape = ''
    )

    $reset = "$([char]27)[0m"
    $room  = [Math]::Max(1, $Width - 4)
    # -1 so the frame never paints the window's last row: the newline that ends
    # it would scroll the buffer, and the whole frame is drawn at a fixed origin
    # on every redraw. The style picker's plan carries the same -1 for the same
    # reason, and was off by one before it did.
    $avail = $WindowHeight - $script:FontFrameChrome - 1
    $vp    = Get-PickerViewport -Total $Catalog.Count -Selected $Index -Available $avail

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('')
    $out.Add('  Choose a font')
    $out.Add("$HintEscape  Up/Down to move, Enter to install, Esc to cancel$reset")
    $out.Add('')

    if ($vp.More -and $vp.First -gt 0) {
        $out.Add("$HintEscape     ... $($vp.First) more above$reset")
    } else { $out.Add('') }

    for ($i = $vp.First; $i -lt ($vp.First + $vp.Count); $i++) {
        $f = $Catalog[$i]
        # Two different facts, two different marks, the same split the style
        # picker draws: '>' is where the cursor is, '[+]' is what is already on
        # this machine. They are unrelated and were never meant to be one mark.
        $prefix = if ($i -eq $Index) { '   > ' } else { '     ' }
        $mark   = if (Test-FontInstalled -Family $f.family -Installed $Installed) { '[+]' } else { '[ ]' }
        $out.Add(($prefix + ('{0,-20} {1}' -f $f.name, $mark)))
    }

    $below = $Catalog.Count - ($vp.First + $vp.Count)
    if ($vp.More -and $below -gt 0) {
        $out.Add("$HintEscape     ... $below more below$reset")
    } else { $out.Add('') }

    $sel = $Catalog[$Index]
    $out.Add('')
    $out.Add("$HintEscape  " + (Get-SentenceSummary -Notes $sel.description -MaxLength $room) + $reset)
    $state = if (Test-FontInstalled -Family $sel.family -Installed $Installed) { 'installed' } else { 'not installed' }
    $out.Add("$HintEscape  $($sel.license) -- $state$reset")
    $out.Add('')
    foreach ($line in (Get-FontPickerFooter -Owner $Owner -TerminalName $TerminalName)) {
        if ($line) {
            $out.Add("$HintEscape  " + (Get-SentenceSummary -Notes $line -MaxLength $room) + $reset)
        } else { $out.Add('') }
    }
    $out.Add('')
    return $out.ToArray()
}

function Invoke-FontPicker {
    <#
    .SYNOPSIS
    `tstyles font` with no argument on an interactive console: arrow to a font.

    .DESCRIPTION
    Drives Invoke-PickerLoop, the same loop the style picker uses, rather than
    growing a second one -- it owns only the index and key dispatch and never
    learns what is being picked.

    There is deliberately no live preview. A style previews by repainting the
    terminal, and there is no escape sequence for a font face: off Windows
    Terminal nothing here can show you the font before it is installed. Rather
    than imply otherwise, the footer says what Enter will actually do on THIS
    terminal, which is one of three different things.

    Seams: -ReadKey and -Write are injected so the whole interaction can be
    driven by tests. Returns @{ Outcome = 'confirmed'|'cancelled'; Index; Font }.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Catalog,
        [string[]]$Installed,
        [scriptblock]$ReadKey,
        [scriptblock]$Write,
        [int]$StartIndex = 0
    )
    if (-not $Catalog)  { $Catalog = @(Get-FontCatalog) }
    if (-not $PSBoundParameters.ContainsKey('Installed')) { $Installed = Get-InstalledFontFamily }
    if (-not $ReadKey)  { $ReadKey = { if ([Console]::KeyAvailable) { [Console]::ReadKey($true) } else { $null } } }
    if (-not $Write)    { $Write   = { param($line) Write-Host $line } }

    $kind  = Get-TerminalKind
    $owner = Get-FontOwner -Kind $kind
    $tname = Get-TerminalDisplayName -Kind $kind
    $hint  = Get-HintEscape

    # Per-call state in $script:, and the draw block is deliberately NOT a
    # closure. GetNewClosure rebinds the block to the session state of the
    # scope that made it, and under Pester's InModuleScope that is not the
    # module's -- so every call the block made to a module-private function
    # (Get-FontPickerFrame, here) died with "not recognized". A plain block
    # keeps the module session state it was defined in, and $script: inside a
    # module is the module's scope, so both halves resolve.
    #
    # Rebuilt on every call, Cleared included: $script: outlives the function,
    # and a flag left $true would mean the SECOND picker of a session never
    # clears the screen it is about to paint over.
    $script:FontPickerCtx = @{
        Catalog = $Catalog; Installed = $Installed; Owner = $owner
        Terminal = $tname;  Hint = $hint; Write = $Write; Cleared = $false
    }

    # Cleared ONCE, then every redraw overwrites in place from row 0. Clearing
    # per keystroke flickers the whole screen on each arrow, and nothing here
    # repaints the terminal between frames -- unlike the style picker, whose
    # preview does -- so the origin is simply the top of a screen this picker
    # owns for the duration.
    #
    # Erase-to-end-of-line on every row, because overwriting in place leaves the
    # previous frame's tail on any row that gets SHORTER -- which is what a
    # narrower description, or a window resize, does.
    $draw = {
        param($idx)
        $c = $script:FontPickerCtx
        $wh = 24; $w = 100
        try { $wh = [Console]::WindowHeight } catch { }
        try { $w  = [Console]::WindowWidth  } catch { }
        if (-not $c.Cleared) { Clear-Host; $c.Cleared = $true }
        try { [Console]::SetCursorPosition(0, 0) } catch { }
        $el = "$([char]27)[K"
        foreach ($line in (Get-FontPickerFrame -Catalog $c.Catalog -Installed $c.Installed -Index $idx `
                            -WindowHeight $wh -Width $w -Owner $c.Owner -TerminalName $c.Terminal `
                            -HintEscape $c.Hint)) {
            & $c.Write ($el + $line)
        }
    }

    $result = Invoke-PickerLoop -ItemCount $Catalog.Count -StartIndex $StartIndex `
                -ReadKey $ReadKey -OnPreview {} -OnRevert {} -OnDraw $draw
    @{
        Outcome = $result.Outcome
        Index   = $result.Index
        Font    = if ($result.Outcome -eq 'confirmed') { $Catalog[$result.Index] } else { $null }
    }
}

function Invoke-TerminalStyleFont {
    # `tstyles font` (list) / `tstyles font <name>` (install if needed + apply).
    param(
        [string]$Name,
        [string]$Target
    )
    if (-not $Name) {
        # The picker only where there is someone to press a key. Redirected
        # output, a script, a CI runner: the list is the right answer there and
        # the picker would block forever waiting on a keystroke nobody can send.
        if (Test-InteractiveConsole) {
            $picked = Invoke-FontPicker
            if ($picked.Outcome -ne 'confirmed') {
                Clear-Host
                Write-Host "Cancelled." -ForegroundColor Yellow
                return
            }
            Clear-Host
            $Name = $picked.Font.name
        } else {
            Show-FontList; return
        }
    }

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

    # Apply to the active profile. Applying a font means writing it into a
    # profile, and Set-ProfileFont only knows how to write Windows Terminal's
    # settings.json -- there is no escape sequence for a font face. So off WT
    # the install above IS the whole job: say so, rather than chasing a
    # settings.json that cannot exist and reporting "Could not locate Windows
    # Terminal settings.json" in red after an install that actually succeeded.
    #
    # Test-FontCommandCanApply, NOT (Get-TerminalCapability).Font: that flag is
    # a promise about the STYLE APPLY path and has been $true for WezTerm since
    # 0.8.24, where this gate then fell through and printed exactly the red line
    # the comment above says it exists to prevent.
    $fontKind = Get-TerminalKind
    $fontName = Get-TerminalDisplayName -Kind $fontKind
    $owner    = Get-FontOwner -Kind $fontKind
    if ($owner -ne 'command') {
        if ($owner -eq 'style') {
            # A terminal whose font a STYLE APPLY writes -- WezTerm, through the
            # generated Lua module. Saying it "takes its font from its own
            # settings" was false here: a font set in the user's own config is
            # overridden by the next apply, so that advice sent them to do
            # something that does not stick. Both routes below are measured:
            # setting config.font after the require line wins, and a tuned
            # style carries `font` into its theme.json, which the writer emits.
            Write-Host ("  '{0}' is installed. The applied style sets {1}'s font." -f $font.family, $fontName) -ForegroundColor DarkGray
            Write-Host "  To use it: tstyles tune <style> and save, which keeps the font with the style --" -ForegroundColor DarkGray
            Write-Host "  or set config.font AFTER the terminalstyles require line in your own config." -ForegroundColor DarkGray
        } else {
            Write-Host ("  {0} takes its font from its own settings, so tstyles font cannot apply it for you." -f $fontName) -ForegroundColor DarkGray
            Write-Host ("  '{0}' is installed and will be listed there." -f $font.family) -ForegroundColor DarkGray
        }
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) { Write-Host "Could not locate Windows Terminal settings.json." -ForegroundColor Red; return }
    # Parsed once and reused: the auto-detect below and the target check share it.
    $settingsJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settingsObj  = ConvertFrom-WTJson $settingsJson
    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settingsObj }
    if (-not $Target) { Write-Host "Could not detect the current profile; pass -Target '<name>'." -ForegroundColor Yellow; return }

    # Resolve BEFORE the backup. This was the other way round, so `tstyles font
    # <name> -Target <typo>` overwrote settings.json.bak with a copy of the
    # current file and only then reported the profile missing -- spending the
    # user's undo of their last real apply on a command that changed nothing.
    $resolvedTarget = Resolve-WTProfileTarget -Settings $settingsObj -TargetName $Target
    if (-not $resolvedTarget.Ok) {
        Write-Host (Get-WTTargetNotFoundMessage -ResolvedTarget $resolvedTarget -TargetName $Target) -ForegroundColor Yellow
        return
    }

    # The same tie, the same note as apply and reset. Set-ProfileFont resolves
    # again internally and gets the same answer; this is the one place that can
    # say so, and it said nothing -- so the font landed on whichever of two
    # same-named profiles came first and "Applied '<font>' to '<name>'" printed
    # in green either way.
    Write-AmbiguousTargetNote -ResolvedTarget $resolvedTarget -TargetName $Target -Verb 'Applied to'

    # Announced, like the apply and reset paths. -Quiet is for the picker and the
    # tuner, whose own docstring scopes it to "a menu that redraws every frame";
    # this is a linear one-shot command that inherited the silence without the
    # reason for it. There is ONE rolling .bak, so this write spends the copy the
    # last real apply left -- the only surviving record of the user's own
    # colorScheme, font and JSONC comments, since a successful apply re-serializes
    # settings.json and drops them. README teaches that file as the undo; a
    # command that consumes it has to say so on the same screen.
    # The catch here was empty, so a Copy-Item that really failed left the .bak
    # holding the state from the user's LAST REAL APPLY while settings.json was
    # rewritten underneath it, and the whole of what the user saw was "Applied
    # '<family>' to '<target>'". This is a linear one-shot command, so it says it
    # the way the apply and reset paths do.
    try { Save-SettingsBackup -Path $settingsPath -ResolvedTarget $resolvedTarget }
    catch { Write-Host (Get-BackupFailureNote -Reason "$_") -ForegroundColor Yellow }
    if (Set-ProfileFont -SettingsPath $settingsPath -TargetName $Target -Family $font.family) {
        Write-Host "  Applied '$($font.family)' to '$Target'. Open a new tab to see it." -ForegroundColor Green
    } else {
        Write-Host "Profile '$Target' not found in settings.json." -ForegroundColor Yellow
    }
}
