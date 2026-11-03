# jsonctext.ps1 -- editing JSONC as TEXT, so comments and formatting survive.
#
# WHY THIS EXISTS. lib/vscode.ps1 merges a style into VS Code's settings.json
# by parsing it, mutating the object and serialising it back. That round trip
# destroys every comment and all formatting in a file people hand-annotate.
# lib/wtsettings.ps1 does the same to Windows Terminal's settings.json and has
# always done, which is a smaller sin only because fewer people comment it.
#
# Everything here is pure: text in, text out. No file is read or written, no
# environment is consulted, and nothing depends on the host -- which is what
# lets the tests drive the hard cases as strings.
#
# THE OWNERSHIP RULE, which is the whole design. Four independent designs for
# this were reviewed and every one of them was broken in the same place: what
# text does a member OWN when you delete it? The clever answers -- own the
# comment above you, own your whole line -- each destroyed something in a real
# file: a `// --- terminal ---` section header deleted along with the key under
# it; a trailing `// keep` belonging to the NEXT member eaten; a compact
# `{ "a": 1, "b": 2 }` mangled by a whole-line delete.
#
# So the rule here is the dull one:
#
#     A member owns its key, its value, the text between them, and the one
#     comma that separates it. It owns NO comment, ever.
#
# An orphaned comment is litter the user can delete in two seconds. A deleted
# comment is their writing, gone, with no undo. Those are not comparable, so
# the rule never has to weigh them. Test-JsoncCommentsIntact turns it into an
# invariant that is CHECKED rather than intended: Set-JsoncLiteral and
# Remove-JsoncValue run it on every splice and refuse ('commentchanged') an
# edit that would change a comment -- including one written in "the text
# between" a member's key and value, which that member's removal would take.
# Set-JsoncLiteral also reads the value back from the result ('notreadback').
# The header said "checked" from 0.9.0 while nothing called the check.
#
# The other trap the review found: a separating comma must be written at the
# value's end offset, never at the end of the line. A line ending in a comment
# puts the comma inside the comment, which silently removes the separator and
# breaks the file at the NEXT member.
#
# And the end of a line is not always outside every comment: a block comment
# that opens there and closes on a later line contains it. A new member written
# at the end of the line went inside that comment (Get-JsoncInsertAnchor).

function Get-JsoncToken {
    <#
    .SYNOPSIS
    Split JSONC text into tokens carrying their source offsets.

    .DESCRIPTION
    Pure. Returns an array of @{ Kind; Start; Length }, covering the text with
    no gaps: joining every token's source text reproduces the input exactly.
    That invariant is what makes splicing safe, and it is asserted directly by
    the tests rather than assumed.

    Kinds: Whitespace, LineComment, BlockComment, String, Colon, Comma,
    BraceOpen, BraceClose, BracketOpen, BracketClose, Other.

    The string state machine is the one lib/wtsettings.ps1's Remove-JsonComment
    already uses -- an $escaped flag, so a backslash-escaped quote does not end
    the string and `\\` before a quote does. That is what keeps braces, commas
    and `//` inside a string value structurally invisible.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $tokens = [System.Collections.Generic.List[object]]::new()
    $n = $Text.Length
    $i = 0
    while ($i -lt $n) {
        $c = $Text[$i]

        if ([char]::IsWhiteSpace($c)) {
            $s = $i
            while ($i -lt $n -and [char]::IsWhiteSpace($Text[$i])) { $i++ }
            $tokens.Add(@{ Kind = 'Whitespace'; Start = $s; Length = $i - $s })
            continue
        }

        if ($c -eq '"') {
            $s = $i
            $i++
            $escaped = $false
            while ($i -lt $n) {
                $ch = $Text[$i]
                if ($escaped)        { $escaped = $false }
                elseif ($ch -eq '\') { $escaped = $true }
                elseif ($ch -eq '"') { $i++; break }
                $i++
            }
            $tokens.Add(@{ Kind = 'String'; Start = $s; Length = $i - $s })
            continue
        }

        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/') {
            $s = $i
            # The newline is NOT part of the comment: it belongs to the
            # whitespace that follows, so a line comment never owns the line
            # break that ends it.
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
            $tokens.Add(@{ Kind = 'LineComment'; Start = $s; Length = $i - $s })
            continue
        }

        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '*') {
            $s = $i
            $i += 2
            while ($i -lt $n -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
            if ($i -lt $n) { $i += 2 } else { $i = $n }   # unterminated: to EOF
            $tokens.Add(@{ Kind = 'BlockComment'; Start = $s; Length = $i - $s })
            continue
        }

        $kind = switch ($c) {
            ':' { 'Colon' }
            ',' { 'Comma' }
            '{' { 'BraceOpen' }
            '}' { 'BraceClose' }
            '[' { 'BracketOpen' }
            ']' { 'BracketClose' }
            default { $null }
        }
        if ($kind) {
            $tokens.Add(@{ Kind = $kind; Start = $i; Length = 1 })
            $i++
            continue
        }

        # A run of anything else: a number, true/false/null, or junk. The
        # editor never needs to tell those apart -- it only ever replaces a
        # value span wholesale -- so one kind is enough.
        $s = $i
        while ($i -lt $n) {
            $ch = $Text[$i]
            if ([char]::IsWhiteSpace($ch) -or $ch -eq '"' -or $ch -eq ':' -or $ch -eq ',' -or
                $ch -eq '{' -or $ch -eq '}' -or $ch -eq '[' -or $ch -eq ']') { break }
            if ($ch -eq '/' -and ($i + 1) -lt $n -and ($Text[$i + 1] -eq '/' -or $Text[$i + 1] -eq '*')) { break }
            $i++
        }
        $tokens.Add(@{ Kind = 'Other'; Start = $s; Length = $i - $s })
    }
    return ,$tokens.ToArray()
}

