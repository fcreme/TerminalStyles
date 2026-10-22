# Pester 5 tests for Invoke-TerminalStylesRegister.
#
# Function adds `Import-Module TerminalStyles -DisableNameChecking` to
# both PowerShell engines' $PROFILE files (wrapped in BEGIN/END markers
# so uninstall can strip it). Tests use the function's -Targets
# parameter to inject a synthetic single-target list pointing at
# $TestDrive, bypassing the real engine discovery.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

# These exercise the WRITE, not the consent gate, so they pass -Yes. Without it
# they now refuse: Pester's host is redirected, and the confirm prompt no longer
# assumes yes when nobody can answer. That change is the point -- `tstyles
# register < /dev/null` used to write the loader into both engines' $PROFILE
# files unattended, because `$ans -match '^(?i)n'` is FALSY against the
# AutomationNull that Read-Host returns at EOF.
Describe 'Invoke-TerminalStylesRegister' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive 'fake-profile.ps1'
            $script:loaderBegin = '# ===== TerminalStyles BEGIN ====='
            $script:loaderEnd   = '# ===== TerminalStyles END ====='
            $script:blockPattern = "(?ms)$([regex]::Escape($script:loaderBegin)).*?$([regex]::Escape($script:loaderEnd))\r?\n?"
            Mock Read-Host { '' }  # default Y on confirm prompt
        }

        It 'writes the loader block to a fresh $PROFILE' {
            # Pre-condition: fakeProfile doesn't exist
            Test-Path -LiteralPath $script:fakeProfile | Should -BeFalse

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $false
                HasLoader   = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            Test-Path -LiteralPath $script:fakeProfile | Should -BeTrue
            $content = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $content | Should -Match $script:blockPattern
            $content | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
        }

        It 'is idempotent: re-running with existing loader skips' {
            # Pre-populate with a BEGIN/END block
            $existingContent = "# my existing profile`r`n`r`n$script:loaderBegin`r`nImport-Module TerminalStyles -DisableNameChecking`r`n$script:loaderEnd`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Targets @($target) -Yes

            # Content unchanged
            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Be $before
            # Exactly one BEGIN/END block (no duplicates)
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
        }

        It '-Force replaces an existing loader block' {
            # Pre-populate with a BEGIN/END block whose body is DIFFERENT (legacy format)
            $oldBody = "$script:loaderBegin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:loaderEnd"
            $existingContent = "# my existing profile`r`n`r`n$oldBody`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Force -Targets @($target) -Yes

            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            # Exactly one BEGIN/END block
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
            # The new body is the canonical PSGallery loader (NOT the legacy dot-source)
            $after | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
            $after | Should -Not -Match 'LOCALAPPDATA\\TerminalStyles\\tstyles\.ps1'
        }

        It '-Force strips only its own block when a stray BEGIN sits above it' {
            # The same defect the rc half carries, on the other half of the same
            # symmetry: `BEGIN .*? END` under (?s) starts at the FIRST BEGIN and
            # runs to the first END after it. Here the strip replaces with
            # NOTHING, so a $PROFILE with a stray or duplicated marker lost the
            # user's own lines outright -- and the first-touch backup is skipped
            # for any file that already carries a BEGIN.
            $stale = "$script:loaderBegin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:loaderEnd"
            $existingContent = "# my existing profile`r`n$script:loaderBegin`r`nfunction prompt { 'keep-me> ' }`r`n$stale`r`nSet-Alias ll Get-ChildItem`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Force -Targets @($target) -Yes

            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Match "keep-me"
            $after | Should -Match 'Set-Alias ll Get-ChildItem'
            $after | Should -Match '# my existing profile'
            # It really did rewrite the block: the legacy body is gone, and one
            # END is left for one loader. The stray BEGIN stays -- it is a line
            # the user wrote, in a file we only ever edit between OUR markers.
            $after | Should -Not -Match 'LOCALAPPDATA\\TerminalStyles\\tstyles\.ps1'
            $after | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
            ([regex]::Matches($after, [regex]::Escape($script:loaderEnd))).Count   | Should -Be 1
            ([regex]::Matches($after, [regex]::Escape($script:loaderBegin))).Count | Should -Be 2
        }
    }
}

