# scripts/review-submission.ps1
#
# The maintainer's half of `tstyles submit`. Run from a clone of
# fcreme/TerminalStyles with `gh` signed in:
#
#   pwsh scripts/review-submission.ps1 -Issue 170              # report only
#   pwsh scripts/review-submission.ps1 -Issue 170 -Accept      # open the two PRs
#   pwsh scripts/review-submission.ps1 -Issue 170 -Reject -Reason "Too close to eva."
#
# Nothing from the submission is ever run. The zip is unpacked under caps,
# only flat files on the allow-list are taken, the checks only parse JSON and
# compare bytes, and the prompt files are printed with control characters
# made visible. Approval is merging the PRs -Accept opens: one adds
# styles/<name>/ to main, the other the image to the gifs branch.
#
# Dot-sourcing this file defines its functions without running anything;
# tests/Review-Submission.Tests.ps1 drives them that way.

[CmdletBinding()]
param(
    [int]$Issue,
    [switch]$Accept,
    [switch]$Reject,
    [string]$Reason,
    [switch]$Yes
)

$script:ReviewRepo = 'fcreme/TerminalStyles'
$script:ReviewMaxEntries = 16
$script:ReviewMaxBytes = 4MB
$script:ReviewMaxDownload = 8MB

function Get-SubmissionZipLinks {
    # Every attachment link to a .zip in an issue body. GitHub writes a
    # dropped file as [name.zip](https://github.com/user-attachments/files/<id>/name.zip);
    # older uploads live under /<owner>/<repo>/files/<id>/.
    param([AllowEmptyString()][string]$Body)
    $rx = 'https://github\.com/(?:user-attachments/files|[A-Za-z0-9-]+/[A-Za-z0-9._-]+/files)/\d+/[^\s\)\]<>"]+?\.zip'
    @([regex]::Matches($Body, $rx) | ForEach-Object Value | Select-Object -Unique)
}

function Test-SubmissionEntryName {
    # Is a zip entry name one file the review takes? Flat (no folder part),
    # one of the style's files, submission.json, or background.<ext>.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$EntryName, [Parameter(Mandatory)][string[]]$Allowed,
          [Parameter(Mandatory)][string[]]$ImageExtensions)
    if ($EntryName -match '[\\/:]' -or $EntryName -eq '' -or $EntryName.StartsWith('.')) { return $false }
    if ($Allowed -ccontains $EntryName -or $EntryName -ceq 'submission.json') { return $true }
    $m = [regex]::Match($EntryName, '^background\.([a-z]+)$')
    $m.Success -and ($ImageExtensions -ccontains $m.Groups[1].Value)
}

