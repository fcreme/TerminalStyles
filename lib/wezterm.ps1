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
#
# Reset, unlike uninstall, is a REWRITE: Clear-WezTermStyleModule leaves a module
# whose apply_to_config sets nothing. WezTerm puts a required file on that watch
# list only when a config load finds it on package.path, and it watches the
# config file's own folder only when that folder is not $HOME. So a deleted
# module can drop off the list for a config that lives outside ~/.config/wezterm
# (~/.wezterm.lua, $WEZTERM_CONFIG_FILE), and the next apply would no longer
# repaint the running windows. A rewritten one stays found and watched, and the
# rewrite itself is what makes WezTerm reload into the user's own config.
#
# PER-TAB MODE (measured 2026-11-20, wezterm 20260917-114457-b09b56c2). Probed in
# a sandbox instance (`wezterm-gui --config-file <probe.lua> start
# --always-new-process`) by scripting it from Lua (update-status, gui-startup,
# a log file), never the user's config:
#
#   * Overrides SURVIVE a reload. After window:set_config_overrides{
#     window_background_opacity = 0.5 }, touching a required module reloaded the
#     config and window:get_config_overrides() still returned the override, and
#     effective_config() still showed 0.5. (window-config-reloaded also fires
#     about once a second while overrides are set, so a handler there must be
#     cheap and idempotent.)
#     CORRECTION (2026-11-23, same build): the "about once a second" was the
#     probe's own doing. WezTerm watches the config file's folder, and the probe
#     logged into it, so every log write reloaded the config. With nothing
#     written there, one reload came in 11 s, and it was the touch that poked
#     it. A handler there still has to be cheap and idempotent, but the event
#     does not tick on its own.
#   * color_scheme has no LITERAL "none". Overriding it to '' or to a name that
#     is not in color_schemes is accepted by set_config_overrides but logs
#     `ERROR config::config > Your configuration specifies color_scheme=""
#     but that scheme was not found`, and effective_config().resolved_palette is
#     left nil (no palette at all). A SYNTHESIZED one works (measured
#     2026-11-23, same build): register wezterm.color.get_default_colors() in
#     color_schemes under a name of our own and override color_scheme to that
#     name. From a 'Builtin Dark' base the effective resolved_palette was
#     identical, all 273 serialized lines, to get_default_colors(), with no
#     ERROR in the log; a config that names no scheme at all reports an empty
#     resolved_palette, i.e. it draws those same defaults. The name is
#     'TerminalStyles /unstyled', which no style can take: '/' is never in a
#     style name. `background = {}` works too: it leaves zero layers and the
#     plain palette background.
#   * A split starts UNTAGGED. After pane:split{ direction = 'Right' } the new
#     pane's get_user_vars().TERMINALSTYLES_STYLE is nil, while the sibling still
#     reads its tag, and window:active_tab():panes() lists both, so the style of
#     a tab can be read from any of its panes.
#   * WezTerm's own values for the other keys a look sets (measured 2026-11-23,
#     same build: effective_config() of a config that sets none of them):
#     window_background_opacity 1.0, macos_window_background_blur 0,
#     default_cursor_style 'SteadyBlock', colors nil, background empty.
#
# DECISION (2026-11-23; it replaces "base = the user's own look", recorded on
# 2026-11-20 while color_scheme seemed to have no "none"). Both keys have a
# working "none" -- the synthesized default scheme and `background = {}` -- so
# base = the LAST-APPLIED STYLE, as the design chose: apply_to_config applies the
# default style to the config itself, a window showing the default carries none
# of a look's keys as overrides, and every other window, an unstyled one
# included, carries a COMPLETE override over every key a look sets, filled from
# the user's own value and then from WezTerm's, for a key the style leaves
# alone. (The qualifier: with NO default the base is itself unstyled, so an
# unstyled window already shows it and gets `{}` rather than a complete
# override.) Overrides on any other key are the user's and are kept. The new-window
# first-frame question is moot in this mode: a new window starts from the base
# config, and the base config already is the default style.

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
    # The one line the user adds. Printed in full by Publish-StyleWezTermConfig
    # when the module is not yet wired, written into the generated file's own
    # header, and searched for by Test-WezTermStyleWired -- so it lives in
    # exactly one place.
    #
    # This used to credit a subcommand that does not exist and never did. A
    # comment is a claim like any other line of output, and the reader it
    # misleads is the next person to go looking for that command.
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
    # String.Replace, not -replace. The regex operator is wrong in BOTH operands
    # at once here: a doubled backslash in the PATTERN means one backslash, but
    # in .NET's REPLACEMENT string only `$` is special, so `-replace '\\','\\\\'`
    # emitted FOUR backslashes per input one. Lua decodes `\\\\` as two, so the
    # path handed to WezTerm was not the path passed in -- on Windows, where
    # every path has separators, `C:\Users\me\bg.gif` became
    # `C:\\Users\\me\\bg.gif`. Never a syntax error, which is why it survived:
    # the value is silently wrong instead of loudly broken. scripts/demo.ps1's
    # ConvertTo-ExpectLiteral already documents this exact hazard.
    $e = $Value.Replace('\', '\\')
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

function Get-WezTermBackgroundAlignment {
    <#
    .SYNOPSIS
    backgroundImageAlignment -> WezTerm's horizontal_align / vertical_align pair.

    .DESCRIPTION
    Windows Terminal expresses alignment as ONE value that carries both axes
    ("bottomRight"); WezTerm takes two. Every value below is one the real binary
    accepts, measured with config_builder, which validates these enums:

        horizontal_align = 'Left' | 'Center' | 'Right'
        vertical_align   = 'Top'  | 'Middle' | 'Bottom'

    Case matters -- 'left' is rejected -- and a rejected value is not a
    differently-placed image, it is the user's whole config replaced by the
    default one, which is why nothing here is passed through from the theme.

    An unrecognised value falls back to centre rather than emitting it: Windows
    Terminal's own default is center, and guessing is what would make the frame
    jump for a style that simply spelled something wrong.
    #>
    param([AllowNull()][string]$Alignment)

    switch ("$Alignment".Trim().ToLowerInvariant()) {
        'left'        { return @{ H = 'Left';   V = 'Middle' } }
        'right'       { return @{ H = 'Right';  V = 'Middle' } }
        'top'         { return @{ H = 'Center'; V = 'Top'    } }
        'bottom'      { return @{ H = 'Center'; V = 'Bottom' } }
        'topleft'     { return @{ H = 'Left';   V = 'Top'    } }
        'topright'    { return @{ H = 'Right';  V = 'Top'    } }
        'bottomleft'  { return @{ H = 'Left';   V = 'Bottom' } }
        'bottomright' { return @{ H = 'Right';  V = 'Bottom' } }
        default       { return @{ H = 'Center'; V = 'Middle' } }
    }
}

function Get-WezTermBackgroundSize {
    # backgroundImageStretchMode -> BackgroundSize. Cover is WezTerm's default
    # (impl Default for BackgroundSize) and the closest thing to uniformToFill,
    # which is what most bundled styles ask for.
    #
    # Every value here must be one BackgroundSize accepts, because a value it
    # does not accept is not a differently-scaled image -- it is the user's
    # whole config replaced by the default one. `none` used to map to 'Auto',
    # which is not a variant, and `kitty` is the bundled style that declares
    # it. Measured on wezterm 20240203-110809-5046fc22:
    #
    #   error converting Lua table to Config (Config::from_dynamic: Error
    #   processing background.width (types: Config, BackgroundLayer) expected
    #   either 'Contain', 'Cover', a number, or a string of the form '123px'
    #   where 'px' is a unit and can be one of 'px', '%', 'pt' or 'cell', but
    #   got String)
    #
    # WezTerm has no natural-size variant, so `none` -- Windows Terminal's
    # "draw it at its own size" -- has no exact counterpart. Contain is the
    # nearest: it is the one option that neither stretches the aspect ratio nor
    # crops the image, which is what asking for `none` is asking to avoid.
    param([AllowNull()][string]$Mode)
    switch (($Mode -as [string]).ToLowerInvariant()) {
        'uniform'        { 'Contain' }
        'uniformtofill'  { 'Cover' }
        'fill'           { '100%' }
        'none'           { 'Contain' }   # nearest: no 'Auto' in BackgroundSize
        default          { 'Cover' }
    }
}

function Get-WezTermCursorStyle {
    <#
    .SYNOPSIS
    theme.json cursorShape -> WezTerm's DefaultCursorStyle, or $null.

    .DESCRIPTION
    The WHOLE Windows Terminal domain is mapped, not just the three shapes the
    bundled styles happen to use (vintage, filledBox, bar): a user style may
    declare any of the six, and the cost of an unrecognised one reaching the
    file is not a plain cursor. Measured against wezterm
    20240203-110809-5046fc22, with config_builder validation on:

      config.default_cursor_style = 'EmptyBox'
      -> error converting Lua table to Config (Config::from_dynamic: Error
         processing Config::default_cursor_style: `EmptyBox` is not a valid
         DefaultCursorStyle variant. ...)

    and a config error is the user's WHOLE appearance, not just the style. So
    anything unrecognised returns $null and the caller emits no line at all --
    WezTerm's own default cursor is a correct answer; an invalid enum is not.

    WezTerm has three shapes (Block / Underline / Bar), each Steady or
    Blinking, so two of Windows Terminal's six have no exact counterpart and
    are mapped to the nearest shape rather than to an invented one:

      emptyBox         -> SteadyBlock      WezTerm draws no hollow cursor. The
                                           box is the shape; the fill is the
                                           part that cannot be carried.
      doubleUnderscore -> SteadyUnderline  One rule where the style asked for
                                           two; WezTerm has no double variant.

    vintage is the classic console cursor -- a short block at the BOTTOM of the
    cell (Windows Terminal draws it as the ▃ glyph), which the underline
    approximates and a full block would overstate, so it maps to
    SteadyUnderline rather than SteadyBlock.

    Steady, never Blinking, throughout: theme.json carries no blink field, so
    choosing a Blinking variant would deliver a request no style ever made.
    #>
    param([AllowNull()][string]$Shape)

    if ([string]::IsNullOrWhiteSpace($Shape)) { return $null }
    switch ($Shape.ToLowerInvariant()) {
        'bar'              { 'SteadyBar' }
        'filledbox'        { 'SteadyBlock' }
        'emptybox'         { 'SteadyBlock' }        # nearest: no hollow cursor
        'underscore'       { 'SteadyUnderline' }
        'doubleunderscore' { 'SteadyUnderline' }    # nearest: no double rule
        'vintage'          { 'SteadyUnderline' }
        default            { $null }
    }
}

function Get-WezTermWindowOpacity {
    <#
    .SYNOPSIS
    theme.json opacity (Windows Terminal's 0-100) -> WezTerm's 0.0-1.0, or
    $null when the style is not asking for transparency at all.

    .DESCRIPTION
    $null for 100 deliberately. 1.0 IS window_background_opacity's default, so
    emitting it states a default rather than a decision -- and this file is
    merged into a config the user owns, where every line we write is a line
    that can contradict one of theirs. Fifteen of the sixteen bundled styles
    are opacity 100 + useAcrylic false, an ordinary opaque window, which is
    what WezTerm already gives.

    Parsed with InvariantCulture on purpose: the value arrives from JSON, where
    the decimal separator is always a dot, and the session's culture may not
    agree -- the same rule the timestamps in this project are pinned by.

    A malformed or negative value is $null rather than clamped: "80abc" is not
    a request for anything, and guessing at one writes a number into the user's
    terminal that no file of theirs contains.
    #>
    param([AllowNull()]$Opacity)

    if ($null -eq $Opacity) { return $null }
    $parsed = 0.0
    if (-not [double]::TryParse("$Opacity", [System.Globalization.NumberStyles]::Float,
                                [cultureinfo]::InvariantCulture, [ref]$parsed)) { return $null }
    if ($parsed -lt 0 -or $parsed -ge 100) { return $null }
    # Rounded so 83 does not arrive as 0.8300000000000001 in a file people read.
    [math]::Round($parsed / 100.0, 4)
}

function Get-WezTermTabForeground {
    <#
    .SYNOPSIS
    Readable tab text for a tab painted $Background, or $null if it cannot be
    computed.

    .DESCRIPTION
    Windows Terminal picks the tab's text colour itself from the tabColor's
    luminance; WezTerm does not -- colors.tab_bar.active_tab.fg_color keeps its
    default (a light grey) unless something sets it, which is unreadable on the
    light accents several bundled styles ship ('kitty' is #ffb3c6). So the
    same choice Windows Terminal makes is made here: WCAG relative luminance,
    then whichever of black and white contrasts further from it.

    $null for a colour ConvertTo-NormalHex cannot reduce to #rrggbb -- WezTerm
    also accepts #rrrgggbbb and #rrrrggggbbbb, which no consumer in this
    project can decode. The caller then emits bg_color alone and leaves
    WezTerm's own fg_color in place, which is a worse tab and a valid config.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Background)

    $hex = ConvertTo-NormalHex $Background
    if (-not $hex) { return $null }
    $chan = foreach ($i in 1, 3, 5) {
        $v = [Convert]::ToInt32($hex.Substring($i, 2), 16) / 255
        if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow((($v + 0.055) / 1.055), 2.4) }
    }
    $l = 0.2126 * $chan[0] + 0.7152 * $chan[1] + 0.0722 * $chan[2]
    if ((($l + 0.05) / 0.05) -ge (1.05 / ($l + 0.05))) { '#000000' } else { '#ffffff' }
}

function Add-WezTermModuleHeader {
    # The three lines both generated modules open with: the style module and
    # the one a reset leaves. Appended through the caller's builder, so the line
    # endings are the rest of the file's.
    #
    # Comments only, and that is what makes sharing them safe:
    # Test-WezTermModuleStyled compares a module's statements and never its
    # comments, so rewording this header -- the wiring line it quotes included
    # -- changes no file's answer.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory)][string]$What
    )
    [void]$Builder.AppendLine("-- Generated by TerminalStyles $What. Do not edit:")
    [void]$Builder.AppendLine('-- rewritten on every apply. Load it from your wezterm.lua with')
    [void]$Builder.AppendLine("--   $(Get-WezTermWiringLine)")
}

function Add-WezTermSchemeBody {
    # scheme.json -> the body of one color_schemes entry, appended at $Indent.
    # The one rule both generated modules use -- the single-style module's
    # config.color_schemes entry and each per-tab look's `scheme` -- so the two
    # cannot come to disagree about which keys a style's palette carries.
    #
    # ansi and brights are FIXED 8-element arrays in WezTerm
    # (Option<[RgbaColor; 8]>); seven or sixteen is a config error, so both are
    # emitted whole or not at all.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory)]$Scheme,
        [Parameter(Mandatory)][string]$Indent
    )
    $q = { param($v) ConvertTo-WezTermLuaString $v }
    $map = [ordered]@{
        foreground   = $Scheme.foreground
        background   = $Scheme.background
        cursor_bg    = $Scheme.cursorColor
        cursor_border= $Scheme.cursorColor   # both, or the block cursor outline is wrong
        cursor_fg    = $Scheme.background    # no WT equivalent; the text under the block
        selection_bg = $Scheme.selectionBackground
        selection_fg = $Scheme.foreground    # no WT equivalent
    }
    foreach ($k in $map.Keys) {
        if (Test-WezTermHexColor $map[$k]) {
            [void]$Builder.AppendLine("$Indent$k = $(& $q $map[$k]),")
        }
    }

    $ansi    = @('black','red','green','yellow','blue','purple','cyan','white')
    $brights = @('brightBlack','brightRed','brightGreen','brightYellow',
                 'brightBlue','brightPurple','brightCyan','brightWhite')
    foreach ($pair in @(@('ansi', $ansi), @('brights', $brights))) {
        $vals = @(foreach ($n in $pair[1]) { $Scheme.$n })
        if (@($vals | Where-Object { Test-WezTermHexColor $_ }).Count -eq 8) {
            [void]$Builder.AppendLine("$Indent$($pair[0]) = {")
            [void]$Builder.AppendLine("$Indent  " + (($vals | ForEach-Object { & $q $_ }) -join ', '))
            [void]$Builder.AppendLine("$Indent},")
        }
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
        [AllowNull()][string]$BackgroundImage,
        # Where font and padding come from, when that is not this style.
        #
        # The picker rewrites this module on every arrow key so the highlighted
        # style can be seen. Colours and the background swap in place, but
        # font_size and window_padding do not: WezTerm reflows the whole
        # terminal for either, so the text jumps on every row and the list is
        # unreadable while moving through it. Pinning layout to the style that
        # was already applied keeps the frame still, and the real style -- font
        # and padding included -- lands on confirm.
        #
        # $null means "omit layout entirely", which is what a preview on a
        # machine with no applied style wants: the user's own wezterm.lua
        # settings apply, and they are as stable as anything else we could pick.
        # Unbound means "this style's own", the normal apply.
        $LayoutTheme
    )

    if (-not $PSBoundParameters.ContainsKey('LayoutTheme')) { $LayoutTheme = $Theme }

    $schemeName = "TerminalStyles $StyleName"
    $q = { param($v) ConvertTo-WezTermLuaString $v }

    $sb = [System.Text.StringBuilder]::new()
    Add-WezTermModuleHeader -Builder $sb -What "for style $StyleName"
    [void]$sb.AppendLine("local wezterm = require 'wezterm'")
    [void]$sb.AppendLine("local M = {}")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("function M.apply_to_config(config)")
    [void]$sb.AppendLine("  config.color_schemes = config.color_schemes or {}")
    [void]$sb.AppendLine("  config.color_schemes[$(& $q $schemeName)] = {")
    Add-WezTermSchemeBody -Builder $sb -Scheme $Scheme -Indent '    '
    [void]$sb.AppendLine("  }")
    [void]$sb.AppendLine("  config.color_scheme = $(& $q $schemeName)")

    # theme.json -> font and padding. From $LayoutTheme, which is this style
    # unless a caller pinned it; see the parameter for why the picker does.
    if ($LayoutTheme -and $LayoutTheme.font -and $LayoutTheme.font.face) {
        $w = Get-WezTermFontWeight $LayoutTheme.font.weight
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  config.font = wezterm.font($(& $q $LayoutTheme.font.face), { weight = $(& $q $w) })")
        if ($LayoutTheme.font.size) {
            $size = [double]$LayoutTheme.font.size
            [void]$sb.AppendLine("  config.font_size = $($size.ToString([cultureinfo]::InvariantCulture))")
        }
    }
    if ($LayoutTheme -and $LayoutTheme.padding) {
        $pad = ($LayoutTheme.padding -split ',')[0].Trim()
        $padNum = 0
        if ([int]::TryParse($pad, [ref]$padNum)) {
            [void]$sb.AppendLine("  config.window_padding = { left = $padNum, right = $padNum, top = $padNum, bottom = $padNum }")
        }
    }

    # theme.json cursorShape -> default_cursor_style. Nothing at all for a
    # shape this project does not recognise: see Get-WezTermCursorStyle for the
    # measured error an invalid enum produces, and what it costs the user.
    $cursor = $null
    if ($Theme) { $cursor = Get-WezTermCursorStyle $Theme.cursorShape }
    if ($cursor) {
        [void]$sb.AppendLine("  config.default_cursor_style = $(& $q $cursor)")
    }

    # theme.json opacity + useAcrylic -> window transparency.
    #
    # Both halves are needed, and they act in DIFFERENT places -- read together
    # from wezterm 20240203-110809-5046fc22's own source:
    #
    #   window/src/os/macos/window.rs, update_window_shadow():
    #     let is_opaque = if self.config.window_background_opacity >= 1.0 { YES }
    #                     else { NO };
    #     self.window.setOpaque_(is_opaque);
    #
    # so nothing shows through the window at all until this setting drops below
    # 1.0 -- a translucent background LAYER on its own cannot make the window
    # itself transparent. And:
    #
    #   wezterm-gui/src/termwindow/render/paint.rs
    #     match (self.window_background.is_empty(), ...) {
    #       (false, ...) => { ... self.render_backgrounds(bg_color, top) ... }
    #       ...
    #     }
    #     if paint_terminal_background { ... .mul_alpha(self.config.window_background_opacity) }
    #
    #   wezterm-gui/src/termwindow/background.rs, render_background():
    #     let color = bg_color.mul_alpha(layer.def.opacity);
    #
    # so once a `background` LAYER LIST exists -- which is every bundled style,
    # they all ship a GIF -- the alpha that reaches the screen is the LAYER's
    # opacity and window_background_opacity is not multiplied in at all. The two
    # branches are mutually exclusive, so carrying the same fraction onto the
    # base colour layer below is not a double application: exactly one of them
    # is the factor, whichever path WezTerm takes.
    #
    # WezTerm converts its own legacy single-image setting the same way --
    # config/src/background.rs, BackgroundLayer::with_legacy():
    #     opacity: cfg.window_background_opacity,
    # the window setting becomes the LAYER's opacity there too.
    #
    # Emitting only window_background_opacity would therefore leave `kitty` --
    # the one bundled style that asks for transparency, and the one that also
    # ships a background -- painting a fully opaque colour layer over a
    # correctly transparent window, which is the capability lie this project
    # keeps a table to prevent.
    $winOpacity = $null
    if ($Theme) { $winOpacity = Get-WezTermWindowOpacity $Theme.opacity }
    if ($null -ne $winOpacity) {
        $o = ([double]$winOpacity).ToString([cultureinfo]::InvariantCulture)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  config.window_background_opacity = $o")
        if ($Theme.useAcrylic) {
            # useAcrylic is the blur, and macos_window_background_blur is
            # macOS-only. GUARDED rather than emitted unconditionally: this
            # file is written on Linux too, wezterm's config_builder REJECTS a
            # field it does not know, and a rejected field is the user's whole
            # config replaced by the default one. wezterm.target_triple is the
            # value WezTerm itself resolves the platform with -- measured here
            # as 'aarch64-apple-darwin'.
            [void]$sb.AppendLine("  if wezterm.target_triple:find('darwin') then")
            [void]$sb.AppendLine("    config.macos_window_background_blur = 20")
            [void]$sb.AppendLine("  end")
        }
    }

    # theme.json tabColor -> the active tab's colours.
    #
    # MERGED field by field, never assigned wholesale. config.colors is the
    # table the user is most likely to have written themselves, and it is also
    # where a color_scheme's per-key overrides live, so `config.colors = { ... }`
    # would delete settings this module never asked about. Each `or {}` below
    # creates a level only when the user has none.
    #
    # active_tab alone, not inactive_tab: this config is global to WezTerm
    # rather than per-profile, so colouring both would paint the whole tab bar
    # the accent colour and erase the active/inactive distinction. Windows
    # Terminal's tabColor tints the tab of the profile in front, which is the
    # active one.
    if ($Theme -and (Test-WezTermHexColor $Theme.tabColor)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  config.colors = config.colors or {}")
        [void]$sb.AppendLine("  config.colors.tab_bar = config.colors.tab_bar or {}")
        [void]$sb.AppendLine("  config.colors.tab_bar.active_tab = config.colors.tab_bar.active_tab or {}")
        [void]$sb.AppendLine("  config.colors.tab_bar.active_tab.bg_color = $(& $q $Theme.tabColor)")
        $tabFg = Get-WezTermTabForeground $Theme.tabColor
        if ($tabFg) {
            [void]$sb.AppendLine("  config.colors.tab_bar.active_tab.fg_color = $(& $q $tabFg)")
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
            # '100%', never the BackgroundSize used for the image: a Color
            # source with Cover or Contain is a config error --
            # "Cover is not implemented for background color. Use e.g.
            # width = '100%' instead" (config/src/background.rs).
            [void]$sb.AppendLine("      width = '100%', height = '100%',")
            if ($null -ne $winOpacity) {
                # The style's opacity, on the layer, because with a layer list
                # this is the alpha that reaches the screen -- see the long
                # note at config.window_background_opacity above.
                [void]$sb.AppendLine("      opacity = $(([double]$winOpacity).ToString([cultureinfo]::InvariantCulture)),")
            }
            [void]$sb.AppendLine("    },")
        }
        # An ABSOLUTE path: File.path is a plain String handed to fs::read, with
        # no config-dir, no ~ and no $HOME expansion, and a path it cannot read
        # is dropped with only a log line -- no background and no error.
        [void]$sb.AppendLine("    {")
        [void]$sb.AppendLine("      source = { File = { path = $(& $q $BackgroundImage) } },")
        [void]$sb.AppendLine("      width = $(& $q $size), height = $(& $q $size),")
        # From the style, not hardcoded. This was 'Center'/'Middle' for every
        # style, so a composition built around where its image sits was silently
        # re-centred: tombraider's own README says "right-aligned image so text
        # sits on the left half", and it was being centred under the text.
        $al = Get-WezTermBackgroundAlignment ($Theme.backgroundImageAlignment)
        [void]$sb.AppendLine("      horizontal_align = $(& $q $al.H), vertical_align = $(& $q $al.V),")
        # NoRepeat on both axes, always. WezTerm TILES a background layer by
        # default, and Contain deliberately leaves space -- it fits the image
        # inside the pane without cropping, so a wide window has bare strips at
        # the sides and WezTerm fills them with copies. Reported on `tombraider`
        # (uniform -> Contain) as the image duplicating once the terminal got
        # wide enough.
        #
        # Not a judgement call: Windows Terminal is what these styles are
        # authored against, and NONE of its four backgroundImageStretchMode
        # values tile. `none` draws one copy at natural size, `fill` stretches
        # one, `uniform` and `uniformToFill` scale one. A style asking for any of
        # them is asking for exactly one image, so repeating it is this writer
        # inventing a look the style never described.
        [void]$sb.AppendLine("      repeat_x = 'NoRepeat', repeat_y = 'NoRepeat',")
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

    The write itself, and the encoding, are Write-WezTermModuleText's. With a
    picker's -Session it goes through Write-FilePreview instead, which records
    the preview first and refuses a module someone else rewrote ('changed').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)]$Scheme,
        $Theme,
        [AllowNull()][string]$BackgroundImage,
        [string]$HomeDir,
        # Forwarded by what the caller BOUND, so "unbound" still means "this
        # style's own layout" and an explicit $null still means "omit it".
        $LayoutTheme,
        [AllowNull()][hashtable]$Session
    )

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    $path = Get-WezTermModulePath @splat

    # Verified here so a bad path surfaces in PowerShell rather than as a missing
    # background and a line in a log the user will never open.
    if ($BackgroundImage -and -not (Test-Path -LiteralPath $BackgroundImage)) {
        $BackgroundImage = $null
    }

    # Forwarded by what was BOUND, not by value: $LayoutTheme has three states
    # and only two of them are values. Passing it unconditionally would turn
    # "unbound" into an explicit $null and silently drop font and padding from
    # every normal apply -- the splat trap in CLAUDE.md, pointed at a parameter
    # whose $null is meaningful.
    $layoutSplat = @{}
    if ($PSBoundParameters.ContainsKey('LayoutTheme')) { $layoutSplat.LayoutTheme = $LayoutTheme }
    $lua = Get-WezTermStyleLua -StyleName $StyleName -Scheme $Scheme -Theme $Theme `
                               -BackgroundImage $BackgroundImage @layoutSplat
    if ($Session) {
        $r = Write-FilePreview -Session $Session -Text $lua
        if ($r -eq 'current') { return 'unchanged' }
        return $r
    }
    return (Write-WezTermModuleText -Path $path -Text $lua)
}

function Write-WezTermModuleText {
    <#
    .SYNOPSIS
    Write a generated module's text to $Path. Returns 'written' | 'unchanged' | 'failed'.

    .DESCRIPTION
    The one place the module is written as text, so a change to how it is
    written has one place to land. Through here: an apply
    (Write-WezTermStyleModule), the picker's preview (which calls
    Write-WezTermStyleModule), the picker's preview and Esc (Write-FilePreview
    and Restore-FilePreview), and reset (Clear-WezTermStyleModule). Only the
    removal of a module a picker session itself created does not go through
    here.

    UTF-8 without BOM, not Get-RcFileEncoding. The file belongs wholly to
    TerminalStyles: it is written whole, and read back only by TerminalStyles --
    the 'unchanged' check below, and Test-WezTermModuleStyled for reset and
    uninstall -- so there is no user content to carry through byte for byte,
    and a BOM ahead of a Lua chunk is a parse error. Every read of it stays
    UTF-8 too, never the decoder for files the user owns: read as ISO-8859-1, a
    module holding a non-ASCII background path would never compare equal to
    the text that wrote it, so every apply would rewrite it and make WezTerm
    reload every window for nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $enc = [System.Text.UTF8Encoding]::new($false)
        if (Test-Path -LiteralPath $Path) {
            # Rewriting an identical file would still trip WezTerm's config
            # reload watch, so an unchanged style does not repaint the window.
            # -ceq: a module that differs only in case is a different module --
            # a style name, or a background path on a case-sensitive file
            # system -- and the picker's preview session, which compares with
            # -ceq, records it as written.
            if ([System.IO.File]::ReadAllText($Path, $enc) -ceq $Text) { return 'unchanged' }
        }
        [System.IO.File]::WriteAllText($Path, $Text, $enc)
        return 'written'
    } catch { return 'failed' }
}

function Get-WezTermUnstyledLua {
    <#
    .SYNOPSIS
    The module a reset leaves: one that applies nothing. Pure.

    .DESCRIPTION
    A table with a callable apply_to_config, never an empty file. The wiring
    line's pcall guards only the require: an empty chunk's require returns
    true, `ts.apply_to_config(config)` is then a call on a boolean, and that is
    a config error -- which in WezTerm is the user's whole wezterm.lua replaced
    by the default config. Loaded through the wiring line by a real WezTerm,
    this form evaluates back to the user's own config.

    Its STATEMENTS are how Test-WezTermModuleStyled recognises it, so they stay
    exactly as they are: changing one makes every module an earlier reset left
    read as styled. Its comments are free to change.
    #>
    $sb = [System.Text.StringBuilder]::new()
    Add-WezTermModuleHeader -Builder $sb -What 'with no style applied'
    [void]$sb.AppendLine('local M = {}')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('function M.apply_to_config(config)')
    [void]$sb.AppendLine('  return config')
    [void]$sb.AppendLine('end')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('return M')
    $sb.ToString()
}

function Get-WezTermModuleCode {
    # A generated module's statements: every line that is not blank and not a
    # `--` comment, kept as it is -- indentation included -- and joined with a
    # line feed. Split on CR LF or LF, so the two line endings of one file
    # compare equal: AppendLine writes CR LF on Windows. A regex rather than
    # String.StartsWith, whose default comparison is culture-sensitive.
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    @("$Text" -split '\r?\n' | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*--' }) -join "`n"
}