function ConvertFrom-JsoncString {
    # The decoded text of a JSON string token, quotes stripped and escapes
    # resolved, so a key written with unicode escapes still matches the plain
    # name a caller asks for. Returns $null if the token is not a well-formed
    # string.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)

    if ($Raw.Length -lt 2 -or $Raw[0] -ne '"' -or $Raw[$Raw.Length - 1] -ne '"') { return $null }
    $body = $Raw.Substring(1, $Raw.Length - 2)
    $sb = [System.Text.StringBuilder]::new($body.Length)
    $i = 0
    while ($i -lt $body.Length) {
        $c = $body[$i]
        if ($c -ne '\') { [void]$sb.Append($c); $i++; continue }
        $i++
        if ($i -ge $body.Length) { break }
        $e = $body[$i]
        switch ($e) {
            'n' { [void]$sb.Append("`n") }
            't' { [void]$sb.Append("`t") }
            'r' { [void]$sb.Append("`r") }
            'b' { [void]$sb.Append([char]8) }
            'f' { [void]$sb.Append([char]12) }
            'u' {
                if (($i + 4) -lt $body.Length + 1 -and ($i + 5) -le $body.Length) {
                    $hex = $body.Substring($i + 1, 4)
                    $code = 0
                    if ([int]::TryParse($hex, [System.Globalization.NumberStyles]::HexNumber,
                            [cultureinfo]::InvariantCulture, [ref]$code)) {
                        [void]$sb.Append([char]$code)
                        $i += 4
                    } else { [void]$sb.Append($e) }
                } else { [void]$sb.Append($e) }
            }
            default { [void]$sb.Append($e) }   # \" \\ \/ and anything else
        }
        $i++
    }
    return $sb.ToString()
}

function ConvertTo-JsoncString {
    # A string as a JSON string literal. Only the escapes JSON requires.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $sb = [System.Text.StringBuilder]::new($Value.Length + 2)
    [void]$sb.Append('"')
    foreach ($c in $Value.ToCharArray()) {
        $code = [int]$c
        if     ($c -eq '"')  { [void]$sb.Append('\"') }
        elseif ($c -eq '\')  { [void]$sb.Append('\\') }
        elseif ($code -eq 8) { [void]$sb.Append('\b') }
        elseif ($code -eq 9) { [void]$sb.Append('\t') }
        elseif ($code -eq 10){ [void]$sb.Append('\n') }
        elseif ($code -eq 12){ [void]$sb.Append('\f') }
        elseif ($code -eq 13){ [void]$sb.Append('\r') }
        elseif ($code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-JsoncLiteral {
    # A PowerShell value as JSONC source text. Strings quote; numbers and
    # booleans do not. Anything else is refused rather than guessed at -- a
    # value this does not understand must not reach a user's file.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or
        $Value -is [decimal] -or $Value -is [single]) {
        return [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value)
    }
    if ($Value -is [string]) { return (ConvertTo-JsoncString -Value $Value) }
    throw "Cannot write a $($Value.GetType().Name) into JSONC text."
}

function Get-JsoncObjectMember {
    <#
    .SYNOPSIS
    The members of the object whose '{' is the token at -OpenIndex.

    .DESCRIPTION
    Pure. Returns an array of member records:

      Name         decoded key
      KeyStart     offset of the opening quote of the key
      ValueStart   offset of the first character of the value
      ValueEnd     offset just past the last character of the value
      ValueOpen    for an object/array value, the token index of its '{' / '['
      CommaOffset  offset of the comma that follows, or -1
      Index, IsLast

    Only the members of THIS object -- a nested object's members belong to that
    object and are found by asking again with its own open token.

    Comments are legal between any two of these pieces and are simply skipped,
    so `"a" /* why */ : 1` parses. Its comment lies inside [KeyStart, ValueEnd),
    the span Remove-JsoncValue deletes, which is why that removal refuses
    ('commentchanged') rather than taking the comment with it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory)][int]$OpenIndex
    )

    $members = [System.Collections.Generic.List[object]]::new()
    # The significance test is written out at each use rather than called as a
    # scriptblock: this loop runs per token, and the call was most of its cost.

    $i = $OpenIndex + 1
    $depth = 0
    while ($i -lt $Tokens.Count) {
        $t = $Tokens[$i]
        if ($t.Kind -eq 'Whitespace' -or $t.Kind -eq 'LineComment' -or $t.Kind -eq 'BlockComment') { $i++; continue }
        if ($t.Kind -eq 'BraceClose') { break }
        if ($t.Kind -eq 'Comma') { $i++; continue }
        if ($t.Kind -ne 'String') { $i++; continue }   # junk: skip, do not guess

        $keyToken = $t
        $keyIndex = $i

        # colon
        $i++
        while ($i -lt $Tokens.Count -and ($Tokens[$i].Kind -eq 'Whitespace' -or $Tokens[$i].Kind -eq 'LineComment' -or $Tokens[$i].Kind -eq 'BlockComment')) { $i++ }
        if ($i -ge $Tokens.Count -or $Tokens[$i].Kind -ne 'Colon') { continue }

        # value
        $i++
        while ($i -lt $Tokens.Count -and ($Tokens[$i].Kind -eq 'Whitespace' -or $Tokens[$i].Kind -eq 'LineComment' -or $Tokens[$i].Kind -eq 'BlockComment')) { $i++ }
        if ($i -ge $Tokens.Count) { break }

        $valueStartToken = $Tokens[$i]
        $valueOpen = -1
        if ($valueStartToken.Kind -eq 'BraceOpen' -or $valueStartToken.Kind -eq 'BracketOpen') {
            $valueOpen = $i
            $close = if ($valueStartToken.Kind -eq 'BraceOpen') { 'BraceClose' } else { 'BracketClose' }
            $open  = $valueStartToken.Kind
            $depth = 0
            while ($i -lt $Tokens.Count) {
                if ($Tokens[$i].Kind -eq $open)  { $depth++ }
                if ($Tokens[$i].Kind -eq $close) { $depth--; if ($depth -eq 0) { break } }
                $i++
            }
        }
        $valueEndToken = $Tokens[[Math]::Min($i, $Tokens.Count - 1)]
        $valueEnd = $valueEndToken.Start + $valueEndToken.Length

        # the comma that separates this member, if there is one
        $j = $i + 1
        while ($j -lt $Tokens.Count -and ($Tokens[$j].Kind -eq 'Whitespace' -or $Tokens[$j].Kind -eq 'LineComment' -or $Tokens[$j].Kind -eq 'BlockComment')) { $j++ }
        $commaOffset = -1
        if ($j -lt $Tokens.Count -and $Tokens[$j].Kind -eq 'Comma') {
            $commaOffset = $Tokens[$j].Start
            $i = $j
        }

        $members.Add(@{
            Name        = (ConvertFrom-JsoncString -Raw $Text.Substring($keyToken.Start, $keyToken.Length))
            KeyStart    = $keyToken.Start
            KeyIndex    = $keyIndex
            ValueStart  = $valueStartToken.Start
            ValueEnd    = $valueEnd
            ValueOpen   = $valueOpen
            CommaOffset = $commaOffset
            Index       = $members.Count
            IsLast      = $false
        })
        $i++
    }

    $arr = $members.ToArray()
    if ($arr.Count -gt 0) { $arr[$arr.Count - 1].IsLast = $true }
    # The leading comma stops PowerShell unrolling a ONE-element array into a
    # bare hashtable on the way out. A hashtable's .Count is its KEY count, so
    # a caller doing $m[$m.Count - 1] would index past the end and get $null --
    # silently, on exactly the commonest shape there is: an object with one
    # member.
    return ,$arr
}

function Find-JsoncRootObject {
    # The token index of the document's root '{'. -1 when the text has no
    # object at the top level, which every caller treats as "refuse".
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens)

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $k = $Tokens[$i].Kind
        if ($k -eq 'Whitespace' -or $k -eq 'LineComment' -or $k -eq 'BlockComment') { continue }
        if ($k -eq 'BraceOpen') { return $i }
        return -1
    }
    return -1
}

