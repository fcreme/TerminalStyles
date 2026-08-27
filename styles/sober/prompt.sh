# SOBER prompt -- zsh and bash.
#
# Ported from styles/sober/profile.ps1; the two are meant to look the same,
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
_ts_pTeal=$(ts_c '122;153;153')
_ts_pX=$(ts_x)

ts_title 'SOBER'

ts_prompt_apply "$(ts_prompt_expand "{LEAF} ${_ts_pTeal}\$${_ts_pX} ")"
