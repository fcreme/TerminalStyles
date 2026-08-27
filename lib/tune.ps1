# tune.ps1 -- `tstyles tune`: the live editor and the style it materialises.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Five knobs, split by what each can actually do. Brightness and saturation
# retint live over OSC on every terminal. Opacity and font can only be previewed
# on Windows Terminal, by writing a scratch style and running the REAL merge
# against it -- so the preview cannot drift from an apply. Off Windows Terminal
# they are recorded in the saved style and nothing there can show them.
#
# Save-TunedStyle materialises a full style, not a diff: it lands in the user
# styles dir and is thereafter indistinguishable from a hand-written one.

function New-TunedThemeObject {
    # Builds the theme.json object for a tuned style: base theme.json (or {})
    # with colorScheme/opacity/font overridden. Preserves font.weight and the
    # backgroundImage placeholder. Shared by Save-TunedStyle and the live
    # preview so the saved result matches what was previewed.
    param(
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$ColorScheme,
        [int]$Opacity,
        [string]$FontFace,
        [int]$FontSize
    )
    $themeSrc = Join-Path $BaseStyleDir 'theme.json'
    $theme = if (Test-Path -LiteralPath $themeSrc) {
        [System.IO.File]::ReadAllText($themeSrc, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } else { [pscustomobject]@{} }

    $theme | Add-Member -NotePropertyName colorScheme -NotePropertyValue $ColorScheme -Force
    $theme | Add-Member -NotePropertyName opacity     -NotePropertyValue $Opacity     -Force

    $font = if ($theme.PSObject.Properties.Match('font').Count) { $theme.font } else { [pscustomobject]@{} }
    $font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
    $font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize -Force
    $theme | Add-Member -NotePropertyName font -NotePropertyValue $font -Force
    return $theme
}


function Test-SameStyleDirectory {
    <#
    .SYNOPSIS
    Do two style paths name the same directory, as the HOST FILESYSTEM sees it?

    .DESCRIPTION
    Carved out as a pure function for the same reason Get-PickerViewport was: the
    decision is one line of subtlety that cannot be tested through its caller.
    Save-TunedStyle's effect here is "copy prompt.sh, or don't", and the case that
    matters -- styles/Eva versus styles/eva -- is not even expressible on the
    macOS and Windows filesystems the test suite mostly runs on, where the two
    are one directory. Mock Get-TStylesPlatform and ask this instead.

    Case sensitivity follows the platform, not PowerShell. -eq is case-insensitive
    everywhere, so on Linux a "Save as Eva" from a base at styles/eva looked like
    the same directory and skipped the prompt.sh copy into what was really a brand
    new style, costing it the zsh/bash prompt entirely.

    Returns $false on any path it cannot resolve: the copies this guards are
    idempotent, so a wrong $false costs a redundant write and a wrong $true costs
    a missing prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$A,
        [Parameter(Mandatory)][AllowEmptyString()][string]$B
    )

    if (-not $A -or -not $B) { return $false }
    try {
        $cmp = if ((Get-TStylesPlatform) -eq 'Linux') { [System.StringComparison]::Ordinal }
               else { [System.StringComparison]::OrdinalIgnoreCase }
        $sep = [System.IO.Path]::DirectorySeparatorChar
        return [string]::Equals(
            [System.IO.Path]::GetFullPath($A).TrimEnd($sep),
            [System.IO.Path]::GetFullPath($B).TrimEnd($sep),
            $cmp)
    } catch { return $false }
}

