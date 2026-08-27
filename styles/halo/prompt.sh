# HALO prompt -- zsh and bash.
#
# Ported from styles/halo/profile.ps1; the two are meant to look the same,
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
pB=$(ts_c '72;104;216')
D=$(ts_raw '90;48;72')
L=$(ts_raw '192;160;240')
O=$(ts_raw '255;104;80')       pO=$(ts_c '255;104;80')
W=$(ts_raw '240;216;192')
X=$(ts_rawx)                   pX=$(ts_x)
Y=$(ts_raw '240;208;64')       pY=$(ts_c '240;208;64')

ts_title 'HALO // EXT3'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' "${D}|  ${O}>>> HALO // EXT3 <<<${W}                        ${D}|${X}"
printf '%s\n' "${D}|  ${Y}NIGHT CHAPEL${W}  ::  ${L}RADIANCE: HIGH${W}            ${D}|${X}"
printf '%s\n' "${D}|  ${O}\"Look up. Look closer.\"${W}                     ${D}|${X}"
printf '%s\n' "${D}+----------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pO}[HALO${pY} // EXT3${pO}]${pX} ${pO}[${pB}{CWD}${pO}]${pX}{NL}${pO}>${pX} ")"
