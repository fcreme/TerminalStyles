# TOMBRAIDER prompt -- zsh and bash.
#
# Ported from styles/tombraider/profile.ps1; the two are meant to look the same,
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
C=$(ts_raw '64;224;224')       pC=$(ts_c '64;224;224')
D=$(ts_raw '90;40;72')
M=$(ts_raw '255;48;136')       pM=$(ts_c '255;48;136')
W=$(ts_raw '240;200;216')
X=$(ts_rawx)                   pX=$(ts_x)
Y=$(ts_raw '240;208;64')       pY=$(ts_c '240;208;64')

ts_title 'TOMB RAIDER // EXT3'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' "${D}|  ${M}>>> TOMB RAIDER // EXT3 <<<${W}                 ${D}|${X}"
printf '%s\n' "${D}|  ${Y}CROFT INDUSTRIES${W}  ::  ${C}POWER: ONLINE${W}            ${D}|${X}"
printf '%s\n' "${D}|  ${M}\"Press start.\"${W}                              ${D}|${X}"
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pM}[CROFT${pY} // EXT3${pM}]${pX} ${pM}[${pC}{CWD}${pM}]${pX}{NL}${pM}>${pX} ")"
