# Pester 5 tests for scripts/review-submission.ps1's pieces: the attachment
# links, the safe unpack, the printable text and the generated README. The
# gh and git half is the maintainer's to run; nothing here reaches GitHub.
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    . (Join-Path $repoRoot 'scripts/review-submission.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:mod = Get-Module TerminalStyles
    $script:allowed = @(& $script:mod { Get-StyleSubmissionFileNames })
    $script:exts = @(& $script:mod { Get-BackgroundImageExtensions })

    function New-TestZip {
        # A zip with these entries (name -> bytes), written by hand so a test
        # can make one tstyles submit never would.
        param([System.Collections.IDictionary]$Entries)
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.zip')
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
        try {
            $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($k in $Entries.Keys) {
                    $s = $z.CreateEntry($k).Open()
                    try { $b = [byte[]]$Entries[$k]; $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
                }
            } finally { $z.Dispose() }
        } finally { $fs.Dispose() }
        $path
    }
    function New-TestDest { $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); $d }
}

Describe 'Get-SubmissionZipLinks' {
    It 'finds the dropped zip, once, in either attachment form' {
        $body = "### The zip`n`n[sunset.zip](https://github.com/user-attachments/files/123/sunset.zip)`n" +
                "again https://github.com/user-attachments/files/123/sunset.zip`n" +
                "old https://github.com/fcreme/TerminalStyles/files/9/old.zip and a picture https://github.com/user-attachments/assets/abc.png"
        Get-SubmissionZipLinks -Body $body | Should -Be @(
            'https://github.com/user-attachments/files/123/sunset.zip',
            'https://github.com/fcreme/TerminalStyles/files/9/old.zip')
    }

    It 'finds nothing in a body with no zip' {
        @(Get-SubmissionZipLinks -Body 'no files here https://example.com/a.zip').Count | Should -Be 0
    }
}

Describe 'Expand-SubmissionZip' {
    It 'unpacks a well-formed submission' {
        $zip = New-TestZip ([ordered]@{ 'scheme.json' = [byte[]](123, 125); 'background.png' = [byte[]](1, 2); 'submission.json' = [byte[]](123, 125) })
        $d = New-TestDest
        (Expand-SubmissionZip -ZipPath $zip -Destination $d -Allowed $script:allowed -ImageExtensions $script:exts).Status | Should -Be 'expanded'
        @(Get-ChildItem -LiteralPath $d | ForEach-Object Name | Sort-Object) | Should -Be @('background.png', 'scheme.json', 'submission.json')
    }

    It 'refuses <Why>, and leaves nothing behind' -ForEach @(
        @{ Why = 'a path that climbs out'; Entry = '../evil.ps1' }
        @{ Why = 'a folder';               Entry = 'sub/scheme.json' }
        @{ Why = 'a backslash path';       Entry = 'sub\scheme.json' }
        @{ Why = 'an absolute path';       Entry = '/etc/scheme.json' }
        @{ Why = 'a file a style lacks';   Entry = 'run.ps1' }
        @{ Why = 'an unsupported image';   Entry = 'background.webp' }
        @{ Why = 'a hidden file';          Entry = '.scheme.json' }
    ) {
        $zip = New-TestZip ([ordered]@{ 'scheme.json' = [byte[]](1); $Entry = [byte[]](1) })
        $d = New-TestDest
        $r = Expand-SubmissionZip -ZipPath $zip -Destination $d -Allowed $script:allowed -ImageExtensions $script:exts
        $r.Status | Should -Be 'refused'
        $r.Reason | Should -BeLike "*'$Entry'*"
        @(Get-ChildItem -LiteralPath $d -Force).Count | Should -Be 0
    }

    It 'refuses too many entries' {
        $zip = New-TestZip ([ordered]@{ 'scheme.json' = [byte[]](1); 'theme.json' = [byte[]](1); 'meta.json' = [byte[]](1) })
        $r = Expand-SubmissionZip -ZipPath $zip -Destination (New-TestDest) -Allowed $script:allowed -ImageExtensions $script:exts -MaxEntries 2
        $r.Status | Should -Be 'refused'
        $r.Reason | Should -Be 'it holds 3 entries; a style is at most 2'
    }

    It 'counts the size it actually copies, and refuses past the cap' {
        $zip = New-TestZip ([ordered]@{ 'scheme.json' = (New-Object byte[] 600); 'background.png' = (New-Object byte[] 600) })
        $d = New-TestDest
        $r = Expand-SubmissionZip -ZipPath $zip -Destination $d -Allowed $script:allowed -ImageExtensions $script:exts -MaxBytes 1000
        $r.Status | Should -Be 'refused'
        @(Get-ChildItem -LiteralPath $d -Force).Count | Should -Be 0
    }

    It 'refuses a file that is not a zip' {
        $p = Join-Path $TestDrive 'not.zip'
        [System.IO.File]::WriteAllText($p, 'hello')
        (Expand-SubmissionZip -ZipPath $p -Destination (New-TestDest) -Allowed $script:allowed -ImageExtensions $script:exts).Status | Should -Be 'refused'
    }
}

