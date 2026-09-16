# Pester 5 tests: a tuned style keeps its ancestry when its base drifts, and the
# tuner's font knobs survive an odd base theme.json.
#
# LINEAGE. A tuned style stores DELTAS against a base, so when that base changes
# the deltas stop meaning what they meant -- 0.8.18 added a fingerprint check
# that drops them rather than double-applying. But dropping the deltas also
# dropped the ANCESTRY: the seed left BaseName at the style itself, so the next
# save wrote `"base": "<the style>"` into tune.json, Get-TunedBaseBackground's
# one-hop self-reference guard returned $null, and the style lost its background
# for good. Bundled styles ship no image beside them -- the GIF lives in the
# data-root cache under the BASE's name -- so inheritance was the only route to
# it. The next apply then took Merge-StyleIntoSettings' bgAction='remove' and
# stripped every background field off the profile, silently, with no way back:
# `base` was self, so every future re-tune rewrote the same self-reference.
#
# Where the colours are MEASURED from and what the style DESCENDS from are two
# questions. They coincide until the base drifts, and then they must not.
#
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

Describe 'a drifted base does not cost the style its ancestry' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:savedData   = $script:TStylesDataRoot
            $script:savedModule = $script:TStylesModuleRoot
            $script:TStylesDataRoot   = $script:root
            $script:TStylesModuleRoot = $script:root

            $script:styles = Join-Path $script:root 'styles'
            $script:evaDir = Join-Path $script:styles 'eva'
            New-Item -ItemType Directory -Path $script:evaDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                '{"name":"eva","background":"#0a0006","foreground":"#ffe8e8"}')
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'theme.json'),
                '{"colorScheme":"eva","backgroundImage":"{{BACKGROUND_IMAGE}}"}')

            # The base's background lives in the data-root cache, as it does in a
            # real install -- NOT beside the style.
            $cache = Join-Path (Join-Path $script:root 'cache') 'eva'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $cache 'background.gif'),
                [byte[]](0x47,0x49,0x46,0x38,0x39,0x61))

            # eva-night, tuned from eva.
            $adj = Get-AdjustedScheme -Brightness -35 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $script:evaDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $script:evaDir -BaseName 'eva' `
                -Brightness -35 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null
            $script:nightDir = Join-Path $script:styles 'eva-night'
        }
        AfterEach {
            $script:TStylesDataRoot   = $script:savedData
            $script:TStylesModuleRoot = $script:savedModule
        }

        It 'inherits the base background before anything drifts' {
            Get-TunedBaseBackground -StyleDir $script:nightDir | Should -Not -BeNullOrEmpty
        }

        It 'keeps base and background after the base drifts and the style is saved again' {
            # eva itself is re-baked, exactly as an Overwrite save or an update does.
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                '{"name":"eva","background":"#1a1016","foreground":"#ffe8e8"}')

            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $seed.BaseChanged | Should -BeTrue -Because 'the fingerprint must notice the base moved'
            $seed.LineageBase | Should -Be 'eva' -Because 'dropping the deltas must not drop the ancestry'

            # What the tuner does when the user saves from that state.
            $ln  = if ($seed.LineageBase)    { $seed.LineageBase }    else { $seed.BaseName }
            $lnd = if ($seed.LineageBaseDir) { $seed.LineageBaseDir } else { $seed.BaseDir }
            $adj = Get-AdjustedScheme -Brightness 0 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $script:nightDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $seed.BaseDir -BaseName $seed.BaseName `
                -LineageBase $ln -LineageBaseDir $lnd `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null

            $written = [System.IO.File]::ReadAllText((Join-Path $script:nightDir 'tune.json')) | ConvertFrom-Json
            $written.base | Should -Be 'eva' -Because 'the style must not become its own base'
            Get-TunedBaseBackground -StyleDir $script:nightDir | Should -Not -BeNullOrEmpty `
                -Because 'the cached background lives under the BASE name; self-reference severs it for good'
        }

        It 'says so when the base is GONE, and keeps the name so it can come back' {
            # "The base changed" and "the base is gone" were folded together by
            # `$baseIsSelf = (-not $resolvedBaseDir) -or ...`, so deleting a base
            # dropped the child's deltas in COMPLETE silence: BaseChanged stayed
            # false, ChangedBaseName stayed empty, and the tuner opened on
            # neutral knobs as though the style had never been tuned. Measured
            # before the fix: brightness -35 / saturation 10 became 0 / 0 with no
            # notice, and the next save wrote base = self, severing the
            # background inheritance permanently.
            #
            # A base can go the ordinary way -- README invites hand-authored
            # styles in this directory, so a folder can simply be removed.
            $before = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $before.Brightness | Should -Be -35 -Because 'the deltas are recorded while the base exists'

            Remove-Item -LiteralPath $script:evaDir -Recurse -Force

            $after = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $after.BaseMissing     | Should -BeTrue  -Because 'gone is not the same as unchanged'
            $after.BaseChanged     | Should -BeTrue  -Because 'the user must be told the knobs were reset'
            $after.ChangedBaseName | Should -Be 'eva' -Because 'the notice has to name the base that vanished'
            $after.LineageBase     | Should -Be 'eva' `
                -Because 'recording the style as its own base would make a returning base unrecoverable'
        }

        It 'does not call a restored base changed after a save taken while it was gone' {
            # The twin of the drift test below, for the half that had none. The
            # missing-base test above stops at Resolve-TuneSeed and never saves,
            # which is exactly why this survived.
            #
            # A save taken while the base is GONE falls back to the style itself
            # as the lineage base dir, so Save-TunedStyle records the style's OWN
            # fingerprint as the base's. Restore the base -- byte-identically, on
            # the tuner's own advice -- and the next open compared the base
            # against the child's hash, found them different, and said "'eva' has
            # changed since this style was tuned" about a file that had not
            # changed at all.
            #
            # BOTH assertions matter, and they must stay together: the first is
            # the defect, the second is the guard that rejects the obvious fix.
            # Recording $null (or the base's real hash) instead makes
            # Test-TuneBaseMoved answer false, so the restored base becomes the
            # colour source again and the recorded delta is re-applied ON TOP of
            # it -- measured at the time as a preview of #040404 against a style
            # whose scheme.json says #000000, with the earlier adjustment lost on
            # the next save.
            $realFp = Get-StyleSchemeFingerprint -StyleDir $script:evaDir
            $parked = Join-Path $TestDrive ('parked-' + [guid]::NewGuid().ToString('n'))
            Move-Item -LiteralPath $script:evaDir -Destination $parked

            $gone = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $gone.BaseMissing | Should -BeTrue -Because 'the base really is unresolvable here'

            # The tuner's own fallback, verbatim, and the save it makes from it.
            $ln  = if ($gone.LineageBase)    { $gone.LineageBase }    else { $gone.BaseName }
            $lnd = if ($gone.LineageBaseDir) { $gone.LineageBaseDir } else { $gone.BaseDir }
            $adj = Get-AdjustedScheme -Brightness -10 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $script:nightDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $gone.BaseDir -BaseName $gone.BaseName `
                -LineageBase $ln -LineageBaseDir $lnd -OpenedStyleDir $script:nightDir `
                -Brightness -10 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null

            # Restored exactly as it was, which is what the notice told the user
            # to do ("Restore that style to get them back").
            Move-Item -LiteralPath $parked -Destination $script:evaDir
            (Get-StyleSchemeFingerprint -StyleDir $script:evaDir) | Should -Be $realFp `
                -Because 'this test is about a base that did NOT change'

            $after = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir

            # 1. the defect: what the tuner SAYS about the restored base.
            @(Get-TuneSeedNotice -Seed $after | ForEach-Object { $_.Text }) -join ' ' |
                Should -Not -Match 'has changed since this style was tuned' `
                -Because 'eva is byte-identical to the copy this style was saved against'
            $after.BaseColoursBaked | Should -BeTrue `
                -Because 'the recorded fingerprint is this style''s own, which only a base-missing save produces'

            # 2. the guard: what it DOES must not change. Colours from the style
            # itself, knobs neutral, lineage kept.
            $after.Brightness | Should -Be 0
            $after.Saturation | Should -Be 0
            $after.LineageBase | Should -Be 'eva'
            $onDisk = ([System.IO.File]::ReadAllText((Join-Path $script:nightDir 'scheme.json')) |
                       ConvertFrom-Json).background
            $preview = Get-AdjustedScheme -Brightness $after.Brightness -Saturation $after.Saturation -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $after.BaseDir 'scheme.json')) | ConvertFrom-Json)
            $preview.background | Should -Be $onDisk `
                -Because 'the tuner must open on the colours the style actually has'
        }

        It 'stops saying it once the style is saved from the restored base' {
            # Self-healing, and the reason the recorded self-hash can stay: the
            # drift branch records BOTH lineage fields, so one save re-links the
            # style to the base and the state is gone for good.
            $parked = Join-Path $TestDrive ('parked2-' + [guid]::NewGuid().ToString('n'))
            Move-Item -LiteralPath $script:evaDir -Destination $parked
            $gone = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $adj = Get-AdjustedScheme -Brightness -10 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $script:nightDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $gone.BaseDir -BaseName $gone.BaseName `
                -LineageBase $gone.LineageBase -LineageBaseDir $gone.LineageBaseDir `
                -OpenedStyleDir $script:nightDir `
                -Brightness -10 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null
            Move-Item -LiteralPath $parked -Destination $script:evaDir

            $baked = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $baked.BaseColoursBaked | Should -BeTrue
            $adj2 = Get-AdjustedScheme -Brightness 0 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $baked.BaseDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj2 -SaveName 'eva-night' `
                -BaseStyleDir $baked.BaseDir -BaseName $baked.BaseName `
                -LineageBase $baked.LineageBase -LineageBaseDir $baked.LineageBaseDir `
                -OpenedStyleDir $script:nightDir `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null

            $healed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir
            $healed.BaseChanged      | Should -BeFalse
            $healed.BaseColoursBaked | Should -BeFalse
            (([System.IO.File]::ReadAllText((Join-Path $script:nightDir 'tune.json')) |
              ConvertFrom-Json).baseFingerprint) |
                Should -Be (Get-StyleSchemeFingerprint -StyleDir $script:evaDir) `
                -Because 'the save from the restored base records the base''s own hash again'
        }

        It 'does not report drift for ever after saving through it' {
            [System.IO.File]::WriteAllText((Join-Path $script:evaDir 'scheme.json'),
                '{"name":"eva","background":"#1a1016","foreground":"#ffe8e8"}')
            $seed = Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir

            $adj = Get-AdjustedScheme -Brightness 0 -Scheme (
                [System.IO.File]::ReadAllText((Join-Path $script:nightDir 'scheme.json')) | ConvertFrom-Json)
            Save-TunedStyle -AdjustedScheme $adj -SaveName 'eva-night' `
                -BaseStyleDir $seed.BaseDir -BaseName $seed.BaseName `
                -LineageBase $seed.LineageBase -LineageBaseDir $seed.LineageBaseDir `
                -Brightness 0 -Saturation 0 -Opacity 100 -FontFace 'x' -FontSize 12 | Out-Null

            # The fingerprint must be the LINEAGE base's current one. Recording
            # the style's own would make every future open report drift again.
            (Resolve-TuneSeed -StyleName 'eva-night' -StyleDir $script:nightDir).BaseChanged |
                Should -BeFalse -Because 'saving through a drift resolves it, it does not make it permanent'
        }
    }
}