function Get-JsoncEol {
    # The line ending the text already uses. Never assumed: a file written with
    # CRLF must come back with CRLF, or every line shows as changed.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -match "`r`n") { return "`r`n" }
    return "`n"
}

function Get-JsoncIndentUnit {
    # The indentation the file already uses, as a string: the leading
    # whitespace of the first line that has any. Tabs stay tabs.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    foreach ($line in ($Text -split "`n")) {
        $m = [regex]::Match($line, '^([ \t]+)\S')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return '  '
}

function Invoke-JsoncSplice {
    <#
    .SYNOPSIS
    Apply a list of @{ Start; Length; Text } edits to text. Returns the result.

    .DESCRIPTION
    Pure. Edits are sorted by Start and applied with a single cursor, so the
    offsets in every edit refer to the ORIGINAL text and no edit has to know
    about any other.

    It THROWS on overlap. That is the point of the function: a planning bug
    becomes a loud failure here instead of a quietly mangled settings.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Edits
    )

    $sorted = @($Edits | Sort-Object { $_.Start })
    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $cursor = 0
    foreach ($e in $sorted) {
        if ($e.Start -lt $cursor) {
            throw "Overlapping JSONC edits at offset $($e.Start): refusing to write."
        }
        if ($e.Start -gt $Text.Length -or ($e.Start + $e.Length) -gt $Text.Length) {
            throw "JSONC edit runs past the end of the text: refusing to write."
        }
        [void]$sb.Append($Text.Substring($cursor, $e.Start - $cursor))
        if ($e.Text) { [void]$sb.Append($e.Text) }
        $cursor = $e.Start + $e.Length
    }
    [void]$sb.Append($Text.Substring($cursor))
    return $sb.ToString()
}

