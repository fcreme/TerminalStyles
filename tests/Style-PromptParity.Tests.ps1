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
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'a style renders the same prompt in PowerShell and in zsh' {
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
    }

    It '<_> renders identically in both halves' -ForEach $script:ParityStyles -Skip:$script:NoParityShell {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $styleDir = Join-Path (Join-Path $repoRoot 'styles') $_
        $runtime  = Join-Path (Join-Path $repoRoot 'shell') 'tstyles.sh'

        # $HOME is the cwd on purpose: it is the case the drift actually showed
        # up in (~ vs the absolute path, ~ vs the folder's own name) and both
        # shells agree on what it is. A temp directory would not do -- macOS
        # puts those behind a symlink, and pwsh reports the resolved path while
        # zsh keeps the logical one, which is a shell difference rather than
        # anything a style controls.
        $strip = { param($s) ($s -replace "`e\[[0-9;]*m", '') }

        # The PowerShell half in a CHILD process: profile.ps1 defines
        # global:prompt and sets PSReadLine options, neither of which belongs in
        # the test host.
        $psOut = & pwsh -NoProfile -Command @"
`$ErrorActionPreference = 'SilentlyContinue'
Set-Location -LiteralPath '$HOME'
. '$(Join-Path $styleDir 'profile.ps1')' *> `$null
[Console]::Out.Write((prompt))
"@ 2>$null
        if (-not $psOut) {
            $psOut = & pwsh-preview -NoProfile -Command @"
`$ErrorActionPreference = 'SilentlyContinue'
Set-Location -LiteralPath '$HOME'
. '$(Join-Path $styleDir 'profile.ps1')' *> `$null
[Console]::Out.Write((prompt))
"@ 2>$null
        }

        $zshScript = @(
            "cd '$HOME'"
            "source '$runtime' >/dev/null 2>&1"
            "source '$(Join-Path $styleDir 'prompt.sh')' >/dev/null 2>&1"
            'print -Pn -- "$PROMPT"'
        ) -join "`n"
        $sf = Join-Path $TestDrive "parity-$_.zsh"
        [System.IO.File]::WriteAllText($sf, $zshScript, [System.Text.UTF8Encoding]::new($false))
        $zshOut = & zsh -f $sf 2>$null

        $psText  = & $strip (($psOut  -join "`n").TrimEnd())
        $zshText = & $strip (($zshOut -join "`n").TrimEnd())

        $psText | Should -Not -BeNullOrEmpty -Because 'the PowerShell half must render something'
        $psText | Should -Be $zshText -Because "$_'s two halves must show the same prompt"
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
