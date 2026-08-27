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
D=$(ts_raw '90;88;112')
M=$(ts_raw '208;168;216')      pM=$(ts_c '208;168;216')
P=$(ts_raw '224;144;184')      pP=$(ts_c '224;144;184')
R=$(ts_raw '176;64;80')
W=$(ts_raw '216;212;224')      pW=$(ts_c '216;212;224')
X=$(ts_rawx)                   pX=$(ts_x)

ts_title 'NAVI // PROTOCOL 7'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' "${D}|  ${P}NAVI // PROTOCOL 7${W}                          ${D}|${X}"
printf '%s\n' "${D}|  ${W}COPLAND OS  ::  WIRED CONNECTION ${R}ONLINE${W}     ${D}|${X}"
printf '%s\n' "${D}|  ${M}\"Present day, present time. Hahaha.\"${W}        ${D}|${X}"
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pP}[LAIN${pM} // WIRED${pP}]${pX} ${pP}[${pW}{CWD}${pP}]${pX}{NL}${pP}>${pX} ")"
