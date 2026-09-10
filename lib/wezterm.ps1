# WezTerm support.
#
# WHY THIS EXISTS. WezTerm is the only terminal available off Windows that
# renders an ANIMATED GIF background, and every bundled style in this project
# ships one. Terminal.app can show a still first frame and nothing more (a
# profile pointing at a GIF renders blank, with no error), so before this the
# animation existed only on Windows Terminal.
#
# THE SHAPE OF THE PROBLEM. wezterm.lua is not a data file, it is a Lua PROGRAM
# the user owns. That makes it more dangerous to edit than ~/.zshrc, not less:
#
#   * A Lua error does not degrade. WezTerm shows an error window and falls back
#     to the DEFAULT config -- the user loses their whole terminal appearance,
#     not just the style. Historically it also stopped watching the file after a
#     failed load, so fixing the error did not auto-reload: restart to recover.
#   * There is no safe generic insertion point. Almost every wezterm.lua ends
#     with `return config`, and Lua requires `return` to be the last statement in
#     its block -- so appending a marker block, the way Register-ShellLoader does
#     for an rc file, is a SYNTAX ERROR on the most common config in existence.
#
# So this module never writes to wezterm.lua. It writes ONE file that belongs
# entirely to TerminalStyles, and prints the single line the user adds by hand:
#
#     local ok, ts = pcall(require, 'terminalstyles')
#     if ok then ts.apply_to_config(config) end
#
# ~/.config/wezterm is on WezTerm's Lua package.path REGARDLESS of where the
# config file itself was found, so `require 'terminalstyles'` resolves even for a
# user whose config lives at ~/.wezterm.lua or at $WEZTERM_CONFIG_FILE. The
# pcall is what bounds the blast radius: if this file is corrupt, half-written or
# deleted, the user's config still loads and they merely lose the style.
#
# Two properties fall out of `require` that make this better than the
# Terminal.app path: WezTerm implicitly adds required files to its config reload
# watch list, so rewriting this file RESTYLES A RUNNING WINDOW -- no new window,
# no restart -- and uninstall is a single Remove-Item rather than a textual strip
# out of a file the user is also editing.

function Get-WezTermModuleDir {
    <#
    .SYNOPSIS
    The directory WezTerm searches for Lua modules: ~/.config/wezterm.

    .DESCRIPTION
    Fixed rather than derived from where wezterm.lua actually lives, because
    package.path carries this directory whatever the config file's location.
    That is the whole reason the require form is usable here.

    -HomeDir is a test seam; real callers omit it. It exists for the reason
    CLAUDE.md gives: overriding the data root does not contain a function that
    resolves from $HOME, so without it a test would write into the operator's own
    ~/.config/wezterm.
    #>
    [CmdletBinding()]
    param([string]$HomeDir = $HOME)

    if ($env:XDG_CONFIG_HOME -and -not $PSBoundParameters.ContainsKey('HomeDir')) {
        return (Join-Path $env:XDG_CONFIG_HOME 'wezterm')
    }
    Join-Path (Join-Path $HomeDir '.config') 'wezterm'
}

function Get-WezTermModulePath {
    # The generated module. Named for the `require 'terminalstyles'` that loads it.
    [CmdletBinding()]
    param([string]$HomeDir)
    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    Join-Path (Get-WezTermModuleDir @splat) 'terminalstyles.lua'
}

function Get-WezTermWiringLine {
    # The one line the user adds. Printed in full by wezterm-init and searched
    # for by Test-WezTermStyleWired, so it lives in exactly one place.
    "local ok, ts = pcall(require, 'terminalstyles'); if ok then ts.apply_to_config(config) end"
}