Describe 'ConvertTo-VisibleText' {
    It 'shows escape and bell as text, and keeps newlines, tabs and non-ASCII' {
        $t = "a" + [char]27 + "]52;c;x" + [char]7 + "`n`tb " + [char]0x276F + [char]0x9B
        ConvertTo-VisibleText $t | Should -Be ("a\x1b]52;c;x\x07`n`tb " + [char]0x276F + '\x9b')
    }
}

Describe 'ConvertTo-VisibleText and invisible formatting' {
    It 'shows a bidi override and a zero-width space as code points' {
        $t = 'if (ok) ' + [char]0x202E + 'x' + [char]0x200B + 'y'
        ConvertTo-VisibleText $t | Should -Be 'if (ok) \u202ex\u200by'
    }
}

Describe 'New-SubmissionReadme' {
    It 'names exactly the files the style ships, and credits the submitter' {
        $r = New-SubmissionReadme -Name 'sunset' -Description 'Warm dusk.' -Author 'someone' -IssueNumber 170 `
            -Files @('scheme.json', 'meta.json', 'prompt.sh', 'profile.ps1') -ImageFile 'background.png' -ImageSource 'my photo' -PromptVerdict 'generated'
        $r | Should -Match 'Submitted by \[someone\]\(https://github\.com/someone\) in #170\.'
        $section = [regex]::Match($r, '(?ms)^##\s+Includes\s*$(.*?)(?=^##\s|\z)').Groups[1].Value
        foreach ($f in 'scheme.json', 'profile.ps1', 'prompt.sh', 'meta.json') { $section | Should -Match ([regex]::Escape("**$f**")) }
        $section | Should -Not -Match 'theme\.json'
        $section | Should -Match 'generated by `tstyles create`'
        $r | Should -Not -Match '#[0-9a-fA-F]{6}\b' -Because 'Style-README-Accuracy holds a quoted colour to the scheme'
    }
}

Describe 'a zip from tstyles submit survives the review' {
    It 'unpacks, passes the checks and is recognised as generated' {
        $zip = & $script:mod {
            param($root)
            $saved = $script:TStylesDataRoot
            $script:TStylesDataRoot = Join-Path $root 'data'
            try {
                $img = Join-Path $root 'src.png'
                [System.IO.File]::WriteAllBytes($img, [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1))
                $scheme = Get-Content -Raw -LiteralPath (Join-Path $script:TStylesModuleRoot 'styles/eva/scheme.json') | ConvertFrom-Json
                $choice = [ordered]@{ shape = 'twoline'; symbol = [string][char]0x03BB; pathColor = '#88c0d0'; symbolColor = '#a3be8c' }
                $theme = New-CreatedThemeObject -Name 'roundtrip' -FontFace 'Cascadia Code' -FontSize 11 -CursorShape 'bar' `
                    -ImageOpacity 0.5 -StretchMode 'uniformToFill' -Alignment 'center' -TabColor '#112233'
                $s = Save-CreatedStyle -Name 'roundtrip' -Scheme $scheme -Theme $theme -BackgroundPath $img `
                    -Prompt (New-CreatedStylePromptText -Choice $choice -Name 'roundtrip') -PromptChoice $choice -Description 'Round trip.'
                (New-StyleSubmissionPackage -StyleDir $s.Path -Name 'roundtrip' -OutDir (Join-Path $root 'out') -RightsConfirmed $true).Path
            } finally { $script:TStylesDataRoot = $saved }
        } $TestDrive

        $d = Join-Path (Join-Path $TestDrive 'review') 'roundtrip'
        (Expand-SubmissionZip -ZipPath $zip -Destination $d -Allowed $script:allowed -ImageExtensions $script:exts).Status | Should -Be 'expanded'
        Remove-Item -LiteralPath (Join-Path $d 'submission.json')
        @(& $script:mod { param($x) Get-StyleSubmissionProblems -StyleDir $x } $d) | Should -BeNullOrEmpty
        & $script:mod { param($x) Test-StylePromptIsGenerated -StyleDir $x } $d | Should -Be 'generated'
    }
}