function Test-WezTermModuleStyled {
    <#
    .SYNOPSIS
    Does the module at $Path still apply a style?

    .DESCRIPTION
    The one question reset (is there a style to take out?) and uninstall (does
    the file it could not delete keep WezTerm styled?) both ask about the file.

    $false when there is no file, and when its statements are the unstyled
    module's, whatever its comments say. $true for anything else: a style an
    apply wrote, a module an older release wrote, or a file this cannot read.
    Unreadable counts as styled because that answer's message names the file
    and says it keeps the style, so the user goes and looks; the other answer
    would print a success line nobody had checked.

    Statements, not the whole text, so a reworded header -- the wiring line it
    quotes included -- does not turn every module an earlier reset left into a
    styled one, and CR LF against LF does not matter. -cne, the same
    case-sensitive comparison as Write-WezTermModuleText's 'unchanged' check
    (-ceq), so the two cannot disagree about one file; change either one and
    the other has to follow.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    } catch { return $true }
    return ((Get-WezTermModuleCode $text) -cne (Get-WezTermModuleCode (Get-WezTermUnstyledLua)))
}

function Clear-WezTermStyleModule {
    <#
    .SYNOPSIS
    The reset half of the WezTerm writer. Returns 'cleared' | 'none' | 'failed'.

    .DESCRIPTION
    Rewrites the module to Get-WezTermUnstyledLua -- not Remove-Item, for the
    watch-list reason in this file's header. Uninstall keeps its single delete.

    'none' has one meaning: nothing styled WezTerm through the module, and
    nothing was written -- either there is no module, or it already applies
    nothing. It never creates a module, or ~/.config/wezterm, where there was
    none: the predicate answers before the write could create the folder.

    -HomeDir is Write-WezTermStyleModule's seam, forwarded only when bound, so a
    bound -HomeDir also overrides the ambient $XDG_CONFIG_HOME.
    #>
    [CmdletBinding()]
    param([string]$HomeDir)

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    $path = Get-WezTermModulePath @splat

    if (-not (Test-WezTermModuleStyled -Path $path)) { return 'none' }
    switch (Write-WezTermModuleText -Path $path -Text (Get-WezTermUnstyledLua)) {
        'written'   { return 'cleared' }
        'unchanged' { return 'none' }    # unreachable while the predicate and the helper agree
        default     { return 'failed' }
    }
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
            # Read-RcFileText, the one decoding every reader of a user's rc or
            # config file uses; read-only here, and its unanchored match is
            # unaffected by a BOM.
            $text = (Read-RcFileText -Path $p).Text
        } catch { return $false }
        return $text -match "require\s*[\(,]?\s*['`"]terminalstyles['`"]"
    }
    return $false
}

