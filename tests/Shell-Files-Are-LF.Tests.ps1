# A carriage return is not whitespace to zsh or bash. It becomes part of the
# token, so `case $x in` reads as `in^M` and the file dies where it is sourced:
#
#   tstyles.sh:37: command not found: ^M
#   tstyles.sh:41: parse error near `in^M'
#
# That shipped. publish.yml runs on windows-latest, where actions/checkout
# converts LF to CRLF on the way in, so the package built there carried CRLF
# into every .sh it staged -- and PSGallery 0.8.32 and 0.8.33 broke `tstyles`
# for every zsh and bash user who installed them. The repo was never wrong; the
# checkout was, and nothing looked.
#
# This file is why .gitattributes exists, and it is most meaningful on the two
# WINDOWS legs: without `* text eol=lf` their checkout converts these files and
# this test fails there while passing everywhere else -- which is exactly the
# shape of the bug it is guarding.
#
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # From git, not from a directory walk: what ships is what git tracks, and
    # a walk would also sweep in a contributor's untracked scratch files.
    Push-Location $repoRoot
    try { $tracked = @(& git ls-files 2>$null) } finally { Pop-Location }
    $script:ShellFiles = @(
        $tracked |
        Where-Object { $_ -match '\.(sh|js)$' } |
        ForEach-Object { @{ Rel = $_; Full = (Join-Path $repoRoot $_) } }
    )
}

Describe 'files a POSIX shell reads contain no carriage returns' {

    BeforeAll {
        # Recomputed HERE rather than read from the discovery-time list. A
        # variable set in BeforeDiscovery is not visible at run time, and
        # `@($null).Count` is 1 -- so a vacuity check written against it
        # reported "1 file" for a list it could not see at all, which is the
        # emptiest possible version of the thing it exists to catch.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Push-Location $repoRoot
        try { $tracked = @(& git ls-files 2>$null) } finally { Pop-Location }
        $script:runtimeShellFiles = @($tracked | Where-Object { $_ -match '\.(sh|js)$' })
    }

    It 'found the shell files to check' {
        # A discovery that came back empty would make the whole file pass while
        # checking nothing -- and on a shallow or export checkout, `git ls-files`
        # is exactly the thing that can come back empty.
        @($script:runtimeShellFiles).Count | Should -BeGreaterThan 10 `
            -Because 'the runtime plus one prompt.sh per style is more than ten files'
    }

    It '<Rel> is LF-only' -ForEach $script:ShellFiles {
        # Bytes, not lines: Get-Content strips the terminators that are the
        # whole subject here, so reading this any other way measures nothing.
        $bytes = [System.IO.File]::ReadAllBytes($Full)
        $cr = @($bytes | Where-Object { $_ -eq 13 }).Count
        $cr | Should -Be 0 -Because (
            "zsh reads a CR as part of the token -- `case `$x in` becomes ``in^M`` and " +
            "$Rel stops parsing where it is sourced")
    }
}

Describe '.gitattributes is what keeps them that way' {

    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:attrPath = Join-Path $script:repoRoot '.gitattributes'
    }

    It 'exists' {
        # The test above passes on macOS and Linux whatever git does, because
        # nothing converts there. This file is the only reason it also passes on
        # the Windows legs.
        Test-Path -LiteralPath $script:attrPath | Should -BeTrue
    }

    It 'pins eol=lf for every extension a shell reads' {
        $attrs = [System.IO.File]::ReadAllText($script:attrPath, [System.Text.UTF8Encoding]::new($false))
        foreach ($ext in 'sh', 'js') {
            $attrs | Should -Match "\*\.$ext\s+text\s+eol=lf" `
                -Because "a .$ext file is sourced or executed and cannot carry CRLF"
        }
    }

    It 'covers every tracked shell file, not just the ones that exist today' {
        # A new style adds a prompt.sh, and a rule listing files by name would
        # not cover it. The rule is by extension for that reason; this checks no
        # tracked shell file falls outside the extensions pinned above.
        Push-Location $script:repoRoot
        try { $tracked = @(& git ls-files 2>$null) } finally { Pop-Location }
        $shellish = @($tracked | Where-Object { $_ -match '\.(sh|js|bash|zsh|command)$' })
        @($shellish).Count | Should -BeGreaterThan 10 -Because 'an empty list would pass this vacuously'
        $exts = @($shellish | ForEach-Object { [System.IO.Path]::GetExtension($_).TrimStart('.') } |
                  Sort-Object -Unique)
        foreach ($e in $exts) {
            $e | Should -BeIn @('sh', 'js') -Because "a .$e file is read by a shell and needs a rule too"
        }
    }
}
