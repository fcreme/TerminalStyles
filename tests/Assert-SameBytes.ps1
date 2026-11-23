# Ordinal comparison for escape-sequence packets.
#
# On pwsh 7 the string operators and Should -BeExactly compare by the current
# culture, and under ICU that IGNORES control characters: "]104" -ceq
# "$([char]27)]104" is True, and so is .StartsWith of the same pair. A packet
# assertion written with them checks only the printable characters, so a packet
# that lost its ESC or BEL, or a tmux wrap that never doubled one, still passes.
# These compare the UTF-8 bytes instead.
#
# Dot-source it inside InModuleScope (BeforeAll), so the tests and the
# ParameterFilters there can call it:
#     BeforeAll { . (Join-Path $PSScriptRoot 'Assert-SameBytes.ps1') }

function script:Test-SameBytes {
    # $true when both encode to the same UTF-8 bytes. Untyped on purpose: a
    # [string] parameter turns $null into '', and $null is not ''.
    param($Actual, $Expected)
    if ($null -eq $Actual -or $null -eq $Expected) { return ($null -eq $Actual -and $null -eq $Expected) }
    $a = [System.Text.Encoding]::UTF8.GetBytes([string]$Actual)
    $e = [System.Text.Encoding]::UTF8.GetBytes([string]$Expected)
    if ($a.Length -ne $e.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $e[$i]) { return $false } }
    return $true
}

function script:ConvertTo-VisibleBytes {
    # A packet with every control character spelled out, for a failure message.
    param($Text)
    if ($null -eq $Text) { return '$null' }
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in ([string]$Text).ToCharArray()) {
        $n = [int]$c
        if ($n -eq 27) { [void]$sb.Append('\e') }
        elseif ($n -eq 7) { [void]$sb.Append('\a') }
        elseif ($n -eq 92) { [void]$sb.Append('\\') }
        elseif ($n -lt 32 -or $n -eq 127) { [void]$sb.Append(('\x{0:x2}' -f $n)) }
        else { [void]$sb.Append($c) }
    }
    $sb.ToString()
}

function script:Assert-SameBytes {
    # Throws, with both sides spelled out, unless the two encode to the same bytes.
    param($Actual, $Expected, [string]$Because)
    if (Test-SameBytes -Actual $Actual -Expected $Expected) { return }
    $why = ''
    if ($Because) { $why = ", because $Because" }
    throw ("Expected the bytes of '{0}', but got '{1}'{2}." -f
           (ConvertTo-VisibleBytes $Expected), (ConvertTo-VisibleBytes $Actual), $why)
}
