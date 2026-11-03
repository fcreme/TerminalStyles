# Pester 5 tests for tuned-style background inheritance: a style whose
# tune.json names a base with no background of its own resolves the base's.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-StyleBundledBackground inheritance' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = Join-Path $TestDrive 'module'
            $script:TStylesDataRoot   = Join-Path $TestDrive 'data'
            # Bundled base 'eva' with a scheme.json (so Get-StyleDir resolves it)
            # and a background.gif.
            $evaDir = Join-Path $script:TStylesModuleRoot 'styles\eva'
            New-Item -ItemType Directory -Path $evaDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $evaDir 'scheme.json'), '{"name":"eva"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $evaDir 'background.gif'), 'GIFDATA', [System.Text.UTF8Encoding]::new($false))
            # Tuned 'eva-night' in the user dir: scheme + tune.json (base=eva), no bg.
            $script:nightDir = Join-Path $script:TStylesDataRoot 'styles\eva-night'
            New-Item -ItemType Directory -Path $script:nightDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'scheme.json'), '{"name":"eva-night"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:nightDir 'tune.json'), '{"base":"eva"}', [System.Text.UTF8Encoding]::new($false))
        }

        It 'resolves the base background for a tuned style with none of its own' {
            $bg = Get-StyleBundledBackground -StyleDir $script:nightDir
            $bg | Should -Match 'styles[\\/]eva[\\/]background\.gif$'
        }

        It 'reports a tuned style as resolved when its base is resolved' {
            Test-StyleResolved -StyleDir $script:nightDir | Should -BeTrue
        }

        It 'does not infinitely recurse on a cyclic tune.json (A->B->A)' {
            # A.tune base=B, B.tune base=A. B gets a .no-background cache marker
            # so the base lookup terminates without a network call. Without the
            # -NoInherit one-hop guard this would stack-overflow.
            $aDir = Join-Path $script:TStylesDataRoot 'styles\cyc-a'
            $bDir = Join-Path $script:TStylesDataRoot 'styles\cyc-b'
            New-Item -ItemType Directory -Path $aDir -Force | Out-Null
            New-Item -ItemType Directory -Path $bDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $aDir 'scheme.json'), '{"name":"cyc-a"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $aDir 'tune.json'),   '{"base":"cyc-b"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $bDir 'scheme.json'), '{"name":"cyc-b"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $bDir 'tune.json'),   '{"base":"cyc-a"}', [System.Text.UTF8Encoding]::new($false))
            # .no-background marker for cyc-b so the one-hop base lookup returns fast.
            $bCache = Join-Path $script:TStylesDataRoot 'cache\cyc-b'
            New-Item -ItemType Directory -Path $bCache -Force | Out-Null
            # Dated, so it does not read as expired and trigger a real fetch.
            [System.IO.File]::WriteAllText((Join-Path $bCache '.no-background'),
                ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false))

            # Both must terminate (return a value, not hang/overflow).
            Get-TunedBaseBackground -StyleDir $aDir | Should -BeNullOrEmpty
            Test-StyleResolved -StyleDir $aDir | Should -BeTrue   # inherits cyc-b's resolved (.no-background) state
        }

        It 'Get-TunedBaseBackground returns null for tune.json with no base field' {
            $d = Join-Path $script:TStylesDataRoot 'styles\nobase'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'), '{}', [System.Text.UTF8Encoding]::new($false))
            Get-TunedBaseBackground -StyleDir $d | Should -BeNullOrEmpty
        }

        It 'Get-TunedBaseBackground returns null for malformed tune.json' {
            $d = Join-Path $script:TStylesDataRoot 'styles\bad'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'), 'NOT JSON {', [System.Text.UTF8Encoding]::new($false))
            Get-TunedBaseBackground -StyleDir $d | Should -BeNullOrEmpty
        }

        It 'Get-TunedBaseBackground returns null when the base style does not resolve' {
            $d = Join-Path $script:TStylesDataRoot 'styles\orphan'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'), '{"base":"does-not-exist"}', [System.Text.UTF8Encoding]::new($false))
            Get-TunedBaseBackground -StyleDir $d | Should -BeNullOrEmpty
        }

        It 'Test-StyleResolved is false for a tuned style whose base does not resolve' {
            $d = Join-Path $script:TStylesDataRoot 'styles\orphan2'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), '{"name":"orphan2"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $d 'tune.json'), '{"base":"does-not-exist"}', [System.Text.UTF8Encoding]::new($false))
            Test-StyleResolved -StyleDir $d | Should -BeFalse
        }
    }
}

