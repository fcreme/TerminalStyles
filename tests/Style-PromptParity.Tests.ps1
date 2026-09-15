# Pester 5 tests: a style's PowerShell half and its zsh/bash half must render
# the same prompt.
#
# Every prompt.sh carries a header saying the two are meant to look the same and
# to keep them in sync, and nothing ever checked it. They had drifted in three
# separate ways, all of them invisible on Windows and all of them permanent on
# macOS and Linux:
#
#   * gitbash, neon-rain and umbrella read $env:USERNAME (and gitbash also
#     $env:COMPUTERNAME) -- Windows-only variables that pwsh does not set on
#     Unix. gitbash rendered "@ MINGW64 <path>" with the identity segment
#     blank, on the one style whose entire point is that line.
#   * fourteen styles printed an absolute path where the shell half printed a
#     ~-abbreviated one, because {CWD} maps to %~ / \w and $PWD.Path abbreviates
#     nothing.
#   * sober took the leaf of $HOME instead of '~', and did it before
#     abbreviating rather than after, so the home directory showed as the user's
#     own folder name.
#
# A static lint cannot see any of this: each half is valid on its own and the
# drift only exists between them. So render both and compare.
#
# WHAT THIS FILE USED TO MISS, and why it now renders three halves at four
# directories instead of two at one. It rendered zsh only, and only at $HOME.
# That is a single point in a two-dimensional space, and both of the defects
# fixed in the release below sat outside it:
#
#   * "the shell half" is two shells. {LEAF} mapped to zsh's %1~ and bash's \W,
#     which are NOT the same escape -- at a single-component absolute path %1~
#     keeps the leading slash and \W drops it -- so sober showed "/usr" in zsh
#     and pwsh and "usr" in bash, and nothing here ever rendered bash.
#   * $HOME is the one directory where a prefix test and a path-boundary test
#     agree. gitbash abbreviated $HOME with StartsWith and no boundary, so a
#     SIBLING of $HOME rendered as "~Xtra" -- invisible from $HOME.
#
# Measured over the full matrix, 16 styles x 4 directories x 3 halves: 62 of
# the 64 combinations agreed before the fix and all 64 after it, and the two
# that disagreed were exactly those two defects. One row of this grid catches
# either of them; the old single point caught neither.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'a style renders the same prompt in PowerShell, zsh and bash' {
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:ParityStyles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object {
                    (Test-Path -LiteralPath (Join-Path $_.FullName 'prompt.sh')) -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName 'profile.ps1'))
                } | ForEach-Object { $_.Name })

        # Decided at DISCOVERY. A -Skip that reads a variable set in BeforeAll
        # gets $null -- falsy -- so the test neither runs nor reports skipped:
        # it silently passes. Windows CI has no zsh and must skip honestly.
        $script:NoParityShell = -not (Get-Command zsh -ErrorAction SilentlyContinue)
        $script:NoParityBash  = $script:NoParityShell -or
                                -not (Get-Command bash -ErrorAction SilentlyContinue)
    }

    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:runtime  = Join-Path (Join-Path $script:repoRoot 'shell') 'tstyles.sh'
        $script:work     = Join-Path $TestDrive 'parity'
        New-Item -ItemType Directory -Path $script:work -Force | Out-Null

        # A synthetic $HOME, so the cwds below can include one that is a
        # character-prefix SIBLING of it. The path is put through `pwd -P` once
        # and that one resolved string is what both $HOME and every cd target
        # are built from -- which is what keeps macOS's symlinked temp
        # directories out of the comparison. zsh keeps the logical path and
        # pwsh reports what it was handed, so as long as both are handed the
        # physical one they are comparing the same thing.
        $seed = Join-Path $script:work 'sand'
        New-Item -ItemType Directory -Path $seed -Force | Out-Null
        # Asked again here rather than read from the discovery flag: this block
        # runs in the run phase and must not depend on which variables survive
        # discovery.
        $real = $seed
        if (Get-Command zsh -ErrorAction SilentlyContinue) {
            $real = (& zsh -f -c "cd '$seed' && pwd -P" 2>$null | Select-Object -First 1)
            if (-not $real) { $real = $seed }
        }
        $script:ParityHome = Join-Path $real 'tsparity'
        $sibling           = Join-Path $real 'tsparityXtra'
        $child             = Join-Path $script:ParityHome 'proj'
        foreach ($d in @($script:ParityHome, $sibling, $child)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }

        # Four directories, each of which some half of some style got wrong:
        #   $HOME          the ~ case the original drift showed up in
        #   <$HOME>Xtra    a SIBLING whose name extends $HOME's -- gitbash's
        #                  StartsWith abbreviated it to "~Xtra"
        #   /usr           a single-component absolute path, where bash's \W
        #                  drops the leading slash that zsh's %1~ keeps
        #   $HOME/proj     an ordinary child, the control
        # /usr rather than /tmp on purpose: it is present and un-symlinked on
        # both Unix runners, and it is never a git worktree, so {GITBRANCH}
        # cannot make two halves disagree for a reason no style controls.
        $script:ParityCwds = @($script:ParityHome, $sibling, '/usr', $child)

        # The engine running the suite, so the 5.1 leg would measure 5.1 rather
        # than whatever pwsh happens to be on PATH.
        $script:Engine = (Get-Process -Id $PID).Path

        $script:StripSgr = {
            param($s)
            ($s -replace "`e\[[0-9;]*m", '' -replace "`e\][0-9]*;[^`a]*`a", '')
        }

        # Each half renders EVERY cwd in one process, writing <TSPn> before each
        # prompt, so the whole sweep costs three children per style.
        function script:Split-Prompts {
            param([string]$Blob, [int]$Count)
            $out = @()
            for ($i = 0; $i -lt $Count; $i++) {
                $a = $Blob.IndexOf("<TSP$i>")
                if ($a -lt 0) { $out += $null; continue }
                $a += "<TSP$i>".Length
                $b = $Blob.IndexOf("<TSP$($i + 1)>")
                if ($b -lt $a) { $b = $Blob.Length }
                $out += $Blob.Substring($a, $b - $a)
            }
            return $out
        }
    }

    It '<_> renders identically in PowerShell and zsh' -ForEach $script:ParityStyles -Skip:$script:NoParityShell {
        $styleDir = Join-Path (Join-Path $script:repoRoot 'styles') $_
        $cwds     = $script:ParityCwds

        # The PowerShell half in a CHILD process: profile.ps1 defines
        # global:prompt and sets PSReadLine options, neither of which belongs in
        # the test host. $HOME reaches it through the environment, which is why
        # it is set and restored around both children rather than passed in.
        $lines = @(
            "`$ErrorActionPreference = 'SilentlyContinue'"
            ". '$(Join-Path $styleDir 'profile.ps1')' *> `$null")
        for ($i = 0; $i -lt $cwds.Count; $i++) {
            $lines += "Set-Location -LiteralPath '$($cwds[$i])'"
            $lines += "[Console]::Out.Write('<TSP$i>' + (prompt))"
        }
        $psFile = Join-Path $script:work "ps-$_.ps1"
        [System.IO.File]::WriteAllText($psFile, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))

        $zLines = @(
            "source '$($script:runtime)' >/dev/null 2>&1"
            "source '$(Join-Path $styleDir 'prompt.sh')' >/dev/null 2>&1")
        for ($i = 0; $i -lt $cwds.Count; $i++) {
            $zLines += "cd '$($cwds[$i])'"
            $zLines += "printf '%s' '<TSP$i>'"
            $zLines += 'print -Pn -- "$PROMPT"'
        }
        $zFile = Join-Path $script:work "z-$_.zsh"
        [System.IO.File]::WriteAllText($zFile, ($zLines -join "`n"), [System.Text.UTF8Encoding]::new($false))

        $oldHome = $env:HOME
        try {
            $env:HOME = $script:ParityHome
            $psBlob  = ((& $script:Engine -NoProfile -File $psFile 2>$null) -join "`n")
            $zshBlob = ((& zsh -f $zFile 2>$null) -join "`n")
        } finally { $env:HOME = $oldHome }

        $psParts  = script:Split-Prompts -Blob $psBlob  -Count $cwds.Count
        $zshParts = script:Split-Prompts -Blob $zshBlob -Count $cwds.Count

        for ($i = 0; $i -lt $cwds.Count; $i++) {
            $psText  = & $script:StripSgr ([string]$psParts[$i]).TrimEnd()
            $zshText = & $script:StripSgr ([string]$zshParts[$i]).TrimEnd()
            $psText | Should -Not -BeNullOrEmpty `
                -Because "the PowerShell half must render something at $($cwds[$i])"
            $psText | Should -Be $zshText `
                -Because "$_'s two halves must show the same prompt at $($cwds[$i])"
        }
    }

    It '<_> renders the same in bash as in zsh' -ForEach $script:ParityStyles -Skip:$script:NoParityBash {
        # THE HALF THAT WAS NEVER RENDERED. Every prompt.sh header promises its
        # two halves look the same, and this file only ever ran zsh -- so a
        # placeholder mapped onto two bash/zsh escapes that disagree with each
        # other passed for four releases. {LEAF} was: zsh's %1~ keeps the
        # leading slash at a single-component absolute path ('/usr'), bash's \W
        # drops it ('usr'), and sober is the one style that uses {LEAF}.
        #
        # bash only expands PS1 when it prints a prompt, and bash 3.2 (macOS
        # stock) has no ${PS1@P}. But an INTERACTIVE bash whose stdin is a pipe
        # still prints its prompt -- to stderr -- so `exec 2>&1` in the rc file
        # puts the expanded prompt on stdout with no pty needed. A marker
        # printed by the rc, and one per cd sent on stdin, bracket each prompt,
        # so multi-line prompts survive intact.
        $styleDir = Join-Path (Join-Path $script:repoRoot 'styles') $_
        $cwds     = $script:ParityCwds

        $rc = @(
            # A scratch data root, so nothing here reads the operator's own.
            "export TSTYLES_DATA='$($script:work)'"
            'exec 2>&1'
            "source '$($script:runtime)' >/dev/null 2>&1"
            "source '$(Join-Path $styleDir 'prompt.sh')' >/dev/null 2>&1"
            "cd '$($cwds[0])'"
            "printf '%s' '<TSP0>'"
        ) -join "`n"
        $rcFile = Join-Path $script:work "b-$_.rc"
        [System.IO.File]::WriteAllText($rcFile, $rc, [System.Text.UTF8Encoding]::new($false))

        $stdin = @()
        for ($i = 1; $i -lt $cwds.Count; $i++) {
            $stdin += "cd '$($cwds[$i])'; printf '%s' '<TSP$i>'"
        }
        $stdin += "printf '%s' '<TSP$($cwds.Count)>'"
        $stdin += 'exit'

        $zLines = @(
            "source '$($script:runtime)' >/dev/null 2>&1"
            "source '$(Join-Path $styleDir 'prompt.sh')' >/dev/null 2>&1")
        for ($i = 0; $i -lt $cwds.Count; $i++) {
            $zLines += "cd '$($cwds[$i])'"
            $zLines += "printf '%s' '<TSP$i>'"
            $zLines += 'print -Pn -- "$PROMPT"'
        }
        $zFile = Join-Path $script:work "zb-$_.zsh"
        [System.IO.File]::WriteAllText($zFile, ($zLines -join "`n"), [System.Text.UTF8Encoding]::new($false))

        $oldHome = $env:HOME
        $oldDep  = $env:BASH_SILENCE_DEPRECATION_WARNING
        try {
            $env:HOME = $script:ParityHome
            # macOS's bash 3.2 otherwise prints its "use zsh" notice at the
            # first prompt, i.e. in the middle of the capture.
            $env:BASH_SILENCE_DEPRECATION_WARNING = '1'
            $bashBlob = ((($stdin -join "`n") |
                          & bash --noprofile --noediting --rcfile $rcFile -i 2>$null) -join "`n")
            $zshBlob  = ((& zsh -f $zFile 2>$null) -join "`n")
        } finally {
            $env:HOME = $oldHome
            $env:BASH_SILENCE_DEPRECATION_WARNING = $oldDep
        }

        $bashParts = script:Split-Prompts -Blob $bashBlob -Count $cwds.Count
        $zshParts  = script:Split-Prompts -Blob $zshBlob  -Count $cwds.Count

        for ($i = 0; $i -lt $cwds.Count; $i++) {
            $bashText = & $script:StripSgr ([string]$bashParts[$i]).TrimEnd()
            $zshText  = & $script:StripSgr ([string]$zshParts[$i]).TrimEnd()
            $bashText | Should -Not -BeNullOrEmpty `
                -Because "the bash half must render something at $($cwds[$i])"
            $bashText | Should -Be $zshText `
                -Because "$_'s bash and zsh halves must show the same prompt at $($cwds[$i])"
        }
    }
}