Describe 'register writes a loader the install can actually resolve' {
    # A bootstrap install lives in the data root, which is NOT on
    # $env:PSModulePath. install.ps1 writes the full-path form for exactly that
    # reason and says so; terminals.ps1 repeats the rule where it stages the
    # shell shim. register wrote `Import-Module TerminalStyles` regardless.
    #
    # Because it uses the installer's own BEGIN/END markers, `tstyles register
    # -Force` on a bootstrap install stripped the working loader and wrote a
    # broken one over it, printed "Registered in <profile>" and "TerminalStyles
    # will auto-load on every new shell tab", and every new tab then opened with
    # a red "no valid module file was found in any module directory" and no
    # tstyles command -- from a session that had been working seconds earlier.
    # install.ps1 also tells a user whose engines were not found to add that
    # by-name line by hand, so there were two ways in.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.ps1')
            $script:savedModule = $script:TStylesModuleRoot
            Mock Read-Host { '' }
        }
        AfterEach { $script:TStylesModuleRoot = $script:savedModule }

        It 'a BOOTSTRAP install gets the full path, not the bare name' {
            $fakeRoot = Join-Path $TestDrive 'bootstrap-root'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { $fakeRoot }
            $script:TStylesModuleRoot = $fakeRoot
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap' -Because 'the fixture must set the branch under test'

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false })

            $written = [System.IO.File]::ReadAllText($script:fakeProfile)
            $written | Should -Match 'TerminalStyles\.psd1' `
                -Because 'the bootstrap directory is not on $env:PSModulePath'
            $written | Should -Not -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$' `
                -Because 'the bare name resolves to nothing there'
        }

        It 'a PSGallery install still gets the bare name' {
            $modRoot = Join-Path $TestDrive 'psgallery-root'
            New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { Join-Path $TestDrive 'a-different-data-root' }
            $script:TStylesModuleRoot = $modRoot
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'

            Invoke-TerminalStylesRegister -Yes -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false })

            [System.IO.File]::ReadAllText($script:fakeProfile) |
                Should -Match '(?m)^Import-Module TerminalStyles -DisableNameChecking\s*$' `
                -Because 'PSModulePath resolves it, and the version-stamped path would pin an old one'
        }

        # The WRITE was fixed and the two messages around it were left naming the
        # pre-fix line: a consent screen whose whole job is "here is the one line
        # I am about to put in your $PROFILE", and a closing hint that on a
        # bootstrap install errored with the very "no valid module file was found
        # in any module directory" this Describe exists to prevent. Both are
        # asserted against the line read back OUT of the file, never a literal --
        # a literal here would just be a fourth copy to keep in step.
        It 'the consent screen shows the loader line a BOOTSTRAP install really gets' {
            $fakeRoot = Join-Path $TestDrive 'bootstrap-root'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { $fakeRoot }
            $script:TStylesModuleRoot = $fakeRoot
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap' -Because 'the fixture must set the branch under test'

            $out = Invoke-TerminalStylesRegister -Yes 6>&1 -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false }) |
                Out-String

            # @(...)[0]: without the array subexpression a single matching line
            # indexes into the string itself and yields 'I'.
            $written = @([System.IO.File]::ReadAllText($script:fakeProfile) -split "`r?`n" |
                         Where-Object { $_ -match '^Import-Module ' })[0]
            $written | Should -Match 'TerminalStyles\.psd1' -Because 'the fixture must be on the bootstrap branch'

            $out | Should -Match ([regex]::Escape($written)) `
                -Because 'the user consents to the line that is actually written'
            $out | Should -Match ('To verify in this session: ' + [regex]::Escape($written)) `
                -Because 'the closing hint must name a command that can resolve THIS install'
        }

        It 'a PSGallery install sees the bare name in both messages' {
            # So the fix cannot be "print the path everywhere": there the bare
            # name is what is written, and it is what both messages must say.
            $modRoot = Join-Path $TestDrive 'psgallery-root'
            New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
            Mock Get-TStylesDataRoot { Join-Path $TestDrive 'a-different-data-root' }
            $script:TStylesModuleRoot = $modRoot
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'

            $out = Invoke-TerminalStylesRegister -Yes 6>&1 -Targets @([pscustomobject]@{
                Label = 'PowerShell 7'; ProfilePath = $script:fakeProfile; Exists = $false; HasLoader = $false }) |
                Out-String

            $out | Should -Match '(?m)^\s+Import-Module TerminalStyles -DisableNameChecking\s*$'
            $out | Should -Match ([regex]::Escape('To verify in this session: Import-Module TerminalStyles -DisableNameChecking -Force'))
            $out | Should -Not -Match 'TerminalStyles\.psd1' `
                -Because 'nothing on a PSGallery install writes a path'
        }
    }
}

