# Pester 5 tests: a style's README must describe the style it ships beside.
#
# The 16 bundled styles are the part of this project a reader judges it by, and
# their READMEs are the one thing here that nothing executed. Three claims were
# false and had been for their whole life:
#
#   - kitty and golden-forest both said "No profile.ps1 -- purely visual" while
#     shipping one that sets the window title, replaces function global:prompt,
#     and rewrites PSReadLine's colors. Someone reading that would have no idea
#     why their prompt changed, or that -KeepPrompt is the flag for it.
#   - gitbash documented "#A6A000 yellows" against a scheme whose yellow is
#     #9B961D. Every other hex in that same sentence is a verbatim scheme value,
#     so the one wrong one reads exactly as authoritative as the five right ones.
#
# Both are checkable, so they are checked here rather than by proofreading.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:StyleCases = foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'README.md'))) { continue }
        @{ Name = $dir.Name; Dir = $dir.FullName }
    }
}

Describe 'bundled style READMEs describe what they ship' {

    It '<Name> does not deny a file it ships, or claim one it does not' -ForEach $script:StyleCases {
        $readme = [System.IO.File]::ReadAllText(
            (Join-Path $Dir 'README.md'), [System.Text.UTF8Encoding]::new($false))

        foreach ($file in 'profile.ps1', 'prompt.sh', 'scheme.json', 'theme.json') {
            $onDisk = Test-Path -LiteralPath (Join-Path $Dir $file)
            $escaped = [regex]::Escape($file)
            # "No `profile.ps1`" and friends -- the shape both false claims took.
            $denied = $readme -match ("(?i)\bno\s+``?" + $escaped + "``?")
            if ($onDisk) {
                $denied | Should -BeFalse `
                    -Because "$Name ships $file, so its README must not say it has none"
            }
        }
    }

    It '<Name>''s Includes list names every file it ships' -ForEach $script:StyleCases {
        # Scoped to READMEs that HAVE an "## Includes" section, on purpose. Eight
        # of the sixteen are short prose descriptions that enumerate nothing --
        # they make no claim about the file list, so there is nothing there to be
        # wrong, and requiring one would invent a rule CONTRIBUTING never states.
        #
        # The other eight do enumerate, and that is a claim. kitty's and
        # golden-forest's lists ran scheme.json, theme.json, and then "No
        # profile.ps1 -- purely visual" while shipping a profile.ps1 that rebinds
        # global:prompt. Someone whose prompt changed had that paragraph to read.
        $readme = [System.IO.File]::ReadAllText(
            (Join-Path $Dir 'README.md'), [System.Text.UTF8Encoding]::new($false))
        if ($readme -notmatch '(?m)^##\s+Includes\s*$') {
            Set-ItResult -Skipped -Because "$Name's README enumerates nothing, so it claims nothing"
            return
        }
        $section = [regex]::Match($readme, '(?ms)^##\s+Includes\s*$(.*?)(?=^##\s|\z)').Groups[1].Value
        $section | Should -Not -BeNullOrEmpty

        foreach ($file in 'scheme.json', 'theme.json', 'profile.ps1', 'prompt.sh') {
            if (-not (Test-Path -LiteralPath (Join-Path $Dir $file))) { continue }
            $section | Should -Match ([regex]::Escape($file)) `
                -Because "$Name ships $file, and its README lists what it ships"
        }
    }

    It '<Name> quotes no colour it does not actually use' -ForEach $script:StyleCases {
        $schemePath = Join-Path $Dir 'scheme.json'
        if (-not (Test-Path -LiteralPath $schemePath)) {
            Set-ItResult -Skipped -Because "$Name ships no scheme.json"
            return
        }
        $scheme = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
        $inScheme = @($scheme.PSObject.Properties |
            Where-Object { $_.Value -is [string] -and $_.Value -like '#*' } |
            ForEach-Object { $_.Value.ToLowerInvariant() })

        $readme = [System.IO.File]::ReadAllText(
            (Join-Path $Dir 'README.md'), [System.Text.UTF8Encoding]::new($false))
        foreach ($m in [regex]::Matches($readme, '#[0-9A-Fa-f]{6}\b')) {
            $inScheme | Should -Contain $m.Value.ToLowerInvariant() `
                -Because "$Name's README quotes $($m.Value), which is in no slot of its scheme.json"
        }
    }
}
