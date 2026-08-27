# TerminalStyles one-liner installer.
#
# Intended to be run via:
#   iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
#
# What it does:
#   1. Downloads the latest TerminalStyles ZIP from GitHub
#   2. Extracts it to %LOCALAPPDATA%\TerminalStyles
#   3. Registers a loader block in your pwsh 7 $PROFILE (idempotent)
#   4. Detects if your existing $PROFILE matches a bundled style and migrates it
#
# After install, open a new pwsh tab and run:  tstyles

#Requires -Version 5.1

function Get-TStylesPlatform {
    # NOTE: duplicated from tstyles.ps1 -- keep in sync. (install.ps1 is the
    # bootstrap entry point, fetched and piped to iex before the module exists,
    # so it cannot dot-source the library.)
    if ($PSVersionTable.PSVersion.Major -lt 6) { return 'Windows' }
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'MacOS' }
    return 'Linux'
}

function Get-PowerShellEngineCandidate {
    # The PowerShell engines to look for when registering the $PROFILE loader.
    #
    # NOTE: mirrors the function of the same name in tstyles.ps1. This script is
    # the bootstrap -- it runs via `iwr | iex` BEFORE the module exists on disk,
    # so it cannot dot-source the library the way apply.ps1 now does. Keep the
    # two in step.
    #
    # Windows ships .exe names and two engines; everywhere else the binary is
    # `pwsh` with no extension and Windows PowerShell does not exist. Probing
    # only the .exe names meant this script downloaded, installed, and THEN
    # threw "Neither pwsh.exe nor powershell.exe was found on PATH" on macOS and
    # Linux -- leaving the files in place with no loader registered.
    param([string]$Platform = (Get-TStylesPlatform))

    if ($Platform -eq 'Windows') {
        return @(
            @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
            @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
        )
    }
    # pwsh-preview is what some macOS machines have INSTEAD of pwsh.
    return @(
        @{ Exe = 'pwsh';         Label = 'PowerShell 7' },
        @{ Exe = 'pwsh-preview'; Label = 'PowerShell 7 (preview)' }
    )
}


function Get-CurrentEngineLabel {
    <#
    .SYNOPSIS
    Which Get-PowerShellEngineCandidate label describes the shell running this
    script.

    .DESCRIPTION
    Off Windows every engine reports PSEdition 'Core', so an edition test cannot
    tell pwsh from pwsh-preview -- and INVERTING it, which is what this used to
    do, named a Windows-only engine on a Mac.

    The discriminator is the prerelease label, not the process name: on macOS
    `pwsh-preview` is a symlink to the 7-preview build's own `pwsh` binary, so
    Get-Process reports 'pwsh' for both.

    Edition is checked first so Windows PowerShell 5.1 never reaches the
    PreReleaseLabel lookup: its $PSVersionTable.PSVersion is a plain
    System.Version, which has no such property.
    #>
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return 'Windows PowerShell 5.1' }
    $v = $PSVersionTable.PSVersion
    $pre = if ($v.PSObject.Properties.Match('PreReleaseLabel').Count -gt 0) { $v.PreReleaseLabel } else { $null }
    if ($pre) { return 'PowerShell 7 (preview)' }
    return 'PowerShell 7'
}

function Get-TStylesDataRoot {
    # NOTE: duplicated from tstyles.ps1 -- keep in sync.
    param(
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir  = $HOME
    )
    switch ($Platform) {
        'Windows' {
            $base = $env:LOCALAPPDATA
            if (-not $base) { $base = Join-Path $HomeDir 'AppData\Local' }
            return Join-Path $base 'TerminalStyles'
        }
        'MacOS' {
            return Join-Path (Join-Path $HomeDir 'Library/Application Support') 'TerminalStyles'
        }
        default {
            $base = $env:XDG_DATA_HOME
            if (-not $base) { $base = Join-Path (Join-Path $HomeDir '.local') 'share' }
            return Join-Path $base 'TerminalStyles'
        }
    }
}

