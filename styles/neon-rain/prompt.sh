# NEON-RAIN prompt -- zsh and bash.
#
# Ported from styles/neon-rain/profile.ps1; the two are meant to look the same,
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
_ts_D=$(ts_raw '90;104;120')
_ts_G=$(ts_raw '94;224;144')       _ts_pG=$(ts_c '94;224;144')
_ts_W=$(ts_raw '216;228;240')      _ts_pW=$(ts_c '216;228;240')
_ts_X=$(ts_rawx)                   _ts_pX=$(ts_x)
_ts_Y=$(ts_raw '240;200;80')       _ts_pY=$(ts_c '240;200;80')

ts_title 'NEON RAIN // DISTRICT-05'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_Y}DISTRICT-05 // NIGHT SECTOR${_ts_W}                 ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_W}RAIN PROTOCOL ACTIVE  ::  STATUS: ${_ts_G}ONLINE${_ts_W}    ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_Y}\"The neon never sleeps.\"${_ts_W}                    ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${_ts_pY}[NEON-RAIN${_ts_pW} // ${_ts_pG}{USER}${_ts_pY}]${_ts_pX} ${_ts_pY}[CWD: ${_ts_pW}{CWD}${_ts_pY}]${_ts_pX}{NL}${_ts_pY}>${_ts_pX} ")"