function ConvertTo-WezTermLuaString {
    <#
    .SYNOPSIS
    A Lua single-quoted string literal, escaped.

    .DESCRIPTION
    Every value that reaches the generated file goes through here. A style name
    or a path can contain a quote or a backslash -- on Windows every path does --
    and an unescaped one does not produce a wrong colour, it produces a Lua
    syntax error, which costs the user their entire config until they find it.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if ($null -eq $Value) { return "''" }
    $e = $Value -replace '\\', '\\\\'
    $e = $e -replace "'", "\'"
    $e = $e -replace "`r", '\r' -replace "`n", '\n'
    "'$e'"
}

function Test-WezTermHexColor {
    <#
    .SYNOPSIS
    Is this a colour WezTerm's parser will actually accept?

    .DESCRIPTION
    SrgbaTuple::from_str requires 1 + digits*3 == length, so #RRGGBB and #RGB
    parse and #RRGGBBAA is REJECTED -- eight hex digits is not three channels.
    A rejected colour is a config error, and a config error is the whole default
    config, so an invalid value is dropped here rather than emitted.
    #>
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value -match '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{9}|[0-9a-fA-F]{12})$'
}

function Get-WezTermFontWeight {
    # Windows Terminal font weights -> WezTerm's names. Anything unrecognised
    # becomes Regular rather than being passed through: an unknown weight is a
    # config error under config:set_strict_mode(true), which some users set.
    param([AllowNull()][string]$Weight)
    switch (($Weight -as [string]).ToLowerInvariant()) {
        'thin'       { 'Thin' }
        'extra-light' { 'ExtraLight' }
        'light'      { 'Light' }
        'semi-light' { 'DemiLight' }
        'normal'     { 'Regular' }
        'medium'     { 'Medium' }
        'semi-bold'  { 'DemiBold' }
        'bold'       { 'Bold' }
        'extra-bold' { 'ExtraBold' }
        'black'      { 'Black' }
        default      { 'Regular' }
    }
}

function Get-WezTermBackgroundSize {
    # backgroundImageStretchMode -> BackgroundSize. Cover is WezTerm's default
    # and the closest thing to uniformToFill, which is what every bundled style
    # asks for.
    param([AllowNull()][string]$Mode)
    switch (($Mode -as [string]).ToLowerInvariant()) {
        'uniform'        { 'Contain' }
        'uniformtofill'  { 'Cover' }
        'fill'           { '100%' }
        'none'           { 'Auto' }
        default          { 'Cover' }
    }
}

