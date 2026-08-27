# Pester 5 tests for the picker's behaviour off Windows Terminal.
#
# Every case here is a bug that shipped in 0.8.0. The picker is a keyboard UI,
# so the Windows CI legs never exercised its non-WT branch at all -- the crash
# below reached users with all four legs green.
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

Describe 'picker guards on a non-console session' {
    InModuleScope TerminalStyles {
        It 'explains itself instead of throwing .NET console internals' {
            # Regression: the picker drew its whole menu, then died on
            # [Console]::KeyAvailable with "Cannot see if a key has been pressed
            # ... Try Console.In.Peek". Anything running tstyles with stdin
            # detached -- a pipe, a redirect, a CI step, an agent shell -- hit it.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Invoke-FontFirstRunPrompt {}
            Mock Write-Host {}
            # Clear-Host must NOT run: the guard returns before the picker takes
            # over the screen, so the user's scrollback survives.
            Mock Clear-Host { throw 'the picker must not clear the screen before bailing out' }
            Mock Invoke-StylePickerLoop { throw 'the picker loop must not start without a console' }

            if ([Console]::IsInputRedirected) {
                { Invoke-TerminalStyle } | Should -Not -Throw
                Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'needs an interactive terminal' }
            } else {
                Set-ItResult -Skipped -Because 'this test run has a real console attached'
            }
        }
    }
}

