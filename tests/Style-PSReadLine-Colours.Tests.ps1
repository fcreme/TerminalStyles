# Pester 5 tests: every style sets every PSReadLine colour the others set.
#
# PSReadLine colours persist for the session, and switching styles only
# replaces the keys the new style sets. koholint, phosphor and skyline left out
# Keyword, Default and InlinePrediction, so after switching to one of them from
# another style those three colours stayed the old style's. From gitbash, a
# light-background style, plain arguments stayed #383838 on a near-black
# background until a new tab (#127).
#
# Each case runs the style's profile.ps1 in a runspace of its own with
# Set-PSReadLineOption replaced by a recorder (a function outranks the cmdlet),
# and asserts on what it asked PSReadLine to set.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $stylesRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'styles'
    $styleCases = @(Get-ChildItem -LiteralPath $stylesRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'profile.ps1') } |
        Sort-Object Name |
        ForEach-Object { @{ Style = $_.Name; Profile = (Join-Path $_.FullName 'profile.ps1') } })
}

BeforeAll {
    # Every colour the style table can carry. A style that leaves one out
    # inherits it from whatever style ran before it in the session.
    $script:allKeys = @('Command', 'Comment', 'Default', 'Error', 'InlinePrediction', 'Keyword',
                        'Member', 'Number', 'Operator', 'Parameter', 'Selection', 'String', 'Type', 'Variable')

    function script:Get-PSReadLineColorCalls {
        # The -Colors tables a profile.ps1 passes to Set-PSReadLineOption, one
        # entry per call, in order.
        param([string]$Path)
        $ps = [powershell]::Create()
        try {
            [void]$ps.AddScript({
                param($ProfilePath)
                $calls = [System.Collections.Generic.List[object]]::new()
                function Set-PSReadLineOption {
                    [CmdletBinding()]
                    param([hashtable]$Colors, $PredictionSource, $PredictionViewStyle, $EditMode)
                    if ($Colors) { $calls.Add(@($Colors.Keys | ForEach-Object { "$_" })) }
                }
                function Get-Module { [pscustomobject]@{ Name = 'PSReadLine' } }
                function Import-Module { }
                # No try around this: setting $Host.UI.RawUI.WindowTitle throws in
                # a host with no UI, and a try would end the profile right there.
                # Without one, that statement fails on its own and the rest runs.
                . $ProfilePath
                , $calls.ToArray()
            }).AddArgument($Path)
            $out = $ps.Invoke()
            return @($out[0])
        } finally { $ps.Dispose() }
    }
}

Describe 'style profile.ps1 PSReadLine colours' {
    It '<Style> sets every PSReadLine colour' -ForEach $styleCases {
        $calls = Get-PSReadLineColorCalls -Path $Profile
        @($calls).Count | Should -BeGreaterThan 0 -Because "$Style must set PSReadLine colours at all"
        $set = @($calls | ForEach-Object { $_ } | Sort-Object -Unique)
        $missing = @($script:allKeys | Where-Object { $set -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because 'a colour left out stays the previous style''s for the rest of the session'
    }

    It '<Style> sets InlinePrediction in a call of its own' -ForEach $styleCases {
        # Older PSReadLine (Windows PowerShell 5.1's) does not know the key, and
        # an unknown key fails the WHOLE call, so in the main table it would
        # take every other colour down with it there.
        $calls = Get-PSReadLineColorCalls -Path $Profile
        $withInline = @($calls | Where-Object { @($_) -contains 'InlinePrediction' })
        $withInline | Should -Not -BeNullOrEmpty
        foreach ($c in $withInline) {
            @($c) | Should -Be @('InlinePrediction') -Because 'it must not share a call with the other colours'
        }
    }
}