Describe 'register tells the truth about a $PROFILE it could not write' {
    # The write loop had no status at all: bare ReadAllText/WriteAllText, and
    # "  Registered in <path>" printed unconditionally on the line after. So an
    # unwritable $PROFILE -- read-only bit, root-owned, a OneDrive lock or a
    # Files-On-Demand placeholder -- produced a red .NET error AND a green
    # "Registered in" line for the same file, and the command still closed on
    # "TerminalStyles will auto-load on every new shell tab." A user who
    # scrolled past the red, or whose second engine failed while the first
    # succeeded, had a real success line sitting beside a fake one.
    #
    # Register-ShellLoader does this same job for rc files and has returned
    # 'failed' instead of throwing since the release its header describes. This
    # is the other half of that symmetry.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            $script:good = Join-Path $script:d 'good-profile.ps1'
            $script:bad  = Join-Path $script:d 'bad-profile.ps1'
            foreach ($p in $script:good, $script:bad) {
                [System.IO.File]::WriteAllText($p, "# my own profile`r`n",
                    [System.Text.UTF8Encoding]::new($false))
            }
            # IsReadOnly rather than chmod: one .NET attribute on every platform
            # the suite runs on. Cleared in AfterEach so TestDrive can be removed.
            (Get-Item -LiteralPath $script:bad -Force).IsReadOnly = $true

            function script:New-Target([string]$Path, [string]$Label) {
                [pscustomobject]@{ Label = $Label; ProfilePath = $Path; Exists = $true; HasLoader = $false }
            }
        }
        AfterEach { (Get-Item -LiteralPath $script:bad -Force).IsReadOnly = $false }

        It 'does not report a file it could not write as registered' {
            $out = Invoke-TerminalStylesRegister -Yes 6>&1 -Targets @(
                (script:New-Target $script:good 'PowerShell 7')
                (script:New-Target $script:bad  'Windows PowerShell 5.1')
            ) | Out-String

            $out | Should -Match ("Registered in " + [regex]::Escape($script:good))
            $out | Should -Not -Match ("Registered in " + [regex]::Escape($script:bad)) `
                -Because 'nothing was written to it'
            $out | Should -Match 'could not write'
            $out | Should -Match ([regex]::Escape($script:bad))

            [System.IO.File]::ReadAllText($script:good) | Should -Match 'TerminalStyles BEGIN'
            [System.IO.File]::ReadAllText($script:bad)  | Should -Be "# my own profile`r`n"
        }

        It 'still writes every other target, and still promises auto-load for them' {
            $out = Invoke-TerminalStylesRegister -Yes 6>&1 -Targets @(
                (script:New-Target $script:bad  'Windows PowerShell 5.1')
                (script:New-Target $script:good 'PowerShell 7')
            ) | Out-String

            # Order matters: the failing target is FIRST, so a loop that unwinds
            # never reaches the one that would have worked.
            [System.IO.File]::ReadAllText($script:good) | Should -Match 'TerminalStyles BEGIN'
            $out | Should -Match 'auto-load on every new shell tab'
            $out | Should -Match 'Not registered in'
        }

        It 'does not promise auto-load when every target failed' {
            $out = Invoke-TerminalStylesRegister -Yes 6>&1 -Targets @(
                (script:New-Target $script:bad 'Windows PowerShell 5.1')
            ) | Out-String

            $out | Should -Not -Match 'auto-load on every new shell tab' `
                -Because 'no shell tab will load anything'
            $out | Should -Not -Match 'To verify in this session'
        }

        It 'leaves no backup of a profile it never modified, however often it is retried' {
            # Save-FirstTouchBackup runs BEFORE the write, so the failing target
            # got a <profile>.bak-<timestamp> copy of a file that never changed
            # -- and since the block never lands, the next run took another.
            Invoke-TerminalStylesRegister -Yes -Targets @((script:New-Target $script:bad 'x')) 6>&1 | Out-Null
            Start-Sleep -Milliseconds 1100   # the stamp is to the second
            Invoke-TerminalStylesRegister -Yes -Targets @((script:New-Target $script:bad 'x')) 6>&1 | Out-Null

            @(Get-ChildItem -LiteralPath $script:d -Filter 'bad-profile.ps1.bak-*' -Force).Count |
                Should -Be 0 -Because 'a backup of an unmodified file is litter, and it compounds'
        }

        It 'does not throw out of the command under $ErrorActionPreference = Stop' {
            # A user profile that sets Stop, or `tstyles register -ErrorAction
            # Stop`. Under the shell default the unguarded .NET exception is
            # non-terminating for the loop; under Stop it unwound the whole
            # command, after printing "Registered in" for a file it had not
            # written.
            $ErrorActionPreference = 'Stop'
            { Invoke-TerminalStylesRegister -Yes -Targets @(
                (script:New-Target $script:bad  'Windows PowerShell 5.1')
                (script:New-Target $script:good 'PowerShell 7')
              ) 6>&1 | Out-Null } | Should -Not -Throw
            [System.IO.File]::ReadAllText($script:good) | Should -Match 'TerminalStyles BEGIN'
        }
    }
}

