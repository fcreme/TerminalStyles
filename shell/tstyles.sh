# tstyles.sh -- TerminalStyles runtime for zsh and bash.
#
# Sourced from ~/.zshrc / ~/.bashrc by the loader block that
# `tstyles shell-init` writes. Two jobs:
#
#   1. Re-emit the applied style's colors, so a new tab/window comes up in the
#      style instead of the terminal's own defaults. The colors are an OSC
#      packet written by the PowerShell side at apply time; replaying it here
#      costs one `cat` and no subprocess.
#   2. Source the applied style's prompt (styles/<name>/prompt.sh, staged as
#      current-prompt.sh) and wire it into PS1/PROMPT.
#
# Deliberately does NOT invoke pwsh: this runs on every interactive shell
# start, and paying PowerShell's startup cost there would be felt on every new
# tab. Everything needed is precomputed on disk by the apply.
#
# Portability: POSIX-ish shell, with the two shells' differences isolated in
# ts_c / ts_prompt_apply below. Sourced by both, so no bashisms outside those.

# --- Data root -------------------------------------------------------------
# Mirrors Get-TStylesDataRoot in tstyles.ps1 -- keep in sync.
if [ -z "$TSTYLES_DATA" ]; then
    case "$(uname -s)" in
        Darwin) TSTYLES_DATA="$HOME/Library/Application Support/TerminalStyles" ;;
        *)      TSTYLES_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/TerminalStyles" ;;
    esac
fi

# --- Shell identification --------------------------------------------------
# Set once, so the per-prompt path does no detection work.
if [ -n "$ZSH_VERSION" ]; then
    TS_SHELL='zsh'
elif [ -n "$BASH_VERSION" ]; then
    TS_SHELL='bash'
else
    TS_SHELL='sh'
fi

# --- Color helpers ---------------------------------------------------------
# ts_c <r;g;b>  -> a 24-bit foreground color, wrapped so the shell does not
#                  count it toward the prompt's visible width.
# ts_x          -> reset, likewise wrapped.
#
# The wrapping is not cosmetic. Both shells compute the cursor column from the
# prompt string; an unwrapped escape sequence is counted as printable, so the
# shell thinks the prompt is ~20 columns wider than it is and redraw goes
# wrong -- long command lines wrap early and Ctrl-R / history recall paint over
# the prompt. zsh marks non-printing spans with %{...%}, bash with \[...\].
#
# The ESC byte itself also differs: bash expands \033 (octal) inside PS1, but
# zsh does not expand backslash escapes in PROMPT, so zsh needs a literal ESC.
if [ "$TS_SHELL" = 'zsh' ]; then
    ts_c() { printf '%%{\033[38;2;%sm%%}' "$1"; }
    ts_x() { printf '%%{\033[0m%%}'; }
else
    ts_c() { printf '\\[\\033[38;2;%sm\\]' "$1"; }
    ts_x() { printf '\\[\\033[0m\\]'; }
fi

# ts_raw <r;g;b> / ts_rawx -- unwrapped, for banner text printed with printf.
# A banner is ordinary output, not part of the prompt, so it must NOT carry the
# non-printing markers (they would show up literally).
ts_raw()  { printf '\033[38;2;%sm' "$1"; }
ts_rawx() { printf '\033[0m'; }

# --- Prompt placeholders ---------------------------------------------------
# A style writes its prompt as a template containing {CWD}, {LEAF} and {NL}.
# Those expand to each shell's OWN prompt escapes rather than to a value
# captured at load time, so the prompt tracks the directory without a subshell
# per command -- and, more importantly, without us having to escape whatever
# characters a path happens to contain. A path holding a '%' would otherwise be
# reinterpreted by zsh as a prompt escape, and a '\' by bash.
#
# Substitution uses ${var//from/to} rather than sed: it needs no subprocess (this
# runs on every shell start), and it cannot be confused by the template's own
# punctuation -- several banners and prompts contain '|', which would collide
# with a sed s|…|…| delimiter.
ts_prompt_expand() {
    _ts_tpl="$1"
    if [ "$TS_SHELL" = 'zsh' ]; then
        _ts_cwd='%~'      # full path, ~-abbreviated
        _ts_leaf='%1~'    # last component only
        _ts_user='%n'
        _ts_host='%m'
    else
        _ts_cwd='\w'
        _ts_leaf='\W'
        _ts_user='\u'
        _ts_host='\h'
    fi
    # A literal newline for {NL}: bash expands \n inside PS1, zsh does not, so
    # carrying the real character keeps one template working for both.
    _ts_nl='
'
    _ts_tpl="${_ts_tpl//\{CWD\}/$_ts_cwd}"
    _ts_tpl="${_ts_tpl//\{LEAF\}/$_ts_leaf}"
    _ts_tpl="${_ts_tpl//\{USER\}/$_ts_user}"
    _ts_tpl="${_ts_tpl//\{HOST\}/$_ts_host}"
    _ts_tpl="${_ts_tpl//\{NL\}/$_ts_nl}"
    _ts_tpl="${_ts_tpl//\{GITBRANCH\}/\$(ts_git_branch)}"
    printf '%s' "$_ts_tpl"
}