function Get-JsoncCommentText {
    # Every comment in the text, in order, as source strings. The evidence for
    # the ownership rule: an edit that loses one of these is rejected.
    # -Tokens reuses a tokenization the caller already holds.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowNull()][object[]]$Tokens
    )

    if ($null -eq $Tokens) { $Tokens = Get-JsoncToken -Text $Text }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $Tokens) {
        if ($t.Kind -eq 'LineComment' -or $t.Kind -eq 'BlockComment') {
            $out.Add($Text.Substring($t.Start, $t.Length))
        }
    }
    return ,$out.ToArray()
}

function Test-JsoncCommentsIntact {
    <#
    .SYNOPSIS
    Did every comment in -Before survive into -After?

    .DESCRIPTION
    Pure, and the invariant this whole file exists to keep. Compares the two
    comment lists as a multiset: every comment present before must still be
    present after, the same number of times. Adding one is fine; losing one is
    not.

    This is a CHECK, not a convention. The four designs reviewed for this each
    intended to preserve comments and each destroyed one in a case its author
    had not thought of, so intent is not the thing to rely on. Set-JsoncLiteral
    and Remove-JsoncValue run it on every splice. -BeforeTokens/-AfterTokens
    reuse tokenizations the caller already holds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Before,
        [Parameter(Mandatory)][AllowEmptyString()][string]$After,
        [AllowNull()][object[]]$BeforeTokens,
        [AllowNull()][object[]]$AfterTokens
    )

    $b = Get-JsoncCommentText -Text $Before -Tokens $BeforeTokens
    $a = Get-JsoncCommentText -Text $After -Tokens $AfterTokens
    # An ORDINAL dictionary, not @{}. A PowerShell hashtable compares string
    # keys case-insensitively, so '// mine' and '// MINE' would be the same
    # comment and an edit that rewrote one into the other would pass this
    # check. Comments are the user's text; case is part of it.
    $counts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    foreach ($c in $a) {
        if ($counts.ContainsKey($c)) { $counts[$c] = $counts[$c] + 1 } else { $counts[$c] = 1 }
    }
    foreach ($c in $b) {
        if (-not $counts.ContainsKey($c) -or $counts[$c] -le 0) { return $false }
        $counts[$c] = $counts[$c] - 1
    }
    return $true
}