function Expand-SubmissionZip {
    <#
    .SYNOPSIS
    Unpacks a submission zip into an empty folder, or refuses.

    .DESCRIPTION
    Returns @{ Status = 'expanded' | 'refused'; Reason }. Refused: more than
    $MaxEntries entries, an entry whose name is not one flat allowed file
    (Test-SubmissionEntryName), a name twice, or more than $MaxBytes in all.
    The size is counted while copying, not taken from the entry headers,
    which the zip's author wrote. On refusal nothing is left in -Destination.
    #>
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][string[]]$ImageExtensions,
        [int]$MaxEntries = $script:ReviewMaxEntries,
        [long]$MaxBytes = $script:ReviewMaxBytes
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $refuse = { param($why)
        Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        [pscustomobject]@{ Status = 'refused'; Reason = $why }
    }
    if (-not [System.IO.Directory]::Exists($Destination)) { [void][System.IO.Directory]::CreateDirectory($Destination) }
    $zip = $null
    try {
        try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath) }
        catch { return (& $refuse "it is not a zip file ($($_.Exception.Message))") }
        $entries = @($zip.Entries)
        if ($entries.Count -gt $MaxEntries) { return (& $refuse "it holds $($entries.Count) entries; a style is at most $MaxEntries") }
        $seen = @{}
        foreach ($e in $entries) {
            if (-not (Test-SubmissionEntryName -EntryName $e.FullName -Allowed $Allowed -ImageExtensions $ImageExtensions)) {
                return (& $refuse "it holds '$($e.FullName)', which is not a file a style holds")
            }
            if ($seen.ContainsKey($e.FullName.ToLowerInvariant())) { return (& $refuse "it holds '$($e.FullName)' twice") }
            $seen[$e.FullName.ToLowerInvariant()] = $true
        }
        $total = [long]0
        $buf = New-Object byte[] 65536
        foreach ($e in $entries) {
            $in = $e.Open()
            try {
                $out = [System.IO.File]::Open((Join-Path $Destination $e.FullName), [System.IO.FileMode]::CreateNew)
                try {
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                        $total += $n
                        if ($total -gt $MaxBytes) { break }
                        $out.Write($buf, 0, $n)
                    }
                } finally { $out.Dispose() }
            } finally { $in.Dispose() }
            if ($total -gt $MaxBytes) { return (& $refuse "it unpacks to more than $([int]($MaxBytes / 1MB)) MB") }
        }
        return [pscustomobject]@{ Status = 'expanded'; Reason = $null }
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function ConvertTo-VisibleText {
    # Text from a submission, safe to print: every control character but
    # newline and tab is shown as \xNN, so an escape sequence in a prompt
    # file is read, not obeyed by the maintainer's terminal; and every
    # invisible format character (\p{Cf}: bidi overrides, zero-width
    # characters) as \uNNNN, so code cannot display as something other
    # than what it runs.
    param([AllowEmptyString()][string]$Text)
    [regex]::Replace($Text, '[\x00-\x08\x0B-\x1F\x7F\u0080-\u009F]|\p{Cf}', {
        param($m)
        $c = [int][char]$m.Value
        if ($c -le 0xFF) { '\x{0:x2}' -f $c } else { '\u{0:x4}' -f $c }
    })
}

function New-SubmissionReadme {
    # README.md for a submitted style that brings none: what it is, who
    # sent it, and an Includes list naming exactly the files it ships, as
    # Style-README-Accuracy.Tests.ps1 requires. No #rrggbb in it: that test
    # would hold any quoted colour to the scheme.
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Description,
        [Parameter(Mandatory)][string]$Author,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string[]]$Files,
        [string]$ImageFile,
        [AllowEmptyString()][string]$ImageSource = '',
        [string]$PromptVerdict = 'hand-written'
    )
    $what = @{
        'scheme.json' = 'the colour scheme.'
        'theme.json'  = 'font, cursor, padding and background settings.'
        'profile.ps1' = 'the PowerShell prompt and tab title.'
        'prompt.sh'   = 'the same prompt for zsh and bash.'
        'meta.json'   = 'the one-line description `tstyles` shows when you pick it.'
    }
    if ($PromptVerdict -eq 'generated') {
        $what['profile.ps1'] = 'the PowerShell prompt and tab title, generated by `tstyles create`.'
        $what['prompt.sh'] = 'the same prompt for zsh and bash, generated by `tstyles create`.'
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $Name")
    $lines.Add('')
    if ($Description) { $lines.Add($Description); $lines.Add('') }
    $lines.Add("Submitted by [$Author](https://github.com/$Author) in #$IssueNumber.")
    $lines.Add('')
    $lines.Add('## Includes')
    $lines.Add('')
    foreach ($f in 'scheme.json', 'theme.json', 'profile.ps1', 'prompt.sh', 'meta.json') {
        if ($Files -contains $f) { $lines.Add("- **$f** - $($what[$f])") }
    }
    if ($ImageFile) {
        $src = if ($ImageSource) { " Source: $ImageSource." } else { '' }
        $lines.Add("- **$ImageFile** - the background image.$src")
        $lines.Add('  Not in this folder: background images live flat-named on the')
        $lines.Add('  [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are')
        $lines.Add('  fetched into your cache on first use, so `main` stays binary-free.')
    }
    ($lines -join "`n") + "`n"
}

function Invoke-ReviewGh {
    # gh, with its output as text; throws with gh's own message on failure.
    $out = & gh @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh $($args -join ' ') failed: $($out -join ' ')" }
    ($out | ForEach-Object { "$_" }) -join "`n"
}

function Invoke-ReviewGit {
    param([Parameter(Mandatory)][string]$Repo)
    $rest = @($args)
    $out = & git -C $Repo @rest 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($rest -join ' ') failed: $($out -join ' ')" }
    ($out | ForEach-Object { "$_" }) -join "`n"
}

