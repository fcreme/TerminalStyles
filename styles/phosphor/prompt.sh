# PHOSPHOR prompt -- zsh and bash.
#
# Ported from styles/phosphor/profile.ps1; the two are meant to look the same,
# so keep them in sync when either changes.
#
# Sourced by shell/tstyles.sh, which defines ts_c / ts_raw / ts_title /
# ts_prompt_expand / ts_prompt_apply. There is no zsh/bash equivalent of the
# PSReadLine block in profile.ps1, so that half of the style does not carry
# over.

# Palette (24-bit ANSI), ts_c-wrapped: in a prompt the non-printing bytes must
# be marked or the shell miscounts the width and redraws over itself.
_ts_pDim=$(ts_c '47;107;58')
_ts_pGlow=$(ts_c '51;255;94')
_ts_pAmber=$(ts_c '255;176;0')
_ts_pX=$(ts_x)

ts_title 'PHOSPHOR'

ts_prompt_apply "$(ts_prompt_expand "${_ts_pDim}[${_ts_pX}${_ts_pGlow}{LEAF}${_ts_pX}${_ts_pDim}]${_ts_pX}${_ts_pAmber}>${_ts_pX} ")"