function Get-WezTermStyleLua {
    <#
    .SYNOPSIS
    The generated module's text. Pure: builds a string, touches no file.

    .DESCRIPTION
    Kept separate from the write so the output can be asserted on directly.
    Nothing here can be checked against a running WezTerm from the test suite,
    so the tests pin the exact keys and shapes the docs and the wezterm source
    define, and this function is the only place that decides them.

    The layer list is deliberately TWO layers, base colour first. Once any
    `background` list exists WezTerm skips the pane's solid background rect and
    clears the frame to transparent, so a GIF that is translucent, has alpha, or
    does not cover the viewport would otherwise show the desktop rather than the
    style's own background colour.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)]$Scheme,
        $Theme,
        [AllowNull()][string]$BackgroundImage
    )

    $schemeName = "TerminalStyles $StyleName"
    $q = { param($v) ConvertTo-WezTermLuaString $v }

    # scheme.json -> the palette. ansi and brights are FIXED 8-element arrays in
    # WezTerm (Option<[RgbaColor; 8]>); seven or sixteen is a config error, so
    # both are emitted whole or not at all.
    $map = [ordered]@{
        foreground   = $Scheme.foreground
        background   = $Scheme.background
        cursor_bg    = $Scheme.cursorColor
        cursor_border= $Scheme.cursorColor   # both, or the block cursor outline is wrong
        cursor_fg    = $Scheme.background    # no WT equivalent; the text under the block
        selection_bg = $Scheme.selectionBackground
        selection_fg = $Scheme.foreground    # no WT equivalent
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("-- Generated by TerminalStyles for style $StyleName. Do not edit:")
    [void]$sb.AppendLine("-- rewritten on every apply. Load it from your wezterm.lua with")
    [void]$sb.AppendLine("--   $(Get-WezTermWiringLine)")
    [void]$sb.AppendLine("local wezterm = require 'wezterm'")
    [void]$sb.AppendLine("local M = {}")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("function M.apply_to_config(config)")
    [void]$sb.AppendLine("  config.color_schemes = config.color_schemes or {}")
    [void]$sb.AppendLine("  config.color_schemes[$(& $q $schemeName)] = {")
    foreach ($k in $map.Keys) {
        if (Test-WezTermHexColor $map[$k]) {
            [void]$sb.AppendLine("    $k = $(& $q $map[$k]),")
        }
    }

    $ansi    = @('black','red','green','yellow','blue','purple','cyan','white')
    $brights = @('brightBlack','brightRed','brightGreen','brightYellow',
                 'brightBlue','brightPurple','brightCyan','brightWhite')
    foreach ($pair in @(@('ansi', $ansi), @('brights', $brights))) {
        $vals = @(foreach ($n in $pair[1]) { $Scheme.$n })
        if (@($vals | Where-Object { Test-WezTermHexColor $_ }).Count -eq 8) {
            [void]$sb.AppendLine("    $($pair[0]) = {")
            [void]$sb.AppendLine("      " + (($vals | ForEach-Object { & $q $_ }) -join ', '))
            [void]$sb.AppendLine("    },")
        }
    }
    [void]$sb.AppendLine("  }")
    [void]$sb.AppendLine("  config.color_scheme = $(& $q $schemeName)")

    # theme.json -> font and padding. Opacity is deliberately absent; see the
    # capability table for why it is not claimed.
    if ($Theme -and $Theme.font -and $Theme.font.face) {
        $w = Get-WezTermFontWeight $Theme.font.weight
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  config.font = wezterm.font($(& $q $Theme.font.face), { weight = $(& $q $w) })")
        if ($Theme.font.size) {
            $size = [double]$Theme.font.size
            [void]$sb.AppendLine("  config.font_size = $($size.ToString([cultureinfo]::InvariantCulture))")
        }
    }
    if ($Theme -and $Theme.padding) {
        $pad = ($Theme.padding -split ',')[0].Trim()
        $padNum = 0
        if ([int]::TryParse($pad, [ref]$padNum)) {
            [void]$sb.AppendLine("  config.window_padding = { left = $padNum, right = $padNum, top = $padNum, bottom = $padNum }")
        }
    }

    # The point of the whole file.
    if ($BackgroundImage) {
        $bgOpacity = 1.0
        if ($Theme -and $null -ne $Theme.backgroundImageOpacity) {
            $bgOpacity = [double]$Theme.backgroundImageOpacity
        }
        $size = Get-WezTermBackgroundSize ($Theme.backgroundImageStretchMode)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  -- Layer 1 is the style's own background colour. With any background")
        [void]$sb.AppendLine("  -- list WezTerm stops drawing the pane's solid rect, so without this")
        [void]$sb.AppendLine("  -- anything the image does not cover shows the desktop.")
        [void]$sb.AppendLine("  config.background = {")
        if (Test-WezTermHexColor $Scheme.background) {
            [void]$sb.AppendLine("    {")
            [void]$sb.AppendLine("      source = { Color = $(& $q $Scheme.background) },")
            [void]$sb.AppendLine("      width = '100%', height = '100%',")
            [void]$sb.AppendLine("    },")
        }
        # An ABSOLUTE path: File.path is a plain String handed to fs::read, with
        # no config-dir, no ~ and no $HOME expansion, and a path it cannot read
        # is dropped with only a log line -- no background and no error.
        [void]$sb.AppendLine("    {")
        [void]$sb.AppendLine("      source = { File = { path = $(& $q $BackgroundImage) } },")
        [void]$sb.AppendLine("      width = $(& $q $size), height = $(& $q $size),")
        [void]$sb.AppendLine("      horizontal_align = 'Center', vertical_align = 'Middle',")
        [void]$sb.AppendLine("      opacity = $($bgOpacity.ToString([cultureinfo]::InvariantCulture)),")
        [void]$sb.AppendLine("    },")
        [void]$sb.AppendLine("  }")
    }

    [void]$sb.AppendLine("  return config")
    [void]$sb.AppendLine("end")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("return M")
    $sb.ToString()
}