Describe 'picker background handling off Windows Terminal' {
    # These two Describes used to assert only that Get-TerminalCapability and
    # Get-TerminalDisplayName return what Get-TerminalCapability.Tests.ps1
    # already pins -- nothing in either reached the picker, so restoring the
    # exact 0.8.0 regressions left them green.
    #
    # The picker's non-WT branch cannot be driven from a test: it needs a real
    # console, and returns early the moment [Console]::IsInputRedirected is true
    # (which is what the first Describe in this file covers). So these are shape
    # assertions -- but on the AST, pinned to the expressions that carry the
    # decision, rather than on whether a string appears anywhere in the file.
    BeforeAll {
        $script:pickerFn = InModuleScope TerminalStyles {
            (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
        }
        function script:Get-AssignmentRhs {
            param([Parameter(Mandatory)][string]$Name)
            $a = @($script:pickerFn.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq $Name }, $true))
            if (-not $a) { return $null }
            $a[0].Right.Extent.Text
        }
    }

    It 'derives the prefetch decision from the terminal, not from a constant' {
        # The regression is a one-word edit: $wantsBackgrounds = $true. The
        # picker then downloads a GIF per style from the gifs branch on a
        # terminal that can never paint one -- megabytes over the network, and a
        # "...fetching background" row beside every entry. Terminal.app CAN show
        # a background image, but only through a profile, never in the window the
        # picker is previewing in.
        $rhs = script:Get-AssignmentRhs -Name '$wantsBackgrounds'
        $rhs | Should -Not -BeNullOrEmpty -Because '$wantsBackgrounds must exist'
        $rhs | Should -Match 'Get-TerminalCapability[^\n]*BackgroundImage' `
            -Because 'it must be asked of the terminal, not hardcoded'
    }

    It 'gates the prefetch loop on it' {
        # Without the gate the download happens regardless of what the flag says.
        $gated = @($script:pickerFn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -match '^\$wantsBackgrounds$' -and
            $n.Clauses[0].Item2.Extent.Text -match 'Test-StyleResolved' }, $true))
        @($gated).Count | Should -BeGreaterThan 0 `
            -Because 'the Test-StyleResolved sweep that builds $missingPaths must sit inside if ($wantsBackgrounds)'
    }

    It 'does not treat a missing background as unresolved when none can be shown' {
        # The row-state half. A bare Test-StyleResolved here prints
        # "...fetching background" next to every style forever, describing work
        # that is deliberately never done.
        #
        # Scoped to $drawMenu deliberately. There is a SECOND $resolved a few
        # lines below, inside the `if (-not $useSettingsFile) { return }` arm --
        # so it only runs on Windows Terminal, where a bare Test-StyleResolved is
        # the correct thing. Taking "the first $resolved in the function" would
        # pass or fail on source order rather than on meaning.
        $draw = @($script:pickerFn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$drawMenu' }, $true))
        @($draw).Count | Should -Be 1 -Because 'the menu is drawn from one scriptblock'

        $rows = @($draw[0].FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$resolved' }, $true))
        @($rows).Count | Should -Be 1 -Because 'the row state is decided in one place'

        $rhs = $rows[0].Right.Extent.Text
        $rhs | Should -Match '-not\s+\$wantsBackgrounds' `
            -Because 'where no background can be shown, every style is ready the moment it is listed'
        $rhs | Should -Match 'Test-StyleResolved' `
            -Because 'and where one can, the swatch still waits for the file'
    }
}

Describe 'picker header target label' {
    BeforeAll {
        $script:pickerFn = InModuleScope TerminalStyles {
            (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
        }
    }

    It 'names the terminal when there is no profile to name' {
        # Off Windows Terminal $Target is empty, and the header read
        # "Choose a style for ''", which looks like a bug in the tool. The label
        # must therefore be a CHOICE -- the quoted profile name only where there
        # is a settings file to name, the terminal's own name otherwise.
        $a = @($script:pickerFn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$pickerTargetLabel' }, $true))
        @($a).Count | Should -BeGreaterThan 0

        $rhs = $a[0].Right.Extent.Text
        $rhs | Should -Match 'Get-TerminalDisplayName' `
            -Because 'with no profile to name, the header names the terminal'
        $rhs | Should -Match '\$useSettingsFile' `
            -Because 'the quoted profile name is only correct where a settings file exists'
    }

    It 'and the name it falls back to is a real one' {
        InModuleScope TerminalStyles {
            Get-TerminalDisplayName -Kind 'AppleTerminal' | Should -Be 'Terminal.app'
        }
    }
}

Describe 'OSC packet is available before the picker paints' {
    InModuleScope TerminalStyles {
        It 'builds a packet from a scheme without needing the per-key cache' {
            # The 0.8.0 crash: the initial paint indexed $oscPackets, which is
            # populated ~50 lines further down for the per-keystroke path and was
            # still $null -- "Cannot index into a null array", before a single
            # row was drawn. The fix builds that one packet from $schemes, so
            # this must work standing alone.
            $scheme = [System.IO.File]::ReadAllText(
                (Join-Path (Get-StyleDir -StyleName 'eva') 'scheme.json'),
                [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $packet = Get-SchemeOscPacket -Scheme $scheme
            $packet | Should -Not -BeNullOrEmpty
            $packet | Should -Match ([regex]::Escape("$([char]27)]11;"))
        }
    }
}

Describe 'Terminal.app profile generation' {
    InModuleScope TerminalStyles {
        # The -Skip: conditions here and in the Describe below are spelled out
        # inline on purpose. A -Skip: is evaluated during discovery, so a flag
        # assigned in a BeforeAll -- which does not run until the *run* phase --
        # is still $null when the skip is decided, and the test is skipped on
        # every platform, macOS included. These four cases sat green-but-never-
        # run that way from 0.8.2 through 0.8.4, across the whole Terminal.app
        # feature. Hoisting the flags to BeforeDiscovery is not enough either:
        # inside InModuleScope a $script: variable resolves against the module's
        # scope, not this file's.
        It 'builds NSColor archives Terminal can unarchive' -Skip:(-not ($IsMacOS -and (Get-Command osascript -ErrorAction SilentlyContinue))) {
            # Each color must be an NSKeyedArchiver archive of an NSColor. A bare
            # value here makes Terminal reject the ENTIRE profile as "corrupt",
            # naming no key -- so this is worth pinning.
            $scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            $data = Get-AppleTerminalProfileData -Scheme $scheme
            $data | Should -Not -BeNullOrEmpty
            $data.ContainsKey('BackgroundColor') | Should -BeTrue
            # Decodes as a plist whose archiver is NSKeyedArchiver.
            $bytes = [Convert]::FromBase64String($data['BackgroundColor'])
            $bytes.Length | Should -BeGreaterThan 100
            [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Match 'NSKeyedArchiver'
        }

        It 'maps the scheme purple slot to Terminal magenta' {
            # scheme.json calls it "purple"; Terminal calls it ANSIMagentaColor.
            # Getting this wrong swaps two palette entries silently.
            $script:TStylesAppleColorMap['purple']       | Should -Be 'ANSIMagentaColor'
            $script:TStylesAppleColorMap['brightPurple'] | Should -Be 'ANSIBrightMagentaColor'
        }

        It 'covers all 16 ANSI slots plus fg/bg/cursor/selection' {
            @($script:TStylesAppleColorMap.Keys).Count | Should -Be 20
        }

        It 'writes a valid plist profile' -Skip:(-not ($IsMacOS -and (Get-Command osascript -ErrorAction SilentlyContinue))) {
            $scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            $out = Join-Path $TestDrive 'test.terminal'
            $p = New-AppleTerminalProfile -StyleName 'test' -Scheme $scheme -OutPath $out
            $p | Should -Not -BeNullOrEmpty
            $content = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
            # 'Window Settings' is what marks it importable; without it Terminal
            # opens the file as a document instead of applying it.
            $content | Should -Match '<key>type</key>'
            $content | Should -Match 'Window Settings'
            $content | Should -Match '<data>'
        }
    }
}

Describe 'Terminal.app background image format' {
    InModuleScope TerminalStyles {
        # Inline -Skip: for the same reason as the Describe above: a BeforeAll
        # flag is still $null when discovery decides the skip.
        It 'leaves a static image alone' {
            $png = Join-Path $TestDrive 'bg.png'
            [System.IO.File]::WriteAllBytes($png, [byte[]](1,2,3))
            ConvertTo-AppleTerminalBackground -Path $png | Should -Be $png
        }

        It 'returns the original when the file does not exist' {
            $missing = Join-Path $TestDrive 'nope.gif'
            ConvertTo-AppleTerminalBackground -Path $missing | Should -Be $missing
        }

        It 'converts an animated GIF to a still PNG' -Skip:(-not ($IsMacOS -and (Get-Command sips -ErrorAction SilentlyContinue))) {
            # Terminal.app renders a still image but NOT an animated GIF -- a
            # profile pointing at one gets a blank background with no error
            # anywhere. Every bundled background in this project is a GIF, so
            # without this the whole feature silently does nothing.
            $src = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/screenshots/eva.png'
            $gif = Join-Path $TestDrive 'bg.gif'
            & sips -s format gif $src --out $gif *> $null
            if (-not (Test-Path -LiteralPath $gif)) {
                Set-ItResult -Skipped -Because 'could not build a GIF fixture'
                return
            }
            $out = ConvertTo-AppleTerminalBackground -Path $gif
            $out | Should -Not -Be $gif
            $out | Should -Match '\.still\.png$'
            Test-Path -LiteralPath $out | Should -BeTrue
        }

        It 'reuses an existing conversion instead of re-running sips' -Skip:(-not ($IsMacOS -and (Get-Command sips -ErrorAction SilentlyContinue))) {
            # This runs on every profile build; re-converting a multi-megabyte
            # GIF each time would be a visible pause.
            $src = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/screenshots/eva.png'
            $gif = Join-Path $TestDrive 'reuse.gif'
            & sips -s format gif $src --out $gif *> $null
            if (-not (Test-Path -LiteralPath $gif)) { Set-ItResult -Skipped -Because 'no GIF fixture'; return }
            $first  = ConvertTo-AppleTerminalBackground -Path $gif
            $stamp  = (Get-Item -LiteralPath $first).LastWriteTimeUtc
            Start-Sleep -Milliseconds 1100
            $second = ConvertTo-AppleTerminalBackground -Path $gif
            $second | Should -Be $first
            (Get-Item -LiteralPath $second).LastWriteTimeUtc | Should -Be $stamp
        }
    }
}

Describe 'appleterminal.js guards' {
    # Both guards in this file used to be inert, and both produced the one shape
    # its own header warns Terminal rejects as "corrupt" while naming no key.
    #
    # -Skip: spelled out inline for the reason documented above: a flag assigned
    # in BeforeAll is still $null when discovery decides the skip.
    InModuleScope TerminalStyles {

        It 'rejects a malformed hex instead of archiving NaN components' -Skip:(-not ($IsMacOS -and (Get-Command osascript -ErrorAction SilentlyContinue))) {
            # parseInt('zz', 16) is NaN, NSColor accepts NaN without complaint,
            # and the archive then carries NSRGB = "nan nan nan". Nothing threw,
            # so the caller's "skip a bad color, keep the rest" catch never fired
            # and the bad color went into the profile.
            $scheme = [pscustomobject]@{ background = '#zzzzzz'; foreground = '#ffe8e8' }
            $data = Get-AppleTerminalProfileData -Scheme $scheme
            if ($data -and $data.ContainsKey('BackgroundColor')) {
                $bytes = [Convert]::FromBase64String($data['BackgroundColor'])
                [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Not -Match 'nan'
            }
            # A valid sibling must still come through.
            $data.ContainsKey('TextColor') | Should -BeTrue
        }

        It 'still archives a valid color unharmed' -Skip:(-not ($IsMacOS -and (Get-Command osascript -ErrorAction SilentlyContinue))) {
            $scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            $data = Get-AppleTerminalProfileData -Scheme $scheme
            $bytes = [Convert]::FromBase64String($data['BackgroundColor'])
            [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Match 'NSKeyedArchiver'
            [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Not -Match 'nan'
        }

        It 'omits the bookmark entirely when the image is missing' -Skip:(-not ($IsMacOS -and (Get-Command osascript -ErrorAction SilentlyContinue))) {
            # A nil ObjC return arrives in JXA as a TRUTHY wrapper, so `!bookmark`
            # was false and `bookmark.length` was undefined -- both halves of the
            # old guard passed nil straight through, and the profile carried a
            # BackgroundImageBookmark archiving nothing.
            $scheme = [pscustomobject]@{ background = '#0a0006'; foreground = '#ffe8e8' }
            $missing = Join-Path $TestDrive 'definitely-not-here.gif'
            $data = Get-AppleTerminalProfileData -Scheme $scheme -BackgroundImage $missing
            $data | Should -Not -BeNullOrEmpty
            $data.ContainsKey('BackgroundImageBookmark') | Should -BeFalse
        }
    }
}
