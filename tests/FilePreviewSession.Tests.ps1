# Pester 5 tests for lib/previewsession.ps1: a whole-file preview recorded on
# disk, so a closed picker's preview is put back by the next command, and a
# change made while the picker is open is never written over.
#
# The Windows Terminal picker, the tuner and the WezTerm picker kept their only
# undo in memory and wrote every preview, and Esc, without looking at the file.
# A closed tab left a preview nothing named, and the next command's rolling .bak
# copied it over the only copy of the user's file.
#
# Every fixture lives in $TestDrive; the data root is pointed there too.
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

Describe 'a Windows Terminal preview session' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:enc = [System.Text.UTF8Encoding]::new($false)
            $script:p = Join-Path $sand 'settings.json'
            $script:original = @(
                '{'
                '  // mine'
                '  "profiles": { "list": [ { "guid": "{a}", "name": "PowerShell", "colorScheme": "Campbell", "font": { "face": "Consolas", "size": 11 } } ] },'
                '  "schemes": [ { "name": "Campbell", "background": "#0C0C0C" } ]'
                '}'
            ) -join "`n"
            [System.IO.File]::WriteAllText($script:p, $script:original, $script:enc)

            foreach ($n in 'probe', 'probe2') {
                $d = Join-Path (Join-Path $sand 'styles') $n
                [void][System.IO.Directory]::CreateDirectory($d)
                [System.IO.File]::WriteAllText((Join-Path $d 'scheme.json'), ('{"name":"' + $n + '","background":"#101010","foreground":"#f0f0f0"}'), $script:enc)
                [System.IO.File]::WriteAllText((Join-Path $d 'theme.json'), ('{"colorScheme":"' + $n + '","opacity":85,"font":{"face":"Menlo"}}'), $script:enc)
                Set-Variable -Scope Script -Name $n -Value $d
            }
            Mock Get-StyleBundledBackground { $null }
            $script:previewOf = {
                param($Base, $Dir)
                Get-StylePreviewJson -OriginalJson $Base -StyleDir $Dir -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            }
            $script:paths = Get-FilePreviewRecordPath -Kind WindowsTerminal -Path $script:p
            $script:outsideEdit = {
                $o = [System.IO.File]::ReadAllText($script:p) | ConvertFrom-Json
                $o | Add-Member -NotePropertyName copyOnSelect -NotePropertyValue $true
                $o.profiles.list = @($o.profiles.list) + [pscustomobject]@{ guid = '{b}'; name = 'Added-By-WT-Settings-UI' }
                $ps = $o.profiles.list[0]
                $rev = [ordered]@{}
                $names = @($ps.PSObject.Properties | ForEach-Object { $_.Name })
                [array]::Reverse($names)
                foreach ($n in $names) { $rev[$n] = $ps.$n }
                $o.profiles.list[0] = [pscustomobject]$rev
                [System.IO.File]::WriteAllText($script:p, ($o | ConvertTo-Json -Depth 100), $script:enc)
            }
            $script:read = { [System.IO.File]::ReadAllText($script:p) | ConvertFrom-Json }
            $script:ps = { param($o) @($o.profiles.list | Where-Object { $_.name -eq 'PowerShell' })[0] }
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'records the preview and keeps a copy of the file before it writes the preview' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            $preview = & $script:previewOf $s.OriginalText $script:probe
            $script:seen = $null
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic {
                $script:seen = @{ Exists = [System.IO.File]::Exists($script:paths.Record)
                                  Written = @(([System.IO.File]::ReadAllText($script:paths.Record) | ConvertFrom-Json).written) }
                [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            } -ParameterFilter { $Path -eq $script:p }

            Write-FilePreview -Session $s -Text $preview | Should -Be 'written'

            $script:seen.Exists | Should -BeTrue -Because 'the record goes first'
            $script:seen.Written | Should -Contain (Get-FilePreviewTextHash -Text $preview)
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:paths.Original)) |
                Should -BeExactly ([Convert]::ToBase64String($script:enc.GetBytes($script:original)))
            [System.IO.File]::ReadAllText($script:p) | Should -BeExactly $preview
        }

        It 'writes nothing over a file that changed after its last write, and stays stopped' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            & $script:outsideEdit
            @((& $script:read).profiles.list | Where-Object { $_.name -eq 'Added-By-WT-Settings-UI' }).Count | Should -Be 1
            $bytes = [System.IO.File]::ReadAllBytes($script:p)

            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe2) | Should -Be 'changed'
            $s.Changed | Should -BeTrue
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'changed'
            ([System.IO.File]::ReadAllBytes($script:p) -join ',') | Should -BeExactly ($bytes -join ',')
        }

        It 'Esc puts back the bytes it found, BOM and comment included, and leaves no record' {
            [System.IO.File]::WriteAllText($script:p, $script:original, [System.Text.UTF8Encoding]::new($true))
            $orig = [System.IO.File]::ReadAllBytes($script:p)
            $orig[0] | Should -Be 0xEF -Because 'the fixture must carry a BOM'
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'

            (Restore-FilePreview -Session $s -End).Status | Should -Be 'restored'
            ([System.IO.File]::ReadAllBytes($script:p) -join ',') | Should -BeExactly ($orig -join ',')
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
            [System.IO.File]::Exists($script:paths.Original) | Should -BeFalse
            (Restore-FilePreview -Session $s -End).Status | Should -Be 'none'
        }

        It 'Esc with nothing previewed writes nothing' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker
            $t = [System.IO.File]::GetLastWriteTimeUtc($script:p)
            (Restore-FilePreview -Session $s -End).Status | Should -Be 'none'
            [System.IO.File]::GetLastWriteTimeUtc($script:p) | Should -Be $t
            [System.IO.Directory]::Exists($script:paths.Dir) | Should -BeFalse
        }

        It 'a missing session is nothing to do, not an error' {
            (Restore-FilePreview -Session $null -End).Status | Should -Be 'none'
            (Complete-FilePreview -Session $null).Status | Should -Be 'done'
        }

        It 'Esc after an outside edit takes the preview out and keeps the edit' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            & $script:outsideEdit

            $r = Restore-FilePreview -Session $s -End
            $r.Status | Should -Be 'merged'
            @($r.Kept).Count | Should -Be 0
            $o = & $script:read
            $o.copyOnSelect | Should -BeTrue
            @($o.profiles.list | Where-Object { $_.name -eq 'Added-By-WT-Settings-UI' }).Count | Should -Be 1
            $ps = & $script:ps $o
            $ps.colorScheme | Should -Be 'Campbell'
            $ps.font.face | Should -Be 'Consolas'
            @($ps.PSObject.Properties.Match('opacity')).Count | Should -Be 0
            (@($o.schemes | ForEach-Object { $_.name }) -join ',') | Should -Be 'Campbell'
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }

        It 'Esc leaves the file alone when another tstyles command took the session over' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            (Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $script:p).Status | Should -Be 'restored'
            Set-ProfileFont -SettingsPath $script:p -TargetName 'PowerShell' -Family 'Menlo' | Should -BeTrue

            (Restore-FilePreview -Session $s -End).Status | Should -Be 'left'
            (& $script:ps (& $script:read)).font.face | Should -Be 'Menlo'
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
            $bytes = [System.IO.File]::ReadAllBytes($script:p)
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'changed'
            ([System.IO.File]::ReadAllBytes($script:p) -join ',') | Should -BeExactly ($bytes -join ',')
        }

        It 'Enter after an outside edit merges the chosen style into the file as it is now' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            & $script:outsideEdit
            $p2 = $script:probe2
            $r = Complete-FilePreview -Session $s -Merge {
                param($b) Get-StylePreviewJson -OriginalJson $b -StyleDir $p2 -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false }
            $r.Status | Should -Be 'merged'
            $o = & $script:read
            $o.copyOnSelect | Should -BeTrue
            @($o.profiles.list | Where-Object { $_.name -eq 'Added-By-WT-Settings-UI' }).Count | Should -Be 1
            (& $script:ps $o).colorScheme | Should -Be 'probe2'
            (@($o.schemes | ForEach-Object { $_.name }) | Sort-Object) -join ',' | Should -Be 'Campbell,probe2'
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }

        It 'Enter writes the chosen style when no preview of it landed, and says nothing changed outside' {
            # A blocked session, or a last preview write that failed: the file
            # still holds what the session found, and Enter must not report a
            # style applied that is not in it.
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            $p2 = $script:probe2
            $r = Complete-FilePreview -Session $s -Merge {
                param($b) Get-StylePreviewJson -OriginalJson $b -StyleDir $p2 -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false }
            $r.Status | Should -Be 'done'
            (& $script:ps (& $script:read)).colorScheme | Should -Be 'probe2'
        }

        It 'Enter on the style last previewed writes nothing more' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            $t = [System.IO.File]::GetLastWriteTimeUtc($script:p)
            $p1 = $script:probe
            (Complete-FilePreview -Session $s -Merge {
                param($b) Get-StylePreviewJson -OriginalJson $b -StyleDir $p1 -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false }).Status |
                Should -Be 'done'
            [System.IO.File]::GetLastWriteTimeUtc($script:p) | Should -Be $t
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }

        It 'Esc says it left the file, not that it took the preview out, when every key was changed again' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            $o = & $script:read
            $e = & $script:ps $o
            $e.colorScheme = 'Mine'; $e.opacity = 40; $e.font = [pscustomobject]@{ face = 'Mine Mono'; size = 11 }
            $o.schemes = @([pscustomobject]@{ name = 'Campbell'; background = '#0C0C0C' }, [pscustomobject]@{ name = 'probe'; background = '#ABCDEF' })
            [System.IO.File]::WriteAllText($script:p, ($o | ConvertTo-Json -Depth 100), $script:enc)
            $bytes = [System.IO.File]::ReadAllBytes($script:p)
            $r = Restore-FilePreview -Session $s -End
            $r.Status | Should -Be 'left'
            ([System.IO.File]::ReadAllBytes($script:p) -join ',') | Should -BeExactly ($bytes -join ',')
        }

        It 'the next command puts back a preview a closed picker left, once' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            $s = $null

            (Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $script:p).Status | Should -Be 'restored'
            [System.IO.File]::ReadAllText($script:p) | Should -BeExactly $script:original
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
            [System.IO.File]::Exists($script:paths.Original) | Should -BeFalse
            $t = [System.IO.File]::GetLastWriteTimeUtc($script:p)
            (Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $script:p).Status | Should -Be 'none'
            [System.IO.File]::GetLastWriteTimeUtc($script:p) | Should -Be $t
        }

        It 'a file changed since the closed picker is left as it is, and the file it found is kept beside it' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $s -Text (& $script:previewOf $s.OriginalText $script:probe) | Should -Be 'written'
            & $script:outsideEdit
            $edited = [System.IO.File]::ReadAllBytes($script:p)

            $r = Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $script:p
            $r.Status | Should -Be 'kept'
            ([System.IO.File]::ReadAllBytes($script:p) -join ',') | Should -BeExactly ($edited -join ',')
            [System.IO.Path]::GetDirectoryName($r.Backup) | Should -Be ([System.IO.Path]::GetDirectoryName($script:p))
            [System.IO.Path]::GetFileName($r.Backup) | Should -Match '^settings\.json\.preview-\d{8}-\d{6}(-\d+)?$'
            [System.IO.File]::ReadAllText($r.Backup) | Should -BeExactly $script:original
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
            [System.IO.File]::Exists($script:paths.Original) | Should -BeFalse
        }

        It 'a restore that cannot write says so, keeps the record, and does not throw' {
            $s = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            $preview = & $script:previewOf $s.OriginalText $script:probe
            Write-FilePreview -Session $s -Text $preview | Should -Be 'written'
            Mock Write-SettingsAtomic { [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false)) }
            Mock Write-SettingsAtomic { throw 'locked' } -ParameterFilter { $Path -eq $script:p }

            $r = Restore-FilePreview -Session $s -End
            $r.Status | Should -Be 'failed'
            $r.Reason | Should -Not -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:p) | Should -BeExactly $preview
            [System.IO.File]::Exists($script:paths.Record) | Should -BeTrue
            [System.IO.File]::Exists($script:paths.Original) | Should -BeTrue
        }

        It 'never writes over a record that names another session' {
            # A recovery that failed leaves the only copy of what the closed
            # session found. A new session must not write its own over it.
            $a = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $a -Text (& $script:previewOf $a.OriginalText $script:probe) | Should -Be 'written'
            $copy = [System.IO.File]::ReadAllBytes($script:paths.Original)

            $b = New-FilePreviewSession -Kind WindowsTerminal -Path $script:p -By picker -TargetName 'PowerShell'
            Write-FilePreview -Session $b -Text (& $script:previewOf $b.OriginalText $script:probe2) | Should -Be 'failed'
            ([System.IO.File]::ReadAllBytes($script:paths.Original) -join ',') | Should -BeExactly ($copy -join ',')
        }
    }
}

