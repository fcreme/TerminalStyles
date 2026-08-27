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
        Write-Host ("  {0} {1,-16}  {2}" -f $marker, $s.Name, $swatch)
    }
    Write-Host ""
    if ($current) {
        Write-Host "$([char]27)[38;2;160;160;160m  (* = currently active)$([char]27)[0m"
    } else {
        Write-Host "$([char]27)[38;2;160;160;160m  (no bundled style currently active)$([char]27)[0m"
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

    # Background image. It cannot be pushed into this window -- only a profile
    # carries one, and a profile only applies to a new window -- so the profile
    # is written either way and opened only when asked. Silently spawning a
    # window on every apply would be a worse surprise than not showing the image.
    $bundledBg = if ($caps.BackgroundImage -and $kind -eq 'AppleTerminal') {
        Get-StyleBundledBackground -StyleDir $StyleDir
    } else { $null }
    if ($bundledBg) {
        $profilePath = New-AppleTerminalProfile -StyleName $StyleName -Scheme $scheme -BackgroundImage $bundledBg
        if ($profilePath) {
            if ($NewWindow) {
                Write-Host ""
                Write-Host "  Opening a new window with the background image..." -ForegroundColor DarkGray
                try { & open $profilePath } catch {
                    Write-Host "  Could not open the profile: $_" -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "  This style ships a background image, which Terminal.app can only show" -ForegroundColor DarkGray
                Write-Host "  in a new window. To get it:" -ForegroundColor DarkGray
                Write-Host "    tstyles $StyleName -NewWindow" -ForegroundColor Cyan
            }
        }
    }
    Write-Host ""

    # Live reload of the prompt in THIS shell (matches the WT confirm path).
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
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
    if ($Target -ne 'defaults') {
        $targetEntry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
        if (-not $targetEntry) {
            $available = @('defaults') + @($settings.profiles.list.name | Where-Object { $_ })
            Write-Error ("Windows Terminal profile '$Target' not found. Available: " +
                         ($available -join ', '))
            return
        }
    }

    # Rolling backup: copy the on-disk settings.json to settings.json.bak
    # before any mutation. Single file, overwritten on each direct apply --
    # gives the user a one-line undo without filling LocalState with timestamped
    # backups over time. The picker doesn't need this (Esc reverts in-memory);
    # apply.ps1 keeps its own timestamped audit trail. -ErrorAction Stop so
    # non-terminating errors (permission denied, etc.) enter the catch block
    # rather than silently logging via $Error.
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
        -TargetName $Target -BackgroundImage $BackgroundImage `
        -BackgroundImageProvided $BackgroundImageProvided
    Write-SettingsFile -Path $settingsPath -Settings $settings

    # Detect pwsh target for profile.ps1 install + live reload
    $isPwshTarget = $false
    if ($Target -eq 'defaults') {
        $isPwshTarget = $true
    } else {
        $entry = $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
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
    param([string]$Target)

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

    # Rolling backup (same safety net as Apply-StyleDirect).
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    # Resolve the profile entry (same resolution as Merge-StyleIntoSettings).
    $entry = if ($Target -eq 'defaults') {
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $settings.profiles.defaults } else { $null }
    } else {
        $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
    }
    if (-not $entry) {
        Write-Host "Profile '$Target' not found in settings.json -- nothing to reset." -ForegroundColor Yellow
        return
    }

    # Capture the scheme name before stripping (for orphan cleanup).
    $schemeName = if ($entry.PSObject.Properties.Match('colorScheme').Count) { $entry.colorScheme } else { $null }

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
        $allProfiles = @()
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $allProfiles += $settings.profiles.defaults }
        $allProfiles += @($settings.profiles.list)
        $stillUsed = @($allProfiles | Where-Object {
            $_.PSObject.Properties.Match('colorScheme').Count -and $_.colorScheme -eq $schemeName
        }).Count -gt 0
        if (-not $stillUsed) {
            $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName })
        }
    }

    Write-SettingsFile -Path $settingsPath -Settings $settings

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
