# TerminalStyles module entry. Dot-sources tstyles.ps1 to bring its
# functions and the `tstyles` alias into module scope. The manifest
# (TerminalStyles.psd1) controls what's exported to consumers.
#
# tstyles.ps1 stays unchanged so that apply.ps1 (a standalone script)
# can keep using the same library directly, and so that the existing
# test fixtures stay familiar.

. (Join-Path $PSScriptRoot 'tstyles.ps1')

Export-ModuleMember -Alias tstyles
