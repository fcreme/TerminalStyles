# Pester 5 tests: the picker may not write settings.json for a style that has
# nothing to put there.
#
# THE RULE, already established twice. Merge-StyleIntoSettings returns the
# settings object UNTOUCHED for a style with a scheme.json and no theme.json --
# deliberately, because a colour scheme is only reachable through a profile's
# colorScheme key, which theme.json carries. Writing the returned object anyway
# is NOT a no-op: it re-serializes what ConvertFrom-WTJson parsed, which drops
# every // and /* */ comment and every trailing comma the user wrote. So the
# caller has to ask Get-StyleSettingsPayload FIRST. Apply-StyleDirect asks;
# apply.ps1 asks; 0.8.18's CHANGELOG says "all four write paths -- the direct
# apply, the picker, the tuner and apply.ps1 -- now check first and say plainly
# that nothing was written."
#
# The picker never did. It held three open-coded copies of ConvertFrom-WTJson ->
# Merge-StyleIntoSettings -> ConvertTo-Json -> write, and Get-StyleSettingsPayload
# had exactly three references in the whole repo, none of them in tstyles.ps1 and
# none in tests/. A style directory with scheme.json and no theme.json is legal
# (README documents theme.json as optional) and Get-AvailableStyles admits it on
# scheme.json existing, so it is listed and selectable. `tstyles aaa-schemeonly`
# refused it in as many words and left settings.json byte-identical; `tstyles`
# and Enter on the SAME style stripped every comment out of settings.json, wrote
# nothing of the style, printed "Style applied: aaa-schemeonly" in green with no
# qualifier, and recorded it -- so `tstyles current` and the `*` in `tstyles
# list` both named a style Windows Terminal had never been told about. The
# load-bearing copy was the FIRST preview, which fires as the picker opens,
# before a key is pressed.
#
# WHY THESE TESTS HAVE THIS SHAPE. The picker body cannot be driven by a test:
# it returns early on [Console]::IsInputRedirected / IsOutputRedirected, which
# are .NET statics and true under Pester. So the decision was carved out into
# Get-StylePreviewJson in lib/picker.ps1 -- the same reason Invoke-StylePickerLoop
# and Get-PickerViewport live there -- and the behavioural half below drives that
# for real. The structural half then pins the rule for every OTHER caller,
# because what actually went wrong here is that a function was added in 0.8.18
# with three of its four intended callers wired up and nothing anywhere held the
# fourth.
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

