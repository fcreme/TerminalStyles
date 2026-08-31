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
_ts_C=$(ts_raw '0;204;255')        _ts_pC=$(ts_c '0;204;255')
_ts_P=$(ts_raw '255;123;138')      _ts_pP=$(ts_c '255;123;138')
_ts_W=$(ts_raw '184;240;255')      _ts_pW=$(ts_c '184;240;255')
_ts_X=$(ts_rawx)                   _ts_pX=$(ts_x)

ts_title 'EX MACHINA // BLUEBOOK'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_C}+----------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_C}|  ${_ts_W}BLUEBOOK RESEARCH // SESSION 06 -- ACTIVE   ${_ts_C}|${_ts_X}"
printf '%s\n' "${_ts_C}|  ${_ts_W}SUBJECT: ${_ts_P}AVA${_ts_W}   ::  PROTOCOL: TURING TEST    ${_ts_C}|${_ts_X}"
printf '%s\n' "${_ts_C}|  ${_ts_W}STATUS: CONSCIOUS  ::  TRUST: ${_ts_P}??${_ts_W}            ${_ts_C}|${_ts_X}"
printf '%s\n' "${_ts_C}+----------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${_ts_pP}[AVA${_ts_pC} // BLUEBOOK${_ts_pP}]${_ts_pX} ${_ts_pC}[LOC: ${_ts_pW}{CWD}${_ts_pC}]${_ts_pX}{NL}${_ts_pC}>${_ts_pX} ")"