$repo       = 'fcreme/TerminalStyles'
$branch     = 'main'
$installDir = Get-TStylesDataRoot
$zipUrl     = "https://github.com/$repo/archive/refs/heads/$branch.zip"
# GUID-suffix both temp paths so back-to-back runs (or a crashed prior
# run leaving a locked file behind) never collide. AV scanners and
# OneDrive sync can hold transient locks on temp files; a fresh
# name per invocation sidesteps that entirely.
# GetTempPath(), not $env:TEMP: the var is Windows-only -- on macOS/Linux it is
# unset, and Join-Path would throw on a null path before the installer ran.
$runId      = [guid]::NewGuid().Guid.Substring(0,8)
$tempRoot   = [System.IO.Path]::GetTempPath()
$tempZip    = Join-Path $tempRoot "TerminalStyles-$branch-$runId.zip"
$tempDir    = Join-Path $tempRoot "TerminalStyles-extract-$runId"

$loaderBegin = '# ===== TerminalStyles BEGIN ====='
$loaderEnd   = '# ===== TerminalStyles END ====='
# Windows keeps the %LOCALAPPDATA%-relative form it has always written, so
# existing profiles see no diff on reinstall. Elsewhere there is no equivalent
# env var, so bake in the resolved absolute path.
$loaderImport = if ((Get-TStylesPlatform) -eq 'Windows') {
    'Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking'
} else {
    'Import-Module "{0}" -DisableNameChecking' -f (Join-Path $installDir 'TerminalStyles.psd1')
}
$loaderBody  = @"
$loaderBegin
$loaderImport
$loaderEnd
"@

# --- Output helpers ---
# Branded banner + step list + bordered "Ready" panel. Pure 7-bit ASCII
# so rendering is identical in any codepage / shell / terminal -- no
# Unicode box-drawing or arrows that might become `?` substitutes on
# WinPS 5.1's CP437 default.

function Write-InstallBanner {
    # Cyan rule + wordmark + tagline + cyan rule.
    $rule = '-' * 52
    Write-Host ''
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host '   tstyles' -ForegroundColor White -NoNewline
    Write-Host '  --  Windows Terminal themes for pwsh' -ForegroundColor DarkGray
    Write-Host "  $rule" -ForegroundColor Cyan
    Write-Host ''
}

function Write-InstallStep {
    # Single-line step indicator. -Check appends a green [ok] tag to
    # signal completion of an action whose "in progress" version printed
    # on the previous line.
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Check
    )
    Write-Host '  > ' -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -NoNewline
    if ($Check) {
        Write-Host ' [ok]' -ForegroundColor Green
    } else {
        Write-Host ''
    }
}

