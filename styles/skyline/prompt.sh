# SKYLINE prompt -- zsh and bash.
#
# Ported from styles/skyline/profile.ps1; the two are meant to look the same,
# so keep them in sync when either changes.
#
# Sourced by shell/tstyles.sh, which defines ts_c / ts_raw / ts_title /
# ts_prompt_expand / ts_prompt_apply. There is no zsh/bash equivalent of the
# PSReadLine block in profile.ps1, so that half of the style does not carry
# over.

# Palette (24-bit ANSI), ts_c-wrapped: in a prompt the non-printing bytes must
# be marked or the shell miscounts the width and redraws over itself.
_ts_sLit=$(ts_c '0;149;255')
_ts_sSign=$(ts_c '66;255;142')
_ts_sDim=$(ts_c '95;107;176')
_ts_sX=$(ts_x)

ts_title 'SKYLINE'

ts_prompt_apply "$(ts_prompt_expand "${_ts_sDim}..${_ts_sX} ${_ts_sLit}{LEAF}${_ts_sX}
${_ts_sSign}|${_ts_sX} ")"
