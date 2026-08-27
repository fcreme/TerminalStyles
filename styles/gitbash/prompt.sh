# GITBASH prompt -- zsh and bash.
#
# Ported from styles/gitbash/profile.ps1; the two are meant to look the same,
# so keep them in sync when either changes.
#
# Sourced by shell/tstyles.sh, which defines ts_c / ts_raw / ts_title /
# ts_prompt_expand / ts_prompt_apply. There is no zsh/bash equivalent of the
# PSReadLine syntax-highlighting block in profile.ps1, so that half of the
# style does not carry over.

# Palette (24-bit ANSI). Two forms of each color: the bare escape for the
# banner, which is ordinary output, and a ts_c-wrapped one for the prompt,
# where non-printing bytes must be marked or the shell miscounts the
# prompt width and redraws over it.
_ts_pCyan=$(ts_c '0;119;119')
_ts_pGray=$(ts_c '56;56;56')
_ts_pGreen=$(ts_c '0;128;0')
_ts_pMagenta=$(ts_c '187;0;187')
_ts_pX=$(ts_x)
_ts_pYellow=$(ts_c '155;150;29')

ts_title 'GITBASH // MINGW64'

# Colors for the " (branch)" segment ts_git_branch appends.
TS_GIT_OPEN=$(ts_cs '187;0;187')   # same magenta as pMagenta, but substitution-safe
TS_GIT_CLOSE=$(ts_xs)

ts_prompt_apply "$(ts_prompt_expand "${_ts_pGreen}{USER}@{HOST}${_ts_pX} ${_ts_pYellow}MINGW64${_ts_pX} ${_ts_pCyan}{CWD}${_ts_pX}{GITBRANCH}{NL}${_ts_pGray}\$${_ts_pX} ")"