function Write-InstallPanel {
    # Bordered "Ready" panel listing the count, the one command to run,
    # and all theme names wrapped to fit. ASCII corners (+) + sides (|)
    # + dashes (-) for cross-codepage rendering.
    param(
        [Parameter(Mandatory)][string[]]$ThemeNames,
        [Parameter(Mandatory)][string[]]$RegisteredEngines
    )
    $width = 56   # interior width, between | chars (not counting them)

    # Borders -- both 58 visible chars (1 corner + 56 interior + 1 corner)
    $labelPart = '- Ready '                                  # 8 chars
    $top    = '+' + $labelPart + ('-' * ($width - $labelPart.Length)) + '+'
    $bottom = '+' + ('-' * $width) + '+'

    # Row writer: writes one panel row with the leading '  ' indent,
    # green borders, and middle content padded to exactly $width chars.
    # The middle content is rendered as up to three colored segments.
    function WriteRow {
        param(
            [Parameter(Mandatory)][int]$Width,
            [string[]]$Segments = @(),
            [string[]]$Colors
        )
        Write-Host '  |' -ForegroundColor Green -NoNewline
        $printed = 0
        for ($i = 0; $i -lt $Segments.Count; $i++) {
            $seg = $Segments[$i]
            $color = if ($Colors -and $i -lt $Colors.Count -and $Colors[$i]) { $Colors[$i] } else { $null }
            if ($color) {
                Write-Host $seg -ForegroundColor $color -NoNewline
            } else {
                Write-Host $seg -NoNewline
            }
            $printed += $seg.Length
        }
        if ($printed -lt $Width) {
            Write-Host (' ' * ($Width - $printed)) -NoNewline
        }
        Write-Host '|' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "  $top" -ForegroundColor Green

    # Row: "  N themes installed."
    WriteRow -Width $width -Segments @('  ', "$($ThemeNames.Count) themes installed.")

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Row: "      tstyles" with the command in cyan
    WriteRow -Width $width -Segments @('      ', 'tstyles') -Colors @($null, 'Cyan')

    # Spacer row
    WriteRow -Width $width -Segments @('')

    # Theme-name rows: wrap at $width chars. ' * ' separator (ASCII).
    $line = '  '
    foreach ($name in $ThemeNames) {
        $candidate = if ($line.Trim().Length -eq 0) { "$line$name" } else { "$line * $name" }
        if ($candidate.Length -gt $width) {
            WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
            $line = "  $name"
        } else {
            $line = $candidate
        }
    }
    if ($line.Trim().Length -gt 0) {
        WriteRow -Width $width -Segments @($line) -Colors @('DarkGray')
    }

    Write-Host "  $bottom" -ForegroundColor Green
    Write-Host ''

    # If more than one engine was registered, mention the ones the user isn't
    # currently in -- they need a new tab for those.
    #
    # Named from what was ACTUALLY registered, not inferred by inverting
    # $PSVersionTable.PSEdition. That inversion assumed the only two engines are
    # pwsh 7 and Windows PowerShell 5.1, which held while this script probed for
    # pwsh.exe / powershell.exe. It stopped holding when the probe became
    # platform-aware: on macOS the pair is pwsh and pwsh-preview, both Core, so
    # "more than one" became true off Windows and the message told Mac users the
    # install was "Also wired up for Windows PowerShell 5.1".
    if ($RegisteredEngines.Count -gt 1) {
        $others = @($RegisteredEngines | Where-Object { $_ -ne (Get-CurrentEngineLabel) })
        if ($others.Count -gt 0) {
            Write-Host "  Also wired up for $($others -join ', ') -- available in any new tab there." -ForegroundColor DarkGray
            Write-Host ''
        }
    }
}

# --- Helper: get a shell's $PROFILE + execution policy in ONE launch ---
# Each shell launch (pwsh.exe / powershell.exe) costs ~500ms on cold start.
# We previously launched each shell twice (once for $PROFILE, once for
# Get-ExecutionPolicy). Combining cuts ~1s off install on dual-shell systems.
function Get-ShellInfo {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Label)
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "  $Label not detected on PATH, skipping." -ForegroundColor DarkGray
        return $null
    }
    # Marker-separated output keeps parsing simple across both engines.
    $out = & $cmd.Source -NoProfile -NonInteractive -Command "Write-Output ('PROFILE='+`$PROFILE); Write-Output ('POLICY='+(Get-ExecutionPolicy))" 2>$null
    $profilePath = $null
    $policy = $null
    foreach ($line in @($out)) {
        $s = "$line".Trim()
        if ($s.StartsWith('PROFILE=')) { $profilePath = $s.Substring(8) }
        elseif ($s.StartsWith('POLICY=')) { $policy = $s.Substring(7) }
    }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-Host "  Could not determine $Label profile path, skipping." -ForegroundColor Yellow
        return $null
    }
    return [pscustomobject]@{
        ProfilePath = $profilePath
        Policy      = $policy
    }
}