# The tag a tab carries: a user variable the generated Lua module reads per tab.
# A `/` cannot appear in any resolvable style name (Test-StyleNameIsSingleSegment),
# so the two markers below cannot collide with a style.
$script:WezTermTagVar           = 'TERMINALSTYLES_STYLE'
$script:WezTermTagUnstyled      = '/unstyled'
$script:WezTermTagPreviewPrefix = '/preview/'

function Test-WezTermPerTab {
    <#
    .SYNOPSIS
    Does this session style one WezTerm tab at a time?

    .DESCRIPTION
    True only inside WezTerm, off Windows, with the require line wired into the
    config WezTerm loads. -Kind, -Platform and -HomeDir are test seams; -HomeDir
    is forwarded only when bound, so an unbound one means the live $HOME.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Kind = (Get-TerminalKind),
        [string]$Platform = (Get-TStylesPlatform),
        [string]$HomeDir
    )
    if ($Kind -ne 'WezTerm') { return $false }
    if ($Platform -eq 'Windows') { return $false }
    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    return [bool](Test-WezTermStyleWired @splat)
}

function Get-WezTermTagPacket {
    <#
    .SYNOPSIS
    The escape sequence that sets this tab's TERMINALSTYLES_STYLE user variable.

    .DESCRIPTION
    ESC ] 1337 ; SetUserVar=NAME=<base64 of UTF-8 Value> BEL. Inside tmux it is
    wrapped in a DCS passthrough with every ESC doubled. An empty Value is valid
    and clears the tag.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [bool]$InTmux = [bool]$env:TMUX
    )
    $esc = [string][char]27
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
    $packet = "$esc]1337;SetUserVar=$($script:WezTermTagVar)=$b64$([char]7)"
    if ($InTmux) { return "${esc}Ptmux;" + $packet.Replace($esc, "$esc$esc") + "$esc\" }
    return $packet
}

