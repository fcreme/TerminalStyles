# Pester 5 tests: the wiki's links lead somewhere.
#
# docs/wiki/ is published to the GitHub wiki by .github/workflows/wiki.yml,
# which turns `Page.md` links into the wiki's `Page`. A link only works there if
# the page and the heading it names exist, and a relative link to a repository
# file (`styles/eva`, `CONTRIBUTING.md`) resolves against the wiki and 404s --
# the pages were cut out of the README, where those links were correct. So
# every link in a page is either absolute, a `#anchor` on the same page, or
# `Page.md[#anchor]` naming a page and a heading that are there. The README's
# own links into the wiki are held to the same rule.

BeforeDiscovery {
    $root = Split-Path $PSScriptRoot -Parent
    $script:WikiPages = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs/wiki') -Filter '*.md' -File |
        Sort-Object Name | ForEach-Object { @{ Name = $_.Name } })
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Wiki = Join-Path $script:Root 'docs/wiki'
    $script:Utf8 = [System.Text.UTF8Encoding]::new($false)

    function Read-Doc([string]$Path) { [System.IO.File]::ReadAllText($Path, $script:Utf8) }

    # GitHub's heading anchor: lower case, punctuation dropped (hyphens and
    # underscores kept), each space a hyphen. "Which profile a style lands on
    # (`-Target`)" -> "which-profile-a-style-lands-on--target".
    function Get-Anchor([string]$Heading) {
        (($Heading.ToLowerInvariant() -replace '[^\p{L}\p{Nd} _-]', '') -replace ' ', '-')
    }

    function Get-Anchors([string]$Text) {
        $inFence = $false
        foreach ($line in ($Text -split "`r?`n")) {
            if ($line -match '^```') { $inFence = -not $inFence; continue }
            if (-not $inFence -and $line -match '^#{1,6}\s+(.+?)\s*$') { Get-Anchor $Matches[1] }
        }
    }

    function Get-Links([string]$Text) {
        $noFences = [regex]::Replace($Text, '(?ms)^```.*?^```', '')
        [regex]::Matches($noFences, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value }
    }

    # Returns a reason the link is broken, or nothing.
    function Test-WikiLink([string]$Link, [string]$FromPage) {
        if ($Link -match '^(https?:|mailto:)') { return }
        $page, $anchor = $Link -split '#', 2
        if ($page -eq '') {
            $target = $FromPage
        } elseif ($page -match '^[A-Za-z0-9_-]+\.md$') {
            $target = $page
        } else {
            return "'$Link' is relative to the repository; on the wiki it resolves against the wiki and 404s"
        }
        $path = Join-Path $script:Wiki $target
        if (-not [System.IO.File]::Exists($path)) { return "'$Link' names a page that is not in docs/wiki" }
        if ($anchor -and $anchor -notin @(Get-Anchors (Read-Doc $path))) {
            return "'$Link' names a heading $target does not have"
        }
    }
}

Describe 'docs/wiki/<Name>' -ForEach $script:WikiPages {

    It 'opens with a heading' -Skip:($Name.StartsWith('_')) {
        # tests/Get-DocsText.ps1 joins the pages, and the README tests end a
        # section at the next heading -- which is the next page's first line.
        (Read-Doc (Join-Path $script:Wiki $Name)) | Should -Match '^#{2,3} '
    }

    It 'links only to pages and headings that exist' {
        $text = Read-Doc (Join-Path $script:Wiki $Name)
        $broken = @(Get-Links $text | ForEach-Object { Test-WikiLink $_ $Name } | Where-Object { $_ })
        $broken | Should -BeNullOrEmpty
    }
}

Describe 'every wiki page can be reached' {

    It 'is in the sidebar and on Home' {
        $pages = @(Get-ChildItem -LiteralPath $script:Wiki -Filter '*.md' -File |
            Where-Object { -not $_.Name.StartsWith('_') -and $_.Name -ne 'Home.md' } |
            ForEach-Object { $_.Name })
        $pages.Count | Should -BeGreaterThan 5 -Because 'the scan must actually be finding pages'
        $sidebar = @(Get-Links (Read-Doc (Join-Path $script:Wiki '_Sidebar.md')))
        $homeLinks = @(Get-Links (Read-Doc (Join-Path $script:Wiki 'Home.md')))
        foreach ($p in $pages) {
            $sidebar | Should -Contain $p -Because "$p is a page nobody can find without it"
            $homeLinks | Should -Contain $p -Because "$p is a page nobody can find without it"
        }
    }

    It 'is linked from the README, and the README''s wiki links resolve' {
        $readme = Read-Doc (Join-Path $script:Root 'README.md')
        $prefix = 'https://github.com/fcreme/TerminalStyles/wiki/'
        $linked = @(Get-Links $readme | Where-Object { $_.StartsWith($prefix) } |
            ForEach-Object { $_.Substring($prefix.Length) })
        $broken = @($linked | ForEach-Object {
            $page, $anchor = $_ -split '#', 2
            $local = "$page.md"
            if ($anchor) { $local += "#$anchor" }
            Test-WikiLink $local 'Home.md'
        } | Where-Object { $_ })
        $broken | Should -BeNullOrEmpty

        $pages = @(Get-ChildItem -LiteralPath $script:Wiki -Filter '*.md' -File |
            Where-Object { -not $_.Name.StartsWith('_') -and $_.Name -ne 'Home.md' } |
            ForEach-Object { $_.BaseName })
        foreach ($p in $pages) {
            @($linked | ForEach-Object { ($_ -split '#', 2)[0] }) | Should -Contain $p `
                -Because "the README's documentation list is how a reader finds $p"
        }
    }
}
