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

    # Apply to the active profile. Applying a font means writing it into a
    # profile, and Set-ProfileFont only knows how to write Windows Terminal's
    # settings.json -- there is no escape sequence for a font face. So off WT
    # the install above IS the whole job: say so, rather than chasing a
    # settings.json that cannot exist and reporting "Could not locate Windows
    # Terminal settings.json" in red after an install that actually succeeded.
    $fontKind = Get-TerminalKind
    if (-not (Get-TerminalCapability -Kind $fontKind).Font) {
        Write-Host ("  {0} takes its font from its own preferences, so TerminalStyles cannot apply it for you." -f (Get-TerminalDisplayName -Kind $fontKind)) -ForegroundColor DarkGray
        Write-Host ("  '{0}' is installed and will be listed there." -f $font.family) -ForegroundColor DarkGray
        return
    }

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
