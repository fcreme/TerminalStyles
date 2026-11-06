# Pester 5 tests for Save-CreatedStyle / New-CreatedThemeObject (tstyles create).
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Save-CreatedStyle' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
            $script:img = Join-Path $TestDrive 'src.png'
            [System.IO.File]::WriteAllBytes($script:img, [byte[]](137, 80, 78, 71, 0, 1, 2, 255, 254))
            $script:scheme = [pscustomobject]@{ name = 'x'; background = '#101010'; foreground = '#eeeeee' }
            $script:theme  = New-CreatedThemeObject -Name 'mine' -FontFace 'Cascadia Code' -FontSize 11 `
                -CursorShape 'bar' -ImageOpacity 0.5 -StretchMode 'uniformToFill' -Alignment 'center' -TabColor '#112233'
            $script:prompt = @{ Profile = "# profile`r`n"; Shell = "line1`r`nline2`n" }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'saves exactly the six files and the style is discoverable' {
            $r = Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt -Description 'd'
            $r.Status | Should -Be 'saved'
            $dir = Join-Path $script:TStylesDataRoot 'styles\mine'
            $r.Path | Should -Be $dir
            (Get-ChildItem -LiteralPath $dir -Force).Name | Sort-Object |
                Should -Be @('background.png', 'meta.json', 'profile.ps1', 'prompt.sh', 'scheme.json', 'theme.json')
            Get-StyleDir -StyleName 'mine' | Should -Be $dir
            (Get-AvailableStyles).Name | Should -Contain 'mine'
            [System.IO.File]::ReadAllBytes((Join-Path $dir 'background.png')) |
                Should -Be ([System.IO.File]::ReadAllBytes($script:img))
            (Get-Content -Raw -LiteralPath (Join-Path $dir 'scheme.json') | ConvertFrom-Json).name | Should -Be 'mine'
            $sh = [System.IO.File]::ReadAllBytes((Join-Path $dir 'prompt.sh'))
            $sh | Should -Not -Contain 13
            $sh[0] | Should -Not -Be 239
            [System.IO.File]::ReadAllText((Join-Path $dir 'profile.ps1')) | Should -Be "# profile`r`n"
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.creating') | Should -BeFalse

            # Contents, not just existence.
            $eva = (Get-Content -Raw -LiteralPath (Join-Path $script:TStylesModuleRoot 'styles\eva\theme.json') | ConvertFrom-Json).PSObject.Properties.Name
            $th = Get-Content -Raw -LiteralPath (Join-Path $dir 'theme.json') | ConvertFrom-Json
            $th.backgroundImage | Should -Be '{{BACKGROUND_IMAGE}}'
            ($th.PSObject.Properties.Name | Sort-Object) | Should -Be ($eva | Sort-Object)
            ($script:theme.PSObject.Properties.Name | Sort-Object) | Should -Be ($eva | Sort-Object)
            $sc = Get-Content -Raw -LiteralPath (Join-Path $dir 'scheme.json') | ConvertFrom-Json
            $sc.background | Should -Be '#101010'
            $sc.foreground | Should -Be '#eeeeee'
            (Get-Content -Raw -LiteralPath (Join-Path $dir 'meta.json') | ConvertFrom-Json).description | Should -Be 'd'
            [System.IO.File]::ReadAllBytes((Join-Path $dir 'prompt.sh')) |
                Should -Be ([System.Text.UTF8Encoding]::new($false).GetBytes("line1`nline2`n"))
            [System.IO.File]::ReadAllBytes((Join-Path $dir 'profile.ps1')) |
                Should -Be ([System.Text.UTF8Encoding]::new($false).GetBytes("# profile`r`n"))
        }

        It 'writes all 21 scheme keys with the input values' {
            $keys = 'background','foreground','cursorColor','selectionBackground','black','red','green','yellow','blue','purple','cyan','white','brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite'
            $o = [ordered]@{ name = 'orig' }
            $i = 0
            foreach ($k in $keys) { $o[$k] = ('#{0:x2}{0:x2}{0:x2}' -f (10 + $i)); $i++ }
            $sch = [pscustomobject]$o
            (Save-CreatedStyle -Name 'mine' -Scheme $sch -Theme $script:theme -BackgroundPath $script:img -Prompt $script:prompt).Status | Should -Be 'saved'
            $back = Get-Content -Raw -LiteralPath (Join-Path $script:TStylesDataRoot 'styles\mine\scheme.json') | ConvertFrom-Json
            @($back.PSObject.Properties).Count | Should -Be 21
            foreach ($k in $keys) { $back.$k | Should -Be $sch.$k }
            $back.name | Should -Be 'mine'
            $sch.name | Should -Be 'orig'
        }

        It 'keeps the lower-cased extension of an upper-case source' {
            $up = Join-Path $TestDrive 'UPPER.PNG'
            Copy-Item -LiteralPath $script:img -Destination $up
            (Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme -BackgroundPath $up -Prompt $script:prompt).Status | Should -Be 'saved'
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'styles\mine\background.png') | Should -BeTrue
        }

        It 'returns invalid for an unsupported background type (<f>)' -ForEach @(@{ f = 'x.webp' }, @{ f = 'x.bmp' }, @{ f = 'noext' }) {
            $p = Join-Path $TestDrive $f
            Copy-Item -LiteralPath $script:img -Destination $p
            $r = Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme -BackgroundPath $p -Prompt $script:prompt
            $r.Status | Should -Be 'invalid'
            $r.Reason | Should -Match 'gif.*png.*jpg.*jpeg'
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'styles') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.creating') | Should -BeFalse
        }

        It 'refuses a taken user name and leaves the folder unchanged' {
            $dir = Join-Path $script:TStylesDataRoot 'styles\mine'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), '{"name":"mine"}')
            $before = [System.IO.File]::ReadAllBytes((Join-Path $dir 'scheme.json'))
            $r = Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt
            $r.Status | Should -Be 'taken'
            [System.IO.File]::ReadAllBytes((Join-Path $dir 'scheme.json')) | Should -Be $before
            @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 1
        }

        It 'refuses a bundled name and writes nothing under the data root' {
            $r = Save-CreatedStyle -Name 'sober' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt
            $r.Status | Should -Be 'taken'
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'styles\sober') | Should -BeFalse
        }

        It 'returns invalid for <n>' -ForEach @(@{ n = '..' }, @{ n = 'a b' }) {
            (Save-CreatedStyle -Name $n -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt).Status | Should -Be 'invalid'
        }

        # Pending until Task 7 adds 'create' to the subcommands (Test-StyleNameValid then rejects it).
        It 'returns invalid for the reserved name create' -Skip {
            (Save-CreatedStyle -Name 'create' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt).Status | Should -Be 'invalid'
        }

        It 'fails cleanly when the image cannot be copied' {
            Mock Copy-Item { throw 'source vanished' }
            $r = Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Match 'vanished'
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot 'styles\mine') | Should -BeFalse
            $left = @(Get-ChildItem -LiteralPath $script:TStylesDataRoot -Recurse -Force -Filter '.creating*')
            $left.Count | Should -Be 0
        }

        It 'fails cleanly when the image is really gone' {
            Remove-Item -LiteralPath $script:img
            $r = Save-CreatedStyle -Name 'mine' -Scheme $script:scheme -Theme $script:theme `
                -BackgroundPath $script:img -Prompt $script:prompt
            $r.Status | Should -Be 'failed'
            (Get-AvailableStyles).Name | Should -Not -Contain 'mine'
            Test-Path -LiteralPath (Join-Path $script:TStylesDataRoot '.creating') | Should -BeFalse
        }

        It 'builds a theme with the upper-cased tab title and the placeholder' {
            $t = New-CreatedThemeObject -Name 'my-style' -FontFace 'F' -FontSize 12 -CursorShape 'bar' `
                -ImageOpacity 0.4 -StretchMode 'fill' -Alignment 'top' -TabColor '#abcdef'
            $t.tabTitle | Should -Be 'MY-STYLE'
            $t.colorScheme | Should -Be 'my-style'
            $t.backgroundImage | Should -Be '{{BACKGROUND_IMAGE}}'
            $t.backgroundImageOpacity | Should -Be 0.4
        }
    }
}