function Save-TunedStyle {
    # Materializes a tuned style into $DataRoot\styles\$SaveName\:
    #   scheme.json (adjusted colors, name = $SaveName)
    #   theme.json  (base theme + colorScheme/opacity/font overrides)
    #   profile.ps1 (copied from base if present)
    #   tune.json   (deltas + base name, for re-tuning)
    param(
        [Parameter(Mandatory)]$AdjustedScheme,
        [Parameter(Mandatory)][string]$SaveName,
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$BaseName,
        [int]$Brightness, [int]$Saturation, [int]$Opacity,
        [string]$FontFace, [int]$FontSize
    )
    $destDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $SaveName
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Clone so the caller's object is not mutated (matches Get-AdjustedScheme's contract).
    $scheme = $AdjustedScheme.PSObject.Copy()
    $scheme | Add-Member -NotePropertyName name -NotePropertyValue $SaveName -Force
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'scheme.json'),
        ($scheme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    $theme = New-TunedThemeObject -BaseStyleDir $BaseStyleDir -ColorScheme $SaveName `
        -Opacity $Opacity -FontFace $FontFace -FontSize $FontSize
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'theme.json'),
        ($theme | ConvertTo-Json -Depth 16),
        [System.Text.UTF8Encoding]::new($false))

    # Re-tuning a style that was already saved with Overwrite makes $BaseStyleDir
    # and $destDir the SAME directory, so every "copy from base to dest" below is
    # really a copy of a file onto itself. Left unguarded that appends a second
    # `# tstyles-tuned:` marker to profile.ps1 on each repeat and makes Copy-Item
    # throw a red "Cannot overwrite the item with itself" for prompt.sh, at save
    # time, after the user has already committed.
    # Compared the way the HOST FILESYSTEM compares, not the way PowerShell's
    # -eq does. -eq is case-insensitive, so on Linux (case-sensitive) a "Save
    # as" of `Eva` from a base at styles/eva would look like the same directory
    # and skip the prompt.sh copy into what is really a brand-new style --
    # costing it the zsh/bash prompt the copy exists to provide.
    $sameDir = Test-SameStyleDirectory -A $destDir -B $BaseStyleDir

    $profileSrc = Join-Path $BaseStyleDir 'profile.ps1'
    if (Test-Path -LiteralPath $profileSrc) {
        # Append a per-style marker so the materialized profile is byte-distinct
        # from the base's (we copied it verbatim). Without this, Get-CurrentStyleName
        # -- which byte-compares current-style.ps1 against each style's profile.ps1
        # and returns the alphabetically-first match -- would attribute this tuned
        # style to its base. The marker is an inert comment (profile is dot-sourced).
        $profileContent = [System.IO.File]::ReadAllText($profileSrc, [System.Text.UTF8Encoding]::new($false))
        # Strip any marker a previous save left, so re-tuning appends exactly one
        # rather than accumulating a line per save. Idempotent either way.
        $profileContent = [regex]::Replace($profileContent,
            '(\r?\n)?^[ \t]*#[ \t]*tstyles-tuned:.*$', '', 'Multiline').TrimEnd("`r", "`n")
        $marker = [Environment]::NewLine + "# tstyles-tuned: $SaveName" + [Environment]::NewLine
        [System.IO.File]::WriteAllText(
            (Join-Path $destDir 'profile.ps1'),
            ($profileContent + $marker),
            [System.Text.UTF8Encoding]::new($false))
    }

    # The zsh/bash prompt, copied verbatim. It needs no per-style marker: unlike
    # profile.ps1, nothing byte-compares it to identify the active style. Without
    # this a tuned style has no shell prompt at all, so a zsh user who tunes
    # anything silently loses the banner and prompt while keeping the colors.
    $promptSrc = Join-Path $BaseStyleDir 'prompt.sh'
    if (-not $sameDir -and (Test-Path -LiteralPath $promptSrc)) {
        Copy-Item -LiteralPath $promptSrc -Destination (Join-Path $destDir 'prompt.sh') -Force
    }

    $tune = [pscustomobject]@{
        schemaVersion = 1
        base          = $BaseName
        brightness    = $Brightness
        saturation    = $Saturation
        opacity       = $Opacity
        fontFace      = $FontFace
        fontSize      = $FontSize
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $destDir 'tune.json'),
        ($tune | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false))

    return $destDir
}

