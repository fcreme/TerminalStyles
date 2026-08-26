# Pester 5 tests: every file under lib/ is loaded, and ships.
#
# The library was one 4,100-line file. Splitting it across lib/ adds exactly one
# new way to break the module, and it is a quiet one: a file that exists in the
# repo, passes every test locally, and is simply absent from the published
# package -- at which point `Import-Module TerminalStyles` fails outright for
# everyone who installs it, while the maintainer's checkout is fine.
#
# Two guards against that, matching the two places a file has to be known:
#   - tstyles.ps1 enumerates lib/*.ps1 rather than listing names, so a new file
#     is dot-sourced without being registered.
#   - scripts/publish.ps1's allowlist has a single 'lib' DIRECTORY entry for the
#     same reason. Get-PublishStagePlan expands it through git ls-files, so an
#     uncommitted file is refused rather than silently dropped.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:LibFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.ps1' |
        ForEach-Object { $_.Name })
}
BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    $script:libDir  = Join-Path $script:repoRoot 'lib'
    $script:tstyles = [System.IO.File]::ReadAllText(
        (Join-Path $script:repoRoot 'tstyles.ps1'), [System.Text.UTF8Encoding]::new($false))
    $script:publish = [System.IO.File]::ReadAllText(
        (Join-Path $script:repoRoot 'scripts/publish.ps1'), [System.Text.UTF8Encoding]::new($false))
}

Describe 'lib/ is loaded by enumeration, not by a hardcoded list' {

    It 'tstyles.ps1 dot-sources every .ps1 it finds under lib' {
        $script:tstyles | Should -Match "Get-ChildItem -LiteralPath \`$script:TStylesLibDir -Filter '\*\.ps1'"
        $script:tstyles | Should -Match '\.\s+\$libFile\.FullName'
    }

    It 'does not name individual lib files, which would be a list to forget' {
        foreach ($f in $script:LibFiles) {
            $script:tstyles | Should -Not -Match ([regex]::Escape("lib/$f")) `
                -Because "$f should be picked up by enumeration, not by name"
        }
    }

    It 'survives lib/ being absent rather than throwing at import' {
        # A partial install, or someone running tstyles.ps1 straight out of a
        # tarball, should get a clear failure later -- not a crash on load.
        $script:tstyles | Should -Match 'if \(Test-Path -LiteralPath \$script:TStylesLibDir\)'
    }
}

Describe 'every lib file actually loaded' {

    It '<_> defines at least one function' -ForEach $script:LibFiles {
        $path = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib') $_
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count |
            Should -BeGreaterThan 0
    }

    It '<_> parses without error' -ForEach $script:LibFiles {
        $path = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib') $_
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }

    It 'every function defined under lib is callable after import' {
        # The point of dot-sourcing rather than nesting a module: one shared
        # scope, so a function that moved out of tstyles.ps1 behaves as it did
        # inside it.
        $missing = @()
        foreach ($f in $script:LibFiles) {
            $path = Join-Path $script:libDir $f
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
            foreach ($fn in $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $found = InModuleScope TerminalStyles -Parameters @{ n = $fn.Name } {
                    param($n) [bool](Get-Command $n -ErrorAction SilentlyContinue)
                }
                if (-not $found) { $missing += "$f :: $($fn.Name)" }
            }
        }
        $missing | Should -BeNullOrEmpty
    }
}

Describe 'lib/ reaches the published package' {

    It "the publish allowlist carries a 'lib' directory entry" {
        # A directory entry, not one line per file: the flat-list form is the
        # thing that would silently ship a module that cannot import.
        $allow = [regex]::Match($script:publish, '(?s)\$allowlist = @\((.*?)\n\)').Groups[1].Value
        $allow | Should -Not -BeNullOrEmpty
        $allow | Should -Match "'lib'"
    }

    It 'the allowlist names no individual lib file' {
        $allow = [regex]::Match($script:publish, '(?s)\$allowlist = @\((.*?)\n\)').Groups[1].Value
        foreach ($f in $script:LibFiles) {
            $allow | Should -Not -Match ([regex]::Escape($f))
        }
    }

    It 'every lib file is tracked by git, or publish would refuse it' {
        # Get-PublishStagePlan expands the allowlist through git ls-files, so an
        # untracked file is not silently dropped -- it stops the publish. Better
        # to find that here than at release time.
        $tracked = @(& git -C $script:repoRoot ls-files 'lib') | ForEach-Object { Split-Path $_ -Leaf }
        foreach ($f in $script:LibFiles) {
            $tracked | Should -Contain $f -Because "$f must be committed to ship"
        }
    }

    It 'uninstall counts lib as install-managed' {
        # A bootstrap uninstall that leaves lib/ behind leaves a half-removed
        # module on disk.
        #
        # InModuleScope because Invoke-TerminalStylesUninstall is not exported --
        # only Invoke-TerminalStyle and Invoke-TerminalStylesUpdate are -- so
        # Get-Command finds nothing out here and .ScriptBlock is $null.
        $items = InModuleScope TerminalStyles {
            $src = (Get-Command Invoke-TerminalStylesUninstall).ScriptBlock.ToString()
            [regex]::Match($src, '(?s)\$installManagedItems = @\((.*?)\)').Groups[1].Value
        }
        $items | Should -Not -BeNullOrEmpty
        $items | Should -Match "'lib'"
    }
}
