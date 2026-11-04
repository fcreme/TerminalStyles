# Pester 5 tests: tab completion quotes a style name the shell would split.
#
# A style is any folder in the styles directory, and only a style the tuner
# CREATES is held to `^[A-Za-z0-9._-]+$` -- a folder the user drops in as
# `My Theme` lists, applies and completes. Both completers inserted the raw
# name, so `tstyles My<Tab>` gave `tstyles My Theme`: two arguments, a style
# called `My`. And a quote typed first (`tstyles 'My<Tab>`) was matched as part
# of the name, so it completed nothing.
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

Describe 'tab completion of style names' {
    BeforeAll {
        # Not InModuleScope: that binds the module instance imported at
        # discovery, and the completers TabExpansion2 calls belong to the one
        # BeforeAll imported, so a sandbox set through it was never what they
        # read. The live instance is Get-Module's; a Pester mock does not reach
        # the completers either, so the styles are real folders in a sandbox.
        $script:mod = Get-Module TerminalStyles
        $script:names = @('My Theme', "it's", 'sober', 'a[1]', 'cost$5')
        $script:complete = {
            param([string]$Line)
            # Not $matches: an automatic variable, replaced by any -match.
            @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches)
        }
    }
    BeforeEach {
        # Saved first, so AfterEach puts back the real root even if a step
        # below throws.
        $script:savedRoot = & $script:mod { $script:TStylesDataRoot }
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $enc = [System.Text.UTF8Encoding]::new($false)
        foreach ($n in $script:names) {
            foreach ($dir in (Join-Path (Join-Path $root 'styles') $n),
                             (Join-Path (Join-Path $root '.deleted') ($n + '-20261101-120000'))) {
                [void][System.IO.Directory]::CreateDirectory($dir)
                [System.IO.File]::WriteAllText((Join-Path $dir 'scheme.json'), '{"name":"x","background":"#101010","foreground":"#f0f0f0"}', $enc)
            }
        }
        & $script:mod { param($r) $script:TStylesDataRoot = $r } $root
        @(& $script:mod { Get-AvailableStyles } | ForEach-Object Name) | Should -Contain 'My Theme' -Because 'the sandbox must be what the completers read'
        @(& $script:mod { Get-StyleTrashEntry } | ForEach-Object StyleName) | Should -Contain 'My Theme'
    }
    AfterEach { & $script:mod { param($r) $script:TStylesDataRoot = $r } $script:savedRoot }

    It 'quotes a name with a space: <Line>' -ForEach @(
        @{ Line = 'tstyles My' }
        @{ Line = "tstyles 'My" }
        @{ Line = 'tstyles "My' }
        @{ Line = 'tstyles delete My' }
        @{ Line = "tstyles delete 'My" }
        @{ Line = 'tstyles restore My' }
    ) {
        $m = & $script:complete $Line
        @($m | Where-Object { $_.ListItemText -eq 'My Theme' }).Count | Should -Be 1 -Because "'My Theme' is offered"
        ($m | Where-Object { $_.ListItemText -eq 'My Theme' }).CompletionText | Should -BeExactly "'My Theme'"
    }

    It 'doubles a single quote inside the name' {
        $m = & $script:complete "tstyles it"
        ($m | Where-Object { $_.ListItemText -eq "it's" }).CompletionText | Should -BeExactly "'it''s'"
    }

    It 'quotes <Name>, which the shell would otherwise read as more than a name' -ForEach @(
        @{ Name = 'cost$5'; Prefix = 'cost' }
    ) {
        $m = & $script:complete "tstyles $Prefix"
        ($m | Where-Object { $_.ListItemText -eq $Name }).CompletionText | Should -BeExactly "'$Name'"
    }

    It 'matches a name with wildcard characters literally' {
        $m = & $script:complete 'tstyles a['
        ($m | Where-Object { $_.ListItemText -eq 'a[1]' }).CompletionText | Should -Not -BeNullOrEmpty
    }

    It 'leaves a plain name bare, and the menu text plain' {
        $m = & $script:complete 'tstyles sob'
        $hit = $m | Where-Object { $_.ListItemText -eq 'sober' }
        $hit.CompletionText | Should -BeExactly 'sober'
        $m = & $script:complete 'tstyles My'
        ($m | Where-Object { $_.CompletionText -eq "'My Theme'" }).ListItemText | Should -BeExactly 'My Theme'
    }

    It 'still offers a plain name when a quote was typed first' {
        $m = & $script:complete "tstyles 'sob"
        @($m | Where-Object { $_.ListItemText -eq 'sober' }).Count | Should -Be 1
    }
}