function Get-WezTermTabKey {
    # "<socket>|<pane>" identifies one WezTerm pane across processes; $null when
    # either half is missing, i.e. outside WezTerm.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (-not $env:WEZTERM_UNIX_SOCKET -or -not $env:WEZTERM_PANE) { return $null }
    return "$($env:WEZTERM_UNIX_SOCKET)|$($env:WEZTERM_PANE)"
}

function Get-WezTermTabRecordPath {
    Join-Path $script:TStylesDataRoot 'wezterm-tabs.json'
}

function Read-WezTermTabRecordTable {
    # key -> value, as an ordered hashtable. Throws on an unreadable file; a
    # missing file is an empty table. Walks PSObject.Properties because Windows
    # PowerShell 5.1 has no ConvertFrom-Json -AsHashtable.
    $path = Get-WezTermTabRecordPath
    $table = [ordered]@{}
    if (-not [System.IO.File]::Exists($path)) { return $table }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
    $obj = $text | ConvertFrom-Json
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $obj.PSObject.Properties) { $table[$p.Name] = [string]$p.Value }
    }
    return $table
}

function Set-WezTermTabRecord {
    <#
    .SYNOPSIS
    Remember which style this tab carries, so a later process can read it back.

    .DESCRIPTION
    Writes wezterm-tabs.json under the data root: key -> value, where '' means
    unstyled. Every entry whose socket (the part before `|`) no longer exists is
    dropped, so the file does not grow with every WezTerm session. A socket is
    not a regular file, hence Test-Path rather than a file-only check. A corrupt
    existing file is treated as empty and rewritten.
    Returns 'ok', 'failed', or 'nokey' (not inside WezTerm; nothing written).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $key = Get-WezTermTabKey
    if (-not $key) { return 'nokey' }
    try {
        $table = [ordered]@{}
        try { $table = Read-WezTermTabRecordTable } catch { $table = [ordered]@{} }
        $kept = [ordered]@{}
        foreach ($k in $table.Keys) {
            $sock = $k.Split('|')[0]
            if ($sock -and (Test-Path -LiteralPath $sock)) { $kept[$k] = $table[$k] }
        }
        $kept[$key] = $Value
        $path = Get-WezTermTabRecordPath
        $dir = Split-Path -Parent $path
        if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        $json = $kept | ConvertTo-Json -Depth 2
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
        return 'ok'
    } catch { return 'failed' }
}