function Resolve-JsoncPath {
    <#
    .SYNOPSIS
    Walk a path of key names and return the member it names, plus its parent.

    .DESCRIPTION
    Pure. -Path is an ARRAY of key names and is never split on anything. That
    is this file's answer to the dotted-key problem: VS Code settings keys
    contain dots ("terminal.integrated.fontSize" is ONE key, and
    "terminal.background" is one key nested inside "workbench.colorCustomizations"),
    so any design that splits a string on '.' cannot tell those apart. The
    caller knows the shape and says so.

    Returns @{ Member; ParentOpenIndex; Found; Reason }. Member is $null when
    the leaf is absent but its parent object exists -- which is what an
    insertion needs. ParentOpenIndex is -1 when the parent itself is missing or
    is not an object, and Reason says which.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory)][string[]]$Path
    )

    $rootOpen = Find-JsoncRootObject -Tokens $Tokens
    if ($rootOpen -lt 0) {
        return @{ Member = $null; ParentOpenIndex = -1; Found = $false; Reason = 'rootnotobject' }
    }

    $open = $rootOpen
    for ($p = 0; $p -lt $Path.Count; $p++) {
        $members = Get-JsoncObjectMember -Text $Text -Tokens $Tokens -OpenIndex $open
        $hit = $null
        # Duplicate keys are legal JSONC and the LAST one wins, which is what
        # every JSON reader does -- so take the last match, not the first.
        foreach ($m in $members) { if ($m.Name -eq $Path[$p]) { $hit = $m } }

        if ($p -eq $Path.Count - 1) {
            return @{ Member = $hit; ParentOpenIndex = $open; Found = ($null -ne $hit); Reason = 'ok' }
        }
        if (-not $hit) {
            return @{ Member = $null; ParentOpenIndex = -1; Found = $false; Reason = 'parentmissing' }
        }
        if ($hit.ValueOpen -lt 0 -or $Tokens[$hit.ValueOpen].Kind -ne 'BraceOpen') {
            return @{ Member = $null; ParentOpenIndex = -1; Found = $false; Reason = 'parentnotobject' }
        }
        $open = $hit.ValueOpen
    }
    return @{ Member = $null; ParentOpenIndex = -1; Found = $false; Reason = 'emptypath' }
}

function Get-JsoncLineBound {
    # The half-open span of the line containing -Offset: Start at the first
    # character of the line, ContentEnd before its terminator, End past it.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Offset
    )

    $start = $Offset
    while ($start -gt 0 -and $Text[$start - 1] -ne "`n") { $start-- }
    $end = $Offset
    while ($end -lt $Text.Length -and $Text[$end] -ne "`n") { $end++ }
    $contentEnd = $end
    if ($contentEnd -gt $start -and $Text[$contentEnd - 1] -eq "`r") { $contentEnd-- }
    if ($end -lt $Text.Length) { $end++ }   # past the newline
    return @{ Start = $start; ContentEnd = $contentEnd; End = $end }
}

function Get-JsoncInsertAnchor {
    <#
    .SYNOPSIS
    Where a new member goes after the line holding -Offset: the end of that
    line, unless a block comment is open there.

    .DESCRIPTION
    Pure. A // comment always ends at its line's end, but a block comment that
    opens on the line and closes on a later one contains it. Writing there put
    the member inside the comment: an apply of a style under
    `{ /* per-theme overrides` / `go in here */` said "Saved" with 4 of its 24
    keys live, and reset could not find the other 20. So the anchor moves to
    the end of the line the comment closes on -- repeatedly, for a comment
    closing where another opens -- which keeps the comment where it was and
    each new key on a line of its own. Clamped to -CloseOffset, the object's
    '}', for a comment that closes on the '}' line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$CloseOffset
    )

    $anchor = (Get-JsoncLineBound -Text $Text -Offset $Offset).ContentEnd
    while ($anchor -lt $CloseOffset) {
        # The last token starting before the anchor: the one that would hold it.
        $lo = 0; $hi = $Tokens.Count - 1; $idx = -1
        while ($lo -le $hi) {
            $mid = [int][Math]::Floor(($lo + $hi) / 2)
            if ($Tokens[$mid].Start -lt $anchor) { $idx = $mid; $lo = $mid + 1 } else { $hi = $mid - 1 }
        }
        if ($idx -lt 0) { break }
        $t = $Tokens[$idx]
        if ($t.Kind -ne 'BlockComment' -or ($t.Start + $t.Length) -le $anchor) { break }
        $anchor = (Get-JsoncLineBound -Text $Text -Offset ($t.Start + $t.Length - 1)).ContentEnd
    }
    return [Math]::Min($anchor, $CloseOffset)
}

function Test-JsoncRangeBlank {
    # Is everything in [Start, End) whitespace? Used to decide whether a line
    # held anything besides the member being removed. A comment is NOT
    # whitespace, which is exactly why a line carrying one is never dropped.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Start,
        [Parameter(Mandatory)][int]$End
    )
    if ($End -le $Start) { return $true }
    for ($i = $Start; $i -lt $End; $i++) {
        if (-not [char]::IsWhiteSpace($Text[$i])) { return $false }
    }
    return $true
}