# --- Atomic UTF-8 (no BOM) text write: temp sibling + replace ---
function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $enc = [System.Text.UTF8Encoding]::new($false)
    $dir = Split-Path -Parent $Path
    $tmp = Join-Path $dir ('.' + (Split-Path -Leaf $Path) + '.tmp-' + ([guid]::NewGuid().Guid.Substring(0,8)))
    [System.IO.File]::WriteAllText($tmp, $Content, $enc)
    try {
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)   # atomic; consumes $tmp
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        # Fallback: best-effort direct write (non-atomic). Surface once.
        Write-Host "  Note: atomic write unavailable on this volume; writing directly." -ForegroundColor DarkGray
        [System.IO.File]::WriteAllText($Path, $Content, $enc)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# --- Helper: write the loader block into a profile, migrating bundled-style content if matched ---
function Register-LoaderInProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$LoaderBegin,
        [Parameter(Mandatory)][string]$LoaderEnd,
        [Parameter(Mandatory)][string]$LoaderBody
    )

    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    # UTF-8 explicit (WinPS 5.1's Get-Content -Raw defaults to ANSI codepage).
    $existing = if (Test-Path -LiteralPath $ProfilePath) {
        [System.IO.File]::ReadAllText($ProfilePath, [System.Text.UTF8Encoding]::new($false))
    } else { '' }
    $originalContent = $existing

    $escBegin = [regex]::Escape($LoaderBegin)
    $escEnd   = [regex]::Escape($LoaderEnd)
    $blockPattern = "(?ms)$escBegin.*?$escEnd\r?\n?"

    $migrated = $false
    if ($existing.Trim().Length -gt 0) {
        $styleDirs = Get-ChildItem -LiteralPath (Join-Path $InstallDir 'styles') -Directory -ErrorAction SilentlyContinue
        foreach ($s in $styleDirs) {
            $sp = Join-Path $s.FullName 'profile.ps1'
            if (Test-Path -LiteralPath $sp) {
                $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
                if ($styleContent.TrimEnd() -eq $existing.TrimEnd()) {
                    $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Copy-Item -LiteralPath $ProfilePath -Destination $bak -Force
                    Write-Host "  Detected '$($s.Name)' style in $Label profile -- migrating into TerminalStyles." -ForegroundColor Yellow
                    Write-Host "  Original profile backed up to: $bak" -ForegroundColor Gray
                    Copy-Item -LiteralPath $sp -Destination (Join-Path $InstallDir 'current-style.ps1') -Force
                    $existing = ''
                    $migrated = $true
                    break
                }
            }
        }
    }

    # First-touch backup: the first time we add our loader to a profile that
    # has pre-existing user content and no loader block yet, preserve it.
    # Skip when we already migrated (that path backed up) or when our block
    # is already present (a re-register only swaps our own block).
    if (-not $migrated -and $originalContent.Trim().Length -gt 0 -and ($originalContent -notmatch $blockPattern)) {
        $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ProfilePath -Destination $bak -Force
        Write-Host "  Backed up your existing $Label profile to: $bak" -ForegroundColor Gray
    }

    if ($existing -match $blockPattern) {
        $existing = [regex]::Replace($existing, $blockPattern, '')
    }

    $final = ($existing.TrimEnd() + "`r`n`r`n" + $LoaderBody + "`r`n").TrimStart()
    Write-TextFileAtomic -Path $ProfilePath -Content $final
}

# --- Validate a downloaded archive before extracting ---
function Assert-ValidArchive {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path) -or ((Get-Item -LiteralPath $Path).Length -eq 0)) {
        throw "Download was empty or missing. This is usually a transient network issue -- re-run the installer."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        throw "Downloaded file is not a valid ZIP archive (partial download or network error) -- re-run the installer."
    }
    try {
        $hasManifest = @($zip.Entries | Where-Object { $_.FullName -match 'TerminalStyles\.psd1$' }).Count -gt 0
    } finally {
        $zip.Dispose()
    }
    if (-not $hasManifest) {
        throw "Downloaded archive does not look like TerminalStyles (module manifest not found) -- re-run the installer."
    }
}

