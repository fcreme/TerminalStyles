# help.ps1 -- `tstyles help`, and the data behind it.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Get-TerminalStyleHelpData is deliberately separate from the rendering: it is
# the one place that knows every subcommand, so a test can assert the dispatcher
# and the help agree rather than letting them drift.

function Get-TerminalStyleHelpData {
    # Single source of truth for `tstyles help`. Ordered command descriptors.
    # Name is the dispatch token AND the `help <Name>` topic key. The picker
    # and `tstyles <style>` are arg-less modes described in the overview
    # preamble (Show-TerminalStyleHelp), not topics here. A drift-guard test
    # asserts every dispatched subcommand has an entry.
    @(
        [pscustomobject]@{
            Name = 'list'; Usage = 'list'; Summary = "List all styles; '*' marks the active one"
            Detail = @("Prints every available style (bundled + your own), one per line,",
                       "with the active style marked by an asterisk.")
            Keys = @(); Examples = @('tstyles list')
        }
        [pscustomobject]@{
            Name = 'current'; Usage = 'current'; Summary = 'Print the active style name'
            Detail = @("Prints just the name of the currently applied style (or nothing",
                       "if none is detected).")
            Keys = @(); Examples = @('tstyles current')
        }
        [pscustomobject]@{
            Name = 'random'; Usage = 'random'; Summary = 'Apply a random style'
            Detail = @("Picks a random style and applies it immediately.")
            Keys = @(); Examples = @('tstyles random')
        }
        [pscustomobject]@{
            Name = 'reset'; Usage = 'reset [-Target <name>]'; Summary = 'Revert a profile to its unstyled default'
            Detail = @("Strips the colors, cursor, font, opacity, and background a style added",
                       "to the target profile, and restores your own prompt. The inverse of",
                       "applying a style.",
                       "",
                       "On Windows Terminal that means editing settings.json, and a",
                       "settings.json.bak is written first. Elsewhere there is no",
                       "settings.json to strip: the reset is an escape sequence handing",
                       "color control back to the terminal's own profile, so there is",
                       "nothing to back up and no .bak is written.")
            Keys = @(); Examples = @('tstyles reset', "tstyles reset -Target 'Ubuntu'")
        }
        [pscustomobject]@{
            Name = 'tune'; Usage = 'tune [name]'; Summary = 'Live-tune a style; save as your own'
            Detail = @("Opens an arrow-key editor for the active style (or [name]). Adjusts",
                       "brightness, saturation, opacity, font face, and font size.",
                       "Saved styles land in your user dir and show up in 'tstyles list'.",
                       "",
                       "Outside Windows Terminal, brightness and saturation preview live;",
                       "opacity and font are recorded in the saved style but no terminal",
                       "there can show them, because no escape sequence carries them and",
                       "the Terminal.app profile carries only colors and a background.")
            Keys = @('Up/Down      select a knob',
                     'Left/Right   adjust it',
                     'R            reset color',
                     'Enter        save (Overwrite / Save as)',
                     'Esc          revert')
            Examples = @('tstyles tune', 'tstyles tune eva')
        }
        [pscustomobject]@{
            Name = 'delete'; Usage = 'delete [name]'; Summary = 'Delete a style you made (bundled styles are refused)'
            Detail = @("With no name, lists the styles this command can act on.",
                       "",
                       "The folder is MOVED to .deleted/<name>-<timestamp> in your data dir",
                       "and kept for 7 days, so a mistake is undone by moving it back. The",
                       "cached background and any Terminal.app profile are left alone.",
                       "",
                       "If your style shadows a bundled one of the same name, deleting yours",
                       "does not remove the name -- it reveals the bundled style again. The",
                       "confirmation says which of the two will happen, and names any style",
                       "tuned from this one that loses its adjustments.")
            Keys = @(); Examples = @('tstyles delete', 'tstyles delete my-theme')
        }
        [pscustomobject]@{
            Name = 'font'; Usage = 'font [name]'; Summary = 'Install a coding font and apply it to the active profile'
            Detail = @("With no argument, lists available coding fonts with installed/installable",
                       "markers. With a font name, installs it (if not already present) and,",
                       "on Windows Terminal, applies it to the active profile.",
                       "",
                       "Every other terminal takes its font from its own preferences, so",
                       "the font is installed for you to select there by hand -- tstyles",
                       "says so rather than applying it.")
            Keys = @(); Examples = @('tstyles font', 'tstyles font ''JetBrains Mono''')
        }
        [pscustomobject]@{
            Name = 'register'; Usage = 'register'; Summary = 'Add the loader to your $PROFILE'
            Detail = @("Adds the Import-Module loader to both PowerShell 7 and Windows",
                       "PowerShell 5.1 `$PROFILE files (with a confirm prompt) so tstyles",
                       "loads on every new tab.")
            Keys = @(); Examples = @('tstyles register')
        }
        [pscustomobject]@{
            Name = 'shell-init'; Usage = 'shell-init'; Summary = 'Style zsh/bash too, not just PowerShell'
            Detail = @("Adds a loader to your ~/.zshrc, ~/.bashrc and ~/.bash_profile so a zsh",
                       "or bash tab comes up in the applied style -- colors, prompt, and banner.",
                       "Also defines a 'tstyles' command for those shells.",
                       "",
                       "Colors belong to the terminal rather than to any one shell, so without",
                       "this a zsh user still sees the palette but keeps their own prompt.",
                       "Re-run it any time; it refreshes the block instead of adding a second.")
            Keys = @(); Examples = @('tstyles shell-init')
        }
        [pscustomobject]@{
            Name = 'shell-remove'; Usage = 'shell-remove'; Summary = 'Remove the zsh/bash loader'
            Detail = @("Strips the loader block from your shell rc files and clears the staged",
                       "prompt. Your own prompt returns in the next tab. The inverse of",
                       "shell-init; leaves the PowerShell side untouched.")
            Keys = @(); Examples = @('tstyles shell-remove')
        }
        [pscustomobject]@{
            Name = 'update'; Usage = 'update'; Summary = 'Update to the latest version'
            Detail = @("Updates TerminalStyles. PSGallery installs run Update-PSResource;",
                       "bootstrap installs re-run the installer.")
            Keys = @(); Examples = @('tstyles update')
        }
        [pscustomobject]@{
            Name = 'uninstall'; Usage = 'uninstall'; Summary = 'Remove the module (keeps your styles)'
            Detail = @("Removes the module and strips the `$PROFILE loader. Your saved",
                       "styles and state are preserved unless you pass -DeleteData.")
            Keys = @(); Examples = @('tstyles uninstall', 'tstyles uninstall -DeleteData')
        }
        [pscustomobject]@{
            Name = 'help'; Usage = 'help [command]'; Summary = 'Show all commands, or details for one'
            Detail = @("With no argument, lists every command. With a command name, shows",
                       "detailed help for that command.")
            Keys = @(); Examples = @('tstyles help', 'tstyles help tune')
        }
    )
}