function Set-JsoncValue {
    <#
    .SYNOPSIS
    Set a key to a value in JSONC text. Returns @{ Text; Changed; Status }.

    .DESCRIPTION
    Pure. Updates the value in place when the key exists, inserts the member
    when it does not, and refuses when the path's parent is missing or is not
    an object -- a Status of 'rootnotobject', 'parentmissing' or
    'parentnotobject' rather than a guess.

    An inserted member follows the file: its indentation is the indentation of
    the member above it, and an object written on ONE line stays on one line
    rather than being helpfully expanded. It goes on a line of its own after
    the last member's line -- or after the line a block comment open there
    closes on (Get-JsoncInsertAnchor).

    Every splice is checked before it is kept: 'commentchanged' when it would
    change one of the file's comments (an update replacing an object value
    with a comment inside it, say), 'notreadback' when the value would not
    read back from the result as written. Both leave the text unchanged.

    The separating comma is written at the previous value's END OFFSET, never
    at the end of its line. A line that ends in a comment would otherwise get
    the comma written inside the comment, which deletes the separator and
    breaks the member after it. That is a real defect found in one of the
    designs this replaced, and it is silent: the file still looks right.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][AllowNull()]$Value
    )
    return (Set-JsoncLiteral -Text $Text -Path $Path -Literal (ConvertTo-JsoncLiteral -Value $Value))
}

function Get-JsoncValueLiteral {
    <#
    .SYNOPSIS
    The SOURCE TEXT of the value at -Path, or $null when the key is absent.

    .DESCRIPTION
    Pure. Source text, not a parsed value, because the caller comparing this
    wants to know whether the bytes are still the ones it wrote. Parsed
    equality would call '#F5F5F5' and '#f5f5f5' the same value; they are the
    same colour but they are not the same text, and only one of them is ours.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Path
    )

    $tokens = Get-JsoncToken -Text $Text
    $found = Resolve-JsoncPath -Text $Text -Tokens $tokens -Path $Path
    if (-not $found.Member) { return $null }
    return $Text.Substring($found.Member.ValueStart, $found.Member.ValueEnd - $found.Member.ValueStart)
}

