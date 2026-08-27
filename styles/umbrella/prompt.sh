# UMBRELLA prompt -- zsh and bash.
#
# Ported from styles/umbrella/profile.ps1; the two are meant to look the same,
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
_ts_R=$(ts_raw '180;30;30')        pR=$(ts_c '180;30;30')
_ts_W=$(ts_raw '232;220;200')      pW=$(ts_c '232;220;200')
_ts_X=$(ts_rawx)                   pX=$(ts_x)

ts_title 'UMBRELLA TERMINAL'

# Startup banner.
# printf '%s\n' -- never printf "$line": a banner containing a '%' (eva's
# SYNC readout does) would otherwise be read as a format specifier.
printf '%s\n' ""
printf '%s\n' "${_ts_R}+------------------------------------------+${_ts_X}"
printf '%s\n' "${_ts_R}|  ${_ts_W}UMBRELLA CORP. // OPERATOR TERMINAL     ${_ts_R}|${_ts_X}"
printf '%s\n' "${_ts_R}|  ${_ts_W}CLEARANCE: PERSONAL  ::  STATUS: FINE   ${_ts_R}|${_ts_X}"
printf '%s\n' "${_ts_R}+------------------------------------------+${_ts_X}"
printf '%s\n' ""

ts_prompt_apply "$(ts_prompt_expand "${pR}[UMBRELLA // OPERATOR: ${pW}{USER}${pR}]${pX}{NL}${pR}[CWD: ${pW}{CWD}${pR}]${pX}{NL}${pR}>${pX} ")"