# --- Assert the module actually landed after the install move ---
function Sync-InstallTree {
    # Put the downloaded tree into the data root, removing ONLY what this
    # install manages.
    #
    # $InstallDir is both the install target and the module's writable data root
    # (Get-TStylesDataRoot), so shipped files sit directly alongside user state:
    # cache/ (lazily-fetched backgrounds, tens of megabytes), fonts/, profiles/,
    # current-style.ps1 / .json / .osc, current-prompt.sh, the staged shell
    # runtime, the update-check markers, and tuned styles under styles/.
    #
    # This used to wipe the whole directory and copy a hand-listed subset back.
    # Everything off that list was destroyed on every update -- and the list read
    # styles/<name>/background.*, the PRE-0.2.0 cache location, so on any current
    # install it preserved nothing while deleting the real cache and every tuned
    # style. Its restore path also hardcoded a backslash separator, so it could
    # not have worked off Windows either.
    #
    # The rule now: the install owns exactly the entries it ships. Anything else
    # under the data root belongs to the user and is never touched.
    param(
        [Parameter(Mandatory)][string]$ExtractedRoot,
        [Parameter(Mandatory)][string]$InstallDir
    )

    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    foreach ($entry in Get-ChildItem -LiteralPath $ExtractedRoot -Force) {
        $target = Join-Path $InstallDir $entry.Name
        if (-not (Test-Path -LiteralPath $target)) { continue }

        # styles/ is the one directory the install and the user share: bundled
        # themes sit beside the user's own, and the README documents dropping a
        # folder named after a bundled theme to override it in place. Removing
        # the tree would take both, so let the copy below overwrite file by file.
        if ($entry.PSIsContainer -and $entry.Name -eq 'styles') { continue }

        Remove-Item -LiteralPath $target -Recurse -Force
        if (Test-Path -LiteralPath $target) {
            throw ("Could not replace '$target' (a file lock may be held by another PowerShell " +
                   "tab, OneDrive, or antivirus). Close other PowerShell windows and re-run " +
                   "the installer.")
        }
    }

    Copy-Item -Path (Join-Path $ExtractedRoot '*') -Destination $InstallDir -Recurse -Force
}

function Assert-InstallLanded {
    param([Parameter(Mandatory)][string]$InstallDir)
    $manifest = Join-Path $InstallDir 'TerminalStyles.psd1'
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw ("Install did not complete: '$manifest' is missing. A leftover file lock on " +
               "'$InstallDir' (another PowerShell tab, OneDrive, or antivirus) may have blocked " +
               "the update. Close other PowerShell windows and re-run the installer.")
    }
}

# --- Pure decision: does this effective policy permit the loader to run? ---
function Test-PolicyResolved {
    param([string]$Policy)
    return (-not [string]::IsNullOrWhiteSpace($Policy)) -and
           ($Policy.Trim() -notin @('Restricted', 'AllSigned'))
}