function Get-WezTermTabRecord {
    <#
    .SYNOPSIS
    This tab's recorded value; $null when there is no key, no file, an unreadable
    file, or no entry. '' (unstyled) is a real answer, distinct from $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $key = Get-WezTermTabKey
    if (-not $key) { return $null }
    try {
        $table = Read-WezTermTabRecordTable
        if ($table.Contains($key)) { return [string]$table[$key] }
    } catch { }
    return $null
}

# The comment line that tells a per-tab module from the single-style one an
# older release wrote: the line right after Add-WezTermModuleHeader's three.
# Written by Get-WezTermTabModuleLua, read by Test-WezTermTabModule.
$script:WezTermTabModuleMarker = '-- TerminalStyles per-tab module'

function Get-WezTermTabMarkerPath {
    # The empty file that says "the WezTerm module is the per-tab one", for the
    # zsh/bash loader, which cannot ask PowerShell. Written beside the per-tab
    # record, under the data root.
    Join-Path $script:TStylesDataRoot 'wezterm-pertab'
}

function Get-WezTermBackgroundCandidates {
    <#
    .SYNOPSIS
    The paths a style's look may draw its background from, in order.

    .DESCRIPTION
    The file in the style's own folder when there is one, else -- for a style
    tuned from another -- the file in its base's folder: the first two tiers of
    Get-StyleBundledBackground. Otherwise every background.<ext> in the cache
    folder that function reads and fetches into (the base's, for a tuned
    style), in Get-BackgroundImageExtensions order, WHETHER OR NOT THE FILE
    EXISTS. The module checks them when it builds a window's look, so an image
    the picker's download job lands after the module was written shows on the
    next look of that style, with no rewrite. Nothing here fetches.

    Unrolled, so a caller wraps it in @().
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$StyleDir)

    $own = Get-BackgroundFileIn -Directory $StyleDir
    if ($own) { return $own }
    $baseDir = Get-TunedBaseDir -StyleDir $StyleDir
    if ($baseDir) {
        $inherited = Get-BackgroundFileIn -Directory $baseDir
        if ($inherited) { return $inherited }
    }
    $cacheDir = Get-StyleBackgroundCacheDir -StyleDir $StyleDir
    foreach ($ext in @(Get-BackgroundImageExtensions)) { Join-Path $cacheDir "background.$ext" }
}

