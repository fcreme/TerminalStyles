# wt-live-install.ps1 -- puts Windows Terminal Stable AND Preview on a
# GitHub-hosted Windows runner, for .github/workflows/wt-live-spike.yml.
#
# From microsoft/terminal's own release assets, by exact version, each checked
# against a pinned SHA-256. A build that is already registered for this user
# is left alone and logged: windows-latest (Server 2025) ships Stable in the
# box, and a Stable WindowsTerminal.exe is already running when the job starts
# -- it hosts the runner agent's own console. Updating that package would mean
# shutting it down, and with it the console the job is reported through.
#
# The only dependency either bundle declares is the Microsoft.UI.Xaml.2.8
# framework (read here from the x64 package's own AppxManifest.xml, not
# assumed). When no registered copy is new enough, it comes from Stable's
# PreinstallKit, which the Terminal maintainers point Server users to: Preview
# releases ship no kit of their own, and the kit's framework is newer than
# either bundle asks for.
#
# Under Windows PowerShell 5.1, where the Appx module loads natively. NOT FOR A
# MACHINE ANYONE USES: it refuses to start anywhere but a GitHub-hosted runner.
[CmdletBinding()]
param(
    # Where downloads go. Default: wt-install under the runner's temp folder.
    [string]$WorkDir
)

. (Join-Path $PSScriptRoot 'wt-live-common.ps1')

$script:WtBuilds = @(
    [pscustomobject]@{
        Label  = 'Stable'
        Name   = 'Microsoft.WindowsTerminal'
        Tag    = 'v1.25.2733.0'
        Asset  = 'Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle'
        Sha256 = 'cce6e9cc3c8457fa11ced1d2a7354888c7d6db83c5ace5d5891a52c95e3b21da'
    },
    [pscustomobject]@{
        Label  = 'Preview'
        Name   = 'Microsoft.WindowsTerminalPreview'
        Tag    = 'v1.26.2734.0'
        Asset  = 'Microsoft.WindowsTerminalPreview_1.26.2734.0_8wekyb3d8bbwe.msixbundle'
        Sha256 = 'dbc240a34e327fa65fc5edabe523a55cdc3a1b165f067e291c165cdc811269dd'
    }
)

$script:WtFrameworkKit = [pscustomobject]@{
    Tag    = 'v1.25.2733.0'
    Asset  = 'Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle_Windows10_PreinstallKit.zip'
    Sha256 = '151cb3ee9a93ba41ad7c412c0efd165a1e47eda6ef47d15a154c33af1e1cec9c'
}

function Get-ReleaseAsset {
    # A microsoft/terminal release asset on disk, its SHA-256 checked against
    # the pinned one. Kept when an earlier call already fetched it intact.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Asset,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$Directory
    )
    $path = Join-Path $Directory $Asset
    if ([System.IO.File]::Exists($path) -and (Get-FileSha256 -Path $path) -eq $Sha256) { return $path }
    $uri = 'https://github.com/microsoft/terminal/releases/download/{0}/{1}' -f $Tag, $Asset
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $uri -OutFile $path -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
            break
        } catch {
            if ($i -eq 3) { throw "could not download ${uri}: $($_.Exception.Message)" }
            Start-Sleep -Seconds (10 * $i)
        }
    }
    $have = Get-FileSha256 -Path $path
    if ($have -ne $Sha256) { throw "$Asset has SHA-256 $have, not the pinned $Sha256" }
    return $path
}

