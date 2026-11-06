# submit.ps1 -- `tstyles submit`: offering a user style for the catalogue.
#
# The user's half only checks and packs. Nothing here talks to GitHub: the
# command writes a zip, opens the "Style submission" issue form, and says
# what is left to do. The maintainer's half is scripts/review-submission.ps1,
# which reads the same rules from here (Get-StyleSubmissionProblems,
# Test-StylePromptIsGenerated), so the check the user ran and the check the
# maintainer runs are one check.

$script:TStylesSubmitRepo = 'fcreme/TerminalStyles'

function Get-StyleMetaLimits {
    # The picker row's caps on a style's meta.json, in characters. One place:
    # Style-Meta.Tests.ps1 holds the bundled styles to it and the submission
    # check holds a submitted one to it.
    @{ Description = 90; Quote = 70 }
}

function Get-StyleSubmissionFileNames {
    # The files a catalogue style may hold, besides one background.<ext> of a
    # type Get-BackgroundImageExtensions names. The zip and the review's
    # unpack both take exactly these.
    @('scheme.json', 'theme.json', 'profile.ps1', 'prompt.sh', 'README.md', 'meta.json')
}

function Get-SchemeCatalogueContrastProblems {
    <#
    .SYNOPSIS
    The catalogue's contrast floors, as the slots that miss them.

    .DESCRIPTION
    Every chromatic ANSI slot needs MORE than 3.0:1 on background (WCAG
    1.4.11's floor for accent colour); foreground needs more than 4.5:1 on
    selectionBackground, because selected text is body text. black, white
    and their brights are exempt by design. Scheme-Contrast.Tests.ps1 holds
    every bundled scheme to this function and Get-StyleSubmissionProblems
    holds a submitted one to it, so the two cannot disagree.

    Returns one record per miss: Slot, Color, Against ('background' or
    'selectionBackground'), AgainstColor, Ratio, Floor. -Exempt names
    slots to skip (umbrella's documented red). A slot that is missing or
    does not parse is skipped; the key-set check reports those.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scheme, [string[]]$Exempt = @())

    $out = New-Object System.Collections.Generic.List[object]
    $bg = ConvertTo-NormalHex $Scheme.background
    if ($bg) {
        foreach ($k in 'red', 'green', 'yellow', 'blue', 'purple', 'cyan',
                       'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan') {
            if ($Exempt -contains $k) { continue }
            $hex = ConvertTo-NormalHex $Scheme.$k
            if (-not $hex) { continue }
            $ratio = Get-ContrastRatio $hex $bg
            if ($ratio -le 3.0) {
                $out.Add([pscustomobject]@{ Slot = $k; Color = $hex; Against = 'background'; AgainstColor = $bg; Ratio = $ratio; Floor = 3.0 })
            }
        }
    }
    $sel = ConvertTo-NormalHex $Scheme.selectionBackground
    $fg = ConvertTo-NormalHex $Scheme.foreground
    if ($sel -and $fg -and ($Exempt -notcontains 'foreground')) {
        $ratio = Get-ContrastRatio $fg $sel
        if ($ratio -le 4.5) {
            $out.Add([pscustomobject]@{ Slot = 'foreground'; Color = $fg; Against = 'selectionBackground'; AgainstColor = $sel; Ratio = $ratio; Floor = 4.5 })
        }
    }
    # Callers wrap in @(): a bare return unrolls to nothing when empty.
    $out.ToArray()
}

function Get-StyleSubmissionProblems {
    <#
    .SYNOPSIS
    Why a style folder could not join the catalogue, as plain sentences.

    .DESCRIPTION
    Empty when the folder passes. A pre-flight, not the gate: the PR that
    adds a style runs the whole suite, which stays the final word. But a
    test holds every bundled style to this function, so it is never
    stricter than the catalogue it feeds.

    -Name defaults to the folder's own name. -CatalogueRoot is the styles
    folder whose names are taken (default: this module's styles\); a folder
    there with this name is a collision unless it IS -StyleDir, which is how
    a bootstrap install, where the two roots are one, still works.
    -ContrastExempt passes through to Get-SchemeCatalogueContrastProblems.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$StyleDir,
        [string]$Name,
        [string]$CatalogueRoot,
        [string[]]$ContrastExempt = @()
    )

    if (-not $Name) { $Name = [System.IO.Path]::GetFileName($StyleDir.TrimEnd('\', '/')) }
    if (-not $CatalogueRoot) { $CatalogueRoot = Join-Path $script:TStylesModuleRoot 'styles' }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $p = New-Object System.Collections.Generic.List[string]

    if (-not (Test-StyleNameValid -Name $Name)) {
        $p.Add("'$Name' is not a name the catalogue can use. $(Get-StyleNameRuleText)")
    } else {
        $taken = Join-Path $CatalogueRoot $Name
        if ([System.IO.Directory]::Exists($taken)) {
            $same = $false
            try {
                $same = [System.IO.Path]::GetFullPath($taken).TrimEnd('\', '/') -eq
                        [System.IO.Path]::GetFullPath($StyleDir).TrimEnd('\', '/')
            } catch { $same = $false }
            if (-not $same) { $p.Add("The catalogue already has a style called '$Name'. Save yours under another name with: tstyles tune $Name") }
        }
    }

    # Which files. Anything else -- a folder, a second image, a .webp -- is
    # named, because the zip and the review take only these.
    $allowed = @(Get-StyleSubmissionFileNames)
    $imageExts = @(Get-BackgroundImageExtensions)
    $images = New-Object System.Collections.Generic.List[string]
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($StyleDir)) {
        $leaf = [System.IO.Path]::GetFileName($entry)
        if ([System.IO.Directory]::Exists($entry)) {
            $p.Add("The folder '$leaf' cannot be submitted: a style is only files.")
            continue
        }
        if ($allowed -ccontains $leaf) { continue }
        $m = [regex]::Match($leaf, '^background\.([A-Za-z]+)$')
        if ($m.Success -and ($imageExts -ccontains $m.Groups[1].Value)) { $images.Add($entry); continue }
        $p.Add("'$leaf' cannot be submitted. A style holds only $($allowed -join ', ') and one background image ($((@($imageExts) | ForEach-Object { '.' + $_ }) -join ', ')).")
    }
    if ($images.Count -gt 1) {
        $p.Add("There are $($images.Count) background images; keep one: $((@($images) | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', ').")
    }
    foreach ($img in $images) {
        $len = (New-Object System.IO.FileInfo $img).Length
        if ($len -gt 2MB) {
            $mb = [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $len / 1MB)
            $p.Add("$([System.IO.Path]::GetFileName($img)) is $mb MB; the catalogue takes images up to 2 MB.")
        }
    }

    # scheme.json: the full key set, every colour #rrggbb, the contrast floors.
    $schemePath = Join-Path $StyleDir 'scheme.json'
    if (-not [System.IO.File]::Exists($schemePath)) {
        $p.Add('scheme.json is missing.')
    } else {
        $scheme = $null
        try { $scheme = [System.IO.File]::ReadAllText($schemePath, $utf8) | ConvertFrom-Json -ErrorAction Stop } catch { $scheme = $null }
        if (-not $scheme) {
            $p.Add('scheme.json is not valid JSON.')
        } else {
            $slots = 'background', 'foreground', 'cursorColor', 'selectionBackground',
                     'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
                     'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
                     'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
            $missing = @($slots | Where-Object { -not $scheme.PSObject.Properties[$_] })
            if ($missing.Count) { $p.Add("scheme.json is missing: $($missing -join ', ').") }
            $bad = @($slots | Where-Object { $scheme.PSObject.Properties[$_] -and ("$($scheme.$_)" -notmatch '^#[0-9a-fA-F]{6}$') })
            if ($bad.Count) { $p.Add("scheme.json colours must be #rrggbb: $($bad -join ', ').") }
            if ("$($scheme.name)" -cne $Name) { $p.Add("scheme.json's name must be '$Name', the style's name.") }
            foreach ($c in @(Get-SchemeCatalogueContrastProblems -Scheme $scheme -Exempt $ContrastExempt)) {
                $ratio = [string]::Format([cultureinfo]::InvariantCulture, '{0:0.00}', $c.Ratio)
                $p.Add("$($c.Slot) ($($c.Color)) is $ratio`:1 on $($c.Against) ($($c.AgainstColor)); the catalogue needs more than $($c.Floor):1.")
            }
        }
    }

    $themePath = Join-Path $StyleDir 'theme.json'
    if ([System.IO.File]::Exists($themePath)) {
        try { $null = [System.IO.File]::ReadAllText($themePath, $utf8) | ConvertFrom-Json -ErrorAction Stop }
        catch { $p.Add('theme.json is not valid JSON.') }
    }

    if ([System.IO.File]::Exists((Join-Path $StyleDir 'profile.ps1')) -and
        -not [System.IO.File]::Exists((Join-Path $StyleDir 'prompt.sh'))) {
        $p.Add('profile.ps1 has no prompt.sh beside it: the catalogue needs the zsh/bash half of the prompt too.')
    }

    # meta.json: the picker shows its description on one row.
    $limits = Get-StyleMetaLimits
    $metaPath = Join-Path $StyleDir 'meta.json'
    $meta = $null
    if ([System.IO.File]::Exists($metaPath)) {
        try { $meta = [System.IO.File]::ReadAllText($metaPath, $utf8) | ConvertFrom-Json -ErrorAction Stop } catch { $meta = $null }
    }
    $desc = if ($meta) { "$($meta.description)".Trim() } else { '' }
    $quote = if ($meta) { "$($meta.quote)".Trim() } else { '' }
    if (-not $desc) {
        $p.Add('meta.json needs a one-line description: it is what the picker shows beside the name.')
    } elseif ($desc -match "[`r`n]" -or $desc.Length -gt $limits.Description) {
        $p.Add("meta.json's description must be one line of at most $($limits.Description) characters (it is $($desc.Length)).")
    }
    if ($quote -and ($quote -match "[`r`n]" -or $quote.Length -gt $limits.Quote)) {
        $p.Add("meta.json's quote must be one line of at most $($limits.Quote) characters (it is $($quote.Length)).")
    }

    # Callers wrap in @(): a bare return unrolls to nothing when empty.
    $p.ToArray()
}

function ConvertTo-CreatedPromptChoice {
    # The creator state's prompt choices, as the record meta.json keeps:
    # what Test-StylePromptIsGenerated regenerates the prompt from.
    param([Parameter(Mandatory)][hashtable]$State)
    [ordered]@{
        shape       = [string]$State.PromptShape
        symbol      = [string]$State.Symbol
        pathColor   = [string]$State.PromptPathColor
        symbolColor = [string]$State.PromptSymbolColor
    }
}

function New-CreatedStylePromptText {
    # The prompt a created style is saved with, from its recorded choice:
    # New-StylePromptText titled with the upper-cased name, no -BranchColor
    # (the git shape's branch takes the generator's default arm). The
    # creator's save and the review's regeneration both come here.
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Choice, [Parameter(Mandatory)][string]$Name)
    New-StylePromptText -Shape $Choice.shape -Symbol $Choice.symbol `
        -PathColor $Choice.pathColor -SymbolColor $Choice.symbolColor `
        -Title $Name.ToUpperInvariant()
}

function Test-StylePromptIsGenerated {
    <#
    .SYNOPSIS
    'generated' | 'hand-written' | 'none': is this style's prompt code the
    creator's, byte for byte?

    .DESCRIPTION
    'generated' only when meta.json carries the creator's `created` record,
    its shape and symbol are ones the creator offers and its colours are
    #rrggbb, and both profile.ps1 and prompt.sh are exactly what
    New-CreatedStylePromptText makes from it (prompt.sh LF-normalised, as
    Save-CreatedStyle writes it). Then the files are this module's code and
    nothing the submitter wrote. Anything else with a prompt file is
    'hand-written' -- the maintainer reads it before accepting. 'none'
    means the style ships neither file.

    The symbol is checked against Get-StylePromptSymbols rather than only
    the generator's own rule: the verdict vouches for the code, so it takes
    nothing the creator would not have offered.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir, [string]$Name)

    if (-not $Name) { $Name = [System.IO.Path]::GetFileName($StyleDir.TrimEnd('\', '/')) }
    $profilePath = Join-Path $StyleDir 'profile.ps1'
    $shellPath = Join-Path $StyleDir 'prompt.sh'
    $hasProfile = [System.IO.File]::Exists($profilePath)
    $hasShell = [System.IO.File]::Exists($shellPath)
    if (-not $hasProfile -and -not $hasShell) { return 'none' }
    if (-not ($hasProfile -and $hasShell)) { return 'hand-written' }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try {
        $meta = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'meta.json'), $utf8) | ConvertFrom-Json -ErrorAction Stop
    } catch { return 'hand-written' }
    $c = $meta.created
    if (-not $c) { return 'hand-written' }
    $choice = [ordered]@{
        shape = "$($c.shape)"; symbol = "$($c.symbol)"
        pathColor = "$($c.pathColor)"; symbolColor = "$($c.symbolColor)"
    }
    if (@(Get-StylePromptShapes) -cnotcontains $choice.shape) { return 'hand-written' }
    if (@(Get-StylePromptSymbols) -cnotcontains $choice.symbol) { return 'hand-written' }
    if ($choice.pathColor -notmatch '^#[0-9a-fA-F]{6}$' -or $choice.symbolColor -notmatch '^#[0-9a-fA-F]{6}$') { return 'hand-written' }
    if (-not (Test-StyleNameValid -Name $Name)) { return 'hand-written' }

    try { $want = New-CreatedStylePromptText -Choice $choice -Name $Name } catch { return 'hand-written' }
    $wantProfile = $utf8.GetBytes([string]$want.Profile)
    $wantShell = $utf8.GetBytes((([string]$want.Shell) -replace "`r`n", "`n"))
    $gotProfile = [System.IO.File]::ReadAllBytes($profilePath)
    $gotShell = [System.IO.File]::ReadAllBytes($shellPath)
    $same = { param($a, $b) [Convert]::ToBase64String([byte[]]$a) -ceq [Convert]::ToBase64String([byte[]]$b) }
    if ((& $same $wantProfile $gotProfile) -and (& $same $wantShell $gotShell)) { return 'generated' }
    'hand-written'
}

function Get-TerminalStylesModuleVersion {
    # This module's version from its manifest, or '' when it cannot be read.
    try {
        $m = Import-PowerShellDataFile -Path (Join-Path $script:TStylesModuleRoot 'TerminalStyles.psd1') -ErrorAction Stop
        return [string]$m.ModuleVersion
    } catch { return '' }
}

function New-StyleSubmissionPackage {
    <#
    .SYNOPSIS
    Packs a style folder into <OutDir>\<Name>.zip for a submission issue.

    .DESCRIPTION
    Flat entries: the style's allowed files (Get-StyleSubmissionFileNames),
    its one background image, and submission.json -- name, description,
    image source, the rights answer ($null when there is no image), module
    version and a UTC timestamp written culture-invariantly. Built beside
    the destination and moved over it, so an older zip for the same name is
    replaced whole or not at all.

    Status is written | failed, with Path or Reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$OutDir,
        [AllowEmptyString()][string]$ImageSource = '',
        $RightsConfirmed = $null
    )
    $result = { param($s, $p, $r) [pscustomobject]@{ Status = $s; Path = $p; Reason = $r } }
    $dest = Join-Path $OutDir "$Name.zip"
    $tmp = Join-Path $OutDir ("$Name." + [guid]::NewGuid().ToString('N') + '.part')
    try {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        if (-not [System.IO.Directory]::Exists($OutDir)) { [void][System.IO.Directory]::CreateDirectory($OutDir) }

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $desc = ''
        try {
            $meta = [System.IO.File]::ReadAllText((Join-Path $StyleDir 'meta.json'), $utf8) | ConvertFrom-Json -ErrorAction Stop
            $desc = "$($meta.description)".Trim()
        } catch { $desc = '' }
        $record = [ordered]@{
            name                 = $Name
            description          = $desc
            imageSource          = $ImageSource
            imageRightsConfirmed = $RightsConfirmed
            moduleVersion        = (Get-TerminalStylesModuleVersion)
            createdUtc           = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        }

        $files = New-Object System.Collections.Generic.List[string]
        foreach ($f in @(Get-StyleSubmissionFileNames)) {
            $path = Join-Path $StyleDir $f
            if ([System.IO.File]::Exists($path)) { $files.Add($path) }
        }
        $img = Get-BackgroundFileIn -Directory $StyleDir
        if ($img) { $files.Add([string]$img) }

        $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::CreateNew)
        try {
            $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($path in $files) {
                    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $path, [System.IO.Path]::GetFileName($path))
                }
                $entry = $zip.CreateEntry('submission.json')
                $w = New-Object System.IO.StreamWriter($entry.Open(), $utf8)
                try { $w.Write(([pscustomobject]$record | ConvertTo-Json -Depth 4)) } finally { $w.Dispose() }
            } finally { $zip.Dispose() }
        } finally { $fs.Dispose() }

        if ([System.IO.File]::Exists($dest)) { [System.IO.File]::Delete($dest) }
        [System.IO.File]::Move($tmp, $dest)
        return (& $result 'written' $dest $null)
    } catch {
        if ([System.IO.File]::Exists($tmp)) { try { [System.IO.File]::Delete($tmp) } catch { $null = $_ } }
        return (& $result 'failed' $null $_.Exception.Message)
    }
}