function Write-WezTermStyleModule {
    <#
    .SYNOPSIS
    Write the generated module. Returns 'written' | 'unchanged' | 'failed'.

    .DESCRIPTION
    A status rather than a boolean, the rule the rest of this project learned the
    hard way: "it failed" and "there was nothing to do" must not be the same
    answer to the caller.

    UTF-8 without BOM, not Get-RcFileEncoding: this file is written whole by
    TerminalStyles and never read back from disk, so there is no user content to
    preserve -- and a BOM ahead of a Lua chunk is a parse error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)]$Scheme,
        $Theme,
        [AllowNull()][string]$BackgroundImage,
        [string]$HomeDir
    )

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    $path = Get-WezTermModulePath @splat

    # Verified here so a bad path surfaces in PowerShell rather than as a missing
    # background and a line in a log the user will never open.
    if ($BackgroundImage -and -not (Test-Path -LiteralPath $BackgroundImage)) {
        $BackgroundImage = $null
    }

    $lua = Get-WezTermStyleLua -StyleName $StyleName -Scheme $Scheme -Theme $Theme `
                               -BackgroundImage $BackgroundImage
    try {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $enc = [System.Text.UTF8Encoding]::new($false)
        if (Test-Path -LiteralPath $path) {
            # Rewriting an identical file would still trip WezTerm's config
            # reload watch, so an unchanged style does not repaint the window.
            if ([System.IO.File]::ReadAllText($path, $enc) -eq $lua) { return 'unchanged' }
        }
        [System.IO.File]::WriteAllText($path, $lua, $enc)
        return 'written'
    } catch { return 'failed' }
}

function Get-WezTermConfigCandidate {
    <#
    .SYNOPSIS
    Where WezTerm looks for its config, in order. Read-only; creates nothing.

    .DESCRIPTION
    WezTerm stops at the FIRST of these that exists, and a parse failure there
    does not fall through to the next -- so only the first existing file can be
    the one carrying the wiring line.
    #>
    [CmdletBinding()]
    param([string]$HomeDir = $HOME)

    $c = @()
    if ($env:WEZTERM_CONFIG_FILE) { $c += $env:WEZTERM_CONFIG_FILE }
    if ($env:XDG_CONFIG_HOME) { $c += (Join-Path (Join-Path $env:XDG_CONFIG_HOME 'wezterm') 'wezterm.lua') }
    $c += (Join-Path (Join-Path (Join-Path $HomeDir '.config') 'wezterm') 'wezterm.lua')
    $c += (Join-Path $HomeDir '.wezterm.lua')
    $c
}

function Test-WezTermStyleWired {
    <#
    .SYNOPSIS
    Has the user added the require line to the config WezTerm will actually load?

    .DESCRIPTION
    Only the FIRST existing candidate is consulted, because that is the only one
    WezTerm reads. Matching on `require` plus the module name rather than the
    whole line, so a user who reformatted it, renamed the local, or moved it
    inside their own function is still recognised as wired.
    #>
    [CmdletBinding()]
    param([string]$HomeDir)
    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }

    foreach ($p in (Get-WezTermConfigCandidate @splat)) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $text = [System.IO.File]::ReadAllText($p, (Get-RcFileEncoding))
        } catch { return $false }
        return $text -match "require\s*[\(,]?\s*['`"]terminalstyles['`"]"
    }
    return $false
}