Describe 'Get-StylePreviewJson decides whether the picker writes at all' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive

            # A settings.json in the shape the picker actually reads: the byte-
            # exact source text, carrying the comments that are the thing at
            # risk. JSONC -- which is what Windows Terminal ships and what
            # ConvertFrom-WTJson exists to parse.
            $script:live = @'
{
    // My Windows Terminal settings -- hand-tuned, do not lose me!
    "profiles": { "list": [ { "name": "PowerShell", "guid": "{x}" } ] },
    "schemes": []
}
'@

            # scheme.json and NO theme.json. Legal per README, and nothing for
            # Windows Terminal.
            $script:schemeOnly = Join-Path $TestDrive 'styles/aaa-schemeonly'
            New-Item -ItemType Directory -Path $script:schemeOnly -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:schemeOnly 'scheme.json'),
                '{"name":"aaa-schemeonly","background":"#101010","foreground":"#e0e0e0"}',
                [System.Text.UTF8Encoding]::new($false))

            # The control: the same fixture WITH a theme.json. Without this the
            # test below would pass just as well against a helper that returned
            # $null for everything, which is a fix that breaks the picker
            # outright.
            $script:full = Join-Path $TestDrive 'styles/zzz-full'
            New-Item -ItemType Directory -Path $script:full -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:full 'scheme.json'),
                '{"name":"zzz-full","background":"#202020","foreground":"#f0f0f0"}',
                [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:full 'theme.json'),
                '{"colorScheme":"zzz-full","cursorShape":"bar"}',
                [System.Text.UTF8Encoding]::new($false))

            # Merge-StyleIntoSettings resolves a bundled background when the
            # caller did not provide one, and its third tier lazily FETCHES from
            # the gifs branch into the cache. Neither fixture ships an image, so
            # $null is the true answer -- mocked so the suite never reaches the
            # network to find that out. (0.8.24: an ordinary suite run used to
            # download a real 3 MB eva.gif this way.)
            Mock Get-StyleBundledBackground { $null }
        }

        It 'returns $null for a style with scheme.json and no theme.json' {
            # $null is how the picker's $writeSettings choke point is told there
            # is nothing to write. Before the fix this returned a full JSON
            # document -- the user's settings re-serialized, comments gone, and
            # not one field of the style in it.
            $json = Get-StylePreviewJson -OriginalJson $script:live -StyleDir $script:schemeOnly `
                        -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            $json | Should -BeNullOrEmpty `
                -Because 'the merge has nothing to merge, so there must be no JSON to write'
        }

        It 'agrees with Get-StyleSettingsPayload rather than deciding for itself' {
            # One rule, one place that knows it. If these two ever disagree the
            # picker and `tstyles <name>` are back to answering differently for
            # the same style, which is the whole defect.
            $payload = Get-StyleSettingsPayload -StyleDir $script:schemeOnly
            $payload.Ok      | Should -BeFalse
            $payload.Missing | Should -Be 'theme.json'
        }

        It 'still builds the full preview for a style that has a theme.json' {
            $json = Get-StylePreviewJson -OriginalJson $script:live -StyleDir $script:full `
                        -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            $json | Should -Not -BeNullOrEmpty

            # Parsed, not string-matched: what matters is that the scheme landed
            # in schemes AND that the profile now points at it, which is the
            # pair that makes a style actually visible.
            $out = $json | ConvertFrom-Json
            @($out.schemes | ForEach-Object { $_.name }) | Should -Contain 'zzz-full'
            $profile = @($out.profiles.list | Where-Object { $_.name -eq 'PowerShell' })[0]
            $profile.colorScheme | Should -Be 'zzz-full'
            $profile.cursorShape | Should -Be 'bar'
        }

        It 'writes nothing for the scheme-only style even under the picker choke point' {
            # The consequence, end to end through the one writer the picker uses.
            # $writeSettings is a scriptblock inside Invoke-TerminalStyle and
            # cannot be reached from here, but its rule is "an empty $Json is a
            # no-op", so this is that rule applied to this helper's answer.
            $path = Join-Path $TestDrive 'settings.json'
            [System.IO.File]::WriteAllText($path, $script:live, [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllBytes($path)

            $json = Get-StylePreviewJson -OriginalJson $script:live -StyleDir $script:schemeOnly `
                        -TargetName 'PowerShell' -BackgroundImage '' -BackgroundImageProvided $false
            if ($json) { Write-SettingsAtomic -Path $path -Json $json }

            [System.IO.File]::ReadAllBytes($path) | Should -Be $before `
                -Because 'a preview with nothing in it must leave the file byte-identical'
            [System.IO.File]::ReadAllText($path) | Should -Match 'hand-tuned, do not lose me'
        }

        It 'and the rewrite it avoids really would have eaten the comments' {
            # The premise, measured rather than asserted from the CHANGELOG: a
            # settings.json that goes through ConvertFrom-WTJson and back out
            # comes back without a single comment. This is why "write the
            # untouched object anyway" is not a harmless no-op, and why the gate
            # has to be in front of the merge rather than after it.
            $script:live | Should -Match 'hand-tuned, do not lose me'
            $roundTripped = ConvertFrom-WTJson $script:live | ConvertTo-Json -Depth 100
            $roundTripped | Should -Not -Match 'hand-tuned, do not lose me'
            $roundTripped | Should -Match '"schemes"' -Because 'it is otherwise the same document'
        }
    }
}

Describe 'every settings.json writer asks first' {
    # The structural half. Get-StyleSettingsPayload was added in 0.8.18 with
    # three of its four intended callers wired up, and nothing anywhere pinned
    # the fourth -- so the picker kept eating comments for six releases while a
    # release note said it did not. This is that release note, as code.

    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent

        # Every file that could hold a writer, not just the ones that do today.
        $script:sourceFiles = @(
            (Join-Path $script:repoRoot 'tstyles.ps1')
            (Join-Path $script:repoRoot 'terminals.ps1')
            (Join-Path $script:repoRoot 'apply.ps1')
            (Join-Path $script:repoRoot 'install.ps1')
        ) + @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'lib') -Filter '*.ps1' |
                ForEach-Object { $_.FullName })

        $script:roots = @{}
        foreach ($p in $script:sourceFiles) {
            $script:roots[$p] = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$null)
        }

        # The scope a call has to be judged in: the innermost function that
        # contains it, or the whole file when the call is at script level
        # (apply.ps1 is a standalone script and has no enclosing function).
        function script:Get-EnclosingScope {
            param($Root, $Node)
            $best = $null
            foreach ($f in $Root.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                if ($Node.Extent.StartOffset -ge $f.Extent.StartOffset -and
                    $Node.Extent.EndOffset   -le $f.Extent.EndOffset) {
                    if ($null -eq $best -or $f.Extent.StartOffset -gt $best.Extent.StartOffset) { $best = $f }
                }
            }
            if ($best) { return $best }
            return $Root
        }

        function script:Get-ArgumentText {
            param($CommandAst, [string]$ParameterName)
            $els = @($CommandAst.CommandElements)
            for ($i = 0; $i -lt $els.Count; $i++) {
                $e = $els[$i]
                if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $e.ParameterName -eq $ParameterName) {
                    if ($e.Argument) { return $e.Argument.Extent.Text }
                    if ($i + 1 -lt $els.Count) { return $els[$i + 1].Extent.Text }
                }
            }
            return $null
        }
    }

    It 'is looking at the files it thinks it is' {
        # A parse that silently returned nothing would make every assertion
        # below pass over zero call sites, which is the exact way the swatch
        # guard reported green for its whole life.
        $script:sourceFiles.Count | Should -BeGreaterOrEqual 10
        foreach ($expected in 'tstyles.ps1', 'apply.ps1', 'picker.ps1', 'applystyle.ps1', 'tune.ps1', 'wtsettings.ps1') {
            @($script:sourceFiles | Where-Object { (Split-Path $_ -Leaf) -eq $expected }).Count |
                Should -Be 1 -Because "$expected must be in the scanned set"
        }
        foreach ($p in $script:sourceFiles) {
            $script:roots[$p] | Should -Not -BeNullOrEmpty -Because "$p must parse"
        }
    }

    It 'no scope merges a style into settings.json without asking whether it has anything to write' {
        $total = 0
        $viaPayload = 0
        $viaOwnTheme = 0
        $offenders = @()

        foreach ($p in $script:sourceFiles) {
            $root = $script:roots[$p]
            $merges = @($root.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Merge-StyleIntoSettings' }, $true))

            foreach ($m in $merges) {
                $total++
                $scope = script:Get-EnclosingScope -Root $root -Node $m

                $asks = @($scope.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Get-StyleSettingsPayload' }, $true)).Count -gt 0
                if ($asks) { $viaPayload++; continue }

                # The one legitimate other way to satisfy the rule: be the thing
                # that WROTE the theme.json you are about to merge. The tuner's
                # preview builds a scratch style dir three statements above its
                # merge, so the answer is known without asking. Pinned on that
                # same directory, not excused by name -- a tuner that stopped
                # writing the file would fail here.
                #
                # The WriteAllText wrapper is load-bearing, and was found the
                # hard way: `Join-Path <dir> 'theme.json'` alone also matches
                # somebody READING the file, and the picker reads exactly that
                # path a hundred lines above its merge to pre-load tab titles.
                # A rule that exempts a reader excuses the very call site it
                # exists to catch -- and did, silently, until the reverted-fix
                # run named two offenders where there were three.
                $dir = script:Get-ArgumentText -CommandAst $m -ParameterName 'StyleDir'
                if ($dir -and $scope.Extent.Text -match
                        ("WriteAllText\(\s*\(\s*Join-Path\s+{0}\s+'theme\.json'\s*\)" -f [regex]::Escape($dir))) {
                    $viaOwnTheme++
                    continue
                }

                $offenders += ('{0}:{1} in {2}' -f (Split-Path $p -Leaf),
                               $m.Extent.StartLineNumber,
                               $(if ($scope -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $scope.Name } else { '<script>' }))
            }
        }

        # The offenders first, because the list names the file, line and
        # function and is what a reader needs. The counts follow and are not
        # decoration: an AST walk that found nothing would report an empty
        # offender list and a green tick, which is exactly how the swatch guard
        # compared zero pairs of themes for its whole life. Four callers today
        # -- Get-StylePreviewJson, Apply-StyleDirect, apply.ps1 and the tuner's
        # preview.
        $offenders -join '; ' | Should -BeNullOrEmpty `
            -Because 'a merge that is written out without asking is a settings.json rewrite that can do nothing but delete comments'
        $total | Should -BeGreaterOrEqual 4 -Because 'the walk must actually find the merge call sites'
        $viaPayload  | Should -BeGreaterOrEqual 3 -Because 'the payload check is how most callers satisfy this'
        $viaOwnTheme | Should -BeGreaterOrEqual 1 -Because 'the tuner satisfies it the other way, so that branch is live'
        ($viaPayload + $viaOwnTheme) | Should -Be $total
    }

    It 'the picker goes through the one helper rather than merging inline again' {
        # Three inline copies is how the check came to be missing from all three.
        $fn = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
        $called = @($fn.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })

        $called | Should -Contain 'Get-StylePreviewJson'
        $called | Should -Not -Contain 'Merge-StyleIntoSettings' `
            -Because 'a fourth inline merge in the picker is how this defect comes back'
    }
}

Describe 'the picker says the same thing the direct path says' {
    # "Every user-facing message is a claim." The picker printed "Style applied:
    # <name>" in green with no qualifier for a style Windows Terminal was never
    # told about, while `tstyles <name>` on the same style said so outright.
    # Pinned on the shared tail of the sentence so the two doors cannot drift
    # into wording that means different things.
    #
    # InModuleScope because Apply-StyleDirect is internal: outside it,
    # Get-Command returns nothing and `$null | Should -Match` is a failure
    # rather than a pass, but a less strict assertion here would have compared
    # nothing at all.
    InModuleScope TerminalStyles {

        It 'both paths carry the same "nothing was written" sentence' {
            $picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast.Extent.Text
            $direct = (Get-Command Apply-StyleDirect).ScriptBlock.Ast.Extent.Text
            $picker | Should -Not -BeNullOrEmpty
            $direct | Should -Not -BeNullOrEmpty

            $direct | Should -Match 'ships no .*so nothing was written to settings\.json' `
                -Because 'this is the sentence the direct path has printed since 0.8.18'
            $picker | Should -Match 'ships no .*so nothing was written to settings\.json' `
                -Because 'the picker must qualify its green success line the same way'
        }

        It 'and the picker still records the style, because off settings.json it really is applied' {
            # Deliberately NOT gated with the write. The prompt, the palette and
            # the shell state are the style's other halves and they were
            # applied; the record is what makes `tstyles current` and the `*` in
            # `tstyles list` work at all, and for a style that ships no
            # profile.ps1 it is the only thing that remembers.
            $picker = (Get-Command Invoke-TerminalStyle).ScriptBlock.Ast
            $called = @($picker.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
            $called | Should -Contain 'Set-CurrentStyleRecord'
        }
    }
}
