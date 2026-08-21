# EX-MACHINA prompt -- zsh and bash.
#
# Ported from styles/ex-machina/profile.ps1; the two are meant to look the same,
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
C=$(ts_raw '0;204;255')        pC=$(ts_c '0;204;255')
P=$(ts_raw '255;123;138')      pP=$(ts_c '255;123;138')
W=$(ts_raw '184;240;255')      pW=$(ts_c '184;240;255')
X=$(ts_rawx)                   pX=$(ts_x)

ts_title 'EX MACHINA // BLUEBOOK'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${C}+----------------------------------------------+${X}"
printf '%s\n' "${C}|  ${W}BLUEBOOK RESEARCH // SESSION 06 -- ACTIVE   ${C}|${X}"
printf '%s\n' "${C}|  ${W}SUBJECT: ${P}AVA${W}   ::  PROTOCOL: TURING TEST    ${C}|${X}"
printf '%s\n' "${C}|  ${W}STATUS: CONSCIOUS  ::  TRUST: ${P}??${W}            ${C}|${X}"
printf '%s\n' "${C}+----------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pP}[AVA${pC} // BLUEBOOK${pP}]${pX} ${pC}[LOC: ${pW}{CWD}${pC}]${pX}{NL}${pC}>${pX} ")"
