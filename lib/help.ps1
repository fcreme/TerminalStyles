# help.ps1 -- `tstyles help`, and the data behind it.
#
# Dot-sourced by tstyles.ps1, so everything here shares its $script: scope.
#
# Get-TerminalStyleHelpData is deliberately separate from the rendering: it is
# the one place that knows every subcommand, so a test can assert the dispatcher
# and the help agree rather than letting them drift.

function Get-TerminalStyleHelpData {
    # Single source of truth for `tstyles help`. Ordered command descriptors.
    # Name is the dispatch token AND the `help <Name>` topic key -- except for
    # the one entry carrying Dispatches = $false, `apply`, which documents
    # `tstyles <style>`: a mode rather than a word the dispatcher matches. The
    # picker is the other mode, described in the overview preamble
    # (Show-TerminalStyleHelp). A drift-guard test asserts every dispatched
    # subcommand has an entry and every dispatching entry names a subcommand.
    #
    # -Platform is a test seam; real callers omit it. Two topics describe what
    # the tool does to PowerShell engines and to shell rc files, and both
    # answers differ by platform -- the register topic named Windows
    # PowerShell 5.1 on macOS and Linux for four releases because the sentence
    # was a literal rather than a reading of the engine table the command
    # itself probes with.
    param([string]$Platform = (Get-TStylesPlatform))

    # Projected with ForEach-Object: member access on an empty array yields one
    # $null, so `.Label` on a candidate list that came back empty would be a
    # one-element list holding nothing, and the sentence would name it.
    $engineLabels = @(Get-PowerShellEngineCandidate -Platform $Platform |
                      ForEach-Object { $_.Label })

    @(
        [pscustomobject]@{
            # NOT a dispatch token, and the one entry that is not. `tstyles
            # <style>` is a MODE: the dispatcher falls through every subcommand
            # arm and matches the argument against the style list, so there is
            # no 'apply' word to type -- `tstyles help apply` is where the mode
            # is documented. Dispatches = $false is what tells the drift guard
            # in tests/Get-TerminalStyleHelpData.Tests.ps1 that this topic has
            # no matching subcommand on purpose; it is a named exception there,
            # not a blanket skip. It is deliberately NOT added to
            # $script:TStylesSubcommands: that list is also what
            # Test-StyleNameValid rejects style names against, and a style
            # called 'apply' would then be forbidden for a command that does
            # not dispatch.
            Name = 'apply'; Dispatches = $false
            Usage = '<style> [-KeepPrompt] [-NewWindow]'
            Summary = 'Apply a style by name (umbrella, eva, ...)'
            Detail = @("The command this tool is for, and the only one that is not a",
                       "subcommand: 'tstyles eva' applies the style called eva to the",
                       "terminal you are sitting in, and records it so new tabs come up in",
                       "it too.",
                       "",
                       "  -KeepPrompt              Apply the colors, font, opacity and",
                       "                           background, but leave your own prompt and",
                       "                           banner alone -- for Oh My Posh, Starship,",
                       "                           or any prompt you would rather keep.",
                       "  -NewWindow               Terminal.app only: open a NEW window",
                       "                           carrying the style's background image. No",
                       "                           escape sequence can put an image on the",
                       "                           window you are already in. If the style",
                       "                           ships no image, or it could not be",
                       "                           downloaded, it says which -- it never just",
                       "                           opens nothing.",
                       "  -Target <name>           Windows Terminal profile to apply to,",
                       "                           instead of the tab's own. 'defaults' is a",
                       "                           name in its own right -- it is what the",
                       "                           not-found message offers first -- and it",
                       "                           means Windows Terminal's profiles.defaults:",
                       "                           every profile that does not set a field",
                       "                           itself inherits it, so a style applied",
                       "                           there styles all of them. Applying a later",
                       "                           style with no background image of its own",
                       "                           clears the image from defaults, and from",
                       "                           every profile that was inheriting it.",
                       "  -BackgroundImage <path>  Use this image instead of the style's.",
                       "                           An empty string ('') turns the background",
                       "                           OFF. Both are Windows Terminal only --",
                       "                           it is the only host whose background this",
                       "                           tool writes as a setting.",
                       "",
                       "Whatever the current terminal cannot show is named as the style is",
                       "applied, rather than dropped in silence.")
            Keys = @()
            Examples = @('tstyles eva', 'tstyles eva -KeepPrompt', "tstyles eva -BackgroundImage ''",
                         'tstyles eva -Target defaults')
        }
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
            Name = 'show'; Usage = 'show <name>'; Summary = 'Preview a style without applying it'
            Detail = @("Repaints the palette so you can see a style, waits for a keypress,",
                       "then puts the terminal back. It writes nothing -- no settings file,",
                       "no profile, no current-style record -- which is the whole point: it",
                       "is the way to look at a style without committing to it.",
                       "",
                       "The cost of writing nothing is that a background, font and cursor",
                       "shape are not part of what you see. On Windows Terminal those are",
                       "most of a style, and the command says so on screen.")
            Keys = @(); Examples = @('tstyles show lain', 'tstyles show koholint')
        },
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
                       "-Target takes 'defaults' as well as a profile name: that is Windows",
                       "Terminal's profiles.defaults, which every profile inherits from, so",
                       "resetting it reaches the ones that never set those fields themselves.",
                       "",
                       "On Windows Terminal that means editing settings.json, and a",
                       "settings.json.bak is written first. Elsewhere there is no",
                       "settings.json to strip: the reset is an escape sequence handing",
                       "color control back to the terminal's own profile, so there is",
                       "nothing to back up and no .bak is written.",
                       "",
                       "A profile also inherits from profiles.defaults. A background image",
                       "this tool put THERE is cleared along with the profile -- which",
                       "removes it from every profile inheriting it, so the command says so.",
                       "An inherited colorScheme is left alone for the same reason it would",
                       "be removed: it belongs to every profile, not the one you named. Reset",
                       "names it and points at 'tstyles reset -Target defaults'.")
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
                       "and kept for $($script:TStylesTrashKeepDays) days: 'tstyles trash' lists what is in there and",
                       "'tstyles restore <name>' puts one back. The cached background and any",
                       "Terminal.app profile are left alone.",
                       "",
                       "If your style shadows a bundled one of the same name, deleting yours",
                       "does not remove the name -- it reveals the bundled style again. The",
                       "confirmation says which of the two will happen, and names any style",
                       "tuned from this one that loses its adjustments.",
                       "",
                       "A bundled style you have edited in place -- tuned with Overwrite, or",
                       "replaced by dropping a folder of the same name into your styles dir --",
                       "counts as yours and can be deleted. Where there is only one styles",
                       "dir (a bootstrap install) the name goes with it until the next",
                       "'tstyles update' puts the shipped copy back.")
            Keys = @(); Examples = @('tstyles delete', 'tstyles delete my-theme')
        }
        [pscustomobject]@{
            Name = 'trash'; Usage = 'trash'; Summary = 'List deleted styles and how long each has left'
            Detail = @("Deleting a style moves it to .deleted/<name>-<timestamp> in your data",
                       "dir. This lists what is in there, when each one went, and how many of",
                       "its $($script:TStylesTrashKeepDays) days are left.",
                       "",
                       "Read-only: it erases nothing. An entry past the window is shown in red",
                       "because the next 'tstyles delete' erases it -- that command names it",
                       "again, in red, on the screen you confirm.")
            Keys = @(); Examples = @('tstyles trash')
        }
        [pscustomobject]@{
            Name = 'restore'; Usage = 'restore [name]'; Summary = 'Put a deleted style back'
            Detail = @("Moves the newest trashed copy of <name> back into your styles dir under",
                       "the plain name -- the timestamp never comes with it. With no name, it",
                       "lists the trash.",
                       "",
                       "Nothing is overwritten: if a style of that name exists again the",
                       "restore refuses, says so, and leaves the trashed copy where it is. It",
                       "restores the folder and nothing else -- it does not re-apply the style",
                       "or undo the reset the delete performed.")
            Keys = @(); Examples = @('tstyles restore', 'tstyles restore my-theme')
        }
        [pscustomobject]@{
            # "and apply it to the active profile" is Windows Terminal only, and
            # this Summary is rendered by an overview loop with no platform
            # branch in it -- so on every other terminal the shortest
            # description of the command promised an apply the command then
            # declined. Phrased to be true everywhere; the Detail below draws
            # the platform line.
            Name = 'font'; Usage = 'font [name]'; Summary = 'Install a coding font (and apply it where tstyles can)'
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
            # Built from the engine table rather than repeating it. This line
            # said "both PowerShell 7 and Windows PowerShell 5.1" on every
            # platform, and was wrong twice off Windows: there is no Windows
            # PowerShell there (the engines probed are pwsh and pwsh-preview),
            # and "both" is wrong wherever only one of them is installed --
            # register skips an engine it does not find, and says so.
            Detail = @("Adds the Import-Module loader (with a confirm prompt) to the `$PROFILE",
                       "of each PowerShell engine found on your PATH, so tstyles loads on",
                       "every new tab.",
                       "",
                       ("On {0} the engines looked for are: {1}." -f $Platform, ($engineLabels -join ', ')),
                       "An engine that is not installed is skipped, not written to.",
                       "Where two engines share one `$PROFILE it is written once.")
            Keys = @(); Examples = @('tstyles register')
        }
        [pscustomobject]@{
            Name = 'shell-init'; Usage = 'shell-init'; Summary = 'Style zsh/bash too, not just PowerShell'
            # Qualified per platform, the way the `font` and `reset` topics
            # already qualify themselves. This promised "a zsh or bash tab
            # comes up in the applied style" on every platform, and on Windows
            # no configuration can produce it: the apply path that stages
            # current-style.osc and current-prompt.sh runs only off Windows
            # Terminal, and shell/tstyles.sh has no MSYS/MinGW/Cygwin arm at
            # all -- under Git Bash it resolves TSTYLES_DATA to
            # $HOME/.local/share/TerminalStyles while the PowerShell side
            # stages to %LOCALAPPDATA%\TerminalStyles. So the command would
            # write (and, for a user with no bash, INVENT) rc files under
            # C:\Users\<you> that can never find a style to paint.
            Detail = $(if ($Platform -eq 'Windows') {
                @("The zsh/bash loader is a macOS/Linux feature, and this command cannot",
                  "deliver it on Windows -- it is listed here so the limit is not a",
                  "surprise.",
                  "",
                  "A Git Bash / MSYS shell shares your Windows home, so the loader would",
                  "go into C:\Users\<you>\.bashrc -- but the runtime it sources looks for",
                  "the applied style under `$HOME/.local/share/TerminalStyles, while the",
                  "apply writes it to %LOCALAPPDATA%\TerminalStyles. The tab would come",
                  "up with your own prompt and no style.",
                  "",
                  "On macOS and Linux the same command wires the shell side up in full:",
                  "the loader goes into ~/.zshrc, ~/.bashrc and ~/.bash_profile, and the",
                  "runtime finds the staged style where the apply put it.")
            } else {
                @("Adds a loader to your ~/.zshrc, ~/.bashrc and ~/.bash_profile so a zsh",
                  "or bash tab comes up in the applied style -- colors, prompt, and banner.",
                  "Also defines a 'tstyles' command for those shells.",
                  "",
                  "Two files it does not name above, in the layouts that need them:",
                  "your ~/.profile, when that is the only file your login shell reads,",
                  "and `$ZDOTDIR/.zshrc when you keep zsh config outside your home.",
                  "",
                  "Colors belong to the terminal rather than to any one shell, so without",
                  "this a zsh user still sees the palette but keeps their own prompt.",
                  "Re-run it any time; it refreshes the block instead of adding a second.")
            })
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
            Name = 'profiles'; Usage = 'profiles [-Clean]'
            Summary = 'Terminal.app profiles this tool has left behind (macOS)'
            Detail = @("Opening a style with -NewWindow imports a .terminal profile into",
                       "Terminal.app. Before this was fixed, every run imported ANOTHER copy --",
                       "Terminal.app numbers the collisions, so a style opened four times left",
                       "'eva', 'eva 1', 'eva 2' and 'eva 3' in your profile list for good.",
                       "",
                       "This lists them and, with -Clean, deletes the numbered ones. The",
                       "unnumbered profile is never touched: it may be one you made yourself,",
                       "and there is no way to prove otherwise.")
            Keys = @(); Examples = @('tstyles profiles', 'tstyles profiles -Clean')
        }
        [pscustomobject]@{
            Name = 'uninstall'; Usage = 'uninstall'; Summary = 'Remove the module (keeps your styles)'
            Detail = @("Removes the module and strips the loader from the `$PROFILE of every",
                       "PowerShell engine on this machine. It also strips the zsh/bash loader",
                       "block from your shell rc files -- the same files shell-remove sweeps",
                       "-- so an uninstall does not leave a shell sourcing a runtime it just",
                       "deleted.",
                       "",
                       "Your saved styles and state are preserved unless you pass -DeleteData.",
                       "The confirmation names every file it is about to change, `$PROFILE and",
                       "rc alike, and the sign-off names any it could not.")
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
    # The `<style>` line is the apply descriptor's own, not a literal beside
    # it: it used to be typed here, which is how the tool's primary command
    # ended up with a line in this list, no `help` topic, and two of its four
    # flags (-KeepPrompt, -BackgroundImage) named nowhere in the help at all.
    # One entry, printed here like every other, and `tstyles help apply`
    # reaches the same record.
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