Describe 'register tells the truth about a $PROFILE it could not read' {
    # The other half of the Describe above, one loop earlier. Detection read
    # each $PROFILE with a bare ReadAllText, outside any try, and did not reset
    # its content between targets. At the shell default a failed read only
    # ended that statement, so the file was answered for from the PREVIOUS
    # target's text -- "Already registered" for a file nobody had read -- and
    # it was never named under "Not registered in". Under Stop, and inside any
    # try (Pester's included), the whole command threw.
    #
    # The unreadable profile is a DIRECTORY at the profile path: ReadAllBytes
    # refuses one on every platform the suite runs on, with no chmod or ACL.
    # The order is the defect's: B after A is what made the old loop answer for
    # B with A's content, and C after B proves the loop goes on.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            $script:a = Join-Path $script:d 'a-profile.ps1'
            $script:b = Join-Path $script:d 'b-profile.ps1'
            $script:c = Join-Path $script:d 'c-profile.ps1'
            [System.IO.File]::WriteAllText($script:a,
                "# mine`r`n`r`n# ===== TerminalStyles BEGIN =====`r`nImport-Module TerminalStyles -DisableNameChecking`r`n# ===== TerminalStyles END =====`r`n",
                [System.Text.UTF8Encoding]::new($false))
            New-Item -ItemType Directory -Path $script:b -Force | Out-Null
            [System.IO.File]::WriteAllText($script:c, "# fresh`r`n", [System.Text.UTF8Encoding]::new($false))

            # Fresh objects per call: register adds members to the ones it is given.
            function script:Targets {
                @([pscustomobject]@{ Label = 'A-registered'; ProfilePath = $script:a; Exists = $true; HasLoader = $false }
                  [pscustomobject]@{ Label = 'B-unreadable'; ProfilePath = $script:b; Exists = $true; HasLoader = $false }
                  [pscustomobject]@{ Label = 'C-fresh';      ProfilePath = $script:c; Exists = $true; HasLoader = $false })
            }
        }

        It 'names a $PROFILE it cannot read, offers it nowhere, and still registers the rest' {
            # -Width 500: 5.1 wraps host text at the console width, and these
            # match whole $TestDrive paths.
            $out = Invoke-TerminalStylesRegister -Yes -Targets (script:Targets) 6>&1 | Out-String -Width 500

            $out | Should -Match ('Already registered in ' + [regex]::Escape($script:a))
            $out | Should -Match ('Could not read ' + [regex]::Escape($script:b)) `
                -Because 'the user is told which file, and why'
            $out | Should -Not -Match ('Already registered in ' + [regex]::Escape($script:b)) `
                -Because 'nothing was read from it, so nothing can be said about what it holds'
            $out | Should -Not -Match ('B-unreadable: ' + [regex]::Escape($script:b)) `
                -Because 'the consent screen lists what will be written, and this file will not be'
            $out | Should -Match 'Not registered in: B-unreadable'
            [System.IO.File]::ReadAllText($script:c) | Should -Match 'TerminalStyles BEGIN' `
                -Because 'one unreadable profile does not stop the ones after it'
            @(Get-ChildItem -LiteralPath $script:b -Force).Count | Should -Be 0 -Because 'nothing was written into it'
        }

        It 'does not throw out of the command under $ErrorActionPreference = Stop' {
            # The user-profile and `-ErrorAction Stop` case the Describe above
            # pins for the write.
            $ErrorActionPreference = 'Stop'
            { Invoke-TerminalStylesRegister -Yes -Targets (script:Targets) 6>&1 | Out-Null } | Should -Not -Throw
            [System.IO.File]::ReadAllText($script:c) | Should -Match 'TerminalStyles BEGIN'
        }
    }
}