function Get-WezTermStyleLook {
    <#
    .SYNOPSIS
    One style's entry in the per-tab module's LOOKS table. Pure.

    .DESCRIPTION
    Data, not statements: the module's Lua turns it into a window's override
    (look_of), so every rule that decides a value is here and every rule about
    what WezTerm does with it is there.

      scheme   the color_schemes body, by Add-WezTermSchemeBody's rule
      cursor   default_cursor_style            (Get-WezTermCursorStyle)
      opacity  window_background_opacity, and the base layer's opacity
                                               (Get-WezTermWindowOpacity)
      blur     20 when useAcrylic asks for it on a translucent window
      tab_bg   colors.tab_bar.active_tab.bg_color
      tab_fg   its readable foreground         (Get-WezTermTabForeground)
      base     the scheme's background, for the colour layer under the image
      images   Get-WezTermBackgroundCandidates, every one of them, in order
      image    the image layer's size, alignment and opacity

    A value the style does not give is left out, never written as nil, so the
    Lua's `if look.x` is the one test of "the style sets this". No font, size
    or padding: those stay the user's own, in every tab.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)]$Scheme,
        [AllowNull()]$Theme,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][string[]]$BackgroundCandidates
    )

    $q = { param($v) ConvertTo-WezTermLuaString $v }
    $inv = [cultureinfo]::InvariantCulture
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("  [$(& $q $StyleName)] = {")
    [void]$sb.AppendLine('    scheme = {')
    Add-WezTermSchemeBody -Builder $sb -Scheme $Scheme -Indent '      '
    [void]$sb.AppendLine('    },')

    $cursor = $null
    $opacity = $null
    if ($Theme) {
        $cursor = Get-WezTermCursorStyle $Theme.cursorShape
        $opacity = Get-WezTermWindowOpacity $Theme.opacity
    }
    if ($cursor) { [void]$sb.AppendLine("    cursor = $(& $q $cursor),") }
    if ($null -ne $opacity) {
        [void]$sb.AppendLine("    opacity = $(([double]$opacity).ToString($inv)),")
        # macOS-only, so the Lua drops it anywhere else: see the blur note in
        # Get-WezTermStyleLua for what an unknown field costs.
        if ($Theme.useAcrylic) { [void]$sb.AppendLine('    blur = 20,') }
    }
    if ($Theme -and (Test-WezTermHexColor $Theme.tabColor)) {
        [void]$sb.AppendLine("    tab_bg = $(& $q $Theme.tabColor),")
        $tabFg = Get-WezTermTabForeground $Theme.tabColor
        if ($tabFg) { [void]$sb.AppendLine("    tab_fg = $(& $q $tabFg),") }
    }
    if (Test-WezTermHexColor $Scheme.background) {
        [void]$sb.AppendLine("    base = $(& $q $Scheme.background),")
    }

    $paths = @($BackgroundCandidates | Where-Object { $_ })
    if ($paths.Count -gt 0) {
        [void]$sb.AppendLine("    images = { $(($paths | ForEach-Object { & $q $_ }) -join ', ') },")
        $stretch = $null
        $align = $null
        $imageOpacity = 1.0
        if ($Theme) {
            $stretch = $Theme.backgroundImageStretchMode
            $align = $Theme.backgroundImageAlignment
            $parsed = 0.0
            if ($null -ne $Theme.backgroundImageOpacity -and
                [double]::TryParse("$($Theme.backgroundImageOpacity)", [System.Globalization.NumberStyles]::Float,
                                   $inv, [ref]$parsed)) {
                $imageOpacity = $parsed
            }
        }
        $size = Get-WezTermBackgroundSize $stretch
        $al = Get-WezTermBackgroundAlignment $align
        [void]$sb.AppendLine("    image = { width = $(& $q $size), height = $(& $q $size), " +
                             "h = $(& $q $al.H), v = $(& $q $al.V), opacity = $($imageOpacity.ToString($inv)) },")
    }
    [void]$sb.AppendLine('  },')
    $sb.ToString()
}

