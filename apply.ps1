# TerminalStyles -- style installer for Windows Terminal + PowerShell 7.
#
# Usage:
#   pwsh -File .\apply.ps1                                            # interactive
#   pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell"       # non-interactive
#   pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -BackgroundImage "C:\img.gif"
#   pwsh -File .\apply.ps1 -Style umbrella -Target defaults           # apply globally
#   pwsh -File .\apply.ps1 -Style kitty -Target "PowerShell" -KeepPrompt
#   pwsh -File .\apply.ps1 -Style umbrella -Target "PowerShell" -SettingsPath "<settings.json>"   # choose the file yourself
#
# Backs up settings.json, timestamped, before every change to it. Never edits
# $PROFILE: like `tstyles <name>`, it puts the style's prompt in
# current-style.ps1 in the data root, which a tab loads when its $PROFILE
# imports TerminalStyles.

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Style,
    [string]$Target,
    [string]$BackgroundImage,
    [string]$SettingsPath,
    # Apply visuals but not the style's prompt/banner: current-style.ps1 is
    # removed, so no style's prompt loads in new tabs. -NoProfile is the
    # original name, kept as an alias for back-compat.
    [Alias('NoProfile')]
    [switch]$KeepPrompt
)

$ErrorActionPreference = 'Stop'

# The library. apply.ps1 used to carry copy-pasted forks of these functions,
# each with a "keep in sync" note; two of them drifted anyway, in ways that lost
# user data:
#
#   Merge-ThemeIntoEntry stripped the background fields whenever no background
#   resolved, with no ownership check -- so it deleted a background the USER had
#   set (their own image, or Windows Terminal's desktopWallpaper), which the
#   module deliberately leaves alone. tests/Background-Carryover.Tests.ps1 pins
#   that distinction, and only ever covered the module.
#
#   Get-StyleBundledBackground was the pre-0.2.0 shape: it wrote fetched images
#   AND the .no-background marker into the STYLE directory rather than the data
#   root's cache, swallowing the failure -- and this script ships to PSGallery,
#   where that directory belongs to the installed module. It also wrote the old
#   undated marker format, which 0.8.6 reads as expired, so the two had diverged
#   on where the cache lives AND what a marker means.
#
#   The prompt step never got the module's inner-guard fix: -KeepPrompt sat on
#   the outer `if`, so it skipped removing the previous style's
#   current-style.ps1, and "has a loader" was decided by the BEGIN marker
#   alone, so a $PROFILE importing TerminalStyles by hand was replaced. It is
#   Set-CurrentStylePrompt now, and it never writes $PROFILE.
#
# $TStylesNoAutoLoad keeps the load from re-emitting the currently applied
# style's palette, which would repaint the terminal with the old style just
# before this script applies the new one.
$TStylesNoAutoLoad = $true
. (Join-Path $PSScriptRoot 'tstyles.ps1')

