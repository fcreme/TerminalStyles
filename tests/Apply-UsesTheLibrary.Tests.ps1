# Pester 5 tests: apply.ps1 must USE the library, not carry a copy of it.
#
# These replace the old "parity" tests, which asserted that apply.ps1's forked
# copies of Remove-JsonComment / ConvertFrom-WTJson / Write-WTSettingsFile /
# Find-SettingsPath still behaved like the module's. Parity tests can only ever
# catch drift in the functions someone remembered to write one for -- and the two
# that actually drifted had none:
#
#   Merge-ThemeIntoEntry stripped the background fields whenever no background
#   resolved, with no ownership check, deleting a background the USER had set
#   (their own image, or Windows Terminal's desktopWallpaper). The module leaves
#   those alone, and tests/Background-Carryover.Tests.ps1 pins that -- for the
#   module only.
#
#   Get-StyleBundledBackground was the pre-0.2.0 shape, writing fetched images
#   and the .no-background marker into the STYLE directory instead of the data
#   root's cache, and swallowing the failure. apply.ps1 ships to PSGallery, where
#   that directory belongs to the installed module. It also wrote the old undated
#   marker format, which 0.8.6 reads as expired.
#
# So the invariant worth testing is the one that makes drift impossible rather
# than merely detectable: there is one implementation, and apply.ps1 calls it.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:repoRoot  = Split-Path $PSScriptRoot -Parent
    $script:applyPath = Join-Path $script:repoRoot 'apply.ps1'
    $script:applyAst  = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:applyPath, [ref]$null, [ref]$null)

    $script:applyFunctions = @($script:applyAst.FindAll({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | ForEach-Object { $_.Name })
}

Describe 'apply.ps1 dot-sources the library' {

    It 'dot-sources tstyles.ps1' {
        $src = [System.IO.File]::ReadAllText($script:applyPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match "\.\s+\(Join-Path\s+\`$PSScriptRoot\s+'tstyles\.ps1'\)"
    }

    It 'suppresses the shell-startup auto-load while doing so' {
        # Without this, loading the library re-emits the CURRENTLY applied
        # style's palette -- repainting the terminal with the old style moments
        # before apply.ps1 applies the new one.
        $src = [System.IO.File]::ReadAllText($script:applyPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match '\$TStylesNoAutoLoad\s*=\s*\$true'
    }

    It 'the auto-load block actually honours that flag' {
        $tstyles = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'tstyles.ps1'), [System.Text.UTF8Encoding]::new($false))
        $tstyles | Should -Match '-not\s+\$TStylesNoAutoLoad\s+-and\s+\(Test-StyledHost\)'
    }
}

Describe 'apply.ps1 defines no copy of a library function' {

    # Every one of these lived in apply.ps1 as a fork with a "keep in sync"
    # comment. Redefining any of them here would shadow the real one for the
    # whole script, which is exactly how the two silent data-loss bugs happened.
    $forked = @(
        'Remove-JsonComment'
        'Remove-JsonTrailingComma'
        'ConvertFrom-WTJson'
        'Get-AvailableStyles'
        'Get-StyleBundledBackground'
        'Merge-ThemeIntoEntry'
        'Merge-StyleIntoSettings'
        'Write-WTSettingsFile'
        'Write-SettingsFile'
        'Write-SettingsAtomic'
        'Find-SettingsPath'
        'Find-WTSettingsPath'
    )

    It "does not define <_>" -ForEach $forked {
        $script:applyFunctions | Should -Not -Contain $_
    }

    It 'keeps only its own interactive helper' {
        # Read-Choice is apply.ps1's own console prompt -- genuinely local, since
        # the module's picker is a full-screen arrow-key UI instead.
        $script:applyFunctions | Should -Be @('Read-Choice')
    }
}

Describe 'apply.ps1 routes the merge through the module' {

    It 'calls Merge-StyleIntoSettings' {
        $calls = @($script:applyAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.CommandAst]
        }, $true) | ForEach-Object { $_.GetCommandName() })
        $calls | Should -Contain 'Merge-StyleIntoSettings'
        $calls | Should -Contain 'Write-SettingsFile'
    }

    It 'passes the ownership flag the merge needs to protect a user background' {
        # -BackgroundImageProvided $false is what tells the merge "work it out
        # from the style", which is the branch that consults
        # Test-ManagedBackgroundPath and leaves a user-set image alone. Passing
        # $true unconditionally would reproduce the old fork's behaviour through
        # the new call.
        $src = [System.IO.File]::ReadAllText($script:applyPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match '-BackgroundImageProvided\s+\$bgProvided'
        $src | Should -Match '\$bgProvided\s*=\s*\$PSBoundParameters\.ContainsKey\('
    }

    It 'writes current-style.ps1 where the module reads it from' {
        # It used to write beside the script, which only coincides with the data
        # root for bootstrap installs; on PSGallery the module looked elsewhere.
        $src = [System.IO.File]::ReadAllText($script:applyPath, [System.Text.UTF8Encoding]::new($false))
        $src | Should -Match '\$currentStyleDest\s*=\s*\$script:TStylesCurrent'
        $src | Should -Not -Match "Join-Path\s+\`$repoRoot\s+'current-style\.ps1'"
    }
}

Describe 'apply.ps1 still loads standalone' {

    It 'dot-sources for its functions without running the installer' {
        # The $TStylesApplyNoRun seam has to survive the de-fork: it is how the
        # tests load this file at all.
        {
            $TStylesApplyNoRun = $true
            . $script:applyPath
        } | Should -Not -Throw
    }

    It 'brings the library functions into scope through the dot-source' {
        $TStylesApplyNoRun = $true
        . $script:applyPath
        Get-Command Merge-StyleIntoSettings -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command ConvertFrom-WTJson      -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Find-WTSettingsPath     -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