function Read-ZipEntryText {
    # One entry of an open ZipArchive, as UTF-8 text.
    param([Parameter(Mandatory)]$Archive, [Parameter(Mandatory)][string]$EntryName)
    $entry = $Archive.GetEntry($EntryName)
    if ($null -eq $entry) { throw "no $EntryName in the archive" }
    $reader = New-Object System.IO.StreamReader($entry.Open(), (New-Object System.Text.UTF8Encoding($false)), $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function ConvertTo-AppxPackageInfo {
    # What an AppxManifest.xml says about its package: { Name; Version;
    # Architecture; Dependencies = @({ Name; MinVersion; Publisher }) }.
    param([Parameter(Mandatory)][string]$ManifestXml)
    $doc = New-Object System.Xml.XmlDocument
    $doc.LoadXml($ManifestXml)
    $identity = $doc.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
    if ($null -eq $identity) { throw 'the manifest has no Identity' }
    $deps = @()
    foreach ($d in @($doc.DocumentElement.SelectNodes("*[local-name()='Dependencies']/*[local-name()='PackageDependency']"))) {
        $deps += [pscustomobject]@{
            Name       = $d.GetAttribute('Name')
            MinVersion = $d.GetAttribute('MinVersion')
            Publisher  = $d.GetAttribute('Publisher')
        }
    }
    return [pscustomobject]@{
        Name         = $identity.GetAttribute('Name')
        Version      = $identity.GetAttribute('Version')
        Architecture = $identity.GetAttribute('ProcessorArchitecture')
        Dependencies = $deps
    }
}

function Get-BundlePackageInfo {
    # The package an .msixbundle installs on $Architecture, read from that
    # package's own AppxManifest.xml: the bundle's AppxBundleManifest.xml names
    # the file, which is itself a zip inside the bundle.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BundlePath,
        [string]$Architecture = 'x64'
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($BundlePath)
    try {
        $bundle = New-Object System.Xml.XmlDocument
        $bundle.LoadXml((Read-ZipEntryText -Archive $zip -EntryName 'AppxMetadata/AppxBundleManifest.xml'))
        $packages = @($bundle.DocumentElement.SelectNodes("*[local-name()='Packages']/*[local-name()='Package']") |
            Where-Object { $_.GetAttribute('Type') -eq 'application' -and $_.GetAttribute('Architecture') -eq $Architecture })
        if ($packages.Count -ne 1) { throw "$BundlePath lists $($packages.Count) $Architecture application packages, not one" }
        $file = $packages[0].GetAttribute('FileName')
        $entry = $zip.GetEntry($file)
        if ($null -eq $entry) { throw "$BundlePath names $file but does not hold it" }
        $ms = New-Object System.IO.MemoryStream
        try {
            $s = $entry.Open()
            try { $s.CopyTo($ms) } finally { $s.Dispose() }
            $ms.Position = 0
            $inner = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                return (ConvertTo-AppxPackageInfo -ManifestXml (Read-ZipEntryText -Archive $inner -EntryName 'AppxManifest.xml'))
            } finally { $inner.Dispose() }
        } finally { $ms.Dispose() }
    } finally { $zip.Dispose() }
}

function Get-AppxFileInfo {
    # What an .appx file says about itself, from its AppxManifest.xml.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        return (ConvertTo-AppxPackageInfo -ManifestXml (Read-ZipEntryText -Archive $zip -EntryName 'AppxManifest.xml'))
    } finally { $zip.Dispose() }
}

function Test-FrameworkSatisfies {
    # A framework package satisfies a dependency: same name, x64, and at least
    # the minimum version, compared as versions.
    param([Parameter(Mandatory)]$Package, [Parameter(Mandatory)]$Dependency)
    $have = $null
    $need = $null
    if (-not [version]::TryParse("$($Package.Version)", [ref]$have)) { return $false }
    if (-not [version]::TryParse("$($Dependency.MinVersion)", [ref]$need)) { return $false }
    return ("$($Package.Name)" -eq "$($Dependency.Name)" -and "$($Package.Architecture)" -eq 'x64' -and $have -ge $need)
}

function Find-RegisteredFramework {
    # The registered framework packages that satisfy $Dependency for this user.
    param([Parameter(Mandatory)]$Dependency)
    @(Get-AppxPackage -Name $Dependency.Name -PackageTypeFilter Framework -ErrorAction SilentlyContinue |
        Where-Object { Test-FrameworkSatisfies -Package $_ -Dependency $Dependency })
}