function Read-Choice {
    param([string]$Title, [string[]]$Options, [string]$Flag)

    # The guard is the FIRST statement, deliberately, because this function is
    # the funnel for both interactive entry points -- the style list and the
    # profile list -- so one check here covers both.
    #
    # Without it the loop below never terminated. Read-Host at EOF returns
    # AutomationNull, which never matches '^\d+$', so `pwsh -File apply.ps1`
    # with stdin redirected printed "Invalid choice." forever: measured at
    # ~800,000 lines in 6 seconds, still running when it was killed. That is
    # reachable from a CI step, a dotfiles manager, or anything running this
    # script with stdin detached -- and apply.ps1 ships to the PowerShell
    # Gallery, so it is not a dev-only script.
    #
    # A hard error naming the flag, rather than a default: there is no
    # defensible guess for "which style did you want".
    if (-not (Test-InteractiveConsole)) {
        $msg = "apply.ps1 needs $Flag when there is no interactive console to ask at."
        throw ($msg + " Available: " + ($Options -join ', '))
    }

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        # Cast: see the guard above. Bare, this comparison is falsy against
        # AutomationNull and the loop spins.
        $answer = "$(Read-Host 'Pick a number')"
        if ($answer -match '^\d+$') {
            $n = [int]$answer
            if ($n -ge 1 -and $n -le $Options.Count) { return $Options[$n - 1] }
        }
        # A console that reaches EOF mid-session cannot answer the re-prompt
        # either, so stop rather than spin.
        if ($null -eq $answer -or $answer -eq '') {
            throw "No answer given for: $Title"
        }
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# Main flow. Guarded so tests can dot-source this script for its functions
# (set $TStylesApplyNoRun = $true before dot-sourcing) without running the
# installer. A normal `pwsh -File apply.ps1` run never sets the var, so main runs.
if (-not $TStylesApplyNoRun) {

# --- Banner ---
Write-Host ""
Write-Host "TerminalStyles installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

# --- Style selection ---
$styles = Get-AvailableStyles
if (-not $Style) {
    $Style = Read-Choice 'Available styles:' @($styles.Name) -Flag '-Style'
}
$styleDir = ($styles | Where-Object Name -eq $Style | Select-Object -First 1).FullName
if (-not $styleDir) {
    throw "Style '$Style' not found. Available: $(($styles.Name) -join ', ')"
}
Write-Host "Style: $Style" -ForegroundColor Green

# --- Settings.json location ---
if (-not $SettingsPath) { $SettingsPath = Find-WTSettingsPath }
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    throw "Settings file not found at $SettingsPath"
}
Write-Host "Settings file: $SettingsPath"
# A preview a closed picker or tuner left goes back before the file is read or
# backed up (Restore-AbandonedFilePreview).
Show-FilePreviewResult -Result (Restore-AbandonedFilePreview -Kind WindowsTerminal -Path $SettingsPath)

# UTF-8 explicit: Get-Content -Raw in WinPS 5.1 defaults to Windows-1252,
# which mangles non-ASCII WT profile names (e.g. "Símbolo del sistema").
$settings = ConvertFrom-JsoncText ([System.IO.File]::ReadAllText($SettingsPath, [System.Text.UTF8Encoding]::new($false)))

# --- Target profile selection ---
# The module's own list, not a fork of it. Built here by hand it always offered
# 'defaults' -- including for a settings.json with no `profiles` object to
# create one on, which is the answer the check below is now guaranteed to
# refuse.
$profileNames = @((Get-WTProfileShape -Settings $settings).Available)
if (-not $profileNames.Count) {
    # Asked before the prompt, because a menu of nothing is not a question --
    # and asked of the resolver, so the refusal can say which shape it is.
    throw (Get-WTTargetNotFoundMessage -ResolvedTarget (Resolve-WTProfileTarget -Settings $settings -TargetName $Target) -TargetName $Target)
}
if (-not $Target) {
    $Target = Read-Choice 'Which Windows Terminal profile to apply this style to?' $profileNames -Flag '-Target'
}
$resolvedTarget = Resolve-WTProfileTarget -Settings $settings -TargetName $Target
if (-not $resolvedTarget.Ok) {
    throw (Get-WTTargetNotFoundMessage -ResolvedTarget $resolvedTarget -TargetName $Target)
}
# Two profiles can share a name, and this script picked one of them in silence.
# Same note the module's apply path prints.
Write-AmbiguousTargetNote -ResolvedTarget $resolvedTarget -TargetName $Target -Verb 'Applied to'
Write-Host "Target: $Target" -ForegroundColor Green

# --- Background image ---
# Precedence: explicit -BackgroundImage > interactive prompt > bundled style
# background. $bgProvided is the module's contract: $true means "the caller
# decided" (a path applies it, an empty string removes it), $false means "work
# it out from the style", which is what leaves a background the USER set in
# place rather than deleting it.
$bgProvided = $PSBoundParameters.ContainsKey('BackgroundImage')

# The ONE prompt here whose non-interactive answer is a sensible default rather
# than an error: $bgProvided = $false already means "work it out from the
# style", which is exactly what a blank answer below selects. So a
# non-interactive run takes that path silently instead of asking.
#
# It used to ask regardless, and `(Read-Host ...).Trim()` throws on the
# AutomationNull returned at EOF -- so the header's own documented
# non-interactive invocation, `-Style X -Target Y` with no -BackgroundImage,
# died with "You cannot call a method on a null-valued expression" before
# writing anything or taking a backup.
if (-not $bgProvided -and (Test-InteractiveConsole)) {
    $bundledBg = Get-StyleBundledBackground -StyleDir $styleDir
    Write-Host ""
    $hint = if ($bundledBg) { "blank = use bundled '$([System.IO.Path]::GetFileName($bundledBg))', 'none' = no background" }
            else            { "blank = no background" }
    $answer = "$(Read-Host "Background image absolute path ($hint)")".Trim()
    if ($answer -eq '') {
        # Let the merge resolve the bundled image itself -- and, when the style
        # ships none, decide by ownership whether an existing background is ours
        # to clear or the user's to keep.
        $BackgroundImage = ''
    } elseif ($answer -eq 'none') {
        $BackgroundImage = ''
        $bgProvided = $true
    } else {
        $BackgroundImage = $answer
        $bgProvided = $true
    }
}
if ($BackgroundImage -and -not (Test-Path -LiteralPath $BackgroundImage)) {
    Write-Warning "Background image path doesn't exist: $BackgroundImage (will still apply the setting)"
}

# --- Is there anything to write? ---
# Merge-StyleIntoSettings returns the settings UNTOUCHED for a style with no
# theme.json, and this script used to write them anyway -- which re-serializes
# the parsed object and drops every JSONC comment in the user's settings.json,
# while printing "settings.json updated." in green. A scheme-only style is
# legal (README documents theme.json as optional), so this is not an error;
# there is simply nothing here for Windows Terminal.
$payload = Get-StyleSettingsPayload -StyleDir $styleDir
if ($payload.Missing -eq 'scheme.json') {
    throw "Style '$Style' has no scheme.json -- nothing to apply."
}

if ($payload.Ok) {
    # --- Backup settings.json ---
    # Timestamped, unlike the module's rolling .bak: this script is the
    # scriptable path, so it keeps a full audit trail of every run. Taken only
    # once we know there is a write to make, so a no-op run does not add a
    # backup file for a change that never happened.
    $bak = "$SettingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SettingsPath -Destination $bak
    Write-Host "Backed up settings to: $bak" -ForegroundColor Gray

    # --- Merge scheme + theme (the module's own merge, not a fork of it) ---
    $settings = Merge-StyleIntoSettings -Settings $settings -StyleDir $styleDir `
        -TargetName $Target -BackgroundImage $BackgroundImage `
        -BackgroundImageProvided $bgProvided

    # --- Save settings.json (UTF-8, atomic, full depth; keeps any BOM) ---
    Write-SettingsFile -Path $SettingsPath -Settings $settings
    Write-Host "settings.json updated." -ForegroundColor Green
} else {
    Write-Host "'$Style' ships no theme.json, so settings.json was not changed." -ForegroundColor DarkGray
}

# --- The prompt ---
# Through Set-CurrentStylePrompt, the helper every apply path uses; this script
# never writes $PROFILE. It used to replace any $PROFILE without the BEGIN
# marker -- the README's own hand-added Import-Module line included -- with the
# style's profile.ps1, and it was the RUNNING engine's $PROFILE, not the
# target's. current-style.ps1 needs no such choice: both engines' loaders read
# it. A tab shows the prompt when its $PROFILE imports TerminalStyles.
$isPwshTarget = $false
if ($Target -eq 'defaults') {
    $isPwshTarget = $true
} else {
    # Shared resolver and shared rule, as in the module's own apply path.
    $entry = (Resolve-WTProfileTarget -Settings $settings -TargetName $Target).Entry
    $isPwshTarget = Test-WTProfileRunsPowerShell -Entry $entry
}

if ($isPwshTarget) {
    $promptResult = Set-CurrentStylePrompt -StyleDir $styleDir -KeepPrompt:$KeepPrompt
    $promptStatus = $promptResult.Status
    if ($promptStatus -eq 'failed') {
        Write-Host (Get-CurrentStylePromptFailureNote -Result $promptResult) -ForegroundColor Yellow
    } elseif ($promptStatus -eq 'installed') {
        Write-Host "Updated current-style.ps1 with $Style's prompt; `$PROFILE was not changed." -ForegroundColor Green
        # A clone run by path is not on PSModulePath, so `tstyles` and the
        # by-name import exist only once the module is installed.
        Write-Host "A new tab loads it when its `$PROFILE imports TerminalStyles. With the module installed" -ForegroundColor Gray
        Write-Host "(Install-PSResource TerminalStyles, or install.ps1), 'tstyles register' adds that line." -ForegroundColor Gray
    } elseif ($promptStatus -eq 'removed') {
        Write-Host "Removed current-style.ps1 (the previous style's prompt), so new tabs load no style's prompt." -ForegroundColor Gray
    }
} elseif ((Test-Path -LiteralPath (Join-Path $styleDir 'profile.ps1')) -and -not $KeepPrompt) {
    Write-Host "Note: '$Target' is not a PowerShell profile -- skipping profile.ps1 install." -ForegroundColor Yellow
}

# Last, so a failed settings.json write above (this script runs under Stop)
# records nothing. A failed prompt step does not stop it: the colours are
# already written, and Set-CurrentStylePrompt reports that failure itself.
# -Kind explicitly: the default describes whatever runs this script, and a
# scheduled task or a non-WT console is not Windows Terminal.
Set-CurrentStyleRecord -StyleName $Style -Kind 'WindowsTerminal'

Write-Host ""
Write-Host "Done. Open a new '$Target' tab in Windows Terminal to see the result." -ForegroundColor Cyan

}
