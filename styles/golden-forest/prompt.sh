# GOLDEN-FOREST prompt -- zsh and bash.
#
# Ported from styles/golden-forest/profile.ps1; the two are meant to look the same,
# so keep them in sync when either changes.
#
# Sourced by shell/tstyles.sh, which defines ts_c / ts_raw / ts_title /
# ts_prompt_expand / ts_prompt_apply. There is no zsh/bash equivalent of the
# PSReadLine syntax-highlighting block in profile.ps1, so that half of the
# style does not carry over.

ts_title 'GOLDEN FOREST'

ts_prompt_apply "$(ts_prompt_expand "PS {CWD}> ")"
