# wt-live-common.ps1 -- helpers shared by the live Windows Terminal check.
#
# Three scripts dot-source this, and it only defines:
#   scripts/wt-live-install.ps1  puts Windows Terminal Stable and Preview on the runner;
#   scripts/wt-live-check.ps1    opens a Preview tab, waits for it, and judges;
#   scripts/wt-live-probe.ps1    runs INSIDE that tab, under the engine under test.
# All of it runs under Windows PowerShell 5.1, so: ASCII only, no syntax newer
# than 5.1, and the C# below is C# 5, which is what 5.1's Add-Type compiles.

function Test-GitHubHostedRunner {
    # True only on a runner GitHub hosts: a new machine for each job, discarded
    # after it. GITHUB_ACTIONS alone is not enough -- a self-hosted runner sets
    # it too, and a self-hosted runner is somebody's machine.
    #
    # The same rule as Test-GitHubHostedRunner in scripts/live-gallery-check.ps1;
    # tests/WT-Live-Check.Tests.ps1 holds the two to the same answers.
    [CmdletBinding()]
    param(
        [string]$GitHubActions = $env:GITHUB_ACTIONS,
        [string]$RunnerEnvironment = $env:RUNNER_ENVIRONMENT
    )
    return ($GitHubActions -eq 'true' -and $RunnerEnvironment -eq 'github-hosted')
}

