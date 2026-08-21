# RAIN prompt -- zsh and bash.
#
# Ported from styles/rain/profile.ps1; the two are meant to look the same,
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
Mist=$(ts_raw '200;197;220')   pMist=$(ts_c '200;197;220')
Moss=$(ts_raw '200;184;80')    pMoss=$(ts_c '200;184;80')
Slate=$(ts_raw '156;160;204')  pSlate=$(ts_c '156;160;204')
X=$(ts_rawx)                   pX=$(ts_x)

ts_title 'RAIN // HIGHLAND'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${Slate}+--------------------------------------------+${X}"
printf '%s\n' "${Slate}|  ${Mist}FIELD JOURNAL // ${Moss}DAY 47${Mist}                   ${Slate}|${X}"
printf '%s\n' "${Slate}|  ${Mist}WEATHER: ${Moss}STEADY RAIN${Mist}  ::  CEILING: ${Moss}40m${Mist}    ${Slate}|${X}"
printf '%s\n' "${Slate}|  ${Mist}STILL NO SIGN OF THE OTHERS.              ${Slate}|${X}"
printf '%s\n' "${Slate}+--------------------------------------------+${X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pSlate}[TRAVELER${pMoss} // RAIN${pSlate}]${pX} ${pSlate}[LOC: ${pMist}{CWD}${pSlate}]${pX}{NL}${pSlate}>${pX} ")"