Describe 'a WezTerm preview session' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $sand = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $script:TStylesDataRoot = Join-Path $sand 'data'
            [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            $script:home2 = Join-Path $sand 'h'
            $script:module = Get-WezTermModulePath -HomeDir $script:home2
            $script:luaOf = {
                param($Name)
                $d = Get-StyleDir -StyleName $Name
                $sc = [System.IO.File]::ReadAllText((Join-Path $d 'scheme.json')) | ConvertFrom-Json
                $th = [System.IO.File]::ReadAllText((Join-Path $d 'theme.json')) | ConvertFrom-Json
                Get-WezTermStyleLua -StyleName $Name -Scheme $sc -Theme $th -BackgroundImage $null
            }
            $script:preview = {
                param($s)
                $d = Get-StyleDir -StyleName 'tombraider'
                $sc = [System.IO.File]::ReadAllText((Join-Path $d 'scheme.json')) | ConvertFrom-Json
                $th = [System.IO.File]::ReadAllText((Join-Path $d 'theme.json')) | ConvertFrom-Json
                Write-WezTermStyleModule -StyleName 'tombraider' -Scheme $sc -Theme $th -BackgroundImage $null `
                    -LayoutTheme $null -HomeDir $script:home2 -Session $s
            }
            $script:paths = Get-FilePreviewRecordPath -Kind WezTerm -Path $script:module
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        It 'Esc leaves a module another tstyles run rewrote' {
            Write-WezTermModuleText -Path $script:module -Text (& $script:luaOf 'sober') | Should -Be 'written'
            $s = New-FilePreviewSession -Kind WezTerm -Path $script:module -By picker
            & $script:preview $s | Should -Be 'written'
            $umbrella = & $script:luaOf 'umbrella'
            Write-WezTermModuleText -Path $script:module -Text $umbrella | Should -Be 'written'

            (Restore-FilePreview -Session $s -End).Status | Should -Be 'left'
            [System.IO.File]::ReadAllText($script:module) | Should -BeExactly $umbrella
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }

        It 'the next picker puts back a module a closed picker left, and removes one it created (<label>)' -ForEach @(
            @{ label = 'module there before'; existed = $true }
            @{ label = 'no module before';    existed = $false }
        ) {
            if ($existed) { Write-WezTermModuleText -Path $script:module -Text (& $script:luaOf 'sober') | Should -Be 'written' }
            $s = New-FilePreviewSession -Kind WezTerm -Path $script:module -By picker
            & $script:preview $s | Should -Be 'written'
            $s = $null

            (Restore-AbandonedFilePreview -Kind WezTerm -Path $script:module).Status | Should -Be 'restored'
            if ($existed) {
                [System.IO.File]::ReadAllText($script:module) | Should -BeExactly (& $script:luaOf 'sober')
            } else {
                [System.IO.File]::Exists($script:module) | Should -BeFalse
            }
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }

        It 'writes a preview that differs from the last only in case, and does not then refuse the next' {
            # Write-FilePreview compares case-sensitively and recorded the text
            # as written; the module write it calls compared with -eq and wrote
            # nothing. The file then held other text than the session's record,
            # so the next preview took it for someone else's edit: 'changed',
            # sticky, for the rest of the picker.
            $s = New-FilePreviewSession -Kind WezTerm -Path $script:module -By picker
            $a = & $script:luaOf 'sober'
            $b = $a.Replace('TerminalStyles sober', 'TerminalStyles SOBER')
            $b | Should -Not -BeExactly $a -Because 'the probe must differ'
            Write-FilePreview -Session $s -Text $a | Should -BeExactly 'written'
            Write-FilePreview -Session $s -Text $b | Should -BeExactly 'written'
            [System.IO.File]::ReadAllText($script:module) | Should -BeExactly $b
            Write-FilePreview -Session $s -Text (& $script:luaOf 'umbrella') | Should -BeExactly 'written'
        }

        It 'Enter drops the record, whatever the publish then writes' {
            $s = New-FilePreviewSession -Kind WezTerm -Path $script:module -By picker
            & $script:preview $s | Should -Be 'written'
            Write-WezTermModuleText -Path $script:module -Text (& $script:luaOf 'umbrella') | Should -Be 'written'
            (Complete-FilePreview -Session $s).Status | Should -Be 'done'
            [System.IO.File]::Exists($script:paths.Record) | Should -BeFalse
        }
    }
}

Describe 'Show-FilePreviewResult' {
    InModuleScope TerminalStyles {
        BeforeEach { Mock Write-Host {} }

        It 'says <label>' -ForEach @(
            @{ label = 'a recovered settings.json'; r = @{ Event = 'recover'; Status = 'restored'; Kind = 'WindowsTerminal'; By = 'picker' }; text = 'was put back first' }
            @{ label = 'a recovered module';        r = @{ Event = 'recover'; Status = 'restored'; Kind = 'WezTerm'; By = 'picker' }; text = "WezTerm's module held a preview" }
            @{ label = 'a kept copy';               r = @{ Event = 'recover'; Status = 'kept'; Kind = 'WindowsTerminal'; By = 'tuner'; Backup = '/x/settings.json.preview-1' }; text = '/x/settings.json.preview-1' }
            @{ label = 'the keys left on Esc';      r = @{ Event = 'restore'; Status = 'merged'; Kind = 'WindowsTerminal'; By = 'picker'; Kept = @('opacity', 'font') }; text = 'Left opacity, font as the file has them now' }
            @{ label = 'a module left on Esc';      r = @{ Event = 'restore'; Status = 'left'; Kind = 'WezTerm'; By = 'picker' }; text = "WezTerm's module changed while the picker was open" }
            @{ label = 'a failed restore';          r = @{ Event = 'restore'; Status = 'failed'; Kind = 'WindowsTerminal'; By = 'picker'; Path = '/x'; Reason = 'locked'; Arm = 'restore' }; text = 'Could not put' }
            @{ label = 'a merge on Enter';          r = @{ Event = 'commit'; Status = 'merged'; Kind = 'WindowsTerminal'; Style = 'probe2' }; text = "'probe2' was merged into it" }
        ) {
            Show-FilePreviewResult -Result $r
            Should -Invoke Write-Host -Scope It -ParameterFilter { ([string]$Object).Contains($text) }
        }

        It 'is quiet for <label>' -ForEach @(
            @{ label = 'nothing done';    r = @{ Event = 'recover'; Status = 'none' } }
            @{ label = 'a clean Enter';   r = @{ Event = 'commit'; Status = 'done' } }
            @{ label = 'a clean Esc';     r = @{ Event = 'restore'; Status = 'restored' } }
        ) {
            Show-FilePreviewResult -Result $r
            Should -Invoke Write-Host -Times 0 -Scope It
        }
    }
}
