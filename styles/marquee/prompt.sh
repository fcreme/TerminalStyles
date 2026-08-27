# MARQUEE prompt -- zsh and bash.
#
# Ported from styles/marquee/profile.ps1; the two are meant to look the same,
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
_ts_B=$(ts_raw '64;144;240')       pB=$(ts_c '64;144;240')
_ts_D=$(ts_raw '90;40;72')
_ts_M=$(ts_raw '255;64;144')       pM=$(ts_c '255;64;144')
_ts_W=$(ts_raw '240;200;216')
_ts_X=$(ts_rawx)                   pX=$(ts_x)
_ts_Y=$(ts_raw '240;208;64')       pY=$(ts_c '240;208;64')

ts_title 'MARQUEE // EXT3'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_M}>>> MARQUEE // EXT3 <<<${_ts_W}                     ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_Y}NIGHT GALLERY${_ts_W}  ::  ${_ts_B}SIGNAL: STRONG${_ts_W}           ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}|  ${_ts_M}\"Through the glass, after hours.\"${_ts_W}           ${_ts_D}|${_ts_X}"
printf '%s\n' "${_ts_D}+----------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pM}[MARQUEE${pY} // EXT3${pM}]${pX} ${pM}[${pB}{CWD}${pM}]${pX}{NL}${pM}>${pX} ")"
