# Pester 5 tests for `tstyles submit` (lib/submit.ps1): the submission check,
# the generated-prompt verdict, the package, the form URL and the command.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:Bundled = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
        ForEach-Object { @{ Name = $_.Name; Dir = $_.FullName } })
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'the submission check is never stricter than the catalogue' {
    # umbrella/red is the catalogue's one documented contrast exception
    # (Scheme-Contrast.Tests.ps1); every other rule applies to every style.
    It '<Name> passes Get-StyleSubmissionProblems' -ForEach $script:Bundled {
        $exempt = @()
        if ($Name -eq 'umbrella') { $exempt = @('red') }
        $p = @(InModuleScope TerminalStyles -Parameters @{ D = $Dir; E = $exempt } {
            param($D, $E)
            Get-StyleSubmissionProblems -StyleDir $D -ContrastExempt $E
        })
        ($p -join ' | ') | Should -BeNullOrEmpty
    }
}

Describe 'submission' {
    InModuleScope TerminalStyles {
        BeforeAll {
            $script:utf8 = [System.Text.UTF8Encoding]::new($false)
            $script:goodScheme = Get-Content -Raw -LiteralPath (Join-Path $script:TStylesModuleRoot 'styles/eva/scheme.json') | ConvertFrom-Json
            $script:choice = [ordered]@{ shape = 'git'; symbol = '>'; pathColor = '#88c0d0'; symbolColor = '#a3be8c' }

            function New-TestCreatedStyle {
                # A style exactly as `tstyles create` saves one, under a
                # sandboxed data root.
                param([string]$Name = 'sunset', [switch]$NoChoice)
                $img = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.png')
                [System.IO.File]::WriteAllBytes($img, [byte[]](137, 80, 78, 71, 1, 2, 3))
                $theme = New-CreatedThemeObject -Name $Name -FontFace 'Cascadia Code' -FontSize 11 `
                    -CursorShape 'bar' -ImageOpacity 0.5 -StretchMode 'uniformToFill' -Alignment 'center' -TabColor '#112233'
                $prompt = New-CreatedStylePromptText -Choice $script:choice -Name $Name
                $splat = @{}
                if (-not $NoChoice) { $splat.PromptChoice = $script:choice }
                $r = Save-CreatedStyle -Name $Name -Scheme $script:goodScheme -Theme $theme `
                    -BackgroundPath $img -Prompt $prompt -Description 'Warm dusk over the sea.' @splat
                $r.Status | Should -Be 'saved'
                $r.Path
            }
        }
        BeforeEach {
            $script:savedRoot = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
        }
        AfterEach { $script:TStylesDataRoot = $script:savedRoot }

        Context 'Get-StyleSubmissionProblems' {
            It 'passes a style the creator saved from a good palette' {
                $dir = New-TestCreatedStyle
                @(Get-StyleSubmissionProblems -StyleDir $dir) | Should -BeNullOrEmpty
            }

            It 'names a stray file, a folder and a second image' {
                $dir = New-TestCreatedStyle
                [System.IO.File]::WriteAllText((Join-Path $dir 'notes.txt'), 'x')
                New-Item -ItemType Directory -Path (Join-Path $dir 'extra') | Out-Null
                [System.IO.File]::WriteAllBytes((Join-Path $dir 'background.gif'), [byte[]](71, 73, 70))
                $p = @(Get-StyleSubmissionProblems -StyleDir $dir)
                $p | Where-Object { $_ -like "*'notes.txt' cannot be submitted*" } | Should -Not -BeNullOrEmpty
                $p | Where-Object { $_ -like "*folder 'extra'*" } | Should -Not -BeNullOrEmpty
                $p | Where-Object { $_ -like 'There are 2 background images*' } | Should -Not -BeNullOrEmpty
            }

            It 'refuses an image over 2 MB and takes one of exactly 2 MB' {
                $dir = New-TestCreatedStyle
                $img = Join-Path $dir 'background.png'
                [System.IO.File]::WriteAllBytes($img, (New-Object byte[] (2MB)))
                @(Get-StyleSubmissionProblems -StyleDir $dir) | Should -BeNullOrEmpty
                [System.IO.File]::WriteAllBytes($img, (New-Object byte[] (2MB + 1)))
                @(Get-StyleSubmissionProblems -StyleDir $dir) | Should -Be @('background.png is 2.0 MB; the catalogue takes images up to 2 MB.')
            }

            It 'names a missing slot, a short hex, a wrong scheme name and a faint colour' {
                $dir = New-TestCreatedStyle
                $s = Get-Content -Raw -LiteralPath (Join-Path $dir 'scheme.json') | ConvertFrom-Json
                $s.PSObject.Properties.Remove('brightCyan')
                $s.cursorColor = '#fff'
                $s.name = 'other'
                $s.red = $s.background
                [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), ($s | ConvertTo-Json), $script:utf8)
                $p = @(Get-StyleSubmissionProblems -StyleDir $dir)
                $p | Should -Contain 'scheme.json is missing: brightCyan.'
                $p | Should -Contain 'scheme.json colours must be #rrggbb: cursorColor.'
                $p | Should -Contain "scheme.json's name must be 'sunset', the style's name."
                $p | Where-Object { $_ -like 'red (*) is 1.00:1 on background*more than 3:1.' } | Should -Not -BeNullOrEmpty
            }

            It 'needs prompt.sh beside profile.ps1' {
                $dir = New-TestCreatedStyle
                Remove-Item -LiteralPath (Join-Path $dir 'prompt.sh')
                @(Get-StyleSubmissionProblems -StyleDir $dir) |
                    Should -Be @('profile.ps1 has no prompt.sh beside it: the catalogue needs the zsh/bash half of the prompt too.')
            }

            It 'needs a description that fits a picker row' {
                $dir = New-TestCreatedStyle
                $meta = Join-Path $dir 'meta.json'
                [System.IO.File]::WriteAllText($meta, '{"description":""}', $script:utf8)
                @(Get-StyleSubmissionProblems -StyleDir $dir) | Should -Be @('meta.json needs a one-line description: it is what the picker shows beside the name.')
                [System.IO.File]::WriteAllText($meta, ('{"description":"' + ('x' * 91) + '"}'), $script:utf8)
                @(Get-StyleSubmissionProblems -StyleDir $dir) | Should -Be @("meta.json's description must be one line of at most 90 characters (it is 91).")
            }

            It 'refuses a name the catalogue already uses' {
                $dir = New-TestCreatedStyle
                $cat = Join-Path $TestDrive ('cat-' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path (Join-Path $cat 'sunset') -Force | Out-Null
                @(Get-StyleSubmissionProblems -StyleDir $dir -CatalogueRoot $cat) |
                    Should -Be @("The catalogue already has a style called 'sunset'. Save yours under another name with: tstyles tune sunset")
            }
        }

        Context 'Test-StylePromptIsGenerated' {
            It 'says generated for the creator''s own prompt' {
                Test-StylePromptIsGenerated -StyleDir (New-TestCreatedStyle) | Should -Be 'generated'
            }

            It 'says hand-written after one byte of prompt.sh changes' {
                $dir = New-TestCreatedStyle
                $sh = Join-Path $dir 'prompt.sh'
                [System.IO.File]::AppendAllText($sh, ' ', $script:utf8)
                Test-StylePromptIsGenerated -StyleDir $dir | Should -Be 'hand-written'
            }

            It 'says hand-written after profile.ps1 changes' {
                $dir = New-TestCreatedStyle
                [System.IO.File]::AppendAllText((Join-Path $dir 'profile.ps1'), "`nWrite-Host hi`n", $script:utf8)
                Test-StylePromptIsGenerated -StyleDir $dir | Should -Be 'hand-written'
            }

            It 'says hand-written when meta.json has no created record' {
                Test-StylePromptIsGenerated -StyleDir (New-TestCreatedStyle -NoChoice) | Should -Be 'hand-written'
            }

            It 'says hand-written for a symbol the creator does not offer, even when the files match it' {
                $dir = New-TestCreatedStyle
                $odd = [ordered]@{ shape = 'git'; symbol = '@'; pathColor = '#88c0d0'; symbolColor = '#a3be8c' }
                $prompt = New-CreatedStylePromptText -Choice $odd -Name 'sunset'
                [System.IO.File]::WriteAllText((Join-Path $dir 'profile.ps1'), [string]$prompt.Profile, $script:utf8)
                [System.IO.File]::WriteAllText((Join-Path $dir 'prompt.sh'), (([string]$prompt.Shell) -replace "`r`n", "`n"), $script:utf8)
                $meta = [pscustomobject]@{ description = 'x'; created = [pscustomobject]$odd }
                [System.IO.File]::WriteAllText((Join-Path $dir 'meta.json'), ($meta | ConvertTo-Json -Depth 4), $script:utf8)
                Test-StylePromptIsGenerated -StyleDir $dir | Should -Be 'hand-written'
            }

            It 'says none for a style with no prompt files' {
                $dir = New-TestCreatedStyle
                Remove-Item -LiteralPath (Join-Path $dir 'profile.ps1'), (Join-Path $dir 'prompt.sh')
                Test-StylePromptIsGenerated -StyleDir $dir | Should -Be 'none'
            }
        }

        Context 'New-StyleSubmissionPackage' {
            BeforeAll {
                Add-Type -AssemblyName System.IO.Compression
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                function Read-TestZip([string]$Path) {
                    $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
                    try {
                        $names = @($z.Entries | ForEach-Object FullName | Sort-Object)
                        $r = New-Object System.IO.StreamReader($z.GetEntry('submission.json').Open())
                        try { $raw = $r.ReadToEnd() } finally { $r.Dispose() }
                    } finally { $z.Dispose() }
                    @{ Names = $names; Record = ($raw | ConvertFrom-Json); Raw = $raw }
                }
            }

            It 'packs the style flat with a submission record' {
                $dir = New-TestCreatedStyle
                $out = Join-Path $TestDrive ('out-' + [guid]::NewGuid().ToString('N'))
                $r = New-StyleSubmissionPackage -StyleDir $dir -Name 'sunset' -OutDir $out -ImageSource 'my photo' -RightsConfirmed $true
                $r.Status | Should -Be 'written'
                $r.Path | Should -Be (Join-Path $out 'sunset.zip')
                $z = Read-TestZip $r.Path
                $z.Names | Should -Be @('background.png', 'meta.json', 'profile.ps1', 'prompt.sh', 'scheme.json', 'submission.json', 'theme.json')
                $z.Record.name | Should -Be 'sunset'
                $z.Record.description | Should -Be 'Warm dusk over the sea.'
                $z.Record.imageSource | Should -Be 'my photo'
                $z.Record.imageRightsConfirmed | Should -BeTrue
                # Raw text: pwsh 7's ConvertFrom-Json turns the value into a DateTime.
                $z.Raw | Should -Match '"createdUtc":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'
                @(Get-ChildItem -LiteralPath $out -Force).Count | Should -Be 1 -Because 'the .part file was moved, not left'
            }

            It 'replaces an older zip for the same name' {
                $dir = New-TestCreatedStyle
                $out = Join-Path $TestDrive ('out-' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $out | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $out 'sunset.zip'), 'old')
                (New-StyleSubmissionPackage -StyleDir $dir -Name 'sunset' -OutDir $out).Status | Should -Be 'written'
                (Read-TestZip (Join-Path $out 'sunset.zip')).Record.imageRightsConfirmed | Should -BeNullOrEmpty
            }
        }

        Context 'Get-StyleSubmissionUrl' {
            It 'prefills the form, escaping every value' {
                $u = Get-StyleSubmissionUrl -Name 'sun.set' -Description 'Dusk & sea' -ImageSource 'https://x.y/a?b=c'
                $u | Should -Be ('https://github.com/fcreme/TerminalStyles/issues/new?template=style_submission.yml' +
                    '&title=Style%3A%20sun.set&style-name=sun.set&description=Dusk%20%26%20sea' +
                    '&image-source=https%3A%2F%2Fx.y%2Fa%3Fb%3Dc')
            }
        }

        Context 'Invoke-TerminalStyleSubmit' {
            BeforeEach {
                $script:out = New-Object System.Collections.Generic.List[string]
                Mock Write-Host { $script:out.Add("$Object") }
                $script:opened = New-Object System.Collections.Generic.List[string]
                $script:open = { param($u) $script:opened.Add($u) }
                Mock Get-StyleOrigin { 'yours' }
            }

            It 'packs, opens the form and says nothing has been sent' {
                New-TestCreatedStyle | Out-Null
                $answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('my own photo', 'y'))
                Invoke-TerminalStyleSubmit -Name 'sunset' -ReadLine { param($p) $answers.Dequeue() } -OpenUrl $script:open
                $zip = Join-Path $script:TStylesDataRoot 'submissions/sunset.zip'
                [System.IO.File]::Exists($zip) | Should -BeTrue
                $script:opened.Count | Should -Be 1
                $script:opened[0] | Should -BeLike '*style-name=sunset*image-source=my%20own%20photo'
                $script:out[$script:out.Count - 1] | Should -BeLike '  Not sent yet: drag the zip into the form*'
            }

            It 'packs nothing without a yes to the image rights' {
                New-TestCreatedStyle | Out-Null
                $answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('', 'n'))
                Invoke-TerminalStyleSubmit -Name 'sunset' -ReadLine { param($p) $answers.Dequeue() } -OpenUrl $script:open
                [System.IO.Directory]::Exists((Join-Path $script:TStylesDataRoot 'submissions')) | Should -BeFalse
                $script:opened.Count | Should -Be 0
                $script:out | Should -Contain '  Not submitted: the catalogue can only ship images that may be shared.'
            }

            It 'lists the problems and packs nothing' {
                $dir = New-TestCreatedStyle
                [System.IO.File]::WriteAllText((Join-Path $dir 'notes.txt'), 'x')
                Invoke-TerminalStyleSubmit -Name 'sunset' -ReadLine { throw 'asked' } -OpenUrl $script:open
                [System.IO.Directory]::Exists((Join-Path $script:TStylesDataRoot 'submissions')) | Should -BeFalse
                $script:out | Should -Contain "  'sunset' cannot be submitted yet:"
                $script:out | Should -Contain '  Nothing was submitted.'
            }

            It 'still prints the address when the browser cannot be opened' {
                New-TestCreatedStyle | Out-Null
                $answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('', 'yes'))
                Invoke-TerminalStyleSubmit -Name 'sunset' -ReadLine { param($p) $answers.Dequeue() } -OpenUrl { throw 'no browser' }
                $script:out | Should -Contain '  Open the submission form in your browser:'
                $script:out | Where-Object { $_ -like '    https://github.com/fcreme/TerminalStyles/issues/new?*' } | Should -Not -BeNullOrEmpty
            }

            It 'refuses a bundled style, a shadow and an unknown origin' {
                Mock Get-StyleOrigin { 'bundled' }
                Invoke-TerminalStyleSubmit -Name 'eva' -ReadLine { throw 'asked' } -OpenUrl $script:open
                $script:out | Should -Contain "  'eva' is already in the catalogue. Nothing was submitted."
                Mock Get-StyleOrigin { 'shadow' }
                Invoke-TerminalStyleSubmit -Name 'eva' -ReadLine { throw 'asked' } -OpenUrl $script:open
                $script:out[$script:out.Count - 1] | Should -BeLike "*uses a bundled style's name*tstyles tune eva"
                Mock Get-StyleOrigin { 'unknown' }
                Invoke-TerminalStyleSubmit -Name 'eva' -ReadLine { throw 'asked' } -OpenUrl $script:open
                $script:out[$script:out.Count - 1] | Should -BeLike "*Cannot tell whether 'eva'*nothing was submitted."
                $script:opened.Count | Should -Be 0
            }

            It 'answers an unknown name and a missing one' {
                Invoke-TerminalStyleSubmit -Name 'no-such-style' -OpenUrl $script:open
                $script:out | Should -Contain "  No style named 'no-such-style'. Nothing was submitted."
                Invoke-TerminalStyleSubmit -OpenUrl $script:open
                $script:out[$script:out.Count - 1] | Should -BeLike '  Usage: tstyles submit <name>*'
            }
        }

        Context 'the dispatcher' {
            It 'knows submit as a subcommand' {
                $script:TStylesSubcommands | Should -Contain 'submit'
            }

            It 'refuses -Target rather than ignoring it' {
                $script:out = New-Object System.Collections.Generic.List[string]
                Mock Write-Host { $script:out.Add("$Object") }
                Mock Invoke-TerminalStyleSubmit { throw 'ran' }
                Invoke-TerminalStyle submit sunset -Target 'Ubuntu'
                $script:out | Should -Contain '  tstyles submit takes only a style name: tstyles submit <name>. Nothing was submitted.'
                Should -Invoke Invoke-TerminalStyleSubmit -Times 0
            }

            It 'passes the name through' {
                Mock Invoke-TerminalStyleSubmit { }
                Invoke-TerminalStyle submit sunset
                Should -Invoke Invoke-TerminalStyleSubmit -Times 1 -ParameterFilter { $Name -eq 'sunset' }
            }
        }
    }
}
