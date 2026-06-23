# Pester 5 tests for apply.ps1's Write-WTSettingsFile -- the settings.json
# serializer/writer for the standalone file-installer entry point.
#
# Regression guard: apply.ps1 previously serialized with ConvertTo-Json -Depth 32,
# which silently stringifies (corrupts) any settings.json subtree nested deeper
# than 32 -- with no warning at all on Windows PowerShell 5.1. The module's
# Write-SettingsFile was hardened to -Depth 100; apply.ps1 must match.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'apply.ps1 Write-WTSettingsFile' {
    BeforeAll {
        $script:applyPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'apply.ps1'
        # Dot-source for functions only -- do NOT run the installer.
        $TStylesApplyNoRun = $true
        . $script:applyPath
        $script:enc = [System.Text.UTF8Encoding]::new($false)
    }

    It 'round-trips a settings object nested deeper than 32 levels without corruption' {
        # ConvertTo-Json -Depth 32 stringifies subtrees past the limit. Build a
        # ~40-level object and require the deepest leaf to survive a write/read.
        $deep = [pscustomobject]@{ marker = 'LEAF' }
        for ($i = 0; $i -lt 40; $i++) { $deep = [pscustomobject]@{ child = $deep } }
        $root = [pscustomobject]@{ nested = $deep }

        $path = Join-Path $TestDrive 'settings.json'
        Write-WTSettingsFile -Path $path -Settings $root

        $reloaded = [System.IO.File]::ReadAllText($path, $script:enc) | ConvertFrom-Json
        $cursor = $reloaded.nested
        for ($i = 0; $i -lt 40; $i++) { $cursor = $cursor.child }
        $cursor.marker | Should -Be 'LEAF'
    }

    It 'writes UTF-8 without a BOM' {
        $path = Join-Path $TestDrive 'nobom.json'
        Write-WTSettingsFile -Path $path -Settings ([pscustomobject]@{ a = 1 })
        $bytes = [System.IO.File]::ReadAllBytes($path)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
            Should -BeFalse
    }

    It 'overwrites an existing file and leaves no leftover .tstmp temp file' {
        $path = Join-Path $TestDrive 'atomic.json'
        [System.IO.File]::WriteAllText($path, '{"old":true}', $script:enc)
        Write-WTSettingsFile -Path $path -Settings ([pscustomobject]@{ fresh = $true })

        $reloaded = [System.IO.File]::ReadAllText($path, $script:enc) | ConvertFrom-Json
        $reloaded.fresh | Should -BeTrue
        $reloaded.PSObject.Properties.Name | Should -Not -Contain 'old'
        (Test-Path -LiteralPath "$path.tstmp") | Should -BeFalse
    }

    It 'replaces an existing file atomically (swaps in a new file, never rewrites in place)' {
        # Regression: File.Replace's backupFileName arg must be a real null.
        # Passing $null makes PowerShell coerce it to '' -> Replace throws
        # "path is empty" -> the catch silently degrades to a non-atomic
        # in-place WriteAllText. Hard-link the destination's underlying file
        # before the write: an atomic Replace swaps in a brand-new file, so the
        # original file (still reachable through the hard link) keeps its OLD
        # bytes. A non-atomic in-place rewrite would write through the shared
        # file and the hard link would observe the NEW bytes instead.
        $path = Join-Path $TestDrive 'atomic-replace.json'
        $link = Join-Path $TestDrive 'atomic-replace.hardlink.json'
        [System.IO.File]::WriteAllText($path, '{"v":"OLD"}', $script:enc)
        New-Item -ItemType HardLink -Path $link -Target $path | Out-Null

        Write-WTSettingsFile -Path $path -Settings ([pscustomobject]@{ v = 'NEW' })

        ([System.IO.File]::ReadAllText($path, $script:enc) | ConvertFrom-Json).v | Should -Be 'NEW'
        ([System.IO.File]::ReadAllText($link, $script:enc) | ConvertFrom-Json).v | Should -Be 'OLD'
    }
}
