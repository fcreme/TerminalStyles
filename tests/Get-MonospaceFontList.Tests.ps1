# Pester 5 tests for Get-MonospaceFontList. Uses the -Installed injection
# param to bypass real System.Drawing font enumeration.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-MonospaceFontList' {
    InModuleScope TerminalStyles {
        It 'returns the allowlist intersected with installed fonts' {
            $installed = @('Consolas','JetBrains Mono','Arial','Times New Roman')
            $list = Get-MonospaceFontList -Current 'Consolas' -Installed $installed -MonospaceNames @()
            $list | Should -Contain 'Consolas'
            $list | Should -Contain 'JetBrains Mono'
            $list | Should -Not -Contain 'Arial'
        }
        It 'puts the current font first and de-duplicates' {
            $installed = @('Consolas','JetBrains Mono')
            $list = Get-MonospaceFontList -Current 'JetBrains Mono' -Installed $installed -MonospaceNames @()
            $list[0] | Should -Be 'JetBrains Mono'
            ($list | Where-Object { $_ -eq 'JetBrains Mono' }).Count | Should -Be 1
        }
        It 'includes a current font that is not on the allowlist' {
            $list = Get-MonospaceFontList -Current 'My Custom Mono' -Installed @('Consolas') -MonospaceNames @()
            $list[0] | Should -Be 'My Custom Mono'
            $list    | Should -Contain 'Consolas'
        }
        It 'falls back to a font that exists on this platform when nothing intersects' {
            # The fallback has to be a font the host actually ships. Consolas is
            # Windows-only -- naming it on a Mac would set the terminal to a
            # family that does not resolve, which renders as the system default
            # and looks like the setting was ignored.
            $expected = switch (Get-TStylesPlatform) {
                'MacOS' { 'Menlo' }
                'Linux' { 'DejaVu Sans Mono' }
                default { 'Consolas' }
            }
            $list = Get-MonospaceFontList -Current '' -Installed @('Arial') -MonospaceNames @()
            $list | Should -Be @($expected)
        }
        It 'includes installed monospace fonts beyond the favorites' {
            $list = Get-MonospaceFontList -Current 'Consolas' `
                -Installed @('Consolas','MonoLisa','Arial') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list | Should -Contain 'MonoLisa'
            $list | Should -Not -Contain 'Arial'
        }
        It 'floats favorites above other monospace fonts, others alphabetical' {
            $list = Get-MonospaceFontList -Current '' `
                -Installed @('Consolas','Aardvark Mono','MonoLisa') `
                -MonospaceNames @('Aardvark Mono','MonoLisa','Consolas')
            $idxFav = [array]::IndexOf($list, 'Consolas')       # a favorite
            $idxA   = [array]::IndexOf($list, 'Aardvark Mono')  # non-favorite
            $idxM   = [array]::IndexOf($list, 'MonoLisa')       # non-favorite
            $idxFav | Should -BeLessThan $idxA
            $idxA   | Should -BeLessThan $idxM   # non-favorites alphabetical
        }
        It 'keeps the current font first even when it is a non-favorite monospace' {
            $list = Get-MonospaceFontList -Current 'MonoLisa' `
                -Installed @('Consolas','MonoLisa') `
                -MonospaceNames @('Consolas','MonoLisa')
            $list[0] | Should -Be 'MonoLisa'
        }
    }
}

Describe 'Get-MonospaceFontList always hands back an array' {
    InModuleScope TerminalStyles {

        # Driven through the -Installed / -MonospaceNames seams the function
        # documents, NOT by mocking Get-InstalledFontFamily. The curated
        # favourites list is platform-dependent -- 'Menlo' is offered on macOS
        # and not on Linux -- so a mock at the lower level made these pass here
        # and fail on the ubuntu CI leg, where the input fell through to the
        # 'DejaVu Sans Mono' fallback. Every name used below is in the BASE
        # favourites list, which is identical on all three platforms.

        It 'returns an array even when exactly one font is installed' {
            # `return @(...)` is not enough: PowerShell unrolls an array on the
            # way to the output stream, so a one-element result reached the
            # caller as a [string]. The tuner's font-face knob then indexed into
            # it per CHARACTER -- the knob read "C", then "a", then "s" -- and a
            # save wrote a one-letter font face into the style's theme.json.
            $f = Get-MonospaceFontList -Installed @('Cascadia Code') -MonospaceNames @()
            ($f -is [array]) | Should -BeTrue -Because 'a scalar string would be indexed per character'
            $f.Count         | Should -Be 1
            $f[0]            | Should -Be 'Cascadia Code'
        }

        It 'indexing it gives whole font names, not characters' {
            $f = Get-MonospaceFontList -Installed @('Cascadia Code') -MonospaceNames @()
            $f[0]             | Should -Not -Be 'C'
            "$($f[0])".Length | Should -BeGreaterThan 1
        }

        It 'still returns an array for the many-font case' {
            $f = Get-MonospaceFontList -Installed @('Cascadia Code','Fira Code','Hack') -MonospaceNames @()
            ($f -is [array]) | Should -BeTrue
            $f.Count         | Should -BeGreaterThan 1
        }

        It 'holds even when the list falls through to the platform default' {
            # A name that is in no curated list and matches no mono/code
            # pattern, so favourites and others are both empty and the platform
            # fallback fires -- a single name, exactly the case that unrolled.
            #
            # NOT -Installed @(): the function guards with `if (-not $Installed)`,
            # and an empty array is falsy there, so it would fall back to
            # enumerating the real machine's fonts instead.
            $f = Get-MonospaceFontList -Installed @('Zzz Proportional Face') -MonospaceNames @()
            ($f -is [array]) | Should -BeTrue
            $f.Count         | Should -Be 1
            "$($f[0])".Length | Should -BeGreaterThan 1
        }

        It 'the tuner wraps the call as well' {
            # Belt and braces: the comma in the function fixes every call site,
            # and the @() at the call site makes the contract visible there.
            $src = (Get-Command Invoke-TerminalStyleTune).ScriptBlock.ToString()
            $src | Should -Match '\$fontList = @\(Get-MonospaceFontList'
        }
    }
}