function Show-TerminalStyleHelp {
    # Renders `tstyles help`. No -Command: the overview (USAGE + COMMANDS +
    # EXAMPLES + docs link). With -Command: that command's detail, or a
    # not-found message. Data comes from Get-TerminalStyleHelpData. All ASCII,
    # lightly colorized to match the picker/tuner.
    param([string]$Command)

    $data = Get-TerminalStyleHelpData

    if ($Command) {
        # No .ToLower(). PowerShell's -eq is already both case-insensitive and
        # culture-INVARIANT, which .ToLower() is not: it lowercases with the
        # current culture, so under tr-TR / az-AZ an uppercase 'I' becomes the
        # dotless 'i' and `tstyles help LIST` looked up "list" -- printing
        # "No help topic 'LIST'." directly above a topics line containing 'list'.
        # The dispatcher accepts `tstyles LIST` in the same session, because it
        # compares with a bare -eq like everything else here. This was the only
        # culture-sensitive comparison left in the module.
        $entry = $data | Where-Object { $_.Name -eq $Command } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "No help topic '$Command'." -ForegroundColor Yellow
            Write-Host ("Topics: " + (($data.Name) -join ', ')) -ForegroundColor DarkGray
            return
        }
        Write-Host ""
        Write-Host ("tstyles " + $entry.Usage) -ForegroundColor Cyan -NoNewline
        Write-Host (" - " + $entry.Summary)
        if ($entry.Detail) {
            Write-Host ""
            foreach ($line in $entry.Detail) { Write-Host ("  " + $line) }
        }
        if ($entry.Keys) {
            Write-Host ""
            Write-Host "KEYS" -ForegroundColor DarkGray
            foreach ($k in $entry.Keys) { Write-Host ("  " + $k) }
        }
        if ($entry.Examples) {
            Write-Host ""
            Write-Host "EXAMPLES" -ForegroundColor DarkGray
            foreach ($e in $entry.Examples) { Write-Host ("  " + $e) }
        }
        Write-Host ""
        return
    }

    # Overview. Module version is best-effort (no disk I/O); omitted if absent.
    $ver = $ExecutionContext.SessionState.Module.Version
    # Not "for Windows Terminal". This module styles Terminal.app, iTerm2,
    # kitty, WezTerm, Ghostty, Alacritty and VS Code as well, and the line was
    # the first thing a macOS or Linux user read -- naming the one terminal
    # they were not using.
    $title = if ($ver) { "tstyles - themed styles for your terminal (v$ver)" }
             else       { "tstyles - themed styles for your terminal" }

    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor DarkGray
    Write-Host "  tstyles [command] [args]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor DarkGray
    Write-Host "  (no command)      Open the interactive picker"
    Write-Host "  <style>           Apply a style by name (umbrella, eva, ...)"
    foreach ($e in $data) {
        Write-Host ("  " + ('{0,-16}' -f $e.Usage) + "  " + $e.Summary)
    }
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor DarkGray
    Write-Host "  tstyles                 # pick interactively"
    Write-Host "  tstyles eva             # apply 'eva'"
    Write-Host "  tstyles tune eva        # tune + save your own"
    Write-Host ""
    Write-Host "More: https://github.com/fcreme/TerminalStyles" -ForegroundColor DarkGray
    Write-Host ""
}