function Set-JsoncLiteral {
    # Set a key to a value given as JSONC SOURCE TEXT, with no encoding step.
    # Writing back a value exactly as it was found is what a restore needs, and
    # re-encoding a parsed value cannot promise that. Refuses, unchanged, an
    # edit that would change a comment or not read back (see Set-JsoncValue).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][string]$Literal
    )

    $tokens = Get-JsoncToken -Text $Text
    $found = Resolve-JsoncPath -Text $Text -Tokens $tokens -Path $Path
    $literal = $Literal

    if ($found.ParentOpenIndex -lt 0) {
        return @{ Text = $Text; Changed = $false; Status = $found.Reason }
    }

    # Present: replace just the value span.
    if ($found.Member) {
        $m = $found.Member
        # -cne, not -ne. PowerShell's -eq is case-insensitive, so writing
        # "#F8F8F8" over "#f8f8f8" would report 'same' and change nothing --
        # a silent no-op on an edit the caller asked for.
        if ($Text.Substring($m.ValueStart, $m.ValueEnd - $m.ValueStart) -ceq $literal) {
            return @{ Text = $Text; Changed = $false; Status = 'same' }
        }
        $new = Invoke-JsoncSplice -Text $Text -Edits @(
            @{ Start = $m.ValueStart; Length = ($m.ValueEnd - $m.ValueStart); Text = $literal }
        )
        return (Confirm-JsoncLiteralSplice -Text $Text -Tokens $tokens -New $new -Path $Path -Literal $literal -Status 'updated')
    }

    # Absent: insert.
    $openTok  = $tokens[$found.ParentOpenIndex]
    $members  = Get-JsoncObjectMember -Text $Text -Tokens $tokens -OpenIndex $found.ParentOpenIndex
    $closeOff = Find-JsoncCloseBrace -Tokens $tokens -OpenIndex $found.ParentOpenIndex
    if ($closeOff -lt 0) { return @{ Text = $Text; Changed = $false; Status = 'unterminated' } }

    $eol  = Get-JsoncEol -Text $Text
    $unit = Get-JsoncIndentUnit -Text $Text
    $keyText = (ConvertTo-JsoncString -Value $Path[$Path.Count - 1]) + ': ' + $literal
    $singleLine = -not ($Text.Substring($openTok.Start, $closeOff - $openTok.Start).Contains("`n"))
    $edits = @()

    if ($singleLine) {
        # Keep a compact object compact. Expanding it would rewrite lines the
        # user never asked us to touch.
        if ($members.Count -eq 0) {
            $edits += @{ Start = ($openTok.Start + 1); Length = 0; Text = $keyText }
        } else {
            $last = $members[$members.Count - 1]
            if ($last.CommaOffset -ge 0) {
                $edits += @{ Start = ($last.CommaOffset + 1); Length = 0; Text = ' ' + $keyText + ',' }
            } else {
                $edits += @{ Start = $last.ValueEnd; Length = 0; Text = ', ' + $keyText }
            }
        }
    } else {
        # The break goes in as the anchor line's own terminator: in a file of
        # mixed endings, a CRLF written before an LF-only line's break would be
        # taken into a // comment ending there (a line comment runs to the LF).
        $breakAt = {
            param([int]$At)
            if ($At -lt $Text.Length -and $Text[$At] -eq "`r") { return "`r`n" }
            if ($At -lt $Text.Length -and $Text[$At] -eq "`n") { return "`n" }
            return $eol
        }
        if ($members.Count -eq 0) {
            $anchorLine = Get-JsoncLineBound -Text $Text -Offset $openTok.Start
            $anchor = Get-JsoncInsertAnchor -Text $Text -Tokens $tokens -Offset $openTok.Start -CloseOffset $closeOff
            $braceIndent = [regex]::Match($Text.Substring($anchorLine.Start), '^[ \t]*').Value
            $edits += @{ Start = $anchor; Length = 0; Text = (& $breakAt $anchor) + $braceIndent + $unit + $keyText }
        } else {
            $last = $members[$members.Count - 1]
            $tailOffset = if ($last.CommaOffset -ge 0) { $last.CommaOffset } else { $last.ValueEnd }
            $lastLine = Get-JsoncLineBound -Text $Text -Offset $tailOffset
            $anchor = Get-JsoncInsertAnchor -Text $Text -Tokens $tokens -Offset $tailOffset -CloseOffset $closeOff
            $eolHere = & $breakAt $anchor
            $indent = [regex]::Match($Text.Substring($lastLine.Start), '^[ \t]*').Value
            $needComma = ($last.CommaOffset -lt 0)

            if ($needComma -and $last.ValueEnd -eq $anchor) {
                # Nothing between the value and the end of the line, so one
                # edit carries both and there is no ordering question.
                $edits += @{ Start = $anchor; Length = 0; Text = ',' + $eolHere + $indent + $keyText }
            } else {
                if ($needComma) {
                    $edits += @{ Start = $last.ValueEnd; Length = 0; Text = ',' }
                }
                $edits += @{ Start = $anchor; Length = 0; Text = $eolHere + $indent + $keyText }
            }
        }
    }

    $new = Invoke-JsoncSplice -Text $Text -Edits $edits
    return (Confirm-JsoncLiteralSplice -Text $Text -Tokens $tokens -New $new -Path $Path -Literal $literal -Status 'inserted')
}

function Confirm-JsoncLiteralSplice {
    # Keep a Set-JsoncLiteral splice only if it changed no comment and the
    # value reads back from the result as written -- the same read a later
    # reset makes. One tokenization of the result serves both checks.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory)][AllowEmptyString()][string]$New,
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][string]$Literal,
        [Parameter(Mandatory)][string]$Status
    )
    $newTokens = Get-JsoncToken -Text $New
    if (-not (Test-JsoncCommentsIntact -Before $Text -After $New -BeforeTokens $Tokens -AfterTokens $newTokens)) {
        return @{ Text = $Text; Changed = $false; Status = 'commentchanged' }
    }
    $back = Resolve-JsoncPath -Text $New -Tokens $newTokens -Path $Path
    if (-not $back.Member -or
        $New.Substring($back.Member.ValueStart, $back.Member.ValueEnd - $back.Member.ValueStart) -cne $Literal) {
        return @{ Text = $Text; Changed = $false; Status = 'notreadback' }
    }
    return @{ Text = $New; Changed = $true; Status = $Status }
}

function Find-JsoncCloseBrace {
    # Offset of the '}' matching the '{' at -OpenIndex, or -1 if unterminated.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory)][int]$OpenIndex
    )
    $depth = 0
    for ($i = $OpenIndex; $i -lt $Tokens.Count; $i++) {
        if ($Tokens[$i].Kind -eq 'BraceOpen')  { $depth++ }
        if ($Tokens[$i].Kind -eq 'BraceClose') {
            $depth--
            if ($depth -eq 0) { return $Tokens[$i].Start }
        }
    }
    return -1
}