Describe 'the font knobs survive an odd base theme.json' {
    InModuleScope TerminalStyles {
        It 'carries face and size when the base font key is <case>' -ForEach @(
            @{ case = 'a string'; json = '{"colorScheme":"x","font":"Menlo"}' }
            @{ case = 'null';     json = '{"colorScheme":"x","font":null}' }
            @{ case = 'an array'; json = '{"colorScheme":"x","font":["a"]}' }
            @{ case = 'a number'; json = '{"colorScheme":"x","font":12}' }
            @{ case = 'absent';   json = '{"colorScheme":"x"}' }
        ) {
            # New-TunedThemeObject guards the OUTER parse -- a theme.json that is
            # empty or a bare scalar -- but took $theme.font unconditionally and
            # Add-Member'd face/size onto it. On a scalar those become ADAPTED
            # members that ConvertTo-Json does not serialise, so the saved style
            # kept the bogus value and carried neither font knob, while the tuner
            # reported success and had shown the chosen font on screen all along.
            # theme.json is documented as optional and hand-authorable, so these
            # shapes are things a user can legitimately write.
            $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'theme.json'), $json)

            $t = New-TunedThemeObject -BaseStyleDir $d -ColorScheme 'tuned' `
                    -Opacity 80 -FontFace 'JetBrains Mono' -FontSize 14
            $round = $t | ConvertTo-Json -Depth 6 | ConvertFrom-Json

            $round.font.face | Should -Be 'JetBrains Mono' -Because 'the user set a font face'
            $round.font.size | Should -Be 14               -Because 'the user set a font size'
        }

        It 'still preserves a valid font object the base already had' {
            $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'theme.json'),
                '{"colorScheme":"x","font":{"weight":"bold"}}')

            $round = New-TunedThemeObject -BaseStyleDir $d -ColorScheme 'tuned' `
                        -Opacity 80 -FontFace 'JetBrains Mono' -FontSize 14 |
                     ConvertTo-Json -Depth 6 | ConvertFrom-Json

            $round.font.weight | Should -Be 'bold' -Because 'the guard must not discard a good object'
            $round.font.face   | Should -Be 'JetBrains Mono'
        }
    }
}