Describe 'a tuned style asks its base before any cache keyed by its own name' {
    # The cache and the gifs branch are keyed by NAME. The resolver checked
    # cache/<the style's name> before the tune.json hop, so a tune of forest
    # saved as 'eva' painted eva's cached wallpaper -- or downloaded it -- while
    # the tuner's preview had shown forest's, and the wiki says a tuned style
    # inherits the base theme's background.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedModule = $script:TStylesModuleRoot
            $script:savedData   = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesModuleRoot = Join-Path $sand 'module'
            $script:TStylesDataRoot   = Join-Path $sand 'data'
            $enc = [System.Text.UTF8Encoding]::new($false)
            foreach ($n in 'eva', 'forest') {
                $d = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $n
                [void][System.IO.Directory]::CreateDirectory($d)
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), ('{"name":"' + $n + '"}'), $enc)
            }
            $script:evaCache    = Get-StyleCacheDir -StyleName 'eva'
            $script:forestCache = Get-StyleCacheDir -StyleName 'forest'
            [void][System.IO.Directory]::CreateDirectory($script:evaCache)
            [void][System.IO.Directory]::CreateDirectory($script:forestCache)
            [System.IO.File]::WriteAllText((Join-Path $script:evaCache 'background.gif'), 'EVA-WALLPAPER', $enc)
            [System.IO.File]::WriteAllText((Join-Path $script:forestCache 'background.gif'), 'FOREST-WALLPAPER', $enc)
            # A tune of forest, saved under the name 'eva'.
            $script:tuned = Join-Path (Join-Path $script:TStylesDataRoot 'styles') 'eva'
            [void][System.IO.Directory]::CreateDirectory($script:tuned)
            [System.IO.File]::WriteAllText((Join-Path $script:tuned 'scheme.json'), '{"name":"eva"}', $enc)
            [System.IO.File]::WriteAllText((Join-Path $script:tuned 'tune.json'), '{"schemaVersion":1,"base":"forest"}', $enc)
            $script:absent = { param($Dir)
                [System.IO.File]::WriteAllText((Join-Path $Dir '.no-background'),
                    ([pscustomobject]@{ schemaVersion = 1; kind = 'absent'; at = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress), $enc)
            }
            Mock Update-CachedBackground { $CachePath }
            Mock Invoke-WebRequest { throw 'network reached' }
        }
        AfterEach {
            $script:TStylesModuleRoot = $script:savedModule
            $script:TStylesDataRoot   = $script:savedData
        }

        It "paints its base's image, not the one cached under its name" {
            [System.IO.File]::ReadAllText((Get-StyleBundledBackground -StyleDir $script:tuned)) | Should -BeExactly 'FOREST-WALLPAPER'
            [System.IO.File]::ReadAllText((Get-StyleBundledBackground -StyleDir $script:tuned -NoFetch)) | Should -BeExactly 'FOREST-WALLPAPER'
            Should -Invoke Update-CachedBackground -Times 1 -Exactly -ParameterFilter { $StyleName -eq 'forest' }
            Should -Invoke Update-CachedBackground -Times 0 -Exactly -ParameterFilter { $StyleName -eq 'eva' }
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It "takes the base's answer as final when the base has no image" {
            [System.IO.File]::Delete((Join-Path $script:forestCache 'background.gif'))
            & $script:absent $script:forestCache
            Get-StyleBundledBackground -StyleDir $script:tuned | Should -BeNullOrEmpty -Because "eva's cached image is not this style's"

            [System.IO.File]::Delete((Join-Path $script:evaCache 'background.gif'))
            Get-StyleBundledBackground -StyleDir $script:tuned | Should -BeNullOrEmpty -Because 'nor is a download of gifs/eva'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Test-StyleResolved: a tuned style is resolved exactly when its base is' {
            [System.IO.File]::Delete((Join-Path $script:forestCache 'background.gif'))
            Test-StyleResolved -StyleDir $script:tuned | Should -BeFalse
            [System.IO.File]::WriteAllText((Join-Path $script:forestCache 'background.gif'), 'FOREST-WALLPAPER')
            Test-StyleResolved -StyleDir $script:tuned | Should -BeTrue
        }
    }
}
