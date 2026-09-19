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
        [void]$sb.AppendLine("      horizontal_align = 'Center', vertical_align = 'Middle',")
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
        [string]$HomeDir,
        # Forwarded by what the caller BOUND, so "unbound" still means "this
        # style's own layout" and an explicit $null still means "omit it".
        $LayoutTheme
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