# --- Offer to fix Restricted/AllSigned execution policy for an engine ---
function Resolve-ExecutionPolicy {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string]$Label,
        [string]$EffectivePolicy
    )
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) { return }
    if (Test-PolicyResolved -Policy $EffectivePolicy) { return }   # already fine

    Write-Host ""
    Write-Host "  ! Script execution is disabled for $Label (effective policy: $($EffectivePolicy.Trim()))." -ForegroundColor Yellow
    Write-Host "    Without changing this, the TerminalStyles loader cannot run on shell startup." -ForegroundColor Yellow

    if (-not [Environment]::UserInteractive) {
        Write-Host "    Non-interactive session -- skipping the prompt. To fix, run in ${Label}:" -ForegroundColor DarkGray
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        return
    }

    $ans = Read-Host "    Set CurrentUser policy to RemoteSigned for $Label? [Y/n]"
    if (-not ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(?i)y')) {
        Write-Host "    Skipped. To fix later, run in ${Label}:" -ForegroundColor DarkGray
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        return
    }

    try {
        # Set + re-query in one launch; the last non-empty line is the new policy.
        $out = & $cmd.Source -NoProfile -NonInteractive -Command `
            'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force; Get-ExecutionPolicy -Scope CurrentUser'
        $newPolicy = @($out | Where-Object { "$_".Trim() } | Select-Object -Last 1)[0]
        if (Test-PolicyResolved -Policy "$newPolicy") {
            Write-Host "    Done. CurrentUser policy is now $("$newPolicy".Trim()) for $Label." -ForegroundColor Green
        } else {
            Write-Host "    The policy did not change (still '$("$newPolicy".Trim())')." -ForegroundColor Red
            Write-Host "    A machine-wide policy (LocalMachine / GPO) may be blocking CurrentUser overrides." -ForegroundColor Yellow
            Write-Host "    Run this manually, elevated if needed:" -ForegroundColor Yellow
            Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "    Could not set policy automatically: $_" -ForegroundColor Red
        Write-Host "    A machine-wide policy (LocalMachine / GPO) may be blocking CurrentUser overrides." -ForegroundColor Yellow
        Write-Host "    Run this manually, elevated if needed:" -ForegroundColor Yellow
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
    }
}

# Main flow. Guarded so tests can dot-source this script for its functions
# (set $TStylesInstallNoRun = $true) without running the installer. A normal
# `iwr | iex` run never sets the var, so main runs.
if (-not $TStylesInstallNoRun) {

    # Force UTF-8 console output as defense-in-depth (see header note).
    # Windows only: chcp is a Windows console command, and `$null = & chcp ... 2>&1`
    # does not swallow its absence -- a missing NATIVE COMMAND is a PowerShell
    # error, not stderr output, so on macOS and Linux this printed a red
    # "The term 'chcp' is not recognized" block as the very first thing anyone
    # running the documented `iwr | iex` one-liner saw. The install worked; it
    # just looked like it had failed before it started.
    if ((Get-TStylesPlatform) -eq 'Windows') {
        $null = & chcp 65001 2>&1
    }
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    # The entry point is `iwr ... | iex`, which runs this whole body in the
    # CALLER'S scope -- so every preference set here outlives the install and
    # changes how the user's shell behaves afterwards. $ErrorActionPreference in
    # particular: leaving it on 'Stop' turns every later non-terminating error in
    # that session into a terminating one. Save and restore them.
    $tstylesPrevEAP      = $ErrorActionPreference
    $tstylesPrevProgress = $ProgressPreference
    $tstylesPrevTls      = $null

    $ErrorActionPreference = 'Stop'
    # Suppress the IWR / Expand-Archive progress UI. On Windows PowerShell 5.1
    # this is the dominant cost of the install -- the progress-bar rendering
    # can make a ~10MB download take 30+ seconds. Silencing it gives 5-10x
    # speedups. Doesn't affect pwsh 7 noticeably but doesn't hurt either.
    $ProgressPreference = 'SilentlyContinue'

    # Force TLS 1.2 on .NET Framework, where the default SecurityProtocol can
    # still omit it -- and GitHub, like PSGallery, hard-refuses anything older.
    # Without this the download below fails on a stock Windows PowerShell 5.1
    # with a bare "underlying connection was closed", which reads like a network
    # fault rather than a protocol one.
    #
    # This project already does exactly this in .github/workflows/test.yml to
    # bootstrap Pester on the 5.1 leg. It was missing from the one place a user
    # actually runs.
    try {
        $tstylesPrevTls = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        # pwsh 7 on Unix negotiates TLS through the OS and may not expose this.
        # Not being able to raise the floor is not a reason to refuse to install.
        $tstylesPrevTls = $null
    }

    try {

    Write-InstallBanner

    # --- Download ---
    Write-InstallStep "Downloading"
    # -TimeoutSec, like the far less important update-check call further down
    # already has. Without it a stalled connection hangs the installer forever
    # with a "Downloading" line and no way to tell it apart from a slow link.
    # 300s is generous for ~10 MB and still bounded.
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing -TimeoutSec 300
    Assert-ValidArchive -Path $tempZip
    Write-InstallStep "Downloading" -Check

    # --- Extract ---
    Write-InstallStep "Extracting"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    Write-InstallStep "Extracting" -Check

    $extractedRoot = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
    if (-not $extractedRoot) { throw "Failed to locate extracted folder under $tempDir" }

    # --- Install into the data root (preserves everything the install does not own) ---
    Write-InstallStep "Installing"
    Sync-InstallTree -ExtractedRoot $extractedRoot.FullName -InstallDir $installDir
    Assert-InstallLanded -InstallDir $installDir
    Write-InstallStep "Installing" -Check

    # Cleanup temp
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    # --- Record install SHA for the update checker ---
    try {
        # GitHub's API documents User-Agent as required for unauthenticated requests.
        $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" `
                                        -Headers @{ 'User-Agent' = 'TerminalStyles-Installer' } `
                                        -TimeoutSec 5 -ErrorAction Stop
        if ($commitInfo.sha) {
            [System.IO.File]::WriteAllText(
                (Join-Path $installDir '.installed-sha'),
                $commitInfo.sha,
                [System.Text.UTF8Encoding]::new($false))
        }
    } catch {
        Write-Host "Note: couldn't record install SHA (network?); update checker will be disabled." -ForegroundColor DarkGray
    }

    # --- Register loader in every detected shell ---
    $shells = @(Get-PowerShellEngineCandidate)

    $registered = @()
    foreach ($s in $shells) {
        $info = Get-ShellInfo -Exe $s.Exe -Label $s.Label
        if (-not $info) { continue }
        Register-LoaderInProfile -ProfilePath $info.ProfilePath -Label $s.Label -InstallDir $installDir `
            -LoaderBegin $loaderBegin -LoaderEnd $loaderEnd -LoaderBody $loaderBody
        Resolve-ExecutionPolicy -Exe $s.Exe -Label $s.Label -EffectivePolicy $info.Policy
        Write-InstallStep "Registered loader: $($s.Label)" -Check
        $registered += $s.Label
    }

    if (-not $registered) {
        # Not a throw: the files are already installed by this point, so failing
        # here left the user installed-but-unloaded with a stack trace. Tell them
        # the one line that fixes it instead.
        Write-Host ""
        Write-Host ("No PowerShell engine found on PATH (looked for: {0})." -f
                    ((Get-PowerShellEngineCandidate).Exe -join ', ')) -ForegroundColor Yellow
        Write-Host "TerminalStyles is installed at $installDir, but no `$PROFILE loader was registered." -ForegroundColor Yellow
        Write-Host "Add this line to your PowerShell profile to load it:" -ForegroundColor Yellow
        Write-Host "    Import-Module TerminalStyles -DisableNameChecking" -ForegroundColor Cyan
        Write-Host ""
    }

    # Gather the bundled theme names for the "Ready" panel
    $themeNames = @(
        Get-ChildItem -LiteralPath (Join-Path $installDir 'styles') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            Sort-Object Name |
            ForEach-Object Name
    )

    Write-InstallPanel -ThemeNames $themeNames -RegisteredEngines $registered

    # --- Same-tab handoff ---
    # Import the freshly-installed module into the GLOBAL scope (not the
    # script's child scope) so the `tstyles` command is available in the
    # caller's session immediately. Without -Global, the import would be
    # scoped to this script and disappear when install.ps1 returns.
    $installedManifest = Join-Path $installDir 'TerminalStyles.psd1'
    if (Test-Path -LiteralPath $installedManifest) {
        Import-Module $installedManifest -Force -Global -DisableNameChecking *> $null
    }

    } finally {
        # Put the caller's session back. This body runs in THEIR scope under
        # `iwr | iex`, so anything left set here follows them around for the rest
        # of the session -- and it has to be restored on the failure paths too,
        # which is why this is a finally rather than a few lines at the end.
        $ErrorActionPreference = $tstylesPrevEAP
        $ProgressPreference    = $tstylesPrevProgress
        if ($null -ne $tstylesPrevTls) {
            try { [Net.ServicePointManager]::SecurityProtocol = $tstylesPrevTls } catch { }
        }
    }
}
