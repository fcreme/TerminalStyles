# LAIN prompt -- zsh and bash.
#
# Ported from styles/lain/profile.ps1; the two are meant to look the same,
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
_ts_D=$(ts_raw '90;88;112')
_ts_M=$(ts_raw '208;168;216')      _ts_pM=$(ts_c '208;168;216')
_ts_P=$(ts_raw '224;144;184')      _ts_pP=$(ts_c '224;144;184')
_ts_R=$(ts_raw '176;64;80')
_ts_W=$(ts_raw '216;212;224')      _ts_pW=$(ts_c '216;212;224')
_ts_X=$(ts_rawx)                   _ts_pX=$(ts_x)

ts_title 'NAVI // PROTOCOL 7'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_P}NAVI // PROTOCOL 7${_ts_W}                          ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_W}COPLAND OS  ::  WIRED CONNECTION ${_ts_R}ONLINE${_ts_W}     ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_M}\"Present day, present time. Hahaha.\"${_ts_W}        ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${_ts_pP}[LAIN${_ts_pM} // WIRED${_ts_pP}]${_ts_pX} ${_ts_pP}[${_ts_pW}{CWD}${_ts_pP}]${_ts_pX}{NL}${_ts_pP}>${_ts_pX} ")"