function Format-Utc {
    # A time as round-trip ISO 8601 UTC text, or $null. Text rather than a
    # [datetime], because Windows PowerShell 5.1's ConvertTo-Json writes a
    # [datetime] as "\/Date(...)\/".
    param($Date)
    if ($null -eq $Date) { return $null }
    return ([datetime]$Date).ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-SamePath {
    # Two Windows paths name the same file, compared as Windows compares them:
    # ignoring case, and ignoring a trailing separator. Strings only, so the
    # verdicts that use it run, and are tested, on macOS and Linux too.
    param([AllowNull()][AllowEmptyString()][string]$A, [AllowNull()][AllowEmptyString()][string]$B)
    if (-not $A -or -not $B) { return $false }
    $x = ($A -replace '/', '\').TrimEnd('\')
    $y = ($B -replace '/', '\').TrimEnd('\')
    return [string]::Equals($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathUnder {
    # $Path lies inside the folder $Root (not merely beside one whose name
    # starts the same way).
    param([AllowNull()][AllowEmptyString()][string]$Path, [AllowNull()][AllowEmptyString()][string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    $p = ($Path -replace '/', '\')
    $r = ($Root -replace '/', '\').TrimEnd('\') + '\'
    return $p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)
}

function Read-SharedBytes {
    # The file's bytes, or $null when it is missing or stays unreadable. Opened
    # with every share mode: Windows Terminal watches settings.json and may hold
    # it open, and a reader that asks for FileShare.Read alone fails exactly then.
    param([Parameter(Mandatory)][string]$Path, [int]$Attempts = 5)
    for ($i = 1; $i -le $Attempts; $i++) {
        if (-not [System.IO.File]::Exists($Path)) { return $null }
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                         [System.IO.FileShare]'ReadWrite, Delete')
            try {
                $ms = New-Object System.IO.MemoryStream
                $fs.CopyTo($ms)
                return ,$ms.ToArray()
            } finally { $fs.Dispose() }
        } catch {
            if ($i -lt $Attempts) { Start-Sleep -Milliseconds 200 }
        }
    }
    return $null
}

function Get-BytesSha256 {
    # Lowercase hex SHA-256 of a byte array.
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function ConvertFrom-Utf8Bytes {
    # UTF-8 text from bytes, without the byte-order mark if the file had one.
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($Bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Get-FileSha256 {
    # Lowercase hex SHA-256 of the file, or $null when it is missing or unreadable.
    param([Parameter(Mandatory)][string]$Path)
    $bytes = Read-SharedBytes -Path $Path
    if ($null -eq $bytes) { return $null }
    return (Get-BytesSha256 -Bytes $bytes)
}

function Get-FileFacts {
    # One reading of a file: whether it is there, its SHA-256, size and write
    # time. Exists and Sha256 are separate on purpose: a verdict has to tell
    # "missing" from "there but unreadable", and two $null hashes must never
    # count as the same file.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    $facts = [ordered]@{ Path = $Path; Exists = $false; Sha256 = $null; Length = $null; LastWriteUtc = $null }
    if ($Path) {
        try {
            $fi = New-Object System.IO.FileInfo($Path)
            if ($fi.Exists) {
                $facts.Exists = $true
                $facts.Length = $fi.Length
                $facts.LastWriteUtc = Format-Utc $fi.LastWriteTimeUtc
                $facts.Sha256 = Get-FileSha256 -Path $Path
            }
        } catch { }
    }
    return [pscustomobject]$facts
}

function Wait-Until {
    # Polls $Condition until it is true or $TimeoutSeconds pass. Returns whether it became true.
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [double]$TimeoutSeconds = 30,
        [int]$IntervalMs = 500
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([datetime]::UtcNow -lt $deadline) {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return [bool](& $Condition)
}

function Wait-FileQuiet {
    # Polls the file's SHA-256 until it has not changed for $QuietSeconds, or
    # $TimeoutSeconds pass. Windows Terminal reloads settings.json whenever it
    # changes and can write it back, so a reading taken mid-reload is not the
    # one to compare. Returns { Settled; Sha256; Changes; Exists }; Changes
    # counts the rewrites it saw while waiting.
    param(
        [Parameter(Mandatory)][string]$Path,
        [double]$QuietSeconds = 3,
        [double]$TimeoutSeconds = 30,
        [int]$IntervalMs = 500
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $last = Get-FileSha256 -Path $Path
    $quietSince = [datetime]::UtcNow
    $changes = 0
    while ([datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds $IntervalMs
        $now = Get-FileSha256 -Path $Path
        if ($now -ne $last) {
            $changes++
            $last = $now
            $quietSince = [datetime]::UtcNow
            continue
        }
        if (([datetime]::UtcNow - $quietSince).TotalSeconds -ge $QuietSeconds) {
            return [pscustomobject]@{ Settled = $true; Sha256 = $last; Changes = $changes; Exists = [System.IO.File]::Exists($Path) }
        }
    }
    return [pscustomobject]@{ Settled = $false; Sha256 = $last; Changes = $changes; Exists = [System.IO.File]::Exists($Path) }
}

function Write-JsonAtomic {
    # Writes $InputObject as UTF-8 JSON (no BOM) beside $Path, then moves it
    # into place, so a reader polling for $Path never opens a half-written file.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowNull()]$InputObject)
    $json = ConvertTo-Json -InputObject $InputObject -Depth 20
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Delete($Path) }
    [System.IO.File]::Move($tmp, $Path)
}

function Read-JsonFile {
    # The parsed JSON at $Path; throws when it is missing or does not parse.
    param([Parameter(Mandatory)][string]$Path)
    $bytes = Read-SharedBytes -Path $Path
    if ($null -eq $bytes) { throw "cannot read $Path" }
    return ((ConvertFrom-Utf8Bytes -Bytes $bytes) | ConvertFrom-Json)
}

function Get-ProcessTable {
    # Every process, from one Win32_Process query, keyed by ProcessId ([int]).
    # One snapshot, so a walk over it sees one consistent tree.
    [CmdletBinding()]
    param()
    $table = @{}
    foreach ($p in @(Get-CimInstance -ClassName Win32_Process -OperationTimeoutSec 30 -ErrorAction Stop)) {
        $table[[int]$p.ProcessId] = $p
    }
    return $table
}

function Get-ProcessChain {
    # $StartId and its ancestors, nearest first, each as { ProcessId;
    # ParentProcessId; Name; ExecutablePath; Created; Package; PackageError }.
    # Read independently of the module's own walk (Find-WTHostExePath), so the
    # two can be compared. Stops where the answer stops being trustworthy, as
    # that walk does: a lookup that finds nothing, PID 0 or 4, a PID already
    # seen, $MaxDepth, or a parent created after its child (its PID was reused).
    param([int]$StartId = $PID, [int]$MaxDepth = 24, [hashtable]$Table)
    if ($null -eq $Table) { $Table = Get-ProcessTable }
    $chain = New-Object System.Collections.ArrayList
    $seen = @{}
    $id = $StartId
    $childCreated = $null
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if ($id -le 0 -or $id -eq 4 -or $seen.ContainsKey($id)) { break }
        $seen[$id] = $true
        $p = $Table[$id]
        if ($null -eq $p) { break }
        $created = $null
        if ($p.CreationDate) { $created = ([datetime]$p.CreationDate).ToUniversalTime() }
        if ($null -ne $childCreated -and $null -ne $created -and $created -gt $childCreated) { break }
        [void]$chain.Add([pscustomobject]@{
            ProcessId       = [int]$p.ProcessId
            ParentProcessId = [int]$p.ParentProcessId
            Name            = [string]$p.Name
            ExecutablePath  = [string]$p.ExecutablePath
            Created         = Format-Utc $created
            Package         = $null
            PackageError    = $null
        })
        $childCreated = $created
        $id = [int]$p.ParentProcessId
    }
    return $chain.ToArray()
}

# Native calls: a process's package identity, and app activation. C# 5, for
# Windows PowerShell 5.1's compiler; compiled on first use, never at dot-source,
# so dot-sourcing this file (as the tests do, on any platform) compiles nothing.
$script:WtLiveNativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WtLive
{
    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                                [MarshalAs(UnmanagedType.LPWStr)] string arguments,
                                int options, out uint processId);
        // Declared only to hold their places in the vtable; never called.
        [PreserveSig]
        int ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray,
                            [MarshalAs(UnmanagedType.LPWStr)] string verb, out uint processId);
        [PreserveSig]
        int ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray,
                                out uint processId);
    }

    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    public class ApplicationActivationManager
    {
    }

    public static class Native
    {
        const uint ProcessQueryLimitedInformation = 0x1000;
        const int ErrorInsufficientBuffer = 122;

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder name);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern int GetCurrentPackageFullName(ref uint length, StringBuilder name);

        // The package full name of a process, or null with the Win32 error in
        // 'error'. 15700 (APPMODEL_ERROR_NO_PACKAGE) means the process has no
        // package identity: it runs unpackaged.
        public static string PackageFullNameOf(int processId, out int error)
        {
            error = 0;
            IntPtr handle = OpenProcess(ProcessQueryLimitedInformation, false, (uint)processId);
            if (handle == IntPtr.Zero)
            {
                error = Marshal.GetLastWin32Error();
                return null;
            }
            try
            {
                uint length = 0;
                int rc = GetPackageFullName(handle, ref length, null);
                if (rc != ErrorInsufficientBuffer)
                {
                    error = rc;
                    return null;
                }
                StringBuilder name = new StringBuilder((int)length);
                rc = GetPackageFullName(handle, ref length, name);
                if (rc != 0)
                {
                    error = rc;
                    return null;
                }
                return name.ToString();
            }
            finally
            {
                CloseHandle(handle);
            }
        }

        public static string CurrentPackageFullName(out int error)
        {
            error = 0;
            uint length = 0;
            int rc = GetCurrentPackageFullName(ref length, null);
            if (rc != ErrorInsufficientBuffer)
            {
                error = rc;
                return null;
            }
            StringBuilder name = new StringBuilder((int)length);
            rc = GetCurrentPackageFullName(ref length, name);
            if (rc != 0)
            {
                error = rc;
                return null;
            }
            return name.ToString();
        }

        // IApplicationActivationManager::ActivateApplication. Returns the HRESULT.
        public static int Activate(string appUserModelId, string arguments, int options, out uint processId)
        {
            IApplicationActivationManager manager = (IApplicationActivationManager)new ApplicationActivationManager();
            try
            {
                return manager.ActivateApplication(appUserModelId, arguments, options, out processId);
            }
            finally
            {
                Marshal.ReleaseComObject(manager);
            }
        }
    }
}
'@

function Initialize-WtLiveNative {
    # Compiles the native helpers once per process.
    [CmdletBinding()]
    param()
    if (-not ('WtLive.Native' -as [type])) {
        Add-Type -TypeDefinition $script:WtLiveNativeSource -Language CSharp -ErrorAction Stop
    }
}

function Get-ProcessPackageName {
    # { Name; Error } for a process: its package full name, or the Win32 error
    # that came back instead (15700: no package identity).
    param([Parameter(Mandatory)][int]$ProcessId)
    try {
        Initialize-WtLiveNative
        $err = 0
        $name = [WtLive.Native]::PackageFullNameOf($ProcessId, [ref]$err)
        return [pscustomobject]@{ Name = $name; Error = $err }
    } catch {
        return [pscustomobject]@{ Name = $null; Error = "$($_.Exception.Message)" }
    }
}

function Get-CurrentPackageName {
    # { Name; Error } for this process, as Get-ProcessPackageName.
    try {
        Initialize-WtLiveNative
        $err = 0
        $name = [WtLive.Native]::CurrentPackageFullName([ref]$err)
        return [pscustomobject]@{ Name = $name; Error = $err }
    } catch {
        return [pscustomobject]@{ Name = $null; Error = "$($_.Exception.Message)" }
    }
}

function Save-DesktopScreenshot {
    # A PNG of the whole desktop. Returns $null when it was written, or why not.
    # Best effort: evidence, never a verdict.
    param([Parameter(Mandatory)][string]$Path)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
            } finally { $graphics.Dispose() }
            $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
        return $null
    } catch {
        return "no screenshot: $($_.Exception.Message)"
    }
}
