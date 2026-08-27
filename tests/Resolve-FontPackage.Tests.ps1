#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Resolve-FontPackage' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Build a tiny zip fixture containing a fake font file.
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $script:srcDir = Join-Path $TestDrive 'src'
            New-Item -ItemType Directory -Path (Join-Path $script:srcDir 'ttf') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:srcDir 'ttf\Fake-Regular.ttf'), 'FAKEFONTBYTES')
            $script:zip = Join-Path $TestDrive 'pkg.zip'
            if (Test-Path $script:zip) { Remove-Item $script:zip -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($script:srcDir, $script:zip)
            $script:zipHash = (Get-FileHash -Path $script:zip -Algorithm SHA256).Hash.ToLowerInvariant()
            $script:cache = Join-Path $TestDrive 'cache'
        }

        It 'verifies the hash and extracts the listed files' {
            $font = [pscustomobject]@{ name='Fake'; url='https://x/pkg.zip'; sha256=$script:zipHash; files=@('ttf/Fake-Regular.ttf') }
            $out = Resolve-FontPackage -Font $font -CacheRoot $script:cache -DownloadPath $script:zip
            @($out).Count | Should -Be 1
            Test-Path -LiteralPath $out[0] | Should -BeTrue
            (Split-Path -Leaf $out[0]) | Should -Be 'Fake-Regular.ttf'
        }

        It 'throws on a SHA-256 mismatch' {
            $font = [pscustomobject]@{ name='Fake'; url='https://x/pkg.zip'; sha256='deadbeef'; files=@('ttf/Fake-Regular.ttf') }
            { Resolve-FontPackage -Font $font -CacheRoot $script:cache -DownloadPath $script:zip } | Should -Throw
        }

        It 'extracts NOTHING when the hash does not match' {
            # Should -Throw above says the call failed; it says nothing about
            # what was left on disk. This function's own contract is "never
            # leaves a partially-installed state", and the ordering that makes
            # it true -- hash gate BEFORE the extract directory is created -- is
            # a two-line move away from being false while every existing
            # assertion still passes.
            # A cache root of its own. TestDrive is NOT reset between It blocks,
            # so sharing $script:cache would find the previous test's extract
            # directory and fail on that instead -- which is exactly what the
            # first draft of this test did.
            $freshCache = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $font = [pscustomobject]@{ name='Fake'; url='https://x/pkg.zip'; sha256='deadbeef'; files=@('ttf/Fake-Regular.ttf') }
            { Resolve-FontPackage -Font $font -CacheRoot $freshCache -DownloadPath $script:zip } | Should -Throw

            $extractDir = Join-Path (Join-Path $freshCache 'Fake') 'files'
            Test-Path -LiteralPath $extractDir | Should -BeFalse `
                -Because 'a refused download must not even create the directory it would have unpacked into'
            @(Get-ChildItem -LiteralPath $freshCache -Recurse -Filter '*.ttf' -ErrorAction SilentlyContinue).Count |
                Should -Be 0
        }

        It 'cannot be made to write outside the extract directory' {
            # Zip slip. The archive is fetched over the network from a URL in
            # fonts.json, so its entry NAMES are not something this code gets to
            # trust -- only its hash is pinned. The defence is that the
            # destination is built from Split-Path -Leaf, so '../../evil.ttf'
            # lands as 'evil.ttf' inside the extract dir. That is one edit away
            # from being an arbitrary-write primitive.
            $slipSrc = Join-Path $TestDrive 'slip'
            New-Item -ItemType Directory -Path $slipSrc -Force | Out-Null
            $slipZip = Join-Path $TestDrive 'slip.zip'
            if (Test-Path $slipZip) { Remove-Item $slipZip -Force }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $fs = [System.IO.File]::Open($slipZip, 'Create')
            try {
                $z = New-Object System.IO.Compression.ZipArchive($fs, 'Create')
                try {
                    $e = $z.CreateEntry('../../../evil.ttf')
                    $w = New-Object System.IO.StreamWriter($e.Open())
                    $w.Write('PWNED'); $w.Dispose()
                } finally { $z.Dispose() }
            } finally { $fs.Dispose() }

            $hash = (Get-FileHash -Path $slipZip -Algorithm SHA256).Hash.ToLowerInvariant()
            $font = [pscustomobject]@{ name='Slip'; url='https://x/slip.zip'; sha256=$hash
                                       files=@('../../../evil.ttf') }
            $out = Resolve-FontPackage -Font $font -CacheRoot $script:cache -DownloadPath $slipZip

            $extractDir = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $script:cache 'Slip') 'files'))
            foreach ($f in @($out)) {
                [System.IO.Path]::GetFullPath($f) | Should -BeLike "$extractDir*" `
                    -Because 'every extracted path must stay under the extract directory'
            }
            Test-Path -LiteralPath (Join-Path $TestDrive 'evil.ttf') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:cache 'evil.ttf') | Should -BeFalse
        }

        It 'throws when a listed file is absent from the archive' {
            $font = [pscustomobject]@{ name='Fake'; url='https://x/pkg.zip'; sha256=$script:zipHash; files=@('ttf/Missing.ttf') }
            { Resolve-FontPackage -Font $font -CacheRoot $script:cache -DownloadPath $script:zip } | Should -Throw
        }

        It 'passes through a direct .ttf download (no files list)' {
            $ttf = Join-Path $TestDrive 'Direct-Regular.ttf'
            [System.IO.File]::WriteAllText($ttf, 'DIRECTFONT')
            $h = (Get-FileHash -Path $ttf -Algorithm SHA256).Hash.ToLowerInvariant()
            $font = [pscustomobject]@{ name='Direct'; url='https://x/Direct-Regular.ttf'; sha256=$h; files=@() }
            $out = Resolve-FontPackage -Font $font -CacheRoot (Join-Path $TestDrive 'cache2') -DownloadPath $ttf
            @($out).Count | Should -Be 1
            (Split-Path -Leaf $out[0]) | Should -Be 'Direct-Regular.ttf'
        }
    }
}