function Get-TunedBaseBackground {
    # If $StyleDir is a tuned style (tune.json with a 'base'), resolve and
    # return the base style's background (with the base's own lazy-fetch).
    # $null if not tuned / base missing / base has no background. Strictly one
    # hop: the base is resolved with -NoInherit, so cyclic tune.json (A->B->A)
    # cannot recurse.
    param([Parameter(Mandatory)][string]$StyleDir)
    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (-not (Test-Path -LiteralPath $tuneFile)) { return $null }
    try {
        $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    } catch { return $null }
    if (-not $tune.base) { return $null }
    $baseDir = Get-StyleDir -StyleName $tune.base
    if (-not $baseDir -or ($baseDir -eq $StyleDir)) { return $null }
    return Get-StyleBundledBackground -StyleDir $baseDir -NoInherit
}

function Resolve-TuneSeed {
    # Computes the working base style + the initial knob values for `tstyles tune`.
    # Extracted from Invoke-TerminalStyleTune so the seeding rules are unit-testable.
    #
    # Rules:
    #   * A tuned style (tune.json with a base that still resolves) seeds the base
    #     dir + the recorded deltas, so re-deriving never double-applies onto the
    #     already-baked scheme.
    #   * Otherwise (a plain style, OR a tuned style whose recorded base was
    #     deleted/renamed) the working base is the style itself, and opacity/font
    #     seed from that style's OWN theme.json -- so re-tuning preserves the saved
    #     values instead of snapping back to the hardcoded defaults.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir
    )

    $seed = [pscustomobject]@{
        BaseName = $StyleName; BaseDir = $StyleDir
        Brightness = 0; Saturation = 0; Opacity = 100; FontFace = $null; FontSize = 12
    }
    $seededFromTune = $false

    $tuneFile = Join-Path $StyleDir 'tune.json'
    if (Test-Path -LiteralPath $tuneFile) {
        try {
            $tune = [System.IO.File]::ReadAllText($tuneFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($tune.base) {
                $resolvedBaseDir = Get-StyleDir -StyleName $tune.base
                # Guard against a self-referential base (an Overwrite save writes
                # the baked scheme back onto the base name and records base = that
                # name). Re-seeding the deltas here would re-apply them on top of
                # the already-baked scheme -- color drift on every re-tune. Fall
                # through to own-theme.json seeding (neutral brightness/saturation)
                # instead. Mirrors the self-reference guard in Get-TunedBaseBackground.
                if ($resolvedBaseDir -and $resolvedBaseDir -ne $StyleDir) {
                    $seed.BaseName   = $tune.base
                    $seed.BaseDir    = $resolvedBaseDir
                    $seed.Brightness = [int]$tune.brightness
                    $seed.Saturation = [int]$tune.saturation
                    $seed.Opacity    = [int]$tune.opacity
                    $seed.FontFace   = [string]$tune.fontFace
                    $seed.FontSize   = [int]$tune.fontSize
                    $seededFromTune  = $true
                }
            }
        } catch { }
    }

    # When NOT seeded from a resolvable tune, take opacity/font from the working
    # base's own theme.json (the base for a plain style; the style itself for a
    # tuned style whose base vanished).
    if (-not $seededFromTune) {
        $baseThemePath = Join-Path $seed.BaseDir 'theme.json'
        if (Test-Path -LiteralPath $baseThemePath) {
            try {
                $baseTheme = [System.IO.File]::ReadAllText($baseThemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                if ($baseTheme.PSObject.Properties.Match('opacity').Count) { $seed.Opacity = [int]$baseTheme.opacity }
                if ($baseTheme.PSObject.Properties.Match('font').Count) {
                    if ($baseTheme.font.PSObject.Properties.Match('face').Count) { $seed.FontFace = [string]$baseTheme.font.face }
                    if ($baseTheme.font.PSObject.Properties.Match('size').Count) { $seed.FontSize = [int]$baseTheme.font.size }
                }
            } catch { }
        }
    }

    return $seed
}

function Invoke-TerminalStyleTune {
    # `tstyles tune [name]` -- interactive live tuning of a style's brightness,
    # saturation, opacity, font face, and font size. Colors retint instantly
    # via OSC; opacity/font ride a debounced settings.json write (through a
    # scratch style dir reusing Merge-StyleIntoSettings). Esc reverts byte-
    # exact; Enter prompts Save / Save As into the user-styles dir.
    [CmdletBinding()]
    param([string]$StyleName)

    Show-UpdateNoticeIfAvailable

    # Windows Terminal previews every knob live, by merging a scratch style into
    # settings.json and letting WT reload. Elsewhere only the color knobs can be
    # previewed -- brightness and saturation ride the OSC packet, while opacity
    # and font can reach the terminal only through a profile, which applies to a
    # new window rather than this one.
    #
    # That is a reduced tuner, not a broken one: the color work is the part
    # people actually sit and adjust, and the font/opacity values are still
    # saved with the style. So run it, and say up front which knobs will not
    # move on screen -- earlier versions refused outright here, which was more
    # conservative than the facts warranted.
    $tuneKind        = Get-TerminalKind
    $tuneUsesSettings = ($tuneKind -eq 'WindowsTerminal')

    # --- Resolve the style (all guards run BEFORE any console interaction) ---
    if (-not $StyleName) {
        $StyleName = Get-CurrentStyleName
        if (-not $StyleName) {
            Write-Error "No active style detected. Try: tstyles tune <name>"
            return
        }
    }
    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    $settingsPath = $null
    if ($tuneUsesSettings) {
        $settingsPath = Find-WTSettingsPath
        if (-not $settingsPath) {
            Write-Error "Could not locate Windows Terminal settings.json."
            return
        }
    }

    # --- Establish working base scheme + seed knob values ---
    # If this style is itself a tuned style (has tune.json), the working base
    # is its recorded base's PRISTINE scheme, and knobs seed from the deltas
    # (so re-deriving never double-applies onto the baked file). Otherwise the
    # working base is this style's own scheme with neutral knobs.
    $seed = Resolve-TuneSeed -StyleName $StyleName -StyleDir $styleDir
    $baseName   = $seed.BaseName
    $baseDir    = $seed.BaseDir
    $brightness = $seed.Brightness
    $saturation = $seed.Saturation
    $opacity    = $seed.Opacity
    $fontFace   = $seed.FontFace
    $fontSize   = $seed.FontSize

    $baseScheme = [System.IO.File]::ReadAllText((Join-Path $baseDir 'scheme.json'), [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $fontList = @(Get-MonospaceFontList -Current $fontFace)
    if (-not $fontFace) { $fontFace = $fontList[0] }
    $fontIdx = [Math]::Max(0, [array]::IndexOf($fontList, $fontFace))

    # --- Target WT profile ---
    $originalJson = $null
    $target = $null
    if ($tuneUsesSettings) {
        $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
        $originalSettings = ConvertFrom-WTJson $originalJson
        $target = Get-CurrentWTProfileName -Settings $originalSettings
        if (-not $target) {
            Write-Error "Could not auto-detect a Windows Terminal profile to preview against."
            return
        }
        if (-not $env:WT_SESSION) {
            Write-Host "Note: live preview is only visible inside Windows Terminal." -ForegroundColor Yellow
        }
    } else {
        # Set expectations before the screen is taken over: the two color knobs
        # move on screen, the other three are only recorded.
        #
        # They are recorded and nothing more. Off Windows Terminal the only
        # writer is New-AppleTerminalProfile, whose profile carries colors and a
        # background image -- no font, no opacity (see Get-AppleTerminalProfileData).
        # Every other terminal gets escape sequences, which cannot carry either.
        # So promising "a new window shows them" sent the user to open one and
        # compare an unchanged font against the screenshot.
        Write-Host ""
        Write-Host ("  Tuning on {0}: brightness and saturation preview live." -f (Get-TerminalDisplayName -Kind $tuneKind)) -ForegroundColor DarkGray
        Write-Host "  Opacity and font are saved with the style, but this terminal cannot show them." -ForegroundColor DarkGray
        Write-Host ""
        Start-Sleep -Milliseconds 900
    }

    # --- Scratch dir for the debounced settings.json preview (reuses Merge) ---
    $scratchDir = Join-Path (Join-Path $script:TStylesDataRoot '.tune-preview') $baseName
    if (-not (Test-Path -LiteralPath $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }

    # Knob model: index 0..4 = brightness, saturation, opacity, font face, size.
    $sel = 0
    $confirmed = $false
    $applied = $false   # set true only after a saved style is applied; gates the revert
    $pendingApply = $false  # the explicit `& $writePreview` below seeds the preview; this gates only knob edits

    $hint  = "$([char]27)[38;2;160;160;160m"
    $reset = "$([char]27)[0m"

    # Recompute the adjusted scheme + cache its OSC packet.
    $adjusted   = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
    $oscPacket  = Get-SchemeOscPacket -Scheme $adjusted

    $writePreview = {
        # Write scratch scheme/theme then merge into settings.json (brings
        # opacity/font/background live). Colors are already shown via OSC.
        $adj = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        $adj | Add-Member -NotePropertyName name -NotePropertyValue $baseScheme.name -Force
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'scheme.json'),
            ($adj | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        $theme = New-TunedThemeObject -BaseStyleDir $baseDir -ColorScheme $baseScheme.name `
            -Opacity $opacity -FontFace $fontFace -FontSize $fontSize
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'theme.json'),
            ($theme | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
        # tune.json so background inheritance resolves the base GIF in preview.
        [System.IO.File]::WriteAllText((Join-Path $scratchDir 'tune.json'),
            ('{"base":"' + $baseName + '"}'), [System.Text.UTF8Encoding]::new($false))

        # The scratch style above is written either way -- Save-TunedStyle reads
        # it on Enter. Only the settings.json merge is Windows-Terminal-only.
        if (-not $tuneUsesSettings) { return }

        $preview = ConvertFrom-WTJson $originalJson
        $preview = Merge-StyleIntoSettings -Settings $preview -StyleDir $scratchDir `
            -TargetName $target -BackgroundImage '' -BackgroundImageProvided $false
        Write-SettingsAtomic -Path $settingsPath -Json ($preview | ConvertTo-Json -Depth 100)
    }

    $bar = {
        param([int]$Value, [int]$Min, [int]$Max)
        $width = 10
        $pos = [int][Math]::Round(($Value - $Min) / [double]($Max - $Min) * ($width - 1))
        $pos = [Math]::Max(0, [Math]::Min($width - 1, $pos))
        $cells = (1..$width | ForEach-Object { if (($_ - 1) -eq $pos) { 'o' } else { '-' } }) -join ''
        return "[$cells]"
    }

    $drawMenu = {
        Clear-Host
        Write-Host ""
        Write-Host "  Tuning " -NoNewline
        Write-Host "'$StyleName'" -ForegroundColor Cyan -NoNewline
        Write-Host "                      base: $baseName" -ForegroundColor DarkGray
        Write-Host "$hint  Up/Down select   Left/Right adjust   R reset color   Enter save   Esc cancel$reset"
        Write-Host ""
        $rows = @(
            @{ Label = 'Brightness'; Display = (& $bar $brightness -100 100); Value = ('{0:+#;-#;0}' -f $brightness) },
            @{ Label = 'Saturation'; Display = (& $bar $saturation -100 100); Value = ('{0:+#;-#;0}' -f $saturation) },
            @{ Label = 'Opacity';    Display = (& $bar $opacity 0 100);       Value = "$opacity%" },
            @{ Label = 'Font face';  Display = "< $fontFace >";                Value = '' },
            @{ Label = 'Font size';  Display = (& $bar $fontSize 6 36);        Value = "$fontSize" }
        )
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $color  = if ($i -eq $sel) { 'Yellow' } else { 'Gray' }
            $prefix = if ($i -eq $sel) { '   > ' } else { '     ' }
            Write-Host ($prefix + ('{0,-12} ' -f $rows[$i].Label) + ('{0,-14} ' -f $rows[$i].Display) + $rows[$i].Value) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  Preview  " -NoNewline
        Write-Host (Get-SchemeSwatch -Scheme $adjusted)
        Write-Host ""
    }

    # On-disk rolling backup before any preview write, so a hard kill mid-tune
    # leaves a recoverable copy (the in-memory $originalJson snapshot dies with
    # the process). Same rolling .bak the direct-apply/reset paths write.
    # Crash-recovery copy -- only meaningful where a settings.json is written.
    if ($tuneUsesSettings) { try { [System.IO.File]::WriteAllText("$settingsPath.bak", $originalJson, [System.Text.UTF8Encoding]::new($false)) } catch { } }

    [Console]::CursorVisible = $false
    $originalTitle = $Host.UI.RawUI.WindowTitle

    # Undo the live preview and put the terminal back the way it was found.
    #
    # Get-OscResetPacket hands colour control to the TERMINAL's own defaults,
    # which is right on Windows Terminal -- settings.json has just been restored
    # and WT repaints from it. Off Windows Terminal there is no such file: the
    # style being tuned was itself only escape sequences, so resetting drops the
    # user to a stock palette instead of the style they opened the tuner on.
    # Re-emit the unmodified base scheme there. Same fix, and the same reasoning,
    # as the picker's Esc.
    $restoreBaseLook = {
        if ($tuneUsesSettings) { Write-SettingsAtomic -Path $settingsPath -Json $originalJson }
        if (-not $tuneUsesSettings -and $baseScheme) {
            [Console]::Out.Write((Get-SchemeOscPacket -Scheme $baseScheme))
        } else {
            [Console]::Out.Write((Get-OscResetPacket))
        }
    }
    $needsRedraw = $true
    try {
        & $writePreview   # initial preview from seeds
        [Console]::Out.Write($oscPacket)

        while (-not $confirmed) {
            if ($needsRedraw) { & $drawMenu; $needsRedraw = $false }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $isColor = ($sel -eq 0 -or $sel -eq 1)
                switch ($key.Key) {
                    'UpArrow'   { if ($sel -gt 0) { $sel-- }; $needsRedraw = $true; continue }
                    'DownArrow' { if ($sel -lt 4) { $sel++ }; $needsRedraw = $true; continue }
                    'LeftArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Max(-100, $brightness - 5) }
                            1 { $saturation = [Math]::Max(-100, $saturation - 5) }
                            2 { $opacity    = [Math]::Max(0,    $opacity - 5) }
                            3 { $fontIdx = ($fontIdx - 1 + $fontList.Count) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Max(6, $fontSize - 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'RightArrow' {
                        switch ($sel) {
                            0 { $brightness = [Math]::Min(100, $brightness + 5) }
                            1 { $saturation = [Math]::Min(100, $saturation + 5) }
                            2 { $opacity    = [Math]::Min(100, $opacity + 5) }
                            3 { $fontIdx = ($fontIdx + 1) % $fontList.Count; $fontFace = $fontList[$fontIdx] }
                            4 { $fontSize = [Math]::Min(36, $fontSize + 1) }
                        }
                        if ($isColor) {
                            $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
                            $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                            [Console]::Out.Write($oscPacket)
                        }
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'R' {
                        $brightness = 0; $saturation = 0
                        $adjusted  = Get-AdjustedScheme -Scheme $baseScheme -Brightness 0 -Saturation 0
                        $oscPacket = Get-SchemeOscPacket -Scheme $adjusted
                        [Console]::Out.Write($oscPacket)
                        $pendingApply = $true; $needsRedraw = $true; continue
                    }
                    'Enter'  { if ($pendingApply) { & $writePreview; $pendingApply = $false }; $confirmed = $true; continue }
                    'Escape' {
                        & $restoreBaseLook
                        Clear-Host
                        Write-Host "Reverted." -ForegroundColor Yellow
                        return
                    }
                }
                continue
            }

            if ($pendingApply) { $pendingApply = $false; & $writePreview; continue }
            Start-Sleep -Milliseconds 50
        }

        # --- Confirmed: Save / Save As prompt ---
        Clear-Host
        Write-Host ""
        Write-Host "  Save tuned '$StyleName'?" -ForegroundColor Cyan
        Write-Host "    [1] Overwrite '$StyleName'   (shadows the bundled style)"
        Write-Host "    [2] Save as a new name"
        Write-Host ""
        $choice = (Read-Host "  Choose [1/2]").Trim()
        $saveName = $null
        if ($choice -eq '1') {
            $saveName = $StyleName
        } else {
            while (-not $saveName) {
                $candidate = (Read-Host "  New style name").Trim()
                if (-not $candidate) { Write-Host "  Cancelled." -ForegroundColor Gray; break }
                if ($candidate -notmatch '^[A-Za-z0-9._-]+$') {
                    Write-Host "  Use letters, digits, dot, underscore, or hyphen only." -ForegroundColor Yellow
                    continue
                }
                # Two different collisions, and only one of them loses work.
                #
                # A USER style of the same name is in the directory Save-TunedStyle
                # writes to, so saving over it destroys it -- and that was the case
                # with no warning at all. A BUNDLED style of the same name is only
                # shadowed: the original stays in the module and comes back if the
                # user style is deleted. The prompt used to warn about the harmless
                # one and stay silent about the destructive one.
                $userDir = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $candidate
                if (Test-Path -LiteralPath (Join-Path $userDir 'scheme.json')) {
                    $warn = (Read-Host "  '$candidate' already exists and will be REPLACED. Continue? [y/N]").Trim()
                    if ($warn -notmatch '^(?i)y') { continue }
                } else {
                    $bundledDir = Join-Path (Join-Path $script:TStylesModuleRoot 'styles') $candidate
                    if (Test-Path -LiteralPath (Join-Path $bundledDir 'scheme.json')) {
                        $warn = (Read-Host "  That shadows bundled '$candidate'. Continue? [y/N]").Trim()
                        if ($warn -notmatch '^(?i)y') { continue }
                    }
                }
                $saveName = $candidate
            }
        }

        if (-not $saveName) {
            # Treat an aborted save like a cancel: revert and exit.
            & $restoreBaseLook
            Write-Host "  Reverted (nothing saved)." -ForegroundColor Yellow
            return
        }

        # Bake + persist, then apply the saved style from a clean settings.json
        # so no preview-scheme pollution lingers.
        $finalScheme = Get-AdjustedScheme -Scheme $baseScheme -Brightness $brightness -Saturation $saturation
        Save-TunedStyle -AdjustedScheme $finalScheme -SaveName $saveName `
            -BaseStyleDir $baseDir -BaseName $baseName `
            -Brightness $brightness -Saturation $saturation -Opacity $opacity `
            -FontFace $fontFace -FontSize $fontSize | Out-Null

        if ($tuneUsesSettings) { Write-SettingsAtomic -Path $settingsPath -Json $originalJson }
        # -Target is a Windows Terminal profile name; off WT it is $null and the
        # apply resolves the host terminal itself.
        #
        # $applied gates the finally block's revert, so it has to mean "the style
        # really went on", not "we reached this line". Apply-StyleDirect's failure
        # modes are all Write-Error, which is non-terminating: setting $applied
        # unconditionally meant a failed apply skipped the OSC reset and left the
        # tuner's preview colors painted over an already-restored settings.json.
        # Filtered on Activity, not just "any error": Apply-StyleDirect's three
        # give-up paths are Write-Error + return, and all three return before
        # touching anything. An incidental non-terminating error from a cmdlet
        # further in (the Copy-Item/Remove-Item that install current-style.ps1)
        # means the style DID go on, so counting it as failure would revert a
        # good apply -- the opposite bug.
        $applyErr = $null
        if ($tuneUsesSettings) { Apply-StyleDirect -StyleName $saveName -Target $target -ErrorVariable applyErr }
        else { Apply-StyleDirect -StyleName $saveName -ErrorVariable applyErr }
        $applied = -not @($applyErr | Where-Object { $_.CategoryInfo.Activity -eq 'Write-Error' }).Count
    } finally {
        [Console]::CursorVisible = $true
        if (-not $applied) {
            # Safety net: restore settings.json + title unless a saved style was
            # applied. Esc / aborted-save already reverted explicitly; this also
            # covers an exception thrown mid-session (the key loop is not tested).
            # $restoreBaseLook may not exist yet if something threw very early.
            if ($restoreBaseLook) { & $restoreBaseLook }
            $Host.UI.RawUI.WindowTitle = $originalTitle
        }
        if (Test-Path -LiteralPath $scratchDir) {
            Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