function Remove-JsoncValue {
    <#
    .SYNOPSIS
    Remove a key from JSONC text. Returns @{ Text; Changed; Status }.

    .DESCRIPTION
    Pure, and the half where the ownership rule bites.

    The member's own span is its key through its value. Exactly one comma goes
    with it -- its own if it has one, otherwise the PREVIOUS member's, since
    removing the last member is what leaves a dangling separator. Those are
    separate edits, so anything sitting between a value and its comma (legal,
    and occasionally a comment) is not inside either.

    The line the member sat on is removed as well ONLY when the line held
    nothing else at all. A line carrying a comment is not blank, so it stays --
    the member goes and the comment remains, orphaned. That is deliberate: an
    orphan comment is two seconds of tidying, and a deleted comment is the
    user's writing with no undo.

    A comment INSIDE the span -- `"a" /* why */ : 1`, or inside an object value
    -- would go with it, so that removal is refused ('commentchanged') and the
    text is returned unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Path
    )

    $tokens = Get-JsoncToken -Text $Text
    $found = Resolve-JsoncPath -Text $Text -Tokens $tokens -Path $Path
    if ($found.ParentOpenIndex -lt 0) {
        return @{ Text = $Text; Changed = $false; Status = $found.Reason }
    }
    if (-not $found.Member) {
        return @{ Text = $Text; Changed = $false; Status = 'absent' }
    }

    $m = $found.Member
    $members = Get-JsoncObjectMember -Text $Text -Tokens $tokens -OpenIndex $found.ParentOpenIndex
    $edits = @()

    $delStart = $m.KeyStart
    $delEnd   = $m.ValueEnd
    $ownComma = $m.CommaOffset

    # Its own comma, when that comma is on the same line and nothing but
    # whitespace separates them, folds into the one span.
    if ($ownComma -ge 0 -and (Test-JsoncRangeBlank -Text $Text -Start $delEnd -End $ownComma)) {
        $delEnd = $ownComma + 1
        $ownComma = -1
    }

    # No comma of its own: the previous member's separator is now dangling.
    if ($m.CommaOffset -lt 0) {
        $prev = $null
        foreach ($x in $members) { if ($x.Index -eq ($m.Index - 1)) { $prev = $x } }
        if ($prev -and $prev.CommaOffset -ge 0) {
            $edits += @{ Start = $prev.CommaOffset; Length = 1; Text = '' }
        }
    } elseif ($ownComma -ge 0) {
        $edits += @{ Start = $ownComma; Length = 1; Text = '' }
    }

    # Whole-line removal, but only when the line held nothing else.
    $line = Get-JsoncLineBound -Text $Text -Offset $delStart
    $endLine = Get-JsoncLineBound -Text $Text -Offset ([Math]::Max($delStart, $delEnd - 1))
    if ($line.Start -eq $endLine.Start -and
        (Test-JsoncRangeBlank -Text $Text -Start $line.Start -End $delStart) -and
        (Test-JsoncRangeBlank -Text $Text -Start $delEnd -End $line.ContentEnd)) {
        $delStart = $line.Start
        $delEnd   = $line.End
    } else {
        # Staying on a shared line: take the spacing that belonged to the
        # separator too, or '{ "a": 1, "b": 2 }' loses a member and keeps its
        # gap. Which side depends on which comma went: a member with its own
        # comma leaves a hole after it, a last member leaves one before it.
        # Spaces and tabs only -- never across a line break, and never a
        # comment, which is not whitespace.
        if ($m.CommaOffset -ge 0) {
            while ($delEnd -lt $Text.Length -and ($Text[$delEnd] -eq ' ' -or $Text[$delEnd] -eq "`t")) { $delEnd++ }
        } else {
            while ($delStart -gt 0 -and ($Text[$delStart - 1] -eq ' ' -or $Text[$delStart - 1] -eq "`t")) { $delStart-- }
        }
    }

    $edits += @{ Start = $delStart; Length = ($delEnd - $delStart); Text = '' }
    $new = Invoke-JsoncSplice -Text $Text -Edits $edits
    # No read-back here: with duplicate keys, removing the last one rightly
    # makes an earlier one visible.
    if (-not (Test-JsoncCommentsIntact -Before $Text -After $new -BeforeTokens $tokens)) {
        return @{ Text = $Text; Changed = $false; Status = 'commentchanged' }
    }
    return @{ Text = $new; Changed = $true; Status = 'removed' }
}
