# Each style carries its own one-line description and quote in meta.json, and
# the picker shows them for the highlighted row.
#
# It lives IN the style rather than in a catalog on purpose. A central list of
# descriptions is a second list of styles, and this project has already paid for
# one: docs/index.html carries a hand-written description per style, and when
# `halo` was removed its entry had to be found and deleted by hand. A file inside
# the folder cannot drift from the folder.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
    $script:StyleDirs = @(Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') -Directory |
                          ForEach-Object { @{ Name = $_.Name; Dir = $_.FullName } })
}
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TerminalStyles.psd1') `
        -Force -DisableNameChecking *> $null
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
}

# NOT wrapped in InModuleScope: -ForEach is evaluated at DISCOVERY, and inside
# InModuleScope `$script:` resolves to the module's scope, where a list built in
# BeforeDiscovery is invisible. The module function is reached per-It instead.
Describe 'every bundled style describes itself' {

    It '<Name> ships a meta.json with a description' -ForEach $script:StyleDirs {
        $m = InModuleScope TerminalStyles { param($d) Get-StyleMeta -StyleDir $d } -Parameters @{ d = $Dir }
        $m.Description | Should -Not -BeNullOrEmpty -Because "$Name is listed in a picker that shows it"
    }

    It '<Name>''s description fits a picker row' -ForEach $script:StyleDirs {
        # The picker truncates rather than wraps -- a description that wrapped
        # would make the frame taller for some styles than others, and the frame
        # is overwritten in place. Truncation is the safety net; this is the cap
        # that keeps it from firing on a normal terminal.
        $m = InModuleScope TerminalStyles { param($d) Get-StyleMeta -StyleDir $d } -Parameters @{ d = $Dir }
        $m.Description.Length | Should -BeLessOrEqual 90 -Because 'an 80-column terminal is the floor'
        $m.Description | Should -Not -Match "`n" -Because 'it is one line, not a paragraph'
    }

    It '<Name>''s quote is a quote, not a second description' -ForEach $script:StyleDirs {
        $m = InModuleScope TerminalStyles { param($d) Get-StyleMeta -StyleDir $d } -Parameters @{ d = $Dir }
        if ($m.Quote) {
            $m.Quote.Length | Should -BeLessOrEqual 70
            $m.Quote | Should -Not -Match "`n"
        }
    }
}

Describe 'Get-StyleMeta degrades instead of throwing' {
    InModuleScope TerminalStyles {

        It 'answers empty for a style that ships no meta.json' {
            # A hand-dropped user style will not have one, and the picker must
            # fall back to the name alone rather than to an error.
            $d = Join-Path $TestDrive 'nometa'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            $m = Get-StyleMeta -StyleDir $d
            $m.Description | Should -BeNullOrEmpty
            $m.Quote       | Should -BeNullOrEmpty
        }

        It 'answers empty for a meta.json that is not valid JSON' {
            $d = Join-Path $TestDrive 'badmeta'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'meta.json'), '{ not json',
                [System.Text.UTF8Encoding]::new($false))
            { Get-StyleMeta -StyleDir $d } | Should -Not -Throw
            (Get-StyleMeta -StyleDir $d).Description | Should -BeNullOrEmpty
        }

        It 'answers empty for a directory that is not there at all' {
            { Get-StyleMeta -StyleDir (Join-Path $TestDrive 'absent') } | Should -Not -Throw
        }
    }
}

Describe 'the picker shows what a style is, and which one is applied' {
    InModuleScope TerminalStyles {
        BeforeAll { $script:picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.ToString() }

        It 'reads the description for the highlighted row' {
            # Structural because the picker body needs a console and a keypress
            # loop no test can drive -- the same reason the viewport and frame
            # budget were carved out as pure functions, which these tests DO drive.
            $script:picker | Should -Match 'Get-StyleMeta -StyleDir \$styles\[\$idx\]\.FullName'
        }

        It 'marks the applied style separately from the cursor' {
            # Two different facts. '>' is where the cursor is; '*' is what is
            # actually applied -- the same mark `tstyles list` uses. They part
            # company the moment you press Down, and the picker used to stop
            # telling you what Esc would return you to.
            $script:picker | Should -Match '\$i -eq \$currentIdx'
            $script:picker | Should -Match "'   > '"
        }

        It 'truncates the description rather than wrapping it' {
            $script:picker | Should -Match '\$room'
            $script:picker | Should -Match '0x2026' -Because 'a cut line says so with an ellipsis'
        }

        It 'buys both rows in the frame budget, always' {
            # The quote row is blank for the seven styles without one. Painting it
            # anyway is what keeps the frame the same height on every redraw; the
            # budget has to match.
            (Get-PickerFramePlan -Total 5 -Selected 0 -WindowHeight 40).ChromeRows |
                Should -Be 10 -Because 'eight rows of chrome plus the description and quote rows'
        }
    }
}

Describe 'the docs site stays in step with the styles that exist' {

    # The drift this catches has already happened twice over. docs/index.html
    # carries its own description per style, written separately from the README
    # -- and they had diverged: the site called sober "Minimalist monochrome.
    # Grayscale with one subtle teal accent, no banner, single-line prompt" while
    # its README said "The quiet one." Nothing compared them, so nothing noticed.
    #
    # And when `halo` was removed, its entry in this file had to be found and
    # deleted by hand; a catalog keyed by style name is a second list of styles,
    # and a second list goes stale. meta.json cannot, because it lives in the
    # folder. What is left to guard is the copy that does not.
    #
    # The prose is NOT asserted equal: the site has room for a longer sentence
    # than a picker row, and requiring one wording for both would be inventing a
    # rule to make a test pass. What must hold is the SET.

    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $html = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'docs/index.html'),
                    [System.Text.UTF8Encoding]::new($false))
        $m = [regex]::Match($html, '(?m)^const STYLES = (\[.*?\]);$')
        $script:siteStyles = if ($m.Success) { @(($m.Groups[1].Value | ConvertFrom-Json) | ForEach-Object { $_.n }) } else { @() }
        $i = [regex]::Match($html, '(?m)^const IMG = (\{.*?\});$')
        $script:siteImg = if ($i.Success) { @(($i.Groups[1].Value | ConvertFrom-Json).PSObject.Properties.Name) } else { @() }
        $script:onDisk = @(Get-ChildItem (Join-Path $script:repoRoot 'styles') -Directory | ForEach-Object { $_.Name })
    }

    It 'parses, or the two assertions below are comparing nothing' {
        @($script:siteStyles).Count | Should -BeGreaterThan 5
        @($script:onDisk).Count     | Should -BeGreaterThan 5
    }

    It 'lists exactly the styles that exist' {
        $missing = @($script:onDisk    | Where-Object { $script:siteStyles -notcontains $_ })
        $extra   = @($script:siteStyles | Where-Object { $script:onDisk     -notcontains $_ })
        ($missing -join ', ') | Should -BeNullOrEmpty -Because 'a style the site never mentions is invisible to anyone reading it'
        ($extra   -join ', ') | Should -BeNullOrEmpty -Because 'a style the site still advertises is one a reader cannot install'
    }

    It 'has an image for exactly those styles too' {
        # Two keyed collections in the same file, so two chances to go stale.
        $missing = @($script:onDisk | Where-Object { $script:siteImg -notcontains $_ })
        $extra   = @($script:siteImg | Where-Object { $script:onDisk -notcontains $_ })
        ($missing -join ', ') | Should -BeNullOrEmpty
        ($extra   -join ', ') | Should -BeNullOrEmpty
    }
}
