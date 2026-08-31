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
_ts_Mist=$(ts_raw '200;197;220')   _ts_pMist=$(ts_c '200;197;220')
_ts_Moss=$(ts_raw '200;184;80')    _ts_pMoss=$(ts_c '200;184;80')
_ts_Slate=$(ts_raw '156;160;204')  _ts_pSlate=$(ts_c '156;160;204')
_ts_X=$(ts_rawx)                   _ts_pX=$(ts_x)

ts_title 'RAIN // HIGHLAND'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_Slate}+--------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_Slate}|  ${_ts_Mist}FIELD JOURNAL // ${_ts_Moss}DAY 47${_ts_Mist}                   ${_ts_Slate}|${_ts_X}"
printf '%s\n' "${_ts_Slate}|  ${_ts_Mist}WEATHER: ${_ts_Moss}STEADY RAIN${_ts_Mist}  ::  CEILING: ${_ts_Moss}40m${_ts_Mist}    ${_ts_Slate}|${_ts_X}"
printf '%s\n' "${_ts_Slate}|  ${_ts_Mist}STILL NO SIGN OF THE OTHERS.              ${_ts_Slate}|${_ts_X}"
printf '%s\n' "${_ts_Slate}+--------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${_ts_pSlate}[TRAVELER${_ts_pMoss} // RAIN${_ts_pSlate}]${_ts_pX} ${_ts_pSlate}[LOC: ${_ts_pMist}{CWD}${_ts_pSlate}]${_ts_pX}{NL}${_ts_pSlate}>${_ts_pX} ")"