function Get-WezTermTabModuleLua {
    <#
    .SYNOPSIS
    The per-tab module's text: every style's look, the default, and the event
    handlers that give each WezTerm window its active tab's look. Pure.

    .DESCRIPTION
    $Styles items are @{ Name; Scheme; Theme; BackgroundCandidates }.
    $DefaultStyle is the last-applied style, or $null / '' for none (after a
    reset); the base config carries it, so a new window and an untagged tab
    look like it from their first frame.

    GENERATION is the first 16 hex digits of the SHA-256 of this text with the
    stamp itself blank. Every window stores "<wanted>@<GENERATION>@<user>" once
    it is synced, <user> being a fingerprint of the user's own values for the
    keys a look sets, and skips a sync whose stamp matches. So a rewritten
    module (a new default changes what the base config draws) or an edited
    wezterm.lua re-syncs every window once, and the reload that
    set_config_overrides itself causes ends at the compare instead of looping.
    A sync replaces only the keys a look sets and keeps every other override
    the window holds.

    The reserved tag values are interpolated from $script:WezTermTagVar and its
    siblings, never retyped, so the PowerShell that writes a tag and the Lua
    that reads it cannot drift apart.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Styles,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$DefaultStyle
    )

    $q = { param($v) ConvertTo-WezTermLuaString $v }
    $default = 'nil'
    if ($DefaultStyle) { $default = & $q $DefaultStyle }

    $head = [System.Text.StringBuilder]::new()
    Add-WezTermModuleHeader -Builder $head -What "with every installed style's look"
    [void]$head.AppendLine($script:WezTermTabModuleMarker)
    [void]$head.AppendLine("local wezterm = require 'wezterm'")
    [void]$head.AppendLine('local M = {}')

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("local DEFAULT = $default")
    [void]$sb.AppendLine("local VAR, UNSTYLED, PREVIEW = $(& $q $script:WezTermTagVar), " +
                         "$(& $q $script:WezTermTagUnstyled), $(& $q $script:WezTermTagPreviewPrefix)")
    [void]$sb.AppendLine("local DARWIN = wezterm.target_triple:find('darwin') ~= nil")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Every installed style, by name. A tab names one in its user variable VAR.')
    [void]$sb.AppendLine('-- No font, size or padding: those stay your own in every tab.')
    [void]$sb.AppendLine('local LOOKS = {')
    foreach ($s in $Styles) {
        [void]$sb.Append((Get-WezTermStyleLook -StyleName $s.Name -Scheme $s.Scheme -Theme $s.Theme `
                                               -BackgroundCandidates @($s.BackgroundCandidates)))
    }
    [void]$sb.AppendLine('}')
    $lua = @'

-- What WezTerm draws for a key nobody set, for a look to fill in. The "none"
-- scheme is WezTerm's own default palette, registered in apply_to_config.
local BUILTIN = {
  color_scheme = 'TerminalStyles ' .. UNSTYLED,
  background = {},
  window_background_opacity = 1.0,
  macos_window_background_blur = 0,
  default_cursor_style = 'SteadyBlock',
}

-- Your own values for every key a look sets, read before the default style
-- is applied over them, and their fingerprint, which is part of every sync
-- stamp so an edit to your wezterm.lua reaches windows holding an override.
local USER = {}
local USERPRINT = ''
local KEYS = { 'color_scheme', 'background', 'window_background_opacity',
               'macos_window_background_blur', 'default_cursor_style', 'colors' }

local function copy(v)
  if type(v) ~= 'table' then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

-- Sorted keys, because pairs() order differs between Lua states, and plain
-- values only, so no userdata address enters it: an unchanged config gives
-- the same string on every evaluation.
local function fingerprint(v)
  local kind = type(v)
  if kind == 'string' then return string.format('%q', v) end
  if kind == 'number' or kind == 'boolean' then return tostring(v) end
  if kind ~= 'table' then return kind end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == 'boolean' then return b and not a end
    return (ta == 'number' or ta == 'string') and a < b
  end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = fingerprint(k) .. '=' .. fingerprint(v[k]) end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function exists(path)
  local f = io.open(path, 'rb')
  if f then f:close() end
  return f ~= nil
end

-- A COMPLETE table over KEYS. An override replaces only the keys it carries
-- and the base config holds the default style, so a key left out would show
-- the default's value. A key the style leaves alone is yours, else WezTerm's.
-- colors is always your own table with the style's active tab merged in.
local function look_of(name)
  local t = {}
  for _, k in ipairs(KEYS) do
    local v = USER[k]
    if v == nil then v = BUILTIN[k] end
    t[k] = copy(v)
  end
  t.colors = t.colors or {}
  local look = LOOKS[name]
  if look then
    t.color_scheme = 'TerminalStyles ' .. name
    if look.cursor then t.default_cursor_style = look.cursor end
    if look.opacity then t.window_background_opacity = look.opacity end
    if look.blur then t.macos_window_background_blur = look.blur end
    if look.tab_bg then
      t.colors.tab_bar = t.colors.tab_bar or {}
      t.colors.tab_bar.active_tab = t.colors.tab_bar.active_tab or {}
      t.colors.tab_bar.active_tab.bg_color = look.tab_bg
      if look.tab_fg then t.colors.tab_bar.active_tab.fg_color = look.tab_fg end
    end
    -- The style's own colour first: with any layer list WezTerm stops drawing
    -- the pane's solid background, so whatever the image does not cover would
    -- show the desktop. Its alpha is the window opacity this look carries
    -- (the style's, else yours), because with a layer list WezTerm takes the
    -- layer's alpha and does not multiply in window_background_opacity. The
    -- image is the first candidate on disk NOW, so one downloaded after this
    -- file was written is found.
    local layers = {}
    if look.base then
      layers[#layers + 1] = { source = { Color = look.base }, width = '100%', height = '100%',
                              opacity = look.opacity or t.window_background_opacity }
    end
    for _, path in ipairs(look.images or {}) do
      if exists(path) then
        local i = look.image
        layers[#layers + 1] = {
          source = { File = { path = path } },
          width = i.width, height = i.height,
          horizontal_align = i.h, vertical_align = i.v,
          repeat_x = 'NoRepeat', repeat_y = 'NoRepeat',
          opacity = i.opacity,
        }
        break
      end
    end
    if #layers > 0 then t.background = layers end
  end
  if not DARWIN then t.macos_window_background_blur = nil end
  return t
end

-- A tag names a style; a preview tag counts only on the pane that carries it.
local function resolve(tag, preview_ok)
  if type(tag) ~= 'string' then return nil end
  if tag == UNSTYLED then return UNSTYLED end
  if preview_ok and tag:sub(1, #PREVIEW) == PREVIEW then
    local name = tag:sub(#PREVIEW + 1)
    if LOOKS[name] then return name end
    return nil
  end
  if LOOKS[tag] then return tag end
  return nil
end

local function tag_of(pane)
  local vars = pane:get_user_vars()
  if vars then return vars[VAR] end
  return nil
end

-- The style a window should show, one per tab: its active pane's tag, else
-- another pane's tag in the same tab (a new split starts untagged), else the
-- pane's pin. A pane is pinned at first sight to what its tab shows then --
-- another pane's tag, else another pane's pin, else the default -- and the pin
-- follows another pane's tag, so a split keeps its tab's look after a default
-- change or after the tagged pane closes. Pins live in wezterm.GLOBAL because
-- this file's locals reset on every config reload.
local function wanted(window, pane)
  local own = resolve(tag_of(pane), true)
  if own then return own end
  local key = 'ts_pin_' .. pane:pane_id()
  local theirs, their_pin = nil, nil
  local tab = window:active_tab()
  if tab then
    for _, other in ipairs(tab:panes()) do
      if other:pane_id() ~= pane:pane_id() then
        theirs = resolve(tag_of(other), false)
        if theirs then break end
        if their_pin == nil then their_pin = wezterm.GLOBAL['ts_pin_' .. other:pane_id()] end
      end
    end
  end
  if theirs then
    if wezterm.GLOBAL[key] ~= theirs then wezterm.GLOBAL[key] = theirs end
    return theirs
  end
  local pin = wezterm.GLOBAL[key]
  if pin == nil then
    pin = their_pin or DEFAULT or UNSTYLED
    wezterm.GLOBAL[key] = pin
  end
  return pin
end

-- set_config_overrides only when the wanted look changed, this file did, or
-- your own values did. Only the keys a look sets are replaced: any other
-- override (a font-size toggle in your own config, say) is kept. The base
-- config is the default style, so showing it takes none of those keys.
local function sync(window, pane)
  if not window or not pane then return end
  local want = wanted(window, pane)
  local stamp = want .. '@' .. GENERATION .. '@' .. USERPRINT
  local key = 'ts_win_' .. window:window_id()
  if wezterm.GLOBAL[key] == stamp then return end
  wezterm.GLOBAL[key] = stamp
  local overrides = window:get_config_overrides() or {}
  for _, k in ipairs(KEYS) do overrides[k] = nil end
  if want ~= (DEFAULT or UNSTYLED) then
    for k, v in pairs(look_of(want)) do overrides[k] = v end
  end
  window:set_config_overrides(overrides)
end

function M.apply_to_config(config)
  for _, k in ipairs(KEYS) do USER[k] = copy(config[k]) end
  USERPRINT = fingerprint(USER)
  config.color_schemes = config.color_schemes or {}
  config.color_schemes['TerminalStyles ' .. UNSTYLED] = wezterm.color.get_default_colors()
  for name, look in pairs(LOOKS) do
    config.color_schemes['TerminalStyles ' .. name] = look.scheme
  end
  for k, v in pairs(look_of(DEFAULT or UNSTYLED)) do config[k] = v end

  -- update-status fires on every tab switch as well as on its interval.
  wezterm.on('update-status', function(window, pane)
    sync(window, pane)
  end)
  -- A tag written by tstyles shows at once.
  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name == VAR then sync(window, window:active_pane()) end
  end)
  -- A rewrite of this file, or an edit to your own config, changes what a
  -- window should show; the stamp makes the reload that set_config_overrides
  -- causes stop at the compare.
  wezterm.on('window-config-reloaded', function(window, pane)
    sync(window, window:active_pane())
  end)
  return config
end

return M
'@
    # A here-string's line breaks are the script file's; AppendLine's are the
    # platform's, and the rest of the module is built from those.
    foreach ($line in ($lua -split '\r?\n')) { [void]$sb.AppendLine($line) }
    $tail = $sb.ToString()

    $nl = [Environment]::NewLine
    $blank = $head.ToString() + "local GENERATION = ''" + $nl + $tail
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($blank))
    } finally { $sha.Dispose() }
    $generation = (-join ($hash | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)
    $head.ToString() + "local GENERATION = '$generation'" + $nl + $tail
}

function Write-WezTermTabModule {
    <#
    .SYNOPSIS
    Write the per-tab module for every installed style. Returns 'written' |
    'unchanged' | 'failed'.

    .DESCRIPTION
    A style whose scheme.json is missing or will not parse is left out -- it
    has no palette to show, and one broken user style must not cost every
    other its look. A theme.json that will not parse reads as no theme, as on
    apply. The build never fetches: a background not on disk yet is a cache
    path the module checks when it builds a look.

    The write is Write-WezTermModuleText's. On 'written' or 'unchanged' the
    marker file (Get-WezTermTabMarkerPath) is written too, for the zsh/bash
    loader. Best-effort: a data root that cannot take an empty file cannot take
    the per-tab record either, and the loader without the marker only replays
    the last-applied palette, as before per-tab mode.

    -HomeDir is the module path's seam, forwarded only when bound (CLAUDE.md);
    a test also points $script:TStylesDataRoot at $TestDrive, which holds the
    marker and every cache path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$DefaultStyle,
        [string]$HomeDir
    )

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }
    $enc = [System.Text.UTF8Encoding]::new($false)

    $styles = @(foreach ($dir in @(Get-AvailableStyles)) {
        $scheme = $null
        try {
            $scheme = [System.IO.File]::ReadAllText((Join-Path $dir.FullName 'scheme.json'), $enc) |
                      ConvertFrom-Json -ErrorAction Stop
        } catch { $scheme = $null }
        if (-not $scheme) { continue }
        $theme = $null
        $themePath = Join-Path $dir.FullName 'theme.json'
        if ([System.IO.File]::Exists($themePath)) {
            try {
                $theme = [System.IO.File]::ReadAllText($themePath, $enc) | ConvertFrom-Json -ErrorAction Stop
            } catch { $theme = $null }
        }
        @{
            Name                 = $dir.Name
            Scheme               = $scheme
            Theme                = $theme
            BackgroundCandidates = @(Get-WezTermBackgroundCandidates -StyleDir $dir.FullName)
        }
    })

    $lua = Get-WezTermTabModuleLua -Styles $styles -DefaultStyle $DefaultStyle
    $status = Write-WezTermModuleText -Path (Get-WezTermModulePath @splat) -Text $lua
    if ($status -ne 'failed') {
        try {
            if (-not [System.IO.Directory]::Exists($script:TStylesDataRoot)) {
                [void][System.IO.Directory]::CreateDirectory($script:TStylesDataRoot)
            }
            [System.IO.File]::WriteAllText((Get-WezTermTabMarkerPath), '', $enc)
        } catch { }
    }
    return $status
}

function Test-WezTermTabModule {
    <#
    .SYNOPSIS
    Is the module at $Path the per-tab one?

    .DESCRIPTION
    True when the file exists and has the marker line Get-WezTermTabModuleLua
    writes; false for the single-style module, the module a reset leaves, no
    file, and a file that cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    try {
        if (-not [System.IO.File]::Exists($Path)) { return $false }
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    } catch { return $false }
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -ceq $script:WezTermTabModuleMarker) { return $true }
    }
    return $false
}