Describe 'register keeps a $PROFILE''s byte-order mark and every character in it' {
    # Register read the $PROFILE with [System.IO.File]::ReadAllText(path,
    # ISO-8859-1). That overload looks for a byte-order mark first and decodes
    # by it, whatever encoding it is handed, so a profile saved as UTF-8 with a
    # BOM -- ISE, Notepad's "UTF-8 with BOM", 5.1's Set-Content -Encoding UTF8
    # -- or as UTF-16 -- 5.1's > and Out-File -- arrived as Unicode text. It was
    # written back through ISO-8859-1, which has no byte for anything above
    # U+00FF. Measured on a UTF-8-BOM profile: `ef bb bf 23 20 63 61 66 c3 a9`
    # came back `23 20 63 61 66 e9`, and the prompt glyph U+276F as 3f. Those
    # are the files Windows PowerShell 5.1 needs: it reads a character outside
    # the ANSI code page only from a file that opens with a byte-order mark.
    #
    # Every expected byte is computed from the fixture, never from a decode of
    # the result: a decode that agrees with the writer agrees with its bugs.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            $script:p = Join-Path $script:d 'fake-profile.ps1'
            $script:begin = '# ===== TerminalStyles BEGIN ====='
            $script:end   = '# ===== TerminalStyles END ====='
            # The legacy body the '-Force replaces an existing loader block'
            # test seeds. A block that is not the one register writes is what
            # makes the write visible: with the current loader line as the
            # fixture's block, a register that wrote nothing passed.
            $script:stale = "$script:begin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:end"
        }

        # Built from [char] codes so this file stays ASCII: 5.1 reads a BOM-less
        # .ps1 in the ANSI code page. A Latin-1 letter, a prompt glyph, Greek,
        # Cyrillic, CJK, an emoji and a Powerline glyph.
        function script:Text {
            '# caf' + [char]0xE9 + "`r`n'" + [char]0x276F + [char]0x03BB + [char]0x0416 + [char]0x65E5 +
                [char]::ConvertFromUtf32(0x1F680) + [char]0xE0B0 + "'`r`n"
        }
        function script:EncodingOf([string]$Kind) {
            switch ($Kind) {
                'utf8bom' { [System.Text.UTF8Encoding]::new($true) }
                'utf16le' { [System.Text.UnicodeEncoding]::new($false, $true) }
                'utf16be' { [System.Text.UnicodeEncoding]::new($true, $true) }
                'utf32le' { [System.Text.UTF32Encoding]::new($false, $true) }
                'utf32be' { [System.Text.UTF32Encoding]::new($true, $true) }
                default   { throw "No encoding kind '$Kind'." }
            }
        }
        function script:Hex([byte[]]$Bytes) {
            if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
            [System.BitConverter]::ToString($Bytes) -replace '-', ''
        }
        function script:Head([byte[]]$Bytes, [int]$Count) {
            if ($Bytes.Length -lt $Count) { return script:Hex $Bytes }
            script:Hex ([byte[]]$Bytes[0..($Count - 1)])
        }
        # -Force: on Unix a dotfile fixture comes back as nothing without it.
        function script:Baks {
            @(Get-ChildItem -LiteralPath $script:d -Filter 'fake-profile.ps1.bak-*' -Force)
        }
        function script:Target([bool]$HasLoader) {
            [pscustomobject]@{ Label = 'PowerShell 7'; ProfilePath = $script:p; Exists = $true; HasLoader = $HasLoader }
        }

        It 'keeps them in a <Label> $PROFILE it registers for the first time' -ForEach @(
            @{ Label = 'UTF-8 with BOM'; Kind = 'utf8bom' }
            @{ Label = 'UTF-16LE';       Kind = 'utf16le' }
            @{ Label = 'UTF-16BE';       Kind = 'utf16be' }
            @{ Label = 'UTF-32LE';       Kind = 'utf32le' }
            @{ Label = 'UTF-32BE';       Kind = 'utf32be' }
        ) {
            $enc = script:EncodingOf $Kind
            $bom = $enc.GetPreamble()
            $fixture = [byte[]]($bom + $enc.GetBytes((script:Text)))
            [System.IO.File]::WriteAllBytes($script:p, $fixture)
            script:Head ([System.IO.File]::ReadAllBytes($script:p)) $bom.Length | Should -BeExactly (script:Hex $bom) `
                -Because 'the fixture has to open with the mark it is named for'

            Invoke-TerminalStylesRegister -Yes -Targets @((script:Target $false)) 6>&1 | Out-Null

            $after = [System.IO.File]::ReadAllBytes($script:p)
            $after.Length | Should -BeGreaterThan $fixture.Length -Because 'the block was added'
            script:Head $after $fixture.Length | Should -BeExactly (script:Hex $fixture) `
                -Because 'the byte-order mark and every character of the user''s text are theirs'
            # The fixture ends in CRLF, and register's separator starts with
            # one, so the user's bytes are a prefix of the file and what follows
            # them is the block alone, in the file's own encoding.
            $enc.GetString($after, $fixture.Length, $after.Length - $fixture.Length) |
                Should -MatchExactly '^\s*# ===== TerminalStyles BEGIN =====[\s\S]*# ===== TerminalStyles END =====\s*$'
            @(script:Baks).Count | Should -Be 1 -Because 'a first register keeps one copy'
            script:Hex ([System.IO.File]::ReadAllBytes((script:Baks)[0].FullName)) | Should -BeExactly (script:Hex $fixture)
        }

        It 'keeps them under -Force, which takes no backup' {
            # The path where the loss could not be undone: the first-touch rule
            # is asked about a file that already carries our block, so no copy
            # is taken. The count is asserted first, so the test proves there is
            # no copy to fall back on rather than assuming it.
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            $head = [byte[]]([byte[]]@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes((script:Text)))
            [System.IO.File]::WriteAllBytes($script:p, [byte[]]($head + $utf8.GetBytes("`r`n$script:stale`r`n")))

            Invoke-TerminalStylesRegister -Yes -Force -Targets @((script:Target $true)) 6>&1 | Out-Null

            @(script:Baks).Count | Should -Be 0 -Because 'our block was already in the file'
            $after = [System.IO.File]::ReadAllBytes($script:p)
            script:Head $after $head.Length | Should -BeExactly (script:Hex $head)
            $rest = $utf8.GetString($after, $head.Length, $after.Length - $head.Length)
            $rest | Should -Match 'Import-Module TerminalStyles -DisableNameChecking' -Because 'the block was rewritten'
            $rest.Contains('tstyles.ps1') | Should -BeFalse -Because 'the stale body is gone'
            [regex]::Matches($rest, [regex]::Escape($script:begin)).Count | Should -Be 1
            [regex]::Matches($rest, [regex]::Escape($script:end)).Count   | Should -Be 1
        }

        # No trailing newline in the fixture, so a 0D after the user's last byte
        # can only be the separator the write adds: a register that wrote
        # nothing, or cut the byte, both fail on it.
        It 'keeps the last byte of <Label>, which TrimEnd took for whitespace' -ForEach @(
            @{ Label = 'a-grave (C3 A0)';   Tail = [byte[]]@(0xC3, 0xA0) }
            @{ Label = 'a star (E2 98 85)'; Tail = [byte[]]@(0xE2, 0x98, 0x85) }
        ) {
            # Decoded through ISO-8859-1, 0xA0 is U+00A0 and 0x85 is U+0085, and
            # String.TrimEnd() counts both as whitespace.
            $fixture = [byte[]]([System.Text.Encoding]::ASCII.GetBytes('# voil') + $Tail)
            [System.IO.File]::WriteAllBytes($script:p, $fixture)

            Invoke-TerminalStylesRegister -Yes -Targets @((script:Target $false)) 6>&1 | Out-Null

            $after = [System.IO.File]::ReadAllBytes($script:p)
            script:Head $after $fixture.Length | Should -BeExactly (script:Hex $fixture)
            $after.Length | Should -BeGreaterThan $fixture.Length -Because 'the block was added'
            $after[$fixture.Length] | Should -Be 0x0D
            (Get-RcFileEncoding).GetString($after) | Should -Match ([regex]::Escape($script:begin))
        }

        It 'keeps a trailing star on -Force, where the block moves and no backup is taken' {
            # The user's last line sits AFTER our block, so -Force strips the
            # block, trims, and appends it again below that line.
            $fixture = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("# mine`r`n$script:stale`r`n# voil") +
                                [byte[]]@(0xE2, 0x98, 0x85))
            [System.IO.File]::WriteAllBytes($script:p, $fixture)

            Invoke-TerminalStylesRegister -Yes -Force -Targets @((script:Target $true)) 6>&1 | Out-Null

            @(script:Baks).Count | Should -Be 0
            $text = (Get-RcFileEncoding).GetString([System.IO.File]::ReadAllBytes($script:p))
            $line = '# voil' + [char]0xE2 + [char]0x98 + [char]0x85 + "`r`n"
            # Ordinal: these are control characters, which a culture-aware
            # search may skip over.
            $at = $text.IndexOf($line, [System.StringComparison]::Ordinal)
            $at | Should -BeGreaterOrEqual 0 -Because 'the star is kept, and the separator comes after it'
            $text.Contains('tstyles.ps1') | Should -BeFalse
            $text.IndexOf($script:begin, [System.StringComparison]::Ordinal) | Should -BeGreaterThan $at `
                -Because 'the block moved below the user''s last line, so the write ran'
        }
    }
}

Describe 'register backs up the pristine $PROFILE, once' {
    # The three cases install.ps1's half has had pinned since 0.8.18
    # (tests/Install-Hardening.Tests.ps1) and the module half never did, plus the
    # fourth shape that showed the same one-line defect pointing the other way.
    #
    # Save-FirstTouchBackup was called with the POST-STRIP content and with the
    # bare BEGIN marker as the "already ours" pattern. Both arguments were wrong:
    #
    #   * -Force strips our block out of the string BEFORE the rule is asked, so
    #     on a profile that already carries one the rule saw a file it had never
    #     touched and copied it AGAIN -- a fresh <profile>.bak-<timestamp> on
    #     every run, measured as four copies from four runs, against a CHANGELOG
    #     entry (0.8.18) that says "Re-running does not pile up backups". Only
    #     the oldest is the pristine copy, and nothing says which that is.
    #   * A $PROFILE carrying an orphan BEGIN and no END matched the bare marker,
    #     so the rule called it "already ours" and skipped the copy -- on the one
    #     shape where the write is a rewrite of a file we do not understand.
    #
    # Counted with -Force on Get-ChildItem for the reason CLAUDE.md gives: on
    # Unix a hidden or dot-prefixed fixture comes back as nothing without it, and
    # the count then compares 0 to 0 while measuring nothing.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null
            $script:p = Join-Path $script:d 'fake-profile.ps1'
            $script:begin = '# ===== TerminalStyles BEGIN ====='
            $script:end   = '# ===== TerminalStyles END ====='

            function script:Baks {
                @(Get-ChildItem -LiteralPath $script:d -Filter 'fake-profile.ps1.bak-*' -Force)
            }
            function script:Target {
                [pscustomobject]@{ Label = 'PowerShell 7'; ProfilePath = $script:p
                                   Exists = (Test-Path -LiteralPath $script:p); HasLoader = $false }
            }
        }

        It 'takes no backup of a $PROFILE that did not exist' {
            Invoke-TerminalStylesRegister -Yes -Targets @((script:Target)) 6>&1 | Out-Null
            [System.IO.File]::ReadAllText($script:p) | Should -Match 'TerminalStyles BEGIN'
            @(script:Baks).Count | Should -Be 0 -Because 'there was nothing of the user''s to keep'
        }

        It 'takes exactly one backup, of the file as the user left it' {
            [System.IO.File]::WriteAllText($script:p, "# my own prompt`r`nSet-Alias ll Get-ChildItem`r`n",
                [System.Text.UTF8Encoding]::new($false))

            Invoke-TerminalStylesRegister -Yes -Targets @((script:Target)) 6>&1 | Out-Null

            @(script:Baks).Count | Should -Be 1
            $copy = [System.IO.File]::ReadAllText((script:Baks)[0].FullName)
            $copy | Should -Match 'my own prompt'
            $copy | Should -Not -Match 'TerminalStyles BEGIN' `
                -Because 'the pristine version is the one the user would want back'
        }

        It 'does not pile up a new backup on every -Force' {
            [System.IO.File]::WriteAllText($script:p, "# my own prompt`r`nSet-Alias ll Get-ChildItem`r`n",
                [System.Text.UTF8Encoding]::new($false))
            Invoke-TerminalStylesRegister -Yes -Targets @((script:Target)) 6>&1 | Out-Null
            @(script:Baks).Count | Should -Be 1 -Because 'the fixture must start from one copy'

            # The stamp is to the SECOND, and Copy-Item -Force overwrites: two
            # backups inside one second are indistinguishable from one, so this
            # has to wait or it passes on the unfixed code while measuring
            # nothing.
            Start-Sleep -Milliseconds 1100
            $out = Invoke-TerminalStylesRegister -Yes -Force -Targets @((script:Target)) 6>&1 | Out-String

            @(script:Baks).Count | Should -Be 1 `
                -Because 'our block is already in the file, so a fresh copy captures a file that carries it'
            $out | Should -Not -Match 'Backed up your existing' `
                -Because 'the line and the write are the same claim'
            [System.IO.File]::ReadAllText($script:p) | Should -Match 'my own prompt'
        }

        It 'refuses a $PROFILE carrying a BEGIN with no END, and leaves it alone' {
            # Register-ShellLoader calls this 'malformed' and refuses; this half
            # had no such arm, so it appended a SECOND complete block below the
            # orphan marker -- and took no backup on the way, because the bare
            # marker read as "already ours".
            $before = "# my hand-written profile`r`nSet-Alias ll Get-ChildItem`r`n$script:begin`r`nImport-Module TerminalStyles`r`n"
            [System.IO.File]::WriteAllText($script:p, $before, [System.Text.UTF8Encoding]::new($false))
            $bytes = [System.IO.File]::ReadAllBytes($script:p)

            $out = Invoke-TerminalStylesRegister -Yes -Targets @((script:Target)) 6>&1 | Out-String

            $out | Should -Match 'no matching END'
            $out | Should -Match 'by hand'
            $out | Should -Match 'Not registered in'
            $out | Should -Not -Match 'Registered in ' -Because 'nothing was written'
            $out | Should -Not -Match 'auto-load on every new shell tab'

            [System.IO.File]::ReadAllBytes($script:p) | Should -Be $bytes `
                -Because 'a file we do not understand is not one to rewrite'
            ([regex]::Matches([System.IO.File]::ReadAllText($script:p),
                              [regex]::Escape($script:begin))).Count | Should -Be 1 `
                -Because 'appending a second block leaves two markers we cannot tell apart'
        }

        It 'still refuses under -Force' {
            # -Force is "replace our block", not "write over anything". The
            # strip's own pattern does not match here, so -Force would rewrite
            # the file with the orphan still in it.
            $before = "# mine`r`n$script:begin`r`nImport-Module TerminalStyles`r`n"
            [System.IO.File]::WriteAllText($script:p, $before, [System.Text.UTF8Encoding]::new($false))
            $bytes = [System.IO.File]::ReadAllBytes($script:p)

            Invoke-TerminalStylesRegister -Yes -Force -Targets @((script:Target)) 6>&1 | Out-Null

            [System.IO.File]::ReadAllBytes($script:p) | Should -Be $bytes
        }
    }
}