function Get-StyleSubmissionUrl {
    # The "Style submission" issue form, prefilled. GitHub issue forms take
    # a field's id as a query parameter.
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Description = '',
        [AllowEmptyString()][string]$ImageSource = ''
    )
    $q = [ordered]@{
        template       = 'style_submission.yml'
        title          = "Style: $Name"
        'style-name'   = $Name
        description    = $Description
        'image-source' = $ImageSource
    }
    $pairs = foreach ($k in $q.Keys) { '{0}={1}' -f $k, [uri]::EscapeDataString([string]$q[$k]) }
    "https://github.com/$($script:TStylesSubmitRepo)/issues/new?" + ($pairs -join '&')
}

function Invoke-TerminalStyleSubmit {
    <#
    .SYNOPSIS
    `tstyles submit <name>`: check a style of yours, pack it, open the issue.

    .DESCRIPTION
    Nothing is sent. The last line says so, and what the user still has to
    do: attach the zip to the issue the browser opened.

    -ReadLine and -OpenUrl are seams: tests answer the prompts and catch the
    URL instead of a person and a browser.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [scriptblock]$ReadLine = { param($prompt) Read-Host $prompt },
        [scriptblock]$OpenUrl = { param($url) Start-Process $url }
    )

    if (-not $Name) {
        Write-Host "  Usage: tstyles submit <name>   (one of your own styles; see tstyles help submit)" -ForegroundColor Yellow
        return
    }
    $dir = Get-StyleDir -StyleName $Name
    if (-not $dir) {
        Write-Host "  No style named '$Name'. Nothing was submitted." -ForegroundColor Yellow
        return
    }
    $origin = Get-StyleOrigin -Name $Name -StyleDir $dir
    if ($origin -eq 'bundled') {
        Write-Host "  '$Name' is already in the catalogue. Nothing was submitted." -ForegroundColor Yellow
        return
    }
    if ($origin -eq 'shadow') {
        Write-Host "  Your '$Name' uses a bundled style's name, and the catalogue needs a name of its own. Save it under a new name with: tstyles tune $Name" -ForegroundColor Yellow
        return
    }
    if ($origin -ne 'yours') {
        Write-Host "  Cannot tell whether '$Name' is your style or a bundled one, so nothing was submitted." -ForegroundColor Yellow
        return
    }

    $problems = @(Get-StyleSubmissionProblems -StyleDir $dir -Name $Name)
    if ($problems.Count) {
        Write-Host "  '$Name' cannot be submitted yet:" -ForegroundColor Yellow
        foreach ($line in $problems) { Write-Host "    - $line" }
        Write-Host "  Nothing was submitted."
        return
    }

    $source = ''
    $rights = $null
    if (Get-BackgroundFileIn -Directory $dir) {
        $source = "$(& $ReadLine '  Where does the background image come from? (a link or a few words; Enter to skip)')".Trim()
        $answer = "$(& $ReadLine '  Do you have the right to let everyone use this image? [y/N]')".Trim()
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host "  Not submitted: the catalogue can only ship images that may be shared." -ForegroundColor Yellow
            return
        }
        $rights = $true
    }

    $pack = New-StyleSubmissionPackage -StyleDir $dir -Name $Name `
        -OutDir (Join-Path $script:TStylesDataRoot 'submissions') -ImageSource $source -RightsConfirmed $rights
    if ($pack.Status -ne 'written') {
        Write-Host "  Could not write the submission: $($pack.Reason) Nothing was submitted." -ForegroundColor Red
        return
    }

    $meta = Get-StyleMeta -StyleDir $dir
    $url = Get-StyleSubmissionUrl -Name $Name -Description $meta.Description -ImageSource $source
    $opened = $true
    try { & $OpenUrl $url } catch { $opened = $false }

    Write-Host "  Packed '$Name' into $($pack.Path)" -ForegroundColor Green
    if ($opened) {
        Write-Host "  The submission form is opening in your browser. If it does not, open:"
    } else {
        Write-Host "  Open the submission form in your browser:"
    }
    Write-Host "    $url"
    Write-Host "  Not sent yet: drag the zip into the form and press Submit. The maintainer decides whether it joins the catalogue." -ForegroundColor Cyan
}