ts_git_branch() {
    # " (branch)" for a git worktree, empty otherwise. Evaluated fresh on every
    # prompt, so it has to stay cheap and silent: --abbrev-ref is a single
    # rev-parse with no object reads, and all output is discarded on failure so
    # a non-repo directory prints nothing rather than a git error.
    _ts_b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    [ -n "$_ts_b" ] || return 0
    printf ' %s(%s)%s' "$TS_GIT_OPEN" "$_ts_b" "$TS_GIT_CLOSE"
}

ts_prompt_apply() {
    # Install $1 (an already-expanded template) as the shell's prompt.
    if [ "$TS_SHELL" = 'zsh' ]; then
        # PROMPT_SUBST lets $(ts_git_branch) re-run on each prompt; without it
        # zsh would show the command substitution literally. It cannot expand
        # anything from the filesystem: the directory reaches the prompt as the
        # %~ escape, never as interpolated text.
        setopt PROMPT_SUBST
        PROMPT="$1"
    else
        PS1="$1"
    fi
}

ts_title() {
    # OSC 0 sets both the window and tab title. Interactive shells only -- a
    # script writing escape bytes into a redirected stdout would corrupt it.
    case "$-" in *i*) printf '\033]0;%s\007' "$1" ;; esac
}

# --- Startup ---------------------------------------------------------------
ts_load() {
    # Non-interactive shells get nothing: no colors, no prompt, no output. This
    # is what keeps `ssh host command`, scp, and rsync safe -- they break if a
    # shell writes anything unexpected to stdout at startup.
    case "$-" in
        *i*) ;;
        *) return 0 ;;
    esac

    # 1. Colors. The packet was rendered at apply time.
    if [ -r "$TSTYLES_DATA/current-style.osc" ]; then
        cat "$TSTYLES_DATA/current-style.osc"
    fi

    # 2. Prompt + banner.
    if [ -r "$TSTYLES_DATA/current-prompt.sh" ]; then
        . "$TSTYLES_DATA/current-prompt.sh"
    fi
}

# --- The `tstyles` command for non-PowerShell shells ------------------------
# TerminalStyles is a PowerShell module, so the CLI runs in pwsh either way.
# What this wrapper adds is the live reload: the pwsh subprocess shares this
# terminal's tty, so its OSC output retints the window immediately, but a
# prompt it stages can only reach THIS shell if we re-source it afterwards.
# Without that, `tstyles eva` would recolor the window and leave the old prompt
# until the next tab.
tstyles() {
    _ts_exe=''
    for _ts_c in pwsh pwsh-preview; do
        if command -v "$_ts_c" >/dev/null 2>&1; then _ts_exe="$_ts_c"; break; fi
    done
    if [ -z "$_ts_exe" ]; then
        printf 'tstyles: PowerShell not found. Install it with: brew install powershell\n' >&2
        return 127
    fi
    if [ ! -r "$TSTYLES_DATA/tstyles-cli.ps1" ]; then
        printf 'tstyles: not initialised. Run this once from pwsh:  tstyles shell-init\n' >&2
        return 1
    fi

    "$_ts_exe" -NoProfile -File "$TSTYLES_DATA/tstyles-cli.ps1" "$@"
    _ts_rc=$?

    # Re-apply the staged prompt in this shell. Only on success: a failed or
    # unrecognized command has not changed the staged state, and re-sourcing
    # would just repeat the previous style's banner.
    if [ $_ts_rc -eq 0 ] && [ -r "$TSTYLES_DATA/current-prompt.sh" ]; then
        . "$TSTYLES_DATA/current-prompt.sh"
    fi
    return $_ts_rc
}

# Load last, once every helper above and the `tstyles` function exist: a style's
# prompt.sh calls ts_c/ts_title/ts_prompt_apply, so sourcing it any earlier
# would fail on the first style that has a banner.
ts_load
