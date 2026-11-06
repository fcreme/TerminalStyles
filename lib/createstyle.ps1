# Writes a style made by `tstyles create` into the user styles directory.
# Like Save-TunedStyle, the result is a full style, indistinguishable from a
# hand-written one. Unlike it, a taken name is REFUSED, never overwritten.

function New-CreatedThemeObject {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FontFace,
        [Parameter(Mandatory)][int]$FontSize,
        [Parameter(Mandatory)][string]$CursorShape,
        [Parameter(Mandatory)][ValidateRange(0.0, 1.0)][double]$ImageOpacity,
        [Parameter(Mandatory)][ValidateSet('none', 'fill', 'uniform', 'uniformToFill')][string]$StretchMode,
        [Parameter(Mandatory)][string]$Alignment,
        [Parameter(Mandatory)][string]$TabColor
    )
    [pscustomobject][ordered]@{
        colorScheme                    = $Name
        tabTitle                       = $Name.ToUpperInvariant()
        tabColor                       = $TabColor
        cursorShape                    = $CursorShape
        useAcrylic                     = $false
        opacity                        = 100
        'experimental.retroTerminalEffect' = $false
        font                           = [pscustomobject][ordered]@{
            face = $FontFace; size = $FontSize; weight = 'normal'
        }
        padding                        = '16'
        backgroundImage                = '{{BACKGROUND_IMAGE}}'
        backgroundImageOpacity         = $ImageOpacity
        backgroundImageStretchMode     = $StretchMode
        backgroundImageAlignment       = $Alignment
    }
}

function Test-CreatedStyleNameTaken {
    # Is $Name taken for a new style? Taken when Get-StyleDir resolves it (a
    # user or bundled style), or when a folder already sits at its path in the
    # user styles directory, style or not. The creator's name page and
    # Save-CreatedStyle both ask here, so they cannot disagree.
    param([Parameter(Mandatory)][string]$Name)
    $dest = Join-Path (Join-Path $script:TStylesDataRoot 'styles') $Name
    [bool]((Get-StyleDir -StyleName $Name) -or (Test-Path -LiteralPath $dest))
}

function Save-CreatedStyle {
    <#
    .SYNOPSIS
    Writes a created style to $DataRoot\styles\<Name>, or refuses.

    .DESCRIPTION
    Status is saved | taken | invalid | failed. -Prompt is the hashtable
    New-StylePromptText returns; its text is written verbatim.

    The style is built in $DataRoot\.creating\<guid> and renamed into place,
    so no half-written folder is ever visible under styles\ (Get-AvailableStyles
    enumerates with -Force, so even a dot-prefixed folder there would be listed
    the moment its scheme.json landed). Both are on the same volume.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Scheme,
        [Parameter(Mandatory)]$Theme,
        [Parameter(Mandatory)][string]$BackgroundPath,
        [Parameter(Mandatory)][hashtable]$Prompt,
        [string]$Description = ''
    )

    $result = { param($s, $p, $r) [pscustomobject]@{ Status = $s; Path = $p; Reason = $r } }

    if (-not (Test-StyleNameValid -Name $Name)) {
        return (& $result 'invalid' $null "'$Name' is not a usable style name.")
    }

    # Only the extensions Get-BackgroundFileIn resolves paint a background.
    $ext = [System.IO.Path]::GetExtension($BackgroundPath).ToLowerInvariant()
    if ($ext -notin '.gif', '.png', '.jpg', '.jpeg') {
        return (& $result 'invalid' $null "Background image must be a .gif, .png, .jpg or .jpeg file (got '$ext').")
    }

    $stylesRoot = Join-Path $script:TStylesDataRoot 'styles'
    $dest = Join-Path $stylesRoot $Name
    if (Test-CreatedStyleNameTaken -Name $Name) {
        return (& $result 'taken' $null "A style named '$Name' already exists.")
    }

    $workRoot = Join-Path $script:TStylesDataRoot '.creating'
    $work = Join-Path $workRoot ([guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false)

        $schemeOut = $Scheme.PSObject.Copy()
        $schemeOut | Add-Member -NotePropertyName name -NotePropertyValue $Name -Force

        [System.IO.File]::WriteAllText((Join-Path $work 'scheme.json'), ($schemeOut | ConvertTo-Json -Depth 16), $utf8)
        [System.IO.File]::WriteAllText((Join-Path $work 'theme.json'), ($Theme | ConvertTo-Json -Depth 16), $utf8)
        [System.IO.File]::WriteAllText((Join-Path $work 'meta.json'), ([pscustomobject]@{ description = $Description } | ConvertTo-Json -Depth 4), $utf8)
        [System.IO.File]::WriteAllText((Join-Path $work 'profile.ps1'), [string]$Prompt.Profile, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $work 'prompt.sh'), (([string]$Prompt.Shell) -replace "`r`n", "`n"), $utf8)

        Copy-Item -LiteralPath $BackgroundPath -Destination (Join-Path $work "background$ext") -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $stylesRoot)) {
            New-Item -ItemType Directory -Path $stylesRoot -Force -ErrorAction Stop | Out-Null
        }
        # Re-check just before the rename: another process may have taken the name.
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            return (& $result 'taken' $null "A style named '$Name' already exists.")
        }
        Move-Item -LiteralPath $work -Destination $dest -ErrorAction Stop
        if (-not (Get-ChildItem -LiteralPath $workRoot -Force)) {
            Remove-Item -LiteralPath $workRoot -Force -ErrorAction SilentlyContinue
        }
        return (& $result 'saved' $dest $null)
    } catch {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $workRoot) -and -not (Get-ChildItem -LiteralPath $workRoot -Force)) {
            Remove-Item -LiteralPath $workRoot -Force -ErrorAction SilentlyContinue
        }
        return (& $result 'failed' $null $_.Exception.Message)
    }
}
