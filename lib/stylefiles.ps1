# Reading a style's own JSON files: scheme.json and theme.json.
#
# A style folder is the one input this tool takes from other people: bundled
# styles, ones made with `tstyles create`, ones somebody hands you. Every path
# that applies, previews, picks at random, lists or tunes a style reads these
# two files, and each used to parse them its own way, so a broken file failed
# in a different place every time: a raw parse error naming a line of this
# module, a picker that died on its first frame, or "Style applied" printed
# over a style that applied nothing. One reader, and one question built on it,
# make a broken file fail the same way everywhere: before anything is
# touched, naming the style, the file and what to do about it. A second parse
# is a second rule -- on Windows PowerShell 5.1 ConvertFrom-Json refuses the
# comment this one accepts -- so tests/Style-Json-One-Reader.Tests.ps1 fails
# on any parse of these files outside Read-StyleJson.

function Read-StyleJson {
    <#
    .SYNOPSIS
    A style's scheme.json or theme.json, parsed; $null when the file is not there.

    .DESCRIPTION
    Throws one terminating error, naming the style and the file, when the file
    exists but holds no JSON object: a parse error (the message is
    ConvertFrom-JsoncText's, so JSONC comments and trailing commas are read as
    Windows Terminal reads them), an empty file, `null`, or a root that is an
    array, a string or a number. The root is checked on the text as well as on
    the value, because pwsh 7's ConvertFrom-Json unrolls a one-element array
    into its element, so `[{...}]` would otherwise pass as an object there and
    fail on Windows PowerShell 5.1.

    Bytes are decoded as UTF-8, as every other read of a style's JSON does.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StyleDir,
        [Parameter(Mandatory)][string]$FileName
    )

    $path = Join-Path $StyleDir $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    $style  = Split-Path -Leaf $StyleDir
    $label  = "$style's $FileName"
    $remedy = "fix the file, or remove the style with: tstyles delete $style"
    $text   = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))

    $value = ConvertFrom-JsoncText -Json $text -SourceName $label -Remedy $remedy
    $isObject = ($value -is [System.Management.Automation.PSCustomObject]) -and
                (Remove-JsonComment -Text $text).TrimStart().StartsWith('{')
    if (-not $isObject) {
        throw "TerminalStyles: could not parse $label. To fix it: $remedy. Underlying error: it holds no JSON object."
    }
    $value
}

function Get-StyleUnreadableFile {
    <#
    .SYNOPSIS
    Which of a style's JSON files cannot be read, or $null when both can.

    .DESCRIPTION
    scheme.json first, then theme.json when there is one (theme.json is
    optional; a missing scheme.json is the caller's own case, since a style
    without one is not a style). Returns @{ File; Message }, Message being
    Read-StyleJson's, so whoever refuses the style says exactly what it says.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StyleDir)

    foreach ($file in 'scheme.json', 'theme.json') {
        try {
            [void](Read-StyleJson -StyleDir $StyleDir -FileName $file)
        } catch {
            return [pscustomobject]@{ File = $file; Message = "$($_.Exception.Message)" }
        }
    }
    return $null
}