Describe 'register asks about each $PROFILE once, however many engines report it' {
    # Two engines can share one $PROFILE -- off Windows the pair probed for is
    # `pwsh` and `pwsh-preview`, and on a Mac carrying the 7-preview build both
    # answer with the same path. Uninstall was de-duplicated when its strip moved
    # into lib/update.ps1; register kept its own open-coded discovery loop, so it
    # listed one file on two rows, asked consent for "2 PowerShell profile
    # file(s)", and wrote that file twice.
    #
    # -Targets cannot exercise this: that seam BYPASSES the discovery loop where
    # the bug lives, so a test built on it passes before and after. These drive
    # the real loop through STAND-IN engines: Get-Command hands back an
    # ExternalScriptInfo for a .ps1 path, and `& $cmd.Source -NoProfile
    # -NonInteractive -Command '<one string>'` binds to its param block exactly
    # as a real engine's command line does. Nothing here launches pwsh, and no
    # path leaves TestDrive.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:d = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:d -Force | Out-Null

            function script:New-StubEngine {
                param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Answers)
                $path = Join-Path $script:d "$Name.ps1"
                $src = @'
param([switch]$NoProfile, [switch]$NonInteractive, [string]$Command)
if ($Command -match 'PROFILE=') {
    Write-Output ('PROFILE=' + '__P__')
    Write-Output 'POLICY=RemoteSigned'
} else {
    Write-Output '__P__'
}
'@.Replace('__P__', $Answers)
                [System.IO.File]::WriteAllText($path, $src, [System.Text.UTF8Encoding]::new($false))
                # A stub Get-Command cannot resolve would make the discovery
                # return nothing, which some of these assertions would read as a
                # pass. Fail here, where the reason is legible.
                if (-not (Get-Command -Name $path -ErrorAction SilentlyContinue)) {
                    throw "Stub engine '$path' is not resolvable by Get-Command on this platform."
                }
                $path
            }
        }

        It 'merges two engines that report one file into one target' {
            $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
            $a = script:New-StubEngine -Name 'engine-a' -Answers $shared
            $b = script:New-StubEngine -Name 'engine-b' -Answers $shared
            Mock Get-PowerShellEngineCandidate {
                @([pscustomobject]@{ Exe = $a; Label = 'PowerShell 7' },
                  [pscustomobject]@{ Exe = $b; Label = 'PowerShell 7 (preview)' })
            }

            $t = @(Resolve-PowerShellProfileTarget -IncludeMissing)

            $t.Count | Should -Be 1 -Because 'it is one file'
            $t[0].ProfilePath | Should -Be $shared
            @($t[0].Labels) | Should -Be @('PowerShell 7', 'PowerShell 7 (preview)')
            $t[0].Label | Should -Be 'PowerShell 7 / PowerShell 7 (preview)' `
                -Because 'the row must name every engine that loads out of it'
        }

        It 'keeps two engines with genuinely separate profiles apart' {
            # The Windows shape, which must not regress into one row.
            $pa = Join-Path $script:d 'a-profile.ps1'
            $pb = Join-Path $script:d 'b-profile.ps1'
            $a = script:New-StubEngine -Name 'engine-a' -Answers $pa
            $b = script:New-StubEngine -Name 'engine-b' -Answers $pb
            Mock Get-PowerShellEngineCandidate {
                @([pscustomobject]@{ Exe = $a; Label = 'PowerShell 7' },
                  [pscustomobject]@{ Exe = $b; Label = 'Windows PowerShell 5.1' })
            }

            $t = @(Resolve-PowerShellProfileTarget -IncludeMissing)

            $t.Count | Should -Be 2
            @($t | ForEach-Object { $_.ProfilePath }) | Should -Be @($pa, $pb)
        }

        It 'only offers files that exist unless asked for the missing ones' {
            # The difference between the removal half and the registration half,
            # and the reason this could not simply be reused as-is.
            $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
            $a = script:New-StubEngine -Name 'engine-a' -Answers $shared
            Mock Get-PowerShellEngineCandidate { @([pscustomobject]@{ Exe = $a; Label = 'PowerShell 7' }) }

            @(Resolve-PowerShellProfileTarget).Count | Should -Be 0 `
                -Because 'a $PROFILE that was never created has no block in it'
            @(Resolve-PowerShellProfileTarget -IncludeMissing).Count | Should -Be 1 `
                -Because 'registration has to be able to create one'
        }

        It 'lists one row and asks consent for one file' {
            # The consumer, end to end, with consent REFUSED: this is the screen
            # the user reads, and on this machine it showed the same path twice.
            $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
            $a = script:New-StubEngine -Name 'engine-a' -Answers $shared
            $b = script:New-StubEngine -Name 'engine-b' -Answers $shared
            Mock Get-PowerShellEngineCandidate {
                @([pscustomobject]@{ Exe = $a; Label = 'PowerShell 7' },
                  [pscustomobject]@{ Exe = $b; Label = 'PowerShell 7 (preview)' })
            }
            Mock Confirm-Action { $false }

            $out = Invoke-TerminalStylesRegister 6>&1 | Out-String

            ([regex]::Matches($out, [regex]::Escape($shared))).Count | Should -Be 1 `
                -Because 'one file is one row'
            Should -Invoke Confirm-Action -Times 1 -Exactly -ParameterFilter {
                $Consequence -match 'writes the loader block into 1 PowerShell profile file\(s\)'
            }
            Test-Path -LiteralPath $shared | Should -BeFalse -Because 'consent was refused'
        }

        It 'writes the shared file once' {
            $shared = Join-Path $script:d 'Microsoft.PowerShell_profile.ps1'
            [System.IO.File]::WriteAllText($shared, "# my own prompt`r`n", [System.Text.UTF8Encoding]::new($false))
            $a = script:New-StubEngine -Name 'engine-a' -Answers $shared
            $b = script:New-StubEngine -Name 'engine-b' -Answers $shared
            Mock Get-PowerShellEngineCandidate {
                @([pscustomobject]@{ Exe = $a; Label = 'PowerShell 7' },
                  [pscustomobject]@{ Exe = $b; Label = 'PowerShell 7 (preview)' })
            }

            $out = Invoke-TerminalStylesRegister -Yes 6>&1 | Out-String

            $after = [System.IO.File]::ReadAllText($shared)
            ([regex]::Matches($after, [regex]::Escape('# ===== TerminalStyles BEGIN ====='))).Count |
                Should -Be 1
            ([regex]::Matches($out, 'Registered in ')).Count | Should -Be 1 `
                -Because 'one write is one line'
            @(Get-ChildItem -LiteralPath $script:d -Filter 'Microsoft.PowerShell_profile.ps1.bak-*' -Force).Count |
                Should -Be 1 -Because 'one file, one first touch'
        }
    }
}

Describe 'register and install.ps1 agree on what a loader line looks like' {
    # install.ps1 is fetched and piped to iex before the module exists, so it
    # cannot dot-source lib/ and the two loader forms are necessarily written
    # twice. They must not drift: register uses the installer's BEGIN/END
    # markers, so whichever runs last wins, and a mismatch means one of them
    # silently replaces a working loader with a broken one.
    BeforeAll {
        $script:repoRoot   = Split-Path $PSScriptRoot -Parent
        $script:installSrc = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install.ps1'))
        $script:updateSrc  = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'lib/update.ps1'))
    }

    It 'the Windows form in install.ps1 also appears in register' {
        $win = 'Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking'
        $script:installSrc | Should -BeLike "*$win*" -Because 'this test is anchored on the installer'
        $script:updateSrc  | Should -BeLike "*$win*" -Because 'register must write what the installer writes'
    }

    It 'both build the non-Windows form from a resolved path to TerminalStyles.psd1' {
        $shape = 'Import-Module "{0}" -DisableNameChecking'
        $script:installSrc | Should -BeLike "*$shape*"
        $script:updateSrc  | Should -BeLike "*$shape*" `
            -Because 'off Windows there is no %LOCALAPPDATA% equivalent, so the absolute path is baked in'
    }
}
