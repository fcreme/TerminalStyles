# Pester 5 tests for Get-TerminalKind (module-private).
#
# Detection is pure env-var inspection, so every case is driven through the
# -EnvTable seam rather than by mutating the real $env: -- which would be
# order-dependent and would break the host session's own detection. Windows
# Terminal is believed only on Windows, so the cases that carry WT_SESSION also
# say which platform they are on: through the -Platform seam (what
# Get-TStylesPlatform would answer), or by mocking Get-TStylesPlatform, which
# is the default every real caller gets. Unbound, they would answer for the CI
# leg they happen to run on.
#
# The -ForEach cases are hashtables, so Pester binds their keys as variables
# ($Marker, $Value, $Term, $Kind, ...); a [pscustomobject] case would arrive
# only as $_.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-TerminalKind' {
    InModuleScope TerminalStyles {

        It 'detects Windows Terminal from WT_SESSION on Windows' {
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = 'a-guid'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            } -Platform 'Windows' | Should -BeExactly 'WindowsTerminal'
        }

        It 'detects Windows Terminal from WT_SESSION when Get-TStylesPlatform says Windows' {
            # The default every real caller gets. A default read from $IsWindows
            # instead would be $null on Windows PowerShell 5.1 -- and on the
            # macOS and Linux legs, where this mock is all that says Windows --
            # and every real WT session on the 5.1 engine would lose its writer.
            Mock Get-TStylesPlatform { 'Windows' }
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = 'a-guid'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
            } | Should -BeExactly 'WindowsTerminal'
        }

        It 'reads an empty TERM_PROGRAM beside WT_SESSION as none' {
            # Only -EnvTable can carry '' -- setting an environment variable to
            # '' removes it on Windows -- but a test written as
            # `$null -eq $program` would refuse it.
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = 'a-guid'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
                TERM_PROGRAM  = ''
            } -Platform 'Windows' | Should -BeExactly 'WindowsTerminal'
        }

        # Windows Terminal puts WT_SESSION and WT_PROFILE_ID into every process
        # a tab starts, and lists both in WSLENV so they reach WSL. A pwsh
        # inside WSL is a Linux install, with Windows Terminal's settings.json
        # on the Windows side, out of its reach -- so answering WindowsTerminal
        # there stopped every apply, reset, tune and picker run on "Could not
        # locate Windows Terminal settings.json.", while WT renders the escape
        # sequences every other terminal is styled with. 'Unknown' is the
        # escape-sequence kind.
        It 'does not answer WindowsTerminal for an inherited WT_SESSION on <_>' -ForEach @('Linux', 'MacOS') {
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = '1b6a9c2e-0000-4000-8000-000000000001'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
                WSLENV        = 'WT_SESSION:WT_PROFILE_ID:'
            } -Platform $_ | Should -BeExactly 'Unknown'
        }

        It 'gates WT_SESSION on Get-TStylesPlatform when -Platform is not bound' {
            # How every real caller calls it. Together with the Windows case
            # above, this pins the default on every leg.
            Mock Get-TStylesPlatform { 'Linux' }
            Get-TerminalKind -EnvTable @{ WT_SESSION = 'a-guid' } | Should -BeExactly 'Unknown'
            Should -Invoke Get-TStylesPlatform -Because 'the platform must come from Get-TStylesPlatform, not from $IsWindows'
        }

        It 'detects Terminal.app from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'Apple_Terminal' } | Should -Be 'AppleTerminal'
        }

        It 'detects iTerm2 from ITERM_SESSION_ID' {
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0' } | Should -Be 'ITerm2'
        }

        It 'detects iTerm2 from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'iTerm.app' } | Should -Be 'ITerm2'
        }

        It 'detects Ghostty from GHOSTTY_RESOURCES_DIR' {
            Get-TerminalKind -EnvTable @{ GHOSTTY_RESOURCES_DIR = '/opt/ghostty' } | Should -Be 'Ghostty'
        }

        It 'detects WezTerm from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'WezTerm' } | Should -Be 'WezTerm'
        }

        It 'detects kitty from KITTY_WINDOW_ID' {
            Get-TerminalKind -EnvTable @{ KITTY_WINDOW_ID = '1' } | Should -Be 'Kitty'
        }

        It 'detects Alacritty from ALACRITTY_WINDOW_ID' {
            Get-TerminalKind -EnvTable @{ ALACRITTY_WINDOW_ID = '1' } | Should -Be 'Alacritty'
        }

        It 'detects the VS Code integrated terminal' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'vscode' } | Should -Be 'VSCode'
        }

        It "returns 'Unknown' for a bare environment rather than guessing" {
            Get-TerminalKind -EnvTable @{} | Should -Be 'Unknown'
        }

        It "returns 'Unknown' for an unrecognized TERM_PROGRAM" {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'SomeFutureTerm' } | Should -Be 'Unknown'
        }

        # Ordering matters, and it follows which marker can be inherited INTO
        # which host. A VS Code that `code .` started from a WT tab carries
        # WT_SESSION and WT_PROFILE_ID in every terminal it opens, and its
        # Remote-WSL terminal gets them through WSLENV; answering
        # WindowsTerminal there rewrote WT's settings.json for the inherited
        # profile. The reverse is rare: Windows Terminal sets no TERM_PROGRAM,
        # and a tab's environment is rebuilt from the registry unless the
        # profile turns compatibility.reloadEnvironmentVariables off, or `wt`
        # was given a command line -- in those cases it inherits the
        # environment of whatever ran `wt`. So a tab that `wt <command>` opened
        # from a VS Code terminal reads as VS Code too. That is accepted: no
        # Windows Terminal file is written, and VS Code's is written only after
        # its own consent question.
        It 'prefers TERM_PROGRAM=vscode over an inherited WT_SESSION on <_>' -ForEach @('Windows', 'Linux') {
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = 'a-guid'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
                TERM_PROGRAM  = 'vscode'
            } -Platform $_ | Should -BeExactly 'VSCode'
        }

        # The same inheritance from every other terminal. VS Code keeps
        # everything it inherits except VSCODE_*, ELECTRON_*, SNAP* and
        # GDK_PIXBUF_*, so a VS Code opened from iTerm2, Ghostty, WezTerm,
        # kitty or Alacritty carries that terminal's own marker beside
        # TERM_PROGRAM=vscode -- and was named as that terminal: VS Code's
        # consent was never asked and its settings.json never written, and from
        # WezTerm the apply rewrote WezTerm's Lua module instead. iTerm2,
        # WezTerm and Ghostty set TERM_PROGRAM afresh in the sessions they host,
        # so 'vscode' beside their markers can only mean VS Code is the host.
        # TERM is xterm-256color, which VS Code sets in every terminal it starts
        # on macOS and Linux.
        It 'prefers TERM_PROGRAM=vscode over an inherited <Marker>' -ForEach @(
            @{ Marker = 'ITERM_SESSION_ID';      Value = 'w0t0p0:F1C2' }
            @{ Marker = 'GHOSTTY_RESOURCES_DIR'; Value = '/Applications/Ghostty.app/Contents/Resources/ghostty' }
            @{ Marker = 'WEZTERM_PANE';          Value = '0' }
            @{ Marker = 'WEZTERM_EXECUTABLE';    Value = '/Applications/WezTerm.app/Contents/MacOS/wezterm-gui' }
            @{ Marker = 'WEZTERM_UNIX_SOCKET';   Value = '/tmp/wezterm-sock' }
            @{ Marker = 'KITTY_WINDOW_ID';       Value = '1' }
            @{ Marker = 'ALACRITTY_WINDOW_ID';   Value = '1' }
        ) {
            # Not named $env: that is the provider drive every other variable
            # here is deliberately avoiding.
            $table = @{ TERM_PROGRAM = 'vscode'; TERM = 'xterm-256color' }
            $table[$Marker] = $Value
            Get-TerminalKind -EnvTable $table -Platform 'MacOS' | Should -BeExactly 'VSCode'
        }

        It 'still answers <Kind> for a <Kind> window started from a VS Code terminal' -ForEach @(
            @{ Marker = 'KITTY_WINDOW_ID';     Term = 'xterm-kitty'; Kind = 'Kitty' }
            @{ Marker = 'ALACRITTY_WINDOW_ID'; Term = 'alacritty';   Kind = 'Alacritty' }
        ) {
            # The counterweight: 'vscode' must not win outright. kitty and
            # Alacritty never touch TERM_PROGRAM, so a window either one opens
            # from a VS Code terminal carries 'vscode' -- and the inherited
            # VSCODE_* variables -- too. Only TERM, which each sets for itself,
            # tells it apart.
            $table = @{ TERM_PROGRAM = 'vscode'; TERM = $Term; VSCODE_GIT_IPC_HANDLE = '/tmp/vscode-git-1.sock' }
            $table[$Marker] = '1'
            Get-TerminalKind -EnvTable $table -Platform 'Linux' | Should -BeExactly $Kind
        }

        # ITERM_SESSION_ID survives a TERM_PROGRAM clobber, so it wins over a
        # stale/foreign TERM_PROGRAM value.
        It 'prefers ITERM_SESSION_ID over a conflicting TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0'; TERM_PROGRAM = 'Apple_Terminal' } |
                Should -Be 'ITerm2'
        }

        # ...and WezTerm's own markers must survive the same inheritance, which
        # they did not: WezTerm was identified by TERM_PROGRAM alone, BELOW the
        # ITERM_SESSION_ID gate, while exporting three unambiguous variables the
        # function never read. Any session carrying an inherited ITERM_SESSION_ID
        # -- a tmux server whose environment was captured under iTerm2, ssh with
        # SendEnv, a WezTerm window launched from an iTerm2 shell -- resolved to
        # 'ITerm2'.
        #
        # Measured on 0.8.28 through a real child-process environment, not just
        # this seam: with ITERM_SESSION_ID set alongside TERM_PROGRAM=WezTerm and
        # WEZTERM_PANE, the kind came back 'ITerm2' with Persist/Font/Padding/
        # BackgroundImage all $false -- so Publish-StyleWezTermConfig returned at
        # its `if ($Kind -ne 'WezTerm')` guard, wrote no Lua module, and printed
        # nothing. kitty, Alacritty and Ghostty were already protected by
        # own-marker checks placed above that gate; WezTerm, the one terminal off
        # Windows with a config writer, was not.
        It 'prefers <_> over an inherited ITERM_SESSION_ID' -ForEach @(
            'WEZTERM_PANE', 'WEZTERM_EXECUTABLE', 'WEZTERM_UNIX_SOCKET') {
            # Not named $env: that is the provider drive every other variable
            # here is deliberately avoiding.
            $table = @{ ITERM_SESSION_ID = 'w0t0p0:F1C2'; TERM_PROGRAM = 'WezTerm' }
            $table[$_] = '0'
            Get-TerminalKind -EnvTable $table | Should -Be 'WezTerm'
        }

        It 'still answers ITerm2 when only iTerm2 markers are present' {
            # The counterweight: the new check must not swallow a real iTerm2
            # session. Nothing here sets a WEZTERM_* variable.
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0'; TERM_PROGRAM = 'iTerm.app' } |
                Should -Be 'ITerm2'
        }

        # A WezTerm or Alacritty window started from a WT tab inherits
        # WT_SESSION, and was taken for Windows Terminal: WT's settings.json was
        # written for the inherited profile, no escape sequence was sent, and
        # WezTerm's Lua module was never written. The reverse is rare, for the
        # reason the vscode case above gives: a tab's environment is rebuilt
        # from the registry, which keeps WEZTERM_* and ALACRITTY_WINDOW_ID out of
        # it, unless the profile turns compatibility.reloadEnvironmentVariables
        # off, or `wt` was given a command line -- in those cases it inherits
        # the environment of whatever ran `wt`. A tab that `wt <command>` opened
        # from a WezTerm shell therefore reads as WezTerm, which is accepted.
        #
        # WezTerm sets TERM_PROGRAM=WezTerm, which on its own keeps it away
        # from the Windows Terminal check. Alacritty sets none, so for it the
        # order alone decides.
        It "prefers <Kind>'s own marker over an inherited WT_SESSION" -ForEach @(
            @{ Marker = 'WEZTERM_PANE';        Program = 'WezTerm'; Kind = 'WezTerm' }
            @{ Marker = 'ALACRITTY_WINDOW_ID'; Program = $null;     Kind = 'Alacritty' }
        ) {
            $table = @{ WT_SESSION = 'a-guid'; WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}' }
            $table[$Marker] = '0'
            if ($Program) { $table['TERM_PROGRAM'] = $Program }
            Get-TerminalKind -EnvTable $table -Platform 'Windows' | Should -BeExactly $Kind
        }

        It 'does not answer WindowsTerminal for a host that sets its own TERM_PROGRAM, started from a WT tab' {
            # Git Bash's mintty sets TERM_PROGRAM=mintty unconditionally, and a
            # mintty window opened from a WT tab inherits WT_SESSION and
            # WT_PROFILE_ID. Answering WindowsTerminal there rewrote WT's
            # settings.json for the inherited profile and printed "Style
            # applied" over a window whose colors did not change. Windows
            # Terminal sets no TERM_PROGRAM, so beside one the answer is the
            # escape sequences, which write no file. A tab that `wt <command>`
            # opened from a mintty shell carries the same variables and gets the
            # same answer: the environment cannot tell the two apart.
            Get-TerminalKind -EnvTable @{
                WT_SESSION    = 'a-guid'
                WT_PROFILE_ID = '{2c4de342-38b7-51cf-b940-2309a097f518}'
                TERM_PROGRAM  = 'mintty'
                TERM          = 'xterm'
            } -Platform 'Windows' | Should -BeExactly 'Unknown'
        }

        # What the environment cannot settle. WezTerm keeps an inherited
        # KITTY_WINDOW_ID, and kitty keeps an inherited TERM_PROGRAM and
        # WEZTERM_*, so "WezTerm started from a kitty shell" and "kitty, with
        # term xterm-256color, started from a WezTerm shell" carry exactly
        # these variables -- as do the Alacritty and Terminal.app pairs. This
        # pins the reading that writes no config: kitty and Alacritty claim the
        # OSC palette only, while WezTerm's and Terminal.app's writers would
        # write a config that window may not read. It is what fails if the
        # kitty/Alacritty tie-break is widened from 'vscode' to any
        # TERM_PROGRAM.
        It 'answers <Kind> when its marker meets a <Program> TERM_PROGRAM that TERM cannot settle' -ForEach @(
            @{ Marker = 'KITTY_WINDOW_ID';     Program = 'WezTerm';        Other = 'WEZTERM_PANE';    Platform = 'Linux'; Kind = 'Kitty' }
            @{ Marker = 'ALACRITTY_WINDOW_ID'; Program = 'WezTerm';        Other = 'WEZTERM_PANE';    Platform = 'Linux'; Kind = 'Alacritty' }
            @{ Marker = 'KITTY_WINDOW_ID';     Program = 'Apple_Terminal'; Other = 'TERM_SESSION_ID'; Platform = 'MacOS'; Kind = 'Kitty' }
        ) {
            $table = @{ TERM_PROGRAM = $Program; TERM = 'xterm-256color' }
            $table[$Marker] = '1'
            $table[$Other]  = '0'
            Get-TerminalKind -EnvTable $table -Platform $Platform | Should -BeExactly $Kind
        }

        It 'rejects a misspelled seam instead of reading the live platform' {
            # Advanced on purpose. A plain function takes -Platfrom into $args
            # and answers for whichever machine runs it.
            { Get-TerminalKind -EnvTable @{} -Platfrom 'Linux' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'reads the live environment when no -EnvTable is supplied' {
            # Whatever is hosting the test run, the result must be one of the
            # known kinds -- never $null or an empty string.
            $kind = Get-TerminalKind
            $kind | Should -Not -BeNullOrEmpty
            @('WindowsTerminal','AppleTerminal','ITerm2','Ghostty','WezTerm',
              'Kitty','Alacritty','VSCode','Unknown') | Should -Contain $kind
        }
    }
}
