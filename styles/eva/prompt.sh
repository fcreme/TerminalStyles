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
R=$(ts_raw '255;61;90')        pR=$(ts_c '255;61;90')
W=$(ts_raw '255;232;232')      pW=$(ts_c '255;232;232')
X=$(ts_rawx)                   pX=$(ts_x)
Y=$(ts_raw '232;197;71')       pY=$(ts_c '232;197;71')

ts_title 'EVA // NERV'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${R}+----------------------------------------------+${X}"
printf '%s\n' "${R}|  ${W}NERV // EVA-02 PILOT INTERFACE              ${R}|${X}"
printf '%s\n' "${R}|  ${W}SOHRYU, ASUKA LANGLEY :: SYNC: ${Y}89%${W}          ${R}|${X}"
printf '%s\n' "${R}|  ${Y}ANTA BAKA?${W}                                  ${R}|${X}"
printf '%s\n' "${R}+----------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pR}[PILOT${pY} // EVA-02${pR}]${pX} ${pR}[LOC: ${pW}{CWD}${pR}]${pX}{NL}${pR}>${pX} ")"
