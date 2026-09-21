# KOHOLINT prompt -- zsh and bash.
#
# Ported from styles/koholint/profile.ps1; the two are meant to look the same,
# so keep them in sync when either changes.
#
# Sourced by shell/tstyles.sh, which defines ts_c / ts_raw / ts_title /
# ts_prompt_expand / ts_prompt_apply. There is no zsh/bash equivalent of the
# PSReadLine block in profile.ps1, so that half of the style does not carry
# over.

# Palette (24-bit ANSI), ts_c-wrapped: in a prompt the non-printing bytes must
# be marked or the shell miscounts the width and redraws over itself.
_ts_kSky=$(ts_c '136;152;248')
_ts_kSea=$(ts_c '120;208;240')
_ts_kHat=$(ts_c '240;248;72')
_ts_kDim=$(ts_c '168;168;208')
_ts_kX=$(ts_x)

ts_title 'KOHOLINT'

ts_prompt_apply "$(ts_prompt_expand "${_ts_kDim}~~~~${_ts_kX} ${_ts_kSea}{LEAF}${_ts_kX}
${_ts_kSky}>${_ts_kX}${_ts_kHat}>${_ts_kX} ")"
