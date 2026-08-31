# EVA prompt -- zsh and bash.
#
# Ported from styles/eva/profile.ps1; the two are meant to look the same,
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
_ts_R=$(ts_raw '255;61;90')        _ts_pR=$(ts_c '255;61;90')
_ts_W=$(ts_raw '255;232;232')      _ts_pW=$(ts_c '255;232;232')
_ts_X=$(ts_rawx)                   _ts_pX=$(ts_x)
_ts_Y=$(ts_raw '232;197;71')       _ts_pY=$(ts_c '232;197;71')

ts_title 'EVA // NERV'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_R}+----------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_R}|  ${_ts_W}NERV // EVA-02 PILOT INTERFACE              ${_ts_R}|${_ts_X}"
printf '%s\n' "${_ts_R}|  ${_ts_W}SOHRYU, ASUKA LANGLEY :: SYNC: ${_ts_Y}89%${_ts_W}          ${_ts_R}|${_ts_X}"
printf '%s\n' "${_ts_R}|  ${_ts_Y}ANTA BAKA?${_ts_W}                                  ${_ts_R}|${_ts_X}"
printf '%s\n' "${_ts_R}+----------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${_ts_pR}[PILOT${_ts_pY} // EVA-02${_ts_pR}]${_ts_pX} ${_ts_pR}[LOC: ${_ts_pW}{CWD}${_ts_pR}]${_ts_pX}{NL}${_ts_pR}>${_ts_pX} ")"