function Get-KitFramework {
    # The x64 framework package for $Dependency, out of Stable's PreinstallKit,
    # checked against its own manifest.
    param([Parameter(Mandatory)]$Dependency, [Parameter(Mandatory)][string]$Directory)
    $kit = Get-ReleaseAsset -Tag $script:WtFrameworkKit.Tag -Asset $script:WtFrameworkKit.Asset `
                            -Sha256 $script:WtFrameworkKit.Sha256 -Directory $Directory
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($kit)
    try {
        $entries = @($zip.Entries | Where-Object { $_.Name -like ($Dependency.Name + '_*_x64__*.appx') })
        if ($entries.Count -ne 1) { throw "the PreinstallKit holds $($entries.Count) x64 $($Dependency.Name) packages, not one" }
        $out = Join-Path $Directory $entries[0].Name
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $out, $true)
    } finally { $zip.Dispose() }
    $info = Get-AppxFileInfo -Path $out
    if (-not (Test-FrameworkSatisfies -Package $info -Dependency $Dependency)) {
        throw "the PreinstallKit's $($entries[0].Name) is $($info.Name) $($info.Version) $($info.Architecture), which does not satisfy $($Dependency.Name) >= $($Dependency.MinVersion) x64"
    }
    return $out
}

function Install-WTBuild {
    # Downloads, checks and registers one build for this user, with whatever
    # framework it needs that is not registered yet.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Build, [Parameter(Mandatory)][string]$Directory)
    $bundle = Get-ReleaseAsset -Tag $Build.Tag -Asset $Build.Asset -Sha256 $Build.Sha256 -Directory $Directory
    Write-Host ("  downloaded {0}, sha256 {1} (pinned)" -f $Build.Asset, $Build.Sha256)
    $info = Get-BundlePackageInfo -BundlePath $bundle -Architecture 'x64'
    if ($info.Name -ne $Build.Name) { throw "$($Build.Asset) installs $($info.Name), not $($Build.Name)" }
    $dependencyPaths = @()
    foreach ($dep in @($info.Dependencies)) {
        $have = @(Find-RegisteredFramework -Dependency $dep)
        if ($have.Count -gt 0) {
            Write-Host ("  needs {0} >= {1}: registered already ({2})" -f $dep.Name, $dep.MinVersion,
                        (@($have | ForEach-Object { $_.Version }) -join ', '))
            continue
        }
        $appx = Get-KitFramework -Dependency $dep -Directory $Directory
        Write-Host ("  needs {0} >= {1}: none registered; adding {2} from the PreinstallKit" -f $dep.Name, $dep.MinVersion, (Split-Path $appx -Leaf))
        $dependencyPaths += $appx
    }
    try {
        if ($dependencyPaths.Count -gt 0) {
            Add-AppxPackage -Path $bundle -DependencyPath $dependencyPaths -ErrorAction Stop
        } else {
            Add-AppxPackage -Path $bundle -ErrorAction Stop
        }
    } catch {
        $why = "$($_.Exception.Message)"
        # The deployment log says why, when the message only names an activity.
        if ($why -match '\[ActivityId\]\s*([0-9a-fA-F-]{36})') {
            try {
                $log = @(Get-AppPackageLog -ActivityID $Matches[1] -ErrorAction Stop | ForEach-Object { "$($_.Message)" })
                if ($log.Count -gt 0) { $why += [Environment]::NewLine + ($log -join [Environment]::NewLine) }
            } catch { }
        }
        throw "Add-AppxPackage $($Build.Asset) failed: $why"
    }
}

function Get-WTBuildReport {
    # How one build is registered for this user, and what is wrong with it, if anything.
    param([Parameter(Mandatory)]$Build)
    $packages = @(Get-AppxPackage -Name $Build.Name -ErrorAction SilentlyContinue)
    $problem = $null
    if ($packages.Count -ne 1) {
        $problem = "{0} ({1}) is registered {2} times for {3}, not once" -f $Build.Label, $Build.Name, $packages.Count, $env:USERNAME
    } elseif ("$($packages[0].Status)" -ne 'Ok') {
        $problem = "{0} is registered with status {1}" -f $Build.Label, $packages[0].Status
    } elseif (-not "$($packages[0].InstallLocation)") {
        $problem = "{0} is registered with no InstallLocation" -f $Build.Label
    }
    $p = $null
    if ($packages.Count -gt 0) { $p = $packages[0] }
    return [pscustomobject]@{
        Label           = $Build.Label
        Name            = $Build.Name
        Version         = $(if ($p) { "$($p.Version)" } else { $null })
        PackageFullName = $(if ($p) { "$($p.PackageFullName)" } else { $null })
        FamilyName      = $(if ($p) { "$($p.PackageFamilyName)" } else { $null })
        InstallLocation = $(if ($p) { "$($p.InstallLocation)" } else { $null })
        Problem         = $problem
    }
}

function Invoke-WTLiveInstall {
    # The whole install. Returns the exit code: 0 when both builds are
    # registered, 1 when either is not, 2 when it refused to start.
    [CmdletBinding()]
    param([string]$WorkDir)
    if (-not (Test-GitHubHostedRunner)) {
        Write-Host 'wt-live-install.ps1 runs only on a GitHub-hosted runner: it installs'
        Write-Host 'Windows Terminal packages for the current user -- here, you.'
        return 2
    }
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    if (-not $WorkDir) { $WorkDir = Join-Path $env:RUNNER_TEMP 'wt-install' }
    $null = New-Item -ItemType Directory -Force -Path $WorkDir

    $lines = New-Object System.Collections.Generic.List[string]
    $failed = $false
    foreach ($build in $script:WtBuilds) {
        $before = @(Get-AppxPackage -Name $build.Name -ErrorAction SilentlyContinue)
        if ($before.Count -gt 0) {
            $how = 'already installed, left as it is (the pinned {0} is for a runner without it)' -f $build.Tag
            Write-Host ("{0}: {1} {2} {3}" -f $build.Label, $build.Name, (@($before | ForEach-Object { $_.Version }) -join ', '), $how)
        } else {
            Write-Host ("{0}: not installed; installing {1} from {2}" -f $build.Label, $build.Name, $build.Tag)
            try {
                Install-WTBuild -Build $build -Directory $WorkDir
                $how = 'installed from microsoft/terminal {0}, sha256 {1}' -f $build.Tag, $build.Sha256
            } catch {
                $how = "install failed: $($_.Exception.Message)"
                Write-Host ('::error title=WT live install::{0}: {1}' -f $build.Label, ($how -replace '\r?\n', ' '))
                $failed = $true
            }
        }
        $report = Get-WTBuildReport -Build $build
        if ($report.Problem) {
            Write-Host ('::error title=WT live install::{0}' -f $report.Problem)
            $failed = $true
        } else {
            Write-Host ("  registered: {0}" -f $report.PackageFullName)
            Write-Host ("  at:         {0}" -f $report.InstallLocation)
        }
        $state = 'registered'
        if ($report.Problem) { $state = '**' + $report.Problem + '**' }
        $lines.Add(('| {0} | {1} | {2} | {3} |' -f $build.Label, $report.Version, $state, ($how -replace '\|', '\|' -replace '\r?\n', ' ')))
    }

    # The alias the primary launch starts: each package's own wt.exe, which
    # names the build (the bare wt.exe in WindowsApps is claimed by both).
    $preview = Get-WTBuildReport -Build $script:WtBuilds[1]
    if ($preview.FamilyName) {
        $alias = Join-Path $env:LOCALAPPDATA ('Microsoft\WindowsApps\{0}\wt.exe' -f $preview.FamilyName)
        # An execution alias is a zero-byte reparse point; ask both ways.
        $seen = Wait-Until -Condition { [System.IO.File]::Exists($alias) -or (Test-Path -LiteralPath $alias) } -TimeoutSeconds 60
        Write-Host ("Preview's own alias {0}: {1}" -f $alias, $(if ($seen) { 'present' } else { 'NOT present after 60 s' }))
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        $md = New-Object System.Collections.Generic.List[string]
        $md.Add('### Windows Terminal on this runner')
        $md.Add('')
        $md.Add('| Build | Version | Registered | How |')
        $md.Add('|---|---|---|---|')
        foreach ($l in $lines) { $md.Add($l) }
        $md.Add('')
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $md -Encoding ASCII
    }
    if ($failed) { return 1 }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-WTLiveInstall -WorkDir $WorkDir)
}
