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
pCyan=$(ts_c '0;119;119')
pGray=$(ts_c '56;56;56')
pGreen=$(ts_c '0;128;0')
pMagenta=$(ts_c '187;0;187')
pX=$(ts_x)
pYellow=$(ts_c '155;150;29')

ts_title 'GITBASH // MINGW64'

# Colors for the " (branch)" segment ts_git_branch appends.
TS_GIT_OPEN=$pMagenta
TS_GIT_CLOSE=$pX

ts_prompt_apply "$(ts_prompt_expand "${pGreen}{USER}@{HOST}${pX} ${pYellow}MINGW64${pX} ${pCyan}{CWD}${pX}{GITBRANCH}{NL}${pGray}\$${pX} ")"
