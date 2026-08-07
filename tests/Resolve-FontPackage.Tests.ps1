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