function Invoke-SubmissionReview {
    param([int]$Issue, [switch]$Accept, [switch]$Reject, [string]$Reason, [switch]$Yes)
    $ErrorActionPreference = 'Stop'
    $repoRoot = Split-Path $PSScriptRoot -Parent

    if ($Issue -le 0) { throw 'Give the submission issue: -Issue <number>.' }
    if ($Accept -and $Reject) { throw 'Choose -Accept or -Reject, not both.' }
    if ($Reject -and -not $Reason) { throw '-Reject needs -Reason: the submitter is owed one.' }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'This script needs the GitHub CLI (gh), signed in.' }

    $remote = Invoke-ReviewGit -Repo $repoRoot remote get-url origin
    if ($remote -notmatch 'github\.com[:/]fcreme/TerminalStyles(\.git)?$') {
        throw "Run this from a clone of $($script:ReviewRepo) (origin is $remote)."
    }

    $issueJson = Invoke-ReviewGh issue view $Issue -R $script:ReviewRepo --json 'number,title,body,state,author,url'
    $info = $issueJson | ConvertFrom-Json
    Write-Host "Issue #$($info.number): $(ConvertTo-VisibleText ([string]$info.title))  ($($info.state), by $($info.author.login))"
    Write-Host "  $($info.url)"

    if ($Reject) {
        Write-Host "Commenting the reason and closing #$Issue as not planned."
        $body = "Thanks for the submission. It is not joining the catalogue: $Reason`n`nIt keeps working as your own style."
        Invoke-ReviewGh issue close $Issue -R $script:ReviewRepo --reason 'not planned' --comment $body | Out-Null
        Write-Host 'Closed.'
        return
    }
    if ($info.state -ne 'OPEN') { throw "#$Issue is $($info.state); only an open submission is reviewed." }

    $links = @(Get-SubmissionZipLinks -Body ([string]$info.body))
    if ($links.Count -ne 1) { throw "#$Issue has $($links.Count) zip attachments; a submission has exactly one." }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('tstyles-review-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($work)
    try {
        $zipPath = Join-Path $work 'submission.zip'
        Write-Host "Downloading $(ConvertTo-VisibleText $links[0])"
        Invoke-WebRequest -Uri $links[0] -OutFile $zipPath -UseBasicParsing -MaximumRedirection 5 | Out-Null
        if ((New-Object System.IO.FileInfo $zipPath).Length -gt $script:ReviewMaxDownload) {
            throw "The attachment is over $([int]($script:ReviewMaxDownload / 1MB)) MB; a style is far smaller."
        }

        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $mod = Get-Module TerminalStyles
        $allowed = @(& $mod { Get-StyleSubmissionFileNames })
        $exts = @(& $mod { Get-BackgroundImageExtensions })

        $unpacked = Join-Path $work 'unpacked'
        $x = Expand-SubmissionZip -ZipPath $zipPath -Destination $unpacked -Allowed $allowed -ImageExtensions $exts
        if ($x.Status -ne 'expanded') { throw "Refusing the zip: $($x.Reason)." }

        $record = $null
        $recordPath = Join-Path $unpacked 'submission.json'
        if ([System.IO.File]::Exists($recordPath)) {
            try { $record = [System.IO.File]::ReadAllText($recordPath) | ConvertFrom-Json } catch { $record = $null }
        }
        if (-not $record) { throw 'The zip has no readable submission.json; it was not made by tstyles submit.' }
        $name = [string]$record.name
        if (-not (& $mod { param($n) Test-StyleNameValid -Name $n } $name)) { throw "submission.json names '$name', which is not a usable style name." }
        [System.IO.File]::Delete($recordPath)

        # Under its own parent, so no style name can land on the work
        # folder's other entries (the zip, the worktrees).
        $styleDir = Join-Path (Join-Path $work 'style') $name
        [void][System.IO.Directory]::CreateDirectory((Split-Path $styleDir -Parent))
        [System.IO.Directory]::Move($unpacked, $styleDir)
        $problems = @(& $mod { param($d, $c) Get-StyleSubmissionProblems -StyleDir $d -CatalogueRoot $c } $styleDir (Join-Path $repoRoot 'styles'))
        $verdict = & $mod { param($d) Test-StylePromptIsGenerated -StyleDir $d } $styleDir
        $image = & $mod { param($d) Get-BackgroundFileIn -Directory $d } $styleDir
        # The description the picker will show, from the meta.json the checks
        # just held to one short line -- not submission.json's copy, which
        # nothing checks.
        $description = [string](& $mod { param($d) (Get-StyleMeta -StyleDir $d).Description } $styleDir)

        Write-Host ''
        Write-Host "Style '$name'  (sent with TerminalStyles $(ConvertTo-VisibleText ([string]$record.moduleVersion)))"
        Write-Host "  Description:  $(ConvertTo-VisibleText $description)"
        if ($image) {
            $kb = [int]((New-Object System.IO.FileInfo $image).Length / 1KB)
            Write-Host "  Image:        $([System.IO.Path]::GetFileName($image)), $kb KB"
            Write-Host "  Image source: $(ConvertTo-VisibleText ([string]$record.imageSource))"
            Write-Host "  Rights:       $(if ($record.imageRightsConfirmed -eq $true) { 'confirmed by the submitter' } else { 'NOT confirmed' })"
        } else {
            Write-Host '  Image:        none'
        }
        if ($problems.Count) {
            Write-Host '  Problems:' -ForegroundColor Yellow
            foreach ($p in $problems) { Write-Host "    - $p" }
        } else {
            Write-Host '  Problems:     none' -ForegroundColor Green
        }
        # theme.json goes into every Windows Terminal profile the style is
        # applied to, so it is always shown, whatever the checks said.
        $themePath = Join-Path $styleDir 'theme.json'
        if ([System.IO.File]::Exists($themePath)) {
            Write-Host '  ----- theme.json -----'
            Write-Host (ConvertTo-VisibleText ([System.IO.File]::ReadAllText($themePath)))
            Write-Host '  -----'
        }
        switch ($verdict) {
            'generated'    { Write-Host '  Prompt:       generated by tstyles create; no hand-written code.' -ForegroundColor Green }
            'none'         { Write-Host '  Prompt:       none.' }
            default {
                Write-Host '  Prompt:       HAND-WRITTEN. Read both files before accepting:' -ForegroundColor Yellow
                foreach ($f in 'profile.ps1', 'prompt.sh') {
                    $path = Join-Path $styleDir $f
                    if (-not [System.IO.File]::Exists($path)) { continue }
                    Write-Host "  ----- $f -----"
                    Write-Host (ConvertTo-VisibleText ([System.IO.File]::ReadAllText($path)))
                }
                Write-Host '  -----'
            }
        }

        if (-not $Accept) {
            Write-Host ''
            Write-Host "To accept: -Accept. To turn it down: -Reject -Reason '<why>'."
            return
        }
        if ($problems.Count) { throw 'Not accepting a submission with problems; ask the submitter to fix them.' }
        if ($image -and $record.imageRightsConfirmed -ne $true) { throw 'Not accepting an image whose rights were not confirmed.' }

        $codeBranch = "style/$name"
        $imageBranch = "style/$name-image"
        Invoke-ReviewGit -Repo $repoRoot fetch -q origin main gifs | Out-Null
        foreach ($b in $codeBranch, $imageBranch) {
            $exists = & git -C $repoRoot ls-remote --heads origin $b
            if ($exists) { throw "origin already has a branch $b; delete it or finish that review first." }
        }

        $author = [string]$info.author.login
        $files = @(Get-ChildItem -LiteralPath $styleDir -File | ForEach-Object Name)
        $codeWt = Join-Path $work 'wt-main'
        Invoke-ReviewGit -Repo $repoRoot worktree add -q -b $codeBranch $codeWt origin/main | Out-Null
        $imageWt = $null
        $pushed = $false
        try {
            $dest = Join-Path $codeWt "styles/$name"
            [void][System.IO.Directory]::CreateDirectory($dest)
            foreach ($f in $files) {
                if ($image -and $f -eq [System.IO.Path]::GetFileName($image)) { continue }
                Copy-Item -LiteralPath (Join-Path $styleDir $f) -Destination $dest
            }
            # The zip never carries a README (Get-StyleSubmissionFileNames);
            # this one's Includes list is built from the folder itself.
            $imgLeaf = if ($image) { [System.IO.Path]::GetFileName($image) } else { $null }
            $source = ConvertTo-VisibleText (([string]$record.imageSource) -replace '[\r\n#]', ' ')
            $readme = New-SubmissionReadme -Name $name -Description $description -Author $author `
                -IssueNumber $Issue -Files $files -ImageFile $imgLeaf -ImageSource $source -PromptVerdict $verdict
            [System.IO.File]::WriteAllText((Join-Path $dest 'README.md'), $readme, [System.Text.UTF8Encoding]::new($false))
            Invoke-ReviewGit -Repo $codeWt add -A | Out-Null
            Invoke-ReviewGit -Repo $codeWt commit -q -m "Add style $name (#$Issue)" | Out-Null

            if ($image) {
                $imageWt = Join-Path $work 'wt-gifs'
                Invoke-ReviewGit -Repo $repoRoot worktree add -q -b $imageBranch $imageWt origin/gifs | Out-Null
                $ext = [System.IO.Path]::GetExtension($image)
                Copy-Item -LiteralPath $image -Destination (Join-Path $imageWt "$name$ext")
                Invoke-ReviewGit -Repo $imageWt add -A | Out-Null
                Invoke-ReviewGit -Repo $imageWt commit -q -m "Add background for $name (#$Issue)" | Out-Null
            }

            Write-Host ''
            Write-Host 'About to:'
            Write-Host "  push $codeBranch and open a PR into main adding styles/$name/"
            if ($image) { Write-Host "  push $imageBranch and open a PR into gifs adding $name$([System.IO.Path]::GetExtension($image))" }
            Write-Host "  comment on #$Issue with the PR links"
            if (-not $Yes) {
                $go = Read-Host 'Go ahead? [y/N]'
                if ("$go" -notmatch '^(y|yes)$') { Write-Host 'Stopped. Nothing was pushed.'; return }
            }

            $pushed = $true
            Invoke-ReviewGit -Repo $codeWt push -q -u origin $codeBranch | Out-Null
            $codeBody = "Adds the style submitted in #$Issue by $author.`n`nPrompt: $verdict.`n`nCI fails until these are done by hand on this branch: the style in docs/index.html (STYLES and IMG), the theme counts in README.md, docs/index.html and the wiki, an entry in docs/wiki/Styles.md, and a screenshot."
            $codePr = Invoke-ReviewGh pr create -R $script:ReviewRepo --base main --head $codeBranch --title "Add style $name" --body $codeBody
            $prs = @($codePr)
            if ($image) {
                Invoke-ReviewGit -Repo $imageWt push -q -u origin $imageBranch | Out-Null
                $imagePr = Invoke-ReviewGh pr create -R $script:ReviewRepo --base gifs --head $imageBranch --title "Add background for $name" --body "The image for the style in #$Issue. Merge together with $codePr."
                $prs += $imagePr
            }
            Invoke-ReviewGh issue comment $Issue -R $script:ReviewRepo --body ("Thanks! This is accepted, and being added in:`n" + (($prs | ForEach-Object { "- $_" }) -join "`n") + "`n`nIt ships in the first release after these are merged.") | Out-Null
            Write-Host ''
            foreach ($u in $prs) { Write-Host "Opened $u" -ForegroundColor Green }
            Write-Host "Merging them is the approval. CI on $codeBranch fails until you add, on that branch: the style in docs/index.html (STYLES and IMG), the theme counts in README.md, docs/index.html and the wiki, an entry in docs/wiki/Styles.md, and a screenshot."
        } finally {
            & git -C $repoRoot worktree remove --force $codeWt 2>$null | Out-Null
            if ($imageWt) { & git -C $repoRoot worktree remove --force $imageWt 2>$null | Out-Null }
            & git -C $repoRoot worktree prune 2>$null | Out-Null
            # Nothing pushed: the local branches were only scaffolding.
            if (-not $pushed) {
                & git -C $repoRoot branch -D $codeBranch 2>$null | Out-Null
                if ($imageWt) { & git -C $repoRoot branch -D $imageBranch 2>$null | Out-Null }
            }
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SubmissionReview -Issue $Issue -Accept:$Accept -Reject:$Reject -Reason $Reason -Yes:$Yes
}
