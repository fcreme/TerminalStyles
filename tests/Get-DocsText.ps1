# The user documentation is README.md plus the pages under docs/wiki/, which
# .github/workflows/wiki.yml publishes to the GitHub wiki. Tests that pin a
# documented claim to the code read it through here, so a section moving
# between the README and a wiki page is still checked wherever it lands.
#
# Pages are joined in a fixed order, each starting on its own line. Every page
# opens with a heading, so a section extracted with a `(?=^#{2,3} )` lookahead
# still ends at the page boundary. Files starting with '_' (the sidebar) are
# navigation, not documentation, and are left out.

function Get-DocsPage {
    param([Parameter(Mandatory)][string]$Root)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [pscustomobject]@{
        Name = 'README.md'
        Text = [System.IO.File]::ReadAllText((Join-Path $Root 'README.md'), $utf8)
    }
    $wiki = Join-Path (Join-Path $Root 'docs') 'wiki'
    $files = @(Get-ChildItem -LiteralPath $wiki -Filter '*.md' -File |
        Where-Object { -not $_.Name.StartsWith('_') } |
        Sort-Object Name)
    foreach ($f in $files) {
        [pscustomobject]@{
            Name = "docs/wiki/$($f.Name)"
            Text = [System.IO.File]::ReadAllText($f.FullName, $utf8)
        }
    }
}

function Get-DocsText {
    param([Parameter(Mandatory)][string]$Root)
    (@(Get-DocsPage -Root $Root) | ForEach-Object { $_.Text.TrimEnd() }) -join "`n`n"
}
