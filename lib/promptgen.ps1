# promptgen.ps1 -- write both halves of a generated style's prompt.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Pure: takes a shape, a symbol, colours and a title and returns the text of
# profile.ps1 (PowerShell) and prompt.sh (zsh/bash). No I/O. The two halves
# promise to render byte-identically, as every shipped style's do, and
# tests/Style-PromptParity.Tests.ps1 renders generated ones to hold them to it.
#
# The PowerShell half is not new code. Each shape is one of the placeholders
# shell/tstyles.sh already expands, and the PowerShell that matches it is
# copied from the style that already proved the match: {LEAF} from
# styles/sober/profile.ps1, {CWD} and the git branch from
# styles/gitbash/profile.ps1.
#
# ENCODING. profile.ps1 comes out ASCII-only, whatever the symbol or title:
# Windows PowerShell 5.1 reads a BOM-less .ps1 in the system codepage, so a
# literal U+276F in a string literal decodes as mojibake or breaks the parse.
# Anything outside printable ASCII is emitted as [char]0xNNNN instead. This
# file is held to the same rule, which is why the symbols below are built
# with [char] too. prompt.sh is UTF-8 and carries the symbol as text; both
# halves then print the same UTF-8 bytes.

function Get-StylePromptShapes {
    # The prompt shapes tstyles create offers, in display order.
    #   minimal  the folder name, then the symbol         {LEAF}
    #   path     the ~-abbreviated path, then the symbol  {CWD}
    #   twoline  the path, and the symbol on the next line {CWD}{NL}
    #   git      the folder name and git branch, then the symbol {LEAF}{GITBRANCH}
    @('minimal', 'path', 'twoline', 'git')
}

function Get-StylePromptSymbols {
    # The prompt symbols on offer. Built from code points: see ENCODING above.
    [OutputType([string[]])]
    param()
    [string[]]@(
        '$', '>', '#',
        [string][char]0x276F,   # heavy right-pointing angle quotation mark
        [string][char]0x03BB,   # lambda
        [string][char]0x00BB    # right-pointing double angle quotation mark
    )
}

function ConvertTo-PromptGenRgb {
    # '#rrggbb' -> 'r;g;b', the parameter list of a 24-bit SGR. Internal.
    param([Parameter(Mandatory)][string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16)
    "$r;$g;$b"
}

function ConvertTo-PromptGenPsExpression {
    # Text -> an ASCII-only PowerShell expression that evaluates to it:
    # single-quoted runs of printable ASCII joined to [char]0xNNNN for
    # everything else. Internal.
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return "''" }
    $parts = New-Object System.Collections.Generic.List[string]
    $run = ''
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -ge 0x20 -and $code -le 0x7E) {
            $run += [string]$ch
        } else {
            if ($run.Length -gt 0) { $parts.Add("'" + ($run -replace "'", "''") + "'"); $run = '' }
            $parts.Add(('[string][char]0x{0:X4}' -f $code))
        }
    }
    if ($run.Length -gt 0) { $parts.Add("'" + ($run -replace "'", "''") + "'") }
    $parts -join ' + '
}