Describe 'a style does not touch the line editor, on any platform' {
    # THE DEFECT THIS EXISTS FOR. All sixteen profile.ps1 files carried
    #
    #     if (($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows) {
    #         Set-PSReadLineOption -EditMode Windows
    #     }
    #
    # and the comment above it, repeated verbatim in all sixteen, said the call
    # was free on Windows because Windows mode is already the default there.
    # It is not free. PSReadLine does not compare the mode it is handed with
    # the mode it is in: supplying -EditMode AT ALL discards the dispatch
    # tables and rebuilds them from that mode's defaults, so every
    # Set-PSReadLineKeyHandler made earlier in the session is deleted.
    # Measured on PSReadLine 2.4.5, session already in Windows mode, EditMode
    # reading 'Windows' both before and after: 65 bound handlers before, 63
    # after, a custom chord and an Alt binding gone outright and Ctrl+w
    # reverted to its stock default. The style is dot-sourced from the END of
    # $PROFILE, after the user's own bindings, so the user always loses.
    #
    # 0.8.21 deleted the call on macOS and Linux, where it also unbinds
    # Ctrl+D/U/E/K, and KEPT it on Windows on the strength of that comment.
    # This is the other half of the same statement.
    #
    # The lint that stood here asserted the opposite -- that the call must
    # survive behind a platform test -- so it certified the bug it was reading
    # over. It had a second hole worth naming: it matched '\$IsWindows'
    # against $text, the WHOLE FILE, where it meant the $line it had just
    # matched, and the shipped comment ("5.1 predates $IsWindows and is
    # Windows by definition") contained that literal, so the guard could be
    # deleted outright and all sixteen still passed. Both halves below are
    # built not to have that shape: the static one walks the AST, where a
    # comment is not a command and cannot satisfy or break it, and the runtime
    # one measures a key binding rather than the text of a file.
    BeforeDiscovery {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $script:ProfileStyles = @(
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'styles') -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'profile.ps1') } |
                ForEach-Object { $_.Name })

        # Decided at DISCOVERY. A -Skip reading a variable set in BeforeAll
        # gets $null -- falsy -- so the test would neither run nor report
        # skipped: it would silently pass. With no PSReadLine there is nothing
        # to measure, because the whole block is inside
        # `if (Get-Module -ListAvailable PSReadLine)`.
        $script:NoPSReadLine = -not (Get-Module -ListAvailable -Name PSReadLine)
    }

    It '<_>/profile.ps1 hands -EditMode to nothing' -ForEach $script:ProfileStyles {
        # Static, so this half also runs on the Windows PowerShell 5.1 leg and
        # on any runner where PSReadLine is missing.
        $style = $_
        $path  = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'styles') $style) 'profile.ps1'

        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0 -Because "$style/profile.ps1 must parse"

        # The AST, not the text. -EditMode has to be a real parameter on a real
        # command for this to see it; the explanatory comment above cannot.
        $offenders = @(
            $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object { $_.GetCommandName() -eq 'Set-PSReadLineOption' } |
                Where-Object {
                    @($_.CommandElements | Where-Object {
                        ($_ -is [System.Management.Automation.Language.CommandParameterAst]) -and
                        'EditMode'.StartsWith($_.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)
                    }).Count -gt 0
                } | ForEach-Object { $_.Extent.StartLineNumber })

        @($offenders).Count | Should -Be 0 -Because (
            "$style must not set an edit mode on any platform -- passing -EditMode rebuilds " +
            "PSReadLine's keymap from defaults and deletes the user's own bindings, even when " +
            "the mode is unchanged (line(s): $($offenders -join ', '))")
    }

    It '<_>/profile.ps1 leaves a key binding made before it alone' -ForEach $script:ProfileStyles -Skip:$script:NoPSReadLine {
        $style        = $_
        $repoRoot     = Split-Path $PSScriptRoot -Parent
        $styleProfile = Join-Path (Join-Path (Join-Path $repoRoot 'styles') $style) 'profile.ps1'

        # A CHILD process, and the same engine running the suite -- so the 5.1
        # leg measures 5.1 rather than whatever pwsh is on PATH, and the style's
        # global:prompt, window title and PSReadLine options never land in the
        # test host.
        $engine = (Get-Process -Id $PID).Path

        # Every name the probe keeps across the dot-source is `tsProbe`-prefixed.
        # A style's top-level `$B = "<escape>"` (halo, marquee) lands in this
        # same scope and PowerShell variable names are case-insensitive, so a
        # probe holding its results in `$b` had them replaced by a colour string
        # and died indexing into it. The shell half has the `_ts_` rule for
        # exactly this reason; the PowerShell half has no such rule, so the
        # probe carries the burden.
        $probe = @"
`$ErrorActionPreference = 'Stop'
`$tsProbeErr = ''; `$tsProbeMode = ''; `$tsProbeColourBefore = ''; `$tsProbeColourAfter = ''
`$tsProbeBound = @{}
try {
    Import-Module PSReadLine

    # Start in the mode a Windows session already starts in, so the style's
    # call cannot be excused as having changed anything.
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key   'Ctrl+w'        -Function ForwardWord
    Set-PSReadLineKeyHandler -Key   'UpArrow'       -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Chord 'Ctrl+f,Ctrl+g' -ScriptBlock { }
    `$tsProbeColourBefore = [string](Get-PSReadLineOption).CommandColor

    # Stand in for Windows on every runner. The erasure itself is
    # platform-independent; only the guard that used to wrap it was not, and
    # forcing this is what makes the macOS and Linux legs cover the Windows
    # branch -- the gap that let 0.8.21 fix one half of this and ship the other.
    Set-Variable -Name IsWindows -Value `$true -Scope Global -Force

    . '$styleProfile' *> `$null

    foreach (`$tsProbeHandler in (Get-PSReadLineKeyHandler -Bound)) {
        `$tsProbeBound[`$tsProbeHandler.Key] = `$tsProbeHandler.Function
    }
    `$tsProbeMode = [string](Get-PSReadLineOption).EditMode
    `$tsProbeColourAfter = [string](Get-PSReadLineOption).CommandColor
} catch { `$tsProbeErr = `$_.Exception.Message }
[Console]::Out.WriteLine('TSTYLES-PSRL ' + (ConvertTo-Json -Compress -InputObject @{
    error    = [string]`$tsProbeErr
    windows  = [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
    editmode = `$tsProbeMode
    recolour = (`$tsProbeColourBefore -ne `$tsProbeColourAfter)
    ctrlw    = [string]`$tsProbeBound['Ctrl+w']
    up       = [string]`$tsProbeBound['UpArrow']
    total    = @(`$tsProbeBound.Keys).Count
    # Looked up by shape, not by an exact key string: a single key is a
    # case-insensitive hashtable hit, but only PSReadLine decides how it spells
    # a CHORD back to you, and 5.1 carries a different PSReadLine (2.0) from
    # pwsh 7. Anything with a comma and Ctrl+f in it is the chord and nothing
    # else is, so the lookup survives the spelling without loosening what it
    # measures -- if the chord was deleted there is no such key and this is ''.
    chord    = [string]((@(`$tsProbeBound.Keys) |
                    Where-Object { `$_ -like '*Ctrl+f,*' } |
                    ForEach-Object { `$tsProbeBound[`$_] }) -join ',')
}))
"@
        $probePath = Join-Path $TestDrive "psreadline-$style.ps1"
        [System.IO.File]::WriteAllText($probePath, $probe, [System.Text.UTF8Encoding]::new($false))

        $out  = & $engine -NoProfile -File $probePath 2>$null
        $blob = (@($out) -join "`n")
        $m    = [regex]::Match($blob, 'TSTYLES-PSRL (\{.*\})')

        # First, that anything was measured at all. A probe that never reported
        # would otherwise leave every assertion below unexecuted and green.
        $m.Success | Should -BeTrue -Because "the probe must report; got: $blob"
        $r = $m.Groups[1].Value | ConvertFrom-Json

        $r.error    | Should -BeNullOrEmpty -Because 'the probe must not throw'
        $r.windows  | Should -BeTrue -Because 'the probe must stand in for Windows, or it measures the branch that was never the bug'
        $r.recolour | Should -BeTrue -Because "$style/profile.ps1 must really have run -- its own PSReadLine colours are the proof"

        $r.ctrlw | Should -Be 'ForwardWord'           -Because "$style must not rebuild PSReadLine's keymap over the user's Ctrl+w"
        $r.up    | Should -Be 'HistorySearchBackward' -Because "$style must not revert UpArrow, the binding PSReadLine's own docs tell users to make"
        $r.chord | Should -Be 'CustomAction'          -Because "$style must not drop the user's chord bindings ($($r.total) handlers bound after the style loaded)"
    }
}
