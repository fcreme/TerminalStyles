# applystyle.ps1 -- applying and resetting a style, and the read-only subcommands.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# One fork runs through all of it: is this Windows Terminal? On WT a style is a
# merge into settings.json and WT repaints from its own file watch. Everywhere
# else it is an OSC packet pushed at the live tab, a recorded style name so a new
# tab can re-emit it, and the staged zsh/bash runtime. Reset is the inverse and
# has to undo whichever half ran.

function Show-StyleList {
    # `tstyles list` -- print available styles, marking the active one.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $styles = Get-AvailableStyles
    # Read once for the whole listing rather than per row, the same seam
    # Show-FontList uses for its installed-font set.
    $claim = Get-InstalledStyleClaim
    $rootsAreOne = Test-StylesRootsAreOne
    $anyYours = $false
    Write-Host ""
    Write-Host "Available styles:" -ForegroundColor Cyan
    foreach ($s in $styles) {
        $marker = if ($s.Name -eq $current) { '*' } else { ' ' }
        # A user-authored style with a malformed or unreadable scheme.json used
        # to throw here, mid-loop -- so `tstyles list` printed a raw .NET
        # exception and then stopped, hiding every style after it. One bad
        # folder should cost its own row, not the listing.
        $schemePath = Join-Path $s.FullName 'scheme.json'
        $swatch = ''
        try {
            $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $swatch = Get-SchemeSwatch -Scheme $scheme
        } catch {
            $swatch = "$([char]27)[38;2;160;160;160m(unreadable scheme.json)$([char]27)[0m"
        }
        # Which styles are YOURS. Deliberately trailing text rather than a
        # column: the picker draws rows at the same width and its viewport
        # budget is already 23 rows in a 24-row window.
        #
        # An 'unknown' origin gets no badge at all -- on an install with no
        # readable .installed-files the tool cannot prove who owns a style, and
        # claiming it is yours is the error that would offer to delete the
        # bundled set. Degrades to no badge on any failure, like the swatch above.
        $badge = ''
        try {
            switch (Get-StyleOrigin -Name $s.Name -StyleDir $s.FullName -Claim $claim -RootsAreOne $rootsAreOne) {
                'yours'  { $badge = "  $([char]27)[38;2;160;160;160myours$([char]27)[0m"; $anyYours = $true }
                'shadow' { $badge = "  $([char]27)[38;2;160;160;160myours (shadows bundled)$([char]27)[0m"; $anyYours = $true }
            }
        } catch { }
        Write-Host ("  {0} {1,-16}  {2}{3}" -f $marker, $s.Name, $swatch, $badge)
    }
    Write-Host ""
    if ($current) {
        Write-Host "$([char]27)[38;2;160;160;160m  (* = currently active)$([char]27)[0m"
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m  (no bundled style currently active)$([char]27)[0m"
    }
    if ($anyYours) {
        Write-Host "$([char]27)[38;2;160;160;160m  (yours = you made it; delete one with: tstyles delete <name>)$([char]27)[0m"
    }
    Write-Host ""
}

function Show-CurrentStyle {
    # `tstyles current` -- print the active style name. Interactive callers
    # see name + swatch (visual self-check); piped/redirected callers get
    # just the name on stdout, preserving scriptability for `tstyles current
    # | grep ...` etc.
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    if ($current) {
        if ([Console]::IsOutputRedirected) {
            Write-Output $current
        } else {
            $styleDir = Get-StyleDir -StyleName $current
            $schemePath = if ($styleDir) { Join-Path $styleDir 'scheme.json' } else { $null }
            if ($schemePath -and (Test-Path -LiteralPath $schemePath)) {
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                Write-Host ("{0,-16}  {1}" -f $current, (Get-SchemeSwatch -Scheme $scheme))
            } else {
                Write-Host $current
            }
        }
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m(no bundled style currently active)$([char]27)[0m"
    }
}

function Invoke-RandomStyle {
    # `tstyles random` -- pick a random bundled style and apply it.
    # Excludes the currently active one so it actually changes.
    #
    # Takes the same apply flags as `tstyles <name>` and forwards them. It used
    # to call Apply-StyleDirect with only the style name, so `tstyles random
    # -KeepPrompt` replaced the prompt it promised to keep, `-Target` applied to
    # the wrong Windows Terminal profile, and `-NewWindow` did nothing.
    #
    # -BackgroundImage was missed by that fix and stayed dropped a while longer:
    # three of the four flags were forwarded and the comment above said all of
    # them were. It needs its own -Provided flag because "" is meaningful --
    # the documented way to apply a style with NO background image -- so the
    # switch cannot be inferred from the value being empty.
    param(
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided,
        [switch]$KeepPrompt,
        [switch]$NewWindow
    )
    Show-UpdateNoticeIfAvailable
    $current = Get-CurrentStyleName
    $candidates = @(Get-AvailableStyles | Where-Object { $_.Name -ne $current })
    if (-not $candidates) {
        Write-Host "No other styles to switch to." -ForegroundColor Yellow
        return
    }
    $pick = $candidates | Get-Random
    Write-Host ""
    Write-Host "Rolling the dice... -> " -NoNewline
    Write-Host $pick.Name -ForegroundColor Cyan
    Apply-StyleDirect -StyleName $pick.Name -Target $Target `
        -BackgroundImage $BackgroundImage -BackgroundImageProvided $BackgroundImageProvided `
        -KeepPrompt:$KeepPrompt -NewWindow:$NewWindow
}



function Invoke-AppleTerminalScript {
    <#
    .SYNOPSIS
    Run one AppleScript against Terminal.app. The single seam for all of them.

    .DESCRIPTION
    Every osascript call in this module goes through here so a test can mock it
    without driving the Terminal.app of whoever is running the suite -- opening
    windows on their screen, or deleting settings sets they own.

    AppleScript rather than writing ~/Library/Preferences/com.apple.Terminal.plist:
    Terminal.app holds its preferences in memory and rewrites that file when it
    quits, so an external write is silently reverted. Going through the app is
    the only way to change its settings while it is running.

    Returns the trimmed stdout, or $null if osascript is absent or errored.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Script)

    if ((Get-TStylesPlatform) -ne 'MacOS') { return $null }
    if (-not (Get-Command osascript -ErrorAction SilentlyContinue)) { return $null }
    try {
        $out = & osascript -e $Script 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($out -join "`n").Trim()
    } catch { return $null }
}

function ConvertTo-AppleScriptString {
    # A double-quoted AppleScript literal. Style names are validated upstream,
    # but a settings-set name read back from Terminal.app is not ours to trust.
    param([AllowEmptyString()][AllowNull()][string]$Value)
    '"' + (($Value -replace '\\', '\\\\') -replace '"', '\"') + '"'
}

function Get-AppleTerminalSettingsSetName {
    <#
    .SYNOPSIS
    The profiles Terminal.app currently has. Read-only.

    .DESCRIPTION
    Empty when Terminal.app cannot be asked, which is the safe direction: every
    caller then falls back to `open`, the behaviour that shipped before this.
    #>
    [CmdletBinding()]
    param()
    $out = Invoke-AppleTerminalScript 'tell application "Terminal" to get name of every settings set'
    if (-not $out) { return @() }
    @($out -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-AppleTerminalImportRecordPath {
    Join-Path $script:TStylesDataRoot '.appleterminal-imported.json'
}

function Get-AppleTerminalImportRecord {
    <#
    .SYNOPSIS
    Which .terminal profiles this tool imported into Terminal.app, and as what.

    .DESCRIPTION
    An ownership record, the same idea as .installed-files: without one there is
    no way to tell a settings set TerminalStyles created from one the user made
    and happened to name after a style, and deleting the wrong one is not
    recoverable. Only names appearing here are ever deleted.

    Maps settings-set name -> the SHA256 of the .terminal file that produced it,
    so a stale import is detectable.
    #>
    [CmdletBinding()]
    param()
    $p = Get-AppleTerminalImportRecordPath
    if (-not (Test-Path -LiteralPath $p)) { return @{} }
    try {
        $raw = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
        $o = $raw | ConvertFrom-Json
        $h = @{}
        foreach ($prop in $o.PSObject.Properties) { $h[$prop.Name] = "$($prop.Value)" }
        return $h
    } catch { return @{} }
}

function Set-AppleTerminalImportRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Hash)
    $r = Get-AppleTerminalImportRecord
    $r[$Name] = $Hash
    try {
        $json = ([pscustomobject]$r | ConvertTo-Json -Depth 3)
        [System.IO.File]::WriteAllText((Get-AppleTerminalImportRecordPath), $json,
            [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Get-AppleTerminalProfileHash {
    param([Parameter(Mandatory)][string]$Path)
    try { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    catch { $null }
}

function Remove-AppleTerminalSettingsSet {
    <#
    .SYNOPSIS
    Delete one Terminal.app profile. Returns $true when it is gone afterwards.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Invoke-AppleTerminalScript ("tell application `"Terminal`" to delete settings set {0}" -f
        (ConvertTo-AppleScriptString $Name)) | Out-Null
    return ($Name -notin (Get-AppleTerminalSettingsSetName))
}

function Open-AppleTerminalProfile {
    <#
    .SYNOPSIS
    Open a new Terminal.app window carrying this style's profile.

    .DESCRIPTION
    This was `& open $Path`, and `open` on a .terminal file does not update a
    profile of the same name -- it imports a SECOND one. Terminal.app resolves
    the collision by appending a number, so every `tstyles <style> -NewWindow`
    added another permanent entry to the user's profile list: eva, eva 1, eva 2,
    eva 3. Nothing deduplicated, nothing updated in place, and `tstyles
    uninstall` does not remove them either -- it promises not to touch
    Terminal.app's settings at all. Found with nine of them on one machine.

    So: import once, then reuse. The three cases are

      * not installed          -> `open` the file, and record what we imported
      * installed and current  -> open a window on the EXISTING settings set,
                                  which is what stops the accumulation
      * installed but stale    -> delete ours and re-import, so a re-tuned style
                                  does not open a window in its old colours

    The stale branch is why the import record exists. Reusing an installed
    profile unconditionally would trade a duplicate for something worse -- a
    window showing settings the style no longer has -- and deleting without a
    record could take a profile the USER made and named after a style.

    Falls back to `open` whenever Terminal.app cannot be asked, so nothing here
    can make the feature worse than it was.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Name)

    if (-not $Name) { & open $Path; return }

    $installed = Get-AppleTerminalSettingsSetName
    if ($installed.Count -eq 0) { & open $Path; return }

    $hash   = Get-AppleTerminalProfileHash -Path $Path
    $record = Get-AppleTerminalImportRecord

    if ($Name -in $installed) {
        $ours    = $record.ContainsKey($Name)
        $current = $ours -and $hash -and $record[$Name] -eq $hash

        if ($current) {
            $script = @"
tell application "Terminal"
    set t to do script ""
    set current settings of t to settings set $(ConvertTo-AppleScriptString $Name)
end tell
"@
            if ($null -ne (Invoke-AppleTerminalScript $script)) { return }
            # Terminal.app refused; fall through to the import path rather than
            # leaving the user with no window at all.
        } elseif ($ours) {
            # Ours, and out of date. Replacing it keeps the name unique, so the
            # re-import cannot produce a numbered copy.
            Remove-AppleTerminalSettingsSet -Name $Name | Out-Null
        }
        # Not ours: left alone. `open` below will make a numbered copy rather
        # than touch a profile this tool did not create.
    }

    & open $Path
    if ($hash) { Set-AppleTerminalImportRecord -Name $Name -Hash $hash }
}

function Publish-StyleBackgroundProfile {
    <#
    .SYNOPSIS
    Write the Terminal.app profile that carries a style's background image, and
    either open it or say how to.

    .DESCRIPTION
    Extracted from Apply-StyleNonWT because the picker needs the identical thing
    and did not have it: on Terminal.app, `tstyles` + Enter applied colors and
    prompt, printed "Style applied: eva", and stopped -- no profile written, no
    mention that the style ships a background, no hint. `tstyles eva` on the same
    terminal wrote the profile and told the user how to see it, and `tstyles
    -NewWindow` was accepted in silence and did nothing at all.

    A background image cannot be pushed into the current window -- only a profile
    carries one, and a profile only applies to a NEW window. So the profile is
    written either way and opened only when asked: silently spawning a window on
    every apply would be a worse surprise than not showing the image.

    .OUTPUTS
    The profile path, or $null where there is nothing to write (any terminal but
    Terminal.app, or a style with no background).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)][AllowNull()]$Scheme,
        [Parameter(Mandatory)][string]$Kind,
        [switch]$NewWindow
    )

    $caps = Get-TerminalCapability -Kind $Kind
    if (-not ($caps.BackgroundImage -and $Kind -eq 'AppleTerminal')) { return $null }

    $bundledBg = Get-StyleBundledBackground -StyleDir $StyleDir
    if (-not $bundledBg) { return $null }

    $profilePath = New-AppleTerminalProfile -StyleName $StyleName -Scheme $Scheme -BackgroundImage $bundledBg
    if (-not $profilePath) { return $null }

    # Say the OTHER half of the limit too. This notice exists so a plain result
    # is never a mystery, and it explained only where the image appears -- not
    # that it will not move. Every bundled background is an animated GIF, so
    # "to get it" read as a promise of the GIF; ConvertTo-AppleTerminalBackground
    # then hands Terminal.app the first frame, because a profile pointing at a
    # GIF renders blank with no error. A user who does exactly what this screen
    # tells them still gets a surprise, which is the thing it is here to prevent.
    #
    # Conditional on the source really being a GIF: a style shipping a static
    # PNG loses nothing by animation, and saying so would be its own false claim.
    $isGif = [System.IO.Path]::GetExtension($bundledBg).ToLowerInvariant() -eq '.gif'

    if ($NewWindow) {
        Write-Host ""
        Write-Host "  Opening a new window with the background image..." -ForegroundColor DarkGray
        if ($isGif) {
            Write-Host "  Terminal.app cannot animate, so this is the GIF's first frame." -ForegroundColor DarkGray
        }
        try { Open-AppleTerminalProfile -Path $profilePath -Name $StyleName } catch {
            Write-Host "  Could not open the profile: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "  This style ships a background image, which Terminal.app can only show" -ForegroundColor DarkGray
        Write-Host "  in a new window. To get it:" -ForegroundColor DarkGray
        Write-Host "    tstyles $StyleName -NewWindow" -ForegroundColor Cyan
        if ($isGif) {
            Write-Host "  It will be the GIF's first frame, not the animation -- Terminal.app" -ForegroundColor DarkGray
            Write-Host "  renders a still background. Animated backgrounds need Windows Terminal." -ForegroundColor DarkGray
        }
    }
    return $profilePath
}

function Publish-StyleWezTermConfig {
    <#
    .SYNOPSIS
    Write the WezTerm Lua module for this style, and say if it is not wired up.

    .DESCRIPTION
    A sibling of Publish-StyleBackgroundProfile rather than a branch inside it:
    the two terminals share nothing but the moment they run, and the Terminal.app
    path is the one people are using today. Both apply paths call both, and
    tests/WezTerm-Writer.Tests.ps1 asserts that, so the duplication is measured
    rather than trusted.

    Returns the module path when one was written, else $null.

    The notice is the same contract as the Terminal.app -NewWindow hint: a
    capability this terminal reports must never produce a plain result the user
    cannot explain. Here the missing piece is the one line only the user can add,
    since nothing may edit their wezterm.lua -- see the header of lib/wezterm.ps1
    for why appending to a Lua program is not the same as appending to an rc file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)]$Scheme,
        $Theme,
        [Parameter(Mandatory)][string]$Kind,
        [string]$HomeDir
    )

    if ($Kind -ne 'WezTerm') { return $null }

    $splat = @{}
    if ($PSBoundParameters.ContainsKey('HomeDir')) { $splat.HomeDir = $HomeDir }

    # The animated GIF itself -- the reason this writer exists. Unlike the
    # Terminal.app path there is no still-frame conversion: WezTerm animates it.
    $bg = Get-StyleBundledBackground -StyleDir $StyleDir

    $status = Write-WezTermStyleModule -StyleName $StyleName -Scheme $Scheme -Theme $Theme `
                                       -BackgroundImage $bg @splat
    $path = Get-WezTermModulePath @splat

    if ($status -eq 'failed') {
        Write-Host ""
        Write-Host "  Could not write $path" -ForegroundColor Yellow
        Write-Host "  WezTerm keeps your colors from this session, but a new window will not." -ForegroundColor DarkGray
        return $null
    }

    if (-not (Test-WezTermStyleWired @splat)) {
        Write-Host ""
        Write-Host "  Wrote the WezTerm style to $path" -ForegroundColor DarkGray
        Write-Host "  It does nothing until your wezterm.lua loads it. Add this line," -ForegroundColor DarkGray
        Write-Host "  above the final `"return config`":" -ForegroundColor DarkGray
        Write-Host "    $(Get-WezTermWiringLine)" -ForegroundColor Cyan
        Write-Host "  Then every style you apply repaints the running window, background" -ForegroundColor DarkGray
        Write-Host "  animation included." -ForegroundColor DarkGray
    }
    return $path
}

function Apply-StyleNonWT {
    # Apply a style on a terminal that is not Windows Terminal.
    #
    # There is no settings.json to merge into, so the work splits in two:
    #   * colors    -- emitted as an OSC packet, which retints the CURRENT tab
    #                  instantly. Recorded in current-style.json so the startup
    #                  block at the bottom of this file can re-emit it into
    #                  every future tab.
    #   * prompt    -- the style's profile.ps1 is copied to current-style.ps1
    #                  and dot-sourced, exactly as on Windows Terminal. That
    #                  file is plain PowerShell + ANSI and is already portable.
    #
    # Fields the host terminal cannot honour (a background image on Terminal.app,
    # a tab accent color anywhere but WT) are reported rather than silently
    # dropped, so the user knows why the style looks plainer than its screenshot.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [Parameter(Mandatory)][string]$StyleDir,
        [switch]$KeepPrompt,
        # Open a new window carrying the FULL style, background image included.
        # Needed because an image can only reach Terminal.app through a profile,
        # and a profile only takes effect on a new window -- unlike colors,
        # which the OSC packet applies to the window you are already in.
        [switch]$NewWindow
    )

    $kind = Get-TerminalKind
    $caps = Get-TerminalCapability -Kind $kind

    $schemePath = Join-Path $StyleDir 'scheme.json'
    if (-not (Test-Path -LiteralPath $schemePath)) {
        Write-Error "Style '$StyleName' has no scheme.json."
        return
    }
    $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json

    $applied = Invoke-TerminalStyleOscApply -Scheme $scheme -Kind $kind
    Set-CurrentStyleRecord -StyleName $StyleName -Kind $kind

    # Stage the zsh/bash side too. The user's login shell is probably not
    # PowerShell, and the colors belong to the terminal rather than to any one
    # shell -- so a zsh tab opened after this should come up styled as well.
    Set-ShellStyleState -StyleName $StyleName -StyleDir $StyleDir -Scheme $scheme -KeepPrompt:$KeepPrompt

    # Prompt/banner: same contract as the Windows Terminal path.
    $styleProfile = Join-Path $StyleDir 'profile.ps1'
    if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
        Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
    } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force
    }

    Write-Host ""
    Write-Host "  Style applied: " -NoNewline
    Write-Host $StyleName -ForegroundColor Green
    Write-Host "  Terminal:      " -NoNewline
    Write-Host (Get-TerminalDisplayName -Kind $kind) -ForegroundColor Cyan

    if (-not $applied) {
        Write-Host ""
        if ([Console]::IsOutputRedirected) {
            # The style IS recorded and staged -- a new tab will come up in it.
            # What could not happen is repainting THIS session, because its
            # output does not go to a terminal. Say that precisely: the
            # alternative is a user watching an unchanged window after being
            # told the style was applied.
            Write-Host "  Colors were not applied to this session: its output is redirected," -ForegroundColor Yellow
            Write-Host "  so there is no terminal to repaint. The style is saved -- open a new" -ForegroundColor Yellow
            Write-Host "  tab, or run tstyles directly in your terminal, to see it." -ForegroundColor Yellow
        } else {
            Write-Host "  Note: this terminal did not accept live color changes, so only the prompt was applied." -ForegroundColor Yellow
        }
    }

    # Tell the user which parts of the style this terminal cannot show, once,
    # rather than letting them wonder why it doesn't match the screenshot.
    $unsupported = @()
    $theme = $null
    $themePath = Join-Path $StyleDir 'theme.json'
    if (Test-Path -LiteralPath $themePath) {
        try {
            $theme = [System.IO.File]::ReadAllText($themePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        } catch { $theme = $null }
    }
    if ($theme) {
        # Capability first, deliberately. Get-StyleBundledBackground can make up
        # to four serial 10-second HTTP attempts against the gifs branch, so as
        # the LEFT operand it ran even where the answer could not matter -- and
        # ran a second time below. Ordered this way the two calls below and here
        # are mutually exclusive on $caps.BackgroundImage, so an apply resolves
        # the background at most once.
        if (-not $caps.BackgroundImage -and (Get-StyleBundledBackground -StyleDir $StyleDir)) {
            $unsupported += 'background image'
        }
        if ($theme.PSObject.Properties.Match('tabColor').Count -gt 0 -and -not $caps.TabColor) {
            $unsupported += 'tab color'
        }
    }
    if ($unsupported.Count -gt 0) {
        Write-Host ""
        Write-Host ("  {0} can't show: {1}." -f (Get-TerminalDisplayName -Kind $kind), ($unsupported -join ', ')) -ForegroundColor DarkGray
    }

    Publish-StyleBackgroundProfile -StyleName $StyleName -StyleDir $StyleDir `
        -Scheme $scheme -Kind $kind -NewWindow:$NewWindow | Out-Null
    Publish-StyleWezTermConfig -StyleName $StyleName -StyleDir $StyleDir `
        -Scheme $scheme -Theme $theme -Kind $kind | Out-Null
    Write-Host ""

    # Live reload of the prompt in THIS shell (matches the WT confirm path).
    #
    # Skipped when $TStylesNoAutoLoad is set, which is exactly the "I am not an
    # interactive pwsh session" signal the generated tstyles-cli.ps1 sets. From
    # zsh or bash, `tstyles <style>` runs that shim in a one-shot pwsh process
    # that exits immediately, so reloading the prompt into it accomplishes
    # nothing -- and dot-sourcing the style's profile.ps1 printed its whole
    # ASCII banner. The shell function then re-sources the staged prompt.sh to
    # swap the prompt for real, printing the banner a SECOND time. Two banners
    # per apply, every apply, for every zsh and bash user.
    #
    # The shell's copy is the one to keep: it is the one that actually changes
    # the prompt the user is looking at.
    if (-not $global:TStylesNoAutoLoad -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
        . $script:TStylesCurrent
    }
}

function Apply-StyleDirect {
    # Apply a style directly (no picker UI). Used by `tstyles <name>` and
    # `tstyles random`. Mirrors the picker's confirm path -- merge into
    # settings.json, copy profile.ps1 to current-style.ps1, dot-source for
    # live reload.
    #
    # Off Windows Terminal the settings.json half does not exist; Apply-StyleNonWT
    # takes over with the OSC + current-style.json path instead.
    param(
        [Parameter(Mandatory)][string]$StyleName,
        [string]$Target,
        [string]$BackgroundImage,
        [bool]$BackgroundImageProvided = $false,
        # Apply the visuals but not the style's prompt/banner: clears
        # current-style.ps1 so the user's own prompt stays in control.
        [switch]$KeepPrompt,
        # Off Windows Terminal: also open a new window carrying the style's
        # background image (see Apply-StyleNonWT).
        [switch]$NewWindow
    )

    $styleDir = Get-StyleDir -StyleName $StyleName
    if (-not $styleDir) {
        Write-Error "Style '$StyleName' not found. Run 'tstyles list' to see available styles."
        return
    }

    Show-UpdateNoticeIfAvailable

    # Non-WT hosts have no settings.json; hand off before we go looking for one.
    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        Apply-StyleNonWT -StyleName $StyleName -StyleDir $styleDir -KeepPrompt:$KeepPrompt -NewWindow:$NewWindow
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = ConvertFrom-WTJson $originalJson

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile. Pass -Target <name>."
        return
    }

    # Validate the target BEFORE anything is written. Merge-StyleIntoSettings
    # returns the settings untouched when the named profile does not exist, but
    # this function used to write and report success regardless -- so a typo in
    # -Target printed "Style applied" in green having applied nothing. Worse,
    # the write was not a no-op: Write-SettingsFile re-serializes the PARSED
    # object, and ConvertFrom-WTJson has already stripped every comment the user
    # wrote in their settings.json. A misspelled profile name silently and
    # irreversibly deleted their JSONC comments.
    $resolvedTarget = Resolve-WTProfileTarget -Settings $settings -TargetName $Target
    if (-not $resolvedTarget.Ok) {
        Write-Error (Get-WTTargetNotFoundMessage -ResolvedTarget $resolvedTarget -TargetName $Target)
        return
    }

    # Say so when the name was not unique -- through the shared note, which is
    # the same sentence reset, font, the picker and apply.ps1 now print. This
    # was the only caller that said anything, and it was the inline version that
    # claimed the session's profile even when the tie could not be broken.
    Write-AmbiguousTargetNote -ResolvedTarget $resolvedTarget -TargetName $Target -Verb 'Applied to'

    # The style half of the same rule. Merge-StyleIntoSettings returns the
    # settings UNTOUCHED for a style with no theme.json -- deliberately, since a
    # scheme is only reachable through a profile's colorScheme key -- and this
    # function used to write them anyway, which re-serializes the parsed object
    # and drops every JSONC comment the user wrote. So applying a scheme-only
    # style (legal: README documents theme.json as optional) destroyed the
    # comments, applied nothing, and reported "Style applied" in green. Same
    # defect the -Target guard above was added for, through the door beside it.
    $payload = Get-StyleSettingsPayload -StyleDir $styleDir
    if ($payload.Missing -eq 'scheme.json') {
        Write-Error "Style '$StyleName' has no scheme.json -- nothing to apply."
        return
    }
    if (-not $payload.Ok) {
        # theme.json absent: nothing for Windows Terminal's settings.json, but
        # the prompt/banner half below is still the style's whole job off WT.
        Write-Host "  '$StyleName' ships no theme.json, so nothing was written to settings.json." -ForegroundColor DarkGray
    } else {
        # Rolling backup: the on-disk settings.json to settings.json.bak before
        # any mutation. One file, overwritten on each direct apply -- a one-line
        # undo without filling LocalState with timestamped backups. Taken only
        # now, because taking it consumes the user's undo of their LAST apply,
        # so a command that turns out to write nothing must not spend it.
        try {
            Save-SettingsBackup -Path $settingsPath -ResolvedTarget $resolvedTarget
        } catch {
            Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
        }

        # Into a SEPARATE variable, and checked before the write. This was
        # `$settings = Merge-...` followed by the write, and PowerShell does not
        # abandon the command when the merge fails: a method call on a
        # null-valued expression aborts only that STATEMENT, and
        # $ErrorActionPreference is 'Continue' in an interactive shell. So the
        # assignment never happened, $settings still held the parsed-but-
        # unmerged object, and Write-SettingsFile re-serialized THAT -- which
        # deleted every JSONC comment in the user's settings.json, printed
        # "Style applied" in green, and recorded a style no profile had
        # received. That is the exact failure the -Target guard above exists to
        # prevent; it came back through the merge. The resolver no longer hands
        # this path a target the merge cannot write, and this makes sure the
        # next throw inside the merge costs an error message instead of the
        # user's comments.
        $merged = $null
        try {
            $merged = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
                -TargetName $Target -BackgroundImage $BackgroundImage `
                -BackgroundImageProvided $BackgroundImageProvided
        } catch {
            $merged = $null
            Write-Error "Could not apply '$StyleName' to '$Target': $_"
        }
        if ($null -eq $merged) { return }
        $settings = $merged
        Write-SettingsFile -Path $settingsPath -Settings $settings
    }

    # Detect pwsh target for profile.ps1 install + live reload
    $isPwshTarget = $false
    if ($Target -eq 'defaults') {
        $isPwshTarget = $true
    } else {
        # Same resolver as the merge, so the pwsh detection inspects the
        # profile the style was actually written to. With two same-named
        # profiles this read the wrong one's commandline and could install (or
        # skip) the prompt on the strength of it.
        $entry = (Resolve-WTProfileTarget -Settings $settings -TargetName $Target).Entry
        $cmd = "$($entry.commandline)"
        $src = "$($entry.source)"
        if ($src -eq 'Windows.Terminal.PowershellCore' -or
            $cmd -match '(?i)\bpwsh\.exe\b' -or
            $cmd -match '(?i)\bpowershell\.exe\b') {
            $isPwshTarget = $true
        }
    }

    $styleProfile = Join-Path $styleDir 'profile.ps1'
    if ($isPwshTarget) {
        if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
            Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
        } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
            Remove-Item -LiteralPath $script:TStylesCurrent -Force
        }
    }

    # Record the choice. Get-CurrentStyleName answers by byte-comparing
    # current-style.ps1 against each style's profile.ps1, and falls back to this
    # record when there is nothing to compare -- which is exactly the case for a
    # style that ships no profile.ps1, and for -KeepPrompt. Without it the
    # branch above DELETES current-style.ps1 and nothing else remembers, so
    # `tstyles current` printed "(no bundled style currently active)", `tstyles
    # list` showed no `*`, the picker opened at index 0 and a bare `tstyles
    # tune` errored "No active style detected" -- all while settings.json
    # plainly carried the style's colorScheme. Tuned styles reach that state
    # routinely: Save-TunedStyle only writes profile.ps1 when the base has one.
    # Best-effort by contract (Set-CurrentStyleRecord is try//catch internally),
    # so it cannot take down an apply that has already succeeded.
    Set-CurrentStyleRecord -StyleName $StyleName -Kind 'WindowsTerminal'

    Write-Host ""
    Write-Host "  Style applied: " -NoNewline
    Write-Host $StyleName -ForegroundColor Green
    Write-Host ""

    # Live reload (same pattern as the picker's confirm path)
    if ($isPwshTarget -and (Test-InWindowsTerminal) -and (Test-Path -LiteralPath $script:TStylesCurrent)) {
        . $script:TStylesCurrent
    }
}

function Test-InWindowsTerminal {
    # True when the current session is hosted by Windows Terminal (which sets
    # WT_SESSION). WT is the only host that renders a style's colors/background,
    # so the themed prompt/banner is loaded only here.
    return [bool]$env:WT_SESSION
}

function Reset-StyleNonWT {
    # `tstyles reset` off Windows Terminal.
    #
    # Nothing was written to a settings file, so there is nothing to strip --
    # the applied colors live entirely in the terminal's dynamic-color state.
    # OSC 104/110/111/112/117 hands that state back to the terminal's own
    # configured profile, which is exactly what "unstyled default" means here.
    $kind = Get-TerminalKind

    [void](Invoke-TerminalStyleOscReset -Kind $kind)
    Clear-CurrentStyleRecord
    Clear-ShellStyleState

    # Restore the user's own prompt by removing the style's loader target. The
    # prompt function already installed in THIS session stays until the shell
    # restarts -- same behaviour as the Windows Terminal path.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  Reset " -NoNewline
    Write-Host (Get-TerminalDisplayName -Kind $kind) -ForegroundColor Cyan -NoNewline
    Write-Host " to its unstyled default."
    Write-Host "  Open a new tab to restore your default prompt."
    Write-Host ""
}

function Reset-StyleDirect {
    # `tstyles reset [-Target <name>]` -- revert a WT profile to its unstyled
    # default: strip the fields TerminalStyles writes, remove the now-orphan
    # color scheme, and clear current-style.ps1 (restore the user's prompt).
    # Inverse of Apply-StyleDirect. Writes a rolling .bak first.
    #
    # Off Windows Terminal there is no settings.json to strip: the reset is an
    # OSC 104/110-117 packet that hands color control back to the terminal's own
    # profile, plus dropping the style record and current-style.ps1.
    #
    # -KnownStyleName is one name the CALLER has already proved is ours, for the
    # ownership marker below. `tstyles delete` is the only user: it proves
    # ownership while the style is still on disk, and the reset it promised runs
    # after the move.
    param([string]$Target, [string]$KnownStyleName)

    Show-UpdateNoticeIfAvailable

    if ((Get-TerminalKind) -ne 'WindowsTerminal') {
        Reset-StyleNonWT
        return
    }

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = ConvertFrom-WTJson $originalJson

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to reset. Try: tstyles reset -Target '<name>'"
        return
    }

    # Resolve BEFORE the backup, not after. This was the other way round, so a
    # mistyped -Target copied settings.json over settings.json.bak and only then
    # discovered the profile did not exist -- printing "nothing to reset" having
    # just destroyed the user's undo of their last real apply. Entry, not Ok:
    # 'defaults' is addressable for an apply (created lazily) but has nothing to
    # strip when the block is absent.
    $resolvedTarget = Resolve-WTProfileTarget -Settings $settings -TargetName $Target
    $entry = $resolvedTarget.Entry
    if (-not $entry) {
        Write-Host "Profile '$Target' not found in settings.json -- nothing to reset." -ForegroundColor Yellow
        return
    }

    # Reset needs this note more than apply does, and never had it. The strip
    # below removes every field an apply may write -- padding, opacity,
    # useAcrylic, cursorShape, font.face and the rest -- off whichever of two
    # same-named profiles the resolver picked, and then reports "Reset '<name>'
    # to its unstyled default." in green. Which one it picked is not something
    # the user can see from the outside.
    Write-AmbiguousTargetNote -ResolvedTarget $resolvedTarget -TargetName $Target -Verb 'Reset'

    # Capture the scheme name before stripping (for orphan cleanup).
    $schemeName = if ($entry.PSObject.Properties.Match('colorScheme').Count) { $entry.colorScheme } else { $null }

    # Did WE style this profile? Ask before removing anything.
    #
    # $script:TStylesThemeFields is the list of keys an apply may write, and the
    # strip below removed every one of them that was present -- with no record of
    # which ones TerminalStyles had actually put there. That list is
    # colorScheme, tabTitle, tabColor, cursorShape, useAcrylic, opacity,
    # experimental.retroTerminalEffect, font, padding and the four
    # backgroundImage keys: very nearly everything a user configures through the
    # Windows Terminal settings UI. So `tstyles reset -Target 'PowerShell'` on a
    # profile that had never been styled deleted the user's own acrylic, opacity,
    # padding, cursor shape, font, wallpaper and tab title, and reported
    # "Reset '<name>' to its unstyled default." in green. README says the
    # opposite in as many words: "Fields you set on the profile by hand are left
    # alone."
    #
    # The apply path already refuses the symmetric thing -- Test-ManagedBackgroundPath
    # exists so that a background the USER set is not cleared by a style that
    # ships none. Reset simply never asked the question.
    #
    # colorScheme naming one of our styles is the marker, because an apply always
    # writes it and writes it last: there is no way to be styled by this tool and
    # not carry it. A profile without it is one we never touched, and the honest
    # answer is to change nothing rather than guess. This runs BEFORE the backup
    # on purpose -- see Save-SettingsBackup below, whose rolling .bak is the
    # user's only undo and must not be spent on a call that writes nothing.
    #
    # Get-AvailableStyles enumerates styles/ under the two roots, and that is
    # the whole of what it can see -- so the marker is false for a style that
    # has just been moved OUT of it. `tstyles delete` does exactly that: it
    # moves the style into .deleted/ (a sibling of styles/) and only then runs
    # the reset it itemised on the consent screen, which refused, leaving the
    # profile fully styled and printing "Its colorScheme is '<name>', which is
    # not a style this tool wrote" four lines under "Deleted <name>." Resetting
    # BEFORE the move would leave the terminal unstyled if the move then
    # throws, so the caller carries its proof across instead.
    $styledByUs = $false
    if ($schemeName) {
        $styledByUs = ($KnownStyleName -and $schemeName -eq $KnownStyleName) -or
                      @(Get-AvailableStyles | Where-Object { $_.Name -eq $schemeName }).Count -gt 0
    }
    if (-not $styledByUs) {
        Write-Host ("  '{0}' carries no TerminalStyles style -- nothing was changed." -f $Target) -ForegroundColor Yellow
        if ($schemeName) {
            Write-Host ("  Its colorScheme is '{0}', which is not a style this tool wrote." -f $schemeName) -ForegroundColor DarkGray
        }
        Write-Host "  Reset only removes what an apply put there; your own profile settings are left alone." -ForegroundColor DarkGray
        return
    }

    try {
        Save-SettingsBackup -Path $settingsPath -ResolvedTarget $resolvedTarget
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    # Strip every TerminalStyles field that is present on the entry.
    $strippedAny = $false
    foreach ($field in $script:TStylesThemeFields) {
        if ($entry.PSObject.Properties.Match($field).Count) {
            $entry.PSObject.Properties.Remove($field)
            $strippedAny = $true
        }
    }

    # Remove the orphan scheme unless another profile still references it.
    if ($schemeName -and $settings.PSObject.Properties.Match('schemes').Count) {
        # "Every profile that could still reference this scheme" has to mean the
        # same set the resolver targets, or the sweep deletes a scheme something
        # still uses. Through the shared shape for that reason: a direct read of
        # .list finds nothing on the legacy flat-array form, where the profiles
        # are the array itself -- and those profiles are now resolvable, so
        # reset can reach them.
        $shape = Get-WTProfileShape -Settings $settings
        $allProfiles = @()
        if ($shape.HasDefaultsSlot -and $settings.profiles.PSObject.Properties.Match('defaults').Count) {
            $allProfiles += $settings.profiles.defaults
        }
        $allProfiles += @($shape.List)
        $stillUsed = @($allProfiles | Where-Object {
            $_.PSObject.Properties.Match('colorScheme').Count -and $_.colorScheme -eq $schemeName
        }).Count -gt 0
        if (-not $stillUsed) {
            $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName })
        }
    }

    # Only when something actually changed. A reset on a profile that was never
    # styled printed "'<name>' had no TerminalStyles fields -- already plain."
    # and then rewrote settings.json anyway, which re-serializes the parsed
    # object and drops every JSONC comment in it. The most likely way a curious
    # user tries this command was also the one that cost them their comments.
    if ($strippedAny) {
        Write-SettingsFile -Path $settingsPath -Settings $settings
    }

    # The other half of recording it on apply. Without this a reset stripped the
    # fields from settings.json and left the record standing, so `tstyles
    # current` would name a style that is no longer applied -- trading one wrong
    # answer for the opposite one. The non-WT reset above has always done this.
    Clear-CurrentStyleRecord

    # Clear the active style's prompt so the user's own prompt returns.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force
    }

    Write-Host ""
    if ($strippedAny) {
        Write-Host "  Reset '$Target' to its unstyled default." -ForegroundColor Green
    } else {
        Write-Host "  '$Target' had no TerminalStyles fields -- already plain." -ForegroundColor Gray
    }
    Write-Host "  Open a new tab to restore your default prompt." -ForegroundColor DarkGray
    Write-Host ""
}

function Get-AppleTerminalDuplicateProfile {
    <#
    .SYNOPSIS
    The numbered copies Terminal.app made of a style profile: "eva 1", "eva 2".

    .DESCRIPTION
    Only ever the NUMBERED ones, and only where the unsuffixed name is a style
    this tool knows. The base name is never reported: a user may well have their
    own profile called `eva`, and there is no way to prove otherwise. "eva 3" has
    no such ambiguity -- Terminal.app appends that suffix itself when an import
    collides, so it can only have come from a repeated import.
    #>
    [CmdletBinding()]
    param([string[]]$InstalledName, [string[]]$StyleName)

    if (-not $PSBoundParameters.ContainsKey('InstalledName')) {
        $InstalledName = Get-AppleTerminalSettingsSetName
    }
    if (-not $PSBoundParameters.ContainsKey('StyleName')) {
        $StyleName = @((Get-AvailableStyles).Name)
    }

    @(foreach ($n in $InstalledName) {
        $m = [regex]::Match($n, '^(?<base>.+?) (?<num>\d+)$')
        if (-not $m.Success) { continue }
        if ($m.Groups['base'].Value -notin $StyleName) { continue }
        [pscustomobject]@{ Name = $n; Base = $m.Groups['base'].Value }
    })
}

function Invoke-TerminalStyleProfiles {
    <#
    .SYNOPSIS
    `tstyles profiles` -- what this tool has left in Terminal.app, and a way out.
    #>
    [CmdletBinding()]
    param([switch]$Clean, [switch]$Yes)

    if ((Get-TStylesPlatform) -ne 'MacOS') {
        Write-Host ""
        Write-Host "  Terminal.app profiles are a macOS thing; there are none to show here." -ForegroundColor Gray
        Write-Host ""
        return
    }

    $installed = Get-AppleTerminalSettingsSetName
    if ($installed.Count -eq 0) {
        Write-Host ""
        Write-Host "  Could not ask Terminal.app for its profiles." -ForegroundColor Yellow
        Write-Host "  It may not be running, or osascript may be unavailable." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $styles = @((Get-AvailableStyles).Name)
    $mine   = @($installed | Where-Object { $_ -in $styles })
    $dupes  = @(Get-AppleTerminalDuplicateProfile -InstalledName $installed -StyleName $styles)

    Write-Host ""
    Write-Host "Terminal.app profiles named after a style:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($n in ($mine | Sort-Object)) { Write-Host ("    {0}" -f $n) }
    if ($dupes.Count -eq 0) {
        Write-Host ""
        Write-Host "  No duplicates." -ForegroundColor Gray
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "Duplicates, one per extra -NewWindow before this was fixed:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($d in ($dupes | Sort-Object Name)) { Write-Host ("    {0}" -f $d.Name) -ForegroundColor Yellow }
    Write-Host ""

    if (-not $Clean) {
        Write-Host "  Remove them with: tstyles profiles -Clean" -ForegroundColor DarkGray
        Write-Host "  The unnumbered profiles above are left alone -- one of them may be yours." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host ("This will DELETE {0} Terminal.app profile(s):" -f $dupes.Count) -ForegroundColor Yellow
    foreach ($d in ($dupes | Sort-Object Name)) { Write-Host ("  - {0}" -f $d.Name) -ForegroundColor Red }
    Write-Host "  - Nothing else in Terminal.app is touched, including the unnumbered" -ForegroundColor Gray
    Write-Host "    profiles, your default profile, and any window already open." -ForegroundColor Gray
    Write-Host ""
    if (-not (Confirm-Action -Question 'Delete them? [y/N]' -Yes:$Yes `
                -Consequence ("deletes {0} Terminal.app profile(s)" -f $dupes.Count))) {
        Write-Host "  Cancelled." -ForegroundColor Gray
        return
    }

    $gone = 0
    foreach ($d in $dupes) {
        if (Remove-AppleTerminalSettingsSet -Name $d.Name) {
            Write-Host ("  Removed {0}" -f $d.Name) -ForegroundColor Green
            $gone++
        } else {
            Write-Host ("  ! could not remove {0}" -f $d.Name) -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host ("  {0} of {1} removed." -f $gone, $dupes.Count) -ForegroundColor Cyan
    Write-Host ""
}