function New-StylePromptText {
    <#
    .SYNOPSIS
    Writes profile.ps1 and prompt.sh for a generated style's prompt.
    .DESCRIPTION
    Returns @{ Profile = <profile.ps1 text>; Shell = <prompt.sh text> }. The two
    render the same bytes. Neither touches PSReadLine: the line editor belongs
    to the user.

    -Symbol must not carry a character that either shell reinterprets inside a
    prompt -- '%' (zsh), '\' and '!' (bash), a quote or backtick, a brace (the
    template's own placeholders), whitespace or a control character -- so the
    shell half can embed it without escaping beyond '$'.
    #>
    param(
        [Parameter(Mandatory)][string]$Shape,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][string]$PathColor,
        [Parameter(Mandatory)][string]$SymbolColor,
        [string]$BranchColor,
        [Parameter(Mandatory)][string]$Title
    )

    if (@(Get-StylePromptShapes) -cnotcontains $Shape) {
        throw "Unknown prompt shape '$Shape'. Expected one of: $((Get-StylePromptShapes) -join ', ')."
    }
    $colors = @{ PathColor = $PathColor; SymbolColor = $SymbolColor }
    if ($PSBoundParameters.ContainsKey('BranchColor')) { $colors.BranchColor = $BranchColor }
    foreach ($k in $colors.Keys) {
        if ($colors[$k] -notmatch '^#[0-9a-fA-F]{6}$') {
            throw "-$k must be a #rrggbb colour, not '$($colors[$k])'."
        }
    }
    if ($Symbol.Length -eq 0 -or $Symbol -match '[\s%\\!`"''{}]' -or $Symbol -match '[\x00-\x1F\x7F]') {
        throw "The prompt symbol '$Symbol' carries a character a shell prompt would reinterpret."
    }
    if ($Title -match '[\x00-\x1F\x7F]') {
        throw 'The title must not carry a control character.'
    }

    $pathRgb = ConvertTo-PromptGenRgb $PathColor
    $symRgb  = ConvertTo-PromptGenRgb $SymbolColor
    $hasBranchColor = $colors.ContainsKey('BranchColor')
    $branchRgb = ''
    if ($hasBranchColor) { $branchRgb = ConvertTo-PromptGenRgb $BranchColor }

    $usesLeaf   = ($Shape -eq 'minimal') -or ($Shape -eq 'git')
    $usesBranch = ($Shape -eq 'git')

    # ---- profile.ps1 ---------------------------------------------------------
    $ps = New-Object System.Collections.Generic.List[string]
    $ps.Add('# Generated by tstyles create -- pwsh 7 and Windows PowerShell 5.1.')
    $ps.Add('# prompt.sh is the zsh/bash half; the two render the same bytes, so')
    $ps.Add('# change them together. function global:prompt so the binding sticks')
    $ps.Add('# when dot-sourced from inside tstyles.ps1''s Invoke-TerminalStyle.')
    $ps.Add('# ASCII-only on purpose: 5.1 reads a BOM-less .ps1 in the system')
    $ps.Add('# codepage, so the symbol is spelled as [char]0xNNNN.')
    $ps.Add('')
    $ps.Add('$Host.UI.RawUI.WindowTitle = ' + (ConvertTo-PromptGenPsExpression $Title))
    $ps.Add('')
    $ps.Add('function global:prompt {')
    $ps.Add('    $Esc   = [char]27')
    $ps.Add('    $PathC = "$Esc[38;2;' + $pathRgb + 'm"')
    $ps.Add('    $SymC  = "$Esc[38;2;' + $symRgb + 'm"')
    if ($usesBranch -and $hasBranchColor) {
        $ps.Add('    $BranchC = "$Esc[38;2;' + $branchRgb + 'm"')
    }
    $ps.Add('    $X     = "$Esc[0m"')
    $ps.Add('    $Sym   = ' + (ConvertTo-PromptGenPsExpression $Symbol))
    if ($usesLeaf) {
        # styles/sober/profile.ps1: {LEAF} is zsh's %1~.
        $ps.Add('    # {LEAF} in the zsh/bash half: zsh''s %1~, and ts_leaf in bash.')
        $ps.Add('    # Abbreviate $HOME to ~ FIRST, then keep the last component --')
        $ps.Add('    # except where that leaves only one, which zsh prints whole')
        $ps.Add('    # (''~'', ''/usr'', ''/'').')
        $ps.Add('    $abbr = $PWD.Path -replace (''^'' + [regex]::Escape($HOME) + ''(?=$|[\\/])''), ''~''')
        $ps.Add('    $where = if ($abbr -eq ''~'' -or ($abbr -replace ''^[\\/]'', '''') -notmatch ''[\\/]'') {')
        $ps.Add('        $abbr')
        $ps.Add('    } else {')
        $ps.Add('        Split-Path -Leaf $abbr')
        $ps.Add('    }')
    } else {
        # styles/gitbash/profile.ps1: {CWD} is zsh's %~ / bash's \w.
        $ps.Add('    # {CWD} in the zsh/bash half: %~ / \w. The abbreviation stops at a')
        $ps.Add('    # path boundary, so a sibling of $HOME such as ~/userXtra is not')
        $ps.Add('    # shortened to "~Xtra".')
        $ps.Add('    $where = ($PWD.Path -replace (''^'' + [regex]::Escape($HOME) + ''(?=$|[\\/])''), ''~'') -replace ''\\'', ''/''')
    }
    if ($usesBranch) {
        # styles/gitbash/profile.ps1: ts_git_branch's " (branch)".
        $ps.Add('    # {GITBRANCH}: " (branch)" in a git worktree, nothing elsewhere.')
        $ps.Add('    # Save/restore $LASTEXITCODE so calling git here does not')
        $ps.Add('    # pollute the user''s subsequent error checks.')
        $ps.Add('    $branchPart = ''''')
        $ps.Add('    $savedExit  = $LASTEXITCODE')
        $ps.Add('    try {')
        $ps.Add('        $b = & git rev-parse --abbrev-ref HEAD 2>$null')
        $ps.Add('        if ($LASTEXITCODE -eq 0 -and $b) {')
        if ($hasBranchColor) {
            $ps.Add('            $branchPart = " ${BranchC}($b)${X}"')
        } else {
            $ps.Add('            $branchPart = " ($b)"')
        }
        $ps.Add('        }')
        $ps.Add('    } catch { }')
        $ps.Add('    $global:LASTEXITCODE = $savedExit')
    }
    $line = '${PathC}${where}${X}'
    if ($usesBranch) { $line += '${branchPart}' }
    if ($Shape -eq 'twoline') { $line += '`n' } else { $line += ' ' }
    $line += '${SymC}${Sym}${X} '
    $ps.Add('    "' + $line + '"')
    $ps.Add('}')

    # ---- prompt.sh -----------------------------------------------------------
    $placeholder = switch ($Shape) {
        'minimal' { '{LEAF}' }
        'path'    { '{CWD}' }
        'twoline' { '{CWD}' }
        'git'     { '{LEAF}' }
    }
    # Inside the double-quoted template only '$' still needs escaping: the
    # checks above refused every other character the shells would read.
    $shSym = $Symbol -replace '\$', '\$'
    $shTitle = "'" + ($Title -replace "'", "'\''") + "'"

    $tpl = '${_ts_pPath}' + $placeholder + '${_ts_pX}'
    if ($usesBranch) { $tpl += '{GITBRANCH}' }
    if ($Shape -eq 'twoline') { $tpl += '{NL}' } else { $tpl += ' ' }
    $tpl += '${_ts_pSym}' + $shSym + '${_ts_pX} '

    $sh = New-Object System.Collections.Generic.List[string]
    $sh.Add('# Generated by tstyles create -- zsh and bash.')
    $sh.Add('#')
    $sh.Add('# profile.ps1 is the PowerShell half; the two render the same bytes, so')
    $sh.Add('# change them together.')
    $sh.Add('#')
    $sh.Add('# Sourced by shell/tstyles.sh, which defines ts_c / ts_title /')
    $sh.Add('# ts_prompt_expand / ts_prompt_apply. Every name assigned here is')
    $sh.Add('# _ts_-prefixed: this runs in the user''s own shell.')
    $sh.Add('')
    $sh.Add("_ts_pPath=`$(ts_c '$pathRgb')")
    $sh.Add("_ts_pSym=`$(ts_c '$symRgb')")
    $sh.Add('_ts_pX=$(ts_x)')
    if ($usesBranch) {
        $sh.Add('')
        $sh.Add('# Colours for the " (branch)" segment ts_git_branch appends. Always')
        $sh.Add('# assigned, so a branch colour left by an earlier style cannot leak in.')
        if ($hasBranchColor) {
            $sh.Add("_ts_git_open=`$(ts_cs '$branchRgb')")
            $sh.Add('_ts_git_close=$(ts_xs)')
        } else {
            $sh.Add("_ts_git_open=''")
            $sh.Add("_ts_git_close=''")
        }
    }
    $sh.Add('')
    $sh.Add('ts_title ' + $shTitle)
    $sh.Add('')
    $sh.Add('ts_prompt_apply "$(ts_prompt_expand "' + $tpl + '")"')

    @{
        Profile = (($ps -join "`n") + "`n")
        Shell   = (($sh -join "`n") + "`n")
    }
}
